// The admin panel search's "Ask AI" (owner, 13 Nov 2026): the normal search first; only when it finds nothing the "AI ని అడుగు" button
// sends every setting of the panel (from the panel's own lists, with the current values) and shows the answer and the settings it chose.
// A limit message never stops the normal search. No real AI call: a fake answers.
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/admin_settings.dart';
import 'package:ecommerce_app/ui/admin_settings_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the index has every section, every form field and every page of the groups, so new ones are found by themselves', () {
    final index = adminSettingsIndex();
    for (final key in ['settings', 'reports', 'ratings', 'staffWork', 'staffLinks', 'idReport', 'blockList']) {
      expect(index.where((h) => !h.isField && h.sectionKey == key), hasLength(1), reason: key);
    }
    for (final field in ['postDuration', 'abuseReportsToSuspend', 'photoSearchesPerDay', 'adminAiPerDay', 'adminSearchAiPerDay']) {
      expect(index.where((h) => h.hint == field), hasLength(1), reason: field);
    }
    final pages = index.where((h) => h.serial.startsWith('P')).map((h) => h.title).toList();
    expect(pages, containsAll(['Orders', 'Products', 'Plans', 'Promotions', 'Service providers', 'Staff Areas']));
    expect(searchAdminSettings('products').map((h) => h.sectionKey), contains('tab:Products'));
  });

  testWidgets('nothing found: "Ask AI" sends the settings with their values; the answer and its settings show and open', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog['settings'] = [...store.entries('settings').where((e) => e.id != 'business'), const Entry('business', {'name': 'Local Market', 'abuseReportsToSuspend': 12})];
    final sent = <Map<String, dynamic>>[];
    AdminSettingHit? opened;
    var limit = false;
    final reports = adminSettingsIndex().firstWhere((h) => h.hint == 'abuseReportsToSuspend');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminSettingsSearchBar(
      store: store,
      open: (h) => opened = h,
      askAi: (data) async {
        sent.add(data);
        if (limit) throw StateError("You have used today's 100 AI searches. Please try again tomorrow; the normal search still works.");
        return {'answer': 'ఆటో సస్పెన్షన్ కి 12 రిపోర్టులు: Business Profile లో.', 'serials': [reports.serial]};
      },
    ))));
    // A name the normal search knows: no AI button.
    await tester.enterText(find.byKey(const ValueKey('admin-settings-search')), 'post duration');
    await tester.pump();
    expect(find.byKey(const ValueKey('admin-settings-ask-ai')), findsNothing);
    // Everyday words it does not know: the button, and the AI's answer with the setting.
    await tester.enterText(find.byKey(const ValueKey('admin-settings-search')), 'ఎన్ని రిపోర్టులకు బ్లాక్');
    await tester.pump();
    expect(find.byKey(const ValueKey('admin-settings-search-none')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('admin-settings-ask-ai')));
    await tester.pumpAndSettle();
    expect(sent.single['query'], 'ఎన్ని రిపోర్టులకు బ్లాక్');
    final row = (sent.single['index'] as List).cast<Map>().firstWhere((r) => r['key'] == 'abuseReportsToSuspend');
    expect(row['value'], '12', reason: 'the current value goes with it');
    expect('${row['label']}', contains('Business Profile'));
    expect(find.textContaining('12 రిపోర్టులు'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('admin-settings-ai-hit-${reports.serial}')));
    expect(opened?.hint, 'abuseReportsToSuspend');

    // Past the AI's daily limit: the message shows, and the normal search still works.
    limit = true;
    await tester.enterText(find.byKey(const ValueKey('admin-settings-search')), 'something else entirely');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('admin-settings-ask-ai')));
    await tester.pumpAndSettle();
    expect(find.textContaining('the normal search still works'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('admin-settings-search')), 'ratings');
    await tester.pump();
    expect(find.byKey(ValueKey('admin-settings-hit-${searchAdminSettings('ratings').first.serial}')), findsOneWidget);
    store.dispose();
  });
}
