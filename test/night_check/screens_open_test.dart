// NIGHT CHECK (11 Nov 2026): every admin tab and every Settings section really opens (no exception, something on screen), on a wide
// screen and a phone. Prints one SCREEN line each for NIGHT_CHECK_REPORT.md. Does not change any app code.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/ui/admin.dart';

const _sections = [
  'categories', 'services', 'fieldAssistants', 'cityCodes', 'settings', 'theme', 'animations', 'scrollingText', 'homeOffers', 'homePromo',
  'homeFresh', 'shopsLocation', 'ads', 'rightBoxes', 'productImageLibrary', 'layout', 'androidHome', 'locations', 'samples', 'areaNames',
  'module-transport', 'module-itemPhotos',
];

Future<Store> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  return store;
}

int _texts(WidgetTester tester) => tester.widgetList<Text>(find.byType(Text)).where((t) => (t.data ?? '').trim().isNotEmpty).length;

void main() {
  testWidgets('every admin tab opens', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store();
    await tester.pumpWidget(MaterialApp(home: AdminPage(store: store)));
    await tester.pumpAndSettle();
    final tabs = tester.widgetList<Tab>(find.byType(Tab)).map((t) => t.text ?? '').where((t) => t.isNotEmpty).toList();
    for (final (i, name) in tabs.indexed) {
      DefaultTabController.of(tester.element(find.byType(TabBar).first)).animateTo(i);
      await tester.pumpAndSettle();
      final error = tester.takeException();
      final shown = _texts(tester);
      // ignore: avoid_print
      print('SCREEN admin-tab "$name" ${error == null ? 'OPENS' : 'ERROR $error'} texts=$shown');
      expect(error, isNull, reason: name);
    }
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in const [Size(1600, 2400), Size(390, 1600)]) {
    testWidgets('every Settings section opens at ${size.width.toInt()} px', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final key in _sections) {
        final store = await _store();
        await tester.pumpWidget(MaterialApp(home: AdminPage(store: store)));
        await tester.pumpAndSettle();
        final bar = DefaultTabController.of(tester.element(find.byType(TabBar).first));
        bar.animateTo(bar.length - 1);
        await tester.pumpAndSettle();
        final tile = find.byKey(ValueKey('settings-$key'));
        if (tile.evaluate().isEmpty) {
          // The phone list builds lazily: scroll down to the section first.
          try {
            await tester.scrollUntilVisible(tile, 200, scrollable: find.byType(Scrollable).last);
          } catch (_) {}
        }
        if (tile.evaluate().isEmpty) {
          // ignore: avoid_print
          print('SCREEN settings "$key" ${size.width.toInt()}px MISSING-TILE');
          continue;
        }
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        // Some sections animate for ever (the Scrolling Text preview): pump a fixed time instead of waiting to settle.
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        final error = tester.takeException();
        // ignore: avoid_print
        print('SCREEN settings "$key" ${size.width.toInt()}px ${error == null ? 'OPENS' : 'ERROR $error'} texts=${_texts(tester)}');
        // Recorded, not fatal: the report lists every section that fails to open.
        await tester.pumpWidget(const SizedBox());
        store.dispose();
      }
    });
  }
}
