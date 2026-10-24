import 'catalog.dart';

// The "Right Side Ad Boxes" down the right of the home page (settings/rightAdBoxes).
//   count          how many boxes the admin has (default 15; Add box / Remove box change it)
//   box<n>Image    the box's JPG/PNG photo (a box with no photo is not shown to customers)
//   box<n>Target   optional link: category:<id> | shop:<id> | product:<id>
//   box<n>Color    optional background colour (#RRGGBB) behind the photo
// The numbers exist only in the admin panel; customers see the photos, in number order.

const rightBoxesDoc = 'rightAdBoxes';
const defaultRightBoxCount = 15;
const maxRightBoxCount = 60;

/// The box height every Right Side Ad Box uses (the size of the old "Big Savings Day" / "Suma Fresh Mart" ad boxes).
const rightBoxHeight = 240.0;

class RightBox {
  const RightBox(this.number, this.imageUrl, this.target, this.color);
  final int number;
  final String imageUrl, target, color;

  /// The link only when a category, shop or product was actually chosen ("category:" alone means none yet).
  bool get hasTarget => target.isNotEmpty && !target.endsWith(':');
}

Entry rightBoxesRecord(List<Entry> settings) => settings.where((e) => e.id == rightBoxesDoc).firstOrNull ?? const Entry(rightBoxesDoc, {});

int rightBoxCount(Entry record) => record.number('count', defaultRightBoxCount.toDouble()).round().clamp(0, maxRightBoxCount);

/// Box [number] (1-based) as saved, whether or not it has a photo.
RightBox rightBoxAt(Entry record, int number) =>
    RightBox(number, record.text('box${number}Image'), record.text('box${number}Target'), record.text('box${number}Color'));

/// The boxes customers see: only those with a photo, in number order.
List<RightBox> liveRightBoxes(Entry record) => [
  for (var n = 1; n <= rightBoxCount(record); n++)
    if (rightBoxAt(record, n).imageUrl.isNotEmpty) rightBoxAt(record, n),
];
