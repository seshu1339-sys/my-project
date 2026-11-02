import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import 'plan_model.dart';

/// Takes the vendor to paying for a request made by startPlanPurchase. Null until a payment method is open.
typedef PlanPay = Future<void> Function(BuildContext context, String requestId);

/// The Plans card of the vendor app. It only needs the store and the vendor id.
class VendorPlansSection extends StatelessWidget {
  const VendorPlansSection({super.key, required this.store, required this.uid, this.onPay});
  final Store store;
  final String uid;
  final PlanPay? onPay;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('vendorPlans').where('active', isEqualTo: true).snapshots(),
    builder: (context, plans) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('vendorPlanStatus').doc(uid).snapshots(),
      builder: (context, status) {
        final data = status.data?.data();
        final endsAt = data?['endsAt'];
        return VendorPlansView(
          plans: [for (final doc in plans.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) SubscriptionPlan.fromData(doc.id, doc.data())],
          status: endsAt is Timestamp ? VendorPlanStatus(planName: data?['planName']?.toString() ?? '', endsAt: endsAt.toDate()) : null,
          onChoose: onPay == null ? null : (plan) => _choose(context, plan),
        );
      },
    ),
  );

  Future<void> _choose(BuildContext context, SubscriptionPlan plan) async {
    final result = await store.call('startPlanPurchase', {'planId': plan.id});
    if (context.mounted) await onPay!(context, result['requestId'] as String);
  }
}

/// The card itself: the running plan, then the plans. With no payment method open the plans show without a button.
class VendorPlansView extends StatefulWidget {
  const VendorPlansView({super.key, required this.plans, required this.status, required this.onChoose, this.now});
  final List<SubscriptionPlan> plans;
  final VendorPlanStatus? status;
  final Future<void> Function(SubscriptionPlan plan)? onChoose;
  final DateTime? now;

  @override
  State<VendorPlansView> createState() => _VendorPlansViewState();
}

class _VendorPlansViewState extends State<VendorPlansView> {
  bool busy = false;

  Future<void> _choose(SubscriptionPlan plan) async {
    setState(() => busy = true);
    try {
      await widget.onChoose!(plan);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final active = status != null && status.activeAt(widget.now ?? DateTime.now());
    final plans = sortedPlans(widget.plans);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Plans', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('A plan unlocks special services such as ads. Your shop stays live and visible with or without a plan.'),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                active ? '${status.planName} is active until ${planDate(status.endsAt)}' : 'Your plan ended on ${planDate(status.endsAt)}. Special services are off; your shop stays visible.',
                key: const ValueKey('plan-status'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          if (plans.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('No plans are available right now.', key: ValueKey('plans-empty'))),
          for (final plan in plans)
            ListTile(
              key: ValueKey('plan-${plan.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(plan.name),
              subtitle: Text('${planPrice(plan.price)} for ${planDuration(plan.durationMonths)}'),
              trailing: widget.onChoose == null
                  ? null
                  : FilledButton(key: ValueKey('plan-choose-${plan.id}'), onPressed: busy ? null : () => _choose(plan), child: Text(active ? 'Renew' : 'Choose')),
            ),
          if (plans.isNotEmpty && widget.onChoose == null) const Text('Payments will open soon.', key: ValueKey('plans-payment-soon')),
        ]),
      ),
    );
  }
}
