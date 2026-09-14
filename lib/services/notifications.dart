import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Registration is explicit: never prompt for notification permission at startup.
class CustomerNotifications {
  CustomerNotifications(this.db);
  final FirebaseFirestore db;
  final _messaging = FirebaseMessaging.instance;
  StreamSubscription<String>? _refresh;
  String? _token;
  String? _uid;

  Future<void> restore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      await _refresh?.cancel();
      if (_uid != null) {
        try {
          await _messaging.deleteToken();
        } catch (_) {
          /* Device may be offline. */
        }
        _uid = null;
        _token = null;
      }
      return;
    }
    try {
      if ((await db.collection('notificationSubscribers').doc(uid).get())
              .data()?['enabled'] !=
          true) {
        return;
      }
      final settings = await _messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        await enable();
      }
    } catch (_) {
      /* Account screen provides an explicit registration retry. */
    }
  }

  Future<void> enable() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in before enabling alerts.');
    if (!await _messaging.isSupported()) {
      throw StateError('Notifications are not supported on this device.');
    }
    const vapid = String.fromEnvironment('FIREBASE_VAPID_KEY');
    if (kIsWeb && vapid.isEmpty) {
      throw StateError('Web push configuration is not available yet.');
    }
    final permission = await _messaging.requestPermission();
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      throw StateError(
        'Allow notifications in your device or browser settings.',
      );
    }
    final token = await _messaging.getToken(vapidKey: kIsWeb ? vapid : null);
    if (token == null) {
      throw StateError('Notification registration is not ready. Try again.');
    }
    _uid = uid;
    await _save(token);
    await db.collection('notificationSubscribers').doc(uid).set({
      'enabled': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _refresh?.cancel();
    _refresh = _messaging.onTokenRefresh.listen((token) async {
      try {
        await _save(token);
      } catch (_) {
        /* Retry by enabling alerts again. */
      }
    });
  }

  Future<void> _save(String token) async {
    if (_uid == null || FirebaseAuth.instance.currentUser?.uid != _uid) return;
    final tokens = db.collection('users').doc(_uid).collection('pushTokens');
    await tokens.doc(token).set({
      'token': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (_token != null && _token != token) await tokens.doc(_token).delete();
    _token = token;
  }

  Future<void> disable() async {
    await _refresh?.cancel();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await db.collection('notificationSubscribers').doc(uid).set({
        'enabled': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    // Delete the device token as well so a shared device cannot receive old alerts.
    try {
      if (await _messaging.isSupported()) await _messaging.deleteToken();
    } catch (_) {
      /* Server-side opt-out above already prevents future sends. */
    }
    if (_uid != null && _token != null) {
      await db
          .collection('users')
          .doc(_uid)
          .collection('pushTokens')
          .doc(_token)
          .delete();
    }
    _token = null;
    _uid = null;
  }

  void dispose() {
    _refresh?.cancel();
  }
}
