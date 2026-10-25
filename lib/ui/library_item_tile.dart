import 'package:flutter/material.dart';

import '../domain/catalog.dart';

/// One item of the admin's Product Image Library (photo and name) to tap and choose; the chosen one is outlined and ticked.
/// Used where a vendor, or staff for a vendor, picks the items a shop sells.
class LibraryItemTile extends StatelessWidget {
  const LibraryItemTile({super.key, required this.item, required this.selected, required this.onTap});
  final Entry item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 104,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color : Colors.black12, width: selected ? 2.5 : 1),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 64,
              width: 88,
              child: item.text('imageUrl').isEmpty
                  ? const Icon(Icons.image_outlined)
                  : Image.network(item.text('imageUrl'), fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined)),
            ),
            const SizedBox(height: 4),
            Text(item.text('name'), maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            if (selected) Icon(Icons.check_circle, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}
