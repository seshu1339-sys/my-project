import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import 'home_section_config.dart';
import 'shared.dart';

/// Shared by the editor and renderer. Zero dimensions mean automatic sizing.
const layoutComponents = <String, String>{
  'header': 'Header',
  'logo': 'Logo',
  'title': 'Business name',
  'tagline': 'Tagline',
  'user': 'Greeting / Welcome text',
  'location': 'Location pill',
  'search': 'Search Box',
  'services': 'Services icon',
  'notificationIcon': 'Notifications icon',
  'wishlistIcon': 'Wishlist icon',
  'cartIcon': 'Shopping bag icon',
  'menuIcon': 'Menu icon',
  'office': 'Office address & phone',
  'notice': 'Ticker / notice bar',
  'promo': 'Banner carousel',
  'categories': 'Categories',
  'moreCategoriesTile': '"More Categories" tile',
  'products': 'Product cards',
  'popular': 'Popular Products',
  'popularFilterChips': 'Popular Products filter chips',
  'localServices': 'Local Services',
  'adsLabel': '"ADS" label',
  'ads': 'Advertisement defaults',
  'boxes': 'Promotional box defaults',
  'crossSellStrip': 'Fresh Fruits & Vegetables strip',
  'nearby': 'Nearby shops / map',
  'nearbyShopCard': 'Nearby shop card',
  'footerBadges': 'Footer badges (shared size)',
  'footerBadge1': 'Footer badge 1',
  'footerBadge2': 'Footer badge 2',
  'footerBadge3': 'Footer badge 3',
  'footerBadge4': 'Footer badge 4',
  'footerBadge5': 'Footer badge 5',
  'footerBadge6': 'Footer badge 6',
  'background': 'Page layout',
  // --- Other screens (no live preview exists for these yet -- see
  // page_elements.dart's doc comment) ---
  'productPageAddButton': 'Product page: "Add to bag" button',
  'productPageBuyButton': 'Product page: "Buy now" button',
  'productPageShareIcon': 'Product page: share icon',
  'productPageWishlistIcon': 'Product page: wishlist icon',
  'productPageRelatedHeading': 'Product page: "Related products" heading',
  'productPageReviewsHeading': 'Product page: "Community reviews" heading',
  'categoryPageHeading': 'Category page: section headings',
  'cartEmptyMessage': 'Cart: empty-bag message',
  'cartEmptyIcon': 'Cart: empty-bag icon',
  'cartSubmitButton': 'Cart: submit order button',
  'servicesPageAppBarTitle': 'Services page: title',
  'shopsPageAppBarTitle': 'Shops page: title',
  'shopsPageHeading': 'Shops page: heading',
  'shopPageDirectionsButton': 'Shop page: "Get directions" button',
  'shopPageRelatedHeading': 'Shop page: "From this shop" heading',
  'accountPageAppBarTitle': 'Account page: title',
  'accountDemoHeading': 'Account page: demo-mode heading',
  'accountOrdersHeading': 'Account page: "Your orders" heading',
  'authFormHeading': 'Sign-in form: heading',
  'wishlistDialogTitle': 'Wishlist dialog: title',
};

const _footerBadgeKeys = {
  'footerBadge1',
  'footerBadge2',
  'footerBadge3',
  'footerBadge4',
  'footerBadge5',
  'footerBadge6',
};

// Plain heading/label/button text on the non-homepage screens -- these
// screens have no live Visual Editor preview at all (see
// page_elements.dart), so unlike the homepage elements above there is no
// wrapSection/click-to-select for any of these; they're reachable only via
// "Go to number" and the Layout Settings dropdown. Treated uniformly as
// one shape (text/color/font family/style/weight + optional background,
// no box sizing) rather than hand-distinguishing headings from buttons --
// a deliberately broader brush than the homepage got, given how many of
// these there are.
const _otherScreenTextKeys = {
  'productPageAddButton',
  'productPageBuyButton',
  'productPageRelatedHeading',
  'productPageReviewsHeading',
  'categoryPageHeading',
  'cartEmptyMessage',
  'cartSubmitButton',
  'servicesPageAppBarTitle',
  'shopsPageAppBarTitle',
  'shopsPageHeading',
  'shopPageDirectionsButton',
  'shopPageRelatedHeading',
  'accountPageAppBarTitle',
  'accountDemoHeading',
  'accountOrdersHeading',
  'authFormHeading',
  'wishlistDialogTitle',
};
// A handful of these (the two-states-share-one-label case, like
// 'categoryPageHeading' covering both "Subcategories" and "{n} products")
// get styling only, no single sensible text override.
const _otherScreenStyleOnly = {'categoryPageHeading'};
const _otherScreenIconKeys = {
  'productPageShareIcon',
  'productPageWishlistIcon',
  'cartEmptyIcon',
};

