import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/today_offers.dart';
import '../domain/towns.dart';
import '../services/analytics.dart';
import '../services/strings.dart';
import 'design_tokens.dart';
import 'home_hero_carousel.dart';
import 'home_impression_once.dart';
import 'shared.dart';
import 'shop_route_map.dart';

/// Today's Offers on the home page: the "Today's Offers" heading and the coloured boxes (lib/domain/today_offers.dart). While an item
/// offer is live for a box, the box shows it: its colour as a frame round a white inside with "Today's Offer" across the top, the
/// item's photo big on the left and its name and offer price on the right. Tapping it opens the shop on the map straight away (its
/// place, the road and its phone). A box with no live offer shows its Today's Offers Box promotion as before (so the town, pincode
/// and area boxes keep working); the boxes change by themselves when an offer starts or ends.
class TodayOffersSection extends StatefulWidget {
  const TodayOffersSection({
    super.key,
    required this.store,
    required this.boxes,
    this.appearance = const Entry('', {}),
    this.reverse = false,
    this.speed = 600,
    this.showAll = false,
    this.onPromotion,
  });
  final Store store;

  /// Opens a promotion's target (the boxes before any item offer is set).
  final void Function(String target)? onPromotion;

  /// The Today's Offers Box promotions (the boxes' look), in their order.
  final List<Entry> boxes;
  final Entry appearance;
  final bool reverse, showAll;
  final double speed;

  @override
  State<TodayOffersSection> createState() => _TodayOffersSectionState();
}

class _TodayOffersSectionState extends State<TodayOffersSection> {
  Timer? _next;
  DateTime? _nextAt;

  @override
  void dispose() {
    _next?.cancel();
    super.dispose();
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

  bool _inTown(Entry offer) {
    final town = widget.store.town;
    return widget.showAll || town.isEmpty || offer.text('town').isEmpty || townKey(offer.text('town')) == townKey(town);
  }

  void _open(Entry offer) {
    Analytics.click(offer);
    final shopId = offer.text('shopId');
    final shop = widget.store.entries('shops').where((s) => s.id == shopId).firstOrNull;
    showShopRoute(
      context,
      ShopStop.shop(
        shop,
        shopId: shopId,
        itemName: offer.text('name'),
        itemPhoto: offer.text('imageUrl'),
        price: offer.number('offerPrice'),
        unit: offer.text('unit'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final now = DateTime.now();
      final offers = widget.store.entries('promotions').where((o) => isTodayOffer(o) && o.active && _inTown(o)).toList();
      final slots = todayOfferSlots(offers, now);
      _wake(nextTodayOfferChange(offers, now), now);
      return Column(
        key: const ValueKey('today-offers'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.local_offer_outlined, color: AppTokens.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    "Today's Offers".tr(context),
                    key: const ValueKey('today-offers-heading'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          HeroCarousel(
            entries: todayOfferBoxesFor(widget.boxes, slots),
            appearance: widget.appearance,
            onTap: widget.onPromotion ?? (_) {},
            reverse: widget.reverse,
            speed: widget.speed,
            // Only a box with a live offer is drawn here; the others are the promotions as before.
            boxBuilder: (context, look, i) =>
                i < slots.length && slots[i] != null ? TodayOfferBox(key: ValueKey('today-offer-box-${i + 1}'), look: look, offer: slots[i]!, onOpen: _open) : null,
          ),
          // A little room before the strip below (the boxes have no dots under them when all 6 fit).
          const SizedBox(height: 10),
        ],
      );
    },
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
    final placeholder = const ColoredBox(color: Color(0xFFF3F4F6), child: Center(child: Icon(Icons.shopping_basket_outlined, color: Colors.black38)));
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
              child: Text("Today's Offer".tr(context), style: TextStyle(color: colour, fontWeight: FontWeight.w900)),
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
                      child: photo.isEmpty
                          ? placeholder
                          : Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
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
                            child: Text(o.text('name'), style: const TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w800, fontSize: 18)),
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
