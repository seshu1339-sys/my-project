// The seven animation types for Today's Offers and for the ads: the
// RotatingPages widget on its own (every type, sizes during the change), and
// on the real customer page (MarketApp) driven by the admin's settings docs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/ui/home_rotating_pages.dart';
import 'package:ecommerce_app/ui/home_promo_card.dart';

const _types = [
  'slide',
  'fade',
  'flip',
  'cube',
  'zoom',
  'bounce',
  'carousel',
];

PromoMotion _motion(String type, {bool pause = true}) => PromoMotion.from(
  Entry('s', {
    'animationType': type,
    'animationMs': 1500,
    'animationSpeed': 5,
    'pauseOnTouch': pause,
  }),
)!;

Widget _host(Widget child, {double width = 300, double height = 200}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );

Widget _page(int i) => Container(
  key: ValueKey('box-$i'),
  color: Colors.primaries[i],
  child: Center(child: Text('Page $i')),
);

void main() {
  test('no animation type chosen means the original behaviour', () {
    expect(PromoMotion.from(const Entry('s', {})), isNull);
    expect(PromoMotion.from(const Entry('s', {'animationType': 'nope'})), isNull);
  });

  test('speed 10 is faster than speed 1 and never outlasts the interval', () {
    PromoMotion at(num speed, num interval) => PromoMotion.from(
      Entry('s', {
        'animationType': 'fade',
        'animationSpeed': speed,
        'animationMs': interval,
      }),
    )!;
    expect(at(10, 5000).transition, lessThan(at(1, 5000).transition));
    expect(at(1, 1500).transition.inMilliseconds, lessThanOrEqualTo(1200));
  });

  for (final type in _types.where((t) => t != 'carousel')) {
    testWidgets('$type: next page arrives and boxes keep their size', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          RotatingPages(
            motion: _motion(type),
            pageCount: 3,
            pageBuilder: (_, i) => _page(i),
          ),
        ),
      );
      expect(find.text('Page 0'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('box-0'))),
          const Size(300, 200));

      // The interval elapses and the change begins: both pages exist and
      // every one of them is still exactly the box size.
      await tester.pump(const Duration(milliseconds: 1500));
      for (final step in [100, 250, 250, 250]) {
        await tester.pump(Duration(milliseconds: step));
        for (final i in [0, 1]) {
          final finder = find.byKey(ValueKey('box-$i'));
          if (finder.evaluate().isNotEmpty) {
            expect(tester.getSize(finder), const Size(300, 200),
                reason: '$type page $i changed size mid-animation');
          }
        }
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 0'), findsNothing);
      expect(tester.takeException(), isNull);

      // It keeps going, round and round (each change: wait out the 1.5 s
      // interval, then let the ~1 s transition finish before the next tick).
      Future<void> nextPage() async {
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pump(const Duration(milliseconds: 1000));
      }

      await nextPage();
      expect(find.text('Page 2'), findsOneWidget);
      await nextPage();
      expect(find.text('Page 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('slide can run vertically, and reversed', (tester) async {
    await tester.pumpWidget(
      _host(
        RotatingPages(
          motion: _motion('slide'),
          pageCount: 2,
          axis: Axis.vertical,
          reverse: true,
          pageBuilder: (_, i) => _page(i),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 200));
    final incoming = tester.getTopLeft(find.byKey(const ValueKey('box-1')));
    final outgoing = tester.getTopLeft(find.byKey(const ValueKey('box-0')));
    // Reversed vertical slide: the new page enters from the top.
    expect(incoming.dy, lessThan(outgoing.dy));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('Page 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('carousel: centre item is the biggest, neighbours smaller', (
    tester,
  ) async {
    final controller = RotatingPagesController();
    await tester.pumpWidget(
      _host(
        RotatingPages(
          motion: _motion('carousel'),
          pageCount: 5,
          slotsPerView: 3,
          controller: controller,
          pageBuilder: (_, i) => _page(i),
        ),
        width: 600,
      ),
    );
    await tester.pump();
    // getRect follows the paint transform, so it shows the drawn size.
    double drawn(int i) => tester.getRect(find.byKey(ValueKey('box-$i'))).width;
    expect(drawn(0), greaterThan(drawn(1)));
    expect(controller.page.value, 0);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(controller.page.value, 1);
    expect(drawn(1), greaterThan(drawn(2)));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('pause on touch holds the page; off keeps it moving', (
    tester,
  ) async {
    Future<void> run(bool pause) async {
      await tester.pumpWidget(
        _host(
          RotatingPages(
            key: ValueKey('pause-$pause'),
            motion: _motion('fade', pause: pause),
            pageCount: 2,
            pageBuilder: (_, i) => _page(i),
          ),
        ),
      );
      final finger = await tester.startGesture(
        tester.getCenter(find.byType(RotatingPages)),
      );
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(
        find.text('Page 0').evaluate().isNotEmpty,
        pause,
        reason: pause
            ? 'a touched group must stay still'
            : 'pause-on-touch off must keep moving',
      );
      await finger.up();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
    }

    await run(true);
    await run(false);
  });

  // ---- the real customer page ------------------------------------------------

  Future<Store> storeWith(Map<String, Map<String, dynamic>> settings) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    for (final entry in settings.entries) {
      await store.save('settings', Entry(entry.key, entry.value));
    }
    return store;
  }

  for (final type in _types) {
    testWidgets('Today\'s Offers on the real page: $type', (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await storeWith({
        'section_promo': {
          'section': 'promo',
          'animationType': type,
          'animationMs': 1500,
          'animationSpeed': 8,
        },
      });
      store.catalog['promotions']!.removeWhere(
        (e) => e.text('placement') == 'carousel',
      );
      for (final (i, name) in ['Offer One', 'Offer Two', 'Offer Three'].indexed) {
        await store.save(
          'promotions',
          Entry('o$i', {
            'name': name,
            'placement': 'carousel',
            'order': i,
            'active': true,
          }),
        );
      }
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pump();
      final viewport = find.byKey(const ValueKey('banner-viewport'));
      final before = tester.getSize(viewport);
      expect(find.text('Offer One'), findsWidgets);
      await tester.pump(const Duration(milliseconds: 1500));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.getSize(viewport), before,
            reason: '$type changed the offers box size');
      }
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Offer Two'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });

    testWidgets('the ads on the real page: $type', (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await storeWith({
        'section_ads': {
          'section': 'ads',
          'animationType': type,
          'animationMs': 1500,
          'animationSpeed': 8,
        },
      });
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pump();
      final viewport = find.byKey(const ValueKey('ads-viewport'));
      expect(viewport, findsOneWidget, reason: 'the animated ad rail is used');
      final before = tester.getSize(viewport);
      expect(find.text('A helping hand, nearby.'), findsWidgets);
      // A carousel shows the next box peeking beside the centre one.
      if (type != 'carousel') {
        expect(find.text('Secure payments.'), findsNothing);
      }
      await tester.pump(const Duration(milliseconds: 1500));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.getSize(viewport), before,
            reason: '$type changed the ads box size');
      }
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Secure payments.'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }

  testWidgets('ads with very different amounts of text are exactly as wide', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await storeWith({});
    store.catalog['promotions']!.removeWhere((e) => e.text('placement') == 'ad');
    await store.save('promotions', const Entry('short', {'name': 'Hi', 'placement': 'ad', 'order': 0, 'active': true}));
    await store.save('promotions', const Entry('long', {
      'name': 'Big Savings Everyday on everything you need',
      'description': 'A much longer line of supporting text that wraps over several lines of the box.',
      'placement': 'ad',
      'order': 1,
      'active': true,
    }));
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    final sizes = [
      for (final e in find.byType(PromoCard).evaluate())
        tester.getSize(find.byWidget(e.widget)),
    ];
    expect(sizes.length, greaterThanOrEqualTo(2));
    expect(sizes.map((s) => s.width).toSet(), hasLength(1), reason: 'ad widths: $sizes');
    // The two ads (a promotional box below them has its own height).
    expect(sizes.take(2).map((s) => s.height).toSet(), hasLength(1), reason: 'ad heights: $sizes');
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('offers and ads keep separate animation settings', (tester) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await storeWith({
      'section_promo': {'section': 'promo', 'animationType': 'fade', 'animationMs': 1500},
      'section_ads': {'section': 'ads', 'animationType': 'cube', 'animationMs': 1500},
    });
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.byKey(const ValueKey('offers-rotation-fade')), findsOneWidget);
    expect(find.byKey(const ValueKey('ads-rotation-cube-2')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
