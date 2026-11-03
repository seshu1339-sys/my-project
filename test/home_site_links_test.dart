import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/ui/home_site_links.dart';

void main() {
  testWidgets('shows the Google Play button, every policy page link and the business details', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HomeSiteLinks())));

    expect(find.byKey(const ValueKey('site-google-play')), findsOneWidget);
    expect(find.text('Get the app on Google Play'), findsOneWidget);
    for (final path in ['/pricing', '/terms', '/refund-policy', '/privacy-policy', '/contact']) {
      expect(find.byKey(ValueKey('site-link-$path')), findsOneWidget);
    }
    expect(find.textContaining('Bollapragada Seshu (Sole Proprietor)'), findsOneWidget);
    expect(find.textContaining('+91 83284 32265'), findsOneWidget);
  });

  test('every page the strip links to exists under web/ and has no XX placeholder left', () {
    for (final (_, path) in HomeSiteLinks.pages) {
      final file = path == '/privacy-policy' ? File('web/privacy-policy.html') : File('web$path/index.html');
      expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
      expect(file.readAsStringSync().contains('XX'), isFalse, reason: '${file.path} still has an XX placeholder');
    }
  });
}
