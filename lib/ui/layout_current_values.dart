import '../domain/catalog.dart';
import 'animation_settings.dart';
import 'home_rotating_pages.dart';
import 'home_section_config.dart';
import 'layout_settings.dart';
import 'text_animation.dart';

// ---------------------------------------------------------------------------------------------
// Layout Settings: the value each field is using RIGHT NOW, shown in brackets next to its label, e.g. "Icon size (24px)".
// A field that is blank or 0 uses the default the website's code falls back to, so that default is shown instead.
//
// The defaults below are read from the code that draws each part of the page (ComponentLayout in layout_settings.dart and the
// home_* / responsive_* widgets). Where the real default depends on the screen or the theme it says so in words. A test
// (test/layout_current_values_test.dart) pins the main ones.
// ---------------------------------------------------------------------------------------------

/// Parts drawn inside a [LayoutSection]: no inner padding, square corners unless set.
const _sectionBoxed = {'header', 'categories', 'localServices', 'nearby', 'popular', 'notice', 'ads', 'boxes', 'background', 'promo'};

/// Defaults that differ from the general ones, per part of the page.
const _componentDefaults = <String, Map<String, String>>{
  'logo': {'height': '36', 'iconSize': '32'},
  'title': {'fontSize': '17', 'fontWeight': '800'},
  'tagline': {'fontSize': '10'},
  'user': {'fontSize': '14', 'fontWeight': '700'},
  'location': {'radius': '20'},
  'office': {'radius': '20', 'padding': '4'},
  'notificationIcon': {'padding': '8'},
  'wishlistIcon': {'padding': '8'},
  'cartIcon': {'padding': '8'},
  'menuIcon': {'padding': '8'},
  'search': {'height': '56', 'gap': '2', 'iconSize': '20', 'voiceIconSize': '22', 'imageIconSize': '22', 'fontSize': 'theme default (16)'},
  'categories': {'width': '125', 'height': '125', 'padding': '12', 'iconSize': '30', 'imageHeight': '68'},
  'products': {'iconSize': '21', 'imageHeight': 'by screen'},
  'promo': {'height': 'by banners', 'visibleCount': '1', 'animationMs': '6000'},
  'ads': {'height': '240', 'animationMs': '4000'},
  'boxes': {'height': '200', 'animationMs': '4000'},
  'nearby': {'height': '320'},
  'nearbyShopCard': {'radius': '16', 'padding': '16', 'iconSize': '24'},
  'footerBadges': {'iconSize': '24'},
  'footerBadge1': {'fontSize': '12'},
  'footerBadge2': {'fontSize': '12'},
  'footerBadge3': {'fontSize': '12'},
  'footerBadge4': {'fontSize': '12'},
  'footerBadge5': {'fontSize': '12'},
  'footerBadge6': {'fontSize': '12'},
  'notice': {'speed': '25', 'stopAfter': '0'},
};

/// What a blank / 0 field really uses for [component]'s [key], as words or a number.
String layoutDefaultFor(String component, String key, {double viewport = 400}) {
  final own = _componentDefaults[component]?[key];
  if (own == 'by screen') return viewport >= 1100 ? '180' : '140';
  if (own == 'by banners') return '300 for one banner, 220 for several';
  if (own != null) return own;
  if (key.endsWith('Scale') || key == 'brightness') return '1';
  switch (key) {
    case 'width' || 'minWidth' || 'maxWidth' || 'mobileWidth' || 'tabletWidth' || 'desktopWidth' || 'imageWidth':
      return 'automatic';
    case 'height' || 'minHeight' || 'maxHeight':
      return 'automatic';
    case 'columns' || 'mobileColumns' || 'tabletColumns' || 'desktopColumns':
      return 'automatic';
    case 'rows' || 'mobileRows' || 'tabletRows' || 'desktopRows':
      return 'unlimited';
    case 'gapX':
      return 'same as gap';
    case 'gap':
      return '12';
    case 'padding':
      return _sectionBoxed.contains(component) ? '0' : '12';
    case 'radius':
      return _sectionBoxed.contains(component) ? '0' : '12';
    case 'margin' || 'borderWidth':
      return '0';
    case 'fontSize':
      return 'theme default';
    case 'iconSize' || 'voiceIconSize' || 'imageIconSize':
      return '24';
    case 'imageHeight':
      return 'automatic';
    case 'visibleCount':
      return '1';
    case 'speed':
      return '25';
    case 'animationMs':
      return '6000';
    case 'animationSpeed':
      return 'original';
    case 'stopAfter':
      return '0';
  }
  return 'default';
}

String _number(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

const _weights = {400: 'Normal', 500: 'Medium', 600: 'Semi-bold', 700: 'Bold', 800: 'Extra bold'};

/// The text for the brackets after [key]'s label, from the SAVED record [saved] (so it changes the moment a save completes).
/// Returns null for fields with nothing sensible to show (free text).
String? layoutBracketText(String component, String key, Entry saved, {double viewport = 400}) {
  if (dimensionFields.containsKey(key)) {
    final raw = saved.data[key];
    final n = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}'.trim()) ?? 0;
    final value = n > 0 ? _number(n) : layoutDefaultFor(component, key, viewport: viewport);
    final numeric = double.tryParse(value) != null;
    return numeric && pixelFields.contains(key) ? '${value}px' : value;
  }
  switch (key) {
    case 'visible':
      return componentVisible(saved, component) ? 'On' : 'Off';
    case 'scrollEnabled' || 'pauseOnTouch':
      return saved.text(key, key == 'pauseOnTouch' ? 'true' : 'false') == 'true' ? 'On' : 'Off';
    case 'fontFamily':
      return saved.text(key).isEmpty ? 'theme default' : saved.text(key);
    case 'fontStyle':
      return saved.text(key) == 'italic' ? 'Italic' : 'Normal';
    case 'fontWeight':
      final stored = saved.number(key).round();
      final weight = stored > 0 ? stored : int.tryParse(_componentDefaults[component]?[key] ?? '') ?? 0;
      return weight == 0 ? 'default' : (_weights[weight] ?? '$weight');
    case 'animation':
      final type = saved.text(key);
      return entranceTypes[type.isEmpty ? 'none' : type] ?? type;
    case 'animationType':
      return saved.text(key).isEmpty ? 'None (original behavior)' : promoAnimationLabels[saved.text(key)] ?? saved.text(key);
    case 'textAnimation' || 'headingAnimation':
      return saved.text(key).isEmpty ? 'None' : textAnimationLabels[saved.text(key)] ?? saved.text(key);
    case 'alignment':
      return switch (saved.text(key)) {
        'center' => 'Center',
        'end' => 'Right',
        'spaceBetween' => 'Spread out',
        _ => 'Left',
      };
    case 'direction':
      final notice = component == 'notice';
      final v = saved.text(key, notice ? 'rtl' : 'up');
      return switch (v) {
        'rtl' => 'Right to left',
        'ltr' => 'Left to right',
        'down' => 'Down',
        _ => notice ? 'Right to left' : 'Up',
      };
    case 'iconUrl' || 'backgroundImage':
      return saved.text(key).isEmpty ? 'none' : 'custom image';
    case 'text':
      return null;
  }
  if (key.endsWith('Color') || key == 'gradientStart' || key == 'gradientEnd') {
    return saved.text(key).isEmpty ? 'theme default' : saved.text(key);
  }
  return null;
}

/// "Label (value)"; just the label when there is no value to show.
String labelWithValue(String label, String? bracket) => bracket == null ? label : '$label ($bracket)';
