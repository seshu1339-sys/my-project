import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// The device's current position, asking for location permission first.
///
/// A fresh install has not been granted permission, so calling
/// [Geolocator.getCurrentPosition] directly fails at once with "denied" and the
/// system prompt never appears. Purchase codes (customer), purchase
/// verification (vendor) and vendor registration all need the position, so
/// all three go through this. [action] names what the position is for, so the
/// permission-denied message reads naturally for whichever caller it is.
Future<Position> currentPosition({String action = 'verify a purchase at the shop'}) async {
  if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
    throw StateError('Turn on location services on this device, then try again.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    throw StateError(
      permission == LocationPermission.deniedForever
          ? 'Location permission is turned off. Allow it for this app in your device settings.'
          : 'Location permission is needed to $action.',
    );
  }
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
    );
  } on TimeoutException {
    throw StateError('Your location could not be found in time. Move to an open area and try again.');
  }
}

/// A best-effort location refresh for app open: unlike [currentPosition],
/// this never prompts for permission and never throws — it simply returns
/// null unless permission was already granted and location services are on.
/// This is what lets the app silently refresh "show only matching ads and
/// offers nearby" on open, without an unexpected permission dialog.
Future<Position?> currentPositionIfPermitted() async {
  try {
    if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) return null;
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
      return null;
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
    );
  } catch (_) {
    return null;
  }
}
