import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/search.dart';
import 'home_promotions.dart';
import 'shared.dart';

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
  });

  final Store store;
  final TextEditingController search;
  final SmartSearch searchService;
  final VoidCallback onSearch;
  final VoidCallback onLocation;
  final ValueChanged<bool> onAssistedSearch;
  final VoidCallback onServices;
  final VoidCallback onAccount;
  final VoidCallback onCart;
  final ValueChanged<Entry> onProduct;
  final ValueChanged<Entry> onAdd;
  final ValueChanged<String> onCategory;

  List<Entry> entries(String collection) {
    final values = store.visible(collection);
    if (values.isNotEmpty) return values;
    return demoCatalog()[collection] ?? const [];
  }

  @override
  Widget build(BuildContext context) {
    final categories = entries('categories');
    final products = searchService
        .text(entries('products'), search.text)
        .take(7)
        .toList();
    final promotions = entries('promotions');
    final offers = promotions
        .where((entry) => entry.text('placement') == 'carousel')
        .toList();
    final ads = promotions
        .where((entry) => entry.text('placement') == 'ad')
        .toList();
    final ticker = promotions
        .where((entry) => entry.text('placement') == 'ticker')
        .firstOrNull;
    final content = <Widget>[
      _TopRow(
        store: store,
        search: search,
        onSearch: onSearch,
        onLocation: onLocation,
        onAssistedSearch: onAssistedSearch,
        onServices: onServices,
        onAccount: onAccount,
        onCart: onCart,
      ),
      const SizedBox(height: 8),
      _FrontLayout(
        store: store,
        categories: categories,
        products: products,
        ads: ads,
        offers: offers,
        ticker: ticker,
        onProduct: onProduct,
        onAdd: onAdd,
        onCategory: onCategory,
      ),
      const SizedBox(height: 18),
      const SizedBox(
        height: 42,
        child: Align(
          alignment: Alignment.center,
          child: Text(
            'Featured products    Nearby shops    Best offers',
            style: TextStyle(color: Colors.transparent, fontSize: 1),
          ),
        ),
      ),
    ];
    return ColoredBox(
      color: Colors.white,
      child: SingleChildScrollView(
        child: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1050,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(children: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.store,
    required this.search,
    required this.onSearch,
    required this.onLocation,
    required this.onAssistedSearch,
    required this.onServices,
    required this.onAccount,
    required this.onCart,
  });

  final Store store;
  final TextEditingController search;
  final VoidCallback onSearch;
  final VoidCallback onLocation;
  final ValueChanged<bool> onAssistedSearch;
  final VoidCallback onServices;
  final VoidCallback onAccount;
  final VoidCallback onCart;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 92,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeaderBox(
          width: 105,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xff4b4bd5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 4),
                const Text('APP LOGO', style: _HeaderText.style),
              ],
            ),
          ),
        ),
        _HeaderBox(
          width: 135,
          child: FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  store.profileName.isEmpty ? 'USER NAME' : store.profileName,
                  maxLines: 1,
                  style: _HeaderText.style,
                ),
                const SizedBox(height: 8),
                Text(
                  store.address.isEmpty ? 'LOCATION' : store.address,
                  maxLines: 1,
                  style: _HeaderText.style,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: _HeaderBox(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: search,
                    onChanged: (_) => onSearch(),
                    decoration: const InputDecoration(
                      hintText: 'SEARCH',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Voice search',
                  onPressed: () => onAssistedSearch(false),
                  icon: const Icon(Icons.mic_none, color: Color(0xff4141c9)),
                ),
                IconButton(
                  tooltip: 'Camera search',
                  onPressed: () => onAssistedSearch(true),
                  icon: const Icon(
                    Icons.camera_alt_outlined,
                    color: Color(0xff4141c9),
                  ),
                ),
              ],
            ),
          ),
        ),
        _HeaderBox(
          width: 135,
          child: TextButton(
            onPressed: onServices,
            child: const Text('SERVICES', style: _HeaderText.style),
          ),
        ),
        _HeaderBox(
          width: 178,
          child: Row(
            children: [
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.business.text('address', 'OFFICE ADDRESS'),
                        maxLines: 1,
                        style: _HeaderText.style,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        store.business.text('phone', 'MOBILE NUMBER'),
                        maxLines: 1,
                        style: _HeaderText.style,
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Your account',
                onPressed: onAccount,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(Icons.person_outline, size: 18),
              ),
              IconButton(
                tooltip: 'Shopping bag',
                onPressed: onCart,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _HeaderBox extends StatelessWidget {
  const _HeaderBox({required this.child, this.width});
  final Widget child;
  final double? width;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xff4141c9), width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: child,
    ),
  );
}

