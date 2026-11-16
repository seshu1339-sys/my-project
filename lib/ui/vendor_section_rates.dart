import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/vendor_items.dart';
import '../services/usage.dart';
import 'vendor_section_kit.dart';

/// The FCM topic of every vendor app (functions/vendor-rates.js): the daily "Are today's rates the same?" goes to it as ONE message.
const vendorRatesTopic = 'vendors';

/// "Are today's rates the same?" on the vendor app's home (owner, 16 Nov 2026). "Yes, same rates" saves one time on the vendor (and its
/// shop), and customers see the green "Today's rate" tick next to every price of the shop for 24 hours; a price the vendor changes gets
/// the tick by itself. The vendor app also joins the vendors' topic here, for the daily reminder (the Android app; a browser cannot).
class VendorRatesCard extends StatefulWidget {
  const VendorRatesCard({super.key, required this.store, required this.uid, this.joinTopic});
  final Store store;
  final String uid;
  // For tests: what joining the topic does (the real one asks Firebase Messaging).
  final Future<void> Function(String topic)? joinTopic;
  @override
  State<VendorRatesCard> createState() => _VendorRatesCardState();
}

class _VendorRatesCardState extends State<VendorRatesCard> with VendorSectionState {
  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    final join = widget.joinTopic ?? (store.live && !kIsWeb ? FirebaseMessaging.instance.subscribeToTopic : null);
    if (join != null) join(vendorRatesTopic).catchError((Object _) {});
  }

  Future<void> _confirm() async {
    Usage.button('vendor_same_rates');
    await store.call('confirmTodaysRates', const {});
    toast("Thank you. Customers see the Today's rate tick on your prices for 24 hours.");
  }

  @override
  Widget build(BuildContext context) {
    if (!store.live) return _card(context, '');
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('vendors').doc(widget.uid).snapshots(),
      builder: (context, snapshot) => _card(context, '${snapshot.data?.data()?['ratesConfirmedAt'] ?? ''}'),
    );
  }

  Widget _card(BuildContext context, String confirmedAt) {
    final at = DateTime.tryParse(confirmedAt);
    final now = DateTime.now();
    final fresh = vendorPriceToday(const {}, now, ratesConfirmedAt: confirmedAt);
    final until = at?.add(const Duration(hours: vendorTodaysRateHours)).toLocal();
    return vendorCard("Are today's rates the same?", [
      if (fresh && until != null)
        Text("✓ Today's rate is shown on your prices until ${TimeOfDay.fromDateTime(until).format(context)}.", key: const ValueKey('vendor-rates-fresh'), style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
      FilledButton.icon(
        key: const ValueKey('vendor-same-rates'),
        onPressed: busy ? null : () => run(_confirm),
        icon: const Icon(Icons.check_circle_outline),
        label: const Text('Yes, same rates'),
      ),
    ], note: "If a price changed, update it in your items below: a new price gets the Today's rate tick by itself.");
  }
}
