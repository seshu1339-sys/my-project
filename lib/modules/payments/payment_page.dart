import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/store.dart';
import 'payment_data.dart';

/// Reads the payment and opens its Razorpay link. The screen itself is [PaymentView].
class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key, required this.store, required this.requestId});
  final Store store;
  final String requestId;

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  Store get store => widget.store;
  late final request = store.firestore.collection('paymentRequests').doc(widget.requestId).snapshots();

  Future<void> _pay() async {
    final url = (await store.call('startRazorpayPayment', {'requestId': widget.requestId}))['url'];
    if (url is! String || !await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) throw StateError('The payment page could not open.');
  }

  Future<String> _check() async => '${(await store.call('checkRazorpayPayment', {'requestId': widget.requestId}))['status']}';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Payment')),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: request,
      builder: (context, requestDoc) {
        final data = requestDoc.data?.data();
        if (requestDoc.hasError) return const Center(child: Text('The payment could not load.'));
        if (data == null) return const Center(child: CircularProgressIndicator());
        return PaymentView(request: PaymentRequest.fromData(widget.requestId, data), onPay: _pay, onCheck: _check);
      },
    ),
  );
}

/// How much to pay and the Razorpay button. Razorpay opens in the browser (UPI, cards, net banking); the server hears from Razorpay
/// when it is paid, and "I have paid" asks it at once.
class PaymentView extends StatefulWidget {
  const PaymentView({super.key, required this.request, required this.onPay, required this.onCheck});
  final PaymentRequest request;
  final Future<void> Function() onPay;
  // The status after asking Razorpay.
  final Future<String> Function() onCheck;

  @override
  State<PaymentView> createState() => _PaymentViewState();
}

class _PaymentViewState extends State<PaymentView> {
  bool busy = false;
  bool opened = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${e is StateError ? e.message : e}')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _check() async {
    final status = await widget.onCheck();
    if (!mounted || status == 'verified') return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Razorpay has not confirmed the payment yet. If you paid, wait a minute and check again.')));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final money = paymentMoney(r.amount);
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(r.label, style: Theme.of(context).textTheme.titleLarge),
      Text(money, key: const ValueKey('payment-amount'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      switch (r.status) {
        'awaiting_payment' => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Pay safely with Razorpay: UPI, debit or credit card, or net banking. The payment page opens in your browser.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('payment-pay'),
            onPressed: busy ? null : () => _run(() async {
              await widget.onPay();
              if (mounted) setState(() => opened = true);
            }),
            icon: const Icon(Icons.lock_outline),
            label: Text('Pay $money with Razorpay'),
          ),
          if (opened) ...[
            const SizedBox(height: 8),
            OutlinedButton(key: const ValueKey('payment-check'), onPressed: busy ? null : () => _run(_check), child: const Text('I have paid: check now')),
            const Text('Your plan starts by itself once Razorpay confirms the payment, usually within a minute.', style: TextStyle(fontSize: 12)),
          ],
        ]),
        'verified' => const ListTile(key: ValueKey('payment-done'), leading: Icon(Icons.check_circle, color: Colors.green), title: Text('Payment received. Thank you!')),
        'paid_after_cancel' => const ListTile(leading: Icon(Icons.info_outline), title: Text('You paid for a choice you had already changed. The office will refund it.')),
        _ => ListTile(leading: const Icon(Icons.block), title: Text(paymentStatusWords[r.status] ?? 'This payment is closed.')),
      },
    ]);
  }
}
