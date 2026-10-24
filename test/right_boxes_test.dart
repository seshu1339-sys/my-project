import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/right_boxes.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/ui/admin_right_boxes.dart';
import 'package:ecommerce_app/ui/right_ad_boxes.dart';

Future<Store> _store([Map<String, dynamic> boxes = const {}]) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  if (boxes.isNotEmpty) store.catalog['settings']!.add(Entry(rightBoxesDoc, boxes));
  return store;
}

void main() {
  group('right_boxes', () {
    test('starts with 15 boxes, and Add / Remove change the count', () {
      expect(rightBoxCount(const Entry(rightBoxesDoc, {})), 15);
      expect(rightBoxCount(const Entry(rightBoxesDoc, {'count': 16})), 16);
      expect(rightBoxCount(const Entry(rightBoxesDoc, {'count': 0})), 0);
      expect(rightBoxCount(const Entry(rightBoxesDoc, {'count': 9999})), maxRightBoxCount);
    });

    test('customers get only the boxes that have a photo, in box-number order', () {
      const record = Entry(rightBoxesDoc, {'count': 5, 'box1Image': 'a.jpg', 'box3Image': 'c.jpg', 'box5Image': 'e.jpg', 'box7Image': 'beyond-the-count.jpg'});
      expect(liveRightBoxes(record).map((b) => b.number), [1, 3, 5]);
    });

    test('a link counts only when something was chosen', () {
      expect(const RightBox(1, 'a', 'category:', '').hasTarget, isFalse);
      expect(const RightBox(1, 'a', '', '').hasTarget, isFalse);
      expect(const RightBox(1, 'a', 'shop:s1', '').hasTarget, isTrue);
    });
  });

  testWidgets('every box is exactly the same size and shows no number or label', (tester) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = [
      const Entry(rightBoxesDoc, {'box1Image': 'http://x/a.jpg', 'box1Color': '#FFEEAA', 'box2Image': 'http://x/b.jpg', 'box4Image': 'http://x/d.jpg'}),
    ];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: RightAdBoxes(settings: settings, onTarget: (_) {})))));
    final sizes = [for (final n in [1, 2, 4]) tester.getSize(find.byKey(ValueKey('right-box-$n')))];
    expect(find.byKey(const ValueKey('right-box-3')), findsNothing, reason: 'a box with no photo is hidden');
    expect(sizes.toSet(), hasLength(1), reason: 'sizes: $sizes');
    expect(sizes.first.height, rightBoxHeight);
    expect(find.textContaining('Right Side Ad Box'), findsNothing);
    expect(find.textContaining('Box 1'), findsNothing);
  });

  testWidgets('the home page shows the boxes on desktop and on a phone, and nothing when no box has a photo', (tester) async {
    for (final width in [1440.0, 390.0]) {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final empty = await _store();
      await tester.pumpWidget(MarketApp(store: empty));
      await tester.pump();
      expect(find.byKey(const ValueKey('right-ad-boxes')), findsNothing, reason: 'width $width, no photos');
      await tester.pumpWidget(const SizedBox());
      empty.dispose();

      final store = await _store({'box1Image': 'http://x/a.jpg', 'box2Image': 'http://x/b.jpg'});
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pump();
      expect(find.byKey(const ValueKey('right-ad-boxes')), findsOneWidget, reason: 'width $width');
      expect(find.byKey(const ValueKey('right-box-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('right-box-2')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    }
  });

  testWidgets('admin: 15 numbered boxes to start, Add box and Remove box change the number', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminRightBoxesPage(store: store))));
    await tester.pump();
    expect(find.text('15 boxes'), findsOneWidget);
    expect(find.text('Right Side Ad Box 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-right-box')));
    await tester.pump();
    await tester.pump();
    expect(find.text('16 boxes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remove-right-box')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('remove-right-box')));
    await tester.pump();
    await tester.pump();
    expect(find.text('14 boxes'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('the header contact box shows exactly what the admin typed in Business profile', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store();
    await store.save('settings', const Entry('business', {'name': 'Local Market', 'headerContact': 'Main Road, Narsipatnam\ninfo@locamarket.in'}));
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.text('Main Road, Narsipatnam\ninfo@locamarket.in'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('an uploaded logo replaces the icon and the name text in the header', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _store();
    await store.save('settings', const Entry('business', {'name': 'Zebra Mart', 'imageUrl': 'http://x/logo.png'}));
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    expect(find.bySemanticsLabel('App logo'), findsOneWidget);
    expect(find.text('Zebra Mart'), findsNothing, reason: 'the logo stands in for the name text');
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
