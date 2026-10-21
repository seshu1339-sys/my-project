import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/catalog.dart';
import '../domain/places.dart';
import '../domain/quick_items.dart';
import '../domain/towns.dart';
import '../services/localization.dart';
import '../services/notifications.dart';

// Store's upload methods and vendor/complaint RPC-wrapper methods live in
// their own extension files (zero call-site change — an extension method
// calls identically to an instance method) — exported so every existing
// `import '...store.dart'` keeps seeing `store.upload(...)`,
// `store.registerVendor(...)` etc. exactly as before this split.
export 'store_uploads.dart';
export 'store_vendor_actions.dart';

class Store extends ChangeNotifier {
  Store({this.live = false, this.database});
  final bool live;
  final FirebaseFirestore? database;
  FirebaseFirestore get firestore => database ?? FirebaseFirestore.instance;
  late final notifications = CustomerNotifications(firestore);
  final Map<String, DateTime> _lastViewCounted = {};

  /// Product interest: which signed-in customer viewed which product, and how
  /// many times. A quick re-open of the same product is not counted again.
  Future<void> trackItemView(Entry entry) async {
    final uid = user?.uid;
    if (!live || uid == null) return;
    final now = DateTime.now();
    final last = _lastViewCounted['$uid:${entry.id}'];
    if (last != null && now.difference(last) < const Duration(seconds: 30)) return;
    _lastViewCounted['$uid:${entry.id}'] = now;
    try {
      await firestore
          .collection('products')
          .doc(entry.id)
          .collection('viewers')
          .doc(uid)
          .set({
            'pincode': pincode,
            'lastViewedAt': FieldValue.serverTimestamp(),
            'viewCount': FieldValue.increment(1),
          }, SetOptions(merge: true));
    } catch (_) {
      /* Analytics must never prevent browsing. */
    }
  }

  // A safety rail, not real pagination: caps each catalog collection's
  // real-time listener so one runaway collection cannot blow up client
  // reads/costs. A business with more items than this needs a paginated
  // or server-searched catalog, which is a separate, larger change.
  static const _catalogPageLimit = 2000;
  Map<String, List<Entry>> catalog = {};
  final Set<String> truncatedCollections = {};
  String get catalogWarning => truncatedCollections.isEmpty
      ? ''
      : 'Showing the first $_catalogPageLimit items in '
            '${truncatedCollections.join(', ')}.';
  final Map<String, int> cart = {};
  final Set<String> wishlist = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  String pincode = '',
      address = '',
      // The customer's town (e.g. "Narsipatnam"), which decides which
      // location-tagged offers/ads they see and names the offers ticker.
      // '' until a location is chosen.
      town = '',
      // ...and the district/state of the place they picked, so an offer can
      // target a whole district or state. '' when unknown.
      district = '',
      state = '',
      profileName = '',
      language = 'en',
      error = '';
  String paymentBrand = '', paymentLast4 = '';
  // True when the customer chose "Use my location": the app then follows their phone's
  // position (and moves the town along with it when they travel). A town or pincode
  // picked by hand is never moved by GPS.
  bool followsGps = false;
  double? latitude, longitude;
  bool admin = false, ready = false;
  String? pendingEmailLink;
  String emailForSignInLink = '';
  User? get user => live ? FirebaseAuth.instance.currentUser : null;
  /// Completes the stored place from the places directory: the town (and its
  /// district/state) of a typed pincode, or the district/state of a town that
  /// came from a place-name search. Only ever fills what is missing, never
  /// replaces what the customer picked. Returns whether anything changed.
  Future<bool> completePlace(PlacesIndex index) async {
    var nextTown = town, nextDistrict = district, nextState = state;
    if (nextTown.isEmpty && pincode.isNotEmpty) {
      final place = index.byPincode(pincode);
      if (place != null) {
        nextTown = place.town;
        nextDistrict = place.district;
        nextState = place.state;
      }
    } else if (nextTown.isNotEmpty && nextDistrict.isEmpty) {
      // The typed pincode settles which town of that name is meant, when it agrees.
      final byPin = pincode.isNotEmpty ? index.byPincode(pincode) : null;
      final place = byPin != null && byPin.town.toLowerCase() == nextTown.toLowerCase()
          ? byPin
          : index.townNamed(nextTown);
      if (place != null) {
        nextDistrict = place.district;
        nextState = place.state;
      }
    }
    if (nextTown == town && nextDistrict == district && nextState == state) {
      return false;
    }
    town = nextTown;
    district = nextDistrict;
    state = nextState;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('town', town);
    await prefs.setString('district', district);
    await prefs.setString('state', state);
    notifyListeners();
    return true;
  }

