import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'usage.dart';

/// A notification was opened: counted for the admin's push centre (trackPushOpen, functions/push-center.js) and in the usage counts.
/// [nid] is an admin-sent notification's id, [type] an automatic one's (priceDrop, offer, orderStatus...). Never throws.
Future<void> reportPushOpen({String? nid, String? type, String title = ''}) async {
  Usage.track('notification_open', key: nid ?? type ?? 'push', label: title);
  try {
    // An opening is counted for the signed-in person, so wait until the sign-in has been restored.
    await FirebaseAuth.instance.authStateChanges().first;
    await FirebaseFunctions.instance.httpsCallable('trackPushOpen').call({'nid': ?nid, 'type': ?type});
  } catch (_) {
    /* best effort */
  }
}

/// On the website a notification opens the site with `?nid=...`: report that opening once.
Future<void> reportWebPushOpen() async {
  if (!kIsWeb) return;
  final nid = Uri.base.queryParameters['nid'];
  if (nid != null && RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(nid)) await reportPushOpen(nid: nid);
}
