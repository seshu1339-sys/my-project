import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import 'admin_frame.dart';
import 'shop_ratings.dart' show stars;

/// Admin > Ratings: every rating, newest first; the admin removes a fake one (it is hidden and the average is worked out again).
class AdminRatingsPage extends StatelessWidget {
  const AdminRatingsPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => AdminNeedsFirebase(
    store: store,
    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('shopRatings').orderBy('updatedAt', descending: true).limit(200).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return const Center(child: Text('Ratings could not load.'));
        final docs = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return ListView(padding: const EdgeInsets.all(12), children: [
          Text('Ratings', style: Theme.of(context).textTheme.headlineSmall),
          const Text('Customers rate shops and service providers (1 to 5 stars, a name, a comment). Remove a fake one: it is hidden and the average changes.'),
          if (docs.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No ratings yet.', key: ValueKey('ratings-empty'))),
          for (final d in docs)
            ListTile(
              key: ValueKey('admin-rating-${d.id}'),
              title: Text('${stars((d.data()['stars'] as num?)?.round() ?? 0)}  ${d.data()['name'] ?? ''} • ${d.data()['kind'] ?? ''} ${d.data()['targetId'] ?? ''}'),
              subtitle: Text('${d.data()['comment'] ?? ''}${d.data()['hidden'] == true ? '  (removed)' : ''}'),
              trailing: d.data()['hidden'] == true
                  ? null
                  : TextButton(
                      key: ValueKey('admin-rating-remove-${d.id}'),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await store.call('removeShopRating', {'ratingId': d.id});
                          messenger.showSnackBar(const SnackBar(content: Text('Rating removed')));
                        } catch (e) {
                          messenger.showSnackBar(SnackBar(content: Text('$e')));
                        }
                      },
                      child: const Text('Remove'),
                    ),
            ),
        ]);
      },
    ),
  );
}
