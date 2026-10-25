import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'usage.dart';

/// Starts usage analytics in an app (customer, vendor, staff or admin) once Firebase is connected: a random id for the device
/// (the same one the visit and ad counting use), and batches sent to the `trackUsage` callable. Never throws.
Future<void> startUsage({required String app}) async {
  if (Usage.instance != null) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('visitorId') ?? '';
    if (!RegExp(r'^[a-zA-Z0-9-]{16,64}$').hasMatch(id)) {
      final random = Random.secure();
      id = List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
      await prefs.setString('visitorId', id);
    }
    Usage.instance = Usage(
      app: app,
      deviceId: id,
      platform: kIsWeb ? 'web' : 'android',
      transport: (batch) => FirebaseFunctions.instance.httpsCallable('trackUsage').call(batch),
    )..touch();
    // Signing in says who is active now (the admin's inactive-accounts list).
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) Usage.instance?.touch();
    });
  } catch (_) {
    /* Usage counting must never prevent the app from starting. */
  }
}
