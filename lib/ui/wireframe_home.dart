import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/towns.dart';
import '../services/search.dart';
import '../services/strings.dart';
import 'home_category_product_strip.dart';
import 'home_footer_badges.dart';
import 'home_no_offers.dart';
import 'home_local_services_section.dart';
import 'home_nearby_section.dart';
import 'home_popular_section.dart';
import 'home_promotions.dart';
import 'home_ticker_section.dart';
import 'layout_settings.dart';
import 'animation_settings.dart';
import 'quick_fresh.dart';
import 'responsive_header.dart';
import 'photo_library_page.dart';
import '../modules/services/services_page.dart';
import '../domain/radius.dart';
import 'home_section_config.dart';
import 'home_strip_band.dart';
import '../domain/right_boxes.dart';
import 'right_ad_boxes.dart';
import 'shared.dart';

/// The customer homepage composition root. Computes the shared data each
/// section needs (catalog slices, layout configs, the admin-configurable
/// section order), then hands each section's own widget file a small,
/// explicit set of parameters — see home_ticker_section.dart,
/// home_categories_section.dart, home_popular_section.dart,
/// home_local_services_section.dart, home_nearby_section.dart and
/// home_ad_rail.dart for each section's own logic. What stays here is
/// specifically the composition concerns that only make sense at this
/// level: section ordering/splicing and the wide/narrow responsive split.
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
    // The admin's editor preview shows every offer/ad whatever the location rules.
    this.showAllLocations = false,
    this.wrapSection = _identitySection,
    this.wrapPromoItem = _identityPromoItem,
    this.wrapCategoryItem = _identityCategoryItem,
    this.wrapProductItem = _identityProductItem,
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
  final bool showAllLocations;
  // Lets the admin Visual Editor overlay click-to-select/dim behavior onto
  // individual sections without this widget knowing anything about editing —
  // every real customer render (the only caller that omits this) gets this
  // exact no-op and therefore byte-identical output to before this existed.
  final Widget Function(String sectionKey, Widget child) wrapSection;
  static Widget _identitySection(String sectionKey, Widget child) => child;
  // Same hook as wrapSection, but per individual ad/box promotion rather
  // than per whole section — see HomeAdRail's own wrapItem doc comment for
  // why a single section-level wrap isn't enough for the ad/box rail.
  final Widget Function(Entry entry, String kind, Widget child) wrapPromoItem;
  static Widget _identityPromoItem(Entry entry, String kind, Widget child) =>
      child;
  // Same hook, for one individual category tile.
  final Widget Function(Entry category, Widget child) wrapCategoryItem;
  static Widget _identityCategoryItem(Entry category, Widget child) => child;
  // Same hook, for one individual product card inside the Fresh Fruits &
  // Vegetables cross-sell strip.
  final Widget Function(Entry product, Widget child) wrapProductItem;
  static Widget _identityProductItem(Entry product, Widget child) => child;

  @override
  Widget build(BuildContext context) {
    final settings = store.entries('settings');
    final categories = store
        .visible('categories')
        .where((e) => e.text('parentId').isEmpty)
        .toList();
    // Service-kind entries now get their own dedicated Local Services
    // section below (with the same search-box filtering), so Popular
    // Products no longer duplicates them — searching still finds a service
    // by name, just rendered in the Local Services section instead.
    final products = searchService
        .text(
          store.visibleProducts(all: showAllLocations),
          search.text,
          store.visible('categories'),
        )
        .where((e) => e.text('kind') != 'service')
        .toList();
    final promotions = store
        .visible('promotions')
        .where(
          (e) => promotionReaches(
            e,
            customerPincode: store.pincode,
            customerLatitude: store.latitude,
            customerLongitude: store.longitude,
          ),
        )
        .toList();
    // Location-tagged offers/ads: with a town chosen, only the ones listing it
    // (else the general, all-town ones) -- see promotionsForTown.
    TownOffers forTown(String placement) => promotionsForTown(
      promotions.where((e) => e.text('placement') == placement).toList(),
      store.town,
      district: store.district,
      state: store.state,
      showAll: showAllLocations,
    );
    final offersForTown = forTown('carousel');
    final offers = offersForTown.entries;
    final localServices = localServiceEntries(
      store,
      searchService,
      search.text,
    );
    // Resolved purely from the already-loaded shops catalog (no new
    // Firestore read) so product cards can show the selling shop's name.
    final shopNameById = {
      for (final shop in store.entries('shops')) shop.id: shop.text('name'),
    };
    final tickerSection = HomeTickerSection(
      store: store,
      settings: settings,
      promotions: promotions,
      products: products,
      onProduct: onProduct,
    );
    // The scrolling-notice marquee (wireframe's thin "6" bar above the
    // offers row) -- driven by the admin's Scrolling Text Settings
    // (settings/scrollingText), independent of the "Today's Best Offers"
    // product-chip strip above.
    final scrolling = store
        .visible('settings')
        .firstWhere(
          (e) => e.id == 'scrollingText',
          orElse: () => const Entry('scrollingText', {}),
        );
    final tickerTextValue = noticeTickerText(scrolling, store.language);
    // The Scrolling Text's own animation (Settings > Homepage sections): "Marquee" is the strip's own scrolling, the others play on it as it appears.
    final scrollingAnimation = effectiveSectionConfig(settings, 'scrollingText');
    final notice0 = scrolling.active && tickerTextValue.isNotEmpty
        ? Padding(
            padding: const EdgeInsets.only(bottom: 8),
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
                    weight.value == scrolling.number('fontWeight', 400).round(),
                orElse: () => FontWeight.normal,
              ),
              speed: scrolling.number('speed', 70).clamp(10, 300),
              height: scrolling.number('height', 36).clamp(24, 120),
              padding: scrolling.number('padding', 9).clamp(0, 40),
              reverse: scrolling.text('direction', 'rtl') == 'ltr',
              backgroundImage: scrolling.text('backgroundImage'),
              brightness: scrolling.number('brightness', 1),
              opacity: scrolling.number('opacity', 1),
              borderColor: scrolling.text('borderColor'),
              borderWidth: scrolling.number('borderWidth'),
              radius: scrolling.number('radius'),
              playback: scrolling.text('playback', 'running'),
            ),
          )
        : const SizedBox.shrink();
    final notice = scrollingAnimation.text('animation') == 'marquee' ? notice0 : applyEntranceAnimation(scrollingAnimation, notice0);
    final page = layoutFor(context, settings, 'background');
    final productLayout = layoutFor(context, settings, 'products');
    final adLayout = layoutFor(context, settings, 'ads');
    final nearby = layoutFor(context, settings, 'nearby');
    final located = store.pincode.isNotEmpty || store.latitude != null;
    final shops = located ? store.nearby() : store.visible('shops');
    final theme =
        settings.where((e) => e.id == 'theme').firstOrNull ??
        const Entry('', {});
    // Side padding of the page. The header is laid out OUTSIDE it so its line
    // stretches from the left edge of the screen to the right edge; its content
    // gets the same padding inside.
    final edge = page
        .n(
          'padding',
          MediaQuery.sizeOf(context).width < 700 ? 10 : 18,
          0,
          48,
        )
        .clamp(0, MediaQuery.sizeOf(context).width / 24)
        .toDouble();
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DefaultTextStyle.merge(
              style: sectionTextStyle(page.styled(context)),
              child: ResponsiveHeader(
                store: store,
                search: search,
                onSearch: onSearch,
                onLocation: onLocation,
                onServices: onServices,
                onAccount: onAccount,
                onCart: onCart,
                onAssistedSearch: onAssistedSearch,
                onProduct: onProduct,
                wrapSection: wrapSection,
                edgePadding: edge,
              ),
            ),
            Padding(
          padding: EdgeInsets.fromLTRB(edge, 0, edge, edge),
          child: LayoutSection(
            layout: ComponentLayout(
              Entry(page.entry.id, {...page.entry.data, 'padding': 0}),
              page.viewport,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!store.live)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Demo marketplace • explore the experience'.tr(context),
                    ),
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
                wrapSection('tickerMarquee', notice),
                LayoutBuilder(
                  builder: (context, c) {
                    final railWidth = adLayout.width(
                      c.maxWidth * .28,
                      fallback: (c.maxWidth * .22).clamp(230, 380),
                    );
                    // The Right Side Ad Boxes (Settings > Right Side Ad Boxes): every box the same size, photos only, no labels.
                    final rightBoxes = RightAdBoxes(settings: settings, onTarget: onPromotion);
                    final hasRightBoxes = shownRightBoxes(rightBoxesRecord(settings)).isNotEmpty;
                    final wide = c.maxWidth >= 1100 && hasRightBoxes;
                    final orderedSectionKeys = [...reorderableHomeSections]
                      ..sort(
                        (a, b) => sectionOrder(
                          settings,
                          a.key,
                        ).compareTo(sectionOrder(settings, b.key)),
                      );
                    // The band under the Today's Offers cards: the product-card row and the Transport / Services boxes (home_strip_band.dart).
                    final stripProducts = products
                        .where((p) => p.text('categoryId') == 'cat-vegetables' || p.text('categoryId') == 'cat-fruits')
                        .toList();
                    final promoAt = orderedSectionKeys.indexWhere((d) => d.key == 'promo');
                    final mainWidth = wide ? c.maxWidth - page.gap - railWidth : c.maxWidth;
                    final bandSideBySide = mainWidth >= 640 && stripProducts.isNotEmpty;
                    // The Popular Products heading goes into the band (so the boxes reach down to the category tabs) only when that
                    // section comes right after Today's Offers.
                    final headingInBand =
                        bandSideBySide && promoAt >= 0 && promoAt + 1 < orderedSectionKeys.length && orderedSectionKeys[promoAt + 1].key == 'popular';
                    final reorderedSections = <String, Widget>{
                      'promo': LayoutSection(
                        layout: layoutFor(context, settings, 'promo'),
                        child: offers.isEmpty &&
                                (store.hasPlace ||
                                    offersForTown.hiddenForLocation > 0)
                            ? NoOffersNotice(store: store, onLocation: onLocation)
                            : HeroCarousel(
                          entries: offers,
                          appearance: effectiveSectionConfig(settings, 'promo'),
                          onTap: onPromotion,
                          reverse:
                              offers.isNotEmpty &&
                              offers.first.text('direction', 'rtl') == 'ltr',
                          speed: offers.isEmpty
                              ? 600
                              : offers.first.number('speed', 600),
                        ),
                      ),
                      'popular': HomePopularSection(
                        store: store,
                        settings: settings,
                        productLayout: productLayout,
                        products: products,
                        categories: categories,
                        productsKey: productsKey,
                        searchText: search.text,
                        shopNameById: shopNameById,
                        onProduct: onProduct,
                        onAdd: onAdd,
                        wrapSection: wrapSection,
                        showHeading: !headingInBand,
                      ),
                      'localServices': HomeLocalServicesSection(
                        store: store,
                        settings: settings,
                        localServices: localServices,
                        shopNameById: shopNameById,
                        onServices: onServices,
                        onProduct: onProduct,
                      ),
                    };
                    // On narrow/mobile layouts the ad rail collapses into this
                    // carousel, inserted at the very top of `main` — the
                    // ticker itself now lives outside `main` entirely (fixed
                    // beside the "All Categories" button), so "right after
                    // the ticker" is simply "first".
                    final main = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The "All Categories" button + chip-strip ticker
                        // lives inside `main` (not as a separate full-width
                        // row above the main/ads split) specifically so its
                        // right edge always matches the offer cards/
                        // categories/products below it, not the ad rail's --
                        // keeping every section in this column visually
                        // aligned to the same left/right edges regardless of
                        // the ad rail's own width.
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Deliberately NOT Flexible/Expanded: a flex
                              // widget here (even Flexible, which defaults to
                              // flex:1) would compete equally with the
                              // ticker's Expanded for the row's width,
                              // splitting it 50/50 regardless of this
                              // button's actual content size -- that was
                              // exactly why the ticker used to stop partway
                              // across instead of filling the rest of the
                              // row. Sized to its own natural content width
                              // instead, so shrinking or growing this button
                              // automatically gives the ticker's Expanded
                              // whatever space is left over.
                              Expanded(
                                child: wrapSection('notice', tickerSection),
                              ),
                            ],
                          ),
                        ),
                        // Quick Add Item: "Showing items in: <location>" + "Fresh today".
                        QuickFreshToday(store: store),
                        for (final (i, descriptor)
                            in orderedSectionKeys.indexed) ...[
                          wrapSection(
                            descriptor.key,
                            reorderedSections[descriptor.key]!,
                          ),
                          // Under the Today's Offers cards: the product cards, with the Transport and Services boxes beside them (or below them on a phone).
                          if (i == promoAt)
                            HomeStripBand(
                              store: store,
                              sideBySide: bandSideBySide,
                              heading: headingInBand
                                  ? HomePopularHeading(settings: settings, searchText: search.text, count: products.length)
                                  : null,
                              strip: wrapSection(
                                'crossSellStrip',
                                HomeCategoryProductStrip(
                                  layout: layoutFor(context, settings, 'crossSellStrip'),
                                  defaultTitle: 'Fresh Fruits & Vegetables'.tr(context),
                                  icon: Icons.eco_outlined,
                                  products: stripProducts,
                                  store: store,
                                  onProduct: onProduct,
                                  wrapProductItem: wrapProductItem,
                                ),
                              ),
                            ),
                        ],
                        wrapSection(
                          'nearby',
                          HomeNearbySection(
                            store: store,
                            nearby: nearby,
                            located: located,
                            shops: shops,
                            onLocation: onLocation,
                            shopCardLayout: layoutFor(
                              context,
                              settings,
                              'nearbyShopCard',
                            ),
                            wrapSection: wrapSection,
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
                              // Individual ads/boxes are wrapped (wrapPromoItem,
                              // threaded through HomeAdRail above), not the
                              // whole rail — wrapping the whole rail in one
                              // SectionTapRegion made one shared selection
                              // box/resize handles span every stacked ad/box
                              // at once, which read as them overlapping and
                              // made it impossible to resize just one.
                              SizedBox(width: railWidth, child: rightBoxes),
                            ],
                          )
                        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [main, if (hasRightBoxes) Padding(padding: const EdgeInsets.only(top: 12), child: rightBoxes)]);
                  },
                ),
                wrapSection(
                  'footerBadges',
                  HomeFooterBadges(settings: settings, wrapSection: wrapSection),
                ),
                Center(
                  child: TextButton.icon(
                    key: const ValueKey('open-photo-library'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PhotoLibraryPage())),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Photo library'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
            ),
          ],
        ),
      ),
    );
  }
}
