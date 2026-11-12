import 'package:geolocator/geolocator.dart' show Position;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/store.dart';
import 'area_lookup.dart';
import 'location.dart';

/// The very first open, in the app and on the website alike (owner, 11 Nov 2026): the phone's or the browser's location question.
/// Allowed, the GPS position sets the place (and its area name) at once, with no dialog; refused, blocked, off, or too rough a fix (a
/// computer guessing from its connection), [pick] ("Where are you shopping?") opens straight away to choose by pincode or town.
/// Asked once: the place is saved, and the pin at the top changes it any time. Does nothing when a place is already saved.
/// [position] asks and returns the fix ([positionWithPermission]); [atPoint] works out the place ([placeAtPoint]): both for tests.
Future<void> askLocationOnFirstOpen(
  Store store, {
  required Future<void> Function() pick,
  Future<Position?> Function()? position,
  Future<FoundPlace> Function(double latitude, double longitude)? atPoint,
}) async {
  if (store.hasPlace) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('locationAsked') ?? false) return;
    await prefs.setBool('locationAsked', true);
  } catch (_) {
    return;
  }
  final fix = await (position ?? positionWithPermission)();
  if (fix != null && exactEnough(fix)) {
    final place = await (atPoint?.call(fix.latitude, fix.longitude) ?? placeAtPoint(store, fix.latitude, fix.longitude));
    await savePlace(store, place, followGps: true);
    return;
  }
  if (!store.located) await pick();
}
