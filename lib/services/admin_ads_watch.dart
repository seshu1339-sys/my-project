import '../data/store.dart';
import '../domain/admin_ads.dart';

/// The admin's ads by command (lib/domain/admin_ads.dart), the ones still running. The customer app and website read them once per
/// open, per place change and on pull to refresh, like the vendors' boxes (owner, 16 Nov 2026); the admin panel keeps them live.
Stream<List<AdminAd>> watchAdminAds(Store store) {
  final query = store.firestore.collection('adminAds').where('active', isEqualTo: true).limit(200);
  List<AdminAd> read(dynamic s) => [for (final d in s.docs) AdminAd.from(d.id as String, Map<String, dynamic>.from(d.data() as Map))];
  if (store.loadsOnce) return store.loadedOnce(() async => read(await query.get()));
  return query.snapshots().map(read);
}

/// The lowest price of [productName] at the shops this customer can see, or null (a "live rate" ad).
double? liveRateOf(Store store, String productName) {
  final want = productName.trim().toLowerCase();
  if (want.isEmpty) return null;
  final shops = store.shopsInReach();
  double? best;
  for (final p in store.entries('products')) {
    if (!p.active || !p.text('name').toLowerCase().contains(want)) continue;
    if (shops.isNotEmpty && !shops.contains(p.text('shopId'))) continue;
    final price = p.number('price');
    if (price > 0 && (best == null || price < best)) best = price;
  }
  return best;
}

/// A photo for a live-rate ad when it has none of its own: the item's catalog photo.
String rateItemPhoto(Store store, String productName) {
  final want = productName.trim().toLowerCase();
  for (final p in store.entries('products')) {
    if (p.text('name').toLowerCase().contains(want) && p.text('imageUrl').startsWith('http')) return p.text('imageUrl');
  }
  return '';
}
