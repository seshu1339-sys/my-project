import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/modules/module_admin.dart';
import 'package:ecommerce_app/ui/admin.dart';
import 'package:ecommerce_app/ui/admin_groups.dart';
import 'package:ecommerce_app/ui/admin_settings.dart';

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

int _group(String id) => adminGroups.indexWhere((g) => g.id == id);

// Settings is the last tab: the index of every section, under the group names.
Future<void> _settingsTab(WidgetTester tester) => _tab(tester, DefaultTabController.of(tester.element(find.byType(TabBar).first)).length - 1);

Future<void> _tapSetting(WidgetTester tester, String key) async {
  final tile = find.byKey(ValueKey('settings-$key'));
  await tester.scrollUntilVisible(tile, 200, scrollable: find.descendant(of: find.byType(AdminSettingsPage), matching: find.byType(Scrollable)).first);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _item(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('group-item-$id')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('six groups: Business, Vendors & Shops, Services, Staff, Ads & Offers, Settings; Business opens on Insights', (tester) async {
    await _open(tester, 1200);
    expect(tester.widgetList<Tab>(find.byType(Tab)).map((t) => t.text).toList(), ['Business', 'Vendors & Shops', 'Services', 'Staff', 'Ads & Offers', 'Settings']);
    expect(DefaultTabController.of(tester.element(find.byType(TabBar).first)).index, 0, reason: 'Business (Insights) is the home page');
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

  test('nothing was taken away: every earlier tab and every Settings section is in exactly one group', () {
    final placed = [for (final g in adminGroups) for (final i in g.items) i.id];
    expect(placed.toSet().length, placed.length, reason: 'no page in two groups');
    for (final tab in ['Insights', 'Orders', 'Products', 'Vendors', 'Shops', 'Complaints', 'Promotions', for (final m in moduleAdminTabs) m.title]) {
      expect(placed, contains(tab), reason: tab);
    }
    for (final hit in adminSettingsIndex().where((h) => !h.isField)) {
      expect(adminGroupOf(hit.sectionKey), isNotNull, reason: '${hit.sectionKey} is in a group');
    }
    expect(adminGroupOf('serviceProviders'), 'Services');
    expect(adminGroupOf('ratings'), 'Vendors & Shops');
    expect(adminGroupOf('staffWork'), 'Staff');
    expect(adminGroupOf('Promotions'), 'Ads & Offers');
    expect(adminGroupOf('theme'), 'Settings');
  });

  testWidgets('Settings is the index of every section, under the group names, each once', (tester) async {
    await _open(tester, 1200);
    // A tall window, so the whole index is built at once.
    tester.view.physicalSize = const Size(1200, 9000);
    await tester.pumpAndSettle();
    await _settingsTab(tester);
    for (final heading in ['Business', 'Vendors & Shops', 'Services', 'Staff', 'Ads & Offers', 'Settings']) {
      expect(find.text(heading), findsWidgets, reason: heading);
    }
    for (final key in ['categories', 'fieldAssistants', 'settings', 'theme', 'animations', 'scrollingText', 'productImageLibrary', 'layout', 'locations']) {
      expect(find.byKey(ValueKey('settings-$key')), findsOneWidget, reason: key);
    }
  });

  testWidgets('Settings sections open: Field Assistants, Layout (Layout settings, Visual Editor, Page view), Quick Add locations', (tester) async {
    await _open(tester, 1200);
    await _settingsTab(tester);
    await _tapSetting(tester, 'fieldAssistants');
    expect(find.textContaining('available when Firebase is connected'), findsOneWidget, reason: 'the offline demo says so instead of failing');
    await _tapSetting(tester, 'layout');
    expect(find.byKey(const ValueKey('layout-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-visual-editor')), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-page-view')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('layout-settings')));
    await tester.pumpAndSettle();
    expect(find.text('UI Customization / Layout Settings'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tapSetting(tester, 'locations');
    expect(find.text('Add new'), findsOneWidget);
  });

  testWidgets('Vendors & Shops opens on the vendor approvals; Complaints, Ratings and Reports are beside them', (tester) async {
    await _open(tester, 1200);
    await _tab(tester, _group('vendors'));
    // (these pages read Firebase directly, so the offline demo shows a note; their content is tested in quick_add_test.dart)
    expect(find.textContaining('available when Firebase is connected'), findsOneWidget);
    for (final id in ['Complaints', 'ratings', 'reports', 'blockList', 'Products', 'Shops']) {
      expect(find.byKey(ValueKey('group-item-$id')), findsOneWidget, reason: id);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('service providers are in one place: Services; the Vendors tab points there', (tester) async {
    await _open(tester, 1200);
    await _tab(tester, _group('services'));
    await _item(tester, 'serviceProviders');
    expect(find.textContaining('available when Firebase is connected'), findsOneWidget);
    // (The Vendors tab's own "Service providers" part now only points here; it needs Firebase, so the demo cannot open it.)
    expect(adminGroups.expand((g) => g.items).where((i) => i.kind == AdminItemKind.providers).length, 1);
  });

  testWidgets('Products, Shops and Promotions list their records with Add new', (tester) async {
    await _open(tester, 1200);
    await _tab(tester, _group('vendors'));
    for (final id in ['Products', 'Shops']) {
      await _item(tester, id);
      expect(find.text('Add new'), findsOneWidget, reason: id);
    }
    await _tab(tester, _group('ads'));
    expect(find.text('Add new'), findsOneWidget, reason: 'Ads & Offers opens on Promotions');
  });

  testWidgets('on a phone a group lists its pages; Settings is a list of sections that open one by one', (tester) async {
    await _open(tester, 390);
    await _tab(tester, _group('staff'));
    expect(find.byKey(const ValueKey('group-item-staffWork')), findsOneWidget, reason: 'a phone lists the group pages');
    await _settingsTab(tester);
    // A tall phone, so the whole index is built at once.
    tester.view.physicalSize = const Size(390, 9000);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-theme')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-categories')));
    await tester.pumpAndSettle();
    expect(find.text('Add new'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
