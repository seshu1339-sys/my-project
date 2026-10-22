import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/admin.dart';

Future<Store> _open(WidgetTester tester, {bool withoutTheme = false}) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  if (withoutTheme) store.catalog['settings'] = [for (final e in store.catalog['settings']!) if (e.id != 'theme') e];
  await tester.pumpWidget(MaterialApp(home: AdminPage(store: store)));
  await tester.pump();
  DefaultTabController.of(tester.element(find.byType(TabBar).first)).animateTo(7);
  await tester.pumpAndSettle();
  return store;
}

Future<void> _section(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey('settings-$key')));
  // the Scrolling Text page shows the moving line itself, which never stops, so wait a moment instead of for stillness
  if (key == 'scrollingText') {
    await tester.pump(const Duration(milliseconds: 600));
  } else {
    await tester.pumpAndSettle();
  }
}

Future<void> _scrollToSave(WidgetTester tester) => tester.scrollUntilVisible(
  find.text('Save changes'),
  300,
  scrollable: find.descendant(of: find.byType(EntryEditor), matching: find.byType(Scrollable)).first,
);

void main() {
  testWidgets('Business Profile opens as one form: no list, no "Add new"', (tester) async {
    await _open(tester);
    await _section(tester, 'settings');
    expect(find.text('Add new'), findsNothing);
    expect(find.textContaining('business profiles'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Business name'), findsOneWidget);
    await _scrollToSave(tester);
    expect(find.text('Save changes'), findsOneWidget);
    // the old per-record title bar is not there either
    expect(find.textContaining('Edit '), findsNothing);
  });

  testWidgets('Theme and Scrolling Text open as one form each, and saving keeps you on the form', (tester) async {
    final store = await _open(tester);
    await _section(tester, 'theme');
    expect(find.text('Add new'), findsNothing);
    await _scrollToSave(tester);
    expect(find.text('Save changes'), findsOneWidget);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Save changes'), findsOneWidget, reason: 'still on the Theme form after saving');
    expect(find.byKey(const ValueKey('settings-theme')), findsOneWidget, reason: 'the Settings list is still there');
    expect(store.entries('settings').firstWhere((e) => e.id == 'theme').text('name'), 'Theme', reason: 'the record is never saved without a name');

    // Scrolling Text is now its own page (preview, animation, colours); its full form opens from "All Scrolling Text options".
    await _section(tester, 'scrollingText');
    expect(find.text('Add new'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('open-scrolling-all')));
    await tester.tap(find.byKey(const ValueKey('open-scrolling-all')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    await _scrollToSave(tester);
    expect(find.text('Save changes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a project that never saved its Theme still gets the form, and the first Save creates it', (tester) async {
    final store = await _open(tester, withoutTheme: true);
    expect(store.entries('settings').where((e) => e.id == 'theme'), isEmpty);
    await _section(tester, 'theme');
    await _scrollToSave(tester);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(store.entries('settings').where((e) => e.id == 'theme').length, 1);
    await _scrollToSave(tester);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(store.entries('settings').where((e) => e.id == 'theme').length, 1, reason: 'saving again updates the same record');
  });

  testWidgets('a Theme saved earlier without any name now saves (its name field starts as "Theme")', (tester) async {
    final store = await _open(tester);
    await store.updateFields('settings', 'theme', const {}, remove: {'name'}, fallback: const Entry('theme', {}));
    expect(store.entries('settings').firstWhere((e) => e.id == 'theme').text('name'), isEmpty);
    await tester.pumpWidget(const SizedBox());
    tester.view.physicalSize = const Size(1200, 2000);
    await tester.pumpWidget(MaterialApp(home: AdminPage(store: store)));
    DefaultTabController.of(tester.element(find.byType(TabBar).first)).animateTo(7);
    await tester.pumpAndSettle();
    await _section(tester, 'theme');
    expect(find.widgetWithText(TextFormField, 'Theme'), findsOneWidget, reason: 'the name field shows the default');
    await _scrollToSave(tester);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name'), findsNothing);
    expect(store.entries('settings').firstWhere((e) => e.id == 'theme').text('name'), 'Theme');
  });

  testWidgets('a record without a name shows its section name in lists instead of a blank row', (tester) async {
    final store = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('settings-categories')));
    await tester.pumpAndSettle();
    await store.save('categories', const Entry('c-nameless', {'order': 9, 'active': true}));
    await tester.pumpAndSettle();
    expect(find.text('Categories'), findsWidgets);
  });
}
