import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/search.dart';
import 'home_promotions.dart';
import 'home_widgets.dart';
import 'shared.dart';

class HomeContent extends StatelessWidget {
  const HomeContent({
    super.key,
    required this.store,
    required this.search,
    required this.searchService,
    required this.category,
    required this.mode,
    required this.onSearch,
    required this.onCategory,
    required this.onMode,
    required this.onLocation,
    required this.onAssistedSearch,
    required this.onProduct,
    required this.onAdd,
    required this.onShop,
    required this.onShops,
    required this.onAdmin,
    required this.onPromotion,
    required this.scroll,
    required this.categoriesKey,
    required this.productsKey,
  });
  final Store store;
  final TextEditingController search;
  final SmartSearch searchService;
  final String category, mode;
  final VoidCallback onSearch, onLocation, onShops, onAdmin;
  final ValueChanged<String> onCategory, onMode, onPromotion;
  final ValueChanged<bool> onAssistedSearch;
  final ValueChanged<Entry> onProduct, onAdd, onShop;
  final ScrollController scroll;
  final GlobalKey categoriesKey, productsKey;
  static final samples = demoCatalog();
  List<Entry> entries(String collection) => store.entries(collection).isEmpty
      ? samples[collection] ?? []
      : store.visible(collection);
  bool preview(String collection) => store.entries(collection).isEmpty;

  String tickerText(Entry entry) {
    final translations = entry.data['translations'];
    if (translations is Map && translations[store.language] != null) {
      return translations[store.language].toString();
    }
    final fallback = translations is Map
        ? translations['en']?.toString()
        : null;
    if (fallback != null && fallback.isNotEmpty) return fallback;
    final fields = [
      'importantNews',
      'importantUpdates',
      'customerNotices',
      'offers',
      'deliveryInformation',
      'serviceAnnouncements',
      'stateSpecificNotices',
      'generalAlerts',
    ];
    final messages = fields
        .map(entry.text)
        .where((value) => value.isNotEmpty)
        .toList();
    return messages.isEmpty ? entry.text('text') : messages.join('  •  ');
  }

  Widget product(Entry entry) => HomeProductTile(
    entry:
        !store.live &&
            entry.data['compareAtPrice'] == null &&
            entry.text('kind') != 'service'
        ? Entry(entry.id, {
            ...entry.data,
            'compareAtPrice': entry.number('price') + 50,
          })
        : entry,
    price: entry.price(store.pincode),
    preview: preview('products'),
    appearance: sectionConfig(store.entries('settings'), 'products'),
    onOpen: preview('products') ? null : () => onProduct(entry),
    onAdd:
        preview('products') ||
            entry.number('stock') <= (store.cart[entry.id] ?? 0)
        ? null
        : () => onAdd(entry),
  );

