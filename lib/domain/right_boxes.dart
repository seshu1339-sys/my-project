import 'catalog.dart';

// The "Right Side Ad Boxes" down the right of the home page (settings/rightAdBoxes).
//   count          how many boxes the admin has (default 15; Add box / Remove box change it)
//   box<n>Image    the box's JPG/PNG photo (a box with no photo is not shown to customers)
//   box<n>Target   optional link: category:<id> | shop:<id> | product:<id>
//   box<n>Color    optional background colour (#RRGGBB) behind the photo
//   box<n>AdId     the shop ad in the box (rbox-..., set only by functions/shop-ads.js when the admin links the box to a vendor);
//                  while the box has a photo its views are counted for that vendor (lib/domain/shop_ads.dart)
// The numbers exist only in the admin panel; customers see the boxes in number order. A box with no photo shows as a light grey
// "your ad here" placeholder of the same size.

const rightBoxesDoc = 'rightAdBoxes';
const defaultRightBoxCount = 15;
const maxRightBoxCount = 60;

/// The box height every Right Side Ad Box uses (the size of the old "Big Savings Day" / "Suma Fresh Mart" ad boxes).
const rightBoxHeight = 240.0;

/// Every shop ad id starts with this (functions/shop-ads.js).
const rightBoxAdPrefix = 'rbox-';

class RightBox {
  const RightBox(this.number, this.imageUrl, this.target, this.color, {this.adId = ''});
  final int number;
  final String imageUrl, target, color, adId;

  /// The link only when a category, shop or product was actually chosen ("category:" alone means none yet).
  bool get hasTarget => target.isNotEmpty && !target.endsWith(':');

  /// The box shows a vendor's shop ad, so the customers' views are counted for that vendor.
  bool get countsViews => imageUrl.isNotEmpty && adId.startsWith(rightBoxAdPrefix);
}

Entry rightBoxesRecord(List<Entry> settings) => settings.where((e) => e.id == rightBoxesDoc).firstOrNull ?? const Entry(rightBoxesDoc, {});

int rightBoxCount(Entry record) => record.number('count', defaultRightBoxCount.toDouble()).round().clamp(0, maxRightBoxCount);

/// Box [number] (1-based) as saved, whether or not it has a photo.
RightBox rightBoxAt(Entry record, int number) => RightBox(
  number,
  record.text('box${number}Image'),
  record.text('box${number}Target'),
  record.text('box${number}Color'),
  adId: record.text('box${number}AdId'),
);

/// Every box customers see, in number order: the ones with a photo, and the empty ones as placeholders.
List<RightBox> shownRightBoxes(Entry record) => [for (var n = 1; n <= rightBoxCount(record); n++) rightBoxAt(record, n)];

/// Only the boxes that have a photo.
List<RightBox> liveRightBoxes(Entry record) => [for (final box in shownRightBoxes(record)) if (box.imageUrl.isNotEmpty) box];

/// The text on an empty box.
const rightBoxPlaceholder = 'ఇక్కడ మీ ప్రకటన';

/// "Shop ad, right box 3" for a shop ad id (rbox-3-...), or null for any other ad.
String? rightBoxAdTitle(String adId) {
  final m = RegExp('^$rightBoxAdPrefix(\\d+)-').firstMatch(adId);
  return m == null ? null : 'Shop ad, right box ${m.group(1)}';
}
