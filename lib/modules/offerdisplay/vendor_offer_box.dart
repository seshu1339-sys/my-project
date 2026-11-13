import 'package:flutter/material.dart';

/// A vendor's offer in a box: the box's colour as a frame, the item's photo on top, the price below and the vendor's short text (if any).
class VendorOfferBox extends StatelessWidget {
  const VendorOfferBox({super.key, required this.photoUrl, required this.price, required this.frame, required this.colour, required this.radius, required this.onTap, this.note = ''});
  final String photoUrl, price;
  // The vendor's short offer text (owner, 13 Nov 2026), under the price; empty shows nothing.
  final String note;

  /// The box's own decoration, so it matches the boxes beside it.
  final Decoration frame;
  final Color colour;
  final double radius;
  final VoidCallback onTap;

  static const frameWidth = 5.0;

  @override
  Widget build(BuildContext context) {
    final placeholder = const ColoredBox(color: Color(0xFFF3F4F6), child: Center(child: Icon(Icons.shopping_basket_outlined, color: Colors.black38)));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: frame,
          padding: const EdgeInsets.all(frameWidth),
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius)),
            padding: const EdgeInsets.all(4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: ClipRRect(
                  key: const ValueKey('vendor-offer-photo'),
                  borderRadius: BorderRadius.circular(radius > 4 ? radius - 4 : 2),
                  child: photoUrl.isEmpty ? placeholder : Image.network(photoUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(price, key: const ValueKey('vendor-offer-price'), style: TextStyle(color: colour, fontWeight: FontWeight.w900, fontSize: 18)),
              ),
              if (note.isNotEmpty)
                Text(note, key: const ValueKey('vendor-offer-note'), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.black87)),
            ]),
          ),
        ),
      ),
    );
  }
}
