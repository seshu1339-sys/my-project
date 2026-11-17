// One post duration for everyone (lib/domain/post_duration.dart; the server side is functions/post-duration.js).
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/post_duration.dart';
import 'package:ecommerce_app/domain/vendor_items.dart';

void main() {
  test('the admin chooses 24 hours, 7 days or 30 days; anything else is 24 hours', () {
    expect(postDurationChoices.keys, ['24h', '7d', '1m'], reason: 'the same keys as POST_DURATIONS in functions/post-duration.js');
    expect(postDurationLabel(const Entry('business', {'postDuration': '7d'})), '7 days');
    expect(postDurationLabel(const Entry('business', {'postDuration': '1m'})), '30 days');
    for (final odd in [<String, dynamic>{}, {'postDuration': ''}, {'postDuration': '3d'}, {'postDuration': 7}]) {
      expect(postDurationKey(Entry('business', odd)), '24h', reason: '$odd');
    }
  });

  test('a vendor price never runs out (owner, 16 Nov 2026): no "valid for" and no date, whatever the post duration', () {
    final now = DateTime.utc(2026, 11, 12, 10);
    final item = {'price': 40, 'unit': '1 kg', 'priceExpiresAt': now.subtract(const Duration(days: 3)).toIso8601String()};
    expect(vendorPriceLine(item, now), '₹40 for 1 kg', reason: 'an old end is ignored');
  });
}
