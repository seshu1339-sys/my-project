import 'ads.dart';
import 'catalog.dart';

// Rules the admin's Ads screens use. Kept apart from the widgets so they can be tested on their own.

/// The fields that only the admin may see: they are saved in `adsPrivate/<id>`, never in the public `ads` record.
const adPrivateFields = ['contactPerson', 'phone', 'amount', 'paid', 'notes'];

const adStatusLabels = <String, String>{
  'pending': 'Pending approval',
  'live': 'Live',
  'scheduled': 'Scheduled',
  'expired': 'Expired',
  'rejected': 'Rejected',
  'inactive': 'Inactive',
};

/// Splits a form's values into what customers may read and what is for the admin only.
({Map<String, dynamic> public, Map<String, dynamic> private}) splitAdFields(Map<String, dynamic> values) => (
  public: {for (final e in values.entries) if (!adPrivateFields.contains(e.key)) e.key: e.value},
  private: {for (final e in values.entries) if (adPrivateFields.contains(e.key)) e.key: e.value},
);

/// Filters the admin's list: [status] is one of [adStatusLabels] (null = all); [query] matches the title, the shop name or the vendor code.
List<Entry> filterAds(List<Entry> ads, DateTime now, {String? status, String query = ''}) {
  final q = query.trim().toLowerCase();
  return [
    for (final ad in ads)
      if ((status == null || adStatus(ad, now) == status) &&
          (q.isEmpty ||
              ad.text('title').toLowerCase().contains(q) ||
              ad.text('shopName').toLowerCase().contains(q) ||
              ad.text('vendorCode').toLowerCase().contains(q)))
        ad,
  ];
}

/// Live or scheduled ads that end within [days] days: the admin is warned about them.
List<Entry> adsEndingSoon(List<Entry> ads, DateTime now, {int days = 3}) => [
  for (final ad in ads)
    if (const {'live', 'scheduled'}.contains(adStatus(ad, now)))
      if (DateTime.tryParse(ad.text('endsAt')) case final end? when end.difference(now) <= Duration(days: days)) ad,
];

/// Whole days left for an ad (rounded up), or null when it has no end date.
int? adDaysLeft(Entry ad, DateTime now) {
  final end = DateTime.tryParse(ad.text('endsAt'));
  if (end == null) return null;
  final left = end.difference(now);
  return left.isNegative ? 0 : (left.inHours / 24).ceil();
}

DateTime _addMonth(DateTime d) {
  final month = d.month == 12 ? 1 : d.month + 1;
  final year = d.month == 12 ? d.year + 1 : d.year;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, d.day > lastDay ? lastDay : d.day, d.hour, d.minute);
}

/// The new end for a renewal: an ad that is still running gets the time added to its current end, an expired one starts again from now.
String renewedEnd(Entry ad, DateTime now, {required String by}) {
  final current = DateTime.tryParse(ad.text('endsAt'));
  final from = current != null && current.isAfter(now) ? current : now;
  final to = by == 'month' ? _addMonth(from) : from.add(const Duration(days: 7));
  return to.toIso8601String();
}

/// A copy to edit: same content, a new id, switched off until the admin checks it, at the end of the order.
Entry duplicateAd(Entry ad, String newId, int order) => Entry(newId, {
  ...ad.data,
  'title': '${ad.text('title', ad.text('name'))} (copy)',
  'active': false,
  'status': 'approved',
  'pinned': false,
  'order': order,
});

/// What a package fills in. Rounds, seconds and the daily limit stay editable afterwards.
Map<String, dynamic> packageFill(String package) {
  final p = adPackageDefaults[package] ?? adPackageDefaults['normal']!;
  return {'package': package, 'rounds': p.rounds, 'seconds': p.seconds, 'maxPerDay': p.maxPerDay};
}

/// "09:00-12:00,18:00-21:00" from a list of slots, and back.
String slotsToText(List<(int, int)> slots) {
  String t(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  return slots.map((s) => '${t(s.$1)}-${t(s.$2)}').join(',');
}

/// The id an imported old ad box gets; importing twice never makes a second copy.
String importedAdId(Entry promotion) => 'import-${promotion.id}';

/// The old ad boxes (promotions placed as "ad") that are not yet in the unified Ads list.
List<Entry> adsToImport(List<Entry> promotions, List<Entry> ads) {
  final have = ads.map((a) => a.id).toSet();
  return [for (final p in promotions) if (p.text('placement') == 'ad' && !have.contains(importedAdId(p))) p];
}

/// A copy of an old ad box as a unified ad. The old record is left as it is.
Entry adFromPromotion(Entry promotion, int order) {
  final target = promotion.text('target');
  final action = target.startsWith('shop:') ? 'shop' : target.startsWith('https://') ? 'link' : '';
  final value = action == 'shop' ? target.substring(5) : action == 'link' ? target : '';
  final image = promotion.text('imageUrl');
  return Entry(importedAdId(promotion), {
    'title': promotion.text('name'),
    'text': promotion.text('description'),
    'contentType': image.isEmpty ? 'text' : 'imageText',
    if (image.isNotEmpty) 'imageUrl': image,
    for (final k in ['backgroundColor', 'textColor', 'locations', 'startsAt', 'endsAt'])
      if (promotion.text(k).isNotEmpty) k: promotion.text(k),
    if (action.isNotEmpty) ...{'tapAction': action, 'tapValue': value} else if (target.isNotEmpty) 'target': target,
    'status': 'approved',
    'active': promotion.active,
    'package': 'normal',
    'rounds': 1,
    'seconds': 5,
    'order': order,
  });
}