const dimensionFields = <String, (String, double, double)>{
  'width': ('Width (0 = automatic)', 0, 3840),
  'height': ('Height (0 = automatic)', 0, 1200),
  'minWidth': ('Minimum width', 0, 3840),
  'maxWidth': ('Maximum width (0 = automatic)', 0, 3840),
  'minHeight': ('Minimum height', 0, 1200),
  'maxHeight': ('Maximum height (0 = automatic)', 0, 1200),
  'mobileWidth': ('Mobile width (0 = automatic)', 0, 3840),
  'tabletWidth': ('Tablet width (0 = automatic)', 0, 3840),
  'desktopWidth': ('Desktop width (0 = automatic)', 0, 3840),
  'mobileScale': ('Mobile scale', .75, 1.5),
  'tabletScale': ('Tablet scale', .75, 1.5),
  'desktopScale': ('Desktop scale', .75, 1.5),
  'padding': ('Internal padding', 0, 48),
  'margin': ('Outer margin', 0, 48),
  'gap': ('Gap / spacing', 0, 64),
  'radius': ('Border radius', 0, 80),
  'borderWidth': ('Border thickness', 0, 8),
  'fontSize': ('Font size (0 = theme default)', 0, 40),
  'iconSize': ('Icon size', 16, 48),
  'voiceIconSize': ('Voice search icon size', 16, 48),
  'imageIconSize': ('Image search icon size', 16, 48),
  'imageHeight': ('Image height', 32, 400),
  'imageWidth': ('Image width (0 = automatic/fill)', 0, 3840),
  'columns': ('Columns (0 = automatic)', 0, 12),
  'rows': ('Rows (0 = unlimited)', 0, 12),
  'gapX': ('Horizontal spacing (0 = same as gap)', 0, 64),
  'mobileColumns': ('Mobile columns (0 = use Columns)', 0, 12),
  'tabletColumns': ('Tablet columns (0 = use Columns)', 0, 12),
  'desktopColumns': ('Desktop columns (0 = use Columns)', 0, 12),
  'mobileRows': ('Mobile rows (0 = use Rows)', 0, 12),
  'tabletRows': ('Tablet rows (0 = use Rows)', 0, 12),
  'desktopRows': ('Desktop rows (0 = use Rows)', 0, 12),
  'visibleCount': ('Visible banners / items', 1, 12),
  'speed': ('Scroll speed (pixels/second)', 10, 300),
  'animationMs': ('Rotation interval (milliseconds)', 1000, 120000),
  'animationSpeed': ('Animation speed (1 = slow, 10 = fast)', 1, 10),
  'stopAfter': ('Stop scrolling after seconds (0 = continuous)', 0, 3600),
  'brightness': ('Brightness / highlight', .2, 2),
};

// The 4 header icon buttons (notifications/wishlist/cart/menu) are plain
// Icon widgets with no font/box of their own — same "only show fields that
// do something" rule as logo/title/user/location above, just shared across
// all 4 since they're identical in shape (an icon, optionally swapped for
// an image, with its own color/size/padding/background/visibility).
const _iconExclusions = {
  'fontSize',
  'gap',
  'margin',
  'radius',
  'borderWidth',
  'width',
  'minWidth',
  'maxWidth',
  'mobileWidth',
  'tabletWidth',
  'desktopWidth',
};

// Small fixed icon+text pieces (the "More Categories" tile, "ADS" label,
// filter chips, footer badges) that size to their own content -- same
// "only show fields that do something" rule as above, just keeping
// fontSize/iconSize/padding since (unlike the plain icon buttons) these
// have both an icon AND a text label.
const _smallBadgeExclusions = {
  'gap',
  'margin',
  'radius',
  'borderWidth',
  'width',
  'minWidth',
  'maxWidth',
  'mobileWidth',
  'tabletWidth',
  'desktopWidth',
};

