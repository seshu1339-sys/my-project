import 'package:cloud_firestore/cloud_firestore.dart';

/// One payment as the vendor and the admin see it (a `paymentRequests` document).
class PaymentRequest {
  const PaymentRequest({required this.id, required this.uid, required this.label, required this.amount, required this.status, this.razorpayPaymentId = '', this.paidAt, this.refundedAmount = 0, this.failureReason = '', this.linkClosed = false});

  factory PaymentRequest.fromData(String id, Map<String, dynamic> data) => PaymentRequest(
    id: id,
    uid: data['uid']?.toString() ?? '',
    label: data['label']?.toString() ?? '',
    amount: (data['amount'] as num?) ?? 0,
    status: data['status']?.toString() ?? '',
    razorpayPaymentId: data['razorpayPaymentId']?.toString() ?? '',
    paidAt: data['paidAt'] is Timestamp ? (data['paidAt'] as Timestamp).toDate() : null,
    refundedAmount: (data['refundedAmount'] as num?) ?? 0,
    failureReason: (data['lastFailure'] is Map ? (data['lastFailure'] as Map)['reason'] : null)?.toString() ?? '',
    linkClosed: data['linkClosedAt'] != null && data['razorpayLinkUrl'] == null,
  );

  final String id, uid, label, status, razorpayPaymentId;
  final num amount, refundedAmount;
  // Why the last try failed (Razorpay's words), and whether the old payment link was closed so Pay will make a new one.
  final String failureReason;
  final bool linkClosed;
  final DateTime? paidAt;
}

/// What each status means, in the words the vendor and the admin see.
const paymentStatusWords = <String, String>{
  'awaiting_payment': 'Waiting for payment',
  'verified': 'Paid',
  'paid_after_cancel': 'Paid after it was cancelled: refund it',
  'refunded': 'Refunded',
  'cancelled': 'Cancelled',
};

String paymentMoney(num amount) => amount == amount.roundToDouble() ? '₹${amount.round()}' : '₹${amount.toStringAsFixed(2)}';
