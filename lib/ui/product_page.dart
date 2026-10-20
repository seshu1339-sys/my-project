import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/strings.dart';
import 'cart_page.dart';
import 'design_tokens.dart';
import 'layout_settings.dart';
import 'responsive_header.dart';
import 'reviews.dart';
import 'shared.dart';
import 'shop_page.dart';

class ProductPage extends StatefulWidget {
  const ProductPage({super.key, required this.store, required this.entry});
  final Store store;
  final Entry entry;
  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  Store get store => widget.store;
  Entry get entry => widget.entry;
  String? selectedVariant;
  @override
  void initState() {
    super.initState();
    store.trackItemView(entry);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final p = store.product(entry.id) ?? entry;
      final shop = store
          .visible('shops')
          .where((s) => s.id == p.text('shopId'))
          .firstOrNull;
      final images = [
        p.text('imageUrl'),
        if (p.data['images'] is List)
          ...(p.data['images'] as List).map((e) => e.toString()),
      ];
      final variants = p.data['variants'] is List
          ? (p.data['variants'] as List).map((item) => item.toString()).toList()
          : <String>[];
      final related = store
          .visible('products')
          .where(
            (item) =>
                item.id != p.id &&
                item.text('categoryId') == p.text('categoryId'),
          )
          .take(4)
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: Text(p.text('name')),
          actions: [
            pageIconButton(
              context,
              layout: layoutFor(
                context,
                store.entries('settings'),
                'productPageShareIcon',
              ),
              icon: Icons.share_outlined,
              tooltip: 'Share product'.tr(context),
              onPressed: () => _share(context, p),
            ),
            pageIconButton(
              context,
              layout: layoutFor(
                context,
                store.entries('settings'),
                'productPageWishlistIcon',
              ),
              icon: store.wishlist.contains(p.id)
                  ? Icons.favorite
                  : Icons.favorite_border,
              tooltip: 'Wishlist'.tr(context),
              onPressed: () => _toggleWishlist(context, p),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                SizedBox(
                  height: 300,
                  child: PageView(
                    children: [
                      for (final url in images)
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: ProductArt(
                            Entry(p.id, {...p.data, 'imageUrl': url}),
                            height: 300,
                          ),
                        ),
                    ],
                  ),
                ),
                if (images.length > 1)
                  Center(child: Text('Swipe to view {n} images'.tr(context, {'n': '${images.length}'}))),
                const SizedBox(height: 24),
                Text(
                  p.text('name'),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (p.number('avgRating') > 0) ...[
                  const SizedBox(height: 8),
                  RatingStars(
                    rating: p.number('avgRating'),
                    count: p.number('reviewCount').toInt(),
                    size: 18,
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  '${money(p.price(store.pincode))} / ${p.text('unit', 'each').tr(context)}',
                  style: const TextStyle(
                    fontSize: 24,
                    color: AppTokens.primary,
                  ),
                ),
                if (store.pincode.isEmpty)
                  Text('Base price shown. Set a pincode on the home page for local pricing.'.tr(context)),
                if (p.number('compareAtPrice') > p.price(store.pincode))
                  Text(
                    'Regular {regular}  •  Offer {offer}'.tr(context, {
                      'regular': money(p.number('compareAtPrice')),
                      'offer': money(p.price(store.pincode)),
                    }),
                    style: const TextStyle(color: Colors.black54),
                  ),
                if (variants.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedVariant,
                      decoration: InputDecoration(labelText: 'Variant'.tr(context)),
                      items: variants
                          .map(
                            (variant) => DropdownMenuItem(
                              value: variant,
                              child: Text(variant),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => selectedVariant = value),
                    ),
                  ),
                if (p.text('size').isNotEmpty || p.text('color').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      [
                        if (p.text('size').isNotEmpty)
                          'Size: {size}'.tr(context, {'size': p.text('size')}),
                        if (p.text('color').isNotEmpty)
                          'Color: {color}'.tr(context, {'color': p.text('color')}),
                      ].join('  '),
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  p.text('description'),
                  style: const TextStyle(fontSize: 17, height: 1.6),
                ),
                const SizedBox(height: 20),
                Builder(
                  builder: (context) {
                    final addLayout = layoutFor(
                      context,
                      store.entries('settings'),
                      'productPageAddButton',
                    );
                    final buyLayout = layoutFor(
                      context,
                      store.entries('settings'),
                      'productPageBuyButton',
                    );
                    final addColor = addLayout.entry.text('backgroundColor');
                    final addTextColor = addLayout.entry.text('textColor');
                    final buyColor = buyLayout.entry.text('borderColor');
                    final buyTextColor = buyLayout.entry.text('textColor');
                    return Row(
                      children: [
                        if (addLayout.visible)
                          Expanded(
                            child: FilledButton.icon(
                              style: addColor.isEmpty && addTextColor.isEmpty
                                  ? null
                                  : FilledButton.styleFrom(
                                      backgroundColor: addColor.isEmpty
                                          ? null
                                          : colorFromHex(
                                              addColor,
                                              AppTokens.primary,
                                            ),
                                      foregroundColor: addTextColor.isEmpty
                                          ? null
                                          : colorFromHex(
                                              addTextColor,
                                              Colors.white,
                                            ),
                                    ),
                              onPressed: _canAdd(p)
                                  ? () {
                                      store.add(p);
                                      message(context, 'Added to bag'.tr(context));
                                    }
                                  : null,
                              icon: const Icon(Icons.shopping_bag_outlined),
                              label: Text(
                                p.number('stock') <= 0
                                    ? 'Currently unavailable'.tr(context)
                                    : addLayout.entry
                                          .text('text', 'Add to bag')
                                          .tr(context),
                                style: overrideTextStyle(addLayout.entry),
                              ),
                            ),
                          ),
                        if (addLayout.visible && buyLayout.visible)
                          const SizedBox(width: 12),
                        if (buyLayout.visible)
                          Expanded(
                            child: OutlinedButton(
                              style: buyColor.isEmpty && buyTextColor.isEmpty
                                  ? null
                                  : OutlinedButton.styleFrom(
                                      side: buyColor.isEmpty
                                          ? null
                                          : BorderSide(
                                              color: colorFromHex(
                                                buyColor,
                                                AppTokens.primary,
                                              ),
                                            ),
                                      foregroundColor: buyTextColor.isEmpty
                                          ? null
                                          : colorFromHex(
                                              buyTextColor,
                                              AppTokens.primary,
                                            ),
                                    ),
                              onPressed: _canAdd(p)
                                  ? () {
                                      store.add(p);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              CartPage(store: store),
                                        ),
                                      );
                                    }
                                  : null,
                              child: Text(
                                buyLayout.entry
                                    .text('text', 'Buy now')
                                    .tr(context),
                                style: overrideTextStyle(buyLayout.entry),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                if (shop != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.storefront),
                    title: Text(shop.text('name')),
                    subtitle: Text('View shop & directions'.tr(context)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ShopPage(store: store, shop: shop),
                      ),
                    ),
                  ),
                if (shop != null && p.text('kind') == 'service') ...[
                  Text(shop.text('address')),
                  ProductArt(shop, height: 140),
                  ContactActions(
                    phone: shop.text('phone'),
                    whatsapp: shop.text('whatsapp'),
                  ),
                ],
                const Divider(height: 40),
                if (related.isNotEmpty) ...[
                  pageHeadingText(
                    context,
                    layout: layoutFor(
                      context,
                      store.entries('settings'),
                      'productPageRelatedHeading',
                    ),
                    defaultText: 'Related products',
                  ),
                  for (final item in related)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: SizedBox(
                        width: 64,
                        child: ProductArt(item, height: 56),
                      ),
                      title: Text(item.text('name')),
                      subtitle: Text(money(item.price(store.pincode))),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ProductPage(store: store, entry: item),
                        ),
                      ),
                    ),
                ],
                Reviews(store: store, productId: p.id),
              ],
            ),
          ),
        ),
      );
    },
  );

  bool _canAdd(Entry product) =>
      product.active && product.number('stock') > (store.cart[product.id] ?? 0);

  Future<void> _toggleWishlist(BuildContext context, Entry product) async {
    try {
      await store.toggleWishlist(product.id);
      if (context.mounted) {
        message(context, 'Wishlist updated'.tr(context));
      }
    } catch (e) {
      if (context.mounted) {
        message(context, e);
      }
    }
  }

  Future<void> _share(BuildContext context, Entry product) async {
    await Clipboard.setData(
      ClipboardData(
        text: 'Check out {name}'.tr(context, {'name': product.text('name')}),
      ),
    );
    if (context.mounted) {
      message(context, 'Product details copied'.tr(context));
    }
  }
}
