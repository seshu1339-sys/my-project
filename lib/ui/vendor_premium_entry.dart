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
        offerBox: StreamBuilder<TodaysOffer?>(
          stream: own,
          builder: (context, offer) {
            final running = offer.data;
            return TodaysOfferPanel(
              offer: running == null ? null : RunningOffer(photoUrl: running.photoUrl, price: running.price, endsAt: running.endsAt),
              hourOptions: todaysOfferHours,
              onSubmit: (result) => offers.submit(widget.uid, result.photo.file!, result.price, result.hours),
            );
          },
        ),
        largeBox: WholesaleBox(source: FirestoreWholesaleOffers(widget.store.firestore), onCall: _call),
      );
    },
  );
}
