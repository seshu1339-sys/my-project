import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/catalog.dart';
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

  Map<String, List<Entry>> catalog = {};
  final Map<String, int> cart = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  String pincode = '', address = '', profileName = '', error = '';
  double? latitude, longitude;
  bool admin = false, ready = false;
  User? get user => live ? FirebaseAuth.instance.currentUser : null;
  Entry get business =>
      entries('settings').where((e) => e.id == 'business').firstOrNull ??
      const Entry('business', {'name': 'Neighbourly', 'radiusKm': 10});
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
    pincode = prefs.getString('pincode') ?? '';
    address = prefs.getString('address') ?? '';
    latitude = prefs.getDouble('latitude');
    longitude = prefs.getDouble('longitude');
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
              (await u.getIdTokenResult()).claims?['admin'] == true;
          profileName = u?.displayName ?? '';
          await notifications.restore();
          notifyListeners();
        }),
      );
      for (final collection in collections) {
        _subscriptions.add(
          firestore
              .collection(collection)
              .snapshots()
              .listen(
                (snapshot) {
                  catalog[collection] = snapshot.docs
                      .map((d) => Entry(d.id, d.data()))
                      .toList();
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

  Future<void> login(String phone, String pin) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('pinLogin')
        .call({'phone': phone, 'pin': pin});
    await FirebaseAuth.instance.signInWithCustomToken(
      result.data['token'] as String,
    );
  }

  Future<void> setPin(String pin) async {
    await FirebaseFunctions.instance.httpsCallable('setPin').call({'pin': pin});
    // Reset revokes old sessions. Start a fresh custom-token session with the new PIN.
    await FirebaseAuth.instance.signOut();
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
    if (live) await notifications.disable();
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
