import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/vendor_ids.dart';
import 'package:ecommerce_app/ui/admin_city_codes.dart';
import 'package:ecommerce_app/ui/admin_settings.dart';

Future<Store> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  return store;
}

void main() {
  test('the built-in city codes, the saved table and the vendor ID format', () {
    expect(cityCodeRows(const []).map((r) => '${r.town}=${r.code}'), ['Narsipatnam=NRPM', 'Tuni=TUNI', 'Rajahmundry=RAJH']);
    final saved = [
      const Entry(cityCodesDoc, {
        'rows': [
          {'town': 'Anakapalle', 'code': 'akpl'},
          {'town': 'Bad', 'code': 'TOOLONG'},
        ],
      }),
    ];
    expect(cityCodeRows(saved).map((r) => r.code), ['AKPL'], reason: 'invalid rows are ignored, codes are upper-cased');
    expect(vendorIdPattern.hasMatch('VEN-NRPM-116-325'), isTrue);
    expect(vendorIdPattern.hasMatch('VN00001'), isFalse);
  });

  test('a table with a missing town, a bad code, a repeated town or code, or a wrong pincode cannot be saved', () {
    expect(cityCodeProblems(const [CityCodeRow('Tuni', 'TUNI', '533401')]), isEmpty);
    expect(cityCodeProblems(const [CityCodeRow('', 'ABCD')]), contains('Row 1: enter the town name.'));
    expect(cityCodeProblems(const [CityCodeRow('Tuni', 'TUN')]).single, contains('four letters'));
    expect(cityCodeProblems(const [CityCodeRow('Tuni', 'TUNI'), CityCodeRow('tuni', 'TUNX')]).single, contains('twice'));
    expect(cityCodeProblems(const [CityCodeRow('Tuni', 'TUNI'), CityCodeRow('Tadi', 'tuni')]).single, contains('already used'));
    expect(cityCodeProblems(const [CityCodeRow('Tuni', 'TUNI', '5334')]).single, contains('six-digit'));
    expect(cityCodeProblems(const []), ['Add at least one town.']);
  });

  testWidgets('Settings > City codes: the admin adds a town and saves the table', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminSettingsPage(store: store))));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings-cityCodes')));
    await tester.pump();
    expect(find.byType(AdminCityCodesPage), findsOneWidget);
    expect(find.widgetWithText(TextField, 'NRPM'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('city-add')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('city-town-3')), 'Anakapalle');
    await tester.enterText(find.byKey(const ValueKey('city-code-3')), 'akpl');
    await tester.tap(find.byKey(const ValueKey('city-save')));
    await tester.pump();
    await tester.pump();
    expect(cityCodeRows(store.entries('settings')).map((r) => r.code), ['NRPM', 'TUNI', 'RAJH', 'AKPL']);

    // a duplicate code is refused, nothing is saved
    await tester.enterText(find.byKey(const ValueKey('city-code-3')), 'TUNI');
    await tester.tap(find.byKey(const ValueKey('city-save')));
    await tester.pump();
    expect(find.textContaining('already used'), findsOneWidget);
    expect(cityCodeRows(store.entries('settings')).last.code, 'AKPL');
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
