import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/shop_ads.dart';
import 'moderation_dialogs.dart';
import 'photo_check.dart';
import 'shop_map.dart';
import 'text_prompt_dialog.dart';

/// Every photo of a staff addition: the vendor's (or the provider's work) photos, then each item's.
List<String> staffAdditionPhotos(Map<String, dynamic> addition) => [
  for (final p in addition['photoPaths'] as List? ?? const []) '$p',
  for (final item in (addition['items'] as List? ?? const []).cast<Map>())
    for (final p in item['photoPaths'] as List? ?? const []) '$p',
];

/// Admin > Field Assistant approvals > Added by staff: the vendors and service providers staff added (functions/staff-additions.js),
/// waiting for approval. Under every photo is a "Google check" (functions/photo-check.js: is the picture online, was the same photo
/// used before); Approve works only once every photo is checked, and then the vendor or provider goes live at once. Reject needs a
/// reason, which the staff member sees.
class StaffAdditionsReviewPage extends StatelessWidget {
  const StaffAdditionsReviewPage({super.key, required this.store, this.additions, this.checksFor, this.photo, this.usage});
  final Store store;
  // Test seams: the pending additions, each one's check results (by photo path), how a photo is shown, and the month's usage line.
  final Stream<List<Entry>>? additions;
  final Stream<Map<String, Map<String, dynamic>>> Function(String additionId)? checksFor;
  final Widget Function(String path)? photo;
  final Widget? usage;

  Stream<List<Entry>> _pending() => store.firestore
      .collection('staffAdditions')
      .where('status', isEqualTo: 'pending')
      .limit(100)
      .snapshots()
      .map((s) => [for (final d in s.docs) Entry(d.id, d.data())]);

  Stream<Map<String, Map<String, dynamic>>> _checks(String additionId) => store.firestore
      .collection('photoChecks')
      .where('ownerId', isEqualTo: additionId)
      .snapshots()
      .map((s) => {for (final d in s.docs) '${d.data()['path']}': d.data()});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Added by staff')),
    body: StreamBuilder<List<Entry>>(
      stream: additions ?? _pending(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('The staff additions could not load.'));
        final list = [...?snapshot.data]..sort((a, b) => '${shopAdTime(a.data['submittedAt']) ?? ''}'.compareTo('${shopAdTime(b.data['submittedAt']) ?? ''}'));
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Vendors and service providers added by staff', style: Theme.of(context).textTheme.headlineSmall),
            Text(snapshot.hasData ? '${list.length} waiting for approval, oldest first. Check every photo with Google, then approve: it goes live at once.' : 'Loading...'),
            usage ?? PhotoCheckUsage(store: store),
            const SizedBox(height: 12),
            if (snapshot.hasData && list.isEmpty) const Text('Nothing is waiting.'),
            for (final a in list)
              _AdditionCard(
                key: ValueKey('staff-review-${a.id}'),
                store: store,
                addition: a,
                checks: (checksFor ?? _checks)(a.id),
                photo: photo ?? (path) => ApplicationPhoto(path: path, height: 150, width: 200),
              ),
          ],
        );
      },
    ),
  );
}

class _AdditionCard extends StatefulWidget {
  const _AdditionCard({super.key, required this.store, required this.addition, required this.checks, required this.photo});
  final Store store;
  final Entry addition;
  final Stream<Map<String, Map<String, dynamic>>> checks;
  final Widget Function(String path) photo;
  @override
  State<_AdditionCard> createState() => _AdditionCardState();
}

class _AdditionCardState extends State<_AdditionCard> {
  final checking = <String>{};
  bool deciding = false;
  late final Stream<Map<String, Map<String, dynamic>>> checks = widget.checks;

  Entry get a => widget.addition;
  Store get store => widget.store;

  void toast(Object m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$m')));

  Future<void> _check(String path) async {
    setState(() => checking.add(path));
    try {
      await store.call('checkPhoto', {'path': path});
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => checking.remove(path));
    }
  }

