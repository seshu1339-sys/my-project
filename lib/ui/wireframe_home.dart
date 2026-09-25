import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/search.dart';
import 'details.dart';
import 'home_promotions.dart';
import 'home_widgets.dart';
import 'layout_settings.dart';
import 'responsive_header.dart';
import 'shared.dart';
import 'shop_map.dart';

/// The existing homepage composition, now constrained by its actual viewport.
class WireframeHome extends StatelessWidget {
  const WireframeHome({
    super.key,
    required this.store,
    required this.search,
    required this.searchService,
    required this.onSearch,
    required this.onLocation,
    required this.onAssistedSearch,
    required this.onServices,
    required this.onAccount,
    required this.onCart,
    required this.onProduct,
    required this.onAdd,
    required this.onCategory,
    required this.onPromotion,
    required this.scroll,
    required this.categoriesKey,
    required this.productsKey,
  });
  final Store store;
  final TextEditingController search;
  final SmartSearch searchService;
  final VoidCallback onSearch, onLocation, onServices, onAccount, onCart;
  final ValueChanged<bool> onAssistedSearch;
  final ValueChanged<Entry> onProduct, onAdd;
  final ValueChanged<String> onCategory, onPromotion;
  final ScrollController scroll;
  final GlobalKey categoriesKey, productsKey;

