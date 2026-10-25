import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/modules/modules.dart';
import 'package:ecommerce_app/modules/transport/admin_transport.dart';
import 'package:ecommerce_app/modules/transport/transport_module.dart';
import 'package:ecommerce_app/modules/transport/transport_page.dart';
import 'package:ecommerce_app/ui/admin_settings.dart';

Future<Store> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  return store;
}

void main() {
  test('Transport and Services are two modules with their own routes; Transport has its own collection', () {
    expect(homeModules.map((m) => m.id), ['transport', 'services']);
    expect(homeModules.map((m) => m.route).toSet(), hasLength(2));
    expect(transportModule.route, '/transport');
    expect(transportModule.collection, 'transport');
  });

  testWidgets('the Transport box opens its own page, which only says it is coming soon', (tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store();
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('home-box-transport')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(TransportPage), findsOneWidget);
    expect(find.text('త్వరలో వస్తుంది'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('the admin panel has a separate, empty Transport section', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminSettingsPage(store: store))));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings-module-transport')));
    await tester.pump();
    expect(find.byType(AdminTransportSection), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-transport-empty')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