  Widget promotion(Entry entry) => PromoCard(
    entry: entry,
    onTap: () => preview('promotions')
        ? onLocation()
        : onPromotion(entry.text('target')),
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1100;
    final mobile = width < 700;
    final categories = entries('categories');
    final settings = store.entries('settings');
    final categoryAppearance = sectionConfig(settings, 'categories');
    final productAppearance = sectionConfig(settings, 'products');
    final offersAppearance = sectionConfig(settings, 'offers');
    final searchAppearance = sectionConfig(settings, 'search');
    final selected = <String>{category};
    for (var i = 0; i < categories.length; i++) {
      for (final c in categories) {
        if (category.isNotEmpty && selected.contains(c.text('parentId'))) {
          selected.add(c.id);
        }
      }
    }
    final filtered =
        search.text.isNotEmpty || category.isNotEmpty || mode != 'all';
    final products = searchService
        .text(entries('products'), search.text)
        .where(
          (p) =>
              (category.isEmpty || selected.contains(p.text('categoryId'))) &&
              (mode == 'all' || p.text('kind') == mode),
        )
        .toList();
    final featured = filtered
        ? products
        : products.where((p) => p.text('kind') != 'service').take(8).toList();
    final services = entries('products')
        .where((p) => p.text('kind') == 'service')
        .take(4)
        .toList();
    final promotions = entries('promotions');
    final carousel = promotions
        .where((p) => p.text('placement') == 'carousel')
        .toList();
    final ads = promotions.where((p) => p.text('placement') == 'ad').toList();
    final offers = promotions
        .where((p) => p.text('placement') == 'box')
        .toList();
    final located = store.pincode.isNotEmpty || store.latitude != null;
    final shops = preview('shops')
        ? entries('shops')
        : located
        ? store.nearby()
        : store.visible('shops');
    final scrolling = store
        .visible('settings')
        .firstWhere(
          (e) => e.id == 'scrollingText',
          orElse: () => const Entry('scrollingText', {}),
        );
    final tickerTextValue = tickerText(scrolling);
    final theme = store
        .entries('settings')
        .firstWhere(
          (e) => e.id == 'theme',
          orElse: () => const Entry('theme', {}),
        );
    final themeBackground = colorFromHex(
      theme.text('background'),
      Theme.of(context).scaffoldBackgroundColor,
    ).withValues(alpha: clampedNumber(theme, 'opacity', 1, 0, 1));
    final pageDecoration = theme.text('backgroundImage').isEmpty
        ? BoxDecoration(
            color: themeBackground,
            gradient: theme.text('gradientStart').isEmpty
                ? null
                : LinearGradient(
                    colors: [
                      colorFromHex(theme.text('gradientStart'), Colors.white),
                      colorFromHex(theme.text('gradientEnd'), Colors.white),
                    ],
                  ),
          )
        : BoxDecoration(
            color: themeBackground,
            image: DecorationImage(
              image: NetworkImage(theme.text('backgroundImage')),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(
                  alpha: 1 - clampedNumber(theme, 'brightness', 1, 0.2, 2) / 2,
                ),
                BlendMode.darken,
              ),
            ),
          );
    final adWidth = ads
        .map((p) => p.number('width', 260).clamp(180, 320).toDouble())
        .fold<double>(240, (a, b) => a > b ? a : b);
    final locationText = Text(
      located
          ? '${store.address.isEmpty ? 'Shopping in' : store.address} ${store.pincode}'
          : 'Your neighbourhood is waiting to be explored',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: Colors.black54),
    );
    final locationButton = TextButton(
      onPressed: onLocation,
      child: Text(located ? 'Change' : 'Set location'),
    );
    return Container(
      decoration: pageDecoration,
      child: SingleChildScrollView(
        controller: scroll,
        child: Column(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: mobile ? 16 : 32,
                    vertical: 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      mobile
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on_outlined,
                                      size: 18,
                                      color: Color(0xff176b50),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(child: locationText),
                                  ],
                                ),
                                locationButton,
                              ],
                            )
                          : Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 18,
                                  color: Color(0xff176b50),
                                ),
                                const SizedBox(width: 6),
                                Expanded(child: locationText),
                                locationButton,
                              ],
                            ),
                      const SizedBox(height: 10),
                      if (sectionVisible(searchAppearance))
                        Container(
                          decoration: entryDecoration(
                            searchAppearance,
                            fallback: Colors.white,
                            defaultRadius: 18,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: search,
                                  onChanged: (_) => onSearch(),
                                  style: sectionTextStyle(searchAppearance),
                                  decoration: InputDecoration(
                                    hintText: mobile
                                        ? 'Search local favourites'
                                        : 'Search products, services and everyday favourites',
                                    prefixIcon: const Icon(
                                      Icons.search_rounded,
                                    ),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    filled: false,
                                    suffixIcon: search.text.isNotEmpty
                                        ? IconButton(
                                            tooltip: 'Clear search',
                                            onPressed: () {
                                              search.clear();
                                              onSearch();
                                            },
                                            icon: const Icon(Icons.close),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Voice search',
                                onPressed: () => onAssistedSearch(false),
                                icon: const Icon(Icons.mic_none),
                              ),
                              IconButton(
                                tooltip: 'Image search',
                                onPressed: () => onAssistedSearch(true),
                                icon: const Icon(Icons.camera_alt_outlined),
                              ),
                              const SizedBox(width: 5),
                            ],
                          ),
                        ),
                      if (scrolling.active && tickerTextValue.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: TickerStrip(
                            text: tickerTextValue,
                            textColor: colorFromHex(
                              scrolling.text('textColor'),
                              Colors.white,
                            ),
                            backgroundColor: colorFromHex(
                              scrolling.text('backgroundColor'),
                              const Color(0xff174c38),
                            ),
                            fontFamily: scrolling.text('fontFamily'),
                            fontSize: scrolling.number('fontSize', 12),
                            fontWeight: FontWeight.values.firstWhere(
                              (weight) =>
                                  weight.value ==
                                  scrolling.number('fontWeight', 400).round(),
                              orElse: () => FontWeight.normal,
                            ),
                            speed: scrolling.number('speed', 70).clamp(10, 300),
                            height: scrolling
                                .number('height', 36)
                                .clamp(24, 120),
                            padding: scrolling
                                .number('padding', 9)
                                .clamp(0, 40),
                            reverse:
                                scrolling.text('direction', 'rtl') == 'ltr',
                            backgroundImage: scrolling.text('backgroundImage'),
                            brightness: scrolling.number('brightness', 1),
                            opacity: scrolling.number('opacity', 1),
                            borderColor: scrolling.text('borderColor'),
                            borderWidth: scrolling.number('borderWidth'),
                            radius: scrolling.number('radius'),
                            playback: scrolling.text('playback', 'running'),
                          ),
                        ),
                      if (!store.live || preview('products'))
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            !store.live
                                ? 'Demo marketplace • explore the experience'
                                : 'Preview collection • real products and prices will appear here soon',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xff596f5e),
                            ),
                          ),
                        ),
                      if (store.error.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            store.error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 22),
                      HeroCarousel(
                        entries: carousel,
                        reverse:
                            carousel.isNotEmpty &&
                            carousel.first.text('direction', 'rtl') == 'ltr',
                        speed: carousel.isEmpty
                            ? 600
                            : carousel.first.number('speed', 600),
                        onTap: (target) => preview('promotions')
                            ? onLocation()
                            : onPromotion(target),
                      ),
                      Wrap(
                        spacing: 24,
                        runSpacing: 12,
                        children: const [
                          _Benefit(
                            icon: Icons.storefront_outlined,
                            label: 'Discover local shops',
                          ),
                          _Benefit(
                            icon: Icons.location_on_outlined,
                            label: 'Prices for your area',
                          ),
                          _Benefit(
                            icon: Icons.handyman_outlined,
                            label: 'Everyday services',
                          ),
                        ],
                      ),
                      if (sectionVisible(categoryAppearance))
                        HomeSectionHeading(
                          key: categoriesKey,
                          title: 'Find your everyday',
                          subtitle: 'A little of everything, right around the corner.',
                          appearance: categoryAppearance,
                        ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            HomeCategoryTile(
                              entry: const Entry('all', {
                                'name': 'Explore all',
                              }),
                              selected: category.isEmpty,
                              onTap: () => onCategory(''),
                              index: 0,
                            ),
                            for (final (index, c) in categories.indexed)
                              Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: HomeCategoryTile(
                                  entry: c,
                                  selected: category == c.id,
                                  onTap: () => onCategory(c.id),
                                  index: index + 1,
                                  appearance: categoryAppearance,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                HomeSectionHeading(
                                  key: productsKey,
                                  title: filtered
                                      ? 'Your local finds'
                                      : 'Featured products',
                                  subtitle: filtered
                                      ? '${featured.length} matching finds'
                                      : 'Everyday essentials. A few new favourites.',
                                  action: filtered
                                      ? () {
                                          search.clear();
                                          onCategory('');
                                        }
                                      : null,
                                  actionLabel: 'Reset',
                                  appearance: productAppearance,
                                ),
                                if (filtered)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Wrap(
                                      spacing: 8,
                                      children: [
                                        for (final item in [
                                          ('all', 'Everything'),
                                          ('product', 'Products'),
                                          ('service', 'Services'),
                                        ])
                                          ChoiceChip(
                                            label: Text(item.$2),
                                            selected: mode == item.$1,
                                            onSelected: (_) => onMode(item.$1),
                                          ),
                                      ],
                                    ),
                                  ),
                                if (featured.isEmpty)
                                  const _Empty(
                                    text: 'No matching finds yet. Try another search or category.',
                                  )
                                else
                                  HomeProductGrid(
                                    entries: featured,
                                    itemBuilder: product,
                                  ),
                                if (!filtered) ...[
                                  HomeSectionHeading(
                                    title: 'Nearby shops',
                                    subtitle: located
                                        ? 'Shops serving your selected location.'
                                        : 'Set your location to discover shops near you.',
                                    action: located ? onShops : onLocation,
                                    actionLabel: located
                                        ? 'View all'
                                        : 'Locate me',
                                  ),
                                  if (shops.isEmpty)
                                    const _Empty(
                                      text: 'No shops found for this location yet. Try another pincode.',
                                    )
                                  else
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          for (final shop in shops.take(8))
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                right: 12,
                                              ),
                                              child: HomeShopTile(
                                                entry: shop,
                                                preview: preview('shops'),
                                                onTap: preview('shops')
                                                    ? null
                                                    : () => onShop(shop),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  HomeSectionHeading(
                                    title: 'A helping hand at home',
                                    subtitle: 'Plumbing, electrical work and more, from local professionals.',
                                    action: () => onMode('service'),
                                  ),
                                  if (services.isEmpty)
                                    const _Empty(
                                      text: 'Local services will appear here as they become available.',
                                    )
                                  else
                                    HomeProductGrid(
                                      entries: services,
                                      itemBuilder: product,
                                    ),
                                ],
                              ],
                            ),
                          ),
                          if (wide && ads.isNotEmpty) ...[
                            const SizedBox(width: 24),
                            SizedBox(
                              width: adWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const HomeSectionHeading(
                                    title: 'Local spotlight',
                                    subtitle: 'More from your neighbourhood.',
                                  ),
                                  for (final ad in ads)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: clampedNumber(
                                          ad,
                                          'spacing',
                                          16,
                                          0,
                                          80,
                                        ),
                                      ),
                                      child: SizedBox(
                                        width: ad
                                            .number('width', 260)
                                            .clamp(180, adWidth),
                                        child: promotion(ad),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (!filtered) ...[
                        HomeSectionHeading(
                          title: 'Best offers',
                          subtitle:
                              'A little more value, a little closer to home.',
                          appearance: offersAppearance,
                        ),
                        if (offers.isEmpty)
                          const _Empty(
                            text: 'Fresh offers are on their way. Check back soon.',
                          )
                        else
                          LayoutBuilder(
                            builder: (context, c) => Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                for (final offer in offers)
                                  Padding(
                                    padding: EdgeInsets.all(
                                      clampedNumber(offer, 'spacing', 0, 0, 48),
                                    ),
                                    child: SizedBox(
                                      width: c.maxWidth < 650
                                          ? c.maxWidth
                                          : (c.maxWidth - 16) / 2,
                                      child: promotion(offer),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (!wide && ads.isNotEmpty) ...[
                          const HomeSectionHeading(
                            title: 'Local spotlight',
                            subtitle: 'Discover something new.',
                          ),
                          for (final ad in ads)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: clampedNumber(ad, 'spacing', 12, 0, 80),
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                child: promotion(ad),
                              ),
                            ),
                        ],
                      ],
                      const SizedBox(height: 36),
                      const Divider(),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 32,
                        runSpacing: 16,
                        children: [
                          Text(
                            store.business.text(
                              'tagline',
                              'Good things. Close to home.',
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xff176b50),
                            ),
                          ),
                          if (store.business.text('address').isNotEmpty)
                            Text(store.business.text('address')),
                          if (store.business.text('phone').isNotEmpty)
                            Text(store.business.text('phone')),
                          TextButton.icon(
                            onPressed: onAdmin,
                            icon: const Icon(
                              Icons.dashboard_outlined,
                              size: 18,
                            ),
                            label: Text(
                              store.live
                                  ? 'Business admin'
                                  : 'Explore demo admin',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth.clamp(0, 320).toDouble()
          : 320.0;
      return SizedBox(
        width: width,
        child: Row(
          children: [
            Icon(icon, size: 17, color: const Color(0xff176b50)),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(text, style: const TextStyle(color: Colors.black54)),
  );
}