// Footer badge SUBS (one of the 6 fixed badges) -- same shape as the other
// small badges above, but `iconSize` also moves out: it's now set once on
// the group's own shared main ('footerBadges' below), so every badge is
// always the same size, per the admin's own "sub-numbers have no size
// option" rule.
const _footerBadgeSubExclusions = {..._smallBadgeExclusions, 'iconSize'};

// The footer badges GROUP MAIN ('footerBadges') controls ONLY the one
// thing that must stay identical across all 6 badges -- icon size -- so
// every other dimension field is excluded here.
const _footerBadgesMainExclusions = {
  'width',
  'height',
  'minWidth',
  'maxWidth',
  'minHeight',
  'maxHeight',
  'mobileWidth',
  'tabletWidth',
  'desktopWidth',
  'mobileScale',
  'tabletScale',
  'desktopScale',
  'padding',
  'margin',
  'gap',
  'radius',
  'borderWidth',
  'fontSize',
};

List<String> componentFields(String component) => [
  ...dimensionFields.keys.where(
    (key) =>
        !{
          'voiceIconSize',
          'imageIconSize',
          'imageHeight',
          'imageWidth',
          'columns',
          'rows',
          'gapX',
          'mobileColumns',
          'tabletColumns',
          'desktopColumns',
          'mobileRows',
          'tabletRows',
          'desktopRows',
          'visibleCount',
          'speed',
          'animationMs',
          'animationSpeed',
          'stopAfter',
          'brightness',
        }.contains(key) &&
        !({
              'header': {'fontSize'},
              // width/padding/margin/radius/borderWidth excluded here, not
              // just unset: the logo icon is a deliberately square box sized
              // from `height` alone (see responsive_header_bar.dart), with
              // no padding/margin/decoration wrapper at all — showing these
              // fields would let an admin "set" them and see nothing happen.
              // Height (and minHeight/maxHeight/*Scale, which feed it) and
              // iconSize are the only ones that actually do anything here.
              'logo': {
                'fontSize',
                'gap',
                'padding',
                'radius',
                'borderWidth',
                'width',
                'minWidth',
                'maxWidth',
                'mobileWidth',
                'tabletWidth',
                'desktopWidth',
              },
              // 'title'/'user' are plain inline text (business name+tagline,
              // the greeting) with no box/decoration of their own -- same
              // "only show fields that do something" rule as 'logo' above.
              // Also excludes height/minHeight/maxHeight/*Scale/iconSize --
              // title is a plain inline Text with no box or icon of its own,
              // so those never did anything (shown-but-dead fields).
              'title': {
                'gap',
                'padding',
                'margin',
                'radius',
                'borderWidth',
                'iconSize',
                'width',
                'minWidth',
                'maxWidth',
                'mobileWidth',
                'tabletWidth',
                'desktopWidth',
                'height',
                'minHeight',
                'maxHeight',
                'mobileScale',
                'tabletScale',
                'desktopScale',
              },
              // 'tagline' is the small muted line under the title — same
              // shape as 'title' above.
              'tagline': {
                'gap',
                'padding',
                'margin',
                'radius',
                'borderWidth',
                'iconSize',
                'width',
                'minWidth',
                'maxWidth',
                'mobileWidth',
                'tabletWidth',
                'desktopWidth',
                'height',
                'minHeight',
                'maxHeight',
                'mobileScale',
                'tabletScale',
                'desktopScale',
              },
              // Also excludes height/minHeight/maxHeight/*Scale -- same
              // "shown-but-dead" fix as 'title' above (iconSize was already
              // excluded here).
              'user': {
                'gap',
                'padding',
                'margin',
                'radius',
                'borderWidth',
                'iconSize',
                'width',
                'minWidth',
                'maxWidth',
                'mobileWidth',
                'tabletWidth',
                'desktopWidth',
                'height',
                'minHeight',
                'maxHeight',
                'mobileScale',
                'tabletScale',
                'desktopScale',
              },
              // 'location' is a small pill (background + radius), no
              // width/padding/margin controls (it already sizes to its own
              // content, like the other inline header items).
              'location': {
                'gap',
                'padding',
                'margin',
                'borderWidth',
                'iconSize',
                'width',
                'minWidth',
                'maxWidth',
                'mobileWidth',
                'tabletWidth',
                'desktopWidth',
              },
              'notificationIcon': _iconExclusions,
              'wishlistIcon': _iconExclusions,
              'cartIcon': _iconExclusions,
              'menuIcon': _iconExclusions,
              // 'office' shows two lines of plain text (address + phone) in
              // a tappable block — background/radius/padding apply to that
              // block, but it has no gap/icon of its own and sizes to its
              // own content like the other inline header items.
              'office': {
                'gap',
                'iconSize',
                'margin',
                'width',
                'minWidth',
                'maxWidth',
                'mobileWidth',
                'tabletWidth',
                'desktopWidth',
              },
              'popular': {'gap', 'iconSize'},
              'localServices': {'gap', 'iconSize'},
              'nearby': {'gap'},
              'background': {'fontSize', 'iconSize'},
              'products': {'margin'},
              'moreCategoriesTile': _smallBadgeExclusions,
              'popularFilterChips': _smallBadgeExclusions,
              'adsLabel': _smallBadgeExclusions,
              // 'nearbyShopCard' is a real card -- keeps radius/borderWidth/
              // padding (unlike the other small badges above) since those
              // all apply visibly to its own box.
              'nearbyShopCard': {
                'gap',
                'margin',
                'width',
                'minWidth',
                'maxWidth',
                'mobileWidth',
                'tabletWidth',
                'desktopWidth',
              },
              'footerBadges': _footerBadgesMainExclusions,
              'footerBadge1': _footerBadgeSubExclusions,
              'footerBadge2': _footerBadgeSubExclusions,
              'footerBadge3': _footerBadgeSubExclusions,
              'footerBadge4': _footerBadgeSubExclusions,
              'footerBadge5': _footerBadgeSubExclusions,
              'footerBadge6': _footerBadgeSubExclusions,
              for (final key in _otherScreenTextKeys)
                key: _smallBadgeExclusions,
              for (final key in _otherScreenIconKeys) key: _iconExclusions,
            }[component]?.contains(key) ??
            false),
  ),
  if (component == 'search') ...['voiceIconSize', 'imageIconSize'],
  if ([
    'categories',
    'products',
    'popular',
    'localServices',
    'crossSellStrip',
  ].contains(component))
    'imageHeight',
  if ([
    'categories',
    'products',
    'popular',
    'localServices',
  ].contains(component))
    'columns',
  // Adjusts the brightness/contrast of the category tile and product card
  // photos themselves (see home_category_tile.dart/home_product_tile.dart)
  // -- not just a decorative section background like 'ads'/'boxes' below.
  // NOT 'popular': its own key only drives the Popular Products heading --
  // the grid/card images there read 'products' (see wireframe_home.dart),
  // so a brightness field under 'popular' itself would be shown but dead,
  // exactly the mistake this round is fixing elsewhere.
  if (['categories', 'products', 'localServices', 'crossSellStrip'].contains(
    component,
  ))
    'brightness',
  if (['products', 'popular', 'localServices'].contains(component)) ...[
    'rows',
    'imageWidth',
    'gapX',
    'mobileColumns',
    'tabletColumns',
    'desktopColumns',
    'mobileRows',
    'tabletRows',
    'desktopRows',
  ],
  // 'speed'/'direction'/'scrollEnabled'/'visibleCount'/'animationMs'/
  // 'stopAfter' moved out to each section's own "<Name> Settings" page
  // (group_settings_page.dart) -- behavior, not look, per the admin's own
  // Design/Settings/Content split. 'brightness' stays here: it's the
  // ad/box's own photo brightness, a real design property.
  if (['ads', 'boxes'].contains(component)) 'brightness',
];

