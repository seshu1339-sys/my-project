import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

// Google Analytics on the website (lib/services/google_analytics.dart): Google's gtag.js, loaded only when the app starts it.
const supported = true;

/// Loads gtag.js for [measurementId] (already checked to be G-...). Returns false when it cannot.
bool start(String measurementId, String app) {
  if (globalContext.has('gtag')) return true;
  final setup = web.document.createElement('script') as web.HTMLScriptElement
    ..text =
        'window.dataLayer=window.dataLayer||[];function gtag(){dataLayer.push(arguments);}'
        "gtag('js',new Date());"
        "gtag('config','$measurementId',{send_page_view:false,allow_google_signals:false,allow_ad_personalization_signals:false});"
        "gtag('set','user_properties',{app:'$app'});";
  web.document.head?.append(setup);
  final loader = web.document.createElement('script') as web.HTMLScriptElement
    ..async = true
    ..src = 'https://www.googletagmanager.com/gtag/js?id=$measurementId';
  web.document.head?.append(loader);
  return globalContext.has('gtag');
}

void event(String name, Map<String, String> params) {
  if (!globalContext.has('gtag')) return;
  // a screen is a page of the site: /<app>/<screen>
  final path = params.remove('page_path');
  if (path != null) params['page_location'] = '${web.window.location.origin}$path';
  globalContext.callMethodVarArgs('gtag'.toJS, ['event'.toJS, name.toJS, params.jsify()]);
}
