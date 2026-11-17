import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import 'staff_link_model.dart';

/// Staff app: "Vendors I registered", read only. Each linked vendor or provider with their ID, when they were linked, and whether they
/// keep their items up to date (how many items, how many updated today, the last update). No edit button anywhere: the vendor manages
/// their own shop, items and prices.
class StaffLinkedList extends StatelessWidget {
  const StaffLinkedList({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('staffLinks').where('staffUid', isEqualTo: uid).snapshots(),
    builder: (context, snapshot) {
      final links = [for (final doc in snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) StaffLink.fromData(doc.id, doc.data())]
        ..sort((a, b) => (b.linkedAt ?? DateTime(0)).compareTo(a.linkedAt ?? DateTime(0)));
      return StaffLinkedListView(
        links: links,
        failed: snapshot.hasError,
        updates: (link) => link.provider
            ? store.firestore.collection('services').where('ownerId', isEqualTo: link.accountUid).snapshots().map((s) => [for (final d in s.docs) d.data()])
            : store.firestore.collection('products').where('ownerId', isEqualTo: link.accountUid).snapshots().map((s) => [for (final d in s.docs) d.data()]),
      );
    },
  );
}

class StaffLinkedListView extends StatelessWidget {
  const StaffLinkedListView({super.key, required this.links, required this.updates, this.failed = false, this.now});
  final List<StaffLink> links;
  // The live items of one linked person (their products, or their service listing).
  final Stream<List<Map<String, dynamic>>> Function(StaffLink link) updates;
  final bool failed;
  final DateTime? now;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Vendors I registered', style: Theme.of(context).textTheme.titleLarge),
        Text('${links.length} linked • read only: they update their own items and prices', key: const ValueKey('staff-links-count')),
        if (failed) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Your list could not load.')),
        if (!failed && links.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nobody linked yet. When a vendor registers, tap Add and enter their ID within 30 minutes.')),
        for (final link in links)
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: updates(link),
            builder: (context, items) {
              final u = linkedUpdates(items.data ?? const [], now ?? DateTime.now());
              final last = u.lastUpdate == null ? 'No update yet' : 'Last update ${linkDate(u.lastUpdate)}';
              final what = link.provider ? 'Service provider' : 'Vendor';
              return ListTile(
                key: ValueKey('staff-link-${link.id}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(link.provider ? Icons.home_repair_service_outlined : Icons.storefront_outlined),
                title: Text(link.name.isEmpty ? link.code : link.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  '$what • ${link.code}${link.linkedAt == null ? '' : ' • linked ${linkDate(link.linkedAt)}'}',
                  link.provider ? last : '${u.items} item${u.items == 1 ? '' : 's'} • ${u.updatedToday} updated today • $last',
                ].join('\n')),
                isThreeLine: true,
                trailing: u.updatedToday > 0 ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, semanticLabel: 'Updated today') : null,
              );
            },
          ),
      ]),
    ),
  );
}
