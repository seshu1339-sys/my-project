import 'package:flutter/material.dart';

import '../data/store.dart';
import '../modules/payments/payments_module.dart';
import '../modules/plans/plans_module.dart';

/// Connects the Plans card to the payment module, which do not know each other. Until the admin has filled in the bank details the card
/// has no pay button and says payments will open soon.
class VendorPlansWithPayment extends StatefulWidget {
  const VendorPlansWithPayment({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;

  @override
  State<VendorPlansWithPayment> createState() => _VendorPlansWithPaymentState();
}

class _VendorPlansWithPaymentState extends State<VendorPlansWithPayment> {
  late final open = paymentsOpen(widget.store);

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: open,
    builder: (context, ready) => VendorPlansSection(
      store: widget.store,
      uid: widget.uid,
      onPay: ready.data == true ? (context, requestId) => openPayment(context, widget.store, requestId) : null,
    ),
  );
}
