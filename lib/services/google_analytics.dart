import 'google_analytics_stub.dart' if (dart.library.js_interop) 'google_analytics_web.dart' as platform;
import 'usage.dart';

/// The Google Analytics (GA4) web measurement id given at build time (FIREBASE_MEASUREMENT_ID, from the Firebase web app's config).
const googleAnalyticsId = String.fromEnvironment('FIREBASE_MEASUREMENT_ID');

/// Whether this build sends to Google Analytics: only the website, and only with a valid measurement id.
bool get googleAnalyticsOn => platform.supported && RegExp(r'^G-[A-Z0-9]{4,20}$').hasMatch(googleAnalyticsId);

/// Google Analytics on the website (customer, vendor and staff apps; never the admin panel): the same events as the usage analytics
/// (lib/services/usage.dart), so the GA4 dashboard shows live users, daily users, retention, paths, towns and phones. No age or
/// gender (Google signals off), no ad personalisation, no account id, and emails, links and long numbers are taken out first.
/// The Android apps need their own step (see the Setup check). Never throws.
void startGoogleAnalytics({required String app}) {
  if (!googleAnalyticsOn || app == 'admin') return;
  try {
    if (!platform.start(googleAnalyticsId, app)) return;
    Usage.sinks.add((event, params) {
      final clean = {for (final e in params.entries) e.key: cleanForAnalytics(e.value)};
      if (event == 'screen_view') {
        platform.event('page_view', {'page_title': clean['key'] ?? '', 'page_path': '/$app/${clean['key'] ?? ''}', 'app': app});
      } else {
        // GA4 keeps some names for itself (notification_open)
        platform.event(event == 'notification_open' ? 'push_opened' : event, {...clean, 'app': app});
      }
    });
  } catch (_) {
    /* analytics must never break the app */
  }
}

/// [value] without emails, links or long numbers (phone numbers), cut to GA4's 100 characters.
String cleanForAnalytics(String value) {
  final clean = value
      .replaceAll(RegExp(r'\S+@\S+'), '<email>')
      .replaceAll(RegExp(r'https?://\S+'), '<link>')
      .replaceAll(RegExp(r'\d{6,}'), '<number>')
      .trim();
  return clean.length > 100 ? clean.substring(0, 100) : clean;
}
