import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/modules/transport/transport_page.dart';
import 'package:ecommerce_app/ui/provider_page.dart';
import 'package:ecommerce_app/ui/vendor_home.dart';
import 'package:ecommerce_app/ui/vendor_page.dart';

/// The vendor app's store with the server faked: which login it is signed in as, and what was asked.
class RoleTestStore extends Store {
  RoleTestStore() : super(live: false);
  final asked = <String>[];
  String? refuse;

  @override
  Future<void> chooseVendorRole(String role) async {
    asked.add('choose:$role');
    if (refuse == role) {
      roleBlock = 'Your $role account is blocked. Contact LOCAMARKET support.';
      blockedRole = role;
      choosingVendorRole = true;
      notifyListeners();
      throw StateError('blocked');
    }
    choosingVendorRole = false;
    sessionRole = role;
    notifyListeners();
  }

  @override
  Future<void> logout() async => asked.add('logout');
}

void main() {
  test('the vendor app holds the vendor and the service-provider login of an email; the other apps one role each', () {
    expect((Store()..appRole = 'vendor').appRoles, ['vendor', 'provider']);
    expect((Store()..appRole = 'staff').appRoles, ['staff']);
    expect((Store()..appRole = 'admin').appRoles, ['admin']);
    expect(Store().appRoles, ['user']);
  });

  Future<void> show(WidgetTester tester, String signedInAs, List<String> did) => tester.pumpWidget(
    MaterialApp(
      home: VendorHomeView(
        signedInAs: signedInAs,
        email: 'same@example.com',
        onVendor: () => did.add('vendor'),
        onServices: () => did.add('services'),
        onTransport: () => did.add('transport'),
        onSwitch: (to) => did.add('switch:$to'),
      ),
    ),
  );

  testWidgets('after sign-in: three options, Vendor, Services and Transport, all of which open', (tester) async {
    final did = <String>[];
    await show(tester, 'vendor', did);
    expect(find.byKey(const ValueKey('vendor-home-vendor')), findsOneWidget);
    expect(find.byKey(const ValueKey('vendor-home-services')), findsOneWidget);
    expect(find.byKey(const ValueKey('vendor-home-transport')), findsOneWidget);
    for (final key in ['vendor', 'services', 'transport']) {
      await tester.tap(find.byKey(ValueKey('vendor-home-$key')));
      await tester.pump();
    }
    expect(did, ['vendor', 'services', 'transport']);
    expect(find.textContaining('different email'), findsNothing, reason: 'the same email may be both');
  });

  testWidgets('it shows which login it is signed in as, and Switch moves to the other one', (tester) async {
    final did = <String>[];
    await show(tester, 'vendor', did);
    expect(find.text('Signed in as Vendor (same@example.com)'), findsOneWidget);
    expect(find.text('Switch to your service-provider account'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('vendor-switch-role')));
    expect(did, ['switch:provider']);

    did.clear();
    await show(tester, 'provider', did);
    expect(find.text('Signed in as Service provider (same@example.com)'), findsOneWidget);
    expect(find.text('Switch to your vendor account'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('vendor-switch-role')));
    expect(did, ['switch:vendor']);
  });

  testWidgets('first sign-in: "Continue as" Vendor or Service provider', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = RoleTestStore()..choosingVendorRole = true;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: VendorRoleChooser(store: store)))));
    expect(find.text('Continue as'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('choose-provider')));
    await tester.pumpAndSettle();
    expect(store.asked, ['choose:provider']);
    expect(store.sessionRole, 'provider');
  });

  testWidgets('a blocked vendor login says so, and the service-provider login still works', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = RoleTestStore()
      ..choosingVendorRole = true
      ..refuse = 'vendor';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ListenableBuilder(listenable: store, builder: (context, child) => VendorRoleChooser(store: store))))));
    await tester.tap(find.byKey(const ValueKey('choose-vendor')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('role-block')), findsOneWidget);
    expect(find.textContaining('vendor account is blocked'), findsOneWidget);
    expect(find.text('This account is blocked'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('choose-provider')));
    await tester.pumpAndSettle();
    expect(store.asked, ['choose:vendor', 'choose:provider']);
    expect(store.sessionRole, 'provider');
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
