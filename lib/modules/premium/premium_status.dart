import 'package:cloud_firestore/cloud_firestore.dart';

/// Tells whether a vendor is Premium, and keeps telling when it changes.
abstract interface class PremiumStatus {
  Stream<bool> watch(String vendorId);
}

/// Reads the vendor's `vendorPremium` document, which only the server writes (functions/modules/premium-status).
class FirestorePremiumStatus implements PremiumStatus {
  const FirestorePremiumStatus(this.database);
  final FirebaseFirestore database;

  @override
  Stream<bool> watch(String vendorId) => database.collection('vendorPremium').doc(vendorId).snapshots().map((doc) => doc.data()?['active'] == true);
}
