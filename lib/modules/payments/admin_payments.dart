import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../home_module.dart';
import 'payment_data.dart';

Widget _build(Store store) => AdminPaymentsPage(store: store);

/// The Payments tab of the admin panel (listed in module_admin.dart).
const paymentsAdminSection = ModuleAdminSection(id: 'payments', title: 'Payments', icon: Icons.account_balance_outlined, hint: 'Razorpay on/off and recent payments', build: _build);

/// Admin > Payments: the Razorpay switch, saved through the module's own callable, and the latest payments.
class AdminPaymentsPage extends StatelessWidget {
  const AdminPaymentsPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('paymentSettings').doc('main').snapshots(),
    builder: (context, settings) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('paymentRequests').orderBy('createdAt', descending: true).limit(50).snapshots(),
      builder: (context, recent) {
        if (settings.hasError || recent.hasError) return const Center(child: Text('Payments could not load.'));
        if (!settings.hasData || !recent.hasData) return const Center(child: CircularProgressIndicator());
        final saved = settings.data?.data() ?? const {};
        return AdminPaymentsView(
          enabled: saved['enabled'] == true,
          keysSet: saved['keysSet'] == true,
          recent: [for (final doc in recent.data!.docs) PaymentRequest.fromData(doc.id, doc.data())],
          onSwitch: (on) async => Map<String, dynamic>.from(await store.call('savePaymentSettings', {'enabled': on})),
        );
      },
    ),
  );
}

class AdminPaymentsView extends StatefulWidget {
  const AdminPaymentsView({super.key, required this.enabled, required this.keysSet, required this.recent, required this.onSwitch});
  final bool enabled, keysSet;
  final List<PaymentRequest> recent;
  // Saves the switch; the answer says whether the keys are set.
  final Future<Map<String, dynamic>> Function(bool on) onSwitch;

  @override
  State<AdminPaymentsView> createState() => _AdminPaymentsViewState();
}

class _AdminPaymentsViewState extends State<AdminPaymentsView> {
  bool busy = false;

  Future<void> _switch(bool on) async {
    setState(() => busy = true);
    try {
      final result = await widget.onSwitch(on);
      if (!mounted) return;
      final text = !on ? 'Payments are off. Vendors see "Payments will open soon".' : result['ready'] == true ? 'Payments are on.' : 'Saved, but the Razorpay keys are not set yet, so payments stay closed.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Card(
      child: Column(children: [
        SwitchListTile(
          key: const ValueKey('payments-switch'),
          title: const Text('Vendors can pay with Razorpay'),
          subtitle: Text(widget.keysSet ? 'Razorpay keys are set.' : 'Razorpay keys are not set yet: payments stay closed even when this is on.'),
          value: widget.enabled,
          onChanged: busy ? null : _switch,
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'Payments are confirmed by Razorpay itself; nothing here needs checking by hand. A payment marked "refund it" came in for a choice '
            'the vendor had already changed: refund it from the Razorpay dashboard. A refund made there shows here as "Refunded"; it does not stop the plan of the vendor, so stop that by hand if needed.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ]),
    ),
    const SizedBox(height: 12),
    Text('Latest payments', style: Theme.of(context).textTheme.titleMedium),
    if (widget.recent.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No payments yet.')),
    for (final r in widget.recent)
      ListTile(
        key: ValueKey('payment-${r.id}'),
        title: Text('${r.label} · ${paymentMoney(r.amount)}'),
        subtitle: Text([paymentStatusWords[r.status] ?? r.status, if (r.refundedAmount > 0 && r.status != 'refunded') 'part refund ${paymentMoney(r.refundedAmount)}', if (r.failureReason.isNotEmpty && r.status == 'awaiting_payment') 'last try failed: ${r.failureReason}', if (r.razorpayPaymentId.isNotEmpty) r.razorpayPaymentId, 'vendor ${r.uid}'].join(' · ')),
        leading: Icon(r.status == 'verified' ? Icons.check_circle_outline : r.status == 'paid_after_cancel' ? Icons.warning_amber : r.status == 'refunded' ? Icons.undo : Icons.schedule),
      ),
  ]);
}