/// The behavior-only field list for each section's own dedicated
/// "Settings" page -- the exact fields removed from allFieldsFor above,
/// kept in one place so neither list can silently drift from the other.
const behaviorSettingsFields = <String, List<String>>{
  'notice': ['speed', 'direction'],
  'promo': [
    'visibleCount',
    'animationMs',
    'animationType',
    'animationSpeed',
    'pauseOnTouch',
  ],
  'ads': [
    'speed',
    'direction',
    'scrollEnabled',
    'stopAfter',
    'animationType',
    'animationSpeed',
    'animationMs',
    'visibleCount',
    'pauseOnTouch',
  ],
  'boxes': ['speed', 'direction', 'scrollEnabled', 'stopAfter'],
};

/// Which `dimensionFields` keys are real pixel quantities (get a "px"
/// suffix in the admin form) versus unitless multipliers/counts/other units
/// that would be misleading with one — the *Scale fields are 0.75-1.5
/// multipliers, columns/rows-family are plain counts, speed is px/second,
/// animationMs/stopAfter are milliseconds/seconds, brightness is a
/// 0.2-2 multiplier.
const pixelFields = <String>{
  'width',
  'height',
  'minWidth',
  'maxWidth',
  'minHeight',
  'maxHeight',
  'mobileWidth',
  'tabletWidth',
  'desktopWidth',
  'padding',
  'margin',
  'gap',
  'gapX',
  'radius',
  'borderWidth',
  'fontSize',
  'iconSize',
  'voiceIconSize',
  'imageIconSize',
  'imageHeight',
  'imageWidth',
};

