import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The privacy policy is a plain public page (web/privacy-policy.html) and a PDF of it, served by the customer Hosting target at
// /privacy-policy and /privacy-policy.pdf with no sign-in. The Play Console link points here, so these must not quietly disappear.
void main() {
  final html = File('web/privacy-policy.html').readAsStringSync();

  test('the page exists and says what a store listing needs it to say', () {
    expect(html, contains('<title>Privacy Policy'));
    for (final topic in ['Information we collect', 'How we use information', 'Who we share it with', 'How long we keep it', 'Your choices and rights', 'Children', 'Contact', 'Delete my account']) {
      expect(html, contains(topic), reason: topic);
    }
    expect(html, contains('info@locamarket.in'));
    expect(html, contains('/privacy-policy.pdf'));
    expect(html.toLowerCase(), isNot(contains('<form')), reason: 'a public page with nothing to sign in to');
  });

  test('the PDF is a real PDF', () {
    final bytes = File('web/privacy-policy.pdf').readAsBytesSync();
    expect(latin1.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(20000));
  });

  test('the customer site serves /privacy-policy before the catch-all rewrite to the app', () {
    final config = jsonDecode(File('firebase.json').readAsStringSync()) as Map<String, dynamic>;
    final customer = (config['hosting'] as List).cast<Map<String, dynamic>>().firstWhere((h) => h['target'] == 'customer');
    final rewrites = (customer['rewrites'] as List).cast<Map<String, dynamic>>();
    final sources = rewrites.map((r) => r['source']).toList();
    expect(sources.indexOf('/privacy-policy'), isNonNegative);
    expect(sources.indexOf('/privacy-policy'), lessThan(sources.indexOf('**')));
    expect(rewrites.firstWhere((r) => r['source'] == '/privacy-policy')['destination'], '/privacy-policy.html');
    expect(sources.last, '**');
  });

  test('the delete-data page for the Play Console exists, needs no sign-in, and is served before the app catch-all', () {
    final page = File('web/delete-account.html').readAsStringSync();
    expect(page, contains('Delete my account'));
    expect(page, contains('info@locamarket.in'));
    expect(page, contains('30 days'));
    expect(page, contains('What we delete'));
    expect(page, contains('What we may keep'));
    expect(page.toLowerCase(), isNot(contains('<form')));
    expect(html, contains('/delete-account'), reason: 'the policy links to it');
    final config = jsonDecode(File('firebase.json').readAsStringSync()) as Map<String, dynamic>;
    final customer = (config['hosting'] as List).cast<Map<String, dynamic>>().firstWhere((h) => h['target'] == 'customer');
    final sources = [for (final r in (customer['rewrites'] as List).cast<Map<String, dynamic>>()) r['source']];
    expect(sources.indexOf('/delete-account'), lessThan(sources.indexOf('**')));
  });
}
