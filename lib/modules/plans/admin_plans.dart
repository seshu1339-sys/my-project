import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../home_module.dart';
import 'plan_model.dart';

Widget _build(Store store) => AdminPlansPage(store: store);

/// The Plans tab of the admin panel (listed in module_admin.dart).
const plansAdminSection = ModuleAdminSection(id: 'plans', title: 'Plans', icon: Icons.workspace_premium_outlined, hint: 'Vendor plans and prices', build: _build);

/// Admin > Plans: reads the plans and the service switches, and saves through the module's own callables.
class AdminPlansPage extends StatelessWidget {
  const AdminPlansPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('vendorPlans').snapshots(),
    builder: (context, plans) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('planServiceGates').doc('main').snapshots(),
      builder: (context, gates) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('vendorPlanStatus').snapshots(),
        builder: (context, statuses) {
          if (plans.hasError) return const Center(child: Text('Plans could not load.'));
          if (!plans.hasData) return const Center(child: CircularProgressIndicator());
          return AdminPlansView(
            plans: [for (final doc in plans.data!.docs) SubscriptionPlan.fromData(doc.id, doc.data())],
            gates: gates.data?.data() ?? const {},
            statuses: [for (final doc in statuses.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) VendorPlanStatus.fromData(doc.id, doc.data())],
            onSave: (fields) => store.call('savePlan', fields),
            onGate: (service, on) => store.call('savePlanGates', {service: on}),
            onFreeLimit: (n) => store.call('savePlanGates', {'freeItemLimit': n}),
            onFreePhotos: (n) => store.call('savePlanGates', {'freeExtraPhotos': n}),
            onActivate: (vendorCode, planId) => store.call('adminActivatePlan', {'vendorCode': vendorCode, 'planId': planId}),
            onStop: (uid) => store.call('adminStopPlan', {'uid': uid}),
          );
        },
      ),
    ),
  );
}

class AdminPlansView extends StatelessWidget {
  const AdminPlansView({
    super.key,
    required this.plans,
    required this.gates,
    required this.onSave,
    required this.onGate,
    this.statuses = const [],
    this.onFreeLimit,
    this.onFreePhotos,
    this.onActivate,
    this.onStop,
    this.now,
  });
  final List<SubscriptionPlan> plans;
  final Map<String, dynamic> gates;
  final Future<void> Function(Map<String, dynamic> fields) onSave;
  final Future<void> Function(String service, bool on) onGate;
  // Every vendor who has or had a plan (vendorPlanStatus), with its end date.
  final List<VendorPlanStatus> statuses;
  final Future<void> Function(int items)? onFreeLimit;
  final Future<void> Function(int photos)? onFreePhotos;
  // Starts a plan by hand (no payment in the app), by Vendor ID; stops a running one.
  final Future<void> Function(String vendorCode, String planId)? onActivate;
  final Future<void> Function(String uid)? onStop;
  final DateTime? now;

  Future<void> _run(BuildContext context, Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _edit(BuildContext context, [SubscriptionPlan? plan]) async {
    final fields = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => PlanEditorDialog(plan: plan));
    if (fields != null && context.mounted) await _run(context, () => onSave(fields), 'Plan saved');
  }

  Future<void> _freeLimit(BuildContext context) async {
    final n = await showDialog<int>(context: context, builder: (_) => _NumberDialog(title: 'Items on the free plan', initial: freeItemLimit(gates), min: 0));
    if (n != null && context.mounted) await _run(context, () => onFreeLimit!(n), 'Saved');
  }

  Future<void> _freePhotos(BuildContext context) async {
    final n = await showDialog<int>(context: context, builder: (_) => _NumberDialog(title: 'Extra photos on the free plan', initial: freeExtraPhotosOf(gates), min: 0));
    if (n != null && context.mounted) await _run(context, () => onFreePhotos!(n), 'Saved');
  }

  Future<void> _activate(BuildContext context, {String vendorCode = ''}) async {
    final choice = await showDialog<(String, String)>(context: context, builder: (_) => ActivatePlanDialog(plans: sortedPlans(plans), vendorCode: vendorCode));
    if (choice != null && context.mounted) await _run(context, () => onActivate!(choice.$1, choice.$2), 'Plan started');
  }

