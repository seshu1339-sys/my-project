import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/store.dart';
import 'payment_data.dart';

/// A chosen screenshot: its bytes untouched, because shrinking it could blur the payment id.
class PickedScreenshot {
  const PickedScreenshot(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
}

/// Reads the payment and the bank details, and sends the screenshot. The screen itself is [PaymentView].
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
  late final bank = store.firestore.collection('paymentBankPublic').doc('main').snapshots();

  Future<void> _send(PickedScreenshot shot) async {
    final uid = store.user?.uid;
    if (uid == null) throw StateError('Sign in first.');
    final path = 'paymentScreenshots/$uid/${widget.requestId}_${DateTime.now().microsecondsSinceEpoch}';
    await FirebaseStorage.instance.ref(path).putData(shot.bytes, SettableMetadata(contentType: shot.contentType));
    await store.call('submitPaymentScreenshot', {'requestId': widget.requestId, 'path': path});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Payment')),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: request,
      builder: (context, requestDoc) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: bank,
        builder: (context, bankDoc) {
          final data = requestDoc.data?.data(), details = bankDoc.data?.data();
          if (requestDoc.hasError || bankDoc.hasError) return const Center(child: Text('The payment could not load.'));
          if (data == null || details == null) return const Center(child: CircularProgressIndicator());
          return PaymentView(request: PaymentRequest.fromData(widget.requestId, data), bank: BankDetails.fromData(details), onSend: _send);
        },
      ),
    ),
  );
}

/// How much to pay, where to, and the screenshot. After sending, it says what is happening.
class PaymentView extends StatefulWidget {
  const PaymentView({super.key, required this.request, required this.bank, required this.onSend, this.pick});
  final PaymentRequest request;
  final BankDetails bank;
  final Future<void> Function(PickedScreenshot shot) onSend;

  /// Chooses a screenshot; the gallery unless a test gives another.
  final Future<PickedScreenshot?> Function()? pick;

  @override
  State<PaymentView> createState() => _PaymentViewState();
}

class _PaymentViewState extends State<PaymentView> {
  bool busy = false;

  Future<PickedScreenshot?> _gallery() async {
    // No maxWidth or quality here: the photo goes up exactly as it is.
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    final name = file.name.toLowerCase();
    final type = name.endsWith('.png') ? 'image/png' : name.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
    return PickedScreenshot(await file.readAsBytes(), type);
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final shot = await (widget.pick ?? _gallery)();
      if (shot == null || !mounted) return;
      setState(() => busy = true);
      await widget.onSend(shot);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      SizedBox(width: 110, child: Text(label)),
      Expanded(child: SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w600))),
      IconButton(
        tooltip: 'Copy $label',
        icon: const Icon(Icons.copy, size: 18),
        onPressed: () => Clipboard.setData(ClipboardData(text: value)),
      ),
    ]),
  );

  String? get _status => switch (widget.request.status) {
    'checking' => 'Your screenshot is in. We are matching it with the bank; this can take up to a few hours.',
    'manual_review' => 'The office is checking your payment. You will be told when it is done.',
    'verified' => 'Your payment is confirmed. Thank you.',
    'rejected' => 'This payment was not accepted. Please contact the office.',
    'cancelled' => 'This payment was cancelled.',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final request = widget.request, bank = widget.bank;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(request.label, style: Theme.of(context).textTheme.titleMedium),
      Text(paymentMoney(request.amount), key: const ValueKey('payment-amount'), style: Theme.of(context).textTheme.headlineMedium),
      if (_status case final status?)
        Padding(padding: const EdgeInsets.only(top: 12), child: Text(status, key: const ValueKey('payment-status')))
      else ...[
        const SizedBox(height: 12),
        const Text('Pay exactly this amount by UPI, then send the screenshot of the successful payment.'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              _row('UPI ID', bank.upiId),
              _row('Account name', bank.accountName),
              _row('Account no.', bank.accountNumber),
              _row('IFSC', bank.ifsc),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('payment-send'),
          onPressed: busy ? null : _send,
          icon: const Icon(Icons.upload_file),
          label: Text(busy ? 'Checking...' : 'Send payment screenshot'),
        ),
      ],
    ]);
  }
}
