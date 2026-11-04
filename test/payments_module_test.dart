import 'package:ecommerce_app/modules/payments/admin_payments.dart';
import 'package:ecommerce_app/modules/payments/payment_data.dart';
import 'package:ecommerce_app/modules/payments/payment_page.dart';
import 'package:ecommerce_app/modules/payments/payments_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PaymentRequest request(String status, {String paymentId = ''}) => PaymentRequest(id: 'r1', uid: 'v1', label: '3 Year plan', amount: 4999, status: status, razorpayPaymentId: paymentId);

Widget page(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  test('the module has its own route', () {
    expect(paymentsRoute, '/payments');
    expect(paymentMoney(4999), '₹4999');
    expect(paymentMoney(99.5), '₹99.50');
  });

  testWidgets('a vendor sees the amount, pays with Razorpay, then can ask whether it went through', (tester) async {
    var paid = 0, checked = 0;
    await tester.pumpWidget(page(PaymentView(request: request('awaiting_payment'), onPay: () async => paid++, onCheck: () async {
      checked++;
      return 'awaiting_payment';
    })));
    expect(find.text('₹4999'), findsOneWidget);
    expect(find.text('Pay ₹4999 with Razorpay'), findsOneWidget);
    expect(find.byKey(const ValueKey('payment-check')), findsNothing, reason: 'nothing to check before paying');
    expect(find.textContaining('screenshot'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('payment-pay')));
    await tester.pumpAndSettle();
    expect(paid, 1);
    await tester.tap(find.byKey(const ValueKey('payment-check')));
    await tester.pumpAndSettle();
    expect(checked, 1);
    expect(find.textContaining('has not confirmed the payment yet'), findsOneWidget);
  });

  testWidgets('a link that cannot open says so', (tester) async {
    await tester.pumpWidget(page(PaymentView(request: request('awaiting_payment'), onPay: () async => throw StateError('The payment page could not open.'), onCheck: () async => '')));
    await tester.tap(find.byKey(const ValueKey('payment-pay')));
    await tester.pumpAndSettle();
    expect(find.text('The payment page could not open.'), findsOneWidget);
  });

  testWidgets('each status after paying is said plainly, with no pay button', (tester) async {
    for (final (status, text) in [('verified', 'Payment received. Thank you!'), ('paid_after_cancel', 'The office will refund it'), ('cancelled', 'Cancelled')]) {
      await tester.pumpWidget(page(PaymentView(request: request(status), onPay: () async {}, onCheck: () async => status)));
      expect(find.textContaining(text), findsOneWidget, reason: status);
      expect(find.byKey(const ValueKey('payment-pay')), findsNothing, reason: status);
    }
  });

  testWidgets('the admin switches Razorpay on, is told when the keys are missing, and sees the latest payments', (tester) async {
    final switched = <bool>[];
    await tester.pumpWidget(page(AdminPaymentsView(
      enabled: false,
      keysSet: false,
      recent: [request('verified', paymentId: 'pay_ABC'), request('paid_after_cancel')],
      onSwitch: (on) async {
        switched.add(on);
        return {'ready': false, 'keysSet': false};
      },
    )));
    expect(find.textContaining('keys are not set yet'), findsOneWidget);
    expect(find.textContaining('pay_ABC'), findsOneWidget);
    expect(find.textContaining('refund it'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('payments-switch')));
    await tester.pumpAndSettle();
    expect(switched, [true]);
    expect(find.text('Saved, but the Razorpay keys are not set yet, so payments stay closed.'), findsOneWidget);
  });

  testWidgets('a failed try, a closed link and refunds are said plainly', (tester) async {
    PaymentRequest with_(String status, {num refunded = 0, String failure = '', bool closed = false}) =>
        PaymentRequest(id: 'r1', uid: 'v1', label: '3 Year plan', amount: 4999, status: status, refundedAmount: refunded, failureReason: failure, linkClosed: closed);
    Future<void> show(PaymentRequest r) => tester.pumpWidget(page(PaymentView(request: r, onPay: () async {}, onCheck: () async => '')));
    await show(with_('awaiting_payment', failure: 'Your bank declined the payment.'));
    expect(find.textContaining('did not go through: Your bank declined the payment.'), findsOneWidget);
    expect(find.byKey(const ValueKey('payment-pay')), findsOneWidget, reason: 'can try again');
    await show(with_('awaiting_payment', closed: true));
    expect(find.byKey(const ValueKey('payment-link-closed')), findsOneWidget);
    expect(find.byKey(const ValueKey('payment-pay')), findsOneWidget);
    await show(with_('refunded', refunded: 4999));
    expect(find.textContaining('Refunded: ₹4999 was sent back'), findsOneWidget);
    expect(find.byKey(const ValueKey('payment-pay')), findsNothing);
    await show(with_('verified', refunded: 1000));
    expect(find.text('Payment received. Thank you!'), findsOneWidget);
    expect(find.textContaining('part refund of ₹1000'), findsOneWidget);
    await tester.pumpWidget(page(AdminPaymentsView(enabled: true, keysSet: true, recent: [with_('refunded', refunded: 4999), with_('awaiting_payment', failure: 'Card declined.')], onSwitch: (_) async => const {})));
    expect(find.textContaining('Refunded'), findsWidgets);
    expect(find.textContaining('last try failed: Card declined.'), findsOneWidget);
  });

  testWidgets('the screens fit a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(page(PaymentView(request: request('awaiting_payment'), onPay: () async {}, onCheck: () async => '')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(page(AdminPaymentsView(enabled: true, keysSet: true, recent: [request('verified')], onSwitch: (_) async => const {})));
    expect(tester.takeException(), isNull);
  });
}
