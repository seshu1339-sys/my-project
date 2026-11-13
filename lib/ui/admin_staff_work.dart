import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/staff_pay.dart';
import '../services/file_download.dart';
import '../services/report_export.dart';
import 'admin_frame.dart';
import 'bar_chart.dart';

// Admin > Staff (owner, 13 Nov 2026), all from functions/modules/staff-work and staff-links:
//   AdminStaffWorkPage     every staff member: ID, phone, area, the vendors linked to them (IDs, phones), today vs the daily target,
//                          the month, the slab reached and the pay; the targets and pay slabs; "Paid" with the history
//   AdminStaffRankingPage  this month's best first (updates, active vendors, target done), by area
//   AdminIdReportPage      one Vendor / provider / Staff ID: everything about it, graphs, monthly Excel / PDF; read only
//   AdminLinkRequestsPage  vendors' "connect me to local staff" requests, and linking any vendor to a staff member of its area

typedef AdminCall = Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> data);

String _money(num v) => '₹${v == v.roundToDouble() ? v.round() : v}';
String _monthOf(DateTime t) => istMonth(t);
List<String> _lastMonths(DateTime now, int n) => [for (var i = 0; i < n; i++) _monthOf(DateTime.utc(now.year, now.month - i, 15))];

Widget _monthPicker(String value, ValueChanged<String> onChanged, {Key? key}) => DropdownButton<String>(
  key: key,
  value: value,
  items: [for (final m in _lastMonths(DateTime.now(), 12)) DropdownMenuItem(value: m, child: Text(m))],
  onChanged: (v) => v == null ? null : onChanged(v),
);

Future<void> _snack(BuildContext context, Future<void> Function() run, String done) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await run();
    messenger.showSnackBar(SnackBar(content: Text(done)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''))));
  }
}

/// Every staff member's work and pay, with the targets and slabs.
class AdminStaffWorkPage extends StatefulWidget {
  const AdminStaffWorkPage({super.key, required this.store, this.call});
  final Store store;
  final AdminCall? call;
  @override
  State<AdminStaffWorkPage> createState() => _AdminStaffWorkPageState();
}

class _AdminStaffWorkPageState extends State<AdminStaffWorkPage> {
  String month = _monthOf(DateTime.now());
  String areaId = '';
  Future<Map<String, dynamic>>? data;
  AdminCall get call => widget.call ?? widget.store.call;

  void _load() => setState(() => data = call('staffWorkOverview', {'month': month, 'areaId': areaId}));

  @override
  void initState() {
    super.initState();
    if (widget.call != null || widget.store.live) _load();
  }