/// Google Fonts offered in the admin's Font family picker — five general
/// e-commerce-friendly latin faces plus five that render Telugu well, since
/// this site's ticker/UI strings are bilingual. Passed straight to
/// `GoogleFonts.getFont` in shared.dart's `sectionTextStyle`, so these must
/// be the exact canonical Google Fonts family names.
const fontFamilyOptions = <String>[
  'Poppins',
  'Roboto',
  'Lato',
  'Montserrat',
  'Open Sans',
  'Inter',
  'Nunito',
  'Noto Sans Telugu',
  'Ramabhadra',
  'Mallanna',
];

// Components whose section container is wrapped in `LayoutSection`
// (layout_settings.dart below) — they get entryDecoration's
// background/border/gradient AND the one-time entrance animation
// LayoutSection applies, plus cascaded text styling via its
// DefaultTextStyle.merge. See wireframe_home.dart/home_ad_rail.dart/
// responsive_header_bar.dart for where each is actually wrapped.
const _animatedSections = {
  'header',
  'notice',
  'promo',
  'categories',
  'popular',
  'localServices',
  'crossSellStrip',
  'nearby',
  'ads',
  'boxes',
  'background',
};
// Has its own entryDecoration/sectionTextStyle call but isn't wrapped in its
// own LayoutSection (no entrance animation of its own).
const _decoratedOnly = {'search'};

/// The full, ordered field list the admin form builds for one component —
/// `componentFields` (the numeric dimension fields) plus visibility, colors,
/// typography and the other non-numeric controls, included only where
/// they're genuinely wired to something real for that specific component.
/// Centralizing this (rather than each caller re-deriving which extras
/// apply) is what makes layout_editor.dart's form and this file's own
/// render-time checks impossible to drift apart.
const _iconOnlyComponents = {
  'notificationIcon',
  'wishlistIcon',
  'cartIcon',
  'menuIcon',
  ..._otherScreenIconKeys,
};
// Elements that read like a small pill/block (background + border, but no
// gradient/entrance-animation of a full LayoutSection) -- 'tagline' and
// 'office' joined this set so every header element gets a background
// color option, matching 'products'/'location' which already had one.
// The small home-page badges joined for the same reason.
const _pillLikeComponents = {
  'products',
  'location',
  'tagline',
  'office',
  'moreCategoriesTile',
  'popularFilterChips',
  'adsLabel',
  'nearbyShopCard',
  ..._footerBadgeKeys,
  ..._otherScreenTextKeys,
};
// Elements with their own text content that can be overridden from the
// admin (as opposed to 'office'/'nearbyShopCard', whose text comes from
// Business Profile/the shops catalog per-entry and has no single sensible
// one-field override).
final _textOverridable = {
  'title',
  'user',
  'location',
  'tagline',
  'notice',
  'categories',
  'popular',
  'localServices',
  'crossSellStrip',
  'nearby',
  'moreCategoriesTile',
  'adsLabel',
  ..._footerBadgeKeys,
  ..._otherScreenTextKeys,
}..removeAll(_otherScreenStyleOnly);
// Has a swappable icon image (iconUrl) alongside its own text/box -- unlike
// the plain icon-only header buttons, these also show a text label.
const _iconReplaceableWithText = {
  'moreCategoriesTile',
  'nearbyShopCard',
  ..._footerBadgeKeys,
};
// Elements whose fallback icon (shown when no image is set) can be
// recolored, without the rest of the full icon-button treatment
// (background/replace-image) -- 'logo''s image already comes from
// Business Profile, and 'services' already gets its own 'iconUrl' field
// below, so neither needs the full _iconOnlyComponents shape, just a color.
const _iconTintable = {'logo', 'services'};

