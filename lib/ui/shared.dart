import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../domain/catalog.dart';
import 'design_tokens.dart';

Color colorFromHex(String value, Color fallback) {
  final normalized = value.trim().replaceFirst('#', '');
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null || (normalized.length != 6 && normalized.length != 8)) {
    return fallback;
  }
  return Color(normalized.length == 6 ? 0xff000000 | parsed : parsed);
}

double clampedNumber(
  Entry entry,
  String key,
  double fallback,
  double min,
  double max,
) {
  final value = entry.number(key, fallback);
  return (value.isFinite ? value : fallback).clamp(min, max).toDouble();
}

TextStyle sectionTextStyle(
  Entry config, {
  double fontSize = 14,
  FontWeight fontWeight = FontWeight.normal,
}) {
  final base = TextStyle(
    color: config.text('textColor').isEmpty
        ? null
        : colorFromHex(config.text('textColor'), Colors.black87),
    fontSize: config.number('fontSize') <= 0
        ? fontSize
        : clampedNumber(config, 'fontSize', fontSize, 10, 72),
    fontWeight: FontWeight.values.firstWhere(
      (weight) =>
          weight.value ==
          config.number('fontWeight', fontWeight.value.toDouble()),
      orElse: () => fontWeight,
    ),
    fontStyle: config.text('fontStyle') == 'italic'
        ? FontStyle.italic
        : FontStyle.normal,
  );
  final family = config.text('fontFamily').trim();
  if (family.isEmpty) return base;
  try {
    // Loads the Google Font on demand and merges it onto the same base
    // style — admins pick from fontFamilyOptions (layout_settings.dart), a
    // closed list of real Google Fonts names, but this still fails safe to
    // the plain base style for any unrecognized/old stored value instead of
    // throwing.
    return GoogleFonts.getFont(family, textStyle: base);
  } catch (_) {
    return base;
  }
}

BoxShadow? shadowFromEntry(Entry entry) {
  final strength = clampedNumber(entry, 'shadow', 0, 0, 1);
  if (strength == 0) return null;
  return BoxShadow(
    color: Colors.black.withValues(alpha: strength * .22),
    blurRadius: 18 * strength,
    offset: Offset(0, 6 * strength),
  );
}

BoxDecoration entryDecoration(
  Entry entry, {
  Color fallback = Colors.white,
  double defaultRadius = 20,
}) {
  final opacity = clampedNumber(entry, 'opacity', 1, 0, 1);
  final brightness = clampedNumber(entry, 'brightness', 1, 0.2, 2);
  final base = colorFromHex(entry.text('backgroundColor'), fallback);
  final background =
      (brightness <= 1
              ? Color.lerp(Colors.black, base, brightness)!
              : Color.lerp(base, Colors.white, brightness - 1)!)
          .withValues(alpha: base.a * opacity);
  final gradientStart = entry.text('gradientStart');
  final gradientEnd = entry.text('gradientEnd');
  final gradient = gradientStart.isEmpty || gradientEnd.isEmpty
      ? null
      : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorFromHex(gradientStart, background).withValues(alpha: opacity),
            colorFromHex(gradientEnd, background).withValues(alpha: opacity),
          ],
        );
  final shadow = shadowFromEntry(entry);
  final imageUrl = entry.text('backgroundImage');
  return BoxDecoration(
    // BoxDecoration paints a solid color OR a gradient, never both — a
    // gradient (when both ends are set) takes over from the plain
    // background color entirely, exactly like background-image does.
    color: gradient == null ? background : null,
    gradient: gradient,
    image: imageUrl.isEmpty
        ? null
        : DecorationImage(
            image: NetworkImage(imageUrl),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 1 - brightness.clamp(0.2, 2) / 2),
              BlendMode.darken,
            ),
          ),
    borderRadius: BorderRadius.circular(
      clampedNumber(entry, 'radius', defaultRadius, 0, 80),
    ),
    border: entry.text('borderColor').isEmpty
        ? null
        : Border.all(
            color: colorFromHex(entry.text('borderColor'), Colors.transparent),
            width: clampedNumber(entry, 'borderWidth', 1, 0, 12),
          ),
    boxShadow: shadow == null ? null : [shadow],
  );
}

/// A product's precomputed `avgRating`/`reviewCount` (set server-side by
/// `submitVerifiedReview` from the real reviews subcollection — never
/// editable directly) rendered as full/half/empty stars. Renders nothing for
/// an unrated product rather than a row of empty stars.
class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, this.count = 0, this.size = 14});
  final double rating;
  final int count;
  final double size;
  @override
  Widget build(BuildContext context) {
    if (rating <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star
                : rating >= i - 0.5
                ? Icons.star_half
                : Icons.star_border,
            size: size,
            color: AppTokens.accentGold,
          ),
        if (count > 0) ...[
          SizedBox(width: size * .3),
          Text(
            '($count)',
            style: TextStyle(fontSize: size * .85, color: AppTokens.textMuted),
          ),
        ],
      ],
    );
  }
}

void message(BuildContext context, Object text) => ScaffoldMessenger.of(context)
    .showSnackBar(
      SnackBar(content: Text(text.toString().replaceFirst('Bad state: ', ''))),
    );

class ProductArt extends StatelessWidget {
  const ProductArt(this.entry, {super.key, this.height = 160, this.width});
  final Entry entry;
  final double height;
  final double? width;
  @override
  Widget build(BuildContext context) {
    final icons = [
      Icons.eco_outlined,
      Icons.coffee_outlined,
      Icons.headphones_outlined,
      Icons.shopping_basket_outlined,
      Icons.plumbing,
      Icons.electrical_services,
      Icons.foundation,
      Icons.handyman_outlined,
    ];
    final index = int.tryParse(entry.id.replaceAll(RegExp(r'\D'), '')) ?? 0;
    final placeholder = Container(
      height: height,
      width: width ?? double.infinity,
      decoration: BoxDecoration(
        color: AppTokens.tintFor(index),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Center(
        child: Container(
          padding: EdgeInsets.all(height * .12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .6),
            shape: BoxShape.circle,
            boxShadow: AppTokens.shadowSoft,
          ),
          child: Icon(
            icons[index % icons.length],
            size: height * .4,
            color: AppTokens.accentFor(index),
          ),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: entry.text('imageUrl').isEmpty
          ? placeholder
          : Image.network(
              entry.text('imageUrl'),
              height: height,
              width: width ?? double.infinity,
              fit: BoxFit.contain,
              errorBuilder: (_, e, s) => placeholder,
            ),
    );
  }
}

String money(num value) =>
    '₹${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}';
