// Shop and provider ratings in the apps (lib/ui/shop_ratings.dart): the label on lists and maps, the latest comments, and the Rate
// dialog (1 to 5 stars, a name, an optional comment). No phone number anywhere.
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/admin_settings.dart';
import 'package:ecommerce_app/ui/shop_ratings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const rated = Entry('s1', {
  'name': 'Ramu Kirana', 'ratingAvg': 4.25, 'ratingCount': 12,
  'ratingRecent': [{'name': 'Lakshmi', 'stars': 5, 'comment': 'Fresh vegetables'}, {'name': 'Ravi', 'stars': 3, 'comment': 'A bit slow'}],
});

void main() {
  test('the label shows the average and the count, or nothing before the first rating', () {
    expect(ratingLabel(rated), '★ 4.3 (12)');
    expect(ratingLabel(const Entry('s2', {'name': 'New shop'})), '');
    expect(ratingLabel(null), '');
    expect(recentRatings(rated).map((r) => r.name), ['Lakshmi', 'Ravi']);
    expect(stars(3), '★★★☆☆');
  });

  testWidgets('the shop shows its stars and latest comments; Rate sends stars, name and comment', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    final sent = <Map<String, dynamic>>[];
    // Signed out: the stars and comments show, no Rate button.
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RatingsSection(store: store, place: rated, target: const {'kind': 'shop', 'shopId': 's1'}, label: 'Ramu Kirana'))));
    expect(find.text('★ 4.3 (12)'), findsOneWidget);
    expect(find.textContaining('Lakshmi: Fresh vegetables'), findsOneWidget);
    expect(find.byKey(const ValueKey('rate-shop')), findsNothing);

    // The dialog itself (a signed-in customer's button).
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RateButton(store: store, target: const {'kind': 'shop', 'shopId': 's1'}, label: 'Ramu Kirana', send: (d) async => sent.add(d)))));
    await tester.tap(find.byKey(const ValueKey('rate-shop')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('rate-send'))).onPressed, isNull, reason: 'stars and a name are needed');
    await tester.tap(find.byKey(const ValueKey('rate-star-4')));
    await tester.enterText(find.byKey(const ValueKey('rate-name')), 'Sita');
    await tester.enterText(find.byKey(const ValueKey('rate-comment')), 'Good rice');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rate-send')));
    await tester.pumpAndSettle();
    expect(sent.single, {'kind': 'shop', 'shopId': 's1', 'stars': 4, 'name': 'Sita', 'comment': 'Good rice'});
    expect(sent.single.keys.any((k) => k.toLowerCase().contains('phone')), isFalse);
    expect(find.text('Thank you for your rating.'), findsOneWidget);
    store.dispose();
  });

  test('the admin finds Ratings in the settings search', () {
    expect(searchAdminSettings('ratings').first.sectionKey, 'ratings');
  });
}
