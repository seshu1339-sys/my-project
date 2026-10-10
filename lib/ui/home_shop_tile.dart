import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../services/strings.dart';
import 'shared.dart';

class HomeShopTile extends StatelessWidget {
  const HomeShopTile({
    super.key,
    required this.entry,
    required this.onTap,
    this.preview = false,
  });
  final Entry entry;
  final VoidCallback? onTap;
  final bool preview;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 270,
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductArt(entry, height: 94),
              const SizedBox(height: 12),
              Text(
                entry.text('name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                preview
                    ? 'Sample shop • coming soon'.tr(context)
                    : (entry.data['address'] == null
                          ? 'Explore this local shop'.tr(context)
                          : entry.text('address')),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.storefront_outlined,
                    size: 16,
                    color: Color(0xff176b50),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      (preview ? 'Preview' : 'Explore shop').tr(context),
                      style: const TextStyle(
                        color: Color(0xff176b50),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
