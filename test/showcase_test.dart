import 'package:ecommerce_app/modules/showcase/showcase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Showcase module (owner, 6 Nov 2026): the paid vendors' boxes take turns, never stay longer than the admin's seconds, and reach only
// customers within the plan's km.
void main() {
  final t0 = DateTime.fromMillisecondsSinceEpoch(30000 * 1000); // turn 6000 for 5-second turns: even, a multiple of 3
  DateTime at(int s) => t0.add(Duration(seconds: s));

  test('more vendors than boxes: a set at a time, every vendor gets a turn, then back to the first', () {
    final v = [for (var i = 1; i <= 7; i++) 'v$i'];
    expect(rotationPage(v, visible: 3, seconds: 5, now: at(0)), ['v1', 'v2', 'v3']);
    expect(rotationPage(v, visible: 3, seconds: 5, now: at(4)), ['v1', 'v2', 'v3'], reason: 'still the same turn');
    expect(rotationPage(v, visible: 3, seconds: 5, now: at(5)), ['v4', 'v5', 'v6']);
    expect(rotationPage(v, visible: 3, seconds: 5, now: at(10)), ['v7']);
    expect(rotationPage(v, visible: 3, seconds: 5, now: at(15)), ['v1', 'v2', 'v3']);
  });

  test('as many or fewer vendors than boxes: every other turn shows the fillers, so no box stays longer than the seconds', () {
    expect(rotationPage(['v1', 'v2'], visible: 6, seconds: 10, now: at(0), fillers: ['p1']), ['v1', 'v2']);
    expect(rotationPage(['v1', 'v2'], visible: 6, seconds: 10, now: at(10), fillers: ['p1']), ['p1']);
    expect(rotationPage(['v1', 'v2'], visible: 6, seconds: 10, now: at(20), fillers: ['p1']), ['v1', 'v2']);
    expect(rotationPage(<String>[], visible: 6, seconds: 10, now: at(0), fillers: ['p1', 'p2']), ['p1', 'p2']);
    expect(untilNextTurn(5, at(2)), const Duration(seconds: 3));
  });

  test('a box reaches only customers within the plan km of the shop; an unknown place sees none', () {
    const silver = ShowcaseEntry(vendorId: 'v', shopId: 's', shopName: 'S', photoUrl: 'https://x', radiusKm: 5, active: true);
    expect(withinReach(silver, lat: 17.68, lng: 82.62, shopLat: 17.668, shopLng: 82.612), isTrue, reason: 'about 1.5 km');
    expect(withinReach(silver, lat: 17.75, lng: 82.70, shopLat: 17.668, shopLng: 82.612), isFalse, reason: 'about 13 km');
    const premium = ShowcaseEntry(vendorId: 'v', shopId: 's', shopName: 'S', photoUrl: 'https://x', radiusKm: 50, active: true);
    expect(withinReach(premium, lat: 17.75, lng: 82.70, shopLat: 17.668, shopLng: 82.612), isTrue);
    expect(withinReach(premium, shopLat: 17.668, shopLng: 82.612), isFalse);
  });

  testWidgets('the vendor picks the ad box photo from their shop photos; a free vendor sees that it comes with a plan', (tester) async {
    final chosen = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VendorShowcaseView(paid: true, radiusKm: 15, photos: const ['https://a/1', 'https://a/2'], chosen: 'https://a/1', onChoose: (u) async => chosen.add(u)))));
    expect(find.textContaining('within 15 km'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('showcase-photo-1')));
    await tester.pump();
    expect(chosen, ['https://a/2']);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VendorShowcaseView(paid: false, photos: const [], onChoose: (_) async {}))));
    expect(find.byKey(const ValueKey('showcase-paid-only')), findsOneWidget);
  });
}
