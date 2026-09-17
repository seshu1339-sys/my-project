import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/ui/home_promotions.dart';
import 'package:ecommerce_app/ui/layout_editor.dart';
import 'package:ecommerce_app/ui/layout_settings.dart';
import 'package:ecommerce_app/ui/services_page.dart';

void main() {
  for (final width in [320.0, 768.0, 1440.0, 2560.0]) {
    testWidgets('responsive viewport $width has no horizontal overflow', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      await tester.pumpWidget(MarketApp(store: store));
      expect(
        tester
            .getSize(find.byKey(const ValueKey('responsive-search-box')))
            .width,
        lessThanOrEqualTo(width),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }

  testWidgets('extreme component values remain usable on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog['settings']!.addAll(
      layoutComponents.keys.map(
        (id) => Entry('section_$id', {
          'width': 1,
          'height': 1,
          'fontSize': 40,
          'padding': 48,
          'margin': 48,
          'gap': 64,
          'mobileScale': 1.5,
          'columns': 12,
        }),
      ),
    );
    await tester.pumpWidget(MarketApp(store: store));
    expect(find.byTooltip('Voice search'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  test('dimension limits handle conflicting and non-finite stored values', () {
    final layout = ComponentLayout(
      const Entry('', {
        'width': double.infinity,
        'minWidth': 900,
        'maxWidth': 40,
        'height': -500,
        'minHeight': 100,
        'maxHeight': 10,
        'desktopScale': double.nan,
      }),
      1440,
    );
    expect(layout.width(320), 320);
    expect(layout.height(56, floor: 48), 100);
    expect(layout.columns(320), 1);
  });

  testWidgets('search dimensions persist and do not resize Services', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(MarketApp(store: store));
    final services = find.widgetWithText(TextButton, 'Services');
    final before = tester.getSize(services);
    await store.save(
      'settings',
      const Entry('section_search', {'desktopWidth': 520, 'height': 100}),
    );
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey('responsive-search-box'))),
      const Size(520, 100),
    );
    expect(tester.getSize(services), before);
    final restored = Store();
    await restored.init();
    expect(
      restored
          .entries('settings')
          .firstWhere((e) => e.id == 'section_search')
          .number('height'),
      100,
    );
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    restored.dispose();
  });

  testWidgets('layout editor validates, saves and resets only its component', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await store.save(
      'settings',
      const Entry('section_services', {'height': 88}),
    );
    await tester.pumpWidget(
      MaterialApp(home: LayoutSettingsPage(store: store)),
    );
    final field = find.byKey(const ValueKey('search-height'));
    await tester.enterText(field, '99999');
    await tester.ensureVisible(find.text('Save layout'));
    await tester.tap(find.text('Save layout'));
    await tester.pump();
    expect(
      store.entries('settings').where((e) => e.id == 'section_search'),
      isEmpty,
    );
    await tester.ensureVisible(field);
    await tester.enterText(field, '96');
    await tester.ensureVisible(find.text('Save layout'));
    await tester.tap(find.text('Save layout'));
    await tester.pump();
    expect(
      store
          .entries('settings')
          .firstWhere((e) => e.id == 'section_search')
          .number('height'),
      96,
    );
    await tester.tap(find.text('Reset this component to default'));
    await tester.pump();
    expect(
      store
          .entries('settings')
          .firstWhere((e) => e.id == 'section_search')
          .data
          .containsKey('height'),
      isFalse,
    );
    expect(
      store
          .entries('settings')
          .firstWhere((e) => e.id == 'section_services')
          .number('height'),
      88,
    );
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('five banners fit desktop and reduce on mobile', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final entries = List.generate(
      5,
      (i) => Entry('b$i', {'name': 'Banner $i'}),
    );
    Widget build() => MaterialApp(
      home: Scaffold(
        body: HeroCarousel(
          entries: entries,
          appearance: const Entry('', {'visibleCount': 5, 'height': 180}),
          onTap: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(build());
    expect(
      tester.getSize(find.byKey(const ValueKey('banner-viewport'))).height,
      180,
    );
    for (var i = 0; i < 5; i++) {
      expect(find.text('Banner $i').hitTestable(), findsOneWidget);
    }
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    expect(find.text('Banner 0').hitTestable(), findsOneWidget);
    expect(find.text('Banner 1').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('advertisement scrolls upward then stops at its timer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: ScheduledPromo(
              entry: const Entry('ad1', {
                'name': 'Offer',
                'height': 200,
                'scrollEnabled': true,
                'speed': 20,
                'stopAfter': 2,
              }),
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    final motion = find.byKey(const ValueKey('promo-motion-ad1'));
    double y() => tester.widget<Transform>(motion).transform.storage[13];
    await tester.pump(const Duration(milliseconds: 100));
    final initial = y();
    await tester.pump(const Duration(seconds: 1));
    expect(y(), lessThan(initial));
    await tester.pump(const Duration(seconds: 2));
    final stopped = y();
    await tester.pump(const Duration(seconds: 1));
    expect(y(), stopped);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ticker moves in both directions and responds to pause', (
    tester,
  ) async {
    for (final reverse in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TickerStrip(
              key: ValueKey(reverse),
              text: 'Offers • नमस्ते • வணக்கம்',
              reverse: reverse,
            ),
          ),
        ),
      );
      final transform = find
          .descendant(
            of: find.byType(TickerStrip),
            matching: find.byType(Transform),
          )
          .first;
      double x() => tester.widget<Transform>(transform).transform.storage[12];
      await tester.pump(const Duration(milliseconds: 100));
      final before = x();
      await tester.pump(const Duration(seconds: 1));
      expect(x(), reverse ? greaterThan(before) : lessThan(before));
      await tester.tap(find.byTooltip('Pause notice'));
      await tester.pump();
      final paused = x();
      await tester.pump(const Duration(seconds: 1));
      expect(x(), paused);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('services can be searched and open existing provider details', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(MaterialApp(home: ServicesPage(store: store)));
    await tester.enterText(find.byType(TextField), 'Plumbing');
    await tester.pump();
    await tester.tap(find.text('Plumbing visit'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.scrollUntilVisible(
      find.text('Call'),
      350,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