  Future<void> _editSlabs(Map<String, dynamic> config, {Map<String, dynamic>? staff}) async {
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _TargetsDialog(config: config, staff: staff));
    if (result == null || !mounted) return;
    await _snack(context, () async {
      if (staff == null) {
        await call('saveStaffPayConfig', result);
      } else {
        await call('setStaffTargets', {'staffUid': staff['staffUid'], ...result});
      }
      _load();
    }, 'Saved');
  }

  Future<void> _paid(Map<String, dynamic> row) async {
    final note = TextEditingController();
    final amount = TextEditingController(text: '${(row['month']?['pay']?['amount'] as num?) ?? 0}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Mark ${row['staffCode']} paid for $month'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Pay by hand first (bank, UPI or cash); this only records it.'),
          TextField(key: const ValueKey('paid-amount'), controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount paid (₹)')),
          TextField(key: const ValueKey('paid-note'), controller: note, decoration: const InputDecoration(labelText: 'Reference (UPI / bank / cash note)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('paid-save'), onPressed: () => Navigator.pop(dialog, true), child: const Text('Mark paid')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _snack(context, () async {
      await call('markStaffPaid', {'staffUid': row['staffUid'], 'month': month, 'amount': num.tryParse(amount.text.trim()), 'note': note.text.trim()});
      _load();
    }, 'Marked paid');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.call == null && !widget.store.live) return AdminNeedsFirebase(store: widget.store, child: const SizedBox());
    return FutureBuilder<Map<String, dynamic>>(
      future: data,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Staff work could not load: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final d = snap.data!;
        final config = Map<String, dynamic>.from(d['config'] as Map? ?? {});
        final rows = [for (final r in d['rows'] as List? ?? const []) Map<String, dynamic>.from(r as Map)];
        final areas = [for (final a in d['areas'] as List? ?? const []) Map<String, dynamic>.from(a as Map)];
        final slabs = slabsOf(config['slabs']);
        return ListView(padding: const EdgeInsets.all(12), children: [
          Text('Staff work and pay', style: Theme.of(context).textTheme.headlineSmall),
          const Text('Only the updates of vendors linked to a staff member count for them: new items, price changes, new offers (one per item a day).'),
          Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _monthPicker(month, (m) { month = m; _load(); }, key: const ValueKey('staff-work-month')),
            DropdownButton<String>(
              key: const ValueKey('staff-work-area'),
              value: areaId,
              items: [const DropdownMenuItem(value: '', child: Text('All areas')), for (final a in areas) DropdownMenuItem(value: '${a['id']}', child: Text('${a['name']}'))],
              onChanged: (v) { areaId = v ?? ''; _load(); },
            ),
          ]),
          Card(
            child: ListTile(
              key: const ValueKey('staff-pay-config'),
              title: Text('Everyone: ${config['dailyTarget'] ?? defaultDailyTarget} updates a day • month ${config['monthlyTarget'] ?? 'daily x days'}'),
              subtitle: Text(slabs.isEmpty ? 'No pay slabs yet' : 'Slabs: ${slabs.map((s) => '${s.percent}% → ${_money(s.amount)}').join(', ')}'),
              trailing: TextButton(key: const ValueKey('staff-pay-config-edit'), onPressed: () => _editSlabs(config), child: const Text('Change')),
            ),
          ),
          if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No staff yet.', key: ValueKey('staff-work-empty'))),
          for (final r in rows) _staffRow(r),
        ]);
      },
    );
  }

  Widget _staffRow(Map<String, dynamic> r) {
    final m = Map<String, dynamic>.from(r['month'] as Map? ?? {});
    final pay = Map<String, dynamic>.from(m['pay'] as Map? ?? {});
    final targets = Map<String, dynamic>.from(m['targets'] as Map? ?? {});
    final slab = pay['slab'] as Map?;
    final people = [for (final p in r['people'] as List? ?? const []) Map<String, dynamic>.from(p as Map)];
    return Card(
      key: ValueKey('staff-work-${r['staffCode']}'),
      child: ExpansionTile(
        title: Text('${r['staffCode']} • ${r['name']} • ${r['phone']}'),
        subtitle: Text('${r['areaName'] == '' ? 'No area' : r['areaName']} • ${r['linked']} linked • today ${r['today']}/${r['dailyTarget']} '
            '• month ${m['updates'] ?? 0}/${targets['monthly'] ?? 0} (${pay['percent'] ?? 0}%) • ${slab == null ? 'no slab' : '${slab['percent']}% slab'} • pay ${_money((pay['amount'] as num?) ?? 0)}'),
        children: [
          for (final p in people)
            ListTile(dense: true, leading: Icon(p['kind'] == 'provider' ? Icons.home_repair_service_outlined : Icons.storefront_outlined), title: Text('${p['code']} • ${p['name']}'), subtitle: Text('${p['phone']} • ${p['town']}')),
          if (people.isEmpty) const ListTile(dense: true, title: Text('Nobody linked yet')),
          ListTile(dense: true, title: Text('This month: ${m['items'] ?? 0} new items • ${m['prices'] ?? 0} price changes • ${m['offers'] ?? 0} offers • ${m['activeVendors'] ?? 0} active vendors')),
          OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, children: [
            TextButton(key: ValueKey('staff-targets-${r['staffCode']}'), onPressed: () => _editSlabs(Map<String, dynamic>.from(targets)..['dailyTarget'] = targets['daily']..['monthlyTarget'] = targets['monthly'], staff: r), child: Text(r['ownNumbers'] == true ? 'Own targets (change)' : 'Set own targets')),
            FilledButton(key: ValueKey('staff-paid-${r['staffCode']}'), onPressed: () => _paid(r), child: const Text('Mark paid')),
          ]),
        ],
      ),
    );
  }
}

