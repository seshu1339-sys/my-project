import 'dart:async';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/catalog_lines.dart';
import 'design_tokens.dart';
import 'item_shops_page.dart';
import 'shared.dart';

/// The category lines under Today's Offers (lib/domain/catalog_lines.dart): [CatalogLinesConfig.lines] lines, each the items of one
/// category, a whole line fading to the next category after the admin's seconds (one line after the other). Nothing here reads
/// Firestore or the network after the app opens: the settings are read once when the section first shows, the items and prices come
/// from what the app already loaded, the app's photos are inside the app, and the Item Catalog photos are loaded once at the start.
class HomeCatalogLines extends StatefulWidget {
  const HomeCatalogLines({super.key, required this.store, required this.android, required this.onProduct});
  final Store store;
  final bool android;
  final ValueChanged<Entry> onProduct;

  @override
  State<HomeCatalogLines> createState() => _HomeCatalogLinesState();
}

class _HomeCatalogLinesState extends State<HomeCatalogLines> {
  // Read once: new values apply from the next app open.
  late final CatalogLinesConfig config = CatalogLinesConfig.from(widget.store.entries('settings'));
  // Items in a line: the app's number in the Android app and on a phone-wide website, the website's number on a wider screen.
  // Fixed when the section first shows.
  late final int perLine = config.itemsPerLine(android: widget.android || MediaQuery.sizeOf(context).width < 600);
  late final CatalogLineRotation rotation = CatalogLineRotation(lines: config.lines, perLine: perLine);
  final _loadedPhotos = <String>{};
  Timer? _timer;
  int _turn = 0;

  @override
  void initState() {
    super.initState();
    // One line changes at a time, in turn: each line stays [seconds], the lines a little apart.
    final every = Duration(milliseconds: config.seconds * 1000 ~/ config.lines);
    _timer = Timer.periodic(every, (_) {
      if (!mounted || rotation.shown.isEmpty) return;
      setState(() => rotation.next(_turn++ % rotation.shown.length));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// The Item Catalog photos come from the internet: all of them are loaded once, now, so a line change never downloads anything.
  void _preload(Iterable<CatalogLineItem> items) {
    for (final item in items) {
      if (item.imageUrl.isEmpty || !_loadedPhotos.add(item.imageUrl)) continue;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) precacheImage(NetworkImage(item.imageUrl), context, onError: (_, _) {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final categories = store.visible('categories');
    final items = catalogLineItems(categories: categories, library: store.visible('productImageLibrary'));
    final order = catalogLineOrder(items, categories, config.order);
    rotation.update(order, {for (final id in order) id: items[id]!.length});
    if (rotation.shown.isEmpty) return const SizedBox.shrink();
    _preload(items.values.expand((list) => list));
    final names = {for (final c in categories) c.id: c.text('name')};
    final products = store.visibleProducts();
    return Padding(
      key: const ValueKey('home-catalog-lines'),
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rotation.shown.length; i++)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
              child: _Line(
                key: ValueKey('catalog-line-$i-${rotation.shown[i].serial}'),
                line: i,
                title: names[rotation.shown[i].categoryId] ?? '',
                items: [for (final n in rotation.shown[i].indexes) items[rotation.shown[i].categoryId]![n]],
                perLine: perLine,
                priceOf: (item) => lowestLinePrice(item, products, pincode: store.pincode),
                open: (item) => openItemShops(context, store, name: item.name, libraryItemId: item.libraryItemId, openItem: widget.onProduct),
                noPrice: noPriceText(store),
              ),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({super.key, required this.line, required this.title, required this.items, required this.perLine, required this.priceOf, required this.open, required this.noPrice});
  // The words for an item with no price (Settings > Design texts & sizes).
  final String noPrice;
  final int line;
  final String title;
  final List<CatalogLineItem> items;
  final int perLine;
  final LinePrice? Function(CatalogLineItem) priceOf;
  final ValueChanged<CatalogLineItem> open;

  @override
  Widget build(BuildContext context) => Padding(
    key: ValueKey('catalog-line-$line'),
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < perLine; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: i < items.length ? _Box(item: items[i], price: priceOf(items[i]), open: open, noPrice: noPrice) : const SizedBox.shrink()),
            ],
          ],
        ),
      ],
    ),
  );
}

class _Box extends StatelessWidget {
  const _Box({required this.item, required this.price, required this.open, required this.noPrice});
  final String noPrice;
  final CatalogLineItem item;
  final LinePrice? price;
  final ValueChanged<CatalogLineItem> open;

  @override
  Widget build(BuildContext context) {
    final photo = item.asset.isNotEmpty
        ? Image.asset(item.asset, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.image_outlined, color: Colors.black26))
        : Image.network(item.imageUrl, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.image_outlined, color: Colors.black26));
    final p = price;
    return Material(
      key: ValueKey('catalog-box-${item.id}'),
      color: Colors.white,
      elevation: 0.5,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: p == null ? null : () => open(item),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(aspectRatio: 1, child: photo),
              const SizedBox(height: 4),
              SizedBox(
                height: 32,
                child: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.25)),
              ),
              const SizedBox(height: 4),
              Container(
                height: 34,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: p == null ? Colors.transparent : const Color(0xffe8f5ee),
                  border: Border.all(color: p == null ? Colors.black26 : const Color(0xff2e7d55)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: p == null
                    ? Text(noPrice, key: const ValueKey('catalog-no-price'), maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: Colors.black54, height: 1.2))
                    : Text('${money(p.price)}${p.unit.isEmpty ? '' : ' / ${p.unit}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xff1d5e3d))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