  Future<void> _stop(BuildContext context, VendorPlanStatus status) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Stop this plan?'),
        content: Text('${_who(status)}: ${status.planName} ends now. The shop stays live; only the plan services stop. The vendor is told.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('plan-stop-confirm'), onPressed: () => Navigator.pop(dialog, true), child: const Text('Stop plan')),
        ],
      ),
    );
    if (yes == true && context.mounted) await _run(context, () => onStop!(status.uid), 'Plan stopped');
  }

  static String _who(VendorPlanStatus s) => [if (s.vendorName.isNotEmpty) s.vendorName, if (s.vendorCode.isNotEmpty) s.vendorCode, if (s.vendorName.isEmpty && s.vendorCode.isEmpty) s.uid].join(' • ');

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    Row(children: [
      Expanded(child: Text('Plans', style: Theme.of(context).textTheme.headlineSmall)),
      FilledButton.icon(key: const ValueKey('plan-add'), onPressed: () => _edit(context), icon: const Icon(Icons.add), label: const Text('Add plan')),
    ]),
    const SizedBox(height: 4),
    const Text(
      'Each plan has: a price, how many years, extra photos, reach in km (how far from the shop customers see the ad, offers and alerts) '
      "and how many Today's Offers boxes. Vendors see exactly these names and prices. A vendor who already chose a plan keeps the price of that day. "
      'A plan never hides a shop.',
    ),
    const SizedBox(height: 12),
    if (plans.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No plans yet.', key: ValueKey('admin-plans-empty')))),
    for (final plan in sortedPlans(plans))
      Card(
        child: ListTile(
          key: ValueKey('admin-plan-${plan.id}'),
          title: Text(plan.name),
          subtitle: Text(
            '${planTiers[plan.tier]} • ${planPrice(plan.price)} for ${planDuration(plan.durationMonths)} • ${plan.extraPhotos} extra photos • '
            "reach ${kmText(plan.radiusKm)} • ${plan.offerBoxes} Today's Offers ${plan.offerBoxes == 1 ? 'box' : 'boxes'} • ${plan.itemLimit} items${plan.active ? '' : ' • Hidden from vendors'}",
          ),
          trailing: TextButton(key: ValueKey('admin-plan-edit-${plan.id}'), onPressed: () => _edit(context, plan), child: const Text('Edit')),
        ),
      ),
    const SizedBox(height: 8),
    Card(
      child: ListTile(
        key: const ValueKey('plan-free-limit'),
        title: const Text('Free plan'),
        subtitle: Text("Free for life: 1 shop photo + ${freeExtraPhotosOf(gates)} extra photos, ${freeItemLimit(gates)} items. A vendor's own item number (Vendors > item limit) is used when it is set."),
        trailing: Wrap(spacing: 4, children: [
          if (onFreePhotos != null) TextButton(key: const ValueKey('plan-free-photos-edit'), onPressed: () => _freePhotos(context), child: const Text('Photos')),
          if (onFreeLimit != null) TextButton(key: const ValueKey('plan-free-limit-edit'), onPressed: () => _freeLimit(context), child: const Text('Items')),
        ]),
      ),
    ),
    const SizedBox(height: 20),
    Row(children: [
      Expanded(child: Text('Vendors with a plan', style: Theme.of(context).textTheme.titleMedium)),
      if (onActivate != null && plans.isNotEmpty)
        OutlinedButton.icon(key: const ValueKey('plan-activate'), onPressed: () => _activate(context), icon: const Icon(Icons.add), label: const Text('Start a plan')),
    ]),
    const Text('Start a plan by hand when the vendor paid at the office. It runs for the plan\'s full duration from today, or from the end of the plan they already have.'),
    if (statuses.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No vendor has a plan yet.', key: ValueKey('plan-statuses-empty'))),
    for (final status in [...statuses]..sort((a, b) => b.endsAt.compareTo(a.endsAt)))
      Builder(builder: (context) {
        final running = status.activeAt(now ?? DateTime.now());
        return Card(
          child: ListTile(
            key: ValueKey('plan-status-${status.uid}'),
            title: Text(_who(status)),
            subtitle: Text(
              '${running ? 'Running' : 'Ended'} • ${status.planName} • ${running ? 'until' : 'ended'} ${planDate(status.endsAt)} • ${status.itemLimit} items${status.byAdmin ? ' • by admin' : ''}${status.renewalText.isEmpty ? '' : '\n${status.renewalText}'}',
              style: TextStyle(color: running ? null : Theme.of(context).colorScheme.error),
            ),
            trailing: Wrap(spacing: 4, children: [
              if (running && onStop != null) TextButton(key: ValueKey('plan-stop-${status.uid}'), onPressed: () => _stop(context, status), child: const Text('Stop')),
              if (onActivate != null && plans.isNotEmpty && status.vendorCode.isNotEmpty)
                TextButton(key: ValueKey('plan-renew-${status.uid}'), onPressed: () => _activate(context, vendorCode: status.vendorCode), child: Text(running ? 'Add' : 'Start again')),
            ]),
          ),
        );
      }),
    const SizedBox(height: 20),
    const Card(
      key: ValueKey('plan-related-settings'),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Related settings in other places', style: TextStyle(fontWeight: FontWeight.bold)),
          Text("• Seconds each Today's Offers box and ad box shows: Ads > Common settings for all ads."),
          Text("• Categories that need the vendor's own photo (for example sarees): Settings > Item photos."),
          Text('• Office phone and WhatsApp for paid vendors: Flash > Settings (at the top).'),
          Text('• Staff targets (each day, week and month) and missed days: Staff Areas > Settings.'),
        ]),
      ),
    ),
    const SizedBox(height: 20),
    Text('Services that need a plan', style: Theme.of(context).textTheme.titleMedium),
    const Text('When a switch is on, a vendor needs a running plan for new use of that service. Ads already live keep running until their own end date. When it is off, every approved vendor can use it, as before.'),
    for (final service in planServices.entries)
      SwitchListTile(
        key: ValueKey('plan-gate-${service.key}'),
        contentPadding: EdgeInsets.zero,
        title: Text(service.value),
        value: gates[service.key] == true,
        onChanged: (on) => _run(context, () => onGate(service.key, on), 'Saved'),
      ),
  ]);
}

