import 'package:cloud_firestore/cloud_firestore.dart';

/// One offer as the administrator added it (a `wholesaleOffers` document).
class WholesaleOffer {
  const WholesaleOffer({required this.id, required this.name, required this.photoUrl, required this.price, required this.minQuantity, required this.validUntil, required this.wholesaler, required this.phone});

  factory WholesaleOffer.fromData(String id, Map<String, dynamic> data) => WholesaleOffer(
    id: id,
    name: data['name']?.toString() ?? '',
    photoUrl: data['photoUrl']?.toString() ?? '',
    price: (data['price'] as num?) ?? 0,
    minQuantity: data['minQuantity']?.toString() ?? '',
    validUntil: (data['validUntil'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
    wholesaler: data['wholesaler']?.toString() ?? '',
    phone: data['phone']?.toString() ?? '',
  );

  final String id, name, photoUrl, minQuantity, wholesaler, phone;
  final num price;
  final DateTime validUntil;
}

/// Where the offers come from.
abstract interface class WholesaleOffers {
  /// The offers still valid, soonest ending first. The rules let only active Premium vendors read them.
  Stream<List<WholesaleOffer>> watch();
}

class FirestoreWholesaleOffers implements WholesaleOffers {
  const FirestoreWholesaleOffers(this.database);
  final FirebaseFirestore database;

  @override
  Stream<List<WholesaleOffer>> watch() => database
      .collection('wholesaleOffers')
      .where('validUntil', isGreaterThan: Timestamp.now())
      .orderBy('validUntil')
      .snapshots()
      .map((snapshot) => [for (final doc in snapshot.docs) WholesaleOffer.fromData(doc.id, doc.data())]);
}
