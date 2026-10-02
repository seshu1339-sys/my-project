import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../data/store.dart';
import 'admin.dart';
import 'staff_detail_page.dart';
import 'vendor_detail_page.dart';

enum _Kind { vendor, staff, shop }

class _Result {
  const _Result(this.kind, this.id, this.name, this.code);
  final _Kind kind;
  final String id;
  final String name;
  final String? code;
}

/// Admin Panel's unified search: one box that matches a Vendor ID, Staff ID,
/// Shop ID, or name across vendors/fieldStaff/shops, and opens the exact
/// matching profile. Reached via admin.dart's existing navTargets mechanism,
/// same as every other moderation page — no change to how those pages work.
class AdminSearchPage extends StatefulWidget {
  const AdminSearchPage({super.key, required this.store});
  final Store store;
  @override
  State<AdminSearchPage> createState() => _AdminSearchPageState();
}

class _AdminSearchPageState extends State<AdminSearchPage> {
  final search = TextEditingController();
  bool backfilling = false;
  // Guards the auto-open below so it fires once per exact-match query, not on
  // every rebuild (e.g. a Firestore snapshot update while the result is open).
  String? _autoOpenedFor;
  Store get store => widget.store;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  bool _matches(String query, String name, String? code, String id) {
    if (query.isEmpty) return true;
    final q = query.trim().toLowerCase();
    if (code != null && code.toLowerCase() == q) return true;
    if (id.toLowerCase() == q) return true;
    return name.toLowerCase().contains(q);
  }

  Future<void> _backfill() async {
    setState(() => backfilling = true);
    try {
      final result = await FirebaseFunctions.instance.httpsCallable('backfillSequentialIds').call();
      final counts = result.data as Map;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          'Assigned IDs — vendors: ${counts['vendors']}, staff: ${counts['fieldStaff']}, shops: ${counts['shops']}',
        )));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() => backfilling = false);
  }

  void _open(_Result result) {
    switch (result.kind) {
      case _Kind.vendor:
        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => VendorDetailPage(store: store, vendorUid: result.id)));
      case _Kind.staff:
        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => StaffDetailPage(store: store, staffUid: result.id)));
      case _Kind.shop:
        final entry = store.entries('shops').where((e) => e.id == result.id).firstOrNull;
        if (entry != null) {
          Navigator.push(context, MaterialPageRoute<void>(builder: (_) => EntryEditor(store: store, collection: 'shops', entry: entry)));
        }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Search'), actions: [
      TextButton.icon(
        onPressed: backfilling ? null : _backfill,
        icon: backfilling ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_fix_high),
        label: const Text('Backfill missing IDs'),
      ),
    ]),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Search by Vendor ID, Staff ID, Shop ID, or name',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: store.firestore.collection('vendors').snapshots(),
            builder: (context, vendorSnapshot) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: store.firestore.collection('fieldStaff').snapshots(),
              builder: (context, staffSnapshot) {
                final query = search.text;
                final results = <_Result>[
                  for (final doc in vendorSnapshot.data?.docs ?? const [])
                    if (_matches(query, (doc.data()['name'] ?? doc.id).toString(), doc.data()['vendorCode'] as String?, doc.id))
                      _Result(_Kind.vendor, doc.id, (doc.data()['name'] ?? doc.id).toString(), doc.data()['vendorCode'] as String?),
                  for (final doc in staffSnapshot.data?.docs ?? const [])
                    if (_matches(query, (doc.data()['name'] ?? doc.id).toString(), doc.data()['staffCode'] as String?, doc.id))
                      _Result(_Kind.staff, doc.id, (doc.data()['name'] ?? doc.id).toString(), doc.data()['staffCode'] as String?),
                  for (final entry in store.entries('shops'))
                    if (_matches(query, entry.text('name'), entry.text('shopCode').isEmpty ? null : entry.text('shopCode'), entry.id))
                      _Result(_Kind.shop, entry.id, entry.text('name'), entry.text('shopCode').isEmpty ? null : entry.text('shopCode')),
                ];
                // "entering a Vendor or Staff ID instantly shows the full profile":
                // an exact code or uid match (vendor/staff only, not shop) opens
                // straight to the detail page instead of waiting for a tap.
                final exactQuery = query.trim().toLowerCase();
                final exactMatch = results.where((r) =>
                  r.kind != _Kind.shop &&
                  ((r.code != null && r.code!.toLowerCase() == exactQuery) || r.id.toLowerCase() == exactQuery)
                ).firstOrNull;
                if (exactMatch != null && exactQuery.isNotEmpty && _autoOpenedFor != exactQuery) {
                  _autoOpenedFor = exactQuery;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _open(exactMatch);
                  });
                }
                if (query.isEmpty) return const Center(child: Text('Type a Vendor ID, Staff ID, Shop ID, or name to search.'));
                if (results.isEmpty) return const Center(child: Text('No matches.'));
                return ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final r = results[i];
                    final kindLabel = switch (r.kind) { _Kind.vendor => 'Vendor', _Kind.staff => 'Staff', _Kind.shop => 'Shop' };
                    final kindIcon = switch (r.kind) { _Kind.vendor => Icons.storefront, _Kind.staff => Icons.badge_outlined, _Kind.shop => Icons.store_outlined };
                    return Card(child: ListTile(
                      leading: Icon(kindIcon),
                      title: Text(r.name),
                      subtitle: Text('$kindLabel${r.code != null ? ' • ${r.code}' : ''}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(r),
                    ));
                  },
                );
              },
            ),
          ),
        ),
      ]),
    ),
  );
}
