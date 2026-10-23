import 'package:flutter/material.dart';

import '../services/strings.dart';
import 'layout_settings.dart';
import 'shared.dart';

// The admin-overridable pieces of the fixed customer screens (product, cart, account ...). They live here, not in shared.dart, because they
// need the customer home layout engine (layout_settings.dart): shared.dart is used by every app, and the vendor and staff apps must not
// have to carry the customer layout engine just to show a message or a colour.

/// A single admin-overridable icon button for one of the fixed, non-home
/// screens (product/cart/account/...) that have no live Visual Editor
/// preview — see lib/ui/page_elements.dart's doc comment. Same shape as the
/// header's own icon-button helper (icon color/size/replace-image/
/// background/visibility), just reusable across files since none of those
/// screens share a single parent widget the way the header does.
Widget pageIconButton(
  BuildContext context, {
  required ComponentLayout layout,
  required IconData icon,
  required String tooltip,
  required VoidCallback onPressed,
}) {
  if (!layout.visible) return const SizedBox.shrink();
  final entry = layout.entry;
  final size = entry.number('iconSize') > 0
      ? clampedNumber(entry, 'iconSize', 24, 16, 48)
      : 24.0;
  final color = entry.text('textColor').isEmpty
      ? null
      : colorFromHex(entry.text('textColor'), Colors.black87);
  final iconUrl = entry.text('iconUrl');
  final iconWidget = iconUrl.isEmpty
      ? Icon(icon, size: size, color: color)
      : Image.network(
          iconUrl,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, error, stack) =>
              Icon(icon, size: size, color: color),
        );
  final button = IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: iconWidget,
  );
  final backgroundColor = entry.text('backgroundColor');
  return backgroundColor.isEmpty
      ? button
      : Material(
          color: colorFromHex(backgroundColor, Colors.transparent),
          shape: const CircleBorder(),
          child: button,
        );
}

/// A single admin-overridable heading/label on one of those same fixed,
/// non-home screens — text/color/font family/style/weight, falling back to
/// exactly [defaultText]/[fontSize]/[fontWeight] when unset. Pass
/// `overridable: false` for the handful of elements that share one
/// settings key across two different default strings (so there's no single
/// sensible text override — see 'categoryPageHeading' in layout_settings.dart).
Widget pageHeadingText(
  BuildContext context, {
  required ComponentLayout layout,
  required String defaultText,
  double fontSize = 24,
  FontWeight fontWeight = FontWeight.bold,
  bool overridable = true,
  bool translate = true,
}) {
  if (!layout.visible) return const SizedBox.shrink();
  final entry = layout.entry;
  final text = overridable ? entry.text('text', defaultText) : defaultText;
  return Text(
    translate ? text.tr(context) : text,
    style: sectionTextStyle(entry, fontSize: fontSize, fontWeight: fontWeight),
  );
}
