import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import '../services/location.dart';
import 'shared.dart';

/// The customer's own order history, including the one-time purchase-code
/// flow for a fulfilled order. `run` is the parent page's shared busy-lock
/// helper, passed in unchanged so every button on the page still disables
/// together while any one action is in flight, exactly as before the split.
class AccountOrdersSection extends StatelessWidget {
  const AccountOrdersSection({
    super.key,
    required this.store,
    required this.run,
  });
  final Store store;
  final Future<void> Function(Future<void> Function() action) run;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('orders')
        .where('userId', isEqualTo: store.user!.uid)
        .snapshots(),
    builder: (context, snap) {
      if (snap.hasError) {
        return const Text('Orders could not load. Please try again.');
      }
      if (!snap.hasData) {
        return const LinearProgressIndicator();
      }
      if (snap.data!.docs.isEmpty) {
        return const Text('Your first local find is waiting for you.');
      }
      return Column(
        children: snap.data!.docs
            .map(
              (d) => ListTile(
                title: Text('Order ${d.id}'),
                subtitle: Text(d.data()['status'].toString()),
                trailing: d.data()['status'] == 'fulfilled'
                    ? TextButton(
                        onPressed: () => run(() async {
                          final pageContext = context;
                          final position = await currentPosition();
                          final code = await store.issuePurchaseCode(
                            d.id,
                            latitude: position.latitude,
                            longitude: position.longitude,
                          );
                          if (!pageContext.mounted) return;
                          await showDialog<void>(
                            context: pageContext,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Your one-time purchase code'),
                              content: Text(code),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        }),
                        child: const Text('Get code'),
                      )
                    : Text(money(d.data()['total'] as num)),
              ),
            )
            .toList(),
      );
    },
  );
}
