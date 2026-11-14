import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import 'area_map.dart';
import 'hex_cell.dart';
import 'staff_area_model.dart';

/// One vendor or provider waiting with the office after their staff ID was cancelled (a staffLinks document with underAdmin).
class OfficeLink {
  const OfficeLink({required this.id, required this.name, required this.code, required this.previousStaffCode});
  factory OfficeLink.fromData(String id, Map<String, dynamic> d) =>
      OfficeLink(id: id, name: '${d['name'] ?? ''}', code: '${d['code'] ?? ''}', previousStaffCode: '${d['previousStaffCode'] ?? ''}');
  final String id, name, code, previousStaffCode;
}

/// Admin > Staff Areas > Cells (owner, 13 Nov 2026): the hexagon cells staff registered, on the map and in a list with who holds them,
/// and per cell: Free, "Link waiting vendors" (one click: the vendors with the office inside the cell go to its staff member) and
/// "Cancel staff ID" (closed for good; the cell is free and the vendors move to the office). Free cells are not stored anywhere.
class AdminHexCellsTab extends StatelessWidget {
  const AdminHexCellsTab({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('staffAreas').where('hex', isEqualTo: true).snapshots(),
    builder: (context, cells) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('staffAreaHolders').snapshots(),
      builder: (context, holders) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('staffLinks').where('underAdmin', isEqualTo: true).snapshots(),
        builder: (context, office) {
          if (cells.hasError) return const Center(child: Text('The cells could not load.'));
          if (!cells.hasData) return const Center(child: CircularProgressIndicator());
          return AdminHexCellsView(
            cells: [for (final d in cells.data!.docs) StaffArea.fromData(d.id, d.data())],
            holders: {for (final d in holders.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) d.id: AreaHolder.fromData(d.data())},
            office: [for (final d in office.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) OfficeLink.fromData(d.id, d.data())],
            onFree: (cell) => store.call('freeStaffArea', {'areaId': cell.id}),
            onPreviewRelink: (staffUid) => store.call('relinkAreaVendors', {'staffUid': staffUid, 'preview': true}),
            onRelink: (staffUid) => store.call('relinkAreaVendors', {'staffUid': staffUid}),
            onCancelStaff: (staffUid, reason) => store.call('cancelFieldStaff', {'staffUid': staffUid, 'reason': reason}),
          );
        },
      ),
    ),
  );
}

class AdminHexCellsView extends StatelessWidget {
  const AdminHexCellsView({
    super.key,
    required this.cells,
    required this.holders,
    required this.office,
    required this.onFree,
    required this.onPreviewRelink,
    required this.onRelink,
    required this.onCancelStaff,
  });
  final List<StaffArea> cells;
  final Map<String, AreaHolder> holders;
  final List<OfficeLink> office;
  final Future<Object?> Function(StaffArea cell) onFree;
  final Future<Map<String, dynamic>> Function(String staffUid) onPreviewRelink, onRelink;
  final Future<Object?> Function(String staffUid, String reason) onCancelStaff;

