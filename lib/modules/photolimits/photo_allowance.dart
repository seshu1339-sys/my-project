import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/store.dart';

/// Photo limits module (functions/modules/photo-limits): every vendor has one shop photo (photo 1, not counted); a free vendor has 2
/// extra photos (or the admin's number), a paid vendor their plan's number. Extra shop photos and own item photos share them.
const freeExtraPhotosDefault = 2;
const planExtraPhotosDefault = 10;

/// How many extra photos a vendor may have and how many they use.
class PhotoAllowance {
  const PhotoAllowance({required this.extras, required this.used, required this.paid});
  final int extras, used;
  final bool paid;
  int get left => extras - used < 0 ? 0 : extras - used;
  bool get full => used >= extras;
  // The shop photo slots: photo 1 and one per extra photo.
  int get shopSlots => 1 + extras;
}

int? _n(Object? v) => v is num && v >= 0 && v <= 100 ? v.toInt() : null;

/// The same rule as functions/plan-gate.js vendorPhotoAllowance / vendorPhotosUsed.
PhotoAllowance photoAllowance({Map<String, dynamic>? gates, Map<String, dynamic>? premium, required Iterable<Map<String, dynamic>> shopPhotos, required Iterable<Map<String, dynamic>> itemPhotos, required DateTime now}) {
  final free = _n(gates?['freeExtraPhotos']) ?? freeExtraPhotosDefault;
  final ends = premium?['endsAt'];
  final paid = premium?['active'] == true && ends is Timestamp && ends.toDate().isAfter(now);
  final plan = _n(premium?['extraPhotos']) ?? planExtraPhotosDefault;
  bool live(Map<String, dynamic> d) => d['status'] == 'pending' || d['status'] == 'approved';
  final used = shopPhotos.where((d) => live(d) && (d['slot'] as num? ?? 0) >= 2).length + itemPhotos.where(live).length;
  return PhotoAllowance(extras: paid ? (plan > free ? plan : free) : free, used: used, paid: paid);
}

/// The vendor's allowance, live.
Stream<PhotoAllowance> watchPhotoAllowance(Store store, String uid) {
  final db = store.firestore;
  return db.collection('planServiceGates').doc('main').snapshots().asyncExpand((gates) => db.collection('vendorPremium').doc(uid).snapshots().asyncExpand(
        (premium) => db.collection('vendorShopPhotos').where('vendorId', isEqualTo: uid).snapshots().asyncExpand(
              (shop) => db.collection('vendorItemPhotos').where('vendorId', isEqualTo: uid).snapshots().map(
                    (items) => photoAllowance(
                      gates: gates.data(),
                      premium: premium.data(),
                      shopPhotos: [for (final d in shop.docs) d.data()],
                      itemPhotos: [for (final d in items.docs) d.data()],
                      now: DateTime.now(),
                    ),
                  ),
            ),
      ));
}