/// The daily target, the monthly target and the slabs (for everyone, or one staff member's own: empty = the same as everyone).
class _TargetsDialog extends StatefulWidget {
  const _TargetsDialog({required this.config, this.staff});
  final Map<String, dynamic> config;
  final Map<String, dynamic>? staff;
  @override
  State<_TargetsDialog> createState() => _TargetsDialogState();
}

class _TargetsDialogState extends State<_TargetsDialog> {
  late final daily = TextEditingController(text: widget.config['dailyTarget'] == null ? '' : '${widget.config['dailyTarget']}');
  late final monthly = TextEditingController(text: widget.config['monthlyTarget'] == null ? '' : '${widget.config['monthlyTarget']}');
  late final slabs = [for (final s in slabsOf(widget.config['slabs'])) (TextEditingController(text: '${s.percent}'), TextEditingController(text: '${s.amount}'))];

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.staff == null ? 'Targets and pay slabs for everyone' : 'Own targets of ${widget.staff!['staffCode']}'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.staff != null) const Text('Leave a box empty to use everyone\'s number.'),
          TextField(key: const ValueKey('target-daily'), controller: daily, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Daily target (updates, 50 when empty)')),
          TextField(key: const ValueKey('target-monthly'), controller: monthly, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monthly target (empty: daily x days of the month)')),
          const SizedBox(height: 8),
          const Align(alignment: Alignment.centerLeft, child: Text('Pay slabs: reach this % of the monthly target → this amount')),
          for (final (i, (p, a)) in slabs.indexed)
            Row(children: [
              Expanded(child: TextField(key: ValueKey('slab-percent-$i'), controller: p, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '%'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(key: ValueKey('slab-amount-$i'), controller: a, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '₹'))),
              IconButton(onPressed: () => setState(() => slabs.removeAt(i)), icon: const Icon(Icons.delete_outline)),
            ]),
          TextButton.icon(key: const ValueKey('slab-add'), onPressed: () => setState(() => slabs.add((TextEditingController(), TextEditingController()))), icon: const Icon(Icons.add), label: const Text('Add slab')),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        key: const ValueKey('targets-save'),
        onPressed: () => Navigator.pop(context, {
          'dailyTarget': int.tryParse(daily.text.trim()),
          'monthlyTarget': int.tryParse(monthly.text.trim()),
          'slabs': [for (final (p, a) in slabs) if (num.tryParse(p.text.trim()) != null) {'percent': num.parse(p.text.trim()), 'amount': num.tryParse(a.text.trim()) ?? 0}],
        }),
        child: const Text('Save'),
      ),
    ],
  );
}

/// This month's ranking: most updates, then most active vendors, then most of the target done; by area.
class AdminStaffRankingPage extends StatefulWidget {
  const AdminStaffRankingPage({super.key, required this.store, this.call});
  final Store store;
  final AdminCall? call;
  @override
  State<AdminStaffRankingPage> createState() => _AdminStaffRankingPageState();
}

class _AdminStaffRankingPageState extends State<AdminStaffRankingPage> {
  String month = _monthOf(DateTime.now());
  String areaId = '';
  Future<Map<String, dynamic>>? data;
  AdminCall get call => widget.call ?? widget.store.call;
  void _load() => setState(() => data = call('staffRanking', {'month': month, 'areaId': areaId}));

