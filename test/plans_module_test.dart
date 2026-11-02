import 'package:ecommerce_app/modules/plans/admin_plans.dart';
import 'package:ecommerce_app/modules/plans/plan_model.dart';
import 'package:ecommerce_app/modules/plans/vendor_plans_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const yearly = SubscriptionPlan(id: 'p1', name: '1 Year', price: 4999, durationMonths: 12, active: true);
const twoYears = SubscriptionPlan(id: 'p2', name: '2 Years', price: 8999.5, durationMonths: 24, active: true);

Widget _page(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

Future<void> _openDialog(WidgetTester tester, [SubscriptionPlan? plan, void Function(Map<String, dynamic>?)? done]) => tester.pumpWidget(MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async => done?.call(await showDialog<Map<String, dynamic>>(context: context, builder: (_) => PlanEditorDialog(plan: plan))),
        child: const Text('open'),
      ),
    ),
  ),
));

void main() {
  test('durations and prices read as the admin set them', () {
    expect(planDuration(12), '1 year');
    expect(planDuration(36), '3 years');
    expect(planDuration(1), '1 month');
    expect(planDuration(18), '18 months');
    expect(planPrice(4999), '₹4999');
    expect(planPrice(8999.5), '₹8999.50');
  });

  test('plans sort by duration, then price', () {
    const cheap = SubscriptionPlan(id: 'c', name: 'Cheap', price: 100, durationMonths: 12, active: true);
    expect(sortedPlans([twoYears, yearly, cheap]).map((p) => p.id), ['c', 'p1', 'p2']);
  });

  testWidgets('the vendor sees exactly the admin plans, and no pay button until payments open', (tester) async {
    await tester.pumpWidget(_page(const VendorPlansView(plans: [twoYears, yearly], status: null, onChoose: null)));
    expect(find.text('1 Year'), findsOneWidget);
    expect(find.text('₹4999 for 1 year'), findsOneWidget);
    expect(find.text('₹8999.50 for 2 years'), findsOneWidget);
    expect(find.byKey(const ValueKey('plans-payment-soon')), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('the card always says the shop stays visible', (tester) async {
    await tester.pumpWidget(_page(const VendorPlansView(plans: [], status: null, onChoose: null)));
    expect(find.textContaining('Your shop stays live and visible'), findsOneWidget);
    expect(find.byKey(const ValueKey('plans-empty')), findsOneWidget);
  });

  testWidgets('a running plan shows its end date, an ended plan says services are off', (tester) async {
    final now = DateTime(2027, 6, 1);
    await tester.pumpWidget(_page(VendorPlansView(plans: const [yearly], status: VendorPlanStatus(planName: '1 Year', endsAt: DateTime(2028, 1, 10)), onChoose: (_) async {}, now: now)));
    expect(find.text('1 Year is active until 10/01/2028'), findsOneWidget);
    expect(find.text('Renew'), findsOneWidget);
    await tester.pumpWidget(_page(VendorPlansView(plans: const [yearly], status: VendorPlanStatus(planName: '1 Year', endsAt: DateTime(2027, 1, 10)), onChoose: (_) async {}, now: now)));
    expect(find.textContaining('Your plan ended on 10/01/2027'), findsOneWidget);
    expect(find.textContaining('your shop stays visible'), findsOneWidget);
    expect(find.text('Choose'), findsOneWidget);
  });

  testWidgets('choosing a plan passes that plan, and an error is shown as a message', (tester) async {
    SubscriptionPlan? chosen;
    await tester.pumpWidget(_page(VendorPlansView(plans: const [yearly], status: null, onChoose: (plan) async => chosen = plan)));
    await tester.tap(find.byKey(const ValueKey('plan-choose-p1')));
    await tester.pump();
    expect(chosen?.id, 'p1');
    await tester.pumpWidget(_page(VendorPlansView(plans: const [yearly], status: null, onChoose: (_) async => throw StateError('No'))));
    await tester.tap(find.byKey(const ValueKey('plan-choose-p1')));
    await tester.pump();
    expect(find.textContaining('No'), findsWidgets);
  });

  testWidgets('admin adds a plan in years; it is saved in months', (tester) async {
    Map<String, dynamic>? saved;
    await _openDialog(tester, null, (fields) => saved = fields);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('plan-name')), ' 3 Years ');
    await tester.enterText(find.byKey(const ValueKey('plan-price')), '12999');
    await tester.enterText(find.byKey(const ValueKey('plan-duration')), '3');
    await tester.tap(find.byKey(const ValueKey('plan-save')));
    await tester.pumpAndSettle();
    expect(saved, {'name': '3 Years', 'price': 12999, 'durationMonths': 36, 'active': true});
  });

  testWidgets('the editor refuses an empty plan', (tester) async {
    Map<String, dynamic>? saved;
    await _openDialog(tester, null, (fields) => saved = fields);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-save')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a plan name'), findsOneWidget);
    expect(find.text('Enter a price above 0'), findsOneWidget);
    expect(saved, isNull);
  });

  testWidgets('editing keeps the plan id and shows months when it is not whole years', (tester) async {
    Map<String, dynamic>? saved;
    await _openDialog(tester, const SubscriptionPlan(id: 'p3', name: 'Half year', price: 2500, durationMonths: 6, active: false), (fields) => saved = fields);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-save')));
    await tester.pumpAndSettle();
    expect(saved, {'planId': 'p3', 'name': 'Half year', 'price': 2500, 'durationMonths': 6, 'active': false});
  });

  testWidgets('admin page lists plans and every service gate is off by default', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminPlansView(
          plans: const [yearly, SubscriptionPlan(id: 'old', name: 'Old', price: 10, durationMonths: 1, active: false)],
          gates: const {},
          onSave: (_) async {},
          onGate: (service, on) async => calls.add('$service=$on'),
        ),
      ),
    ));
    expect(find.text('₹4999 for 1 year'), findsOneWidget);
    expect(find.textContaining('Hidden from vendors'), findsOneWidget);
    for (final service in planServices.keys) {
      expect(tester.widget<SwitchListTile>(find.byKey(ValueKey('plan-gate-$service'))).value, isFalse);
    }
    await tester.tap(find.byKey(const ValueKey('plan-gate-vendorAds')));
    await tester.pump();
    expect(calls, ['vendorAds=true']);
  });
}
