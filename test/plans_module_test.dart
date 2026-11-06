import 'package:ecommerce_app/domain/vendor_items.dart';
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
    expect(saved, {'name': '3 Years', 'price': 12999, 'durationMonths': 36, 'itemLimit': 10, 'tier': 'premium', 'extraPhotos': 10, 'radiusKm': 25, 'offerBoxes': 5, 'active': true});
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
    expect(saved, {'planId': 'p3', 'name': 'Half year', 'price': 2500, 'durationMonths': 6, 'itemLimit': 10, 'tier': 'premium', 'extraPhotos': 10, 'radiusKm': 25, 'offerBoxes': 5, 'active': false});
  });

  testWidgets('admin page lists plans and every service gate is off by default', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    expect(find.text("Premium • ₹4999 for 1 year • 10 extra photos • reach 25 km • 5 Today's Offers boxes • 10 items"), findsOneWidget);
    expect(find.textContaining('Hidden from vendors'), findsOneWidget);
    for (final service in planServices.keys) {
      expect(tester.widget<SwitchListTile>(find.byKey(ValueKey('plan-gate-$service'))).value, isFalse);
    }
    await tester.tap(find.byKey(const ValueKey('plan-gate-vendorAds')));
    await tester.pump();
    expect(calls, ['vendorAds=true']);
  });

  test('the item limit in the vendor app follows the same rule as the server', () {
    final now = DateTime(2027, 6, 1);
    expect(vendorItemLimitNow(null, now: now), 2);
    expect(vendorItemLimitNow(null, planGates: {'freeItemLimit': 3}, now: now), 3);
    expect(vendorItemLimitNow({'itemLimit': 5}, planGates: {'freeItemLimit': 3}, now: now), 5);
    expect(vendorItemLimitNow(null, planEndsAt: DateTime(2028), planItemLimit: 10, now: now), 10);
    expect(vendorItemLimitNow(null, planEndsAt: DateTime(2028), now: now), 10, reason: 'a plan made before limits');
    expect(vendorItemLimitNow(null, planEndsAt: DateTime(2027), planItemLimit: 10, now: now), 2, reason: 'the plan ended');
    expect(vendorItemLimitNow({'itemLimit': 20}, planEndsAt: DateTime(2028), planItemLimit: 10, now: now), 20);
  });

  testWidgets('Free and Premium side by side: what each gives, the price, and which is the vendor\'s plan', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const premium = SubscriptionPlan(id: 'pr', name: 'Premium', price: 2000, durationMonths: 36, active: true, itemLimit: 10);
    await tester.pumpWidget(_page(const VendorPlansView(plans: [premium], status: null, onChoose: null, freeItems: 2)));
    final free = find.byKey(const ValueKey('plan-compare-free'));
    final paid = find.byKey(const ValueKey('plan-pr'));
    expect(find.descendant(of: free, matching: find.text('Free for life')), findsOneWidget);
    expect(find.descendant(of: free, matching: find.text('1 shop photo + 2 extra photos')), findsOneWidget);
    expect(find.descendant(of: free, matching: find.text('Your plan')), findsOneWidget);
    expect(find.descendant(of: paid, matching: find.text('₹2000 for 3 years')), findsOneWidget);
    expect(find.descendant(of: paid, matching: find.text('1 shop photo + 10 extra photos')), findsOneWidget);
    expect(find.descendant(of: paid, matching: find.text('Customers within 25 km see your ad and offer')), findsOneWidget);
    expect(find.descendant(of: paid, matching: find.text("Your box in Today's Offers")), findsOneWidget);
    expect(tester.getTopLeft(free).dy, tester.getTopLeft(paid).dy, reason: 'side by side on a wide screen');
    // No pressure: nothing shouts or counts down.
    for (final word in ['Hurry', 'Upgrade now', 'Limited time', 'Last chance', '!']) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
    await tester.pumpWidget(_page(VendorPlansView(plans: const [premium], status: VendorPlanStatus(planName: 'Premium', endsAt: DateTime(2029, 11, 6)), onChoose: null, now: DateTime(2027, 1, 1))));
    expect(find.text('Premium is active until 06/11/2029'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('plan-pr')), matching: find.text('Your plan')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('plan-compare-free')), matching: find.text('Your plan')), findsNothing);
  });

  testWidgets('on a narrow phone Free and Premium stack, with no overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_page(const VendorPlansView(plans: [yearly, twoYears], status: null, onChoose: null)));
    final free = tester.getTopLeft(find.byKey(const ValueKey('plan-compare-free')));
    final first = tester.getTopLeft(find.byKey(const ValueKey('plan-p1')));
    expect(first.dy, greaterThan(free.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin: start a plan by Vendor ID, stop a running one, change the free number, see each end date', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <String>[];
    const premium = SubscriptionPlan(id: 'pr', name: 'Premium', price: 2000, durationMonths: 36, active: true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminPlansView(
          plans: const [premium],
          gates: const {'freeItemLimit': 2},
          statuses: [
            VendorPlanStatus(uid: 'v1', vendorName: 'Ramu Kirana', vendorCode: 'VEN-NRPM-116-325', planName: 'Premium', endsAt: DateTime(2029, 11, 6), byAdmin: true),
            VendorPlanStatus(uid: 'v2', vendorName: 'Old Shop', vendorCode: 'VEN-NRPM-116-001', planName: 'Premium', endsAt: DateTime(2026, 1, 1)),
          ],
          now: DateTime(2027, 1, 1),
          onSave: (_) async {},
          onGate: (_, _) async {},
          onFreeLimit: (n) async => calls.add('free=$n'),
          onActivate: (code, planId) async => calls.add('start $code $planId'),
          onStop: (uid) async => calls.add('stop $uid'),
        ),
      ),
    ));
    expect(find.text('Ramu Kirana • VEN-NRPM-116-325'), findsOneWidget);
    expect(find.text('Premium • until 06/11/2029 • 10 items • by admin'), findsOneWidget);
    expect(find.text('Premium • ended 01/01/2026 • 10 items'), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-stop-v2')), findsNothing, reason: 'an ended plan cannot be stopped');

    await tester.tap(find.byKey(const ValueKey('plan-activate')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('plan-activate-code')), 'ven-nrpm-116-999');
    await tester.tap(find.byKey(const ValueKey('plan-activate-save')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('plan-stop-v1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-stop-confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('plan-free-limit-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('plan-number')), '3');
    await tester.tap(find.byKey(const ValueKey('plan-number-save')));
    await tester.pumpAndSettle();

    expect(calls, ['start VEN-NRPM-116-999 pr', 'stop v1', 'free=3']);
  });

  testWidgets('the plan editor saves the item limit and refuses 0', (tester) async {
    Map<String, dynamic>? saved;
    await _openDialog(tester, const SubscriptionPlan(id: 'pr', name: 'Premium', price: 2000, durationMonths: 36, active: true), (fields) => saved = fields);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('plan-item-limit')), '0');
    await tester.tap(find.byKey(const ValueKey('plan-save')));
    await tester.pumpAndSettle();
    expect(find.text('Enter 1 to 100'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('plan-item-limit')), '12');
    await tester.tap(find.byKey(const ValueKey('plan-save')));
    await tester.pumpAndSettle();
    expect(saved?['itemLimit'], 12);
    expect(saved?['durationMonths'], 36);
  });
}
