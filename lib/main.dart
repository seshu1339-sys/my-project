import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'data/store.dart';
import 'ui/storefront.dart';
import 'ui/email_link.dart';
import 'ui/details.dart';
import 'ui/admin_auth.dart';
import 'domain/catalog.dart';
import 'services/firebase_startup.dart';
import 'services/analytics.dart';
import 'services/usage_start.dart';
import 'services/push_opens.dart';
import 'services/emulators.dart';
import 'services/admin_route.dart';
import 'services/location.dart';
import 'services/location_town.dart';
import 'services/app_theme.dart';
import 'services/localization.dart';

final _navigator = GlobalKey<NavigatorState>();
final _messenger = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
  var live = false;
  String? startupError;
  if (project.isNotEmpty) {
    try {
      await Firebase.initializeApp(options: firebaseOptions);
      await connectToEmulatorsIfConfigured();
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
      }
      live = true;
    } catch (e) {
      startupError = 'Firebase could not start. Check the supplied project configuration and restart.';
    }
  }
  if (startupError != null) {
    runApp(
      MaterialApp(
        home: Scaffold(body: Center(child: Text(startupError))),
      ),
    );
    return;
  }
  final firestore = live ? FirebaseFirestore.instance : null;
  final store = Store(live: live, database: firestore);
  await store.init();
  if (kIsWeb && isAdminRoute) {
    // Usage analytics (lib/services/usage.dart): the admin panel counts as the admin app.
    if (live) unawaited(startUsage(app: 'admin'));
    runApp(AdminEntryApp(store: store));
    return;
  }
  // Anonymous visit counting; only the customer app ever starts it.
  if (live) {
    // Start counting visits, then genuine ad views once the device id exists.
    unawaited(Analytics.start().then((_) => Analytics.startAdTracker()));
    unawaited(startUsage(app: 'customer'));
    // The website opened from a notification (?nid=...): counted as opened.
    unawaited(reportWebPushOpen());
  }
  runApp(MarketApp(store: store));
  if (live) {
    unawaited(_refreshLocationOnOpen(store));
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification != null) {
        _messenger.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              '${notification.title ?? 'New alert'}: ${notification.body ?? ''}',
            ),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => _openAlert(store, message),
            ),
          ),
        );
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _openAlert(store, message),
    );
    try {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      if (message != null) {
        await WidgetsBinding.instance.endOfFrame;
        await _openAlert(store, message);
      }
    } catch (_) {
      /* Unsupported messaging must not block the storefront. */
    }
  }
}

// On every app open, refresh the customer's coordinates (never the manually
// chosen pincode/address) so ads/offers and nearby search reflect where they
// actually are right now. Never prompts for permission and never blocks
// first paint; silently does nothing if permission was never granted.
Future<void> _refreshLocationOnOpen(Store store) async {
  await WidgetsBinding.instance.endOfFrame;
  final position = await currentPositionIfPermitted();
  if (position != null) {
    // Someone who chose "Use my location" has the town follow their phone: when they
    // have travelled to another town, the stored place (and so the offers shown and
    // the location push notification) moves with them. A town picked by hand never moves.
    final nearest = store.followsGps
        ? await nearestPlaceFor(position.latitude, position.longitude)
        : null;
    if (nearest != null && nearest.town != store.town) {
      await store.setLocation(
        pincodeForGps(store.pincode, nearest),
        nearest.label,
        lat: position.latitude,
        lng: position.longitude,
        town: nearest.town,
        district: nearest.district,
        state: nearest.state,
        followGps: true,
      );
      return;
    }
    await store.setLocation(
      store.pincode,
      store.address,
      lat: position.latitude,
      lng: position.longitude,
      followGps: store.followsGps,
    );
  }
}

Future<void> _openAlert(Store store, RemoteMessage message) async {
  // Counted for the admin's push centre: which notification (or which kind) was opened.
  unawaited(reportPushOpen(nid: message.data['nid'], type: message.data['type'], title: message.notification?.title ?? ''));
  final id = message.data['productId'];
  if (id == null) {
    _navigator.currentState?.popUntil((route) => route.isFirst);
    return;
  }
  try {
    final doc = await store.firestore.collection('products').doc(id).get();
    if (doc.exists) {
      _navigator.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ProductPage(store: store, entry: Entry(doc.id, doc.data()!)),
        ),
      );
    }
  } catch (_) {
    _messenger.currentState?.showSnackBar(
      const SnackBar(
        content: Text('Could not open this item. Please try searching for it.'),
      ),
    );
  }
}

class MarketApp extends StatelessWidget {
  const MarketApp({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => MaterialApp(
      navigatorKey: _navigator,
      scaffoldMessengerKey: _messenger,
      debugShowCheckedModeBanner: false,
      title: 'Local Market • Everyday shopping made easy',
      locale: AppLocale.fromCode(store.language),
      supportedLocales: AppLocale.enabled(
        store.business.text('enabledLanguages'),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: AppLocale.isRtl(store.language)
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: child ?? const SizedBox.shrink(),
      ),
      theme: buildAppTheme(store, dark: false),
      darkTheme: buildAppTheme(store, dark: true),
      themeMode: resolveThemeMode(store),
      home: store.pendingEmailLink != null
          ? EmailLinkPage(store: store)
          : Storefront(store: store),
    ),
  );
}
