import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/ads.dart';
import '../domain/catalog.dart';
import '../domain/today_offers.dart';
import '../domain/reach.dart';
import '../modules/offerdisplay/offerdisplay_module.dart';
import '../modules/offerrotation/offerrotation_module.dart';
import '../modules/offerstore/offerstore_module.dart';
import '../modules/showcase/showcase_module.dart';
import '../services/ad_tracker.dart';
import '../services/analytics.dart';
import '../services/server_clock.dart';
import '../services/strings.dart';
import 'ad_box.dart';
import 'design_tokens.dart';
import 'home_hero_carousel.dart';
import 'home_impression_once.dart';
import 'home_vendor_offers.dart';
import 'right_ad_boxes.dart' show SeenCounter;
import 'shared.dart';
import 'shop_route_map.dart';

/// One thing the carousel goes through: a promotion as it is, or an offer drawn inside a box's look.
class _Box {
  const _Box({this.promotion, this.offer});
  final Entry? promotion;
  final Widget Function(Entry look, int index)? offer;
}

/// Today's Offers on the home page: the coloured boxes (lib/domain/today_offers.dart). All live offers make one list, the admin's item
/// offers first and then the vendors' offers in the customer's circle (lib/modules/offerrotation). The carousel shows them set by set and
/// loops, at the Today's Offers speed the admin set; with few enough to fit they stay put. An admin offer shows its colour as a frame round a
/// white inside with "Today's Offer" across the top, the item's photo big on the left and its name and offer price on the right; a tap
/// opens the shop on the map straight away (its place, the road and its phone). A vendor offer shows only its photo and price, and a tap
/// opens the shop's page. Boxes left over show their Today's Offers Box promotion as before (so the town, pincode and area boxes keep
/// working); the boxes change by themselves when an offer starts or ends.
class TodayOffersSection extends StatefulWidget {
  const TodayOffersSection({
    super.key,
    required this.store,
    required this.boxes,
    this.looks,
    this.appearance = const Entry('', {}),
    this.reverse = false,
    this.speed = 600,
    this.showAll = false,
    this.onPromotion,
    this.empty,
    this.vendorOffers,
    this.adsAt,
    this.showcase,
    this.visible = todayOfferBoxCount,
    this.seconds = 5,
  });
  final Store store;

  /// The paid vendors' reach (lib/modules/showcase): a vendor's box shows only to customers within their plan's km. Null: from Firestore.
  final Stream<Map<String, ShowcaseEntry>>? showcase;

  /// How many boxes show at once (Android 2, website 6), and how many seconds each vendor's box stays before the next ones come.
  final int visible, seconds;

  /// The live ads of the Ads list for this customer at a time (lib/domain/ads.dart liveAds): they go round after the offers. Null = none.
  final List<Entry> Function(DateTime now)? adsAt;

  /// Shown instead when there is nothing at all to put in the boxes.
  final Widget? empty;

  /// Where vendor offers come from; the offer store unless a test gives another.
  final Stream<List<TodaysOffer>>? vendorOffers;

  /// Opens a promotion's target (the boxes before any item offer is set).
  final void Function(String target)? onPromotion;

  /// The Today's Offers Box promotions this customer may see (of a shop within reach), shown in boxes no offer fills.
  final List<Entry> boxes;

  /// The Today's Offers Box promotions whose colours the 6 boxes take, in their order, whether or not they are shown ([boxes] when
  /// null): a box's look is not an offer.
  final List<Entry>? looks;
  final Entry appearance;
  final bool reverse, showAll;
  final double speed;

  @override
  State<TodayOffersSection> createState() => _TodayOffersSectionState();
}

class _TodayOffersSectionState extends State<TodayOffersSection> {
  Timer? _next;
  DateTime? _nextAt;
  Timer? _turn;
  late final Stream<Map<String, ShowcaseEntry>>? _showcase = widget.showcase ?? (widget.store.live ? watchShowcase(widget.store) : null);

  @override
  void dispose() {
    _next?.cancel();
    _turn?.cancel();
    super.dispose();
  }

  /// The vendors' boxes take turns: build again when the next turn starts.
  void _nextTurn(DateTime now) {
    _turn?.cancel();
    _turn = Timer(untilNextTurn(widget.seconds, now) + const Duration(milliseconds: 50), () {
      if (mounted) setState(() {});
    });
  }

