import 'package:flutter/widgets.dart';

import '../data/store.dart';
import '../services/strings.dart';

/// The home greeting, the same on the website and in the Android app (owner, 11 Nov 2026):
///   signed in (with a name)   "Hello, Ravi", and the area name on the line under it
///   otherwise                 "Hello, Kancharapalem People"
///   no place known yet        "Hello, Ravi" / the admin's welcome text ([welcome])
/// The area is the customer's ONE place name ([Store.placeName]), the same one the location box and "Today's ... Offers" show.
({String line, String under}) greetingLines(BuildContext context, Store store, {String welcome = 'Welcome'}) {
  final place = store.placeName;
  // The signed-in person's name (cleared on sign-out).
  final name = store.profileName.trim();
  if (name.isNotEmpty) return (line: 'Hello, {name}'.tr(context, {'name': name}), under: place);
  if (place.isNotEmpty) return (line: 'Hello, {area} People'.tr(context, {'area': place}), under: '');
  return (line: welcome.tr(context), under: '');
}
