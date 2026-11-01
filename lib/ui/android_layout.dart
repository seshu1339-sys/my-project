import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../domain/catalog.dart';
import 'home_section_config.dart';

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

/// The usual top-to-bottom order of the parts under the top row, as the app builds them until the admin places them differently
/// (Settings > Android App): the ad boxes, the red scrolling banner, the notice banner, Fresh today, Today's Offers and the band under
/// it, then the sections in the order the home page has them, then the shops.
List<String> androidDefaultOrder(List<Entry> settings) {
  final sections = [...reorderableHomeSections]..sort((a, b) => sectionOrder(settings, a.key).compareTo(sectionOrder(settings, b.key)));
  return ['ads', 'scrollingText', 'notice', 'quickFresh', for (final d in sections) ...[d.key, if (d.key == 'promo') 'strip'], 'nearby'];
}
