import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/store.dart';
import 'todays_offer.dart';

/// The hours a vendor may choose from.
const todaysOfferHours = [24, 48];

/// What the rest of the app may do with Today's Offers.
abstract interface class TodaysOfferStore {
  /// The vendor's own offer, or null when they have none running.
  Stream<TodaysOffer?> watchOwn(String vendorId);

  /// Every running offer. Which of them a customer sees is decided where they are shown.
  Stream<List<TodaysOffer>> watchLive();

  /// Sends the photo and price; the server checks them and puts the offer live, replacing the vendor's old one.
  Future<void> submit(String vendorId, XFile photo, num price, int hours);
}

class FirestoreTodaysOfferStore implements TodaysOfferStore {
  const FirestoreTodaysOfferStore(this.store);
  final Store store;

  CollectionReference<Map<String, dynamic>> get _offers => store.firestore.collection('vendorTodaysOffers');

  @override
  Stream<TodaysOffer?> watchOwn(String vendorId) => _offers.doc(vendorId).snapshots().map((doc) {
    final data = doc.data();
    final offer = data == null ? null : TodaysOffer.fromData(doc.id, data);
    return offer != null && offer.liveAt(DateTime.now()) ? offer : null;
  });

  @override
  Stream<List<TodaysOffer>> watchLive() => _offers
      .where('endsAt', isGreaterThan: Timestamp.now())
      .orderBy('endsAt')
      .snapshots()
      .map((snapshot) => [for (final doc in snapshot.docs) TodaysOffer.fromData(doc.id, doc.data())]);

  @override
  Future<void> submit(String vendorId, XFile photo, num price, int hours) async {
    final photoUrl = await store.upload(photo, folder: 'vendorTodaysOffers/$vendorId');
    await store.call('submitTodaysOffer', {'photoUrl': photoUrl, 'price': price, 'hours': hours});
  }
}
