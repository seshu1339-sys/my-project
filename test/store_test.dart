import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';

void main() {
  test('wishlist toggles on and off and persists across restarts', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    expect(store.wishlist, isEmpty);
    await store.toggleWishlist('p1');
    expect(store.wishlist, contains('p1'));
    await store.toggleWishlist('p2');
    expect(store.wishlist, containsAll(['p1', 'p2']));
    await store.toggleWishlist('p1');
    expect(store.wishlist, isNot(contains('p1')));
    expect(store.wishlist, contains('p2'));
    final restarted = Store();
    await restarted.init();
    expect(restarted.wishlist, {'p2'});
  });

  test('payment card saves, displays and can be removed, and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    expect(store.paymentLast4, isEmpty);
    await store.setPaymentCard('Visa', '4242');
    expect(store.paymentBrand, 'Visa');
    expect(store.paymentLast4, '4242');
    final restarted = Store();
    await restarted.init();
    expect(restarted.paymentBrand, 'Visa');
    expect(restarted.paymentLast4, '4242');
    await restarted.removePaymentCard();
    expect(restarted.paymentBrand, isEmpty);
    expect(restarted.paymentLast4, isEmpty);
    final afterRemoval = Store();
    await afterRemoval.init();
    expect(afterRemoval.paymentLast4, isEmpty);
  });

  test('language preference persists across restarts', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await store.setLanguage('hi');
    expect(store.language, 'hi');
    final restarted = Store();
    await restarted.init();
    expect(restarted.language, 'hi');
  });
}
