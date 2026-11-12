import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/catalog.dart';
import '../domain/delivery.dart';
import '../domain/places.dart';
import '../domain/quick_items.dart';
import '../domain/reach.dart';
import '../domain/towns.dart';
import '../services/google_account.dart';
import '../services/usage.dart';
import 'store_consent.dart';
import '../services/localization.dart';
import '../services/notifications.dart';
import '../services/server_clock.dart';

// Store's upload methods and vendor/complaint RPC-wrapper methods live in
// their own extension files (zero call-site change — an extension method
// calls identically to an instance method) — exported so every existing
// `import '...store.dart'` keeps seeing `store.upload(...)`,
// `store.registerVendor(...)` etc. exactly as before this split.
export 'store_consent.dart';
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
    // Services are not products: they have no viewer records.
    if (!live || uid == null || entry.text('kind') == 'service') return;
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
      // What the customer typed as their address: for delivery only, never shown as their place.
      address = '',
      // The customer's AREA (lib/domain/area_names.dart): the name everyone calls the part of town they are in, e.g. "Kancharapalem".
      // Shown, through [placeName], in the location box, the greeting and "Today's ... Offers". '' until it is known.
      area = '',
      // The customer's town (e.g. "Narsipatnam"): the area's fallback name, and the town in the usage reports. What the customer sees
      // is decided by distance only (lib/domain/reach.dart), never by the town.
      town = '',
      // ...and the district/state of the place, for the reports. '' when unknown.
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
  /// Which app this is: 'user' (customers), 'vendor' (vendors and service providers), 'staff', or 'admin' (the admin panel). Each
  /// app signs in with the email's OWN login for its role (functions/role-logins.js): the person uses the same email (and Google
  /// account) everywhere, and gets a separate account, with its own ID, records and block, in each app.
  String appRole = 'user';

  /// The roles this app signs in as. The vendor app holds both the vendor and the service-provider login of an email.
  List<String> get appRoles => switch (appRole) {
    'vendor' => const ['vendor', 'provider'],
    'staff' => const ['staff'],
    'admin' => const ['admin'],
    _ => const ['user'],
  };

  /// The role of the signed-in login ('user', 'vendor', 'provider', 'staff' or 'admin'); '' when nobody is signed in to this app.
  String sessionRole = '';

  /// The email the signed-in login belongs to (a role login has no email of its own in Firebase Auth).
  String sessionEmail = '';
  String? _sessionUid;

  /// The last email that signed in on this phone: the email-code field starts with it.
  String lastSignInEmail = '';

  /// Vendor app only: the email is proven, and the person chooses Vendor or Service provider now.
  bool choosingVendorRole = false;

  /// The role a sign-in was refused for because it is blocked ([roleBlock] says so); null otherwise.
  String? blockedRole;

  /// Agreement to the Terms & Conditions and the Privacy Policy (store_consent.dart). Only the customer, vendor and staff apps ask for it.
  bool requiresConsent = false;

  /// A signed-in person has not agreed to the current version yet: the agreement screen shows.
  bool consentNeeded = false;

  /// This phone has already had an agreement saved, so the sign-in screen does not show the tick box again.
  bool deviceConsented = false;

  /// The person continued on the sign-in screen, under "By continuing, you agree to ...": the agreement is saved right after sign-in.
  bool pendingConsent = false;

  /// The sign-in screen shows the agreement sentence (nobody has agreed on this phone yet).
  bool get asksConsentBeforeSignIn => requiresConsent && !deviceConsented;

  /// The sign-in screen offers the 6-digit email code. Google always comes first: the code is offered only once Google did not work,
  /// is not possible on this device, or the person closed the Google sheet without choosing an account. Hidden again after Log out.
  bool emailCodeOffered = false;

  /// Offers the email code on the sign-in screen (Google did not work or was closed).
  void offerEmailCode() {
    if (emailCodeOffered) return;
    emailCodeOffered = true;
    notifyListeners();
  }

  /// The Google sheet has already opened by itself in this run of the app (or the person just logged out), so it does not again.
  bool _autoGoogleDone = false;

  /// The customer app opened its sign-in sheet by itself once on this phone (the first open after install); never again after that.
  bool _firstOpenOffered = false;

  /// The sign-in screen may open the Google sheet by itself: live, nobody signed in, and not yet in this run of the app.
  bool get opensGoogleByItself => live && user == null && !_autoGoogleDone;

  /// The customer app's first open after install: its sign-in sheet opens by itself, once (customers may also shop without signing in).
  bool get offersSignInOnFirstOpen => live && appRole == 'user' && user == null && !_firstOpenOffered && !_autoGoogleDone;

  /// The sign-in screen opened the Google sheet by itself; it does not do so again in this run.
  void googleOpenedByItself() => _autoGoogleDone = true;

  /// The customer app's first-open sign-in sheet was shown; remembered on this phone.
  Future<void> firstOpenSignInShown() async {
    _firstOpenOffered = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('firstOpenSignInShown', true);
  }

  /// The agreement screen covers the app: signed in, and no saved agreement for the current version.
  bool get showsConsentScreen => live && requiresConsent && user != null && consentNeeded;

  /// Lets the consent extension (store_consent.dart) tell the screens that the agreement state changed.
  void consentChanged() => notifyListeners();

  /// Why the last sign-in could not finish (that role is blocked, or no connection); shown on the login screen, null otherwise.
  String? roleBlock;

  /// The signed-in login of this app: its role login once entered, or (customer app) the email's own login while its email waits for
  /// verification. The email's own verified login is never "signed in" here: it only proves the email, and the app swaps it for its
  /// role login straight away.
  User? get user {
    if (!live) return null;
    final current = FirebaseAuth.instance.currentUser;
    if (current == null) return null;
    if (sessionRole.isNotEmpty && current.uid == _sessionUid) return current;
    if (current.email != null && !current.emailVerified) return current;
    return null;
  }

  /// The signed-in person's email is proven (always true for a role login).
  bool get emailConfirmed => sessionRole.isNotEmpty || (user?.emailVerified ?? false);

  /// The signed-in person's email, for display.
  String get signedInEmail => sessionEmail.isNotEmpty ? sessionEmail : (user?.email ?? '');
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
      // (a sub office such as Rajampet of pincode 503110 belongs to the town Kamareddy: its own name counts too)
      final sameTown = byPin != null &&
          (byPin.town.toLowerCase() == nextTown.toLowerCase() || byPin.name.toLowerCase() == nextTown.toLowerCase());
      final place = sameTown ? byPin : index.townNamed(nextTown);
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

  /// Where the customer is, by name (town, district, state).
  CustomerPlace get place =>
      CustomerPlace(town: town, district: district, state: state);

  /// The ONE name of the customer's place, shown everywhere (location box, greeting, "Today's ... Offers"): the area, else the
  /// town; '' while neither is known. Never the typed address.
  String get placeName => area.isNotEmpty ? area : town;

  /// The customer's point is known (GPS or a place chosen by hand): what they see is measured from it.
  bool get located => latitude != null && longitude != null && !(latitude == 0 && longitude == 0);

  /// The customer has a place: a point, or at least a name or pincode still to be turned into one.
  bool get hasPlace => located || !place.isEmpty || pincode.isNotEmpty;

  /// The admin's one km (Settings > Business Profile): customers see the shops, products, services, offers and ads within it.
  double get reachKm => reachKmOf(business);

  /// The ids of the shops within [reachKm] of the customer (none until the customer's point is known).
  Set<String> shopsInReach() => shopIdsWithin(visible('shops'), located ? latitude : null, located ? longitude : null, reachKm);

  /// Only the demo (no Firebase: the previews and the tests) with no place chosen yet shows the whole catalogue, offers and ads,
  /// like the admin's preview. The real app and website never do: there nothing shows until the customer's place is known.
  bool get showsEverything => !live && !located;

  /// [item]'s shop is within reach of the customer ([linkedShopId]); an item without a shop never is.
  bool reaches(Entry item) => showsEverything || shopsInReach().contains(linkedShopId(item));
  Entry get business =>
      entries('settings').where((e) => e.id == 'business').firstOrNull ??
      const Entry('business', {'name': 'Local Market', 'radiusKm': 10});
  List<Entry> entries(String collection) =>
      List<Entry>.from(catalog[collection] ?? [])
        ..sort((a, b) => a.number('order').compareTo(b.number('order')));
  // Start / end times are decided by the server's clock, never the phone's (lib/services/server_clock.dart).
  List<Entry> visible(String collection) =>
      entries(collection).where((e) => e.visibleAt(ServerClock.now())).toList();
  /// The town a product is sold in: its own, else its shop's (older products have no town of their own).
  String productTown(Entry product) {
    final own = product.text('town');
    if (own.isNotEmpty) return own;
    final shop = entries('shops').where((s) => s.id == product.text('shopId')).firstOrNull;
    return shop?.text('town') ?? '';
  }

  /// [items] of the shops within reach of the customer (distance only, lib/domain/reach.dart): an item of a farther shop, of a shop
  /// with no saved location, or with no shop at all is hidden, and so is everything while the customer's place is not known yet.
  /// [all] (the admin preview) shows every item.
  List<Entry> _inReach(List<Entry> items, bool all) {
    if (all || showsEverything) return items;
    final shops = shopsInReach();
    return items.where((p) => shops.contains(p.text('shopId'))).toList();
  }

  /// Visible products of the shops within reach. Services are not products: they live in their own collection
  /// (see [visibleServices]), and a service record that is still in products is never listed here.
  List<Entry> visibleProducts({bool all = false}) => _inReach(
    visible('products').where((e) => e.text('kind') != 'service' && inSearchAt(e, ServerClock.now())).toList(),
    all,
  );

  /// Visible service listings (the services collection, without the service-type records) of the shops within reach.
  List<Entry> visibleServices({bool all = false}) =>
      _inReach(visible('services').where((e) => e.text('kind') != 'serviceType').toList(), all);

  /// The fixed service types (Plumber, Electrician, ...) stored in the services collection, in their own order.
  List<Entry> serviceTypes() => visible('services').where((e) => e.text('kind') == 'serviceType').toList();

  Entry? product(String id) =>
      entries('products').where((e) => e.id == id).firstOrNull;
  Entry? service(String id) =>
      entries('services').where((e) => e.id == id && e.text('kind') != 'serviceType').firstOrNull;

  /// A product or a service by id (the bag, the wishlist and links hold either).
  Entry? item(String id) => product(id) ?? service(id);
  double get total => cart.entries.fold(
    0,
    (subtotal, line) =>
        subtotal + (item(line.key)?.price(pincode) ?? 0) * line.value,
  );
  /// The delivery charge of each shop in the bag, from the place the customer chose. A client-side estimate for display only; placeOrder
  /// works it out again on the server, from the customer's real position, when the order request is sent. The admin alone sets the
  /// rules (settings/business.deliveryFeeTiers, freeDeliveryAbove and a shop's freeDelivery), and the vendor is paid the charge directly.
  List<DeliveryPart> get deliveryParts {
    final subtotals = <String, double>{};
    for (final line in cart.entries) {
      final entry = item(line.key);
      final shopId = entry?.text('shopId') ?? '';
      if (entry == null || shopId.isEmpty) continue;
      subtotals[shopId] = (subtotals[shopId] ?? 0) + entry.price(pincode) * line.value;
    }
    if (subtotals.isEmpty) return const [];
    return buildDeliveryParts(subtotals: subtotals, shops: entries('shops'), business: business, latitude: latitude, longitude: longitude);
  }

  /// The charges that are known (a shop past the last tier shows no charge; the customer settles that with the vendor).
  double get deliveryFee => deliveryParts.fold(0, (running, part) => running + part.fee);

  double get grandTotal => total + deliveryFee;
  int get count => cart.values.fold(0, (a, b) => a + b);
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    if (live) {
      // The website reads its saved login from the browser a moment after the start; without this wait every open would show the
      // sign-in screen first (and, with no connection then, stay signed out). A phone has it at once. Never blocks for long.
      if (kIsWeb) await _savedLoginLoaded();
      // The app opens straight inside: the role of the login this phone is still signed in with is known before the first screen,
      // without waiting for the network (the claims are checked again as soon as Firebase reports the login).
      lastSignInEmail = prefs.getString('lastSignInEmail') ?? '';
      _firstOpenOffered = prefs.getBool('firstOpenSignInShown') ?? false;
      final saved = (prefs.getString('sessionRole') ?? '').split('|');
      final current = FirebaseAuth.instance.currentUser;
      if (saved.length == 3 && current != null && current.uid == saved[0] && appRoles.contains(saved[1])) {
        _sessionUid = saved[0];
        sessionRole = saved[1];
        sessionEmail = saved[2];
      }
    }
    pincode = prefs.getString('pincode') ?? '';
    await loadConsentDevice();
    address = prefs.getString('address') ?? '';
    area = prefs.getString('area') ?? '';
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
          if (u != null && !await _adoptLogin(u)) return;
          if (u == null) {
            if (FirebaseAuth.instance.currentUser != null) return;
            await _setSession(null);
            consentNeeded = false;
          }
          if (u != null && emailConfirmed) await syncConsent();
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
      // The website's One Tap prompt answers here, whenever the person clicks their account (lib/services/google_account.dart).
      if (kIsWeb && appRole != 'admin') {
        _subscriptions.add(googleIdTokens().listen((idToken) => unawaited(_finishGoogleQuietly(idToken))));
      }
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
                  // The Ads collection is optional: if it cannot be read (yet) the site simply keeps its existing ad boxes.
                  if (collection == 'ads') return;
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

  /// Live Quick Add items within the admin's km of the customer's place (distance only), optionally one category. None until the
  /// customer's place is known.
  List<Entry> quickItemsHere({String? categoryId, DateTime? now}) => liveQuickItems(
    catalog['quickItems'] ?? const [],
    now ?? DateTime.now(),
    latitude: located ? latitude : null,
    longitude: located ? longitude : null,
    km: reachKm,
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

  /// Records of a collection the public catalog does not carry (ad view counts: only the admin and the owning vendor may read them),
  /// kept up to date live. In demo mode, the local copy once.
  Stream<List<Entry>> watchEntries(String collection, {String? vendorId}) {
    if (!live) return Stream.value(entries(collection));
    Query<Map<String, dynamic>> query = firestore.collection(collection);
    if (vendorId != null) query = query.where('vendorId', isEqualTo: vendorId);
    return query.snapshots().map((s) => [for (final d in s.docs) Entry(d.id, d.data())]);
  }

  /// The per-day ad statistics from day [from] to day [to] (YYYY-MM-DD, India). A vendor passes [vendorId] to get only their own ads.
  Future<List<Entry>> dailyAdStats(String from, String to, {String? vendorId}) async {
    if (!live) {
      return [for (final e in entries('adStatsDaily')) if (e.text('day').compareTo(from) >= 0 && e.text('day').compareTo(to) <= 0 && (vendorId == null || e.text('vendorId') == vendorId)) e];
    }
    Query<Map<String, dynamic>> query = firestore.collection('adStatsDaily').where('day', isGreaterThanOrEqualTo: from).where('day', isLessThanOrEqualTo: to);
    if (vendorId != null) query = query.where('vendorId', isEqualTo: vendorId);
    final snapshot = await query.get();
    return [for (final d in snapshot.docs) Entry(d.id, d.data())];
  }

  /// The newest counted views and taps of one ad (time, town, device), for the admin to check any number.
  Future<List<Entry>> recentAdViews(String adId, {int limit = 200}) async {
    if (!live) {
      final all = entries('adViews').where((e) => e.text('adId') == adId).toList();
      return all.take(limit).toList();
    }
    final snapshot = await firestore.collection('adViews').where('adId', isEqualTo: adId).orderBy('at', descending: true).limit(limit).get();
    return [for (final d in snapshot.docs) Entry(d.id, d.data())];
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
  /// Changes only the typed address (for delivery): the place, its area and what the customer sees stay as they are.
  Future<void> setDeliveryAddress(String value) async {
    address = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('address', value);
    notifyListeners();
  }

  Future<void> setLocation(
    String pin,
    String value, {
    double? lat,
    double? lng,
    String? town,
    String? district,
    String? state,
    String? area,
    bool followGps = false,
  }) async {
    followsGps = followGps;
    // A refresh that leaves the pincode/address untouched (e.g. the on-open GPS
    // coordinate refresh) must not forget a town the customer already picked.
    final unchanged = town == null && pin == pincode && value == address;
    // The area goes with the place it was worked out for (lib/services/area_lookup.dart): kept only when nothing else changes.
    this.area = area ?? (unchanged && lat == latitude && lng == longitude ? this.area : '');
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
    // Usage analytics: a newly chosen town.
    if (nextTown.isNotEmpty && townKey(nextTown) != townKey(this.town)) Usage.track('location_change', key: townKey(nextTown), label: nextTown, town: nextTown);
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
    await prefs.setString('area', this.area);
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

  /// The shops within the admin's km of the customer ([reachKm]; a shop's own radius no longer counts). None while the customer's
  /// place is not known.
  List<Entry> nearby() {
    if (showsEverything) return visible('shops');
    final ids = shopsInReach();
    return visible('shops').where((s) => ids.contains(s.id)).toList();
  }
  void add(Entry entry, [int quantity = 1]) {
    final next = (cart[entry.id] ?? 0) + quantity;
    if (next <= 0) {
      cart.remove(entry.id);
    } else if (next <= entry.number('stock', 0)) {
      cart[entry.id] = next;
    }
    notifyListeners();
  }

  /// Sends the order request to the shops. [phone] is the number the vendor can call and ([latitude], [longitude]) the customer's place,
  /// for each shop's delivery charge. The phone number is kept on this order only, not in the account.
  Future<String> checkout(String deliveryAddress, String requestId, {String paymentMethod = 'direct_vendor', required String phone, required double latitude, required double longitude}) async {
    if (!live) {
      throw StateError(
        'Demo checkout preview only. Connect Firebase to place orders.',
      );
    }
    if (user == null) {
      throw StateError('Please sign in first.');
    }
    if (!emailConfirmed) {
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
          'phone': phone,
          'latitude': latitude,
          'longitude': longitude,
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

  /// Password sign-in (the customer app's form and the admin panel): proves the email, then enters this app's role login.
  Future<void> login(String email, String password) async {
    roleBlock = null;
    final signedIn = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (signedIn.user?.emailVerified == true) await enterAppRole();
  }

  /// Who [u] is, from its claims. True when [u] is this app's own role login (the session is set); false when it is the email's own
  /// login (a verified one is swapped for the role login right away, an unverified one waits for the email check) or another app's
  /// login (signed out: on the web the shop and the admin panel share the browser).
  Future<bool> _adoptLogin(User u) async {
    // A late event for a login that has already been swapped for another one.
    if (FirebaseAuth.instance.currentUser?.uid != u.uid) return false;
    Map<String, dynamic> claims;
    try {
      claims = (await u.getIdTokenResult()).claims ?? const {};
    } catch (_) {
      // No connection to refresh the token: keep the session this phone already knows for this login.
      return sessionRole.isNotEmpty && _sessionUid == u.uid;
    }
    if (FirebaseAuth.instance.currentUser?.uid != u.uid) return false;
    final role = claims['role']?.toString() ?? '';
    if (role.isEmpty) {
      await _setSession(null);
      if (u.emailVerified) unawaited(_enterRoleQuietly());
      notifyListeners();
      return false;
    }
    if (!appRoles.contains(role)) {
      await _setSession(null);
      await FirebaseAuth.instance.signOut();
      notifyListeners();
      return false;
    }
    await _setSession(u.uid, role: role, email: claims['loginEmail']?.toString() ?? '', isAdmin: role == 'admin' && claims['admin'] == true);
    return true;
  }

  /// Remembers (or, with a null [uid], forgets) the signed-in role login, so the app opens straight inside next time.
  Future<void> _setSession(String? uid, {String role = '', String email = '', bool isAdmin = false}) async {
    _sessionUid = uid;
    sessionRole = uid == null ? '' : role;
    sessionEmail = uid == null ? '' : email;
    admin = uid != null && isAdmin;
    final prefs = await SharedPreferences.getInstance();
    if (uid == null) {
      await prefs.remove('sessionRole');
      return;
    }
    roleBlock = null;
    blockedRole = null;
    choosingVendorRole = false;
    await prefs.setString('sessionRole', '$uid|$role|$email');
    if (email.isNotEmpty) {
      lastSignInEmail = email;
      await prefs.setString('lastSignInEmail', email);
    }
    if (appRoles.length > 1) await prefs.setString('vendorAppRole', role);
  }

  Future<void>? _entering;

  /// Swaps the email's own (proven) login for this app's login in [role] (the app's own role, or in the vendor app the remembered
  /// choice): functions/role-logins.js enterRole makes it the first time. Throws, with [roleBlock] set, when that role is blocked or
  /// the server cannot be reached.
  Future<void> enterAppRole([String? role]) => _entering ??= _enterRole(role).whenComplete(() => _entering = null);

  Future<void> _enterRoleQuietly() async {
    try {
      await enterAppRole();
    } catch (_) {
      /* roleBlock already says why; the sign-in screen shows it. */
    }
  }

  Future<void> _enterRole(String? wanted) async {
    final role = wanted ?? await _defaultRole();
    if (role == null) {
      // Vendor app, first sign-in: "Vendor or Service provider?" decides.
      choosingVendorRole = true;
      notifyListeners();
      return;
    }
    try {
      final result = await call('enterRole', {'role': role});
      await FirebaseAuth.instance.signInWithCustomToken(result['token'] as String);
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) await _adoptLogin(u);
    } catch (e) {
      final refused = e is FirebaseFunctionsException && e.code == 'permission-denied';
      roleBlock = e is FirebaseFunctionsException && (e.message ?? '').isNotEmpty
          ? e.message
          : 'Could not finish signing in. Check your connection and try again.';
      final details = e is FirebaseFunctionsException ? e.details : null;
      blockedRole = details is Map ? details['blocked']?.toString() : null;
      if (appRoles.length > 1) {
        // The vendor app offers the email's other login (Vendor or Service provider), which a block on this one never touches.
        choosingVendorRole = true;
      } else if (refused) {
        await _forgetGoogle();
        await FirebaseAuth.instance.signOut();
      }
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  Future<String?> _defaultRole() async {
    if (appRoles.length == 1) return appRoles.first;
    final saved = (await SharedPreferences.getInstance()).getString('vendorAppRole');
    return appRoles.contains(saved) ? saved : null;
  }

  /// Vendor app: the answer to "Vendor or Service provider?" after the first sign-in (remembered on this phone).
  Future<void> chooseVendorRole(String role) async {
    choosingVendorRole = false;
    roleBlock = null;
    blockedRole = null;
    notifyListeners();
    await enterAppRole(role);
  }

  /// Vendor app: moves to the same email's other login (Vendor <-> Service provider), each with its own ID, records and block.
  Future<void> switchVendorRole(String to) async {
    if (sessionRole == to) return;
    final result = await call('switchRole', {'to': to});
    await FirebaseAuth.instance.signInWithCustomToken(result['token'] as String);
    final u = FirebaseAuth.instance.currentUser;
    if (u != null) await _adoptLogin(u);
    notifyListeners();
  }

  /// Signs Google out on this phone or in this browser (lib/services/google_account.dart).
  Future<void> _forgetGoogle() async {
    if (kIsWeb && appRole == 'admin') return;
    await forgetGoogleAccount();
  }

  /// Waits (at most a few seconds) until Firebase has read the website's saved login from the browser.
  Future<void> _savedLoginLoaded() async {
    try {
      await FirebaseAuth.instance.authStateChanges().first.timeout(const Duration(seconds: 4));
    } catch (_) {
      /* Slow or no storage: the app starts and the login, if any, follows a moment later. */
    }
  }

  /// Main sign-in: "Continue with Google", one tap on an account already on the phone (its email shown), no typing; Google has already
  /// verified the email. Signing in and registering are the same step: the app's own account for this email is made on the first
  /// sign-in. [automatic] is the sheet that opens by itself: only the sheet, never Google's full picker; on the website, the One Tap
  /// prompt, whose answer comes later through [googleIdTokens].
  /// Returns true when signed in, false when the person closed Google without choosing (or there is nothing to show), and null while
  /// the website's One Tap prompt is waiting for a click.
  Future<bool?> signInWithGoogle({bool automatic = false}) async {
    roleBlock = null;
    try {
      if (kIsWeb) {
        if (automatic) {
          await showWebOneTap();
          return null;
        }
        await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      } else {
        final account = await pickGoogleAccount(sheetOnly: automatic);
        if (account == null) return false;
        final idToken = account.authentication.idToken;
        if (idToken == null) throw StateError('Google did not send a sign-in token. Please try again, or use an email code.');
        await FirebaseAuth.instance.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      }
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user' || e.code == 'cancelled-popup-request') return false;
      rethrow;
    }
    await enterAppRole();
    return true;
  }

  /// The website: the person clicked their account in the One Tap prompt, which only opens on a sign-in screen, under the agreement
  /// sentence ("By continuing, you agree to ...").
  Future<void> _finishGoogleQuietly(String idToken) async {
    if (sessionRole.isNotEmpty) return;
    try {
      roleBlock = null;
      if (asksConsentBeforeSignIn) pendingConsent = true;
      await FirebaseAuth.instance.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      await enterAppRole();
    } catch (_) {
      // roleBlock (when set) says why on the sign-in screen; Google did not work, so the email code is offered.
      emailCodeOffered = true;
      notifyListeners();
    }
  }

  /// Backup sign-in: the server emails a 6-digit code to [email].
  Future<void> requestEmailCode(String email) async {
    await call('requestEmailLoginCode', {'email': email});
  }

  /// Checks the code the person typed; the server marks the email verified and hands back a sign-in token for the email's own login,
  /// which is then swapped for this app's role login.
  Future<void> verifyEmailCode(String email, String code) async {
    roleBlock = null;
    final result = await call('verifyEmailLoginCode', {'email': email, 'code': code});
    await FirebaseAuth.instance.signInWithCustomToken(result['token'] as String);
    await enterAppRole();
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

  /// After the person opened the verification link: once the email is verified, the app's role login is entered.
  Future<bool> refreshEmailVerification() async {
    if (sessionRole.isNotEmpty) {
      notifyListeners();
      return true;
    }
    await FirebaseAuth.instance.currentUser?.reload();
    final current = FirebaseAuth.instance.currentUser;
    if (current == null || !current.emailVerified) {
      notifyListeners();
      return false;
    }
    await current.getIdToken(true);
    await enterAppRole();
    notifyListeners();
    return sessionRole.isNotEmpty;
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
    if (live && emailConfirmed) await notifications.disable();
    await _forgetGoogle();
    await FirebaseAuth.instance.signOut();
    await _setSession(null);
    choosingVendorRole = false;
    // Signed out on purpose: the sign-in screen shows Google first again, and does not pop the Google sheet up by itself.
    emailCodeOffered = false;
    _autoGoogleDone = true;
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
