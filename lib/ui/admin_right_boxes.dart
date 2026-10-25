import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/right_boxes.dart';
import '../domain/shop_ads.dart';
import 'color_picker_field.dart';
import 'shared.dart';

/// What the page shows about the shop ads (live only): every shop ad (rightBoxAds), their total views and taps (adStats), and the
/// approved vendors (to link a box to, the ones who ticked "Ad for your shop" first).
class RightBoxShopAds {
  const RightBoxShopAds({this.ads = const [], this.views = const {}, this.taps = const {}, this.vendors = const []});
  final List<ShopAd> ads;
  final Map<String, int> views, taps;
  final List<Entry> vendors;

  ShopAd? live(String adId) => adId.isEmpty ? null : ads.where((a) => a.id == adId && a.live).firstOrNull;
  List<Entry> get interested => [for (final v in vendors) if (v.data['adInterest'] == true) v];
}

/// Settings > Right Side Ad Boxes: the boxes down the right of the home page, all one size. Each box has a JPG/PNG photo, an optional
/// link (a category, shop or product) and a background colour. "Add box" / "Remove box" change how many there are (15 to start).
/// The numbers are shown only here; customers see just the photos, in this order, and a box with no photo shows "your ad here".
/// A box can be linked to a vendor (a shop ad arranged offline, functions/shop-ads.js): its views then count for that vendor, and
/// this page shows each box's total views, the vendors who want an ad, and the shop ads that have ended.
class AdminRightBoxesPage extends StatefulWidget {
  const AdminRightBoxesPage({super.key, required this.store, this.shopAds});
  final Store store;
  // The shop-ad data; by default read live from Firestore (nothing in the demo). Given in tests.
  final Stream<RightBoxShopAds>? shopAds;
  @override
  State<AdminRightBoxesPage> createState() => _AdminRightBoxesPageState();
}

class _AdminRightBoxesPageState extends State<AdminRightBoxesPage> {
  Store get store => widget.store;
  bool busy = false;
  late final Stream<RightBoxShopAds> _shopAds = widget.shopAds ?? (store.live ? _watchShopAds() : Stream.value(const RightBoxShopAds()));

  Entry get _record => rightBoxesRecord(store.entries('settings'));

