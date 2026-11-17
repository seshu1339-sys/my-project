import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../data/store.dart';

/// "Alerts on this device" for the admin (AI Agent + Health System part 1): this browser / phone gets a push the moment a problem
/// happens many times in a short time (functions/modules/app-problems/alerts.js). The token is saved in `adminPushTokens/{token}` (rules:
/// admin only) and removed when turned off. Firebase Cloud Messaging is free.
class AdminPush {
  AdminPush._();

  static String? _token;

  /// True when this device is saved for alerts (checked once per open of the Health page).
  static Future<bool> isOn(Store store) async {
    if (!store.live) return false;
    try {
      final token = await _tokenOf();
      return token != null && (await store.firestore.collection('adminPushTokens').doc(token).get()).exists;
    } catch (_) {
      return false;
    }
  }

  /// Asks the browser / phone for permission and saves this device. Throws a readable error when it cannot.
  static Future<void> turnOn(Store store) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (!store.live || uid == null) throw StateError('Sign in to the live admin panel first.');
    final messaging = FirebaseMessaging.instance;
    if (!await messaging.isSupported()) throw StateError('This browser cannot show notifications. Try Chrome.');
    final permission = await messaging.requestPermission();
    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      throw StateError('Notifications are blocked for this site. Allow them in the browser settings (the lock icon next to the address).');
    }
    final token = await _tokenOf();
    if (token == null) throw StateError('Could not get a notification token. Try again.');
    await store.firestore.collection('adminPushTokens').doc(token).set({'uid': uid, 'at': FieldValue.serverTimestamp()});
  }

  /// Removes this device from the alerts.
  static Future<void> turnOff(Store store) async {
    final token = await _tokenOf();
    if (token != null) await store.firestore.collection('adminPushTokens').doc(token).delete();
  }

  static Future<String?> _tokenOf() async {
    if (_token != null) return _token;
    const vapid = String.fromEnvironment('FIREBASE_VAPID_KEY');
    if (kIsWeb && vapid.isEmpty) return null;
    _token = await FirebaseMessaging.instance.getToken(vapidKey: kIsWeb ? vapid : null);
    return _token;
  }
}