  /// The paid vendors' offers this customer may see: within the vendor's plan km of the shop (owner, 6 Nov 2026; the plans keep
  /// their own km, 11 Nov 2026). Without the plans' records, the vendors within the admin's km; without the customer's place, none.
  List<TodaysOffer> _reachable(List<TodaysOffer> running, Map<String, ShowcaseEntry>? reach, DateTime now) {
    final lat = widget.store.latitude, lng = widget.store.longitude;
    if (reach == null || !widget.store.located) return vendorOffersForCustomer(running, widget.store.shopsInReach(), now);
    final shops = {for (final s in widget.store.entries('shops')) s.id: s};
    return [
      for (final o in running)
        if (o.liveAt(now) && (reach[o.vendorId]?.liveAt(now) ?? false))
          if (withinReach(reach[o.vendorId]!, lat: lat, lng: lng, shopLat: shops[o.shopId]?.number('latitude'), shopLng: shops[o.shopId]?.number('longitude'))) o,
    ]..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
  }

  /// A tap on a vendor's box: straight to the shop on the map, its address and the way there (app and website alike).
  void _openVendor(TodaysOffer offer) {
    final shop = widget.store.entries('shops').where((s) => s.id == offer.shopId).firstOrNull;
    showShopRoute(context, ShopStop.shop(shop, shopId: offer.shopId, itemPhoto: offer.photoUrl, price: offer.price.toDouble()));
  }

  /// Builds again when the next offer starts or ends.
  void _wake(DateTime? at, DateTime now) {
    if (at == _nextAt) return;
    _next?.cancel();
    _nextAt = at;
    if (at == null) return;
    final wait = at.difference(now) + const Duration(seconds: 1);
    if (wait > const Duration(days: 20)) return;
    _next = Timer(wait, () {
      if (mounted) setState(() => _nextAt = null);
    });
  }

  /// Distance only (lib/domain/reach.dart): the admin's item offers of the shops within the admin's km; one without a shop never.
  bool _inReach(Entry offer, Set<String> shops) => widget.showAll || widget.store.showsEverything || shops.contains(linkedShopId(offer));

  void _open(Entry offer) {
    Analytics.click(offer);
    final shopId = offer.text('shopId');
    final shop = widget.store.entries('shops').where((s) => s.id == shopId).firstOrNull;
    showShopRoute(context, ShopStop.shop(shop, shopId: shopId, itemName: offer.text('name'), itemPhoto: offer.text('imageUrl'), price: offer.number('offerPrice'), unit: offer.text('unit')));
  }

  _Box _vendorBox(TodaysOffer offer) => _Box(
    offer: (look, i) {
      final inner = max(clampedNumber(look, 'radius', 20, 0, 80) - VendorOfferBox.frameWidth, 6.0);
      return VendorOfferBox(
        key: ValueKey('vendor-offer-box-${i + 1}'),
        photoUrl: offer.photoUrl,
        price: offer.price == offer.price.roundToDouble() ? '₹${offer.price.round()}' : '₹${offer.price.toStringAsFixed(2)}',
        frame: entryDecoration(look, fallback: AppTokens.primaryLight),
        colour: colorFromHex(look.text('backgroundColor'), AppTokens.primary),
        radius: inner,
        note: offer.note,
        onTap: () => _openVendor(offer),
      );
    },
  );

  /// An ad of the Ads list in a box: the box's colour as a frame, the ad (photo and / or text) inside; a tap opens what the ad links to.
  /// Its views count like the ad's views anywhere else (functions/ad-tracking.js).
  _Box _adBox(Entry ad) => _Box(
    offer: (look, i) => SeenCounter(
      adId: ad.id,
      tracker: AdsTracker.instance,
      town: widget.store.town,
      child: Container(
        key: ValueKey('today-ad-box-${ad.id}'),
        decoration: entryDecoration(look, fallback: AppTokens.primaryLight),
        padding: const EdgeInsets.all(TodayOfferBox.frame),
        child: AdBox(
          ad: ad,
          config: AdsConfig.from(widget.store.entries('settings')),
          onTap: (a) {
            AdsTracker.instance?.tap(a.id, town: widget.store.town);
            final target = adTarget(a);
            if (target.isNotEmpty) widget.onPromotion?.call(target);
          },
        ),
      ),
    ),
  );