List<String> allFieldsFor(String component) {
  final animated = _animatedSections.contains(component);
  final decorated = animated || _decoratedOnly.contains(component);
  // 'title'/'user'/'tagline' are plain text with no box of their own --
  // they get text styling without ever qualifying for background/border
  // fields on their own (tagline/location/office instead get the reduced
  // pill-like set below).
  final plainText = {'title', 'user'}.contains(component);
  final pillLike = _pillLikeComponents.contains(component);
  final iconOnly = _iconOnlyComponents.contains(component);
  final textStyled = decorated || plainText || pillLike;
  return [
    'visible',
    ...componentFields(component),
    if (decorated) ...[
      'backgroundColor',
      'gradientStart',
      'gradientEnd',
      'borderColor',
    ] else if (pillLike || iconOnly) ...[
      'backgroundColor',
      'borderColor',
    ],
    if (textStyled) ...[
      'textColor',
      'fontFamily',
      'fontStyle',
      'fontWeight',
    ] else if (iconOnly || _iconTintable.contains(component))
      'textColor',
    if (_textOverridable.contains(component)) 'text',
    if (animated) 'animation',
    // Lets an admin set a real photo behind the "Today's Best Offers"
    // strip, turning it into an actual banner instead of a plain-colored
    // bar -- scoped to just 'notice' for now, the one place this was asked
    // for, rather than every decorated section at once.
    if (component == 'notice') 'backgroundImage',
    if (['products', 'popular', 'localServices'].contains(component))
      'alignment',
    if (component == 'services' ||
        iconOnly ||
        _iconReplaceableWithText.contains(component))
      'iconUrl',
  ];
}

class ComponentLayout {
  ComponentLayout(this.entry, this.viewport);
  final Entry entry;
  final double viewport;
  String get breakpoint => viewport < 700
      ? 'mobile'
      : viewport < 1100
      ? 'tablet'
      : 'desktop';
  double n(String key, double fallback, [double min = 0, double max = 3840]) {
    final value = entry.number(key, fallback);
    return (value.isFinite ? value : fallback).clamp(min, max).toDouble();
  }

  double get scale => n('${breakpoint}Scale', 1, .75, 1.5);
  double get gap => n('gap', 12, 0, 64) * scale;
  double get gapX {
    final raw = n('gapX', 0, 0, 64);
    return raw > 0 ? raw * scale : gap;
  }

  double get padding => n('padding', 12, 0, 48) * scale;
  double get margin => n('margin', 0, 0, 48);
  double get radius => n('radius', 12, 0, 80);
  int get rows {
    final perBreakpoint = n('${breakpoint}Rows', 0, 0, 12).round();
    return perBreakpoint > 0 ? perBreakpoint : n('rows', 0, 0, 12).round();
  }

  WrapAlignment get alignment => switch (entry.text('alignment')) {
    'center' => WrapAlignment.center,
    'end' => WrapAlignment.end,
    'spaceBetween' => WrapAlignment.spaceBetween,
    _ => WrapAlignment.start,
  };
  bool get visible => sectionVisible(entry) && entry.active;
  double font(double fallback) =>
      (n('fontSize', 0, 0, 40) > 0
          ? n('fontSize', fallback, 10, 40)
          : fallback) *
      scale;
  double width(double available, {double? fallback, double floor = 0}) {
    final limit = math.max(0.0, available);
    final explicit = n('${breakpoint}Width', 0);
    final requested = explicit > 0 ? explicit : n('width', 0);
    final min = math.max(floor, n('minWidth', 0)).clamp(0, limit).toDouble();
    final rawMax = n('maxWidth', 0);
    final max = (rawMax > 0 ? rawMax * scale : limit)
        .clamp(min, limit)
        .toDouble();
    return (requested > 0 ? requested * scale : fallback ?? limit)
        .clamp(min, max)
        .toDouble();
  }

