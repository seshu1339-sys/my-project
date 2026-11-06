import 'catalog.dart';
import 'ist_time.dart';

// Today's Offers: the 6 coloured boxes under the "Today's Offers" heading on the home page. Each box is one of the Today's Offers
// Box promotions (placement 'carousel', in their order) unless an offer fills it. An item offer is a promotion with
//   placement 'offer', slot 1-6 (its turn in the list), productId, name (the item), imageUrl (the item's photo), offerPrice, unit, shopId,
//   startsAt, endsAt (ISO)
// set by the admin (Settings > Today's Offers Box > Item offers). It shows only from its start to its end. Offers and the order of the
// boxes are put together on the home page (lib/ui/home_today_offers.dart, lib/modules/offerrotation).

const todayOfferBoxCount = 6;
const todayOfferPlacement = 'offer';

/// The colours of the 6 boxes when there are fewer Today's Offers Box promotions (the colours the boxes had).
const todayOfferDefaultColors = ['#16a34a', '#2563eb', '#d97706', '#dc2626', '#9333ea', '#0d9488'];

bool isTodayOffer(Entry e) => e.text('placement') == todayOfferPlacement;

/// The box (1-6) of an offer; 0 when it has none.
int todayOfferSlot(Entry offer) {
  final n = offer.number('slot').round();
  return n >= 1 && n <= todayOfferBoxCount ? n : 0;
}

DateTime? _time(Entry e, String key) => parseIstTime(e.text(key));

/// The offers live at [now], by their box number, then by who started first.
List<Entry> liveTodayOffers(Iterable<Entry> offers, DateTime now) => [
  for (final o in offers)
    if (isTodayOffer(o) && todayOfferSlot(o) != 0 && o.visibleAt(now)) o,
]..sort((a, b) {
    final bySlot = todayOfferSlot(a).compareTo(todayOfferSlot(b));
    return bySlot != 0 ? bySlot : a.text('startsAt').compareTo(b.text('startsAt'));
  });

/// The next time after [now] that any box changes (an offer starts or ends), or null when none will.
DateTime? nextTodayOfferChange(Iterable<Entry> offers, DateTime now) {
  DateTime? next;
  for (final o in offers) {
    if (!isTodayOffer(o) || !o.active) continue;
    for (final t in [_time(o, 'startsAt'), _time(o, 'endsAt')]) {
      if (t != null && t.isAfter(now) && (next == null || t.isBefore(next))) next = t;
    }
  }
  return next;
}

/// The look of each of the 6 boxes: the Today's Offers Box promotions in their order, then the default colours.
List<Entry> todayOfferBoxLooks(List<Entry> carousel) => [
  for (var i = 0; i < todayOfferBoxCount; i++)
    i < carousel.length ? carousel[i] : Entry('today-offer-box-${i + 1}', {'backgroundColor': todayOfferDefaultColors[i], 'textColor': '#ffffff'}),
];

/// The offer price as a number to show: "25", "12.50".
String todayOfferAmount(Entry offer) {
  final v = offer.number('offerPrice');
  return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);
}

/// "₹25 / 1 kg" (or "₹25").
String todayOfferRate(Entry offer) {
  final unit = offer.text('unit');
  return '₹${todayOfferAmount(offer)}${unit.isEmpty ? '' : ' / $unit'}';
}

/// Where an offer is in time at [now], in words for the admin.
String todayOfferStatus(Entry offer, DateTime now) {
  final start = _time(offer, 'startsAt'), end = _time(offer, 'endsAt');
  if (!offer.active) return 'Off';
  if (end != null && !now.isBefore(end)) return 'Ended';
  if (start != null && now.isBefore(start)) return 'Waiting';
  return 'Live now';
}

/// The other offers of the same box whose time overlaps [offer]'s (the admin is told; the one that starts later shows then).
List<Entry> overlappingTodayOffers(Iterable<Entry> offers, Entry offer) {
  final start = _time(offer, 'startsAt'), end = _time(offer, 'endsAt');
  return [
    for (final o in offers)
      if (o.id != offer.id && isTodayOffer(o) && o.active && todayOfferSlot(o) == todayOfferSlot(offer))
        if ((end == null || _time(o, 'startsAt') == null || _time(o, 'startsAt')!.isBefore(end)) &&
            (start == null || _time(o, 'endsAt') == null || _time(o, 'endsAt')!.isAfter(start)))
          o,
  ];
}