  /// The earlier of the next admin offer change, the next vendor offer end and the next ad start or end.
  DateTime? _nextChange(List<Entry> adminOffers, List<TodaysOffer> vendorOffers, DateTime now) {
    final times = [?nextTodayOfferChange(adminOffers, now), for (final o in vendorOffers) o.endsAt, ?nextAdChange(widget.store.entries('ads'), now)];
    return times.isEmpty ? null : times.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Map<String, ShowcaseEntry>>(
    stream: _showcase,
    builder: (context, reach) => VendorOffersFeed(
      store: widget.store,
      source: widget.vendorOffers,
      builder: (context, running) => ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          // The server's time, never the phone's (lib/services/server_clock.dart).
          final now = ServerClock.now();
          final shops = widget.store.shopsInReach();
          final adminOffers = widget.store.entries('promotions').where((o) => isTodayOffer(o) && o.active && _inReach(o, shops)).toList();
          final vendorOffers = _reachable(running, _showcase == null ? null : reach.data, now);
          final ads = widget.adsAt?.call(now) ?? const <Entry>[];
          _wake(_nextChange(adminOffers, vendorOffers, now), now);
          // One box per paid vendor, [visible] at a time, each turn [seconds] long; with few vendors every other turn has none of them,
          // so no vendor's box stays on longer than the admin's seconds.
          final liveAdmin = liveTodayOffers(adminOffers, now);
        // The vendors take the boxes the admin's own offers leave, so a turn's set stays still for exactly the admin's seconds.
        final vendorTurn = rotationPage<TodaysOffer>(vendorOffers, visible: max(1, widget.visible - liveAdmin.length), seconds: widget.seconds, now: now);
          if (vendorOffers.isNotEmpty) _nextTurn(now);
          final boxes = fillBoxes<_Box>(
            mergeOffers(
              [
                for (final o in liveTodayOffers(adminOffers, now))
                  _Box(
                    offer: (look, i) => TodayOfferBox(key: ValueKey('today-offer-box-${i + 1}'), look: look, offer: o, onOpen: _open),
                  ),
              ],
              [for (final o in vendorTurn) _vendorBox(o), for (final ad in ads) _adBox(ad)],
            ),
            [for (final p in widget.boxes) _Box(promotion: p)],
            widget.visible,
          );
          if (boxes.isEmpty && widget.empty != null) return widget.empty!;
          final looks = todayOfferBoxLooks(widget.looks ?? widget.boxes);
          return Column(
            key: const ValueKey('today-offers'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeroCarousel(
                entries: [for (final (i, box) in boxes.indexed) box.promotion ?? looks[i % looks.length]],
                appearance: widget.appearance,
                onTap: widget.onPromotion ?? (_) {},
                reverse: widget.reverse,
                speed: widget.speed,
                // Only offers are drawn here; the others are the promotions as before.
                boxBuilder: (context, look, i) => i < boxes.length ? boxes[i].offer?.call(look, i) : null,
              ),
              // A little room before the strip below (the boxes have no dots under them when all 6 fit).
              const SizedBox(height: 10),
            ],
          );
        },
      ),
    ),
  );
}

/// A box with its live item offer: the box's colour as a rounded frame, and inside it a plain white area with "Today's Offer" across
/// the top, the item's photo big on the left, and its name with the offer price under it on the right. The box keeps its size.
class TodayOfferBox extends StatelessWidget {
  const TodayOfferBox({super.key, required this.look, required this.offer, required this.onOpen});
  final Entry look;
  final Entry offer;
  final ValueChanged<Entry> onOpen;

  /// How thick the coloured frame is.
  static const frame = 5.0;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    final colour = colorFromHex(look.text('backgroundColor'), AppTokens.primary);
    final inner = max(clampedNumber(look, 'radius', 20, 0, 80) - frame, 6.0);
    final photo = o.text('imageUrl');
    final placeholder = const ColoredBox(
      color: Color(0xFFF3F4F6),
      child: Center(child: Icon(Icons.shopping_basket_outlined, color: Colors.black38)),
    );
    final box = Container(
      decoration: entryDecoration(look, fallback: AppTokens.primaryLight),
      padding: const EdgeInsets.all(frame),
      child: Container(
        key: const ValueKey('today-offer-white'),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(inner)),
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FittedBox(
              fit: BoxFit.fitWidth,
              child: Text(
                "Today's Offer".tr(context),
                style: TextStyle(color: colour, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 3),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ClipRRect(
                      key: const ValueKey('today-offer-photo'),
                      borderRadius: BorderRadius.circular(max(inner - 4, 4)),
                      child: photo.isEmpty ? placeholder : Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              o.text('name'),
                              style: const TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w800, fontSize: 18),
                            ),
                          ),
                        ),
                        // The same size in every box: "₹25 / 1 kg" on one line when it fits, else "/ 1 dozen" under "₹40".
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: '₹${todayOfferAmount(o)}', style: const TextStyle(fontSize: 18)),
                              if (o.text('unit').isNotEmpty) TextSpan(text: ' /\u00A0${o.text('unit').replaceAll(' ', '\u00A0')}', style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                          key: const ValueKey('today-offer-rate'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colour, fontWeight: FontWeight.w900, height: 1.1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return ImpressionOnce(
      entry: o,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: () => onOpen(o), child: box),
      ),
    );
  }
}