  /// Where the customer is, as offers are matched against it.
  CustomerPlace get place =>
      CustomerPlace(town: town, district: district, state: state);
  bool get hasPlace => !place.isEmpty;
  Entry get business =>
      entries('settings').where((e) => e.id == 'business').firstOrNull ??
      const Entry('business', {'name': 'Local Market', 'radiusKm': 10});
  List<Entry> entries(String collection) =>
      List<Entry>.from(catalog[collection] ?? [])
        ..sort((a, b) => a.number('order').compareTo(b.number('order')));
  List<Entry> visible(String collection) =>
      entries(collection).where((e) => e.visibleAt(DateTime.now())).toList();
  /// The town a product is sold in: its own, else its shop's (older products have no town of their own).
  String productTown(Entry product) {
    final own = product.text('town');
    if (own.isNotEmpty) return own;
    final shop = entries('shops').where((s) => s.id == product.text('shopId')).firstOrNull;
    return shop?.text('town') ?? '';
  }

  /// Visible products and services for the customer's chosen town: items of other towns are hidden.
  /// Nothing is hidden while no town is chosen, and an item with no known town shows everywhere.
  /// [all] (the admin preview) ignores the town.
  List<Entry> visibleProducts({bool all = false}) {
    final items = visible('products');
    if (all || town.isEmpty) return items;
    final mine = town.trim().toLowerCase();
    return items.where((p) {
      final there = productTown(p).trim().toLowerCase();
      return there.isEmpty || there == mine;
    }).toList();
  }

  Entry? product(String id) =>
      entries('products').where((e) => e.id == id).firstOrNull;
  double get total => cart.entries.fold(
    0,
    (subtotal, line) =>
        subtotal + (product(line.key)?.price(pincode) ?? 0) * line.value,
  );
  // Client-side estimate for display only; placeOrder recomputes this
  // authoritatively from settings/business at checkout time.
  double get deliveryFee {
    final fee = business.number('deliveryFee', 0);
    if (fee <= 0) return 0;
    final threshold = business.number('freeDeliveryAbove', 0);
    if (threshold > 0 && total >= threshold) return 0;
    return fee;
  }

