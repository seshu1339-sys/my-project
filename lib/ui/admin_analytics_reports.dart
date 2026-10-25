import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/right_boxes.dart';
import '../domain/usage_report.dart';
import '../services/file_download.dart';
import '../services/report_export.dart';
import '../services/usage_buttons.dart';

/// The report tables of a range: the same ones on screen and in the Excel download.
List<ReportTable> usageTables(UsageReport r, {List<Entry> adStats = const [], List<Entry> ads = const []}) {
  String adTitle(String id) => ads.where((a) => a.id == id).map((a) => a.text('title', a.text('name'))).firstOrNull ?? rightBoxAdTitle(id) ?? id;
  List<List<Object>> keyRows(String event) => [for (final row in r.top(event)) [row.label.isEmpty ? row.key : row.label, if (row.town.isNotEmpty) row.town else '', row.count]];
  final shops = r.merged(['shop_call', 'shop_whatsapp', 'shop_directions']);
  final workers = r.merged(['worker_call', 'worker_whatsapp']);
  final used = {for (final row in [...r.top('screen_view', max: 1000), ...r.top('button', max: 1000)]) row.key: row.count};
  return [
    ReportTable('Totals', ['What', 'Count'], [for (final e in usageEventLabels.entries) [e.value, r.total(e.key)]]),
    ReportTable('Shops: calls, WhatsApp, directions', ['Shop', 'Town', 'Calls', 'WhatsApp', 'Directions', 'Total'], [
      for (final s in shops) [s.label.isEmpty ? s.key : s.label, s.town, s.counts['shop_call'] ?? 0, s.counts['shop_whatsapp'] ?? 0, s.counts['shop_directions'] ?? 0, s.total],
    ]),
    ReportTable('Most searched', ['Search', 'Town', 'Times'], keyRows('search')),
    ReportTable('Searched but nothing found (items or shops to add)', ['Search', 'Town', 'Times'], keyRows('search_no_result')),
    ReportTable('Map opened after choosing an item', ['Item', 'Town', 'Times'], keyRows('map_view')),
    ReportTable('Price list seen (lowest price first)', ['Item', 'Town', 'Times'], keyRows('price_list_view')),
    ReportTable('Services opened', ['Service', 'Town', 'Times'], keyRows('service_open')),
    ReportTable('Service workers: calls and WhatsApp', ['Worker', 'Town', 'Calls', 'WhatsApp', 'Total'], [
      for (final w in workers) [w.label.isEmpty ? w.key : w.label, w.town, w.counts['worker_call'] ?? 0, w.counts['worker_whatsapp'] ?? 0, w.total],
    ]),
    ReportTable('Towns customers choose', ['Town', '', 'Times'], keyRows('location_change')),
    ReportTable("Today's Offers boxes tapped", ['Offer', 'Town', 'Taps'], keyRows('offer_click')),
    ReportTable('Ads: views and taps (all time)', ['Ad', 'Views', 'Taps'], [
      for (final s in [...adStats]..sort((a, b) => b.number('views').compareTo(a.number('views')))) [adTitle(s.id), s.number('views').round(), s.number('taps').round()],
    ]),
    ReportTable('Transport tapped (coming soon): demand by day', ['Day', 'Taps'], [
      for (final e in (r.byDay('transport_click').entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) [e.key, e.value],
    ]),
    ReportTable('Vendor registrations by town', ['Town', '', 'Registrations'], keyRows('vendor_register')),
    ReportTable('Items vendors add', ['Item', 'Town', 'Times'], keyRows('item_added')),
    ReportTable('Price changes', ['Item', 'Town', 'Changes'], keyRows('price_changed')),
    ReportTable('"Ad for your shop" ticks', ['Vendor', 'Town', 'Ticks'], keyRows('ad_interest')),
    ReportTable('Added by staff', ['Staff', 'Town', 'Added'], keyRows('staff_added')),
    ReportTable('Screens and buttons: used and never used', ['App', 'Screen / button', 'Used'], [
      for (final item in [...usageItems]..sort((a, b) => (used[a.id] ?? 0).compareTo(used[b.id] ?? 0))) [item.app, item.label, used[item.id] ?? 0],
    ]),
  ];
}

/// Admin > Insights > Analytics > Reports: what people did in the apps over the last 7, 30 or 90 days (functions/usage.js), in
/// tables, with an Excel download of all of them.
class AnalyticsReportsView extends StatefulWidget {
  const AnalyticsReportsView({super.key, required this.store, this.load, this.loadAds});
  final Store store;
  // Test seams: the usageDaily records of a range, and the ads' totals.
  final Future<List<Entry>> Function(String from, String to)? load;
  final Future<List<Entry>> Function()? loadAds;
  @override
  State<AnalyticsReportsView> createState() => _AnalyticsReportsViewState();
}

class _AnalyticsReportsViewState extends State<AnalyticsReportsView> {
  int days = 7;
  UsageReport? report;
  List<Entry> adStats = const [];
  String? error;
  bool loading = true;
  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<Entry>> _daily(String from, String to) async {
    final snapshot = await store.firestore.collection('usageDaily').where('day', isGreaterThanOrEqualTo: from).where('day', isLessThanOrEqualTo: to).limit(4000).get();
    return [for (final d in snapshot.docs) Entry(d.id, d.data())];
  }

  Future<List<Entry>> _ads() async {
    final snapshot = await store.firestore.collection('adStats').limit(500).get();
    return [for (final d in snapshot.docs) Entry(d.id, d.data())];
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final now = DateTime.now();
      final rows = await (widget.load ?? _daily)(usageDay(now.subtract(Duration(days: days - 1))), usageDay(now));
      final ads = await (widget.loadAds ?? _ads)();
      if (mounted) {
        setState(() {
          report = UsageReport.build(rows);
          adStats = ads;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = 'The report could not load: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _excel(List<ReportTable> tables) async {
    try {
      await downloadFile('analytics-last-$days-days-${usageDay(DateTime.now())}.xlsx', buildXlsx(tables), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not download: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = report;
    final tables = r == null ? const <ReportTable>[] : usageTables(r, adStats: adStats, ads: store.entries('ads'));
    return ListView(
      key: const ValueKey('analytics-reports'),
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 7, label: Text('7 days')), ButtonSegment(value: 30, label: Text('30 days')), ButtonSegment(value: 90, label: Text('90 days'))],
              selected: {days},
              onSelectionChanged: (v) {
                setState(() => days = v.first);
                _load();
              },
            ),
            FilledButton.icon(
              key: const ValueKey('analytics-excel'),
              onPressed: tables.isEmpty ? null : () => _excel(tables),
              icon: const Icon(Icons.table_chart),
              label: const Text('Excel download'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Counted from the apps (only counts, no one is followed). The Firebase Analytics dashboard has more: live users, retention, phones.'),
        if (error != null) Padding(padding: const EdgeInsets.all(8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (!loading && r != null) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in usageEventLabels.entries)
                if (!const {'screen_view', 'button'}.contains(e.key))
                  SizedBox(
                    width: 170,
                    child: Card(
                      key: ValueKey('analytics-total-${e.key}'),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${r.total(e.key)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                          Text(e.value, style: const TextStyle(fontSize: 12)),
                        ]),
                      ),
                    ),
                  ),
            ],
          ),
          for (final t in tables.skip(1)) _TableCard(table: t),
        ],
      ],
    );
  }
}

/// One report table, opened to see its rows (the first 50).
class _TableCard extends StatelessWidget {
  const _TableCard({required this.table});
  final ReportTable table;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 10),
    child: ExpansionTile(
      key: ValueKey('analytics-table-${table.title}'),
      title: Text(table.title),
      subtitle: Text(table.rows.isEmpty ? 'Nothing yet' : '${table.rows.length} row${table.rows.length == 1 ? '' : 's'}'),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        if (table.rows.isEmpty) const Align(alignment: Alignment.centerLeft, child: Text('Nothing counted in this range.')),
        if (table.rows.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 40,
              columns: [for (final h in table.header) DataColumn(label: Text(h, style: const TextStyle(fontWeight: FontWeight.bold)))],
              rows: [for (final row in table.rows.take(50)) DataRow(cells: [for (final c in row) DataCell(Text('$c'))])],
            ),
          ),
      ],
    ),
  );
}
