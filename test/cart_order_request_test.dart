// The cart sends an order request to the vendor: the app does not deliver or take money. The delivery charge is the admin's, by distance
// and per shop, and is paid to the vendor. Our own delivery promises (badges, ads, pay on delivery) stay hidden behind a flag.
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/feature_flags.dart';
import 'package:ecommerce_app/ui/cart_page.dart';
import 'package:ecommerce_app/ui/home_footer_badges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Store> _storeWithTiers({String tiers = '5:10, 10:20'}) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  final product = store.entries('products').firstWhere((e) => e.text('name') == 'Farm-fresh vegetable box');
  final shop = store.entries('shops').firstWhere((e) => e.id == product.text('shopId'));
  await store.save('shops', Entry(shop.id, {...shop.data, 'latitude': 17.027, 'longitude': 82.0, 'phone': '9876543210'}));
  await store.save('settings', Entry('business', {...store.business.data, 'deliveryFeeTiers': tiers}));
  store.latitude = 17.0;
  store.longitude = 82.0;
  store.add(product);
  return store;
}

Future<void> _pump(WidgetTester tester, Store store, {String language = 'en'}) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: Locale(language),
    supportedLocales: [Locale(language)],
    localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
    home: CartPage(store: store),
  ));
  await tester.pump();
}

void main() {
  test('the delivery promises are hidden for now', () {
    expect(showDeliveryPromises, isFalse);
  });

  testWidgets('the cart shows the admin delivery charge, who it is paid to, an Address field, a phone field and the new button', (tester) async {
    final store = await _storeWithTiers();
    await _pump(tester, store);
    expect(find.text('Delivery fee ₹10'), findsOneWidget);
    expect(find.text('This charge and the price of the items are paid to the vendor directly. The app does not take any money.'), findsOneWidget);
    expect(find.text('Address'), findsOneWidget);
    expect(find.text('Delivery / service address'), findsNothing);
    expect(find.byKey(const ValueKey('cart-phone')), findsOneWidget);
    expect(find.text('Preview checkout'), findsOneWidget, reason: 'the demo store has no live order button');
    expect(find.text('Cash on delivery'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('past the last distance the cart sends the customer to the vendor instead of showing a charge', (tester) async {
    final store = await _storeWithTiers(tiers: '1:10');
    await _pump(tester, store);
    expect(find.textContaining('agreed with the vendor by phone'), findsOneWidget);
    expect(find.textContaining('Delivery fee'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('without a known place the cart asks to turn location on instead of guessing a charge', (tester) async {
    final store = await _storeWithTiers();
    store.latitude = null;
    store.longitude = null;
    await _pump(tester, store);
    expect(find.text('Turn on your location to see the delivery charge.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('the cart speaks Telugu: the charge note and the labels', (tester) async {
    final store = await _storeWithTiers();
    await _pump(tester, store, language: 'te');
    expect(find.text('ఈ ఛార్జీ మరియు సరుకు డబ్బు వెండర్‌కే నేరుగా చెల్లించాలి. యాప్ డబ్బు తీసుకోదు.'), findsOneWidget);
    expect(find.text('చిరునామా'), findsOneWidget);
    expect(find.text('మీ ఫోన్ నంబర్'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('the footer hides our own delivery and pay-on-delivery badges', (tester) async {
    final store = await _storeWithTiers();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: HomeFooterBadges(settings: store.entries('settings'))))));
    expect(find.text('Fast & Safe Delivery'), findsNothing);
    expect(find.text('Pay on Delivery'), findsNothing);
    expect(find.text('Best Prices Always'), findsOneWidget);
    store.dispose();
  });

  test('the starter delivery ads are switched off', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    final ads = store.entries('promotions').where((e) => e.id == 'ad2' || e.id == 'ad3');
    expect(ads, isNotEmpty);
    expect(ads.every((ad) => ad.data['active'] == false), isTrue);
  });
}