  double get grandTotal => total + deliveryFee;
  int get count => cart.values.fold(0, (a, b) => a + b);
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    if (live) {
      emailForSignInLink = prefs.getString('emailForSignInLink') ?? '';
      if (FirebaseAuth.instance.isSignInWithEmailLink(Uri.base.toString())) {
        pendingEmailLink = Uri.base.toString();
      }
    }
    pincode = prefs.getString('pincode') ?? '';
    address = prefs.getString('address') ?? '';
    town = prefs.getString('town') ?? '';
    district = prefs.getString('district') ?? '';
    state = prefs.getString('state') ?? '';
    followsGps = prefs.getBool('followsGps') ?? false;
    latitude = prefs.getDouble('latitude');
    longitude = prefs.getDouble('longitude');
    final savedLanguage = prefs.getString('language');
    if (savedLanguage != null) {
      language = savedLanguage;
    } else {
      try {
        language = AppLocale.detect(
          WidgetsBinding.instance.platformDispatcher.locales,
        );
      } catch (_) {
        language = 'en';
      }
    }
    paymentBrand = prefs.getString('paymentBrand') ?? '';
    paymentLast4 = prefs.getString('paymentLast4') ?? '';
    wishlist.addAll(prefs.getStringList('wishlist') ?? const []);
    if (!live) {
      final saved = prefs.getString('demoCatalog');
      catalog = saved == null
          ? demoCatalog()
          : (jsonDecode(saved) as Map<String, dynamic>).map(
              (k, v) => MapEntry(
                k,
                (v as List)
                    .map(
                      (e) => Entry(
                        e['id'] as String,
                        Map<String, dynamic>.from(e['data']),
                      ),
                    )
                    .toList(),
              ),
            );
    } else {
      _subscriptions.add(
        FirebaseAuth.instance.idTokenChanges().listen((u) async {
          admin =
              u != null &&
              u.emailVerified &&
              (await u.getIdTokenResult()).claims?['admin'] == true;
          profileName = u?.displayName ?? '';
          if (u != null) {
            try {
              final profile = await firestore
                  .collection('users')
                  .doc(u.uid)
                  .get();
              final data = profile.data();
              language = data?['language']?.toString() ?? language;
              paymentBrand = data?['paymentBrand']?.toString() ?? paymentBrand;
              paymentLast4 = data?['paymentLast4']?.toString() ?? paymentLast4;
              final cloudWishlist = data?['wishlist'];
              if (cloudWishlist is List) {
                wishlist.addAll(cloudWishlist.map((e) => e.toString()));
              }
            } catch (_) {
              /* Optional profile preferences must not block sign-in. */
            }
          }
          await notifications.restore(
            pincode: pincode,
            latitude: latitude,
            longitude: longitude,
          );
          notifyListeners();
        }),
      );
      for (final collection in collections) {
        _subscriptions.add(
          firestore
              .collection(collection)
              .limit(_catalogPageLimit)
              .snapshots()
              .listen(
                (snapshot) {
                  catalog[collection] = snapshot.docs
                      .map((d) => Entry(d.id, d.data()))
                      .toList();
                  if (snapshot.docs.length >= _catalogPageLimit) {
                    truncatedCollections.add(collection);
                  } else {
                    truncatedCollections.remove(collection);
                  }
                  notifyListeners();
                },
                onError: (Object e) {
                  error =
                      'Could not load $collection. Check your connection and Firebase permissions.';
                  notifyListeners();
                },
              ),
        );
      }
    }
    if (live) _watchQuickItems();
    ready = true;
    notifyListeners();
  }

  // Customers read only APPROVED quick items (the rules allow nothing else); the clock decides
  // which of those are live.
  void _watchQuickItems() {
    _subscriptions.add(
      firestore
          .collection('quickItems')
          .where('status', isEqualTo: 'approved')
          .limit(_catalogPageLimit)
          .snapshots()
          .listen((snapshot) {
            catalog['quickItems'] = snapshot.docs
                .map((d) => Entry(d.id, d.data()))
                .toList();
            notifyListeners();
          }, onError: (Object _) {
            /* Quick items are optional; browsing must not break without them. */
          }),
    );
  }

  /// Extra places the admin added (optional: staff pick towns from the pincode directory).
  List<Entry> get quickLocations =>
      entries('locations').where((l) => l.active).toList();

  /// Live Quick Add items in the town the customer chose with "Choose your location" (the same
  /// town that decides their offers), optionally one category. None until a town is chosen.
  List<Entry> quickItemsHere({String? categoryId, DateTime? now}) => liveQuickItems(
    catalog['quickItems'] ?? const [],
    now ?? DateTime.now(),
    town: town,
    district: district,
    categoryId: categoryId,
  );

  Future<void> save(String collection, Entry entry) async {
    if (live) {
      await firestore.collection(collection).doc(entry.id).set(entry.data);
    } else {
      catalog.putIfAbsent(collection, () => []);
      catalog[collection]!.removeWhere((e) => e.id == entry.id);
      catalog[collection]!.add(entry);
      await _persistDemo();
      notifyListeners();
    }
  }

  /// Writes ONLY the given fields of an existing document (and deletes the
  /// [remove]d ones), leaving every other field as it is in the database right
  /// now. An admin form must use this rather than [save]: a form built from a
  /// copy loaded earlier would otherwise write that old copy back over fields
  /// changed meanwhile -- stock lowered by an order, a rating added by a review.
  /// If the document no longer exists, [fallback] is saved in full instead.
  Future<void> updateFields(
    String collection,
    String id,
    Map<String, dynamic> changes, {
    Set<String> remove = const {},
    Entry? fallback,
  }) async {
    if (changes.isEmpty && remove.isEmpty) return;
    if (live) {
      final ref = firestore.collection(collection).doc(id);
      try {
        await ref.update({
          ...changes,
          for (final key in remove) key: FieldValue.delete(),
        });
      } on FirebaseException catch (e) {
        if (e.code == 'not-found' && fallback != null) {
          await ref.set(fallback.data);
        } else {
          rethrow;
        }
      }
    } else {
      final current = catalog[collection]?.where((e) => e.id == id).firstOrNull;
      if (current == null) {
        if (fallback != null) await save(collection, fallback);
        return;
      }
      final next = {...current.data, ...changes}..removeWhere((k, _) => remove.contains(k));
      await save(collection, Entry(id, next));
    }
  }

  /// Changes some fields of many existing records at once (bulk edits and order numbers): [changes] maps a record id to the
  /// fields to set. Live, the writes go in batches (each record is written whole or not at all); in the demo, once.
  Future<void> updateMany(String collection, Map<String, Map<String, dynamic>> changes) async {
    final todo = {for (final e in changes.entries) if (e.value.isNotEmpty) e.key: e.value};
    if (todo.isEmpty) return;
    if (live) {
      final ids = todo.keys.toList();
      for (var i = 0; i < ids.length; i += 400) {
        final batch = firestore.batch();
        for (final id in ids.skip(i).take(400)) {
          batch.update(firestore.collection(collection).doc(id), todo[id]!);
        }
        await batch.commit();
      }
    } else {
      final list = catalog[collection];
      if (list == null) return;
      catalog[collection] = [
        for (final e in list)
          if (todo[e.id] case final change?) Entry(e.id, {...e.data, ...change}) else e,
      ];
      await _persistDemo();
      notifyListeners();
    }
  }

  /// A record read from the server itself (not the local copy), to confirm that a write really reached it. Offline, the local copy.
  Future<Map<String, dynamic>?> freshRecord(String collection, String id) async {
    if (!live) return catalog[collection]?.where((e) => e.id == id).firstOrNull?.data;
    final snapshot = await firestore.collection(collection).doc(id).get(const GetOptions(source: Source.server));
    return snapshot.data();
  }

  Future<void> delete(String collection, String id) async {
    if (live) {
      await firestore.collection(collection).doc(id).delete();
    } else {
      catalog[collection]?.removeWhere((entry) => entry.id == id);
      await _persistDemo();
      notifyListeners();
    }
  }

  Future<void> _persistDemo() async =>
      (await SharedPreferences.getInstance()).setString(
        'demoCatalog',
        jsonEncode(
          catalog.map(
            (k, v) => MapEntry(
              k,
              v.map((e) => {'id': e.id, 'data': e.data}).toList(),
            ),
          ),
        ),
      );
  Future<void> setLocation(
    String pin,
    String value, {
    double? lat,
    double? lng,
    String? town,
    String? district,
    String? state,
    bool followGps = false,
  }) async {
    followsGps = followGps;
    // A refresh that leaves the pincode/address untouched (e.g. the on-open GPS
    // coordinate refresh) must not forget a town the customer already picked.
    final unchanged = town == null && pin == pincode && value == address;
    final nextTown = unchanged
        ? this.town
        : resolveTown(
            town: town,
            pincode: pin,
            address: value,
            towns: parseServiceTowns(business.text('serviceTowns')),
          );
    final nextDistrict = unchanged ? this.district : (district ?? '');
    final nextState = unchanged ? this.state : (state ?? '');
    pincode = pin;
    address = value;
    this.town = nextTown;
    this.district = nextDistrict;
    this.state = nextState;
    latitude = lat;
    longitude = lng;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pincode', pin);
    await prefs.setString('address', value);
    await prefs.setString('town', this.town);
    await prefs.setString('district', this.district);
    await prefs.setString('state', this.state);
    await prefs.setBool('followsGps', followsGps);
    if (lat != null && lng != null) {
      await prefs.setDouble('latitude', lat);
      await prefs.setDouble('longitude', lng);
    } else {
      await prefs.remove('latitude');
      await prefs.remove('longitude');
    }
    if (live) {
      unawaited(notifications.updateLocationIfEnabled(pincode: pin, latitude: lat, longitude: lng));
    }
    notifyListeners();
  }

  Future<void> setLanguage(String value) async {
    language = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', value);
    if (live && user != null) {
      await firestore.collection('users').doc(user!.uid).set({
        'language': value,
      }, SetOptions(merge: true));
    }
    notifyListeners();
  }

  Future<void> setPaymentCard(String brand, String last4) async {
    paymentBrand = brand;
    paymentLast4 = last4;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('paymentBrand', brand);
    await prefs.setString('paymentLast4', last4);
    if (live && user != null) {
      await firestore.collection('users').doc(user!.uid).set({
        'paymentBrand': brand,
        'paymentLast4': last4,
      }, SetOptions(merge: true));
    }
    notifyListeners();
  }

  Future<void> removePaymentCard() async {
    paymentBrand = '';
    paymentLast4 = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('paymentBrand');
    await prefs.remove('paymentLast4');
    if (live && user != null) {
      await firestore.collection('users').doc(user!.uid).set({
        'paymentBrand': FieldValue.delete(),
        'paymentLast4': FieldValue.delete(),
      }, SetOptions(merge: true));
    }
    notifyListeners();
  }

  Future<void> toggleWishlist(String productId) async {
    if (!wishlist.add(productId)) {
      wishlist.remove(productId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('wishlist', wishlist.toList());
    if (live && user != null) {
      try {
        await firestore.collection('users').doc(user!.uid).set({
          'wishlist': wishlist.toList(),
        }, SetOptions(merge: true));
      } catch (_) {
        /* Wishlist works offline; cross-device sync is best-effort. */
      }
    }
    notifyListeners();
  }

  List<Entry> nearby() => visible('shops').where((s) {
    if (latitude != null && longitude != null) {
      return distanceKm(
            latitude!,
            longitude!,
            s.number('latitude'),
            s.number('longitude'),
          ) <=
          s.number('radiusKm', business.number('radiusKm', 10));
    }
    return pincode.isNotEmpty && s.text('pincode') == pincode;
  }).toList();
  void add(Entry entry, [int quantity = 1]) {
    final next = (cart[entry.id] ?? 0) + quantity;
    if (next <= 0) {
      cart.remove(entry.id);
    } else if (next <= entry.number('stock', 0)) {
      cart[entry.id] = next;
    }
    notifyListeners();
  }

  Future<String> checkout(String deliveryAddress, String requestId, {String paymentMethod = 'direct_vendor'}) async {
    if (!live) {
      throw StateError(
        'Demo checkout preview only. Connect Firebase to place orders.',
      );
    }
    if (user == null) {
      throw StateError('Please sign in first.');
    }
    if (!user!.emailVerified) {
      throw StateError('Verify your email in Your account before ordering.');
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable('placeOrder')
        .call({
          'items': cart.entries
              .map((e) => {'productId': e.key, 'quantity': e.value})
              .toList(),
          'pincode': pincode,
          'address': deliveryAddress,
          'requestId': requestId,
          'paymentMethod': paymentMethod,
        });
    cart.clear();
    notifyListeners();
    return result.data['orderId'] as String;
  }

  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    if (!live) throw StateError('This action requires a connected Firebase project.');
    final result = await FirebaseFunctions.instance.httpsCallable(name).call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> login(String email, String password) async {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// [continueUrl] lets another app (the vendor site) receive its own link;
  /// the customer site remains the default.
  Future<void> sendSignInLink(String email, {String? continueUrl}) async {
    await FirebaseAuth.instance.setLanguageCode(language);
    await FirebaseAuth.instance.sendSignInLinkToEmail(
      email: email,
      actionCodeSettings: ActionCodeSettings(
        url: continueUrl ?? 'https://e-commerce-app-a3897.web.app/?emailSignIn=1',
        handleCodeInApp: true,
      ),
    );
    // Only remember the address after sending succeeds. Never put it in the URL.
    emailForSignInLink = email;
    await (await SharedPreferences.getInstance()).setString(
      'emailForSignInLink',
      email,
    );
  }

  Future<void> completeSignInLink(String email, String link) async {
    if (!FirebaseAuth.instance.isSignInWithEmailLink(link)) {
      throw StateError('Use the complete sign-in link from your email.');
    }
    await FirebaseAuth.instance.signInWithEmailLink(
      email: email,
      emailLink: link,
    );
    await FirebaseAuth.instance.currentUser!.getIdToken(true);
    pendingEmailLink = null;
    emailForSignInLink = '';
    await (await SharedPreferences.getInstance()).remove('emailForSignInLink');
    notifyListeners();
  }

  Future<void> registerEmail(String email, String password) async {
    await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await sendVerificationEmail();
  }

  Future<void> sendVerificationEmail() async {
    final current = user;
    if (current == null) throw StateError('Sign in first.');
    await FirebaseAuth.instance.setLanguageCode(language);
    await current.sendEmailVerification();
  }

  Future<bool> refreshEmailVerification() async {
    await user?.reload();
    final current = user;
    if (current == null) {
      notifyListeners();
      return false;
    }
    final token = await current.getIdTokenResult(true);
    admin = current.emailVerified && token.claims?['admin'] == true;
    notifyListeners();
    return current.emailVerified;
  }

  Future<void> resetPassword(String email) async {
    await FirebaseAuth.instance.setLanguageCode(language);
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  Future<void> updateProfile(String name) async {
    await user!.updateDisplayName(name);
    await firestore.collection('users').doc(user!.uid).set({
      'name': name,
    }, SetOptions(merge: true));
    profileName = name;
    notifyListeners();
  }

  Future<void> logout() async {
    if (live && user?.emailVerified == true) await notifications.disable();
    await FirebaseAuth.instance.signOut();
    cart.clear();
    // Clear per-account local caches so a different account signing in next
    // on this device never inherits this account's wishlist/payment display
    // (the post-login listener merges cloud data into these, so leftover
    // local state here would otherwise bleed into the next account's profile).
    wishlist.clear();
    paymentBrand = '';
    paymentLast4 = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('wishlist', const []);
    await prefs.remove('paymentBrand');
    await prefs.remove('paymentLast4');
    notifyListeners();
  }

  @override
  void dispose() {
    if (live) notifications.dispose();
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }
}
