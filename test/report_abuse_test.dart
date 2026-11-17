// Abuse reports in the apps (lib/ui/report_abuse.dart): the dialog needs a reason, sends what the server needs, and shows the server's
// answer (for example "Only a customer who ordered from this shop can report it."). The admin's number is a Business Profile field.
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/ui/admin_fields.dart';
import 'package:ecommerce_app/ui/admin_settings.dart';
import 'package:ecommerce_app/ui/report_abuse.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a report needs a reason, sends the target with it, and shows the server answer', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    final sent = <Map<String, dynamic>>[];
    var refuse = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReportButton(
      store: store,
      target: const {'kind': 'shop', 'shopId': 's1'},
      label: 'Ramu Kirana',
      send: (data) async {
        if (refuse) throw StateError('Only a customer who ordered from this shop can report it.');
        sent.add(data);
      },
    ))));
    await tester.tap(find.byKey(const ValueKey('report-shop')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('report-send'))).onPressed, isNull, reason: 'a reason is needed');
    await tester.tap(find.byKey(const ValueKey('report-reason-cheating')));
    await tester.enterText(find.byKey(const ValueKey('report-details')), 'Took money, gave nothing');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('report-send')));
    await tester.pumpAndSettle();
    expect(sent.single, {'kind': 'shop', 'shopId': 's1', 'reason': 'cheating', 'details': 'Took money, gave nothing'});
    expect(find.textContaining('The Support Team will look at your report'), findsOneWidget);

    refuse = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.byKey(const ValueKey('report-shop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-reason-fake')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('report-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Only a customer who ordered from this shop'), findsOneWidget);
    store.dispose();
  });

  test('the admin sets the number of reports in Business Profile, and finds Reports and the Block list in the search', () {
    expect(fields['settings']!.keys, contains('abuseReportsToSuspend'));
    expect(searchAdminSettings('reports').map((h) => h.sectionKey), contains('reports'));
    expect(searchAdminSettings('block list').first.sectionKey, 'blockList');
    expect(searchAdminSettings('automatic temporary suspension').map((h) => h.hint), contains('abuseReportsToSuspend'));
  });
}