  @override
  void initState() {
    super.initState();
    if (widget.call != null || widget.store.live) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.call == null && !widget.store.live) return AdminNeedsFirebase(store: widget.store, child: const SizedBox());
    return FutureBuilder<Map<String, dynamic>>(
      future: data,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('The ranking could not load: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = [for (final r in snap.data!['rows'] as List? ?? const []) Map<String, dynamic>.from(r as Map)];
        final areas = [for (final a in snap.data!['areas'] as List? ?? const []) Map<String, dynamic>.from(a as Map)];
        return ListView(padding: const EdgeInsets.all(12), children: [
          Text('Staff ranking', style: Theme.of(context).textTheme.headlineSmall),
          Wrap(spacing: 12, children: [
            _monthPicker(month, (m) { month = m; _load(); }, key: const ValueKey('ranking-month')),
            DropdownButton<String>(
              key: const ValueKey('ranking-area'),
              value: areaId,
              items: [const DropdownMenuItem(value: '', child: Text('All areas')), for (final a in areas) DropdownMenuItem(value: '${a['id']}', child: Text('${a['name']}'))],
              onChanged: (v) { areaId = v ?? ''; _load(); },
            ),
          ]),
          for (final r in rows)
            ListTile(
              key: ValueKey('ranking-${r['staffCode']}'),
              leading: CircleAvatar(child: Text('${r['rank']}')),
              title: Text('${r['staffCode']} • ${r['name']}'),
              subtitle: Text('${(r['month'] as Map?)?['updates'] ?? 0} updates • ${(r['month'] as Map?)?['activeVendors'] ?? 0} active vendors • '
                  '${((r['month'] as Map?)?['pay'] as Map?)?['percent'] ?? 0}% of target • ${r['areaName']}'),
            ),
          if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No staff in this area.')),
        ]);
      },
    );
  }
}

/// One ID, everything about it, read only: type the ID and press Enter. Graphs by day, week or month; a month's report as Excel or PDF.
class AdminIdReportPage extends StatefulWidget {
  const AdminIdReportPage({super.key, required this.store, this.call, this.download});
  final Store store;
  final AdminCall? call;
  final Future<void> Function(String name, List<int> bytes, String type)? download;
  @override
  State<AdminIdReportPage> createState() => _AdminIdReportPageState();
}