  Stream<RightBoxShopAds> _watchShopAds() {
    List<Entry> rows(QuerySnapshot<Map<String, dynamic>> s) => [for (final d in s.docs) Entry(d.id, d.data())];
    final controller = StreamController<RightBoxShopAds>();
    var ads = const <Entry>[], stats = const <Entry>[], vendors = const <Entry>[];
    void emit() => controller.add(RightBoxShopAds(ads: shopAdsInOrder(ads), views: shopAdViews(stats), taps: shopAdTaps(stats), vendors: vendors));
    final subs = [
      store.firestore.collection('rightBoxAds').limit(500).snapshots().listen((s) {
        ads = rows(s);
        emit();
      }, onError: controller.addError),
      store.firestore.collection('adStats').where('kind', isEqualTo: 'rightBox').limit(500).snapshots().listen((s) {
        stats = rows(s);
        emit();
      }, onError: controller.addError),
      store.firestore.collection('vendors').where('status', isEqualTo: 'approved').limit(500).snapshots().listen((s) {
        vendors = rows(s);
        emit();
      }, onError: controller.addError),
    ];
    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };
    return controller.stream;
  }

  Future<void> _write(Map<String, dynamic> changes, {Set<String> remove = const {}}) async {
    setState(() => busy = true);
    try {
      final next = {..._record.data, ...changes}..removeWhere((k, _) => remove.contains(k));
      await store.updateFields('settings', rightBoxesDoc, changes, remove: remove, fallback: Entry(rightBoxesDoc, next));
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Links box [n] to [vendorId] (a new shop ad starts), or ends its shop ad when [vendorId] is empty. False when it failed.
  Future<bool> _link(int n, String vendorId, {bool quiet = false}) async {
    setState(() => busy = true);
    try {
      await store.call('assignRightBoxVendor', {'box': n, 'vendorId': vendorId});
      if (mounted && !quiet) message(context, vendorId.isEmpty ? 'The shop ad in Right Side Ad Box $n has ended.' : 'Right Side Ad Box $n is linked: its views now count for this vendor.');
      return true;
    } catch (e) {
      if (mounted) message(context, e);
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _chooseVendor(int n, RightBoxShopAds data, ShopAd? current) async {
    final picked = await showDialog<String>(context: context, builder: (_) => _VendorPickerDialog(vendors: data.vendors, ads: data.ads, current: current?.vendorId));
    if (picked == null || picked == current?.vendorId || !mounted) return;
    await _link(n, picked);
  }

  Future<void> _endAd(int n, ShopAd ad) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('End the shop ad in box $n?'),
        content: Text('${ad.vendorName.isEmpty ? 'The vendor' : ad.vendorName} keeps the views counted so far. The photo stays in the box until you remove it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          FilledButton(key: const ValueKey('end-shop-ad-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('End ad')),
        ],
      ),
    );
    if (ok == true && mounted) await _link(n, '');
  }

  Future<void> _addBox() async {
    final count = rightBoxCount(_record);
    if (count >= maxRightBoxCount) return message(context, 'The most boxes allowed is $maxRightBoxCount.');
    await _write({'count': count + 1});
  }

  Future<void> _removeBox() async {
    final count = rightBoxCount(_record);
    if (count == 0) return;
    final box = rightBoxAt(_record, count);
    final hasAd = box.adId.isNotEmpty;
    if (box.imageUrl.isNotEmpty || hasAd) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Remove Right Side Ad Box $count?'),
          content: Text(hasAd ? 'This box has a shop ad. Removing the box ends the ad and takes it off the website.' : 'This box has a photo. Removing the box takes it off the website.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove box')),
          ],
        ),
      );
      if (ok != true) return;
    }
    // The shop ad ends first (the vendor keeps the views counted so far); a box is never removed with its ad still running.
    if (hasAd && store.live && !await _link(count, '', quiet: true)) return;
    await _write({'count': count - 1}, remove: {'box${count}Image', 'box${count}Target', 'box${count}Color'});
  }

  Future<void> _upload(int n) async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final name = file.name.toLowerCase();
      if (!(name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png'))) {
        if (mounted) message(context, 'Choose a JPG or PNG photo.');
        return;
      }
      setState(() => busy = true);
      final url = await store.upload(file, folder: 'ads');
      if (mounted) await _write({'box${n}Image': url});
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<RightBoxShopAds>(
    stream: _shopAds,
    builder: (context, snapshot) => ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final data = snapshot.data ?? const RightBoxShopAds();
        final linking = store.live || widget.shopAds != null;
        final record = _record;
        final count = rightBoxCount(record);
        final ended = data.ads.where((a) => !a.live).toList();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Right Side Ad Boxes', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            const Text(
              'The boxes down the right side of the home page, top to bottom. Every box is the same size. '
              'Customers see only the photo (no number). A box with no photo shows as a light grey "ఇక్కడ మీ ప్రకటన" box of the same size.',
            ),
            if (linking) ...[
              const SizedBox(height: 12),
              _InterestedVendors(data: data),
              if (snapshot.hasError) Text('Could not load the shop ads: ${snapshot.error}', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('$count boxes', key: const ValueKey('right-box-count'), style: Theme.of(context).textTheme.titleMedium),
                FilledButton.icon(key: const ValueKey('add-right-box'), onPressed: busy ? null : _addBox, icon: const Icon(Icons.add), label: const Text('Add box')),
                OutlinedButton.icon(key: const ValueKey('remove-right-box'), onPressed: busy || count == 0 ? null : _removeBox, icon: const Icon(Icons.remove), label: const Text('Remove box')),
              ],
            ),
            const SizedBox(height: 12),
            for (var n = 1; n <= count; n++)
              _BoxCard(
                key: ValueKey('admin-right-box-$n'),
                number: n,
                box: rightBoxAt(record, n),
                store: store,
                busy: busy,
                onUpload: () => _upload(n),
                onWrite: _write,
                shopAd: linking ? _ShopAdRow(number: n, box: rightBoxAt(record, n), data: data, busy: busy, onChoose: (ad) => _chooseVendor(n, data, ad), onEnd: (ad) => _endAd(n, ad)) : null,
              ),
            if (ended.isNotEmpty)
              Card(
                child: ExpansionTile(
                  key: const ValueKey('ended-shop-ads'),
                  title: Text('Ended shop ads (${ended.length})'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final ad in ended)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Box ${ad.box} • ${ad.vendorName}${ad.vendorCode.isEmpty ? '' : ' (${ad.vendorCode})'} • ${shopAdDate(ad.startedAt)} to ${shopAdDate(ad.endedAt)} • '
                          '${shopAdCount(data.views[ad.id] ?? 0)} views • ${shopAdCount(data.taps[ad.id] ?? 0)} taps',
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// The vendors who ticked "Ad for your shop", with whether they already have a box.
class _InterestedVendors extends StatelessWidget {
  const _InterestedVendors({required this.data});
  final RightBoxShopAds data;

  @override
  Widget build(BuildContext context) {
    final wanting = data.interested;
    return Card(
      key: const ValueKey('shop-ad-interested'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vendors who want an ad for their shop (${wanting.length})', style: Theme.of(context).textTheme.titleMedium),
            const Text('They ticked "Ad for your shop" in the vendor app. Call them, arrange the ad and the payment, upload their photo into a box and link the box to them.'),
            const SizedBox(height: 6),
            if (wanting.isEmpty) const Text('Nobody yet.'),
            for (final v in wanting)
              Builder(builder: (context) {
                final boxes = [for (final a in data.ads) if (a.live && a.vendorId == v.id) a.box];
                final ticked = shopAdDate(shopAdTime(v.data['adInterestAt']));
                return ListTile(
                  key: ValueKey('shop-ad-wants-${v.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(v.text('name', v.id)),
                  subtitle: Text([if (v.text('vendorCode').isNotEmpty) v.text('vendorCode'), if (ticked.isNotEmpty) 'ticked $ticked'].join(' • ')),
                  trailing: Text(boxes.isEmpty ? 'No ad yet' : 'Box ${boxes.join(', ')}, live'),
                );
              }),
          ],
        ),
      ),
    );
  }
}

/// A box's shop ad: whose it is, since when, its total views and taps, and the buttons to link, change or end it.
class _ShopAdRow extends StatelessWidget {
  const _ShopAdRow({required this.number, required this.box, required this.data, required this.busy, required this.onChoose, required this.onEnd});
  final int number;
  final RightBox box;
  final RightBoxShopAds data;
  final bool busy;
  final ValueChanged<ShopAd?> onChoose;
  final ValueChanged<ShopAd> onEnd;

  @override
  Widget build(BuildContext context) {
    final ad = data.live(box.adId);
    return Container(
      key: ValueKey('right-box-shop-ad-$number'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Shop ad', style: TextStyle(fontWeight: FontWeight.bold)),
          if (ad == null)
            const Text('No vendor linked. Link the box to a vendor and its views count for them.')
          else ...[
            Text('${ad.vendorName.isEmpty ? ad.vendorId : ad.vendorName}${ad.vendorCode.isEmpty ? '' : ' (${ad.vendorCode})'}${ad.startedAt == null ? '' : ' • since ${shopAdDate(ad.startedAt)}'}'),
            Text(
              '${shopAdCount(data.views[ad.id] ?? 0)} views • ${shopAdCount(data.taps[ad.id] ?? 0)} taps',
              key: ValueKey('right-box-views-$number'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (box.imageUrl.isEmpty) const Text('Upload the vendor\'s ad photo: views are counted only while the box shows a photo.'),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: ValueKey('link-right-box-$number'),
                onPressed: busy ? null : () => onChoose(ad),
                icon: const Icon(Icons.link),
                label: Text(ad == null ? 'Link to a vendor' : 'Change vendor'),
              ),
              if (ad != null) TextButton(key: ValueKey('end-right-box-$number'), onPressed: busy ? null : () => onEnd(ad), child: const Text('End ad')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Picks an approved vendor: the ones who want an ad first, then by name; search by name or Vendor ID.
class _VendorPickerDialog extends StatefulWidget {
  const _VendorPickerDialog({required this.vendors, required this.ads, this.current});
  final List<Entry> vendors;
  final List<ShopAd> ads;
  final String? current;
  @override
  State<_VendorPickerDialog> createState() => _VendorPickerDialogState();
}

class _VendorPickerDialogState extends State<_VendorPickerDialog> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = search.text.trim().toLowerCase();
    final shown = [
      for (final v in widget.vendors)
        if (q.isEmpty || v.text('name').toLowerCase().contains(q) || v.text('vendorCode').toLowerCase().contains(q)) v,
    ]..sort((a, b) {
        final wants = (b.data['adInterest'] == true ? 1 : 0) - (a.data['adInterest'] == true ? 1 : 0);
        return wants != 0 ? wants : a.text('name').toLowerCase().compareTo(b.text('name').toLowerCase());
      });
    return AlertDialog(
      title: const Text('Link the box to a vendor'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('shop-ad-vendor-search'),
              controller: search,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Name or Vendor ID', isDense: true),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('No approved vendor found.'))
                  : ListView(
                      children: [
                        for (final v in shown)
                          ListTile(
                            key: ValueKey('pick-vendor-${v.id}'),
                            selected: v.id == widget.current,
                            title: Text(v.text('name', v.id)),
                            subtitle: Text([
                              if (v.text('vendorCode').isNotEmpty) v.text('vendorCode'),
                              if (v.data['adInterest'] == true) 'wants an ad',
                              for (final a in widget.ads) if (a.live && a.vendorId == v.id) 'box ${a.box}',
                            ].join(' • ')),
                            onTap: () => Navigator.pop(context, v.id),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

class _BoxCard extends StatelessWidget {
  const _BoxCard({super.key, required this.number, required this.box, required this.store, required this.busy, required this.onUpload, required this.onWrite, this.shopAd});
  final int number;
  final RightBox box;
  final Store store;
  final bool busy;
  final VoidCallback onUpload;
  final Future<void> Function(Map<String, dynamic> changes, {Set<String> remove}) onWrite;
  // The box's shop ad (live only).
  final Widget? shopAd;

  static const _kinds = {'category': 'A category', 'shop': 'A shop', 'product': 'A product'};

  List<Entry> _items(String kind) => switch (kind) {
    'category' => store.visible('categories'),
    'shop' => store.visible('shops'),
    _ => store.visible('products'),
  };

  @override
  Widget build(BuildContext context) {
    final colon = box.target.indexOf(':');
    final kind = colon > 0 ? box.target.substring(0, colon) : '';
    final itemId = colon > 0 ? box.target.substring(colon + 1) : '';
    final items = kind.isEmpty ? const <Entry>[] : _items(kind);
    final selected = items.any((e) => e.id == itemId) ? itemId : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Right Side Ad Box $number', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                Container(
                  width: 160,
                  height: 160 * rightBoxHeight / 300,
                  decoration: BoxDecoration(
                    color: box.color.isEmpty ? Colors.white : colorFromHex(box.color, Colors.white),
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: box.imageUrl.isEmpty
                      ? const Center(child: Text('No photo\n(shows "your ad here")', textAlign: TextAlign.center))
                      : Image.network(box.imageUrl, fit: BoxFit.cover, errorBuilder: (_, error, stack) => const Center(child: Text('Photo not found'))),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(key: ValueKey('upload-right-box-$number'), onPressed: busy ? null : onUpload, icon: const Icon(Icons.upload), label: Text(box.imageUrl.isEmpty ? 'Upload JPG photo' : 'Replace photo')),
                          if (box.imageUrl.isNotEmpty)
                            TextButton(onPressed: busy ? null : () => onWrite(const {}, remove: {'box${number}Image'}), child: const Text('Remove photo')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        key: ValueKey('right-box-kind-$number-$kind'),
                        initialValue: kind.isEmpty ? '' : kind,
                        decoration: const InputDecoration(labelText: 'Tapping the box opens (optional)', isDense: true, border: OutlineInputBorder()),
                        items: [const DropdownMenuItem(value: '', child: Text('Nothing')), for (final e in _kinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                        onChanged: busy ? null : (v) => (v ?? '').isEmpty ? onWrite(const {}, remove: {'box${number}Target'}) : onWrite({'box${number}Target': '$v:'}),
                      ),
                      if (kind.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          key: ValueKey('right-box-item-$number-$kind-${selected ?? ''}'),
                          initialValue: selected,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: 'Which ${_kinds[kind]?.substring(2) ?? 'item'}', isDense: true, border: const OutlineInputBorder()),
                          items: [for (final e in items) DropdownMenuItem(value: e.id, child: Text(e.text('name', e.id), overflow: TextOverflow.ellipsis))],
                          onChanged: busy ? null : (v) => onWrite({'box${number}Target': '$kind:${v ?? ''}'}),
                        ),
                      ],
                      const SizedBox(height: 10),
                      ColorPickerField(label: 'Background colour', value: box.color, onChanged: (v) => v.isEmpty ? onWrite(const {}, remove: {'box${number}Color'}) : onWrite({'box${number}Color': v})),
                    ],
                  ),
                ),
              ],
            ),
            ?shopAd,
          ],
        ),
      ),
    );
  }
}
