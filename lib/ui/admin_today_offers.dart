import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/item_shops.dart';
import '../domain/today_offers.dart';
import 'admin_list_labels.dart';
import 'admin_shops_location.dart';
import 'shared.dart';

String _two(int n) => n.toString().padLeft(2, '0');
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "26 Oct, 09:30" in the admin's own time.
String offerTimeText(String iso) {
  final t = DateTime.tryParse(iso)?.toLocal();
  return t == null ? '-' : '${t.day} ${_months[t.month - 1]}, ${_two(t.hour)}:${_two(t.minute)}';
}

/// Settings > Today's Offers Box > Item offers: what each of the 6 boxes shows, and when. An offer is an item the shops already sell
/// (its photo comes with it), its offer price, the shop giving it, the box (1-6), and its start and end; several can wait for the same
/// box one after another. Stored as promotions with placement 'offer' (lib/domain/today_offers.dart), so a new offer is announced to
/// customers like any other offer when it starts (unless switched off for it).
class AdminTodayOffersPage extends StatelessWidget {
  const AdminTodayOffersPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final now = DateTime.now();
      final offers = store.entries('promotions').where(isTodayOffer).toList()
        ..sort((a, b) => a.text('startsAt').compareTo(b.text('startsAt')));
      final looks = todayOfferBoxLooks(sortedByOrder([for (final p in store.entries('promotions')) if (p.text('placement') == 'carousel' && p.active) p]));
      return ListView(
        key: const ValueKey('admin-today-offers'),
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Each box shows its offer only from its start to its end. Put several offers in a box one after another: when one ends the '
            'next one comes by itself. A box with no offer at that time shows its usual Today\'s Offers Box promotion. The box colours stay as they are.',
          ),
          if (shopsWithoutLocation(store).isNotEmpty)
            Card(
              key: const ValueKey('offers-shops-without-location'),
              child: ListTile(
                leading: const Icon(Icons.location_off_outlined),
                title: Text('${shopsWithoutLocation(store).length} shops have no place on the map'),
                subtitle: const Text('Customers tapping their offers see no road or distance. Fix them.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Shops without location')), body: AdminShopsLocationPage(store: store))),
                ),
              ),
            ),
          const SizedBox(height: 12),
          for (var slot = 1; slot <= todayOfferBoxCount; slot++)
            Card(
              key: ValueKey('admin-offer-box-$slot'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(color: colorFromHex(looks[slot - 1].text('backgroundColor'), Colors.grey), borderRadius: BorderRadius.circular(6)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Box $slot', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                        FilledButton.tonalIcon(
                          key: ValueKey('add-offer-$slot'),
                          onPressed: () => openTodayOfferForm(context, store, slot: slot),
                          icon: const Icon(Icons.add),
                          label: const Text('Add offer'),
                        ),
                      ],
                    ),
                    if (!offers.any((o) => todayOfferSlot(o) == slot))
                      const Padding(padding: EdgeInsets.only(top: 8), child: Text('No offers: the box shows its usual promotion.')),
                    for (final o in offers.where((o) => todayOfferSlot(o) == slot))
                      ListTile(
                        key: ValueKey('admin-offer-${o.id}'),
                        contentPadding: EdgeInsets.zero,
                        leading: ClipOval(child: SizedBox(width: 48, height: 48, child: ProductArt(Entry(o.id, {'imageUrl': o.text('imageUrl')}), height: 48, width: 48))),
                        title: Text('${o.text('name')} • ${todayOfferRate(o)}'),
                        subtitle: Text(
                          '${store.entries('shops').where((s) => s.id == o.text('shopId')).firstOrNull?.text('name') ?? o.text('shopId')}\n'
                          '${offerTimeText(o.text('startsAt'))} → ${offerTimeText(o.text('endsAt'))} • ${todayOfferStatus(o, now)}',
                        ),
                        isThreeLine: true,
                        trailing: Wrap(
                          children: [
                            IconButton(tooltip: 'Edit', onPressed: () => openTodayOfferForm(context, store, offer: o), icon: const Icon(Icons.edit_outlined)),
                            IconButton(tooltip: 'Delete', key: ValueKey('delete-offer-${o.id}'), onPressed: () => _delete(context, o), icon: const Icon(Icons.delete_outline)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  Future<void> _delete(BuildContext context, Entry offer) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete this offer?'),
        content: Text('${offer.text('name')} • ${todayOfferRate(offer)} in box ${todayOfferSlot(offer)}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('delete-offer-confirm'), onPressed: () => Navigator.pop(dialog, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await store.delete('promotions', offer.id);
    } catch (e) {
      if (context.mounted) message(context, e);
    }
  }
}

Future<void> openTodayOfferForm(BuildContext context, Store store, {int slot = 1, Entry? offer}) => showDialog<void>(
  context: context,
  builder: (_) => Dialog(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: TodayOfferForm(store: store, slot: slot, offer: offer))),
);

/// Add or change one item offer.
class TodayOfferForm extends StatefulWidget {
  const TodayOfferForm({super.key, required this.store, this.slot = 1, this.offer, this.now});
  final Store store;
  final int slot;
  final Entry? offer;
  // Test seam: the time the form starts from.
  final DateTime? now;
  @override
  State<TodayOfferForm> createState() => _TodayOfferFormState();
}

class _TodayOfferFormState extends State<TodayOfferForm> {
  Store get store => widget.store;
  final search = TextEditingController(), price = TextEditingController(), unit = TextEditingController();
  ItemPick? item;
  String shopId = '';
  late int slot = widget.offer == null ? widget.slot : todayOfferSlot(widget.offer!).clamp(1, todayOfferBoxCount);
  late DateTime start, end;
  bool notify = true, saving = false;
  String? problem;

  @override
  void initState() {
    super.initState();
    final o = widget.offer;
    final now = widget.now ?? DateTime.now();
    if (o != null) {
      item = ItemPick(name: o.text('name'), libraryItemId: o.text('libraryItemId'), productId: o.text('productId'), imageUrl: o.text('imageUrl'));
      price.text = o.number('offerPrice') == 0 ? '' : '${o.number('offerPrice')}'.replaceAll(RegExp(r'\.0$'), '');
      unit.text = o.text('unit');
      shopId = o.text('shopId');
      notify = o.data['notifySubscribers'] != false;
    }
    start = DateTime.tryParse(o?.text('startsAt') ?? '')?.toLocal() ?? DateTime(now.year, now.month, now.day, now.hour, now.minute);
    end = DateTime.tryParse(o?.text('endsAt') ?? '')?.toLocal() ?? DateTime(start.year, start.month, start.day, 23, 59);
  }

  @override
  void dispose() {
    for (final c in [search, price, unit]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The shops selling the chosen item first, then every other shop.
  List<Entry> get _shops {
    final shops = store.entries('shops');
    final picked = item;
    if (picked == null) return shops;
    final selling = {
      for (final p in store.entries('products'))
        if (p.id == picked.productId || isSameItem(p, name: picked.name, libraryItemId: picked.libraryItemId)) p.text('shopId'),
    };
    return [...shops.where((s) => selling.contains(s.id)), ...shops.where((s) => !selling.contains(s.id))];
  }

  void _choose(ItemPick pick) {
    final product = store.entries('products').where((p) => p.id == pick.productId).firstOrNull;
    setState(() {
      item = pick;
      search.clear();
      if (unit.text.isEmpty) unit.text = product?.text('unit') ?? '';
      if (shopId.isEmpty) shopId = product?.text('shopId') ?? '';
      problem = null;
    });
  }

  Future<DateTime?> _pick(DateTime from) async {
    final day = await showDatePicker(context: context, initialDate: from, firstDate: DateTime(2024), lastDate: DateTime(2100));
    if (day == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(from));
    if (time == null) return null;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  String _when(DateTime t) => '${t.day} ${_months[t.month - 1]} ${t.year}, ${_two(t.hour)}:${_two(t.minute)}';

  Entry _draft() {
    final shop = store.entries('shops').where((s) => s.id == shopId).firstOrNull;
    final rate = double.tryParse(price.text.trim()) ?? 0;
    final draft = Entry(widget.offer?.id ?? 'offer-${DateTime.now().millisecondsSinceEpoch}', {
      ...?widget.offer?.data,
      'placement': todayOfferPlacement,
      'slot': slot,
      'order': slot,
      'name': item?.name ?? '',
      'productId': item?.productId ?? '',
      'libraryItemId': item?.libraryItemId ?? '',
      'imageUrl': item?.imageUrl ?? '',
      'offerPrice': rate,
      'unit': unit.text.trim(),
      'shopId': shopId,
      'town': shop?.text('town') ?? '',
      // The offer's push reaches the customers of the shop's town only (functions/notifications.js).
      'locations': shop?.text('town') ?? '',
      'startsAt': start.toUtc().toIso8601String(),
      'endsAt': end.toUtc().toIso8601String(),
      'active': true,
      'notifySubscribers': notify,
    });
    return Entry(draft.id, {...draft.data, 'description': '${todayOfferRate(draft)}${shop == null ? '' : ' at ${shop.text('name')}'}'});
  }

  Future<void> _save() async {
    final rate = double.tryParse(price.text.trim()) ?? 0;
    final error = item == null
        ? 'Choose the item.'
        : rate <= 0
        ? 'Give the offer price.'
        : shopId.isEmpty
        ? 'Choose the shop.'
        : !end.isAfter(start)
        ? 'The end must be after the start.'
        : null;
    if (error != null) return setState(() => problem = error);
    setState(() => saving = true);
    try {
      await store.save('promotions', _draft());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => problem = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final picks = item == null || search.text.isNotEmpty ? itemPicks(store.entries('products'), search.text) : const <ItemPick>[];
    final shops = _shops;
    final overlaps = item == null ? const <Entry>[] : overlappingTodayOffers(store.entries('promotions'), _draft());
    return ListView(
      key: const ValueKey('today-offer-form'),
      shrinkWrap: true,
      padding: const EdgeInsets.all(20),
      children: [
        Text(widget.offer == null ? 'New offer' : 'Change offer', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (item != null)
          ListTile(
            key: const ValueKey('offer-item-chosen'),
            contentPadding: EdgeInsets.zero,
            leading: ClipOval(child: SizedBox(width: 52, height: 52, child: ProductArt(Entry('pick', {'imageUrl': item!.imageUrl}), height: 52, width: 52))),
            title: Text(item!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(item!.imageUrl.isEmpty ? 'No photo for this item yet' : 'Its photo is used'),
            trailing: TextButton(onPressed: () => setState(() => item = null), child: const Text('Change')),
          )
        else
          TextField(
            key: const ValueKey('offer-item-search'),
            controller: search,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Item (type its name)', prefixIcon: Icon(Icons.search)),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              final found = itemPicks(store.entries('products'), search.text);
              if (found.isNotEmpty) _choose(found.first);
            },
          ),
        if (item == null)
          for (final pick in picks)
            ListTile(
              key: ValueKey('offer-pick-${pick.key}'),
              dense: true,
              leading: ClipOval(child: SizedBox(width: 40, height: 40, child: ProductArt(Entry('pick', {'imageUrl': pick.imageUrl}), height: 40, width: 40))),
              title: Text(pick.name),
              onTap: () => _choose(pick),
            ),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('offer-price'),
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Offer price (₹)'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: TextField(key: const ValueKey('offer-unit'), controller: unit, decoration: const InputDecoration(labelText: 'For (e.g. 1 kg)'))),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const ValueKey('offer-shop'),
          initialValue: shops.any((s) => s.id == shopId) ? shopId : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Shop giving the offer'),
          items: [for (final s in shops) DropdownMenuItem(value: s.id, child: Text([s.text('name'), s.text('town')].where((x) => x.isNotEmpty).join(' • ')))],
          onChanged: (v) => setState(() => shopId = v ?? ''),
        ),
        const SizedBox(height: 12),
        const Text('Box'),
        SegmentedButton<int>(
          key: const ValueKey('offer-box'),
          segments: [for (var i = 1; i <= todayOfferBoxCount; i++) ButtonSegment(value: i, label: Text('$i'))],
          selected: {slot},
          onSelectionChanged: (v) => setState(() => slot = v.first),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('offer-start'),
              onPressed: () async {
                final t = await _pick(start);
                if (t != null) {
                  setState(() {
                    start = t;
                    if (!end.isAfter(start)) end = DateTime(t.year, t.month, t.day, 23, 59);
                  });
                }
              },
              icon: const Icon(Icons.event),
              label: Text('Starts: ${_when(start)}'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('offer-end'),
              onPressed: () async {
                final t = await _pick(end);
                if (t != null) setState(() => end = t);
              },
              icon: const Icon(Icons.event_busy),
              label: Text('Ends: ${_when(end)}'),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: notify,
          onChanged: (v) => setState(() => notify = v),
          title: const Text('Tell customers of the shop\'s town when it starts (push notification)'),
        ),
        if (overlaps.isNotEmpty)
          Text(
            'Box $slot already has ${overlaps.map((o) => o.text('name')).join(', ')} at that time; the one that starts later shows then.',
            key: const ValueKey('offer-overlap'),
            style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
          ),
        if (problem != null) Text(problem!, key: const ValueKey('offer-problem'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(key: const ValueKey('offer-save'), onPressed: saving ? null : _save, child: Text(saving ? 'Saving...' : 'Save')),
          ],
        ),
      ],
    );
  }
}