  Future<void> _run(BuildContext context, Future<Object?> Function() action, String Function(Object? result) done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await action();
      messenger.showSnackBar(SnackBar(content: Text(done(result))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''))));
    }
  }

  Future<bool> _yes(BuildContext context, String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(title: Text(title), content: Text(body), actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('admin-hex-confirm'), onPressed: () => Navigator.pop(dialog, true), child: const Text('Yes')),
        ]),
      ) ==
      true;

  Future<void> _relink(BuildContext context, StaffArea cell, AreaHolder holder) async {
    final messenger = ScaffoldMessenger.of(context);
    Map<String, dynamic> preview;
    try {
      preview = await onPreviewRelink(holder.staffUid);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''))));
      return;
    }
    final count = (preview['count'] as num?)?.toInt() ?? 0;
    if (!context.mounted) return;
    if (count == 0) {
      messenger.showSnackBar(const SnackBar(content: Text('No vendors with the office are inside this cell.')));
      return;
    }
    final names = ((preview['names'] as List?) ?? const []).join(', ');
    if (await _yes(context, 'Link $count to ${holder.staffCode}?', 'The vendors and providers with the office inside ${cell.hexCode} go to ${holder.staffName} (${holder.staffCode}): $names') && context.mounted) {
      await _run(context, () => onRelink(holder.staffUid), (r) => 'Linked ${(r as Map?)?['count'] ?? count} to ${holder.staffCode}');
    }
  }

  Future<void> _cancel(BuildContext context, AreaHolder holder) async {
    final reason = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Cancel staff ID ${holder.staffCode}?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('The ID is closed for good and never given again. Their cell becomes free and their linked vendors move to the office.'),
            TextField(
              key: const ValueKey('admin-hex-cancel-reason'),
              controller: reason,
              maxLines: 2,
              maxLength: 500,
              onChanged: (_) => setDialogState(() {}),
              decoration: const InputDecoration(labelText: 'Reason (required)'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Back')),
            FilledButton(
              key: const ValueKey('admin-hex-cancel-go'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: reason.text.trim().length < 3 ? null : () => Navigator.pop(dialog, true),
              child: const Text('Cancel the ID'),
            ),
          ],
        ),
      ),
    );
    // Not disposed here: the dialog may still be closing; the controller goes with this call.
    final text = reason.text.trim();
    if (go == true && context.mounted) await _run(context, () => onCancelStaff(holder.staffUid, text), (_) => '${holder.staffCode} is closed for good');
  }

  @override
  Widget build(BuildContext context) {
    final taken = cells.where((c) => !c.free).toList()..sort((a, b) => a.hexCode.compareTo(b.hexCode));
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text(
        'Staff register a hexagon cell standing inside it (1 km in dense cities, 2 km in towns, 5 km in villages, set automatically from '
        'population). One cell per staff member, home within 5 km of the cell\'s centre. Only taken cells are stored.',
      ),
      const Text(worldPopCredit, style: TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 8),
      Text('${taken.length} cells taken • ${taken.where((c) => c.status == 'booked').length} booked • ${taken.where((c) => c.status == 'pending').length} waiting for approval',
          key: const ValueKey('admin-hex-count')),
      if (taken.isNotEmpty) ...[
        const SizedBox(height: 8),
        AreaMap(areas: taken, height: 360),
        const AreaLegend(),
      ],
      for (final cell in taken)
        Card(
          key: ValueKey('admin-hex-${cell.id}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(radius: 8, backgroundColor: areaColour(cell.status)),
                const SizedBox(width: 8),
                Expanded(child: Text('${cell.hexCode} • ${cell.hexSizeKm} km • ${cell.town}', style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
              Text([
                areaStatusLabel(cell.status),
                if (holders[cell.id] case final h?) '${h.staffName} • ${h.staffCode} • ${h.staffPhone}',
              ].join(' • ')),
              Wrap(spacing: 4, children: [
                if (holders[cell.id] case final h?) ...[
                  TextButton(key: ValueKey('admin-hex-relink-${cell.id}'), onPressed: () => _relink(context, cell, h), child: const Text('Link waiting vendors')),
                  TextButton(key: ValueKey('admin-hex-cancel-${cell.id}'), onPressed: () => _cancel(context, h), child: const Text('Cancel staff ID', style: TextStyle(color: Colors.red))),
                ],
                TextButton(
                  key: ValueKey('admin-hex-free-${cell.id}'),
                  onPressed: () async {
                    if (await _yes(context, 'Make ${cell.hexCode} free?', 'The staff member loses this cell and may register another.') && context.mounted) {
                      await _run(context, () => onFree(cell), (_) => '${cell.hexCode} is free');
                    }
                  },
                  child: const Text('Free'),
                ),
              ]),
            ]),
          ),
        ),
      const SizedBox(height: 16),
      Text('With the office (${office.length})', style: Theme.of(context).textTheme.titleMedium, key: const ValueKey('admin-hex-office-count')),
      const Text('Vendors and providers whose staff ID was cancelled. "Link waiting vendors" on the cell\'s new staff member links those inside the cell in one click.'),
      for (final link in office.take(100))
        ListTile(dense: true, key: ValueKey('admin-hex-office-${link.id}'), title: Text('${link.name} • ${link.code}'), subtitle: Text('Was with ${link.previousStaffCode}')),
    ]);
  }
}
