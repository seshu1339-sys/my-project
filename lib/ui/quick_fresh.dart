import 'dart:async';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/quick_items.dart';
import '../services/location.dart';
import 'design_tokens.dart';

// ---------------------------------------------------------------------------------------------
// Customer side of Quick Add Item: "Showing items in: <location> [Change]" and the "Fresh today"
// strip. Items shown are only the live ones (between startsAt and expiresAt) at the chosen
// location; when the time is up they disappear on their own.
// ---------------------------------------------------------------------------------------------

String _money(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

/// The location list dialog. Returns the chosen location id (also saved on the device).
Future<void> showQuickLocationPicker(BuildContext context, Store store, {String? notice, Future<dynamic> Function()? locate}) async {
  await showDialog<void>(
    context: context,
    builder: (dialog) => SimpleDialog(
      title: const Text('Choose a location'),
      children: [
        if (notice != null) Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 12), child: Text(notice)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: OutlinedButton.icon(
            key: const ValueKey('quick-use-my-location'),
            icon: const Icon(Icons.my_location),
            label: const Text('Use my location'),
            onPressed: () async {
              final found = await _nearest(store, locate: locate);
              if (!dialog.mounted) return;
              if (found != null) {
                await store.setQuickLocation(found.id);
                if (dialog.mounted) Navigator.pop(dialog);
              } else if (dialog.mounted) {
                ScaffoldMessenger.of(dialog).showSnackBar(const SnackBar(content: Text('Could not find your location. Please choose from the list.')));
              }
            },
          ),
        ),
        for (final location in store.quickLocations)
          SimpleDialogOption(
            key: ValueKey('quick-location-${location.id}'),
            onPressed: () async {
              await store.setQuickLocation(location.id);
              if (dialog.mounted) Navigator.pop(dialog);
            },
            child: Row(children: [
              Icon(location.id == store.quickLocationId ? Icons.radio_button_checked : Icons.radio_button_off, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(location.text('name', location.id), style: const TextStyle(fontSize: 16))),
            ]),
          ),
      ],
    ),
  );
}

/// The nearest listed location to where the phone is, or null (denied / no GPS / none listed).
Future<Entry?> _nearest(Store store, {Future<dynamic> Function()? locate}) async {
  try {
    final position = await (locate ?? () => currentPosition(action: 'show items near you'))();
    return store.nearestQuickLocation(position.latitude as double, position.longitude as double);
  } catch (_) {
    return null;
  }
}

/// First visit: ask to detect the location; if that is refused, ask them to pick from the list.
Future<void> promptQuickLocation(BuildContext context, Store store, {Future<dynamic> Function()? locate}) async {
  final allow = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => AlertDialog(
      title: const Text('Fresh items near you'),
      content: const Text('Allow location access so we can show items from the nearest location? You can also pick a location yourself.'),
      actions: [
        TextButton(key: const ValueKey('quick-prompt-choose'), onPressed: () => Navigator.pop(dialog, false), child: const Text('Choose from list')),
        FilledButton(key: const ValueKey('quick-prompt-allow'), onPressed: () => Navigator.pop(dialog, true), child: const Text('Allow location')),
      ],
    ),
  );
  if (allow == true) {
    final found = await _nearest(store, locate: locate);
    if (found != null) {
      await store.setQuickLocation(found.id);
      return;
    }
  }
  await store.markQuickLocationAsked();
  if (context.mounted) {
    await showQuickLocationPicker(
      context,
      store,
      notice: allow == true ? 'We could not use your location, so please pick one from the list.' : null,
      locate: locate,
    );
  }
}

/// "Showing items in: X  [Change]" plus the "Fresh today" strip. Shows nothing until the admin
/// has added locations.
class QuickFreshToday extends StatefulWidget {
  const QuickFreshToday({super.key, required this.store, this.prompt = true, this.now, this.locate});
  final Store store;
  // False in the admin's preview, which must never pop up the customer's first-visit question.
  final bool prompt;
  final DateTime Function()? now;
  final Future<dynamic> Function()? locate;
  @override
  State<QuickFreshToday> createState() => _QuickFreshTodayState();
}

class _QuickFreshTodayState extends State<QuickFreshToday> {
  Timer? _tick;
  bool _prompting = false;

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

  // Follows the store, so choosing another location updates the strip at once.
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.store, builder: (context, _) => _content(context));

  Widget _content(BuildContext context) {
    final store = widget.store;
    if (store.quickLocations.isEmpty) return const SizedBox.shrink();
    final needsPrompt = widget.prompt && !store.quickLocationAsked && store.quickLocation == null;
    if (needsPrompt && !_prompting) {
      _prompting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await promptQuickLocation(context, store, locate: widget.locate);
        _prompting = false;
      });
    }
    final location = store.quickLocation;
    final items = store.quickItemsHere(now: now);
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
                location == null ? 'Choose a location to see fresh items' : 'Showing items in: ${location.text('name', location.id)}',
                key: const ValueKey('quick-showing-in'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              key: const ValueKey('quick-change-location'),
              onPressed: () => showQuickLocationPicker(context, store, locate: widget.locate),
              child: Text(location == null ? 'Choose' : 'Change'),
            ),
          ]),
          if (location != null && items.isNotEmpty) ...[
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
          ] else if (location != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('No fresh items in ${location.text('name', location.id)} right now.', style: const TextStyle(fontSize: 12)),
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
                Text('${item.text('locationName')}${item.text('shopName').isEmpty ? '' : ' • ${item.text('shopName')}'}'),
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

/// Live items of one category at the chosen location, shown at the top of its category page.
class QuickCategoryItems extends StatefulWidget {
  const QuickCategoryItems({super.key, required this.store, required this.categoryId, this.now});
  final Store store;
  final String categoryId;
  final DateTime Function()? now;
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
    final location = store.quickLocation;
    if (location == null) return const SizedBox.shrink();
    final items = store.quickItemsHere(categoryId: widget.categoryId, now: now);
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text('Fresh today in ${location.text('name', location.id)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
          TextButton(onPressed: () => showQuickLocationPicker(context, store), child: const Text('Change')),
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
