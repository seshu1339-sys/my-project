import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'moderation_dialogs.dart';
import 'shop_map.dart';
import 'text_prompt_dialog.dart';

/// Admin > Vendors > Service providers: the service-provider applications (a separate kind of account from vendors). The admin sees
/// the photo, the service, the charge per hour, the address and the location on a map, and approves (the listing goes live in the
/// services collection) or rejects with a reason.
class ProviderModerationPage extends StatelessWidget {
  const ProviderModerationPage({super.key, required this.store});
  final Store store;

  static const _order = {'pending': 0, 'rejected': 2, 'approved': 1};

  Future<void> _reject(BuildContext context, String id) async {
    final reason = await askText(context, title: 'Reject this application?', label: 'Reason (the provider sees it)', confirm: 'Reject', maxLines: 2, fieldKey: const ValueKey('provider-reject-reason'));
    if (reason == null || reason.isEmpty || !context.mounted) return;
    await runModerationAction(context, () => store.call('approveProvider', {'providerId': id, 'approved': false, 'reason': reason}), onSuccess: (_) => 'Rejected');
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('providerApplications').limit(300).snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('Could not load the service-provider applications.'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final docs = [...snapshot.data!.docs]..sort((a, b) => (_order[a.data()['status']] ?? 3).compareTo(_order[b.data()['status']] ?? 3));
      final pending = docs.where((d) => d.data()['status'] == 'pending').length;
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Service providers', style: Theme.of(context).textTheme.headlineSmall),
          Text('$pending waiting for approval • ${docs.length} in all. A service provider is a separate account from a vendor.'),
          const SizedBox(height: 12),
          if (docs.isEmpty) const Text('No service-provider applications yet.'),
          for (final doc in docs) _application(context, doc),
        ],
      );
    },
  );

  Widget _application(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final status = '${data['status'] ?? ''}';
    return Card(
      child: ExpansionTile(
        key: ValueKey('provider-application-${doc.id}'),
        initiallyExpanded: status == 'pending',
        title: Text('${data['name'] ?? doc.id} • ${data['serviceName'] ?? ''}'),
        subtitle: Text('₹${data['hourlyRate'] ?? ''} per hour • ${switch (status) { 'pending' => 'Pending approval', 'approved' => 'Approved, live', 'rejected' => 'Rejected', _ => status }}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ApplicationPhoto(label: 'Photo', path: data['photoPath']?.toString(), height: 160, width: 200),
          const SizedBox(height: 8),
          Text('Mobile: ${data['phone'] ?? ''}'),
          if ('${data['email'] ?? ''}'.isNotEmpty) Text('Email: ${data['email']}'),
          Text('House address: ${data['address'] ?? ''} ${data['pincode'] ?? ''}'),
          if ('${data['gpsAddress'] ?? ''}'.isNotEmpty) Text('Address from GPS: ${data['gpsAddress']}'),
          if (status == 'rejected' && '${data['decisionReason'] ?? ''}'.isNotEmpty) Text('Reason: ${data['decisionReason']}'),
          if (data['latitude'] is num && data['longitude'] is num)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ShopMap(shops: [Entry(doc.id, {'name': data['name'] ?? '', 'latitude': data['latitude'], 'longitude': data['longitude']})], height: 180),
              ),
            ),
          if (status == 'pending')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OverflowBar(
                spacing: 8,
                children: [
                  FilledButton(
                    key: ValueKey('provider-approve-${doc.id}'),
                    onPressed: () => runModerationAction(context, () => store.call('approveProvider', {'providerId': doc.id, 'approved': true}), onSuccess: (_) => 'Approved: the service is live'),
                    child: const Text('Approve'),
                  ),
                  OutlinedButton(key: ValueKey('provider-reject-${doc.id}'), onPressed: () => _reject(context, doc.id), child: const Text('Reject')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
