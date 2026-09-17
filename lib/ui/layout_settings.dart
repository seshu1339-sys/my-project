import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import 'shared.dart';

/// Shared by the editor and renderer. Zero dimensions mean automatic sizing.
const layoutComponents = <String, String>{
  'header': 'Header',
  'logo': 'Logo',
  'user': 'User / location',
  'search': 'Search Box',
  'services': 'Services',
  'office': 'Office / Head Office',
  'notice': 'Ticker / notice bar',
  'promo': 'Banner carousel',
  'categories': 'Categories',
  'products': 'Product cards',
  'popular': 'Popular Products',
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
  'columns': ('Columns (0 = automatic)', 0, 12),
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
          'columns',
          'visibleCount',
          'speed',
          'animationMs',
          'stopAfter',
          'brightness',
        }.contains(key) &&
        !({
              'header': {'fontSize'},
              'logo': {'fontSize', 'gap'},
              'user': {'gap', 'iconSize'},
              'office': {'gap', 'iconSize'},
              'popular': {'gap', 'iconSize'},
              'nearby': {'gap'},
              'background': {'fontSize', 'iconSize'},
              'products': {'margin'},
            }[component]?.contains(key) ??
            false),
  ),
  if (component == 'search') ...['voiceIconSize', 'imageIconSize'],
  if (['categories', 'products'].contains(component)) 'imageHeight',
  if (['categories', 'products'].contains(component)) 'columns',
  if (component == 'promo') ...['visibleCount', 'animationMs'],
  if (['notice', 'ads', 'boxes'].contains(component)) 'speed',
  if (['ads', 'boxes'].contains(component)) ...['stopAfter', 'brightness'],
];

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
  double get gap => n('gap', 16, 0, 64) * scale;
  double get padding => n('padding', 12, 0, 48) * scale;
  double get margin => n('margin', 0, 0, 48);
  double get radius => n('radius', 12, 0, 80);
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
    final desired = n('columns', 0, 0, 12).round();
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
        return Padding(
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
      },
    );
  }
}
