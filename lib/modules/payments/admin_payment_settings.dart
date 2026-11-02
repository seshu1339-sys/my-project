import 'package:flutter/material.dart';

import 'payment_data.dart';

/// The bank settings. Any value starting with XX means "not filled in yet", and payments stay closed until none is left. One SMS format per
/// pattern: words that show money came in, then the amount and the payment id, each in one pair of brackets.
class AdminPaymentSettings extends StatefulWidget {
  const AdminPaymentSettings({super.key, required this.config, required this.onSave, required this.onTest});
  final BankConfig config;
  final Future<void> Function(Map<String, dynamic> fields) onSave;
  final Future<Map<String, dynamic>> Function(String sender, String text) onTest;

  @override
  State<AdminPaymentSettings> createState() => _AdminPaymentSettingsState();
}

class _AdminPaymentSettingsState extends State<AdminPaymentSettings> {
  late final accountName = TextEditingController(text: widget.config.text('accountName'));
  late final accountNumber = TextEditingController(text: widget.config.text('accountNumber'));
  late final ifsc = TextEditingController(text: widget.config.text('ifsc'));
  late final upiId = TextEditingController(text: widget.config.text('upiId'));
  late final senders = TextEditingController(text: widget.config.senders.join(', '));
  late final credit = TextEditingController(text: _pattern('credit'));
  late final amount = TextEditingController(text: _pattern('amount'));
  late final paymentId = TextEditingController(text: _pattern('paymentId'));
  late final window = TextEditingController(text: '${widget.config.number('windowHours', 3)}');
  late final daily = TextEditingController(text: '${widget.config.number('dailyScreenshots', 5)}');
  final testSender = TextEditingController();
  final testText = TextEditingController();
  String? testResult;

  String _pattern(String key) => widget.config.patterns.firstOrNull?[key]?.toString() ?? '';

  @override
  void dispose() {
    for (final field in [accountName, accountNumber, ifsc, upiId, senders, credit, amount, paymentId, window, daily, testSender, testText]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onSave({
        'accountName': accountName.text.trim(),
        'accountNumber': accountNumber.text.trim(),
        'ifsc': ifsc.text.trim(),
        'upiId': upiId.text.trim(),
        'smsSenders': [for (final s in senders.text.split(',')) if (s.trim().isNotEmpty) s.trim()],
        'smsPatterns': [
          {'credit': credit.text.trim(), 'amount': amount.text.trim(), 'paymentId': paymentId.text.trim()},
        ],
        'windowHours': int.tryParse(window.text.trim()) ?? 0,
        'dailyScreenshots': int.tryParse(daily.text.trim()) ?? 0,
      });
      messenger.showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _test() async {
    try {
      final result = await widget.onTest(testSender.text.trim(), testText.text);
      final found = result['found'];
      setState(() => testResult = '${result['senderAllowed'] == true ? 'Sender accepted' : 'Sender NOT accepted'}. ${found is Map ? 'Found: ID ${found['paymentId']}, amount ${found['amount']}' : 'Nothing found in this SMS'}.');
    } catch (e) {
      setState(() => testResult = '$e');
    }
  }

  Widget _field(String key, TextEditingController controller, String label, {int lines = 1}) => TextField(
    key: ValueKey('bank-$key'),
    controller: controller,
    maxLines: lines,
    decoration: InputDecoration(labelText: label),
  );

  bool get _unfilled => [accountName, accountNumber, ifsc, upiId, senders, credit, amount, paymentId].any((c) => c.text.trim().startsWith('XX'));

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Bank settings', style: Theme.of(context).textTheme.headlineSmall),
    if (_unfilled)
      const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text('Values starting with XX are not filled in. Until none is left, vendors see "Payments will open soon" and no SMS is matched.', key: ValueKey('bank-unfilled'), style: TextStyle(color: Colors.red)),
      ),
    _field('accountName', accountName, 'Account name'),
    _field('accountNumber', accountNumber, 'Account number'),
    _field('ifsc', ifsc, 'IFSC'),
    _field('upiId', upiId, 'UPI ID'),
    _field('senders', senders, 'SMS sender IDs (separate with commas)'),
    _field('credit', credit, 'Words that show money came in'),
    _field('amount', amount, 'Amount pattern (the amount in brackets)'),
    _field('paymentId', paymentId, 'Payment ID pattern (the ID in brackets)'),
    _field('window', window, 'Hours to wait for the SMS'),
    _field('daily', daily, 'Screenshots a vendor may send in a day'),
    const SizedBox(height: 8),
    FilledButton(key: const ValueKey('bank-save'), onPressed: _save, child: const Text('Save bank settings')),
    const SizedBox(height: 16),
    Text('Test an SMS', style: Theme.of(context).textTheme.titleMedium),
    const Text('Tests what is saved above. Nothing here is stored.'),
    _field('test-sender', testSender, 'Sender'),
    _field('test-text', testText, 'SMS text', lines: 3),
    const SizedBox(height: 8),
    OutlinedButton(key: const ValueKey('bank-test'), onPressed: _test, child: const Text('Test')),
    if (testResult != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(testResult!, key: const ValueKey('bank-test-result'))),
  ]);
}