  Future<void> _decide({required bool approved}) async {
    var reason = '';
    if (!approved) {
      final text = await askText(context, title: 'Not approve this?', label: 'Reason (the staff member sees it)', confirm: 'Reject', maxLines: 2, fieldKey: ValueKey('staff-reject-reason-${a.id}'));
      if (text == null || !mounted) return;
      if (text.length < 3) return toast('Give the staff member the reason.');
      reason = text;
    }
    setState(() => deciding = true);
    try {
      await store.call('reviewStaffAddition', {'additionId': a.id, 'approved': approved, if (!approved) 'reason': reason});
      if (mounted) toast(approved ? 'Approved: it is live now.' : 'Not approved. The staff member sees the reason.');
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => deciding = false);
    }
  }

  Widget _photoWithCheck(String path, String label, Map<String, Map<String, dynamic>> results) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      widget.photo(path),
      PhotoCheckView(path: path, result: results[path], busy: checking.contains(path), onCheck: deciding ? null : () => _check(path)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final provider = a.text('kind') == 'provider';
    final person = Map<String, dynamic>.from((provider ? a.data['provider'] : a.data['vendor']) as Map? ?? const {});
    final code = provider ? a.text('providerCode') : a.text('vendorCode');
    final items = (a.data['items'] as List? ?? const []).cast<Map>();
    final photos = staffAdditionPhotos(a.data);
    final added = shopAdDate(shopAdTime(a.data['submittedAt']));
    return StreamBuilder<Map<String, Map<String, dynamic>>>(
      stream: checks,
      builder: (context, snapshot) {
        final results = snapshot.data ?? const <String, Map<String, dynamic>>{};
        final checked = photos.where(results.containsKey).length;
        final allChecked = checked == photos.length;
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(provider ? Icons.home_repair_service_outlined : Icons.storefront_outlined),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${person['name'] ?? ''}${provider ? ' • ${a.text('serviceName')}' : ''}', style: Theme.of(context).textTheme.titleMedium)),
                ]),
                Text('${provider ? 'Provider' : 'Vendor'} ID: $code • Phone: ${person['phone'] ?? ''}'),
                Text('Added by ${a.text('staffName', 'staff')}${a.text('staffCode').isEmpty ? '' : ' (${a.text('staffCode')})'}${added.isEmpty ? '' : ' on $added'}'),
                if (provider) Text('Charge: ₹${a.data['hourlyRate'] ?? ''} per hour'),
                if ('${person['ownerName'] ?? ''}'.isNotEmpty) Text('Owner: ${person['ownerName']}'),
                if ('${person['shopCategory'] ?? ''}'.isNotEmpty) Text('Category: ${person['shopCategory']}'),
                if ('${person['address'] ?? ''}'.isNotEmpty) Text('Address: ${person['address']}'),
                Text('Place: ${[a.text('town'), a.text('pincode')].where((v) => v.isNotEmpty).join(' ')}'),
                if ('${person['description'] ?? ''}'.isNotEmpty) Text('About: ${person['description']}'),
                if (a.data['latitude'] is num && a.data['longitude'] is num)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ShopMap(shops: [Entry(a.id, {'name': '${person['name'] ?? ''}', 'latitude': a.data['latitude'], 'longitude': a.data['longitude']})], height: 160),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(provider ? 'Photos of their work' : 'Vendor photos', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final (i, path) in [for (final p in a.data['photoPaths'] as List? ?? const []) '$p'].indexed)
                    _photoWithCheck(path, provider ? 'Work photo ${i + 1}' : i == 0 ? 'Vendor / shop photo' : 'Extra photo $i', results),
                ]),
                for (final (i, item) in items.indexed) ...[
                  const SizedBox(height: 12),
                  Text('Item ${i + 1}: ${item['name'] ?? ''} • ₹${item['price'] ?? ''} for ${item['unit'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final (n, path) in [for (final p in item['photoPaths'] as List? ?? const []) '$p'].indexed) _photoWithCheck(path, 'Photo ${n + 1}', results),
                  ]),
                ],
                const SizedBox(height: 12),
                Text('$checked of ${photos.length} photos checked with Google', key: ValueKey('staff-review-checked-${a.id}'), style: TextStyle(fontWeight: FontWeight.bold, color: allChecked ? const Color(0xFF15803D) : null)),
                const SizedBox(height: 8),
                OverflowBar(
                  spacing: 8,
                  children: [
                    Tooltip(
                      message: allChecked ? 'Goes live at once' : 'Check every photo with Google first',
                      child: FilledButton(
                        key: ValueKey('staff-approve-${a.id}'),
                        onPressed: allChecked && !deciding ? () => _decide(approved: true) : null,
                        child: const Text('Approve'),
                      ),
                    ),
                    OutlinedButton(key: ValueKey('staff-reject-${a.id}'), onPressed: deciding ? null : () => _decide(approved: false), child: const Text('Reject')),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
