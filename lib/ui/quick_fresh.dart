import 'dart:async';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/quick_items.dart';
import 'design_tokens.dart';
import 'location_picker_dialog.dart';

// ---------------------------------------------------------------------------------------------
// Customer side of Quick Add Item: "Showing items in: <town> [Change]" and the "Fresh today" strip.
// The town is the one the customer chose with "Choose your location" (from the pincode directory) --
// the same place that decides their offers -- so there is no second list to pick from. Items shown
// are only the live ones (between startsAt and expiresAt) added for that town; when the time is up
// they disappear on their own.
// ---------------------------------------------------------------------------------------------

String _money(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

/// Opens the same "Choose your location" dialog as the header's location pill.
typedef QuickChooseLocation = Future<void> Function(BuildContext context, Store store);
Future<void> _defaultChoose(BuildContext context, Store store) => showLocationPickerDialog(context, store);

/// "Showing items in: X  [Change]" plus the "Fresh today" strip. Shows nothing while no Quick Add
/// item has been approved, so the home page stays exactly as it was.
class QuickFreshToday extends StatefulWidget {
  const QuickFreshToday({super.key, required this.store, this.now, this.choose = _defaultChoose});
  final Store store;
  final DateTime Function()? now;
  final QuickChooseLocation choose;
  @override
  State<QuickFreshToday> createState() => _QuickFreshTodayState();
}

class _QuickFreshTodayState extends State<QuickFreshToday> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Keeps "Available for 2h 15m" current and lets finished items vanish on time.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  DateTime get now => (widget.now ?? DateTime.now)();

  // Follows the store, so choosing another town updates the strip at once.
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.store, builder: (context, _) => _content(context));

  Widget _content(BuildContext context) {
    final store = widget.store;
    final anyApproved = (store.catalog['quickItems'] ?? const []).isNotEmpty;
    if (!anyApproved) return const SizedBox.shrink();
    final items = store.quickItemsHere(now: now);
    final hasTown = store.town.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.place_outlined, size: 20),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                hasTown ? 'Showing items in: ${store.town}' : 'Choose your location to see fresh items',
                key: const ValueKey('quick-showing-in'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              key: const ValueKey('quick-change-location'),
              onPressed: () => widget.choose(context, store),
              child: Text(hasTown ? 'Change' : 'Choose'),
            ),
          ]),
          if (hasTown && items.isNotEmpty) ...[
            Text('Fresh today', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SizedBox(
              height: 214,
              child: ListView.separated(
                key: const ValueKey('quick-fresh-strip'),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => QuickItemCard(item: items[i], now: now),
              ),
            ),
          ] else if (hasTown)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('No fresh items in ${store.town} right now.', key: const ValueKey('quick-none-here'), style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

/// One live item: photo, name, rate and how long it is still available.
class QuickItemCard extends StatelessWidget {
  const QuickItemCard({super.key, required this.item, required this.now, this.width = 150});
  final Entry item;
  final DateTime now;
  final double width;

  String get left => 'Available for ${quickCountdown(quickExpiresAt(item)!.difference(now))}';

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      key: ValueKey('quick-card-${item.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          builder: (sheet) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(height: 200, width: double.infinity, child: _photo(fit: BoxFit.cover))),
                const SizedBox(height: 12),
                Text(item.text('name'), style: Theme.of(sheet).textTheme.headlineSmall),
                Text('₹${_money(item.number('price'))} ${item.text('unit')}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text([
                  item.text('locationTown', item.text('locationName')),
                  item.text('locationPincode'),
                  item.text('shopName'),
                ].where((p) => p.isNotEmpty).join(' • ')),
                const SizedBox(height: 4),
                Text(left, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 108, width: double.infinity, child: _photo(fit: BoxFit.cover)),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.text('name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('₹${_money(item.number('price'))} ${item.text('unit')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTokens.primaryDark, fontWeight: FontWeight.w600)),
                  Text(left, key: ValueKey('quick-left-${item.id}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.green)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _photo({required BoxFit fit}) => item.text('imageUrl').isEmpty
      ? const ColoredBox(color: Colors.black12, child: Icon(Icons.image_outlined))
      : Image.network(item.text('imageUrl'), fit: fit, errorBuilder: (_, e, s) => const ColoredBox(color: Colors.black12, child: Icon(Icons.image_not_supported_outlined)));
}

/// Live items of one category in the customer's town, shown at the top of its category page.
class QuickCategoryItems extends StatefulWidget {
  const QuickCategoryItems({super.key, required this.store, required this.categoryId, this.now, this.choose = _defaultChoose});
  final Store store;
  final String categoryId;
  final DateTime Function()? now;
  final QuickChooseLocation choose;
  @override
  State<QuickCategoryItems> createState() => _QuickCategoryItemsState();
}

class _QuickCategoryItemsState extends State<QuickCategoryItems> {
  Timer? _tick;
  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.store, builder: (context, _) => _content(context));

  Widget _content(BuildContext context) {
    final store = widget.store;
    final now = (widget.now ?? DateTime.now)();
    if (store.town.isEmpty) return const SizedBox.shrink();
    final items = store.quickItemsHere(categoryId: widget.categoryId, now: now);
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text('Fresh today in ${store.town}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
          TextButton(onPressed: () => widget.choose(context, store), child: const Text('Change')),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 214,
          child: ListView.separated(
            key: const ValueKey('quick-category-strip'),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => QuickItemCard(item: items[i], now: now),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