/// Name, price and duration of a plan. Pops the fields to save (with planId when editing), or null when cancelled.
class PlanEditorDialog extends StatefulWidget {
  const PlanEditorDialog({super.key, this.plan});
  final SubscriptionPlan? plan;

  @override
  State<PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends State<PlanEditorDialog> {
  final formKey = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.plan?.name ?? '');
  late final price = TextEditingController(text: widget.plan == null ? '' : '${widget.plan!.price}');
  late final inYears = (widget.plan?.durationMonths ?? 12) % 12 == 0;
  late String unit = inYears ? 'years' : 'months';
  late final duration = TextEditingController(text: widget.plan == null ? '1' : '${inYears ? widget.plan!.durationMonths ~/ 12 : widget.plan!.durationMonths}');
  late bool active = widget.plan?.active ?? true;
  late final itemLimit = TextEditingController(text: '${widget.plan?.itemLimit ?? defaultPlanItemLimit}');
  late String tier = widget.plan?.tier ?? 'premium';
  late final extraPhotos = TextEditingController(text: '${widget.plan?.extraPhotos ?? defaultPlanExtraPhotos}');
  late final radiusKm = TextEditingController(text: kmText(widget.plan?.radiusKm ?? defaultPlanRadiusKm).replaceAll(' km', ''));
  // Today's Offers boxes: Silver 1, Gold 3, Premium 5 unless the admin types another number. Changing the kind of a new plan moves the
  // number to that kind's default until the admin types one.
  late final offerBoxes = TextEditingController(text: '${widget.plan?.offerBoxes ?? defaultOfferBoxes[tier]}');
  late bool boxesTyped = widget.plan != null;

