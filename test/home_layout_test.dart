import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/ui/home_widgets.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    if (Platform.isWindows) {
      final font = File('${Platform.environment['WINDIR']}/Fonts/arial.ttf');
      if (await font.exists()) {
        await (FontLoader('Arial')..addFont(
              font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            ))
            .load();
      }
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final size in [
    const Size(320, 844),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1024, 768),
    const Size(1440, 1100),
    const Size(1920, 1080),
    const Size(2560, 1440),
  ]) {
    testWidgets('home layout and navigation at ${size.width}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      store.catalog['settings']!.removeWhere((e) => e.id == 'theme');
      store.catalog['settings']!.add(
        const Entry('theme', {'fontFamily': 'Arial'}),
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MarketApp(store: store),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('App logo'), findsOneWidget);
      expect(find.text('Categories'), findsWidgets);
      expect(find.byTooltip('Voice search'), findsOneWidget);
      expect(find.byTooltip('Camera search'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if ([390.0, 768.0, 1440.0, 2560.0].contains(size.width)) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/home-${size.width.toInt()}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.ensureVisible(find.text('Popular Products'));
        await tester.pump();
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('build/home-${size.width.toInt()}-products.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }

  testWidgets('empty collection cannot create purchasable demo cards', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog['products'] = [];
    await tester.pumpWidget(MarketApp(store: store));
    expect(find.byType(HomeProductTile), findsNothing);
    expect(
      find.text('No matching products. Try another search.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('home supports large text on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(MarketApp(store: store));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
