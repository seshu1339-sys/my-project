import 'package:flutter/material.dart';

import '../data/store.dart';
import 'app_bottom_ad.dart';
import 'vendor_plans_payment.dart';

/// The plans screen of the vendor app (owner, 13 Nov 2026): the plans side by side, Upgrade / Renew starting the payment at once. While it
/// is open the ad box at the bottom is about 30% of the screen's height; everywhere else it stays small.
class VendorPlansPage extends StatefulWidget {
  const VendorPlansPage({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;

  @override
  State<VendorPlansPage> createState() => _VendorPlansPageState();
}

class _VendorPlansPageState extends State<VendorPlansPage> {
  @override
  void initState() {
    super.initState();
    // After this frame: the ad box rebuilds, which must not happen while the page is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) => appBottomAdTall.value = true);
  }

  @override
  void dispose() {
    Future.microtask(() => appBottomAdTall.value = false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Plans')),
    body: ListView(padding: const EdgeInsets.all(16), children: [VendorPlansWithPayment(store: widget.store, uid: widget.uid)]),
  );
}

/// Opens the plans screen.
Future<void> openVendorPlans(BuildContext context, Store store, String uid) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => VendorPlansPage(store: store, uid: uid)));
