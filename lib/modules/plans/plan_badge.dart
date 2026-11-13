import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import 'plan_model.dart';

/// The line at the top of the vendor app (owner, 13 Nov 2026): "Gold Plan · until 12/03/2027" while a plan runs, otherwise "Free Plan" with
/// an Upgrade button. A running plan also gets a button to move to a higher one.
class VendorPlanBadge extends StatelessWidget {
  const VendorPlanBadge({super.key, required this.store, required this.uid, required this.onUpgrade, this.now});
  final Store store;
  final String uid;
  // Opens the plans page.
  final VoidCallback onUpgrade;
  final DateTime? now;

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('vendorPlanStatus').doc(uid).snapshots(),
    builder: (context, snapshot) {
      final data = snapshot.data?.data();
      final status = data?['endsAt'] is Timestamp ? VendorPlanStatus.fromData(uid, data!) : null;
      return VendorPlanBadgeView(status: status, onUpgrade: onUpgrade, now: now);
    },
  );
}

/// The badge itself, for the status read above.
class VendorPlanBadgeView extends StatelessWidget {
  const VendorPlanBadgeView({super.key, required this.status, required this.onUpgrade, this.now});
  final VendorPlanStatus? status;
  final VoidCallback onUpgrade;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final current = status;
    final active = current != null && current.activeAt(now ?? DateTime.now());
    final scheme = Theme.of(context).colorScheme;
    final kind = active ? (planTiers[current.tier] ?? current.planName) : '';
    return Card(
      key: const ValueKey('vendor-plan-badge'),
      color: active ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Icon(active ? Icons.workspace_premium : Icons.person_outline, color: active ? scheme.primary : null),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              active ? '$kind Plan · until ${planDate(current.endsAt)}' : 'Free Plan',
              key: const ValueKey('vendor-plan-badge-text'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          FilledButton.tonal(key: const ValueKey('vendor-plan-upgrade'), onPressed: onUpgrade, child: Text(active ? 'Change plan' : 'Upgrade')),
        ]),
      ),
    );
  }
}
