import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import 'home_section_config.dart';
import 'shared.dart';

/// Shared by the editor and renderer. Zero dimensions mean automatic sizing.
const layoutComponents = <String, String>{
  'header': 'Header',
  'logo': 'Logo',
  'title': 'Business name & tagline',
  'user': 'Greeting / Welcome text',
  'location': 'Location pill',
  'search': 'Search Box',
  'services': 'Services',
  'office': 'Office / Head Office',
  'notice': 'Ticker / notice bar',
  'promo': 'Banner carousel',
  'categories': 'Categories',
  'products': 'Product cards',
  'popular': 'Popular Products',
  'localServices': 'Local Services',
  'nearby': 'Nearby shops / map',
  'ads': 'Advertisement defaults',
  'boxes': 'Promotional box defaults',
  'background': 'Page layout',
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
  'stopAfter': ('Stop scrolling after seconds (0 = continuous)', 0, 3600),
  'brightness': ('Brightness / highlight', .2, 2),
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
                'fontSize', 'gap', 'padding', 'radius', 'borderWidth',
                'width', 'minWidth', 'maxWidth', 'mobileWidth', 'tabletWidth', 'desktopWidth',
              },
              // 'title'/'user' are plain inline text (business name+tagline,
              // the greeting) with no box/decoration of their own -- same
              // "only show fields that do something" rule as 'logo' above.
              'title': {
                'gap', 'padding', 'margin', 'radius', 'borderWidth',
                'width', 'minWidth', 'maxWidth', 'mobileWidth', 'tabletWidth', 'desktopWidth',
              },
              'user': {
                'gap', 'padding', 'margin', 'radius', 'borderWidth', 'iconSize',
                'width', 'minWidth', 'maxWidth', 'mobileWidth', 'tabletWidth', 'desktopWidth',
              },
              // 'location' is a small pill (background + radius), no
              // width/padding/margin controls (it already sizes to its own
              // content, like the other inline header items).
              'location': {
                'gap', 'padding', 'margin', 'borderWidth', 'iconSize',
                'width', 'minWidth', 'maxWidth', 'mobileWidth', 'tabletWidth', 'desktopWidth',
              },
              'office': {'gap', 'iconSize'},
              'popular': {'gap', 'iconSize'},
              'localServices': {'gap', 'iconSize'},
              'nearby': {'gap'},
              'background': {'fontSize', 'iconSize'},
              'products': {'margin'},
            }[component]?.contains(key) ??
            false),
  ),
  if (component == 'search') ...['voiceIconSize', 'imageIconSize'],
  if (['categories', 'products', 'popular', 'localServices'].contains(component)) 'imageHeight',
  if (['categories', 'products', 'popular', 'localServices'].contains(component)) 'columns',
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
  if (component == 'promo') ...['visibleCount', 'animationMs'],
  if (['notice', 'ads', 'boxes'].contains(component)) 'speed',
  if (['ads', 'boxes'].contains(component)) ...['stopAfter', 'brightness'],
];

/// Which `dimensionFields` keys are real pixel quantities (get a "px"
/// suffix in the admin form) versus unitless multipliers/counts/other units
/// that would be misleading with one — the *Scale fields are 0.75-1.5
/// multipliers, columns/rows-family are plain counts, speed is px/second,
/// animationMs/stopAfter are milliseconds/seconds, brightness is a
/// 0.2-2 multiplier.
const pixelFields = <String>{
  'width', 'height', 'minWidth', 'maxWidth', 'minHeight', 'maxHeight',
  'mobileWidth', 'tabletWidth', 'desktopWidth', 'padding', 'margin', 'gap',
  'gapX', 'radius', 'borderWidth', 'fontSize', 'iconSize', 'voiceIconSize',
  'imageIconSize', 'imageHeight', 'imageWidth',
};

/// Google Fonts offered in the admin's Font family picker — five general
/// e-commerce-friendly latin faces plus five that render Telugu well, since
/// this site's ticker/UI strings are bilingual. Passed straight to
/// `GoogleFonts.getFont` in shared.dart's `sectionTextStyle`, so these must
/// be the exact canonical Google Fonts family names.
const fontFamilyOptions = <String>[
  'Poppins', 'Roboto', 'Lato', 'Montserrat', 'Open Sans',
  'Inter', 'Nunito', 'Noto Sans Telugu', 'Ramabhadra', 'Mallanna',
];

// Components whose section container is wrapped in `LayoutSection`
// (layout_settings.dart below) — they get entryDecoration's
// background/border/gradient AND the one-time entrance animation
// LayoutSection applies, plus cascaded text styling via its
// DefaultTextStyle.merge. See wireframe_home.dart/home_ad_rail.dart/
// responsive_header_bar.dart for where each is actually wrapped.
const _animatedSections = {
  'header', 'notice', 'promo', 'categories', 'popular', 'localServices', 'nearby', 'ads', 'boxes', 'background',
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
List<String> allFieldsFor(String component) {
  final animated = _animatedSections.contains(component);
  final decorated = animated || _decoratedOnly.contains(component);
  // 'title'/'user' are plain text with no box of their own -- they get
  // text styling without ever qualifying for background/border fields.
  // 'location' is a small pill -- gets a reduced background+border set,
  // the same shape 'products' already uses, without the full
  // gradient/animation treatment a whole LayoutSection gets.
  final plainText = {'title', 'user'}.contains(component);
  final textStyled = decorated || plainText || ['products', 'location'].contains(component);
  return [
    'visible',
    ...componentFields(component),
    if (decorated) ...['backgroundColor', 'gradientStart', 'gradientEnd', 'borderColor']
    else if (['products', 'location'].contains(component)) ...['backgroundColor', 'borderColor'],
    if (textStyled) ...['textColor', 'fontFamily', 'fontStyle'],
    if (['title', 'user', 'location'].contains(component)) 'text',
    if (animated) 'animation',
    if (['notice', 'ads', 'boxes'].contains(component)) 'direction',
    if (['ads', 'boxes'].contains(component)) 'scrollEnabled',
    if (['products', 'popular', 'localServices'].contains(component)) 'alignment',
    if (component == 'services') 'iconUrl',
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
      return animation == 'slide' ? Transform.translate(offset: Offset(0, (1 - t) * 24), child: faded) : faded;
    },
    child: child,
  );
}