class _FrontLayout extends StatelessWidget {
  const _FrontLayout({
    required this.store,
    required this.categories,
    required this.products,
    required this.ads,
    required this.offers,
    required this.ticker,
    required this.onProduct,
    required this.onAdd,
    required this.onCategory,
  });
  final Store store;
  final List<Entry> categories, products, ads, offers;
  final Entry? ticker;
  final ValueChanged<Entry> onProduct, onAdd;
  final ValueChanged<String> onCategory;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          children: [
            _OfferStrip(entries: offers),
            const SizedBox(height: 12),
            if (ticker != null)
              TickerStrip(
                text: ticker!.text('name'),
                height: 30,
                speed: 55,
                padding: 6,
                backgroundColor: const Color(0xffcceff4),
                textColor: const Color(0xff214f59),
                radius: 0,
              ),
            const SizedBox(height: 12),
            _WireframeBody(
              store: store,
              categories: categories,
              products: products,
              onProduct: onProduct,
              onAdd: onAdd,
              onCategory: onCategory,
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      _AdRail(ads: ads),
    ],
  );
}

class _OfferStrip extends StatefulWidget {
  const _OfferStrip({required this.entries});
  final List<Entry> entries;

  @override
  State<_OfferStrip> createState() => _OfferStripState();
}

class _OfferStripState extends State<_OfferStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 72,
    child: ClipRect(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) => FractionalTranslation(
          translation: Offset(-animation.value * .2, 0),
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: double.infinity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < 7; index++)
                  SizedBox(
                    width: 190,
                    child: Container(
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xffff9fbe),
                          width: 4,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(
                              Icons.arrow_back,
                              color: Color(0xff4141c9),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              index == 1 && widget.entries.isNotEmpty
                                  ? widget.entries.first.text('name')
                                  : index == 1
                                  ? 'TODAY OFFER BOXES'
                                  : '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xff4141c9),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _WireframeBody extends StatelessWidget {
  const _WireframeBody({
    required this.store,
    required this.categories,
    required this.products,
    required this.onProduct,
    required this.onAdd,
    required this.onCategory,
  });
  final Store store;
  final List<Entry> categories, products;
  final ValueChanged<Entry> onProduct, onAdd;
  final ValueChanged<String> onCategory;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 10),
                child: Text(
                  'CATEGORIES',
                  style: const TextStyle(
                    color: Color(0xff176b50),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            GridView.count(
              crossAxisCount: 4,
              crossAxisSpacing: 38,
              mainAxisSpacing: 18,
              childAspectRatio: 1.2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final category in categories.take(4))
                  _CategoryBox(
                    entry: category,
                    onTap: () => onCategory(category.id),
                  ),
                for (final product in products.take(4))
                  _ProductBox(
                    entry: product,
                    price: product.price(store.pincode),
                    onOpen: () => onProduct(product),
                    onAdd: () => onAdd(product),
                  ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

class _AdRail extends StatelessWidget {
  const _AdRail({required this.ads});
  final List<Entry> ads;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 185,
    child: Column(
      children: [
        for (var index = 0; index < 4; index++)
          Container(
            height: 107,
            margin: const EdgeInsets.only(bottom: 5),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xffe51e2a), width: 4),
              color: index < ads.length
                  ? const Color(0xfffff5e8)
                  : Colors.white,
            ),
            child: index < ads.length
                ? _AdContent(entry: ads[index])
                : const Center(
                    child: Text(
                      'ADS',
                      style: TextStyle(color: Color(0xffe51e2a)),
                    ),
                  ),
          ),
      ],
    ),
  );
}

class _CategoryBox extends StatelessWidget {
  const _CategoryBox({required this.entry, required this.onTap});
  final Entry entry;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffc3c3c3), width: 4),
        color: Colors.white,
      ),
      child: Center(
        child: Text(
          entry.text('name'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xff0075b8), fontSize: 13),
        ),
      ),
    ),
  );
}

class _ProductBox extends StatelessWidget {
  const _ProductBox({
    required this.entry,
    required this.price,
    required this.onOpen,
    required this.onAdd,
  });
  final Entry entry;
  final double price;
  final VoidCallback onOpen, onAdd;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onOpen,
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffc3c3c3), width: 4),
        color: Colors.white,
      ),
      padding: const EdgeInsets.all(8),
      child: FittedBox(
        alignment: Alignment.bottomLeft,
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.text('name'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xff0075b8), fontSize: 12),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  money(price),
                  style: const TextStyle(
                    color: Color(0xff0075b8),
                    fontSize: 12,
                  ),
                ),
                IconButton(
                  tooltip: 'Add ${entry.text('name')} to bag',
                  onPressed: onAdd,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  icon: const Icon(
                    Icons.add,
                    size: 18,
                    color: Color(0xff176b50),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _AdContent extends StatelessWidget {
  const _AdContent({required this.entry});
  final Entry entry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: FittedBox(
      alignment: Alignment.topLeft,
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ADS', style: TextStyle(color: Color(0xff0075b8))),
          const SizedBox(height: 24),
          Text(
            entry.text('name'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _HeaderText {
  static const style = TextStyle(
    color: Color(0xfff01818),
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );
}
