import 'store.dart';

/// Thin RPC wrappers around the generic `Store.call(name, data)` passthrough
/// — the actions a vendor (or a complaint-filer) takes. Extension methods so
/// every call site (vendor.dart, field.dart, account.dart, details.dart) is
/// unchanged — `store.registerVendor(...)` etc. call identically whether
/// these are instance methods or extension methods.
extension StoreVendorActions on Store {
  Future<String> registerVendor({
    required String ownerName,
    required String phone,
    required String name,
    required String shopCategory,
    required String address,
    required String pincode,
    required String description,
    required double latitude,
    required double longitude,
  }) async {
    final result = await call('registerVendor', {
      'ownerName': ownerName,
      'phone': phone,
      'name': name,
      'shopCategory': shopCategory,
      'address': address,
      'pincode': pincode,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
    });
    return result['status'] as String;
  }

  Future<String> updateVendorOrder(String orderId, String status) async {
    final result = await call('updateVendorOrder', {'orderId': orderId, 'status': status});
    return result['status'] as String;
  }

  Future<String> submitVendorFeePayment(String paymentReference) async {
    final result = await call('submitVendorFeePayment', {'paymentReference': paymentReference});
    return result['status'] as String;
  }

  Future<String> submitVendorChange({required String type, required String collection, required String docId, required Map<String, dynamic> changes}) async {
    final result = await call('submitVendorChange', {'type': type, 'collection': collection, 'docId': docId, 'changes': changes});
    return result['status'] as String;
  }

  Future<String> issuePurchaseCode(String orderId, {required double latitude, required double longitude}) async {
    final result = await call('issuePurchaseCode', {'orderId': orderId, 'latitude': latitude, 'longitude': longitude});
    return result['code'] as String;
  }

  Future<String> createComplaint({String? orderId, String? productId, String? vendorId, required String subject, required String description}) async {
    final result = await call('createComplaint', {'orderId': orderId, 'productId': productId, 'vendorId': vendorId, 'subject': subject, 'description': description});
    return result['complaintId'] as String;
  }

  Future<void> addComplaintMessage(String complaintId, String body) async {
    await call('addComplaintMessage', {'complaintId': complaintId, 'body': body});
  }
}
