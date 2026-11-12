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

/// A fix less exact than this (a computer without GPS guesses from its internet connection, often a city hundreds of km away) is not
/// used to set the customer's place: they choose it by hand instead.
const roughFixMeters = 5000.0;

/// True when [position] is exact enough to set the customer's place ([roughFixMeters]; an unknown accuracy counts as exact).
bool exactEnough(Position position) => position.accuracy <= 0 || position.accuracy <= roughFixMeters;

/// The first open of the app or the website: asks for location permission (the phone's or the browser's own question) and then
/// the position. Null when it is refused or blocked, location is off, or no position comes: the caller then shows the place picker.
/// Never throws.
Future<Position?> positionWithPermission() async {
  try {
    if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) return null;
    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
    } catch (_) {
      // Some browsers cannot tell before asking.
      permission = LocationPermission.denied;
    }
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) return null;
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
    );
  } catch (_) {
    return null;
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
