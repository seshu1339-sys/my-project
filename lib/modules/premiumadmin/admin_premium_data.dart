import 'package:cloud_firestore/cloud_firestore.dart';

/// A wholesale offer as the admin edits it (a `wholesaleOffers` document).
class AdminWholesale {
  const AdminWholesale({required this.id, required this.name, required this.photoUrl, required this.price, required this.minQuantity, required this.validUntil, required this.wholesaler, required this.phone});

  factory AdminWholesale.fromData(String id, Map<String, dynamic> data) => AdminWholesale(
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

/// A vendor's Today's Offer as the admin sees it (a `vendorTodaysOffers` document).
class AdminVendorOffer {
  const AdminVendorOffer({required this.vendorId, required this.shopId, required this.photoUrl, required this.price, required this.endsAt});

  factory AdminVendorOffer.fromData(String id, Map<String, dynamic> data) => AdminVendorOffer(
    vendorId: id,
    shopId: data['shopId']?.toString() ?? '',
    photoUrl: data['photoUrl']?.toString() ?? '',
    price: (data['price'] as num?) ?? 0,
    endsAt: (data['endsAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  final String vendorId, shopId, photoUrl;
  final num price;
  final DateTime endsAt;
}

String premiumPrice(num price) => price == price.roundToDouble() ? '₹${price.round()}' : '₹${price.toStringAsFixed(2)}';

String premiumDate(DateTime date) => '${date.day}/${date.month}/${date.year}';
