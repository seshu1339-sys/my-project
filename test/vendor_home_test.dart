import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/modules/transport/transport_page.dart';
import 'package:ecommerce_app/ui/provider_page.dart';
import 'package:ecommerce_app/ui/vendor_home.dart';
import 'package:ecommerce_app/ui/vendor_page.dart';

void main() {
  test('an account is a vendor account, a provider account, a field-staff account, or none yet; never two', () {
    expect(vendorAccountRole(), VendorAccountRole.none);
    expect(vendorAccountRole(vendorApplication: {'status': 'pending'}), VendorAccountRole.vendor);
    expect(vendorAccountRole(vendor: {'status': 'approved'}), VendorAccountRole.vendor);
    expect(vendorAccountRole(quickAccount: {'role': 'vendor'}), VendorAccountRole.vendor);
    expect(vendorAccountRole(quickAccount: {'role': 'staff'}), VendorAccountRole.staff, reason: 'an admin-made Quick Add staff account is staff');
    expect(vendorAccountRole(staff: {'status': 'pending'}), VendorAccountRole.staff);
    expect(vendorAccountRole(providerApplication: {'status': 'pending'}), VendorAccountRole.provider);
    expect(vendorAccountRole(vendorApplication: {}, providerApplication: {}), VendorAccountRole.vendor, reason: 'a vendor record decides');
  });

  Future<void> show(WidgetTester tester, VendorAccountRole role, List<String> opened) => tester.pumpWidget(
    MaterialApp(
      home: VendorHomeView(
        role: role,
        onVendor: () => opened.add('vendor'),
        onServices: () => opened.add('services'),
        onTransport: () => opened.add('transport'),
      ),
    ),
  );

  testWidgets('after sign-in: three options, Vendor, Services and Transport', (tester) async {
    final opened = <String>[];
    await show(tester, VendorAccountRole.none, opened);
    expect(find.byKey(const ValueKey('vendor-home-vendor')), findsOneWidget);
    expect(find.byKey(const ValueKey('vendor-home-services')), findsOneWidget);
    expect(find.byKey(const ValueKey('vendor-home-transport')), findsOneWidget);
    for (final key in ['vendor', 'services', 'transport']) {
      await tester.tap(find.byKey(ValueKey('vendor-home-$key')));
      await tester.pump();
    }
    expect(opened, ['vendor', 'services', 'transport']);
  });

  testWidgets('a vendor account cannot open Services: it is told to register separately', (tester) async {
    final opened = <String>[];
    await show(tester, VendorAccountRole.vendor, opened);
    await tester.tap(find.byKey(const ValueKey('vendor-home-services')));
    await tester.pumpAndSettle();
    expect(find.text(VendorHomeView.servicesBlocked), findsOneWidget);
    expect(opened, isEmpty);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vendor-home-vendor')));
    await tester.tap(find.byKey(const ValueKey('vendor-home-transport')));
    expect(opened, ['vendor', 'transport']);
  });

  testWidgets('a field-staff account opens neither Vendor nor Services: it is told to use a separate account', (tester) async {
    final opened = <String>[];
    await show(tester, VendorAccountRole.staff, opened);
    expect(find.text('Not for this account'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('vendor-home-vendor')));
    await tester.pumpAndSettle();
    expect(find.text(VendorHomeView.staffBlocked), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vendor-home-services')));
    await tester.pumpAndSettle();
    expect(find.text(VendorHomeView.staffBlocked), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
  });

  testWidgets('a service-provider account cannot open Vendor', (tester) async {
    final opened = <String>[];
    await show(tester, VendorAccountRole.provider, opened);
    await tester.tap(find.byKey(const ValueKey('vendor-home-vendor')));
    await tester.pumpAndSettle();
    expect(find.text(VendorHomeView.vendorBlocked), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('the options open their pages: Transport says coming soon, Services the provider flow, Vendor the vendor flow', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(MaterialApp(home: VendorHomePage(store: store)));
    await tester.tap(find.byKey(const ValueKey('vendor-home-transport')));
    await tester.pumpAndSettle();
    expect(find.byType(TransportPage), findsOneWidget);
    expect(find.text(transportComingSoon), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vendor-home-services')));
    await tester.pumpAndSettle();
    expect(find.byType(ServiceProviderPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vendor-home-vendor')));
    await tester.pumpAndSettle();
    expect(find.byType(VendorPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
