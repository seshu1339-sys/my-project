import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';
import '../domain/ad_reports.dart';
import '../domain/catalog.dart';
import '../services/file_download.dart';
import '../services/report_export.dart';
import 'shared.dart';

String dayText(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Settings -> Ads -> Reports: what the server counted for the ads, by date, ad, shop, town and device, with a daily graph,
/// downloads (Excel, PDF) and a WhatsApp share. The live totals at the top update by themselves as customers see the ads.
class AdReportsPage extends StatefulWidget {
  const AdReportsPage({super.key, required this.store, this.vendorId, this.today});
  final Store store;
  // A vendor passes their own id and sees only their own ads.
  final String? vendorId;
  final DateTime? today;
  @override
  State<AdReportsPage> createState() => _AdReportsPageState();
}

class _AdReportsPageState extends State<AdReportsPage> {
  late DateTime to = widget.today ?? DateTime.now();
  late DateTime from = to.subtract(const Duration(days: 29));
  String adId = '', shop = '', town = '', device = '';
  List<Entry> daily = const [];
  bool loading = true;
  String? error;

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await store.dailyAdStats(dayText(from), dayText(to), vendorId: widget.vendorId);
      if (mounted) setState(() => daily = rows);
    } catch (e) {
      if (mounted) setState(() => error = 'The report could not load: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<Entry> get ads => [for (final a in store.entries('ads')) if (widget.vendorId == null || a.text('vendorId') == widget.vendorId) a];
  String titleOf(String id) => ads.where((a) => a.id == id).map((a) => a.text('title', a.text('name'))).firstOrNull ?? id;

  Set<String>? get adFilter {
    if (adId.isNotEmpty) return {adId};
    if (shop.isNotEmpty) return {for (final a in ads) if (a.text('shopName') == shop) a.id};
    return null;
  }

  AdReport get report => AdReport.build(daily, adIds: adFilter, town: town.isEmpty ? null : town, device: device.isEmpty ? null : device);

  Future<void> _pick(bool isFrom) async {
    final picked = await showDatePicker(context: context, initialDate: isFrom ? from : to, firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 1)));
    if (picked == null) return;
    setState(() => isFrom ? from = picked : to = picked);
    if (from.isAfter(to)) setState(() => isFrom ? to = from : from = to);
    _load();
  }

  void _quick(int days) {
    setState(() {
      to = widget.today ?? DateTime.now();
      from = to.subtract(Duration(days: days - 1));
    });
    _load();
  }

  List<ReportTable> _tables(AdReport r) {
    List<Object> line(String label, AdTotals t) => [label, t.views, if (r.uniqueKnown) t.unique, t.taps, t.seconds, t.missed, t.scheduled];
    final head = ['', 'Views', if (r.uniqueKnown) 'Unique people', 'Taps', 'Seconds on screen', 'Missed', 'Scheduled'];
    return [
      ReportTable('Per day', ['Day', ...head.skip(1)], [for (final d in r.days(dayText(from), dayText(to))) line(d.$1, d.$2)]),
      ReportTable('Per ad', ['Ad', ...head.skip(1)], [for (final e in r.byAd.entries) line(titleOf(e.key), e.value)]),
      ReportTable('Per town', ['Town', ...head.skip(1).where((h) => h != 'Unique people')], [for (final e in r.byTown.entries) [townLabel(e.key), e.value.views, e.value.taps, e.value.seconds, e.value.missed, e.value.scheduled]]),
      ReportTable('Per device', ['Device', ...head.skip(1).where((h) => h != 'Unique people')], [for (final e in r.byDevice.entries) [e.key == 'android' ? 'App' : 'Website', e.value.views, e.value.taps, e.value.seconds, e.value.missed, e.value.scheduled]]),
    ];
  }

  Future<void> _export(String kind) async {
    final r = report;
    final range = '${dayText(from)}_${dayText(to)}';
    try {
      if (kind == 'xlsx') {
        await downloadFile('ads-report-$range.xlsx', buildXlsx(_tables(r)), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      } else if (kind == 'csv') {
        await downloadFile('ads-report-$range.csv', buildCsv(_tables(r)[1]), 'text/csv');
      } else {
        await downloadFile('ads-report-$range.pdf', await buildPdf('Ads report', reportSummaryText(r, from: dayText(from), to: dayText(to), title: 'Ads report'), _tables(r)), 'application/pdf');
      }
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  Future<void> _share() async {
    final text = reportSummaryText(report, from: dayText(from), to: dayText(to));
    final ok = await launchUrl(Uri.https('wa.me', '/', {'text': text}), mode: LaunchMode.externalApplication);
    if (!ok && mounted) message(context, 'Could not open WhatsApp.');
  }

  Future<void> _log(String id) async {
    final rows = await store.recentAdViews(id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Counted views and taps — ${titleOf(id)}'),
        content: SizedBox(
          width: 520,
          height: 360,
          child: rows.isEmpty
              ? const Text('Nothing counted yet.')
              : ListView(
                  key: const ValueKey('view-log'),
                  children: [
                    for (final v in rows)
                      ListTile(
                        dense: true,
                        leading: Icon(v.text('type') == 'tap' ? Icons.touch_app : Icons.visibility),
                        title: Text('${v.text('type') == 'tap' ? 'Tap' : 'View'} · ${v.text('town', 'unknown town')} · ${v.text('device') == 'android' ? 'App' : 'Website'}'),
                        subtitle: Text(_when(v.data['at'])),
                      ),
                  ],
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close'))],
      ),
    );
  }

  String _when(Object? at) {
    final dynamic value = at;
    DateTime? t;
    if (value is DateTime) t = value;
    if (value != null && t == null) {
      try {
        t = (value as dynamic).toDate() as DateTime;
      } catch (_) {
        t = DateTime.tryParse('$value');
      }
    }
    if (t == null) return '';
    t = t.toLocal();
    return '${dayText(t)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  }

  Widget _card(String label, Object value) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$value', style: Theme.of(context).textTheme.headlineSmall), Text(label)]),
    ),
  );

  Widget _table(String title, List<(String, AdTotals, String?)> rows, {required bool unique}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(padding: const EdgeInsets.only(top: 16, bottom: 4), child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
      if (rows.isEmpty)
        const Text('No numbers in this range.')
      else
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 20,
            columns: [
              const DataColumn(label: Text('')),
              const DataColumn(label: Text('Views'), numeric: true),
              if (unique) const DataColumn(label: Text('People'), numeric: true),
              const DataColumn(label: Text('Taps'), numeric: true),
              const DataColumn(label: Text('Seconds'), numeric: true),
              const DataColumn(label: Text('Missed'), numeric: true),
              const DataColumn(label: Text('')),
            ],
            rows: [
              for (final r in rows)
                DataRow(cells: [
                  DataCell(Text(r.$1)),
                  DataCell(Text('${r.$2.views}')),
                  if (unique) DataCell(Text('${r.$2.unique}')),
                  DataCell(Text('${r.$2.taps}')),
                  DataCell(Text('${r.$2.seconds}')),
                  DataCell(Text('${r.$2.missed}')),
                  DataCell(r.$3 == null ? const SizedBox.shrink() : TextButton(onPressed: () => _log(r.$3!), child: const Text('Check views'))),
                ]),
            ],
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final r = report;
    final shops = {for (final a in ads) if (a.text('shopName').isNotEmpty) a.text('shopName')}.toList()..sort();
    final towns = <String>{for (final d in daily) ...(((d.data['towns'] as Map?) ?? const {}).keys.map((k) => '$k'))}.toList()..sort();
    final days = r.days(dayText(from), dayText(to));
    return Scaffold(
      appBar: AppBar(title: const Text('Ad reports')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          StreamBuilder<List<Entry>>(
            stream: store.watchEntries('adStats', vendorId: widget.vendorId),
            builder: (context, snapshot) {
              final live = AdTotals();
              for (final s in snapshot.data ?? const <Entry>[]) {
                if (adId.isNotEmpty && s.id != adId) continue;
                live.add(s.data);
              }
              return Wrap(
                key: const ValueKey('live-totals'),
                spacing: 12,
                children: [_card('Total views, all time (live)', live.views), _card('Unique people, all time', live.unique), _card('Taps, all time', live.taps)],
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(key: const ValueKey('report-from'), onPressed: () => _pick(true), icon: const Icon(Icons.event), label: Text('From ${dayText(from)}')),
              OutlinedButton.icon(key: const ValueKey('report-to'), onPressed: () => _pick(false), icon: const Icon(Icons.event), label: Text('To ${dayText(to)}')),
              TextButton(key: const ValueKey('report-7'), onPressed: () => _quick(7), child: const Text('Last 7 days')),
              TextButton(key: const ValueKey('report-30'), onPressed: () => _quick(30), child: const Text('Last 30 days')),
              SizedBox(width: 220, child: _drop('report-ad', 'Ad', adId, {for (final a in ads) a.id: a.text('title', a.text('name'))}, (v) => setState(() => adId = v))),
              if (widget.vendorId == null) SizedBox(width: 200, child: _drop('report-shop', 'Shop', shop, {for (final s in shops) s: s}, (v) => setState(() => shop = v))),
              SizedBox(width: 200, child: _drop('report-town', 'Location', town, {for (final t in towns) t: townLabel(t)}, (v) => setState(() => town = v))),
              SizedBox(width: 180, child: _drop('report-device', 'Device', device, const {'web': 'Website', 'android': 'App'}, (v) => setState(() => device = v))),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(key: const ValueKey('export-xlsx'), onPressed: () => _export('xlsx'), icon: const Icon(Icons.table_chart), label: const Text('Excel')),
              FilledButton.icon(key: const ValueKey('export-pdf'), onPressed: () => _export('pdf'), icon: const Icon(Icons.picture_as_pdf), label: const Text('PDF')),
              OutlinedButton.icon(key: const ValueKey('export-csv'), onPressed: () => _export('csv'), icon: const Icon(Icons.description), label: const Text('CSV')),
              OutlinedButton.icon(key: const ValueKey('share-whatsapp'), onPressed: _share, icon: const Icon(Icons.share), label: const Text('Share on WhatsApp')),
            ],
          ),
          if (error != null) Padding(padding: const EdgeInsets.all(8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())) else ...[
            const SizedBox(height: 12),
            Wrap(
              key: const ValueKey('range-totals'),
              spacing: 12,
              children: [
                _card('Total views', r.total.views),
                if (r.uniqueKnown) _card('Unique people', r.total.unique),
                _card('Taps', r.total.taps),
                _card('Seconds on screen', r.total.seconds),
                _card('Scheduled but missed', r.total.missed),
              ],
            ),
            if (!r.uniqueKnown) const Text('Unique people is counted per ad, so it is hidden while a location or device is chosen.', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            SizedBox(height: 180, child: CustomPaint(key: const ValueKey('daily-graph'), painter: DailyGraphPainter([for (final d in days) d.$2.views], [for (final d in days) d.$2.taps], Theme.of(context).colorScheme.primary), size: Size.infinite)),
            Text('Daily views (bars) and taps (line): ${days.first.$1} to ${days.last.$1}', style: const TextStyle(fontSize: 12)),
            _table('Per day', [for (final d in days.reversed) if (d.$2.scheduled > 0 || d.$2.taps > 0) (d.$1, d.$2, null)], unique: r.uniqueKnown),
            _table('Per ad', [for (final e in r.byAd.entries) (titleOf(e.key), e.value, e.key)], unique: r.uniqueKnown),
            _table('Per location', [for (final e in r.byTown.entries) (townLabel(e.key), e.value, null)], unique: false),
            _table('Per device', [for (final e in r.byDevice.entries) (e.key == 'android' ? 'App' : 'Website', e.value, null)], unique: false),
          ],
        ],
      ),
    );
  }

  Widget _drop(String key, String label, String value, Map<String, String> options, ValueChanged<String> onChanged) => DropdownButtonFormField<String>(
    key: ValueKey('$key-$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
    items: [DropdownMenuItem(value: '', child: Text('All')), for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
    onChanged: (v) => onChanged(v ?? ''),
  );
}

/// Bars for the days' views and a line for their taps.
class DailyGraphPainter extends CustomPainter {
  DailyGraphPainter(this.views, this.taps, this.color);
  final List<int> views, taps;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (views.isEmpty) return;
    final top = [...views, ...taps, 1].reduce((a, b) => a > b ? a : b).toDouble();
    final slot = size.width / views.length;
    final bar = Paint()..color = color.withValues(alpha: .7);
    for (var i = 0; i < views.length; i++) {
      final h = size.height * views[i] / top;
      canvas.drawRect(Rect.fromLTWH(i * slot + slot * .15, size.height - h, slot * .7, h), bar);
    }
    final line = Paint()
      ..color = Colors.deepOrange
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < taps.length; i++) {
      final p = Offset(i * slot + slot / 2, size.height - size.height * taps[i] / top);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant DailyGraphPainter old) => old.views != views || old.taps != taps || old.color != color;
}
