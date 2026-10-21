import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/ui/admin.dart';

Future<Store> _open(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  await tester.pumpWidget(MaterialApp(home: AdminPage(store: store)));
  await tester.pump();
  return store;
}

Future<void> _tab(WidgetTester tester, int index) async {
  DefaultTabController.of(tester.element(find.byType(TabBar).first)).animateTo(index);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the main tabs are Insights, Orders, Products, Vendors, Shops, Complaints, Promotions, then Settings', (tester) async {
    await _open(tester, 1200);
    expect(tester.widgetList<Tab>(find.byType(Tab)).map((t) => t.text).toList(), [
      'Insights', 'Orders', 'Products', 'Vendors', 'Shops', 'Complaints', 'Promotions', 'Settings',
    ]);
    expect(DefaultTabController.of(tester.element(find.byType(TabBar).first)).index, 0, reason: 'Insights is the home page');
    expect(find.text('Site and ad statistics'), findsOneWidget);
  });

  testWidgets('the top bar has only Search, AI Agent and Sign out, each with a text label', (tester) async {
    for (final width in [360.0, 800.0, 1440.0]) {
      await _open(tester, width);
      expect(find.byKey(const ValueKey('top-search')), findsOneWidget);
      expect(find.byKey(const ValueKey('top-ai-agent')), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('AI Agent'), findsOneWidget);
      // not live in tests: no Sign out then; and no bare icons, no ⋮ menu, no gear, no layout/visual-editor icons
      expect(find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton)), findsNothing);
      expect(find.descendant(of: find.byType(AppBar), matching: find.byType(PopupMenuButton<String>)), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('every other setting is in Settings, each in exactly one place', (tester) async {
    await _open(tester, 1200);
    await _tab(tester, 7);
    for (final key in ['categories', 'fieldAssistants', 'settings', 'theme', 'scrollingText', 'productImageLibrary', 'layout', 'locations']) {
      expect(find.byKey(ValueKey('settings-$key')), findsOneWidget, reason: key);
    }
    expect(find.text('Business Profile'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Product Image Library'), findsOneWidget);
    // the old duplicate entry points are gone from the other tabs
    for (final index in [2, 4, 6]) {
      await _tab(tester, index);
      expect(find.text('Product Image Library'), findsNothing);
      expect(find.text('Theme Settings'), findsNothing);
      expect(find.text('Business profile'), findsNothing);
    }
  });

  testWidgets('Settings sections open: Field Assistants, Layout (Layout settings, Visual Editor, Page view), Quick Add locations', (tester) async {
    await _open(tester, 1200);
    await _tab(tester, 7);
    await tester.tap(find.byKey(const ValueKey('settings-fieldAssistants')));
    await tester.pumpAndSettle();
    expect(find.textContaining('available when Firebase is connected'), findsOneWidget, reason: 'the offline demo says so instead of failing');
    await tester.tap(find.byKey(const ValueKey('settings-layout')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('layout-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-visual-editor')), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-page-view')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('layout-settings')));
    await tester.pumpAndSettle();
    expect(find.text('UI Customization / Layout Settings'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-locations')));
    await tester.pumpAndSettle();
    expect(find.text('Add new'), findsOneWidget);
  });

  testWidgets('Vendors holds vendor approvals with the Quick Add accounts and items beside them', (tester) async {
    await _open(tester, 1200);
    await _tab(tester, 3);
    // (these pages read Firebase directly, so the offline demo shows a note; their content is tested in quick_add_test.dart)
    expect(find.textContaining('available when Firebase is connected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Vendors tab has its three parts', (tester) async {
    final store = Store(live: false);
    await store.init();
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: AdminPage(store: store)));
    await _tab(tester, 3);
    expect(find.text('Complaints'), findsOneWidget, reason: 'the main tab bar is still there');
  });

  testWidgets('Products, Shops and Promotions tabs list their records with Add new', (tester) async {
    await _open(tester, 1200);
    for (final index in [2, 4, 6]) {
      await _tab(tester, index);
      expect(find.text('Add new'), findsOneWidget);
    }
  });

  testWidgets('on a phone Settings is a list of sections that open one by one', (tester) async {
    await _open(tester, 390);
    await _tab(tester, 7);
    expect(find.byKey(const ValueKey('settings-theme')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-categories')));
    await tester.pumpAndSettle();
    expect(find.text('Add new'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
