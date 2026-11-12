import 'catalog.dart';

// One post duration for everyone (owner, 12 Nov 2026). The admin chooses it in Business Profile (settings/business.postDuration); every
// post of a vendor or staff (item prices, Today's Offers, Vendor Offers, vendor ads, exclusive items) ends at the latest this long after
// it was posted, paid plans included. The server caps each post's end (functions/post-duration.js), so the website and the apps hide a
// post at its end time by themselves. Keep the keys the same as POST_DURATIONS there.
const postDurationChoices = {'24h': '24 hours', '7d': '7 days', '1m': '1 month'};
const defaultPostDuration = '24h';

/// The admin's post duration key ('24h', '7d' or '1m'); 24 hours when it is not set or not one of these.
String postDurationKey(Entry business) {
  final key = business.text('postDuration');
  return postDurationChoices.containsKey(key) ? key : defaultPostDuration;
}

/// "24 hours", "7 days" or "1 month", for the vendor's notes.
String postDurationLabel(Entry business) => postDurationChoices[postDurationKey(business)]!;
