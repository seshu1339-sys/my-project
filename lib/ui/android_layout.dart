import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../domain/catalog.dart';

/// True only inside the Android app. The website (desktop or a phone's browser) and every other platform keep the home page exactly as
/// it was; the Android home layout (android_home_header.dart, android_ads_strip.dart and the few `isAndroidApp()` branches in
/// wireframe_home.dart) is built only when this is true.
bool isAndroidApp() => debugAndroidApp ?? (!kIsWeb && Platform.isAndroid);

/// Tests only: pretend to be (true) or not to be (false) the Android app.
@visibleForTesting
bool? debugAndroidApp;

/// The side margin of the Android home page: small, so more photos fit.
const androidEdge = 6.0;

/// The home parts' own padding and margin (Settings > Layout) never take more room than this in the Android app.
const _tightParts = {'promo', 'notice', 'crossSellStrip', 'products', 'popular', 'localServices', 'nearby', 'nearbyShopCard', 'background'};
const _maxPartPadding = 4.0;
const _maxPartMargin = 2.0;

/// The settings with the padding and margin of the home parts capped (only ones that are larger are changed). Used by the Android home
/// page alone; nothing is saved.
List<Entry> tightForAndroid(List<Entry> settings) => [
  for (final e in settings)
    if (_tightParts.contains(e.id) && (e.number('padding') > _maxPartPadding || e.number('margin') > _maxPartMargin))
      Entry(e.id, {...e.data, if (e.number('padding') > _maxPartPadding) 'padding': _maxPartPadding, if (e.number('margin') > _maxPartMargin) 'margin': _maxPartMargin})
    else
      e,
];
