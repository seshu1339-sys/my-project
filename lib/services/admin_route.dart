import 'package:flutter/foundation.dart';

/// The path that reveals the admin panel inside the customer web app. Never
/// linked from any public page — reachable only by entering this URL
/// directly. Change it at build time (never in source) with:
///   flutter build web --dart-define=ADMIN_ROUTE_PATH=/your-own-path
/// The default below is only a fallback for local development; pick your own
/// hard-to-guess value for anything you deploy.
const String adminRoutePath = String.fromEnvironment(
  'ADMIN_ROUTE_PATH',
  defaultValue: '/jyothi9',
);

/// True only on the web, and only when the current URL path is exactly the
/// configured admin route. Checked once at startup (see main.dart); a plain
/// page reload is the only way back to this check, so it cannot be reached by
/// client-side navigation from the storefront.
bool get isAdminRoute => kIsWeb && Uri.base.path == adminRoutePath;
