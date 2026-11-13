import '../domain/post_duration.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';
import '../modules/offerstore/offerstore_module.dart';
import '../modules/premium/premium_module.dart';
import '../modules/premiumscreen/premiumscreen_module.dart';
import '../modules/wholesale/wholesale_module.dart';

/// Connects the Premium modules in the vendor app, which do not know each other: the status decides whether anything shows, the screen is
/// given the offer store and the wholesale box. A vendor who is not Premium gets nothing at all here.
class VendorPremiumEntry extends StatefulWidget {
  const VendorPremiumEntry({super.key, required this.store, required this.uid, this.status});
  final Store store;
  final String uid;

  /// The Premium answer; the server's unless a test gives another.
  final PremiumStatus? status;

  @override
  State<VendorPremiumEntry> createState() => _VendorPremiumEntryState();
}

class _VendorPremiumEntryState extends State<VendorPremiumEntry> {
  late final premium = (widget.status ?? FirestorePremiumStatus(widget.store.firestore)).watch(widget.uid);

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: premium,
    builder: (context, snapshot) {
      if (snapshot.data != true) return const SizedBox.shrink();
      return PremiumEntryCard(
        onOpen: () => Navigator.of(context).push(
          MaterialPageRoute<void>(settings: const RouteSettings(name: premiumscreenRoute), builder: (_) => VendorPremiumPage(store: widget.store, uid: widget.uid)),
        ),
      );
    },
  );
}

class VendorPremiumPage extends StatefulWidget {
  const VendorPremiumPage({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;

  @override
  State<VendorPremiumPage> createState() => _VendorPremiumPageState();
}

class _VendorPremiumPageState extends State<VendorPremiumPage> {
  late final premium = FirestorePremiumStatus(widget.store.firestore).watch(widget.uid);
  late final offers = FirestoreTodaysOfferStore(widget.store);
  late final own = offers.watchOwn(widget.uid);
  // The plan's number of boxes and the vendor's own items (an item's photo is what its box shows).
  late final plan = widget.store.firestore.collection('vendorPremium').doc(widget.uid).snapshots();
  late final items = widget.store.firestore.collection('products').where('ownerId', isEqualTo: widget.uid).snapshots();

  Future<void> _call(String phone) async {
    try {
      if (await launchUrl(Uri(scheme: 'tel', path: phone), mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Falls through to the message below.
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not start the call.')));
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: premium,
    builder: (context, status) {
      if (status.data == false) return const PremiumEndedScreen();
      return PremiumOfferScreen(
        offerBox: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: plan,
          builder: (context, premium) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: items,
            builder: (context, products) => StreamBuilder<List<TodaysOffer>>(
              stream: own,
              builder: (context, running) => TodaysOfferPanel(
                boxes: todaysOfferBoxesOf(premium.data?.data()),
                offers: [
                  for (final o in running.data ?? const <TodaysOffer>[])
                    RunningOffer(photoUrl: o.photoUrl, price: o.price, endsAt: o.endsAt, slot: o.slot, productId: o.productId, name: o.name, days: o.days),
                ],
                items: [
                  for (final d in products.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                    if (d.data()['active'] != false && '${d.data()['imageUrl'] ?? ''}'.startsWith('http'))
                      OfferItemChoice(id: d.id, name: '${d.data()['name'] ?? ''}', photoUrl: '${d.data()['imageUrl']}', price: d.data()['price'] as num?),
                ],
                dayOptions: todaysOfferDays,
                durationNote: postDurationNotice(widget.store.business),
                onSubmit: (r) => offers.submit(productId: r.productId, price: r.price, days: r.days, slot: r.slot),
                onRemove: offers.remove,
              ),
            ),
          ),
        ),
        largeBox: WholesaleBox(source: FirestoreWholesaleOffers(widget.store.firestore), onCall: _call),
      );
    },
  );
}
