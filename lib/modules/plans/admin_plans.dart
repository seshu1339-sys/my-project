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
      builder: (context, gates) {
        if (plans.hasError) return const Center(child: Text('Plans could not load.'));
        if (!plans.hasData) return const Center(child: CircularProgressIndicator());
        return AdminPlansView(
          plans: [for (final doc in plans.data!.docs) SubscriptionPlan.fromData(doc.id, doc.data())],
          gates: gates.data?.data() ?? const {},
          onSave: (fields) => store.call('savePlan', fields),
          onGate: (service, on) => store.call('savePlanGates', {service: on}),
        );
      },
    ),
  );
}

class AdminPlansView extends StatelessWidget {
  const AdminPlansView({super.key, required this.plans, required this.gates, required this.onSave, required this.onGate});
  final List<SubscriptionPlan> plans;
  final Map<String, dynamic> gates;
  final Future<void> Function(Map<String, dynamic> fields) onSave;
  final Future<void> Function(String service, bool on) onGate;

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

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    Row(children: [
      Expanded(child: Text('Plans', style: Theme.of(context).textTheme.headlineSmall)),
      FilledButton.icon(key: const ValueKey('plan-add'), onPressed: () => _edit(context), icon: const Icon(Icons.add), label: const Text('Add plan')),
    ]),
    const SizedBox(height: 4),
    const Text('Vendors see exactly these names and prices. A vendor who already chose a plan keeps the price of that day. A plan never hides a shop.'),
    const SizedBox(height: 12),
    if (plans.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No plans yet.', key: ValueKey('admin-plans-empty')))),
    for (final plan in sortedPlans(plans))
      Card(
        child: ListTile(
          key: ValueKey('admin-plan-${plan.id}'),
          title: Text(plan.name),
          subtitle: Text('${planPrice(plan.price)} for ${planDuration(plan.durationMonths)}${plan.active ? '' : ' • Hidden from vendors'}'),
          trailing: TextButton(key: ValueKey('admin-plan-edit-${plan.id}'), onPressed: () => _edit(context, plan), child: const Text('Edit')),
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

  @override
  void dispose() {
    name.dispose();
    price.dispose();
    duration.dispose();
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
                  decoration: const InputDecoration(labelText: 'Duration'),
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
