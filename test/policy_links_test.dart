import 'dart:io';

import 'package:ecommerce_app/ui/policy_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each app points at its own Privacy Policy page, and every page exists under web/', () {
    expect(PolicyLinks.privacyPath('user'), '/privacy');
    expect(PolicyLinks.privacyPath('vendor'), '/privacy-vendor');
    expect(PolicyLinks.privacyPath('staff'), '/privacy-staff');
    for (final role in ['user', 'vendor', 'staff']) {
      for (final (_, path) in PolicyLinks.pages(role)) {
        expect(File('web$path/index.html').existsSync(), isTrue, reason: 'web$path/index.html is missing for $role');
      }
    }
  });

  testWidgets('the vendor app shows privacy, terms, refund and contact; the customer app has no refund link', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PolicyLinks(appRole: 'vendor'))));
    for (final path in ['/privacy-vendor', '/terms', '/refund-policy', '/digital-delivery', '/contact']) {
      expect(find.byKey(ValueKey('policy-link-$path')), findsOneWidget, reason: path);
    }
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PolicyLinks(appRole: 'user'))));
    expect(find.byKey(const ValueKey('policy-link-/refund-policy')), findsNothing);
    expect(find.byKey(const ValueKey('policy-link-/privacy')), findsOneWidget);
    expect(find.byKey(const ValueKey('policy-link-/digital-delivery')), findsNothing);
  });
}
