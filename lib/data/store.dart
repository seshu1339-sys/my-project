import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/catalog.dart';
import '../services/localization.dart';
import '../services/notifications.dart';

class Store extends ChangeNotifier {
  Store({this.live = false, this.database});
  final bool live;
  final FirebaseFirestore? database;
  FirebaseFirestore get firestore => database ?? FirebaseFirestore.instance;
  late final notifications = CustomerNotifications(firestore);
  Future<void> trackItemView(Entry entry) async {
    final uid = user?.uid;
    if (!live || uid == null) return;
    try {
      await firestore
          .collection('products')
          .doc(entry.id)
          .collection('viewers')
          .doc(uid)
          .set({
            'pincode': pincode,
            'lastViewedAt': FieldValue.serverTimestamp(),
          });
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
      profileName = '',
      language = 'en',
      error = '';
  String paymentBrand = '', paymentLast4 = '';
  double? latitude, longitude;
  bool admin = false, ready = false;
  String? pendingEmailLink;
  String emailForSignInLink = '';
  User? get user => live ? FirebaseAuth.instance.currentUser : null;
  Entry get business =>
      entries('settings').where((e) => e.id == 'business').firstOrNull ??
      const Entry('business', {'name': 'Local Market', 'radiusKm': 10});
  List<Entry> entries(String collection) =>
      List<Entry>.from(catalog[collection] ?? [])
        ..sort((a, b) => a.number('order').compareTo(b.number('order')));
  List<Entry> visible(String collection) =>
      entries(collection).where((e) => e.visibleAt(DateTime.now())).toList();
  Entry? product(String id) =>
      entries('products').where((e) => e.id == id).firstOrNull;
  double get total => cart.entries.fold(
    0,
    (subtotal, line) =>
        subtotal + (product(line.key)?.price(pincode) ?? 0) * line.value,
  );
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
            } catch (_) {
              /* Optional profile preferences must not block sign-in. */
            }
          }
          await notifications.restore();
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
    ready = true;
    notifyListeners();
  }

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
  }) async {
    pincode = pin;
    address = value;
    latitude = lat;
    longitude = lng;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pincode', pin);
    await prefs.setString('address', value);
    if (lat != null && lng != null) {
      await prefs.setDouble('latitude', lat);
      await prefs.setDouble('longitude', lng);
    } else {
      await prefs.remove('latitude');
      await prefs.remove('longitude');
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
      await firestore.collection('users').doc(user!.uid).set({
        'wishlist': wishlist.toList(),
      }, SetOptions(merge: true));
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

  Future<String> checkout(String deliveryAddress, String requestId) async {
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
        });
    cart.clear();
    notifyListeners();
    return result.data['orderId'] as String;
  }

  Future<void> login(String email, String password) async {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> sendSignInLink(String email) async {
    await FirebaseAuth.instance.setLanguageCode(language);
    await FirebaseAuth.instance.sendSignInLinkToEmail(
      email: email,
      actionCodeSettings: ActionCodeSettings(
        url: 'https://e-commerce-app-a3897.web.app/?emailSignIn=1',
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
    notifyListeners();
  }

  Future<String> upload(XFile file) async {
    if (!live) {
      throw StateError(
        'Image uploads require a connected Firebase project. You can use an image URL in the demo.',
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      throw StateError('Choose an image smaller than 5 MB.');
    }
    final ext = file.name.split('.').last.toLowerCase();
    final type = ext == 'png'
        ? 'image/png'
        : ext == 'webp'
        ? 'image/webp'
        : 'image/jpeg';
    final ref = FirebaseStorage.instance.ref(
      'catalog/${DateTime.now().microsecondsSinceEpoch}.$ext',
    );
    await ref.putData(bytes, SettableMetadata(contentType: type));
    return ref.getDownloadURL();
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
