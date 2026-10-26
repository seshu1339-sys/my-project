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

/// Today's Offers on the home page: the "Today's Offers" heading and the 6 coloured boxes (lib/domain/today_offers.dart). Each box
/// shows its item offer of the moment: the item's photo in a white circle, its name and the offer price in white. Tapping a box
/// opens the shop on the map straight away (its place, the road and its phone). A box with no offer now is empty; the boxes change
/// by themselves when an offer starts or ends. Until the admin has set item offers (for the customer's town), the boxes show the
/// Today's Offers Box promotions as before.
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
          if (offers.isEmpty)
            HeroCarousel(entries: widget.boxes, appearance: widget.appearance, onTap: widget.onPromotion ?? (_) {}, reverse: widget.reverse, speed: widget.speed)
          else
            HeroCarousel(
              entries: todayOfferBoxLooks(widget.boxes),
              appearance: widget.appearance,
              onTap: (_) {},
              reverse: widget.reverse,
              speed: widget.speed,
              boxBuilder: (context, look, i) => TodayOfferBox(key: ValueKey('today-offer-box-${i + 1}'), look: look, offer: slots[i], onOpen: _open),
            ),
          // A little room before the strip below (the boxes have no dots under them when all 6 fit).
          const SizedBox(height: 10),
        ],
      );
    },
  );
}

/// One of the 6 boxes: its own colour and shape, and the offer (photo in a white circle, name, price) or nothing.
class TodayOfferBox extends StatelessWidget {
  const TodayOfferBox({super.key, required this.look, required this.offer, required this.onOpen});
  final Entry look;
  final Entry? offer;
  final ValueChanged<Entry> onOpen;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    final box = Container(
      decoration: entryDecoration(look, fallback: AppTokens.primaryLight),
      child: o == null
          ? const SizedBox.expand()
          : LayoutBuilder(
              builder: (context, c) {
                // The same circle in every box: the boxes are all the same size.
                final circle = min(c.maxHeight * .48, c.maxWidth * .62).clamp(40.0, 170.0);
                const white = Colors.white;
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        key: const ValueKey('today-offer-circle'),
                        width: circle,
                        height: circle,
                        padding: EdgeInsets.all(circle * .1),
                        decoration: BoxDecoration(color: white, shape: BoxShape.circle, boxShadow: AppTokens.shadowSoft),
                        child: ClipOval(child: ProductArt(Entry(o.id, {'imageUrl': o.text('imageUrl')}), height: circle * .8, width: circle * .8)),
                      ),
                      SizedBox(height: circle * .08),
                      Text(
                        o.text('name'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: white, fontWeight: FontWeight.w800, fontSize: (circle * .19).clamp(13.0, 22.0), height: 1.15),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          todayOfferRate(o),
                          key: const ValueKey('today-offer-rate'),
                          style: TextStyle(color: white, fontWeight: FontWeight.w900, fontSize: (circle * .24).clamp(15.0, 28.0)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
    if (o == null) return box;
    return ImpressionOnce(
      entry: o,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: () => onOpen(o), child: box),
      ),
    );
  }
}