  @override
  Widget build(BuildContext context) {
    final settings = store.entries('settings');
    final categories = store
        .visible('categories')
        .where((e) => e.text('parentId').isEmpty)
        .toList();
    final products = searchService.text(
      store.visible('products'),
      search.text,
      store.visible('categories'),
    );
    final promotions = store.visible('promotions');
    final offers = promotions
        .where((e) => e.text('placement') == 'carousel')
        .toList();
    final ads = promotions.where((e) => e.text('placement') == 'ad').toList();
    final boxes = promotions
        .where((e) => e.text('placement') == 'box')
        .toList();
    final tickerSettings = store
        .visible('settings')
        .where((e) => e.id == 'scrollingText')
        .firstOrNull;
    final tickerPromo = promotions
        .where((e) => e.text('placement') == 'ticker')
        .firstOrNull;
    final noticeLayout = layoutFor(context, settings, 'notice');
    final ticker = Entry('notice', {
      ...?tickerSettings?.data,
      ...noticeLayout.entry.data,
    });
    final translations = ticker.data['translations'];
    final notices = [
      'importantNews',
      'importantUpdates',
      'customerNotices',
      'offers',
      'deliveryInformation',
      'serviceAnnouncements',
      'stateSpecificNotices',
      'generalAlerts',
    ].map(ticker.text).where((s) => s.isNotEmpty).join('  •  ');
    final text = translations is Map && translations[store.language] != null
        ? translations[store.language].toString()
        : notices.isNotEmpty
        ? notices
        : ticker.text('text').isNotEmpty
        ? ticker.text('text')
        : tickerPromo?.text('name') ?? '';
    final tickerSection = text.isNotEmpty && noticeLayout.visible
        ? LayoutSection(
            layout: noticeLayout,
            child: TickerStrip(
              text: text,
              height: ComponentLayout(ticker, noticeLayout.viewport).height(40, floor: 32),
              fontSize: ComponentLayout(ticker, noticeLayout.viewport).font(14),
              fontFamily: ticker.text('fontFamily'),
              fontWeight: FontWeight.values.firstWhere(
                (w) => w.value == ticker.number('fontWeight', 400),
                orElse: () => FontWeight.normal,
              ),
              speed: clampedNumber(ticker, 'speed', 70, 10, 300),
              padding: clampedNumber(ticker, 'padding', 8, 0, 48),
              reverse: ticker.text('direction', 'rtl') == 'ltr',
              backgroundColor: colorFromHex(
                ticker.text('backgroundColor'),
                const Color(0xff174c38),
              ),
              textColor: colorFromHex(ticker.text('textColor'), Colors.white),
              backgroundImage: ticker.text('backgroundImage'),
              brightness: ticker.number('brightness', 1),
              opacity: ticker.number('opacity', 1),
              radius: clampedNumber(ticker, 'radius', 8, 0, 80),
              borderColor: ticker.text('borderColor'),
              borderWidth: clampedNumber(ticker, 'borderWidth', 0, 0, 8),
              playback: ticker.text('playback', 'running'),
            ),
          )
        : const SizedBox.shrink();
    final page = layoutFor(context, settings, 'background');
    final categoryLayout = layoutFor(context, settings, 'categories');
    final productLayout = layoutFor(context, settings, 'products');
    final adLayout = layoutFor(context, settings, 'ads');
    final nearby = layoutFor(context, settings, 'nearby');
    final located = store.pincode.isNotEmpty || store.latitude != null;
    final shops = located ? store.nearby() : store.visible('shops');
    final theme =
        settings.where((e) => e.id == 'theme').firstOrNull ??
        const Entry('', {});
    return Container(
      decoration: entryDecoration(
        Entry('background', {
          ...theme.data,
          'backgroundColor': theme.text('background'),
          ...page.entry.data,
        }),
        fallback: Theme.of(context).scaffoldBackgroundColor,
        defaultRadius: 0,
      ),
      child: SingleChildScrollView(
        controller: scroll,
        child: Padding(
          padding: EdgeInsets.all(
            page
                .n(
                  'padding',
                  MediaQuery.sizeOf(context).width < 700 ? 12 : 24,
                  0,
                  48,
                )
                .clamp(0, MediaQuery.sizeOf(context).width / 24),
          ),
          child: LayoutSection(
            layout: ComponentLayout(
              Entry(page.entry.id, {...page.entry.data, 'padding': 0}),
              page.viewport,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ResponsiveHeader(
                  store: store,
                  search: search,
                  onSearch: onSearch,
                  onLocation: onLocation,
                  onServices: onServices,
                  onAccount: onAccount,
                  onCart: onCart,
                  onAssistedSearch: onAssistedSearch,
                ),
                if (!store.live)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Demo marketplace • explore the experience'),
                  ),
                if (store.error.isNotEmpty)
                  Text(
                    store.error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (store.catalogWarning.isNotEmpty)
                  Text(
                    store.catalogWarning,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                SizedBox(height: page.gap),
                LayoutBuilder(
                  builder: (context, c) {
                    final railWidth = adLayout.width(
                      c.maxWidth * .28,
                      fallback: (c.maxWidth * .22).clamp(230, 380),
                    );
                    final railHasContent =
                        (adLayout.visible && ads.isNotEmpty) ||
                        (layoutFor(context, settings, 'boxes').visible &&
                            boxes.isNotEmpty);
                    final wide = c.maxWidth >= 1100 && railHasContent;
                    // Ads and feature/promo boxes share the same vertical
                    // side rail, stacked together, rather than boxes
                    // repeating as a separate full-width section below.
                    final rail = Column(
                      children: [
                        if (adLayout.visible)
                          LayoutSection(
                            layout: adLayout,
                            child: Column(
                              children: [
                                for (final ad in ads)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      bottom: ad
                                          .number('spacing', adLayout.gap)
                                          .clamp(0, 64),
                                    ),
                                    child: ScheduledPromo(
                                      entry: Entry(ad.id, {
                                        ...adLayout.entry.data,
                                        ...ad.data,
                                      }),
                                      onTap: () =>
                                          onPromotion(ad.text('target')),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (boxes.isNotEmpty)
                          LayoutSection(
                            layout: layoutFor(context, settings, 'boxes'),
                            child: Column(
                              children: [
                                for (final box in boxes)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      bottom: clampedNumber(
                                        box,
                                        'spacing',
                                        layoutFor(
                                          context,
                                          settings,
                                          'boxes',
                                        ).gap,
                                        0,
                                        64,
                                      ),
                                    ),
                                    child: ScheduledPromo(
                                      entry: Entry(box.id, {
                                        ...sectionConfig(
                                          settings,
                                          'boxes',
                                        ).data,
                                        ...box.data,
                                      }),
                                      onTap: () =>
                                          onPromotion(box.text('target')),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    );
                    final reorderedSections = <String, Widget>{
                      'notice': tickerSection,
                      'promo': LayoutSection(
                        layout: layoutFor(context, settings, 'promo'),
                        child: HeroCarousel(
                          entries: offers,
                          appearance: sectionConfig(settings, 'promo'),
                          onTap: onPromotion,
                          reverse:
                              offers.isNotEmpty &&
                              offers.first.text('direction', 'rtl') == 'ltr',
                          speed: offers.isEmpty
                              ? 600
                              : offers.first.number('speed', 600),
                        ),
                      ),
                      'categories': LayoutSection(
                        layout: ComponentLayout(
                          Entry(categoryLayout.entry.id, {
                            'visible': categoryLayout.visible,
                            'margin': categoryLayout.margin,
                          }),
                          categoryLayout.viewport,
                        ),
                        child: Column(
                          key: categoriesKey,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            HomeSectionHeading(
                              title: 'Categories',
                              subtitle: 'Browse your everyday essentials',
                              appearance: categoryLayout.entry,
                            ),
                            if (categories.isEmpty)
                              const Text(
                                'Categories will appear here when available.',
                              ),
                            LayoutBuilder(
                              builder: (context, grid) {
                                final columns = categoryLayout.columns(
                                  grid.maxWidth,
                                  preferred: 170,
                                  minimum: 125,
                                );
                                final tileWidth =
                                    (grid.maxWidth -
                                        (columns - 1) * categoryLayout.gap) /
                                    columns;
                                return Wrap(
                                  spacing: categoryLayout.gap,
                                  runSpacing: categoryLayout.gap,
                                  children: [
                                    for (final (i, category)
                                        in categories.indexed)
                                      SizedBox(
                                        width: tileWidth,
                                        height: categoryLayout.height(
                                          tileWidth,
                                          floor: tileWidth,
                                        ),
                                        child: HomeCategoryTile(
                                          entry: category,
                                          selected: false,
                                          onTap: () =>
                                              onCategory(category.id),
                                          index: i,
                                          appearance: categoryLayout.styled(
                                            context,
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      'popular': LayoutSection(
                        layout: layoutFor(context, settings, 'popular'),
                        child: Column(
                          key: productsKey,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            HomeSectionHeading(
                              title: search.text.isEmpty
                                  ? 'Popular Products'
                                  : 'Search results',
                              subtitle: search.text.isEmpty
                                  ? 'Products and services from your neighbourhood'
                                  : '${products.length} matching items',
                              appearance: sectionConfig(settings, 'popular'),
                            ),
                            if (products.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'No matching products. Try another search.',
                                ),
                              ),
                            if (productLayout.visible)
                              HomeProductGrid(
                                entries: products,
                                appearance: productLayout.entry,
                                itemBuilder: (entry) => HomeProductTile(
                                  entry: entry,
                                  price: entry.price(store.pincode),
                                  appearance: productLayout.styled(
                                    context,
                                    fontSize: 16,
                                  ),
                                  onOpen: () => onProduct(entry),
                                  onAdd:
                                      entry.number('stock') >
                                          (store.cart[entry.id] ?? 0)
                                      ? () => onAdd(entry)
                                      : null,
                                ),
                              ),
                          ],
                        ),
                      ),
                    };
                    final orderedSectionKeys = [...reorderableHomeSections]
                      ..sort(
                        (a, b) => sectionOrder(
                          settings,
                          a,
                        ).compareTo(sectionOrder(settings, b)),
                      );
                    final main = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final key in orderedSectionKeys)
                          reorderedSections[key]!,
                        LayoutSection(
                          layout: nearby,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              HomeSectionHeading(
                                title: 'Nearby shops',
                                subtitle: located
                                    ? 'Shops serving your selected location'
                                    : 'Choose a location or browse available shops',
                                action: onLocation,
                                actionLabel: located
                                    ? 'Change location'
                                    : 'Set location',
                                appearance: nearby.entry,
                              ),
                              if (shops.isNotEmpty && located)
                                ShopMap(
                                  key: ValueKey(
                                    '${store.pincode}-${store.latitude}-${shops.map((e) => e.id).join(',')}',
                                  ),
                                  shops: shops,
                                  latitude: store.latitude,
                                  longitude: store.longitude,
                                  height: nearby.height(320, floor: 180),
                                  onShop: (shop) => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          ShopPage(store: store, shop: shop),
                                    ),
                                  ),
                                ),
                              if (shops.isEmpty)
                                const Text(
                                  'No nearby shops found. You can change your pincode without enabling GPS.',
                                ),
                              for (final shop in shops)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.storefront_outlined,
                                  ),
                                  title: Text(shop.text('name')),
                                  subtitle: Text(
                                    '${shop.text('address')} • ${shop.text('phone')} ${store.latitude == null ? '' : '• ${distanceKm(store.latitude!, store.longitude!, shop.number('latitude'), shop.number('longitude')).toStringAsFixed(1)} km'}',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          ShopPage(store: store, shop: shop),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                    return wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: main),
                              SizedBox(width: page.gap),
                              SizedBox(width: railWidth, child: rail),
                            ],
                          )
                        : Column(
                            children: [main, if (railHasContent) rail],
                          );
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