class _AdminIdReportPageState extends State<AdminIdReportPage> {
  final code = TextEditingController();
  Map<String, dynamic>? report;
  String? error;
  bool busy = false;
  String by = 'day';
  String month = _monthOf(DateTime.now());
  AdminCall get call => widget.call ?? widget.store.call;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    if (code.text.trim().isEmpty) return;
    setState(() { busy = true; error = null; });
    try {
      final r = await call('idReport', {'code': code.text.trim()});
      setState(() => report = r);
    } catch (e) {
      setState(() { report = null; error = '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''); });
    }
    setState(() => busy = false);
  }

  List<ReportTable> _tables(Map<String, dynamic> r) {
    final days = [for (final d in r['days'] as List? ?? const []) Map<String, dynamic>.from(d as Map)].where((d) => '${d['day']}'.startsWith(month)).toList();
    final tables = <ReportTable>[
      ReportTable('Days $month', ['Day', 'Updates', 'New items', 'Price changes', 'Offers'], [for (final d in days) [d['day'], d['updates'], d['items'], d['prices'], d['offers']]]),
    ];
    if (r['kind'] == 'staff') {
      tables.add(ReportTable('Linked', ['ID', 'Name', 'Phone', 'Linked on', 'By'], [for (final p in r['linked'] as List? ?? const []) [p['code'], p['name'], p['phone'], p['linkedAt'] ?? '', p['linkedBy']]]));
      tables.add(ReportTable('Payouts', ['Month', 'Updates', 'Target', '%', 'Amount', 'Status', 'Reference'], [for (final p in r['payouts'] as List? ?? const []) [p['month'], p['updates'], p['target'], p['percent'], p['amount'], p['status'], p['reference'] ?? '']]));
    } else {
      tables.add(ReportTable('Items', ['Name', 'Price', 'Price set', 'Shown'], [for (final i in r['items'] as List? ?? const []) [i['name'], i['price'] ?? '', i['priceSetAt'] ?? '', i['active'] == true ? 'yes' : 'no']]));
      tables.add(ReportTable('Price changes', ['When', 'Item', 'From', 'To', 'Kind'], [for (final c in r['priceChanges'] as List? ?? const []) if ('${c['at']}'.startsWith(month)) [c['at'], c['item'], c['from'] ?? '', c['to'] ?? '', c['type']]]));
      tables.add(ReportTable('Offers', ['Kind', 'Title', 'Price', 'Status', 'Ends'], [for (final o in r['offers'] as List? ?? const []) [o['kind'], o['title'], o['price'] ?? '', o['status'], o['endsAt'] ?? '']]));
      tables.add(ReportTable('Ads', ['Title', 'Views', 'Taps', 'Starts', 'Ends'], [for (final a in r['ads'] as List? ?? const []) [a['title'], a['views'], a['taps'], a['startsAt'] ?? '', a['endsAt'] ?? '']]));
    }
    return tables;
  }

  Future<void> _download(String kind) async {
    final r = report!;
    final tables = _tables(r);
    final name = '${r['code']}-$month';
    final save = widget.download ?? (String n, List<int> b, String t) => downloadFile(n, Uint8List.fromList(b), t);
    if (kind == 'xlsx') {
      await save('$name.xlsx', buildXlsx(tables), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    } else {
      await save('$name.pdf', await buildPdf('LOCAMARKET ID report ${r['code']} • $month', _summary(r), tables), 'application/pdf');
    }
  }

  String _summary(Map<String, dynamic> r) => r['kind'] == 'staff'
      ? '${r['code']} • ${r['name']} • ${r['phone']} • ${(r['linked'] as List?)?.length ?? 0} linked • this month ${(r['month'] as Map?)?['updates'] ?? 0} updates, '
          '${((r['month'] as Map?)?['pay'] as Map?)?['percent'] ?? 0}% of target, pay ${_money((((r['month'] as Map?)?['pay'] as Map?)?['amount'] as num?) ?? 0)}'
      : '${r['code']} • ${r['name']} • ${r['phone']} • ${r['town']} • linked to ${(r['linkedStaff'] as Map?)?['staffCode'] ?? 'nobody'} • '
          '★ ${(r['ratings'] as Map?)?['avg'] ?? 0} (${(r['ratings'] as Map?)?['count'] ?? 0}) • ${(r['reports'] as Map?)?['count'] ?? 0} reports • '
          '${(r['activity'] as Map?)?['last30Days'] ?? 0} updates in 30 days';

  @override
  Widget build(BuildContext context) {
    final r = report;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text('ID report', style: Theme.of(context).textTheme.headlineSmall),
      const Text('Type a Vendor ID (VEN-...), a service provider ID (SRV-...) or a Staff ID (STF-...) and press Enter. Read only.'),
      TextField(
        key: const ValueKey('id-report-code'),
        controller: code,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _find(),
        decoration: InputDecoration(
          labelText: 'ID',
          suffixIcon: IconButton(key: const ValueKey('id-report-find'), onPressed: busy ? null : _find, icon: const Icon(Icons.search)),
        ),
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Padding(padding: const EdgeInsets.all(8), child: Text(error!, key: const ValueKey('id-report-error'), style: const TextStyle(color: Colors.red))),
      if (r != null) ...[
        const SizedBox(height: 8),
        Text(_summary(r), key: const ValueKey('id-report-summary'), style: const TextStyle(fontWeight: FontWeight.w600)),
        if (r['kind'] != 'staff') ...[
          Text('Status: ${r['status']} • Area: ${r['area']} • ${r['pincode']}'),
          Text('Active: ${(r['activity'] as Map?)?['activeDays30'] ?? 0} of the last 30 days • last update ${(r['activity'] as Map?)?['lastUpdateDay'] ?? '—'}'),
        ],
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'day', label: Text('Day')), ButtonSegment(value: 'week', label: Text('Week')), ButtonSegment(value: 'month', label: Text('Month'))],
          selected: {by},
          onSelectionChanged: (s) => setState(() => by = s.first),
        ),
        BarChart(values: _series(r)),
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _monthPicker(month, (m) => setState(() => month = m), key: const ValueKey('id-report-month')),
          OutlinedButton.icon(key: const ValueKey('id-report-xlsx'), onPressed: () => _download('xlsx'), icon: const Icon(Icons.table_view), label: const Text('Excel')),
          OutlinedButton.icon(key: const ValueKey('id-report-pdf'), onPressed: () => _download('pdf'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('PDF')),
        ]),
        for (final t in _tables(r))
          ExpansionTile(
            title: Text('${t.title} (${t.rows.length})'),
            children: [for (final row in t.rows.take(100)) ListTile(dense: true, title: Text(row.map((c) => '$c').join('  •  ')))],
          ),
      ],
    ]);
  }

  List<(String, int)> _series(Map<String, dynamic> r) {
    final days = [for (final d in r['days'] as List? ?? const []) ('${(d as Map)['day']}', ((d['updates'] as num?) ?? 0).toInt())]..sort((a, b) => a.$1.compareTo(b.$1));
    if (by == 'month') return [for (final m in r['months'] as List? ?? const []) ('${(m as Map)['month']}', ((m['updates'] as num?) ?? 0).toInt())]..sort((a, b) => a.$1.compareTo(b.$1));
    if (by == 'week') return groupCounts(days, 'week');
    return [for (final d in days.length > 30 ? days.sublist(days.length - 30) : days) (d.$1.substring(5), d.$2)];
  }
}

