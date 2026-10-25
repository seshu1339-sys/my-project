import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/shop_ads.dart';
import '../domain/staff_report.dart';

/// Admin > Field Assistant approvals > Staff report: every field-staff member with their Staff ID and phone and how many vendors and
/// service providers they added (live, waiting, not approved), the ones who added the most first. Opening a staff member lists everyone
/// they added, with each one's ID and phone. A search finds a staff member, or the staff member who added a given vendor or provider.
class StaffReportPage extends StatefulWidget {
  const StaffReportPage({super.key, required this.store, this.staff, this.additions});
  final Store store;
  // Test seams: the staff records and the staff additions.
  final Stream<List<Entry>>? staff, additions;
  @override
  State<StaffReportPage> createState() => _StaffReportPageState();
}

class _StaffReportPageState extends State<StaffReportPage> {
  final search = TextEditingController();
  Store get store => widget.store;

  Stream<List<Entry>> _watch(String collection, int limit) =>
      store.firestore.collection(collection).limit(limit).snapshots().map((s) => [for (final d in s.docs) Entry(d.id, d.data())]);

  late final Stream<List<Entry>> staff = widget.staff ?? _watch('fieldStaff', 500);
  late final Stream<List<Entry>> additions = widget.additions ?? _watch('staffAdditions', 3000);

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Staff report')),
    body: StreamBuilder<List<Entry>>(
      stream: staff,
      builder: (context, staffSnapshot) => StreamBuilder<List<Entry>>(
        stream: additions,
        builder: (context, additionSnapshot) {
          if (staffSnapshot.hasError || additionSnapshot.hasError) return const Center(child: Text('The staff report could not load.'));
          if (!staffSnapshot.hasData || !additionSnapshot.hasData) return const Center(child: CircularProgressIndicator());
          final all = staffAdditionTotals(additionSnapshot.data!);
          final rows = [for (final r in staffReport(staffSnapshot.data!, additionSnapshot.data!)) if (staffReportMatches(r, search.text)) r];
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Who added how many', style: Theme.of(context).textTheme.headlineSmall),
              Text(
                '${staffSnapshot.data!.length} staff • ${all.$1} added • ${all.$2} live • ${all.$3} waiting • ${all.$4} not approved',
                key: const ValueKey('staff-report-totals'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('staff-report-search'),
                controller: search,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search staff, or a vendor / provider they added (name, ID, phone)', border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty) const Text('Nobody matches.'),
              for (final row in rows) _staffCard(context, row),
            ],
          );
        },
      ),
    ),
  );

  Widget _staffCard(BuildContext context, StaffReportRow row) {
    final status = row.staff?.text('status') ?? '';
    return Card(
      key: ValueKey('staff-report-${row.staffId}'),
      child: ExpansionTile(
        title: Text(row.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text([
          if (row.code.isNotEmpty) 'Staff ID: ${row.code}',
          if (row.phone.isNotEmpty) 'Phone: ${row.phone}',
          if (status.isNotEmpty && status != 'active') status[0].toUpperCase() + status.substring(1),
          if (row.staff?.data['autoApprove'] == true) 'Auto-approve on',
        ].join(' • ')),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${row.total} added', key: ValueKey('staff-report-count-${row.staffId}'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            Text('${row.live} live • ${row.waiting} waiting • ${row.rejected} not approved', style: const TextStyle(fontSize: 12)),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (row.additions.isEmpty) const Align(alignment: Alignment.centerLeft, child: Text('Nobody added yet.')),
          for (final a in row.additions) _additionRow(a),
        ],
      ),
    );
  }

  Widget _additionRow(Entry a) {
    final person = staffAdditionPerson(a);
    final provider = a.text('kind') == 'provider';
    final when = shopAdDate(shopAdTime(a.data['submittedAt']));
    return ListTile(
      key: ValueKey('staff-report-addition-${a.id}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(provider ? Icons.home_repair_service_outlined : Icons.storefront_outlined),
      title: Text('${person['name'] ?? ''}${provider ? ' • ${a.text('serviceName')}' : ''}'),
      subtitle: Text([
        '${provider ? 'Provider' : 'Vendor'} ID: ${staffAdditionCode(a)}',
        'Phone: ${person['phone'] ?? ''}',
        if (when.isNotEmpty) when,
      ].join(' • ')),
      trailing: Text(staffAdditionState(a)),
    );
  }
}

/// All additions: (added, live, waiting, not approved).
(int, int, int, int) staffAdditionTotals(List<Entry> additions) => (
  additions.length,
  additions.where((a) => a.text('status') == 'approved').length,
  additions.where((a) => a.text('status') == 'pending').length,
  additions.where((a) => a.text('status') == 'rejected').length,
);