  @override
  void dispose() {
    name.dispose();
    price.dispose();
    duration.dispose();
    itemLimit.dispose();
    extraPhotos.dispose();
    radiusKm.dispose();
    offerBoxes.dispose();
    super.dispose();
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    final count = int.parse(duration.text.trim());
    Navigator.pop(context, <String, dynamic>{
      if (widget.plan != null) 'planId': widget.plan!.id,
      'name': name.text.trim(),
      'price': num.parse(price.text.trim()),
      'durationMonths': unit == 'years' ? count * 12 : count,
      'itemLimit': int.parse(itemLimit.text.trim()),
      'tier': tier,
      'extraPhotos': int.parse(extraPhotos.text.trim()),
      'radiusKm': num.parse(radiusKm.text.trim()),
      'offerBoxes': int.parse(offerBoxes.text.trim()),
      'active': active,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.plan == null ? 'Add plan' : 'Edit plan'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              key: const ValueKey('plan-name'),
              controller: name,
              decoration: const InputDecoration(labelText: 'Plan name'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a plan name' : null,
            ),
            TextFormField(
              key: const ValueKey('plan-price'),
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Price (₹)'),
              validator: (v) => (num.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Enter a price above 0' : null,
            ),
            Row(children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('plan-duration'),
                  controller: duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'How long the plan runs'),
                  validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) < 1 ? 'Enter a whole number' : null,
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                key: const ValueKey('plan-unit'),
                value: unit,
                items: const [DropdownMenuItem(value: 'years', child: Text('Years')), DropdownMenuItem(value: 'months', child: Text('Months'))],
                onChanged: (v) => setState(() => unit = v ?? unit),
              ),
            ]),
            DropdownButtonFormField<String>(
              key: const ValueKey('plan-tier'),
              initialValue: tier,
              decoration: const InputDecoration(labelText: 'Plan type (Silver, Gold or Premium)'),
              items: [for (final t in planTiers.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
              onChanged: (v) => setState(() {
                tier = v ?? tier;
                if (!boxesTyped) offerBoxes.text = '${defaultOfferBoxes[tier]}';
              }),
            ),
            TextFormField(
              key: const ValueKey('plan-extra-photos'),
              controller: extraPhotos,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Extra photos', helperText: 'The 1 shop photo is free and not counted'),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return n == null || n < 0 || n > 30 ? 'Enter 0 to 30' : null;
              },
            ),
            TextFormField(
              key: const ValueKey('plan-radius'),
              controller: radiusKm,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Reach (km)', helperText: 'Customers within this distance of the shop see the ad, offers and alerts'),
              validator: (v) {
                final n = num.tryParse((v ?? '').trim());
                return n == null || n < 1 || n > 500 ? 'Enter 1 to 500 km' : null;
              },
            ),
            TextFormField(
              key: const ValueKey('plan-item-limit'),
              controller: itemLimit,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Items the vendor may list'),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return n == null || n < 1 || n > 100 ? 'Enter 1 to 100' : null;
              },
            ),
            TextFormField(
              key: const ValueKey('plan-offer-boxes'),
              controller: offerBoxes,
              keyboardType: TextInputType.number,
              onChanged: (_) => boxesTyped = true,
              decoration: const InputDecoration(labelText: "Today's Offers boxes", helperText: 'How many items the vendor can show in Today\'s Offers at one time'),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return n == null || n < 0 || n > maxOfferBoxes ? 'Enter 0 to $maxOfferBoxes' : null;
              },
            ),
            SwitchListTile(
              key: const ValueKey('plan-active'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Show to vendors'),
              value: active,
              onChanged: (v) => setState(() => active = v),
            ),
          ]),
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const ValueKey('plan-save'), onPressed: _save, child: const Text('Save')),
    ],
  );
}

/// Start a plan by hand: the Vendor ID and which plan. Pops (vendorCode, planId), or null when cancelled.
class ActivatePlanDialog extends StatefulWidget {
  const ActivatePlanDialog({super.key, required this.plans, this.vendorCode = ''});
  final List<SubscriptionPlan> plans;
  final String vendorCode;

  @override
  State<ActivatePlanDialog> createState() => _ActivatePlanDialogState();
}

class _ActivatePlanDialogState extends State<ActivatePlanDialog> {
  final formKey = GlobalKey<FormState>();
  late final code = TextEditingController(text: widget.vendorCode);
  late String? planId = widget.plans.isEmpty ? null : widget.plans.last.id;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Start a plan'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            key: const ValueKey('plan-activate-code'),
            controller: code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Vendor ID', hintText: 'VEN-NRPM-116-325'),
            validator: (v) => (v ?? '').trim().length < 5 ? 'Enter the Vendor ID' : null,
          ),
          DropdownButtonFormField<String>(
            key: const ValueKey('plan-activate-plan'),
            initialValue: planId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Plan'),
            items: [
              for (final plan in widget.plans)
                DropdownMenuItem(value: plan.id, child: Text('${plan.name} • ${planPrice(plan.price)} for ${planDuration(plan.durationMonths)}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => planId = v),
            validator: (v) => v == null ? 'Choose a plan' : null,
          ),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        key: const ValueKey('plan-activate-save'),
        onPressed: () {
          if (formKey.currentState!.validate()) Navigator.pop(context, (code.text.trim().toUpperCase(), planId!));
        },
        child: const Text('Start plan'),
      ),
    ],
  );
}

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({required this.title, required this.initial, required this.min});
  final String title;
  final int initial, min;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final value = TextEditingController(text: '${widget.initial}');
  String? error;

  @override
  void dispose() {
    value.dispose();
    super.dispose();
  }

  void _save() {
    final n = int.tryParse(value.text.trim());
    if (n == null || n < widget.min || n > 100) return setState(() => error = 'Enter ${widget.min} to 100');
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(key: const ValueKey('plan-number'), controller: value, keyboardType: TextInputType.number, decoration: InputDecoration(errorText: error)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const ValueKey('plan-number-save'), onPressed: _save, child: const Text('Save')),
    ],
  );
}