  double height(double fallback, {double floor = 0}) {
    final min = math.max(floor, n('minHeight', 0)).toDouble();
    final rawMax = n('maxHeight', 0);
    final max = math.max(min, rawMax > 0 ? rawMax * scale : 1800.0);
    final requested = n('height', 0);
    return ((requested > 0 ? requested : fallback) * scale)
        .clamp(min, max)
        .toDouble();
  }

  int columns(
    double available, {
    double preferred = 240,
    double minimum = 170,
  }) {
    final perBreakpointCols = n('${breakpoint}Columns', 0, 0, 12).round();
    final desired = perBreakpointCols > 0
        ? perBreakpointCols
        : n('columns', 0, 0, 12).round();
    final safeCount = math.max(
      1,
      ((available + gap) / (minimum + gap)).floor(),
    );
    final targetWidth = width(
      available,
      fallback: preferred * scale,
      floor: minimum,
    );
    final automatic = math.max(
      1,
      ((available + gap) / (targetWidth + gap)).floor(),
    );
    return (desired > 0 ? desired : automatic).clamp(1, safeCount);
  }

  Entry styled(BuildContext context, {double fontSize = 14}) =>
      Entry(entry.id, {
        ...entry.data,
        'fontSize': font(
          (Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14) *
              fontSize /
              14,
        ),
      });
}

ComponentLayout layoutFor(
  BuildContext context,
  List<Entry> settings,
  String id,
) => ComponentLayout(
  sectionConfig(settings, id),
  MediaQuery.sizeOf(context).width,
);

/// A section may grow for readable content even if an admin requests a tiny height.
class LayoutSection extends StatelessWidget {
  const LayoutSection({super.key, required this.layout, required this.child});
  final ComponentLayout layout;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (!layout.visible) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final insetBudget = math.max(0.0, (c.maxWidth - 280) / 4);
        final margin = layout.margin.clamp(0, insetBudget).toDouble();
        final padding = layout
            .n('padding', 0, 0, 48)
            .clamp(0, insetBudget)
            .toDouble();
        final content = Padding(
          padding: EdgeInsets.all(margin),
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              width: layout.width(
                math.max(0, c.maxWidth - margin * 2),
                floor: math.min(c.maxWidth, 280),
              ),
              constraints: BoxConstraints(minHeight: layout.height(0)),
              padding: EdgeInsets.all(padding),
              decoration: entryDecoration(
                layout.entry,
                fallback: Colors.transparent,
                defaultRadius: 0,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: IconTheme.merge(
                  data: IconThemeData(size: layout.n('iconSize', 24, 16, 48)),
                  child: DefaultTextStyle.merge(
                    style: sectionTextStyle(layout.styled(context)),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
        return applyEntranceAnimation(layout.entry, content);
      },
    );
  }
}

/// Wraps [child] in a one-time entrance animation (fade in, or fade+slide up)
/// driven by the component's own `animation` field (none/fade/slide,
/// default none — fully backward compatible with every section that's never
/// set it). Plays once per mount, not on every rebuild: `TweenAnimationBuilder`
/// only re-animates when its tween's begin/end values actually move the
/// displayed value, and once this reaches 1.0 a fresh 0→1 tween on a later
/// rebuild has nothing left to animate. Exposed as a top-level helper (not
/// buried in `LayoutSection`'s build method) so the same effect can be
/// reused for the admin form's own "Preview" button on a tiny demo box.
Widget applyEntranceAnimation(Entry entry, Widget child) {
  final animation = entry.text('animation', 'none');
  if (animation != 'fade' && animation != 'slide') return child;
  return TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 450),
    curve: Curves.easeOut,
    builder: (context, t, builtChild) {
      final faded = Opacity(opacity: t, child: builtChild);
      return animation == 'slide'
          ? Transform.translate(offset: Offset(0, (1 - t) * 24), child: faded)
          : faded;
    },
    child: child,
  );
}
