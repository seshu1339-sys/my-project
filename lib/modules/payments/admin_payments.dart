import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../home_module.dart';
import 'admin_payment_settings.dart';
import 'payment_data.dart';

Widget _build(Store store) => AdminPaymentsPage(store: store);

/// The Payments tab of the admin panel (listed in module_admin.dart).
const paymentsAdminSection = ModuleAdminSection(id: 'payments', title: 'Payments', icon: Icons.account_balance_outlined, hint: 'Manual check and bank settings', build: _build);

/// Admin > Payments: the manual check list and the bank settings, saved through the module's own callables.
class AdminPaymentsPage extends StatelessWidget {
  const AdminPaymentsPage({super.key, required this.store});
  final Store store;

  Future<String> _screenshotUrl(String path) => FirebaseStorage.instance.ref(path).getDownloadURL();

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('paymentRequests').where('status', isEqualTo: 'manual_review').snapshots(),
    builder: (context, waiting) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('paymentBankConfig').doc('main').snapshots(),
      builder: (context, config) {
        if (waiting.hasError || config.hasError) return const Center(child: Text('Payments could not load.'));
        // The settings boxes are filled once, so they wait for the saved values: placeholders must never be saved over them.
        if (!waiting.hasData || !config.hasData) return const Center(child: CircularProgressIndicator());
        final saved = config.data?.data();
        return AdminPaymentsView(
          waiting: [for (final doc in waiting.data!.docs) PaymentRequest.fromData(doc.id, doc.data())],
          config: saved == null ? placeholderBankConfig : BankConfig(saved),
          screenshotUrl: _screenshotUrl,
          onDecide: (id, action) => store.call('reviewPayment', {'requestId': id, 'action': action}),
          onSaveConfig: (fields) => store.call('savePaymentConfig', fields),
          onTest: (sender, text) => store.call('testPaymentSms', {'sender': sender, 'text': text}),
        );
      },
    ),
  );
}

class AdminPaymentsView extends StatelessWidget {
  const AdminPaymentsView({super.key, required this.waiting, required this.config, required this.screenshotUrl, required this.onDecide, required this.onSaveConfig, required this.onTest});
  final List<PaymentRequest> waiting;
  final BankConfig config;
  final Future<String> Function(String path) screenshotUrl;
  final Future<void> Function(String requestId, String action) onDecide;
  final Future<void> Function(Map<String, dynamic> fields) onSaveConfig;
  final Future<Map<String, dynamic>> Function(String sender, String text) onTest;

  Future<void> _decide(BuildContext context, PaymentRequest request, String action) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(action == 'approve' ? 'Approve ${paymentMoney(request.amount)}?' : 'Reject this payment?'),
        content: Text(action == 'approve' ? 'Check the money is in the bank first. This activates what the vendor paid for.' : 'The vendor is told it was not accepted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('payment-confirm'), onPressed: () => Navigator.pop(dialog, true), child: Text(action == 'approve' ? 'Approve' : 'Reject')),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await onDecide(request.id, action);
      messenger.showSnackBar(SnackBar(content: Text(action == 'approve' ? 'Approved' : 'Rejected')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _claim(PaymentRequest request) {
    final amount = request.claimedAmount;
    return Text('The screenshot says: ${amount == null ? 'nothing readable' : '${paymentMoney(amount)}, ID ${request.claimedId}, ${request.claimedDate} ${request.claimedTime}'}');
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    Text('Manual check', style: Theme.of(context).textTheme.headlineSmall),
    const Text('Payments that could not be confirmed by a bank SMS. AI only reads the screenshot; nothing here is approved until you do it.'),
    const SizedBox(height: 8),
    if (waiting.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Nothing is waiting.', key: ValueKey('payments-none-waiting')))),
    for (final request in waiting)
      Card(
        key: ValueKey('payment-${request.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${request.label}: ${paymentMoney(request.amount)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(request.reviewReason),
            _claim(request),
            if (request.screenshotPath.isNotEmpty)
              FutureBuilder<String>(
                future: screenshotUrl(request.screenshotPath),
                builder: (context, url) => url.hasData
                    ? Padding(padding: const EdgeInsets.only(top: 8), child: Image.network(url.data!, height: 240, errorBuilder: (_, _, _) => const Text('The screenshot could not load.')))
                    : const SizedBox.shrink(),
              ),
            Wrap(spacing: 4, children: [
              TextButton(key: ValueKey('payment-approve-${request.id}'), onPressed: () => _decide(context, request, 'approve'), child: const Text('Approve')),
              TextButton(key: ValueKey('payment-reject-${request.id}'), onPressed: () => _decide(context, request, 'reject'), child: const Text('Reject')),
            ]),
          ]),
        ),
      ),
    const SizedBox(height: 24),
    AdminPaymentSettings(config: config, onSave: onSaveConfig, onTest: onTest),
  ]);
}
