import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/staff_pay.dart';
import 'bar_chart.dart';

/// Staff app > My work: only this staff member's own work, live (functions/modules/staff-work writes staffWork with every update of
/// a linked vendor): how many are linked, today's updates against the daily target, the month's total, the graph (day / week / month),
/// the slab reached and this month's amount by the admin's slabs. Read only; no other staff member's numbers or ranking.
class StaffMyWork extends StatelessWidget {
  const StaffMyWork({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;

  @override
  Widget build(BuildContext context) {
    if (!store.live) return const SizedBox.shrink();
    final db = store.firestore;
    final now = DateTime.now();
    final from = istDay(now.subtract(const Duration(days: 92)));
    final work = db.collection('staffWork').doc(uid);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: work.collection('days').where(FieldPath.documentId, isGreaterThanOrEqualTo: from).snapshots(),
      builder: (context, days) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: work.collection('months').snapshots(),
        builder: (context, months) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: db.collection('staffPayConfig').doc('main').snapshots(),
          builder: (context, config) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: db.collection('staffPayTargets').doc(uid).snapshots(),
            builder: (context, own) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db.collection('staffLinks').where('staffUid', isEqualTo: uid).snapshots(),
              builder: (context, links) => StaffMyWorkView(
                now: now,
                days: {for (final d in days.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) d.id: (d.data()['updates'] as num?)?.toInt() ?? 0},
                months: {for (final d in months.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) d.id: (d.data()['updates'] as num?)?.toInt() ?? 0},
                config: config.data?.data(),
                own: own.data?.data(),
                linked: links.data?.docs.length ?? 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card itself, from plain numbers ([days]: "YYYY-MM-DD" -> updates, [months]: "YYYY-MM" -> updates).
class StaffMyWorkView extends StatefulWidget {
  const StaffMyWorkView({super.key, required this.now, required this.days, required this.months, this.config, this.own, this.linked = 0});
  final DateTime now;
  final Map<String, int> days, months;
  final Map<String, dynamic>? config, own;
  final int linked;
  @override
  State<StaffMyWorkView> createState() => _StaffMyWorkViewState();
}

class _StaffMyWorkViewState extends State<StaffMyWorkView> {
  String by = 'day';

  @override
  Widget build(BuildContext context) {
    final month = istMonth(widget.now), today = istDay(widget.now);
    final targets = targetsFor(widget.config, widget.own, month);
    final monthUpdates = widget.months[month] ?? 0;
    final todayUpdates = widget.days[today] ?? 0;
    final pay = payFor(monthUpdates, targets);
    final dayList = [
      for (var i = 29; i >= 0; i--)
        (istDay(widget.now.subtract(Duration(days: i))).substring(5), widget.days[istDay(widget.now.subtract(Duration(days: i)))] ?? 0),
    ];
    final full = [for (var i = 91; i >= 0; i--) (istDay(widget.now.subtract(Duration(days: i))), widget.days[istDay(widget.now.subtract(Duration(days: i)))] ?? 0)];
    final shown = by == 'day'
        ? dayList
        : by == 'week'
            ? groupCounts(full, 'week')
            : ([for (final e in widget.months.entries) (e.key, e.value)]..sort((a, b) => a.$1.compareTo(b.$1)));
    final text = Theme.of(context).textTheme;
    return Card(
      key: const ValueKey('staff-my-work'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('My work', style: text.titleLarge),
          const Text('Only the updates of the vendors linked to you count: new items, price changes, new offers (one per item a day).'),
          const SizedBox(height: 8),
          Wrap(spacing: 16, runSpacing: 8, children: [
            _tile(context, 'Linked', '${widget.linked}', 'my-work-linked'),
            _tile(context, 'Today', '$todayUpdates / ${targets.daily}', 'my-work-today'),
            _tile(context, 'This month', '$monthUpdates / ${targets.monthly}', 'my-work-month'),
            _tile(context, 'Target done', '${pay.percent}%', 'my-work-percent'),
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: targets.daily == 0 ? 0 : (todayUpdates / targets.daily).clamp(0, 1).toDouble(), minHeight: 8),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'day', label: Text('Day')), ButtonSegment(value: 'week', label: Text('Week')), ButtonSegment(value: 'month', label: Text('Month'))],
            selected: {by},
            onSelectionChanged: (s) => setState(() => by = s.first),
          ),
          const SizedBox(height: 8),
          BarChart(values: shown, target: by == 'day' ? targets.daily : null),
          const SizedBox(height: 12),
          if (targets.slabs.isEmpty)
            const Text('The admin has not set pay slabs yet.', key: ValueKey('my-work-no-slabs'))
          else ...[
            Text(
              pay.slab == null ? 'No slab reached yet this month.' : 'Slab reached: ${pay.slab!.percent}% → ₹${pay.amount}',
              key: const ValueKey('my-work-slab'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (pay.next != null) Text('Next: ${pay.next!.percent}% → ₹${pay.next!.amount} (${(targets.monthly * pay.next!.percent / 100).ceil() - monthUpdates} more updates)'),
            Text('This month by the slabs: ₹${pay.amount}', key: const ValueKey('my-work-amount')),
            const Text('The office pays by hand; this only shows the amount.'),
          ],
        ]),
      ),
    );
  }

  Widget _tile(BuildContext context, String label, String value, String key) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, key: ValueKey(key), style: Theme.of(context).textTheme.headlineSmall),
      Text(label),
    ],
  );
}