/// Vendors' and providers' "connect me to local staff" requests, and linking any vendor or provider to a staff member of its area.
class AdminLinkRequestsPage extends StatefulWidget {
  const AdminLinkRequestsPage({super.key, required this.store, this.call});
  final Store store;
  final AdminCall? call;
  @override
  State<AdminLinkRequestsPage> createState() => _AdminLinkRequestsPageState();
}

class _AdminLinkRequestsPageState extends State<AdminLinkRequestsPage> {
  final code = TextEditingController();
  AdminCall get call => widget.call ?? widget.store.call;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  /// Shows the staff of the person's area and links the chosen one.
  Future<void> _choose(Map<String, dynamic> who) async {
    final messenger = ScaffoldMessenger.of(context);
    List<Map<String, dynamic>> staff;
    try {
      staff = [for (final s in (await call('staffForArea', who))['staff'] as List? ?? const []) Map<String, dynamic>.from(s as Map)];
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Staff of this area'),
        content: SizedBox(
          width: 400,
          child: staff.isEmpty
              ? const Text('No active staff member has this place in their area.', key: ValueKey('link-no-staff'))
              : ListView(shrinkWrap: true, children: [
                  for (final s in staff)
                    ListTile(key: ValueKey('link-staff-${s['staffCode']}'), title: Text('${s['staffCode']} • ${s['name']}'), subtitle: Text('${s['phone']} • ${s['areaName']}'), onTap: () => Navigator.pop(dialog, s)),
                ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel'))],
      ),
    );
    if (chosen == null || !mounted) return;
    await _snack(context, () => call('adminLinkStaff', {...who, 'staffUid': chosen['staffUid']}), 'Linked to ${chosen['staffCode']}');
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
    Text('Staff links', style: Theme.of(context).textTheme.headlineSmall),
    const Text('Link any vendor or service provider to a staff member of the same area, at any time. Staff of another area are never offered.'),
    Row(children: [
      Expanded(child: TextField(key: const ValueKey('link-code'), controller: code, decoration: const InputDecoration(labelText: 'Vendor ID or service provider ID'))),
      FilledButton(key: const ValueKey('link-choose'), onPressed: () => _choose({'code': code.text.trim()}), child: const Text('Choose staff')),
    ]),
    const SizedBox(height: 16),
    Text('Requests from the Support Team chat', style: Theme.of(context).textTheme.titleMedium),
    if (!widget.store.live && widget.call == null)
      const Text('Requests show here when Firebase is connected.')
    else
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: widget.store.firestore.collection('staffLinkRequests').where('status', isEqualTo: 'open').limit(100).snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          if (docs.isEmpty) return const Text('No open requests.', key: ValueKey('link-requests-empty'));
          return Column(children: [
            for (final d in docs)
              ListTile(
                key: ValueKey('link-request-${d.id}'),
                leading: Icon(d.data()['kind'] == 'provider' ? Icons.home_repair_service_outlined : Icons.storefront_outlined),
                title: Text('${d.data()['code']} • ${d.data()['name']}'),
                subtitle: Text('${d.data()['phone'] ?? ''} • ${d.data()['town'] ?? ''}'),
                trailing: TextButton(onPressed: () => _choose({'kind': d.data()['kind'], 'accountUid': d.data()['accountUid']}), child: const Text('Choose staff')),
              ),
          ]);
        },
      ),
  ]);
}
