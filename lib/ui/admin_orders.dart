import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import 'shared.dart';

/// Live order queue: streams `orders` and lets the admin change each one's
/// status directly (a plain Firestore write, gated by firestore.rules).
class AdminOrders extends StatelessWidget {
  const AdminOrders({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Order requests')),
    body: !store.live
        ? const Center(
            child: Text(
              'Live customer orders will appear here when Firebase is connected.',
            ),
          )
        : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('orders')
                .orderBy('createdAt', descending: true)
                .limit(100)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    'Orders could not load. Check administrator access.',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.docs.isEmpty) {
                return const Center(
                  child: Text('New order requests will appear here.'),
                );
              }
              return ListView(
                children: snapshot.data!.docs.map((doc) {
                  final order = doc.data();
                  return Card(
                    margin: const EdgeInsets.all(16),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order ${doc.id}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text('${order['address']} • ${order['pincode']}'),
                          for (final line in order['lines'] as List)
                            Text('${line['quantity']} × ${line['name']}'),
                          Text('Total ${money(order['total'] as num)}'),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: order['status'] as String,
                            decoration: const InputDecoration(
                              labelText: 'Order status',
                            ),
                            items:
                                [
                                      'submitted',
                                      'confirmed',
                                      'fulfilled',
                                      'cancelled',
                                    ]
                                    .map(
                                      (s) => DropdownMenuItem(
                                        value: s,
                                        child: Text(s),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (status) async {
                              if (status == null) {
                                return;
                              }
                              try {
                                await doc.reference.update({'status': status});
                              } catch (e) {
                                if (context.mounted) {
                                  message(context, e);
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
  );
}
