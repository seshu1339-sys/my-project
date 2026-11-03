import 'package:cloud_firestore/cloud_firestore.dart';

/// One payment as the vendor and the admin see it (a `paymentRequests` document).
class PaymentRequest {
  const PaymentRequest({required this.id, required this.uid, required this.label, required this.amount, required this.status, this.razorpayPaymentId = '', this.paidAt});

  factory PaymentRequest.fromData(String id, Map<String, dynamic> data) => PaymentRequest(
    id: id,
    uid: data['uid']?.toString() ?? '',
    label: data['label']?.toString() ?? '',
    amount: (data['amount'] as num?) ?? 0,
    status: data['status']?.toString() ?? '',
    razorpayPaymentId: data['razorpayPaymentId']?.toString() ?? '',
    paidAt: data['paidAt'] is Timestamp ? (data['paidAt'] as Timestamp).toDate() : null,
  );

  final String id, uid, label, status, razorpayPaymentId;
  final num amount;
  final DateTime? paidAt;
}

/// What each status means, in the words the vendor and the admin see.
const paymentStatusWords = <String, String>{
  'awaiting_payment': 'Waiting for payment',
  'verified': 'Paid',
  'paid_after_cancel': 'Paid after it was cancelled: refund it',
  'cancelled': 'Cancelled',
};

String paymentMoney(num amount) => amount == amount.roundToDouble() ? '₹${amount.round()}' : '₹${amount.toStringAsFixed(2)}';
