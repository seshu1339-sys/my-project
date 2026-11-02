import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import 'payment_page.dart';

/// The payment module: shows a vendor where to pay and takes the screenshot. The server does the checking. It knows nothing about plans; any
/// module can ask for a payment by making a `paymentRequests` document and opening [openPayment] with its id.
const paymentsRoute = '/payments';

/// True once the admin has filled in every bank detail, so payments can open.
Stream<bool> paymentsOpen(Store store) => store.firestore.collection('paymentBankPublic').doc('main').snapshots().map((DocumentSnapshot<Map<String, dynamic>> doc) => doc.data()?['ready'] == true);

Future<void> openPayment(BuildContext context, Store store, String requestId) => Navigator.of(context).push(
  MaterialPageRoute<void>(settings: const RouteSettings(name: paymentsRoute), builder: (_) => PaymentPage(store: store, requestId: requestId)),
);
