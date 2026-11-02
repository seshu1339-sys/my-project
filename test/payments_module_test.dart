import 'dart:typed_data';

import 'package:ecommerce_app/modules/payments/admin_payments.dart';
import 'package:ecommerce_app/modules/payments/payment_data.dart';
import 'package:ecommerce_app/modules/payments/payment_page.dart';
import 'package:ecommerce_app/modules/payments/payments_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const bank = BankDetails(accountName: 'Local Market', accountNumber: '501000', ifsc: 'HDFC0000001', upiId: 'lm@hdfcbank');

PaymentRequest request(String status, {String reason = '', num? claimed}) => PaymentRequest(id: 'r1', uid: 'v1', label: '1 Year plan', amount: 4999, status: status, reviewReason: reason, claimedAmount: claimed, claimedId: claimed == null ? '' : '123456789012', claimedDate: '2026-11-02', claimedTime: '09:30');

Widget page(Widget child) => MaterialApp(home: Scaffold(body: child));

void wide(WidgetTester tester, [Size size = const Size(1000, 2400)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

AdminPaymentsView admin({List<PaymentRequest> waiting = const [], BankConfig config = placeholderBankConfig, Future<void> Function(String, String)? onDecide, Future<void> Function(Map<String, dynamic>)? onSave, Future<Map<String, dynamic>> Function(String, String)? onTest}) => AdminPaymentsView(
  waiting: waiting,
  config: config,
  screenshotUrl: (_) async => 'https://example.com/s.png',
  onDecide: onDecide ?? (_, _) async {},
  onSaveConfig: onSave ?? (_) async {},
  onTest: onTest ?? (_, _) async => const {},
);

void main() {
  test('the module has its own route', () {
    expect(paymentsRoute, '/payments');
    expect(paymentMoney(4999), '₹4999');
    expect(paymentMoney(99.5), '₹99.50');
  });

  test('the placeholders are plainly marked XX', () {
    expect(placeholderBankConfig.text('accountNumber'), startsWith('XX'));
    expect(placeholderBankConfig.senders.single, startsWith('XX'));
    expect(placeholderBankConfig.patterns.single.values, everyElement(startsWith('XX')));
  });

  testWidgets('a vendor sees the amount and where to pay, and sends the screenshot untouched', (tester) async {
    wide(tester);
    final sent = <PickedScreenshot>[];
    final bytes = Uint8List.fromList([1, 2, 3]);
    await tester.pumpWidget(page(PaymentView(
      request: request('awaiting_payment'),
      bank: bank,
      pick: () async => PickedScreenshot(bytes, 'image/png'),
      onSend: (shot) async => sent.add(shot),
    )));
    expect(find.text('₹4999'), findsOneWidget);
    expect(find.text('lm@hdfcbank'), findsOneWidget);
    expect(find.text('HDFC0000001'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('payment-send')));
    await tester.pumpAndSettle();
    expect(sent.single.bytes, bytes);
  });

  testWidgets('a refused screenshot shows the server\'s reason', (tester) async {
    wide(tester);
    await tester.pumpWidget(page(PaymentView(
      request: request('awaiting_payment'),
      bank: bank,
      pick: () async => PickedScreenshot(Uint8List(1), 'image/png'),
      onSend: (_) async => throw StateError('This payment ID was already used.'),
    )));
    await tester.tap(find.byKey(const ValueKey('payment-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('already used'), findsOneWidget);
  });

  testWidgets('after sending there is no second send, and each status is said plainly', (tester) async {
    wide(tester);
    for (final (status, words) in [('checking', 'matching'), ('manual_review', 'office is checking'), ('verified', 'confirmed'), ('rejected', 'not accepted')]) {
      await tester.pumpWidget(page(PaymentView(key: ValueKey(status), request: request(status), bank: bank, onSend: (_) async {})));
      expect(find.textContaining(words), findsOneWidget, reason: status);
      expect(find.byKey(const ValueKey('payment-send')), findsNothing, reason: status);
    }
  });

  testWidgets('the admin sees why, what the screenshot says, and decides after confirming', (tester) async {
    wide(tester);
    final calls = <String>[];
    await tester.pumpWidget(page(admin(
      waiting: [request('manual_review', reason: 'No bank SMS came in time.', claimed: 4999)],
      onDecide: (id, action) async => calls.add('$action $id'),
    )));
    expect(find.text('No bank SMS came in time.'), findsOneWidget);
    expect(find.textContaining('ID 123456789012'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('payment-approve-r1')));
    await tester.pumpAndSettle();
    expect(calls, isEmpty, reason: 'nothing happens before confirming');
    await tester.tap(find.byKey(const ValueKey('payment-confirm')));
    await tester.pumpAndSettle();
    expect(calls, ['approve r1']);
    await tester.tap(find.byKey(const ValueKey('payment-reject-r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment-confirm')));
    await tester.pumpAndSettle();
    expect(calls.last, 'reject r1');
  });

  testWidgets('an unreadable screenshot says so', (tester) async {
    wide(tester);
    await tester.pumpWidget(page(admin(waiting: [request('manual_review', reason: 'The screenshot could not be read.')])));
    expect(find.textContaining('nothing readable'), findsOneWidget);
  });

  testWidgets('the settings warn about XX values and save what is typed', (tester) async {
    wide(tester);
    Map<String, dynamic>? saved;
    await tester.pumpWidget(page(admin(onSave: (fields) async => saved = fields)));
    expect(find.byKey(const ValueKey('bank-unfilled')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('bank-senders')), 'HDFCBK, HDFCBN');
    await tester.enterText(find.byKey(const ValueKey('bank-window')), '4');
    await tester.tap(find.byKey(const ValueKey('bank-save')));
    await tester.pumpAndSettle();
    expect(saved?['smsSenders'], ['HDFCBK', 'HDFCBN']);
    expect(saved?['windowHours'], 4);
    expect(saved?['dailyScreenshots'], 5);
    expect((saved?['smsPatterns'] as List).single['credit'], 'XX-CREDIT-WORDS');
  });

  testWidgets('the test box shows what was found', (tester) async {
    wide(tester);
    await tester.pumpWidget(page(admin(onTest: (sender, text) async => {'senderAllowed': true, 'found': {'paymentId': '123', 'amount': 10}})));
    await tester.enterText(find.byKey(const ValueKey('bank-test-text')), 'sample');
    await tester.tap(find.byKey(const ValueKey('bank-test')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sender accepted'), findsOneWidget);
    expect(find.textContaining('ID 123, amount 10'), findsOneWidget);
  });

  testWidgets('the screens fit a small phone', (tester) async {
    wide(tester, const Size(320, 640));
    await tester.pumpWidget(page(PaymentView(request: request('awaiting_payment'), bank: bank, onSend: (_) async {})));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(page(admin(waiting: [request('manual_review', reason: 'Why', claimed: 1)])));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
