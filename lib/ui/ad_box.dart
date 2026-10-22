import 'package:flutter/material.dart';

import '../domain/ads.dart';
import '../domain/catalog.dart';
import 'shared.dart';

/// One ad, drawn the same way wherever it appears (home column, phone pager, "Offers & Ads" page): image full box, text only, or
/// image + text, with a small "Ad" label, an optional badge and coupon, the common corners / border / shadow, and a tap action.
class AdBox extends StatelessWidget {
  const AdBox({super.key, required this.ad, required this.config, this.onTap, this.mobile = false});
  final Entry ad;
  final AdsConfig config;
  final ValueChanged<Entry>? onTap;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final type = ad.text('contentType', ad.text('imageUrl').isEmpty ? 'text' : 'image');
    final image = mobile && ad.text('mobileImageUrl').isNotEmpty ? ad.text('mobileImageUrl') : ad.text('imageUrl');
    final background = colorFromHex(ad.text('backgroundColor', config.backgroundColor), Theme.of(context).colorScheme.primaryContainer);
    final textColor = colorFromHex(ad.text('textColor', config.textColor), Colors.black87);
    final showImage = type != 'text' && image.isNotEmpty;
    final showText = type != 'image' || image.isEmpty;
    final overImage = showImage && showText;
    final title = ad.text('title', ad.text('name'));
    final body = ad.text('text', ad.text('description'));
    final textStyleColor = overImage ? Colors.white : textColor;
    final border = config.borderWidth > 0
        ? Border.all(color: colorFromHex(config.borderColor, const Color(0xFFD32F2F)), width: config.borderWidth)
        : null;
    final radius = BorderRadius.circular(config.radius);
    return DecoratedBox(
      key: ValueKey('ad-${ad.id}'),
      decoration: BoxDecoration(
        borderRadius: radius,
        border: border,
        boxShadow: config.shadow > 0
            ? [BoxShadow(color: Colors.black.withValues(alpha: config.shadow), blurRadius: 10, offset: const Offset(0, 3))]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          color: background,
          child: InkWell(
            onTap: onTap == null ? null : () => onTap!(ad),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (showImage) Image.network(image, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                if (overImage)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xAA000000)]),
                    ),
                  ),
                if (showText && (title.isNotEmpty || body.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisAlignment: overImage ? MainAxisAlignment.end : MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title.isNotEmpty)
                          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: textStyleColor, fontWeight: FontWeight.w800, fontSize: 18)),
                        if (body.isNotEmpty)
                          Text(body, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: textStyleColor, fontSize: 13)),
                      ],
                    ),
                  ),
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    key: const ValueKey('ad-label'),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                    child: Text(config.label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ),
                if (ad.text('badge').isNotEmpty)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFD32F2F), borderRadius: BorderRadius.circular(10)),
                      child: Text(ad.text('badge'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
                if (ad.text('coupon').isNotEmpty)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.black26)),
                      child: Text('Code: ${ad.text('coupon')}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
