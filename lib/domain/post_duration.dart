import 'catalog.dart';

// One post duration for everyone (owner, 12 Nov 2026). The admin chooses it in Business Profile (settings/business.postDuration); every
// post of a vendor or staff (item prices, Today's Offers, Vendor Offers, vendor ads, exclusive items) ends at the latest this long after
// it was posted, paid plans included. The server caps each post's end (functions/post-duration.js), so the website and the apps hide a
// post at its end time by themselves. Keep the keys the same as POST_DURATIONS there.
const postDurationChoices = {'24h': '24 hours', '7d': '7 days', '1m': '30 days'};
const defaultPostDuration = '24h';

/// The admin's post duration key ('24h', '7d' or '1m'); 24 hours when it is not set or not one of these.
String postDurationKey(Entry business) {
  final key = business.text('postDuration');
  return postDurationChoices.containsKey(key) ? key : defaultPostDuration;
}

/// "24 hours", "7 days" or "30 days", for the vendor's notes.
String postDurationLabel(Entry business) => postDurationChoices[postDurationKey(business)]!;

/// The vendor's own day choices (Today's Offers, My Offers, ads, exclusive items) stay in the code but are hidden (owner, 13 Nov 2026):
/// the admin's post duration decides for everyone. Set to true to show them again; the server still caps every post at the duration.
// A variable (not a const) so the tests of the hidden choices can still switch them on.
// ignore: prefer_const_declarations
bool showPostDayChoices = false;

/// What every vendor and staff screen that posts says, with the admin's duration: paid vendors are told before they post.
String postDurationNotice(Entry business) =>
    'Every post shows for ${postDurationLabel(business)} after you post it, then it hides by itself. Post it again to show it again. Paid plans give more photos and posts, not a longer time.';
