import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/store.dart';
import 'todays_offer.dart';

/// How long a vendor may show an item in Today's Offers (owner, 7 Nov 2026), in days, with the words the vendor reads.
const todaysOfferDays = <int, String>{7: '1 week', 30: '1 month', 60: '2 months', 90: '3 months'};

/// Today's Offers boxes a plan gives when the plan has no number of its own (functions/modules/todays-offer/rules.js).
int todaysOfferBoxesOf(Map<String, dynamic>? premium) {
  final n = premium?['offerBoxes'];
  if (n is num && n == n.roundToDouble() && n >= 0 && n <= 20) return n.toInt();
  return switch (premium?['tier']) { 'silver' => 1, 'gold' => 3, _ => 5 };
}

/// What the rest of the app may do with Today's Offers.
abstract interface class TodaysOfferStore {
  /// The vendor's own running boxes, box 1 first.
  Stream<List<TodaysOffer>> watchOwn(String vendorId);

  /// Every running offer. Which of them a customer sees is decided where they are shown.
  Stream<List<TodaysOffer>> watchLive();

  /// Puts one of the vendor's items in a box (the server checks it and puts it live at once). [slot] replaces that box.
  Future<void> submit({required String productId, required num price, required int days, int? slot});

  /// Takes one of the vendor's boxes down.
  Future<void> remove(int slot);
}

class FirestoreTodaysOfferStore implements TodaysOfferStore {
  const FirestoreTodaysOfferStore(this.store);
  final Store store;

  CollectionReference<Map<String, dynamic>> get _offers => store.firestore.collection('vendorTodaysOffers');

  @override
  Stream<List<TodaysOffer>> watchOwn(String vendorId) => _offers.where('vendorId', isEqualTo: vendorId).snapshots().map((snapshot) {
    final now = DateTime.now();
    return [for (final doc in snapshot.docs) TodaysOffer.fromData(doc.id, doc.data())].where((o) => o.liveAt(now)).toList()..sort((a, b) => a.slot.compareTo(b.slot));
  });

  @override
  Stream<List<TodaysOffer>> watchLive() => _offers
      .where('endsAt', isGreaterThan: Timestamp.now())
      .orderBy('endsAt')
      .snapshots()
      .map((snapshot) => [for (final doc in snapshot.docs) TodaysOffer.fromData(doc.id, doc.data())]);

  @override
  Future<void> submit({required String productId, required num price, required int days, int? slot}) =>
      store.call('submitTodaysOffer', {'productId': productId, 'price': price, 'days': days, 'slot': ?slot});

  @override
  Future<void> remove(int slot) => store.call('removeMyTodaysOffer', {'slot': slot});
}
