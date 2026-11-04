import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';

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

  test('delivery charge follows the admin tiers for each shop and the old flat fee is ignored', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    final product = store
        .entries('products')
        .firstWhere((e) => e.text('name') == 'Farm-fresh vegetable box');
    store.add(product);
    expect(store.total, 249);
    expect(store.deliveryFee, 0);
    expect(store.grandTotal, 249);
    await store.save('settings', Entry('business', {...store.business.data, 'deliveryFee': 30}));
    expect(store.deliveryFee, 0, reason: 'the old flat fee is no longer used');
    final shopId = product.text('shopId');
    final shop = store.entries('shops').firstWhere((e) => e.id == shopId);
    await store.save('shops', Entry(shopId, {...shop.data, 'latitude': 17.027, 'longitude': 82.0}));
    store.latitude = 17.0;
    store.longitude = 82.0;
    await store.save('settings', Entry('business', {...store.business.data, 'deliveryFeeTiers': '5:10, 10:20', 'freeDeliveryAbove': 500}));
    expect(store.deliveryFee, 10);
    expect(store.grandTotal, 259);
    store.add(product, 2);
    expect(store.deliveryFee, 0, reason: 'above the free-delivery limit');
    expect(store.grandTotal, 249 * 3);
    store.cart.clear();
    store.add(product);
    await store.save('settings', Entry('business', {...store.business.data, 'deliveryFeeTiers': '1:10', 'freeDeliveryAbove': 0}));
    expect(store.deliveryParts.single.talkToVendor, isTrue, reason: 'past the last tier');
    expect(store.deliveryFee, 0);
    await store.save('shops', Entry(shopId, {...shop.data, 'latitude': 17.027, 'longitude': 82.0, 'freeDelivery': true}));
    expect(store.deliveryParts.single.talkToVendor, isFalse);
  });
}
