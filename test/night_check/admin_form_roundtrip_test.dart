// NIGHT CHECK (11 Nov 2026): every admin form field (lib/ui/admin_fields.dart) is typed into the real admin form (EntryEditor) and
// saved; the record must then hold the same value under the same field name. Prints one ROUNDTRIP line per field (OK / FAIL / SKIP and
// why) for NIGHT_CHECK_REPORT.md. Does not change any app code.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/admin_fields.dart';
import 'package:ecommerce_app/ui/entry_editor.dart';

const _numbers = {
  'price': '7', 'compareAtPrice': '9', 'stock': '4', 'order': '3', 'latitude': '17.5', 'longitude': '82.5', 'radiusKm': '12',
  'vendorPhotoLimit': '3', 'fieldPhotoLimit': '2', 'quickItemsPerDayStaff': '5', 'quickItemsPerDayVendor': '4', 'freeDeliveryAbove': '300',
  'width': '320', 'height': '300', 'fontSize': '14', 'speed': '80', 'padding': '6', 'radius': '12', 'shadow': '0.5', 'brightness': '1.1',
  'opacity': '0.9', 'spacing': '8', 'animationMs': '500', 'stopAfter': '10', 'countdownSeconds': '60', 'borderWidth': '2',
  'exclusiveExpiryNoticeDays': '3', 'storageWarningGb': '4', 'photoSearchesPerDay': '10', 'adminAiPerDay': '5', 'abuseReportsToSuspend': '12',
};
const _texts = {
  'supportEmail': 'help@example.com', 'websiteUrl': 'https://example.com', 'vendorSignupUrl': 'https://example.com/sell',
  'imageUrl': 'https://example.com/a.png', 'backgroundImage': 'https://example.com/b.png', 'images': 'https://example.com/c.png',
  'prices': '560001=99', 'translations': 'te=తెలుగు', 'enabledLanguages': 'en,te', 'deliveryFeeTiers': '5:10', 'serviceTowns': 'Narsipatnam=531116',
  'autoPublishVendorChanges': 'true', 'priceDropAutoEnabled': 'false', 'directVendorPaymentEnabled': 'true', 'cashOnDeliveryEnabled': 'true',
  'platformCollectionEnabled': 'false', 'productImageLibraryEnforced': 'true', 'target': 'shop:shop-n', 'pincode': '531116',
};

String _valueFor(String key) => _numbers[key] ?? _texts[key] ?? 'NC $key';

Object? _expected(String key, String typed) {
  if (_numbers.containsKey(key)) return num.parse(typed);
  if (key == 'prices') return {'560001': 99};
  if (key == 'images') return ['https://example.com/c.png'];
  if (key == 'translations') return {'te': 'తెలుగు'};
  return typed;
}

bool _same(Object? saved, Object? want) {
  if (saved is num && want is num) return saved == want;
  if (saved is Map && want is Map) return saved.length == want.length && want.entries.every((e) => '${saved[e.key]}' == '${e.value}');
  if (saved is List && want is List) return saved.length == want.length && [for (var i = 0; i < want.length; i++) '${saved[i]}' == '${want[i]}'].every((x) => x);
  return '$saved' == '$want';
}

Map<String, dynamic> _start(String collection) => switch (collection) {
  'promotions' => {'name': 'NC promo', 'placement': 'carousel', 'radiusShopId': 'shop-n'},
  'products' => {'name': 'NC product', 'price': 5, 'shopId': 'shop-n', 'kind': 'product', 'categoryId': 'cat-1'},
  'services' => {'name': 'NC service', 'price': 5, 'shopId': 'shop-n', 'kind': 'service', 'categoryId': 'cat-1'},
  'productImageLibrary' => {'name': 'NC photo', 'categoryId': 'cat-1'},
  _ => {'name': 'NC $collection'},
};

void main() {
  for (final collection in fields.keys) {
    testWidgets('every field of the $collection form saves under its own name', (tester) async {
      tester.view.physicalSize = const Size(1400, 9000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      store.catalog['shops'] = [const Entry('shop-n', {'name': 'Suma Fresh Mart', 'latitude': 17.667, 'longitude': 82.612})];
      if (collection != 'categories') store.catalog['categories'] = [const Entry('cat-1', {'name': 'Vegetables'})];
      final id = 'nc-$collection';
      // Theme and Scrolling Text are records of the settings collection (lib/ui/entry_editor.dart save()).
      final stored = collection == 'theme' || collection == 'scrollingText' ? 'settings' : collection;
      final original = Entry(id, _start(collection));
      await store.save(stored, original);
      await tester.pumpWidget(MaterialApp(home: EntryEditor(store: store, collection: collection, entry: original)));
      await tester.pumpAndSettle();
      final typed = <String, String>{};
      final lines = <String>[];
      for (final MapEntry(key: key, value: label) in fields[collection]!.entries) {
        final box = find.widgetWithText(TextFormField, label);
        if (box.evaluate().isEmpty) {
          lines.add('ROUNDTRIP $collection.$key SKIP not a text box (dropdown, colour or picker)');
          continue;
        }
        if (key == 'startsAt' || key == 'endsAt') {
          lines.add('ROUNDTRIP $collection.$key SKIP date picker');
          continue;
        }
        final value = _valueFor(key);
        await tester.enterText(box.first, value);
        typed[key] = value;
      }
      await tester.pump();
      final save = find.text('Save changes');
      expect(save, findsOneWidget, reason: 'the $collection form has a Save button');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final errors = [
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          if ((t.data ?? '').startsWith('Enter ') || (t.data ?? '').startsWith('Use ') || (t.data ?? '').startsWith('Choose ')) t.data!,
        for (final t in tester.widgetList<Text>(find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)))) 'snack: ${t.data}',
      ];
      final saved = store.entries(stored).where((e) => e.id == id).firstOrNull;
      var failed = 0;
      for (final MapEntry(key: key, value: value) in typed.entries) {
        final ok = saved != null && _same(saved.data[key], _expected(key, value));
        if (!ok) failed++;
        lines.add('ROUNDTRIP $collection.$key ${ok ? 'OK' : 'FAIL saved=${saved?.data[key]} typed=$value'}');
      }
      for (final l in lines) {
        // ignore: avoid_print
        print(l);
      }
      // ignore: avoid_print
      if (errors.isNotEmpty) print('ROUNDTRIP $collection FORM-ERRORS ${errors.join(' | ')}');
      expect(tester.takeException(), isNull);
      expect(failed, 0, reason: 'fields of $collection that did not save as typed (see ROUNDTRIP lines); form errors: $errors');
    });
  }
}
