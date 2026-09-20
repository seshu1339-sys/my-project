import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// The device's current position, asking for location permission first.
///
/// A fresh install has not been granted permission, so calling
/// [Geolocator.getCurrentPosition] directly fails at once with "denied" and the
/// system prompt never appears. Purchase codes (customer) and purchase
/// verification (vendor) both need the position, so both go through this.
Future<Position> currentPosition() async {
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
          : 'Location permission is needed to verify a purchase at the shop.',
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
