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
      builder: (context, status) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('planServiceGates').doc('main').snapshots(),
        builder: (context, gates) {
          final data = status.data?.data();
          return VendorPlansView(
            plans: [for (final doc in plans.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) SubscriptionPlan.fromData(doc.id, doc.data())],
            status: data?['endsAt'] is Timestamp ? VendorPlanStatus.fromData(uid, data!) : null,
            freeItems: freeItemLimit(gates.data?.data()),
            onChoose: onPay == null ? null : (plan) => _choose(context, plan),
          );
        },
      ),
    ),
  );

  Future<void> _choose(BuildContext context, SubscriptionPlan plan) async {
    final result = await store.call('startPlanPurchase', {'planId': plan.id});
    if (context.mounted) await onPay!(context, result['requestId'] as String);
  }
}

/// The card itself: the running plan, then Free and each plan side by side (what each one gives, in plain words). With no payment
/// method open the plans show without a button; the admin can still start a plan by hand.
class VendorPlansView extends StatefulWidget {
  const VendorPlansView({super.key, required this.plans, required this.status, required this.onChoose, this.now, this.freeItems = defaultFreeItemLimit});
  final List<SubscriptionPlan> plans;
  // Items a vendor may have on the free plan (Admin > Plans).
  final int freeItems;
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
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, c) {
            // Two side by side when there is room (a phone held upright shows them one under the other).
            final width = c.maxWidth >= 520 ? (c.maxWidth - 12) / 2 : c.maxWidth;
            return Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(
                width: width,
                child: _PlanCompareCard(
                  key: const ValueKey('plan-compare-free'),
                  title: 'Free',
                  price: 'Free for life',
                  current: !active,
                  points: const ['1 shop photo + $freeExtraPhotos extra photos', 'Change your prices any day', 'Your shop shows in search and on the map'],
                ),
              ),
              for (final plan in plans)
                SizedBox(
                  width: width,
                  child: _PlanCompareCard(
                    key: ValueKey('plan-${plan.id}'),
                    title: plan.name,
                    badge: planTiers[plan.tier],
                    price: '${planPrice(plan.price)} for ${planDuration(plan.durationMonths)}',
                    current: active && status.planName == plan.name,
                    points: [
                      '1 shop photo + ${plan.extraPhotos} extra photos',
                      'Customers within ${kmText(plan.radiusKm)} see your ad and offer',
                      if (plan.offerBoxes > 0) "${plan.offerBoxes} ${plan.offerBoxes == 1 ? 'item' : 'items'} at a time in Today's Offers",
                      ...paidPlanServices,
                    ],
                    action: widget.onChoose == null
                        ? null
                        : FilledButton(key: ValueKey('plan-choose-${plan.id}'), onPressed: busy ? null : () => _choose(plan), child: Text(active ? 'Renew' : 'Choose')),
                  ),
                ),
            ]);
          }),
          if (plans.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('No plans are available right now.', key: ValueKey('plans-empty'))),
          if (plans.isNotEmpty && widget.onChoose == null)
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('Payments will open soon. To start a plan now, contact the LOCAMARKET office.', key: ValueKey('plans-payment-soon'))),
        ]),
      ),
    );
  }
}

/// One column of the comparison: the name, the price, what it gives, and the button (if payments are open).
class _PlanCompareCard extends StatelessWidget {
  const _PlanCompareCard({super.key, required this.title, required this.price, required this.points, required this.current, this.action, this.badge});
  final String title, price;
  // The plan's kind (Silver / Gold / Premium).
  final String? badge;
  final List<String> points;
  final bool current;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: current ? scheme.primary : scheme.outlineVariant, width: current ? 2 : 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          if (current) Text('Your plan', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600, fontSize: 12)),
        ]),
        if (badge != null && badge != title) Text(badge!, style: TextStyle(color: scheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
        Text(price),
        const SizedBox(height: 6),
        for (final point in points)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.check, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(child: Text(point)),
            ]),
          ),
        if (action != null) Padding(padding: const EdgeInsets.only(top: 8), child: action),
      ]),
    );
  }
}
