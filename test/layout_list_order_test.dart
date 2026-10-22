// The admin's Layout Settings list: every numbered element is present (14 was
// missing) and the list follows the element numbers (20 was before 18).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/ui/entry_editor.dart';
import 'package:ecommerce_app/ui/layout_editor.dart';
import 'package:ecommerce_app/ui/page_elements.dart';

void main() {
  final choices = layoutComponentChoices();
  final keys = [for (final c in choices) c.key];

  test('every numbered element is in the list, including 14', () {
    for (final element in pageElements) {
      expect(keys, contains(element.key), reason: '#${element.number} ${element.label}');
    }
    expect(keys.toSet().length, keys.length, reason: 'no component listed twice');
    expect(pageElementByNumber(14)!.key, 'tickerMarquee');
    expect(keys, contains('tickerMarquee'));
  });

  test('numbered elements follow their numbers, with nothing out of order', () {
    final numbers = [
      for (final key in keys)
        if (pageElementByKey(key) != null) pageElementByKey(key)!.number,
    ];
    expect(numbers, [...numbers]..sort(), reason: 'list order: $numbers');
    expect(numbers.first, 1);
    int at(String key) => keys.indexOf(key);
    expect(at('notice'), lessThan(at('tickerMarquee')), reason: '13 then 14');
    expect(at('tickerMarquee'), lessThan(at('promo')), reason: '14 then 15');
    expect(at('popular'), lessThan(at('popularFilterChips')));
    expect(at('popularFilterChips'), lessThan(at('products')), reason: '18, 19, then 20');
    expect(at('products'), lessThan(at('localServices')), reason: '20 then 21');
    expect(at('footerBadges'), lessThan(at('footerBadge1')));
    expect(at('footerBadge6'), lessThan(at('productPageAddButton')), reason: '28.x before 29');
    expect(keys.first, 'header');
  });

  testWidgets('14 shows in the dropdown and opens the Scrolling Text editor', (tester) async {
    tester.view.physicalSize = const Size(1600, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(MaterialApp(home: LayoutSettingsPage(store: store)));
    await tester.tap(find.byKey(const ValueKey('search')));
    await tester.pumpAndSettle();
    final labels = [
      for (final text in tester.widgetList<Text>(find.byType(Text)))
        if ((text.data ?? '').contains(' – ')) text.data!,
    ];
    final i13 = labels.indexWhere((l) => l.startsWith('13 – '));
    final i14 = labels.indexWhere((l) => l.startsWith('14 – Scrolling Text'));
    final i15 = labels.indexWhere((l) => l.startsWith('15 – '));
    expect(i14, greaterThan(i13));
    expect(i15, greaterThan(i14));
    await tester.tap(find.textContaining('14 – Scrolling Text').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('open-scrolling-text-settings')), findsOneWidget);
    expect(find.text('Save layout'), findsNothing, reason: 'nothing to save on this panel');
    await tester.tap(find.byKey(const ValueKey('open-scrolling-text-settings')));
    await tester.pumpAndSettle();
    final editor = tester.widget<EntryEditor>(find.byType(EntryEditor));
    expect(editor.collection, 'scrollingText');
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
