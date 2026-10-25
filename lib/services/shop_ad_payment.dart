import 'package:flutter/widgets.dart';

/// How a vendor pays for an ad for their shop (the "Ad for your shop" section of the vendor app).
///
/// Today the office arranges every shop ad, and its payment, offline ([OfflineShopAdPayment]): the vendor ticks "I want an ad for my
/// shop", the office calls them, takes the payment and the photo, and links a Right Side Ad Box to the vendor (functions/shop-ads.js).
/// An in-app payment is added later as another ShopAdPayment (its [payLabel] shows a button, [pay] opens the payment, and a server call
/// starts the ad once it is paid) and passed to the section; the ads and how their views are counted stay as they are.
abstract class ShopAdPayment {
  const ShopAdPayment();

  /// Stored with each ad (rightBoxAds.payment).
  String get id;

  /// What the vendor is told once they want an ad.
  String get howItWorks;

  /// The button that starts paying in the app, or null when the vendor does not pay in the app.
  String? get payLabel => null;

  Future<void> pay(BuildContext context) async {}
}

/// The office calls the vendor and takes the payment outside the app.
class OfflineShopAdPayment extends ShopAdPayment {
  const OfflineShopAdPayment();

  @override
  String get id => 'offline';

  @override
  String get howItWorks =>
      'Our office will call you about the price, the photo for your ad and the payment. Once it is arranged, your ad shows in the boxes on the right side of the website.';
}
