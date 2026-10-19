import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/strings.dart';
import 'design_tokens.dart';
import 'layout_settings.dart';
import 'product_page.dart';
import 'responsive_header.dart';
import 'shared.dart';
import 'shop_map.dart';

class ShopPage extends StatelessWidget {
  const ShopPage({super.key, required this.store, required this.shop});
  final Store store;
  final Entry shop;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(shop.text('name'))),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              shop.text('name'),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
            if (shop.text('shopCode').isNotEmpty) Text('Shop ID: ${shop.text('shopCode')}'),
            const SizedBox(height: 12),
            Text(shop.text('description')),
            Text('${shop.text('address')} • ${shop.text('pincode')}'),
            Text(shop.text('phone')),
            ContactActions(
              phone: shop.text('phone'),
              whatsapp: shop.text('whatsapp'),
            ),
            const SizedBox(height: 20),
            ShopMap(
              shops: [shop],
              latitude: store.latitude,
              longitude: store.longitude,
            ),
            const SizedBox(height: 16),
            _ShopPhotos(store: store, shopId: shop.id),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final layout = layoutFor(context, store.entries('settings'), 'shopPageDirectionsButton');
                if (!layout.visible) return const SizedBox.shrink();
                final backgroundColor = layout.entry.text('backgroundColor');
                final textColor = layout.entry.text('textColor');
                return FilledButton.icon(
                  style: backgroundColor.isEmpty && textColor.isEmpty
                      ? null
                      : FilledButton.styleFrom(
                          backgroundColor: backgroundColor.isEmpty ? null : colorFromHex(backgroundColor, AppTokens.primary),
                          foregroundColor: textColor.isEmpty ? null : colorFromHex(textColor, Colors.white),
                        ),
                  onPressed: () async {
                    final uri = Uri.https('www.google.com', '/maps/dir/', {
                      'api': '1',
                      'destination': '${shop.number('latitude')},${shop.number('longitude')}',
                      if (store.latitude != null) 'origin': '${store.latitude},${store.longitude}',
                    });
                    try {
                      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
                        message(context, 'Could not open directions');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        message(context, 'Could not open directions');
                      }
                    }
                  },
                  icon: const Icon(Icons.directions),
                  label: Text(layout.entry.text('text', 'Get directions').tr(context)),
                );
              },
            ),
            const SizedBox(height: 24),
            pageHeadingText(
              context,
              layout: layoutFor(context, store.entries('settings'), 'shopPageRelatedHeading'),
              defaultText: 'From this shop',
            ),
            for (final p
                in store
                    .visible('products')
                    .where((e) => e.text('shopId') == shop.id))
              ListTile(
                title: Text(p.text('name')),
                subtitle: Text(money(p.price(store.pincode))),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ProductPage(store: store, entry: p),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Only shop photos the admin has approved are ever shown here — a pending or rejected
/// submission stays invisible to customers.
class _ShopPhotos extends StatelessWidget {
  const _ShopPhotos({required this.store, required this.shopId});
  final Store store;
  final String shopId;
  @override
  Widget build(BuildContext context) {
    final approved = store
        .entries('vendorShopPhotos')
        .where((e) => e.text('shopId') == shopId && e.text('status') == 'approved')
        .toList();
    if (approved.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final photo in approved)
        FutureBuilder<String>(
          future: FirebaseStorage.instance.ref(photo.text('path')).getDownloadURL(),
          builder: (context, snapshot) => snapshot.hasData
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(snapshot.data!, width: 140, height: 100, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                )
              : const SizedBox(width: 140, height: 100),
        ),
    ]);
  }
}
