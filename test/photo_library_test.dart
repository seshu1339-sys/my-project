import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/ui/photo_library_data.dart';
import 'package:ecommerce_app/ui/photo_library_page.dart';

void main() {
  test('names: lower-case hyphen folders in the address, readable names on screen', () {
    expect(photoCategoryTitle('fancy-items'), 'Fancy Items');
    expect(photoCategoryTitle('grocery'), 'Grocery');
    expect(photoTitle('bulb-holder.webp'), 'Bulb holder');
    expect(photoUrl('fancy-items', 'anklet.webp'), endsWith('/images/fancy-items/anklet.webp'));
  });

  test('the list matches the WebP files in web/images exactly, and every name is lower case with hyphens', () {
    final folders = Directory('web/images').listSync().whereType<Directory>().map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last).toSet();
    expect(photoLibrary.keys.toSet(), folders);
    var total = 0;
    for (final e in photoLibrary.entries) {
      expect(e.key, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')));
      final files = Directory('web/images/${e.key}').listSync().map((f) => f.uri.pathSegments.last).toSet();
      expect(e.value.toSet(), files, reason: e.key);
      for (final f in e.value) {
        expect(f, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*\.webp$')));
      }
      total += e.value.length;
    }
    expect(total, 210);
  });

  testWidgets('one section per category; photos are built lazily', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: PhotoLibraryPage()));
    expect(find.text('Photo library'), findsOneWidget);
    expect(find.text('Electricals'), findsOneWidget);
    expect(find.byType(Image).evaluate().length, lessThan(30), reason: 'only the photos near the screen exist');
    for (var i = 0; i < 400 && find.text('Vegetables').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump();
    }
    expect(find.text('Vegetables'), findsOneWidget);
  });
}
