import 'package:flutter/material.dart';

import '../domain/catalog.dart';

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
) => entry.number(key, fallback).clamp(min, max).toDouble();

Entry sectionConfig(List<Entry> settings, String section) =>
    settings.firstWhere(
      (entry) => entry.id == 'section_$section',
      orElse: () => const Entry('', {}),
    );

bool sectionVisible(Entry config) =>
    config.id.isEmpty || config.data['visible'] != 'false';

TextStyle sectionTextStyle(
  Entry config, {
  double fontSize = 14,
  FontWeight fontWeight = FontWeight.normal,
}) => TextStyle(
  color: colorFromHex(config.text('textColor'), Colors.black87),
  fontFamily: config.text('fontFamily').isEmpty
      ? null
      : config.text('fontFamily'),
  fontSize: clampedNumber(config, 'fontSize', fontSize, 8, 72),
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
  final background = Color.lerp(
    Colors.black,
    base,
    brightness.clamp(0, 1),
  )!.withValues(alpha: opacity);
  final shadow = shadowFromEntry(entry);
  final imageUrl = entry.text('backgroundImage');
  return BoxDecoration(
    color: background,
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

void message(BuildContext context, Object text) => ScaffoldMessenger.of(context)
    .showSnackBar(
      SnackBar(content: Text(text.toString().replaceFirst('Bad state: ', ''))),
    );

class ProductArt extends StatelessWidget {
  const ProductArt(this.entry, {super.key, this.height = 160});
  final Entry entry;
  final double height;
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
      width: double.infinity,
      decoration: BoxDecoration(
        color: [
          const Color(0xffe8efdc),
          const Color(0xfff2e9dd),
          const Color(0xffe4e9f1),
          const Color(0xfff5e7ce),
        ][index % 4],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Container(
          padding: EdgeInsets.all(height * .12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .5),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xff47624f).withValues(alpha: .08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            icons[index % icons.length],
            size: height * .4,
            color: const Color(0xff47624f),
          ),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: entry.text('imageUrl').isEmpty
          ? placeholder
          : Image.network(
              entry.text('imageUrl'),
              height: height,
              width: double.infinity,
              fit: BoxFit.cover,
              cacheWidth: (height * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              errorBuilder: (_, e, s) => placeholder,
            ),
    );
  }
}

String money(num value) =>
    '₹${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}';
