import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/usage_report.dart';

/// What each own-number means to its owner (a vendor, a service provider, a staff member).
const myNumberLabels = {
  'shop_call': 'Calls to your shop',
  'shop_whatsapp': 'WhatsApp messages',
  'shop_directions': 'People who took directions',
  'worker_call': 'Calls to you',
  'worker_whatsapp': 'WhatsApp to you',
  'item_added': 'Items you added',
  'price_changed': 'Price changes',
  'staff_added': 'Vendors and providers you added',
};

/// The own numbers of the last [days] days, from usageOwnerDaily records (functions/usage.js): event -> count.
Map<String, int> myNumbers(Iterable<Entry> records, {required DateTime now, int days = 7}) {
  final from = usageDay(now.subtract(Duration(days: days - 1)));
  final out = <String, int>{};
  for (final r in records) {
    if (r.text('day').compareTo(from) < 0) continue;
    ((r.data['counts'] as Map?) ?? const {}).forEach((event, n) {
      if (n is num) out['$event'] = (out['$event'] ?? 0) + n.round();
    });
  }
  return out;
}

/// "Your numbers": how many called, messaged and took directions to this vendor's shop (or this provider, or the vendors this staff
/// member added) in the last 7 and 30 days. [events] are the ones this account shows.
class MyNumbersView extends StatelessWidget {
  const MyNumbersView({super.key, required this.records, required this.events, required this.now});
  final List<Entry> records;
  final List<String> events;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final week = myNumbers(records, now: now, days: 7), month = myNumbers(records, now: now, days: 30);
    return Card(
      key: const ValueKey('my-numbers'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your numbers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Text('Counted from the customer app and website.'),
            const SizedBox(height: 8),
            Table(
              columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
              children: [
                const TableRow(children: [SizedBox(), Text('7 days', style: TextStyle(fontWeight: FontWeight.w600)), Text('30 days', style: TextStyle(fontWeight: FontWeight.w600))]),
                for (final e in events)
                  TableRow(children: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(myNumberLabels[e] ?? usageEventLabels[e] ?? e)),
                    Text('${week[e] ?? 0}', key: ValueKey('my-number-$e-7')),
                    Text('${month[e] ?? 0}', key: ValueKey('my-number-$e-30')),
                  ]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// [MyNumbersView] read live for the signed-in owner [ownerId].
class MyNumbersCard extends StatefulWidget {
  const MyNumbersCard({super.key, required this.store, required this.ownerId, required this.events});
  final Store store;
  final String ownerId;
  final List<String> events;

  @override
  State<MyNumbersCard> createState() => _MyNumbersCardState();
}

class _MyNumbersCardState extends State<MyNumbersCard> {
  late final _mine = widget.store.firestore.collection('usageOwnerDaily').where('ownerId', isEqualTo: widget.ownerId);
  // The newest 60 days (the index usageOwnerDaily ownerId + day, firestore.indexes.json). Until that index is deployed the query
  // fails, and the records are read without an order instead (right for an owner's first 60 days).
  late final _newest = _mine.orderBy('day', descending: true).limit(60).snapshots();
  late final _anyOrder = _mine.limit(60).snapshots();

  Widget _view(Stream<QuerySnapshot<Map<String, dynamic>>> stream, Widget Function() onError) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) return onError();
      return MyNumbersView(records: [for (final d in snapshot.data?.docs ?? const []) Entry(d.id, d.data())], events: widget.events, now: DateTime.now());
    },
  );

  @override
  Widget build(BuildContext context) => _view(_newest, () => _view(_anyOrder, () => const SizedBox.shrink()));
}
