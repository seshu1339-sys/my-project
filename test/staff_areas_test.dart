import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/modules/staffareas/admin_staff_areas.dart';
import 'package:ecommerce_app/modules/staffareas/staffareas_module.dart';
import 'package:ecommerce_app/services/report_export.dart';

const _bazaar = StaffArea(id: 'a1', name: 'Narsipatnam Main Bazaar', town: 'Narsipatnam', latitude: 17.668, longitude: 82.612, radiusKm: 1, status: 'free');
final _t = DateTime.utc(2026, 11, 6, 6);
const _taken = StaffArea(id: 'a2', name: 'Bus Stand', town: 'Narsipatnam', latitude: 17.690, longitude: 82.612, radiusKm: 1, status: 'booked');

Future<Store> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  return store;
}

void _phone(WidgetTester tester, [Size size = const Size(420, 1400)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('claim: green free and red booked; Terms needed; far away is refused; inside it is claimed', (tester) async {
    _phone(tester);
    final store = await _store();
    var at = const LatLng(17.75, 82.70); // far away
    final sent = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StaffAreaClaimPage(
          store: store,
          areas: Stream.value(const [_bazaar, _taken]),
          locate: () async => at,
          onClaim: (data) async {
            sent.add(data);
            return {'status': 'pending'};
          },
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Narsipatnam Main Bazaar'), findsWidgets);
    expect(find.textContaining('Booked • 1 km'), findsOneWidget);
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('staff-area-a2'))).enabled, isFalse, reason: 'a booked area cannot be chosen');

    await tester.tap(find.byKey(const ValueKey('staff-area-a1')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('staff-area-claim')));
    await tester.tap(find.byKey(const ValueKey('staff-area-claim')));
    await tester.pump();
    expect(find.textContaining('Tick "I accept the Terms & Conditions"'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byKey(const ValueKey('staff-area-terms')), matching: find.byType(Checkbox)));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('staff-area-claim')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Please go to this area to register it'), findsOneWidget);
    expect(sent, isEmpty);

    at = const LatLng(17.6682, 82.6122); // standing inside
    await tester.tap(find.byKey(const ValueKey('staff-area-claim')));
    await tester.pumpAndSettle();
    expect(sent.single, {'areaId': 'a1', 'latitude': 17.6682, 'longitude': 82.6122, 'termsAccepted': true});
    expect(find.textContaining('held for you until the admin approves you'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('dashboard: the monthly targets with progress, the week\'s rate days, missed days, the shops with a tick, the warning', (tester) async {
    _phone(tester);
    final today = AreaToday.fromData({
      'area': {'id': 'a1', 'name': 'Narsipatnam Main Bazaar', 'town': 'Narsipatnam', 'latitude': 17.668, 'longitude': 82.612, 'radiusKm': 1, 'status': 'booked'},
      'photos': {'done': 60, 'target': 100}, 'vendors': {'done': 10, 'target': 10}, 'paidVendors': {'done': 1, 'target': 2}, 'rateDays': {'done': 3, 'target': 4},
      'todayUpdates': 5, 'staffCount': 5, 'vendorCount': 2, 'missedThisMonth': 6, 'maxMissedDays': 7,
      'warning': 'One more and your staff ID stops',
      'shops': [
        {'id': 's1', 'name': 'Lakshmi Kirana', 'latitude': 17.6685, 'longitude': 82.6125, 'offerToday': true},
        {'id': 's2', 'name': 'Ravi Fruits', 'latitude': 17.6675, 'longitude': 82.6115, 'offerToday': false},
      ],
    });
    var added = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: StaffAreaDashboardView(today: today, showMap: false, onAddOffer: () => added++)))));
    expect(find.text('My area: Narsipatnam Main Bazaar'), findsOneWidget);
    expect(find.text('Live photos: 60 / 100'), findsOneWidget);
    expect(find.text('New vendors: 10 / 10 ✓'), findsOneWidget);
    expect(find.text('New Premium (paid) vendors: 1 / 2'), findsOneWidget);
    expect(find.text('The month counts only when every target is complete.'), findsOneWidget);
    expect(find.text('Rate update days this week: 3 / 4'), findsOneWidget);
    expect(find.text('Missed days this month: 6 / 7'), findsOneWidget);
    expect(find.byKey(const ValueKey('staff-area-warning')), findsOneWidget);
    expect(find.text('Has an offer today'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('staff-area-add-offer')));
    expect(added, 1);
  });

  testWidgets('dashboard with no area: choose one', (tester) async {
    var chose = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StaffAreaDashboardView(today: AreaToday.fromData({'target': 20}), onChoose: () => chose++))));
    await tester.tap(find.byKey(const ValueKey('staff-area-choose')));
    expect(chose, 1);
    expect(find.byKey(const ValueKey('staff-area-add-offer')), findsNothing);
  });

  testWidgets("a rate update: a shop of my area, a LIVE photo standing there (fake GPS or far away refused), the item, a lower price", (tester) async {
    _phone(tester);
    final store = await _store();
    Map<String, dynamic>? saved;
    var shot = LivePhoto(id: 'p1', latitude: 17.70, longitude: 82.70, accuracy: 10, mocked: false, takenAt: _t);
    await tester.pumpWidget(MaterialApp(
      home: StaffOfferForm(
        store: store,
        shops: const [AreaShop(id: 's1', name: 'Lakshmi Kirana', latitude: 17.6685, longitude: 82.6125, offerToday: false)],
        items: () async => const [Entry('lib-tomato', {'name': 'Tomato', 'imageUrl': ''}), Entry('lib-onion', {'name': 'Onion', 'imageUrl': ''})],
        now: () => DateTime.utc(2026, 11, 6, 6),
        capture: () async => shot,
        onSave: (data) async {
          saved = data;
          return {'offerId': 'o1'};
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('staff-offer-shop')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lakshmi Kirana').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('staff-offer-photo')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Go to the shop'), findsOneWidget, reason: 'taken from far away');
    shot = LivePhoto(id: 'p2', latitude: 17.6686, longitude: 82.6126, accuracy: 10, mocked: true, takenAt: _t);
    await tester.tap(find.byKey(const ValueKey('staff-offer-photo')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fake GPS (a mock location app)'), findsOneWidget);
    shot = LivePhoto(id: 'p3', latitude: 17.6686, longitude: 82.6126, accuracy: 10, mocked: false, takenAt: _t);
    await tester.tap(find.byKey(const ValueKey('staff-offer-photo')));
    await tester.pumpAndSettle();
    expect(find.text('Live photo taken at the shop'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('staff-offer-item-search')), 'tom');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('staff-offer-item-lib-tomato')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('staff-offer-regular')), '32');
    await tester.enterText(find.byKey(const ValueKey('staff-offer-price')), '40');
    await tester.ensureVisible(find.byKey(const ValueKey('staff-offer-save')));
    await tester.tap(find.byKey(const ValueKey('staff-offer-save')));
    await tester.pump();
    expect(find.text('Must be lower than the normal price'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('staff-offer-price')), '25');
    await tester.ensureVisible(find.byKey(const ValueKey('staff-offer-save')));
    await tester.tap(find.byKey(const ValueKey('staff-offer-save')));
    await tester.pumpAndSettle();
    expect(saved?['shopId'], 's1');
    expect(saved?['offerPrice'], 25);
    expect(saved?.containsKey('validDate'), isFalse, reason: 'staff choose no dates: always the rate of today');
    expect(find.byKey(const ValueKey('staff-offer-date')), findsNothing);
    expect((saved?['photo'] as Map)['id'], 'p3');
    expect((saved?['photo'] as Map)['mocked'], false);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('the Terms show the admin\'s text and the current numbers; the defaults name every rule', (tester) async {
    // The cell rules (owner, 13 Nov 2026) made the Terms longer: a tall screen shows them all.
    _phone(tester, const Size(900, 2400));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StaffTermsView(settings: StaffAreaSettings(rateDaysPerWeek: 5, maxMissedDays: 6)))));
    expect(find.textContaining('no fixed salary'), findsOneWidget);
    expect(find.textContaining('rate updates on at least 5 days a week'), findsOneWidget);
    expect(find.textContaining('the account stops at 6 missed days'), findsOneWidget);
    for (final rule in ['no fixed salary', 'One area per staff', "Today's Offers", 'live camera photo', 'monthly targets', 'deactivated automatically', 'change these rules']) {
      expect(defaultStaffTerms.toLowerCase().contains(rule.toLowerCase()), isTrue, reason: rule);
    }
  });

  testWidgets('admin settings: monthly targets, rate days a week, missed days and Terms are checked and saved', (tester) async {
    _phone(tester, const Size(900, 1600));
    Map<String, dynamic>? saved;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StaffAreaSettingsForm(settings: const StaffAreaSettings(), onSave: (f) async => saved = f))));
    await tester.enterText(find.byKey(const ValueKey('staff-area-rate-days')), '8');
    await tester.ensureVisible(find.byKey(const ValueKey('staff-area-settings-save')));
    await tester.tap(find.byKey(const ValueKey('staff-area-settings-save')));
    await tester.pump();
    expect(find.text('Enter 1 to 7 rate update days a week.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('staff-area-rate-days')), '4');
    await tester.enterText(find.byKey(const ValueKey('staff-target-monthly-Photo')), '120');
    await tester.enterText(find.byKey(const ValueKey('staff-area-max-missed')), '7');
    await tester.ensureVisible(find.byKey(const ValueKey('staff-area-settings-save')));
    await tester.tap(find.byKey(const ValueKey('staff-area-settings-save')));
    await tester.pumpAndSettle();
    expect(saved?['monthlyPhotoTarget'], 120);
    expect(saved?['rateDaysPerWeek'], 4);
    expect(saved?['maxMissedDays'], 7);
    expect(saved?['monthlyVendorTarget'], 10);
    expect(saved?['monthlyPaidVendorTarget'], 2);
    expect(saved?['terms'], defaultStaffTerms);
    // Daily and weekly targets for every measure, 0 (no target) until the admin types one (owner, 7 Nov 2026).
    for (final p in ['daily', 'weekly']) {
      for (final m in ['Photo', 'Shop', 'Vendor', 'PaidVendor']) {
        expect(saved?['$p${m}Target'], 0, reason: '$p $m');
      }
    }
    expect(saved?['monthlyShopTarget'], 0);
  });

  testWidgets('the staff dashboard shows the day and week targets the admin set, and shops visited', (tester) async {
    _phone(tester, const Size(500, 2400));
    final today = AreaToday.fromData({
      'area': {'id': 'a1', 'name': 'Main Bazaar', 'town': 'Narsipatnam', 'latitude': 17.668, 'longitude': 82.612, 'radiusKm': 1, 'status': 'booked'},
      'missedThisMonth': 0, 'maxMissedDays': 7,
      'targets': {
        'daily': {'photos': {'done': 2, 'target': 5}, 'shops': {'done': 2, 'target': 3}, 'vendors': {'done': 0, 'target': 0}, 'paidVendors': {'done': 0, 'target': 0}},
        'weekly': {'photos': {'done': 0, 'target': 0}, 'shops': {'done': 0, 'target': 0}, 'vendors': {'done': 1, 'target': 2}, 'paidVendors': {'done': 0, 'target': 0}},
        'monthly': {'photos': {'done': 1, 'target': 1}, 'shops': {'done': 4, 'target': 10}, 'vendors': {'done': 1, 'target': 1}, 'paidVendors': {'done': 0, 'target': 0}},
      },
      'photos': {'done': 1, 'target': 1}, 'vendors': {'done': 1, 'target': 1}, 'paidVendors': {'done': 0, 'target': 0},
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: StaffAreaDashboardView(today: today, showMap: false)))));
    expect(find.text('Live photos: 2 / 5'), findsOneWidget);
    expect(find.text('Shops visited: 2 / 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('staff-target-daily-Vendor')), findsNothing, reason: 'no target for that');
    expect(find.text('New vendors: 1 / 2'), findsOneWidget);
    expect(find.text('Shops visited: 4 / 10'), findsOneWidget);
    expect(find.textContaining('The month counts only when'), findsOneWidget, reason: 'shops visited this month is not complete');
  });

  testWidgets('admin town radius: 1 / 2 / 3 / 5 km or another', (tester) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(onPressed: () async => saved = await showDialog(context: context, builder: (_) => const StaffTownDialog()), child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('staff-town-name')), 'Visakhapatnam');
    await tester.tap(find.byKey(const ValueKey('staff-town-radius-custom')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('staff-town-radius-value')), '1.5');
    await tester.tap(find.byKey(const ValueKey('staff-town-save')));
    await tester.pumpAndSettle();
    expect(saved, {'town': 'Visakhapatnam', 'radiusKm': 1.5});
  });

  testWidgets('admin reports: per staff (targets, complete or not) and per town, and the Excel download', (tester) async {
    _phone(tester, const Size(1800, 1400));
    List<ReportTable>? downloaded;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StaffAreaReportTab(
          load: (month) async => {
            'month': month,
            'staff': [
              {'staffCode': 'STF-NRPM-116-482', 'name': 'Kiran', 'phone': '98765', 'status': 'active', 'area': 'Main Bazaar', 'town': 'Narsipatnam', 'photos': 120, 'vendorsLinked': 11, 'paidVendorsLinked': 2, 'providersLinked': 1, 'monthComplete': true, 'daysWorked': 22, 'missedDays': 1, 'staffOffers': 300, 'vendorOffers': 120},
            ],
            'towns': [
              {'town': 'Narsipatnam', 'total': 6, 'free': 3, 'booked': 2, 'pending': 1, 'deactivatedThisMonth': 1},
            ],
          },
          download: (name, tables) async => downloaded = tables,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('STF-NRPM-116-482'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('staff-area-report-export')));
    await tester.pumpAndSettle();
    expect(downloaded, hasLength(2));
    expect(downloaded!.first.rows.single.sublist(6, 11), [120, 11, 2, 1, 'Yes']);
    expect(downloaded!.last.rows.single, ['Narsipatnam', 6, 3, 2, 1, 1]);
  });
}
