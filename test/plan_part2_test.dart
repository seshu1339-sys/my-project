import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/modules/plans/admin_plans.dart';
import 'package:ecommerce_app/modules/plans/plan_badge.dart';
import 'package:ecommerce_app/modules/plans/plan_model.dart';
import 'package:ecommerce_app/ui/app_bottom_ad.dart';
import 'package:ecommerce_app/ui/vendor_section_products.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Part 2 (owner, 13 Nov 2026): plan kinds, the plan badge, the km dropdown, the tall bottom ad on the plans page, the Upgrade button,
// the catalog search and the item that is not in the catalog.
class _Store extends Store {
  _Store() : super(live: true);
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    calls.add((name, data));
    return {'status': 'approved', 'docId': 'p1'};
  }
}

void main() {
  final now = DateTime(2027, 1, 10);

  test('Platinum and Diamond are plan kinds with 4 and 6 boxes; Gold has 2', () {
    expect(planTiers.keys, containsAll(['silver', 'gold', 'platinum', 'diamond', 'premium']));
    expect([defaultOfferBoxes['gold'], defaultOfferBoxes['platinum'], defaultOfferBoxes['diamond']], [2, 4, 6]);
    expect(const SubscriptionPlan(id: 'a', name: 'A', price: 1, durationMonths: 1, active: true, tier: 'diamond').offerBoxes, 6);
    expect(planRadiusChoices, [5, 10, 25, 50, 100]);
  });

  testWidgets('the badge: Free Plan with Upgrade, or the plan kind with its end date', (tester) async {
    var tapped = 0;
    Future<void> show(VendorPlanStatus? status) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: VendorPlanBadgeView(status: status, now: now, onUpgrade: () => tapped++))));
    await show(null);
    expect(find.text('Free Plan'), findsOneWidget);
    await tester.tap(find.text('Upgrade'));
    expect(tapped, 1);
    await show(VendorPlanStatus(planName: '1 Year', tier: 'gold', endsAt: DateTime(2027, 3, 12)));
    expect(find.text('Gold Plan · until 12/03/2027'), findsOneWidget);
    expect(find.text('Change plan'), findsOneWidget);
    await show(VendorPlanStatus(planName: '1 Year', tier: 'gold', endsAt: DateTime(2026, 12, 1)));
    expect(find.text('Free Plan'), findsOneWidget, reason: 'an ended plan is the free plan again');
  });

  testWidgets('the plan editor: Diamond gives 6 boxes and the km comes from the dropdown', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => saved = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const PlanEditorDialog()),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('plan-name')), 'Big');
    await tester.enterText(find.byKey(const ValueKey('plan-price')), '999');
    await tester.tap(find.byKey(const ValueKey('plan-tier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diamond').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('plan-radius')));
    await tester.tap(find.byKey(const ValueKey('plan-radius')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('100 km').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('plan-save')));
    await tester.tap(find.byKey(const ValueKey('plan-save')));
    await tester.pumpAndSettle();
    expect([saved?['tier'], saved?['offerBoxes'], saved?['radiusKm']], ['diamond', 6, 100]);
  });

  testWidgets('the bottom ad grows to about 30% of the screen only while the flag is on', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _Store();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: AppBottomAd(store: store, uid: 'v1', staff: true)))));
    final box = find.byKey(const ValueKey('app-bottom-ad-empty'));
    expect(tester.getSize(box).height, lessThan(80));
    appBottomAdTall.value = true;
    await tester.pump();
    expect(tester.getSize(box).height, closeTo(1000 * appBottomAdTallShare - 12, 1));
    appBottomAdTall.value = false;
    await tester.pump();
    expect(tester.getSize(box).height, lessThan(80));
  });

  testWidgets('full items: an Upgrade button; the catalog search finds an item in any category; a missing item is named by the vendor', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _Store();
    store.catalog['categories'] = const [Entry('cat-veg', {'name': 'Vegetables', 'order': 1, 'active': true})];
    store.catalog['productImageLibrary'] = const [
      Entry('lib-tomato', {'name': 'Tomato', 'categoryId': 'cat-veg', 'imageUrl': '', 'active': true, 'order': 1, 'tags': 'thakkali'}),
    ];
    var upgrades = 0;
    Widget section((int, int, bool) preview) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: VendorAddProductSection(store: store, uid: 'v1', preview: preview, onUpgrade: () => upgrades++))),
    );
    await tester.pumpWidget(section((2, 2, true)));
    await tester.tap(find.byKey(const ValueKey('vendor-item-upgrade')));
    expect(upgrades, 1);

    await tester.pumpWidget(section((0, 2, true)));
    await tester.enterText(find.byKey(const ValueKey('vendor-item-search')), 'thakkali');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vendor-library-item-lib-tomato')), findsOneWidget, reason: 'found by its keyword without choosing a category');
    await tester.enterText(find.byKey(const ValueKey('vendor-item-search')), '');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vendor-item-category-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vegetables').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vendor-item-missing')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('vendor-custom-name')), 'Clay lamp');
    await tester.enterText(find.byKey(const ValueKey('vendor-item-price')), '40');
    await tester.tap(find.byKey(const ValueKey('vendor-item-save')));
    await tester.pumpAndSettle();
    expect(store.calls.single.$2['changes'], {'customName': 'Clay lamp', 'categoryId': 'cat-veg', 'unitType': 'kg', 'quantity': 1, 'price': 40.0});
    expect(find.textContaining('own photo'), findsWidgets);
  });
}
