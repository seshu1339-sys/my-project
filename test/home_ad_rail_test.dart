import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/home_ad_rail.dart';
import 'package:ecommerce_app/ui/layout_settings.dart';

void main() {
  final adLayout = ComponentLayout(const Entry('section_ads', {}), 1200);
  final boxLayout = ComponentLayout(const Entry('section_boxes', {}), 1200);

  group('HomeAdRail.wrapItem', () {
    testWidgets('the real customer site (wrapItem omitted) renders ads/boxes unwrapped, unchanged', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomeAdRail(
        adLayout: adLayout,
        boxLayout: boxLayout,
        ads: [const Entry('ad1', {'target': 'x'})],
        boxes: const [],
        onPromotion: (_) {},
      ))));
      expect(tester.takeException(), isNull);
    });

    testWidgets('each ad and box is wrapped INDIVIDUALLY, not the rail as a whole', (tester) async {
      final wrapped = <String>[];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: HomeAdRail(
        adLayout: adLayout,
        boxLayout: boxLayout,
        ads: [const Entry('ad1', {'target': 'x'}), const Entry('ad2', {'target': 'y'})],
        boxes: [const Entry('box1', {'target': 'z'})],
        onPromotion: (_) {},
        wrapItem: (entry, kind, child) {
          wrapped.add('$kind:${entry.id}');
          return KeyedSubtree(key: ValueKey('wrapped-${entry.id}'), child: child);
        },
      )))));
      expect(wrapped, ['ad:ad1', 'ad:ad2', 'box:box1'], reason: 'wrapItem must be called once per individual ad/box, with the correct kind, never once for the whole rail');
      expect(find.byKey(const ValueKey('wrapped-ad1')), findsOneWidget);
      expect(find.byKey(const ValueKey('wrapped-ad2')), findsOneWidget);
      expect(find.byKey(const ValueKey('wrapped-box1')), findsOneWidget);
    });

    testWidgets('wrapping is independent per item — the wrapper for one ad never contains another', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: HomeAdRail(
        adLayout: adLayout,
        boxLayout: boxLayout,
        ads: [const Entry('ad1', {'target': 'x'}), const Entry('ad2', {'target': 'y'})],
        boxes: const [],
        onPromotion: (_) {},
        wrapItem: (entry, kind, child) => Container(key: ValueKey('wrap-${entry.id}'), child: child),
      )))));
      final wrap1 = find.byKey(const ValueKey('wrap-ad1'));
      final wrap2 = find.byKey(const ValueKey('wrap-ad2'));
      expect(wrap1, findsOneWidget);
      expect(wrap2, findsOneWidget);
      // wrap-ad2 must not be a descendant of wrap-ad1 (they're siblings).
      expect(find.descendant(of: wrap1, matching: wrap2), findsNothing);
    });
  });

  group('adjustPromoDimension', () {
    test('writes only the requested field, preserving every other field on the promotion doc', () async {
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      await store.save('promotions', const Entry('ad1', {'target': 'shop-1', 'imageUrl': 'https://x/y.png', 'width': 300.0}));

      await adjustPromoDimension(store, 'ad1', 'height', 555.0);

      final saved = store.entries('promotions').firstWhere((e) => e.id == 'ad1');
      expect(saved.number('height', 0), 555.0);
      expect(saved.number('width', 0), 300.0, reason: 'the pre-existing width must survive a height-only update');
      expect(saved.text('target'), 'shop-1');
      expect(saved.text('imageUrl'), 'https://x/y.png');
    });

    test('resizing one ad never touches another ad\'s doc', () async {
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      await store.save('promotions', const Entry('ad1', {'height': 200.0}));
      await store.save('promotions', const Entry('ad2', {'height': 200.0}));

      await adjustPromoDimension(store, 'ad1', 'height', 999.0);

      expect(store.entries('promotions').firstWhere((e) => e.id == 'ad1').number('height', 0), 999.0);
      expect(store.entries('promotions').firstWhere((e) => e.id == 'ad2').number('height', 0), 200.0);
    });
  });
}
