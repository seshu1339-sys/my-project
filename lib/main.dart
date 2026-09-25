import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import 'services/emulators.dart';
import 'services/admin_route.dart';
import 'ui/shared.dart';
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
      // The hidden admin route always starts at the password step: any
      // session already persisted in this browser (from an earlier visit, or
      // from the customer site sharing the same Firebase project) is signed
      // out before the admin UI is ever built, so a direct reload can never
      // skip straight past the password check.
      if (kIsWeb && isAdminRoute) await FirebaseAuth.instance.signOut();
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
    runApp(AdminEntryApp(store: store));
    return;
  }
  // Anonymous visit counting; only the customer app ever starts it.
  if (live) Analytics.start();
  runApp(MarketApp(store: store));
  if (live) {
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

Future<void> _openAlert(Store store, RemoteMessage message) async {
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
      theme: _theme(store, dark: false),
      darkTheme: _theme(store, dark: true),
      themeMode: _themeMode(store),
      home: store.pendingEmailLink != null
          ? EmailLinkPage(store: store)
          : Storefront(store: store),
    ),
  );

  ThemeMode _themeMode(Store store) {
    final mode = store
        .entries('settings')
        .firstWhere(
          (entry) => entry.id == 'theme',
          orElse: () => const Entry('theme', {}),
        )
        .text('mode', 'light');
    return mode == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  ThemeData _theme(Store store, {required bool dark}) {
    final settings = store
        .entries('settings')
        .firstWhere(
          (entry) => entry.id == 'theme',
          orElse: () => const Entry('theme', {}),
        );
    final primary = colorFromHex(
      settings.text(dark ? 'darkPrimary' : 'primary'),
      const Color(0xff176b50),
    );
    final background = colorFromHex(
      settings.text(dark ? 'darkBackground' : 'background'),
      dark ? const Color(0xff101512) : const Color(0xfff7f8f4),
    );
    final surface = colorFromHex(
      settings.text(dark ? 'darkSurface' : 'surface'),
      dark ? const Color(0xff1a211d) : Colors.white,
    );
    final text = colorFromHex(
      settings.text(dark ? 'darkText' : 'text'),
      dark ? Colors.white : Colors.black87,
    );
    final appBar = colorFromHex(
      settings.text(dark ? 'darkAppBar' : 'appBar'),
      background,
    );
    final secondary = colorFromHex(
      settings.text(dark ? 'darkSecondary' : 'secondary'),
      primary,
    );
    final fontFamily = settings.text('fontFamily').trim();
    final fontSize = settings.number('fontSize', 14).clamp(10, 30).toDouble();
    final fontWeight = FontWeight.values.firstWhere(
      (weight) => weight.value == settings.number('fontWeight', 400).round(),
      orElse: () => FontWeight.normal,
    );
    final textTheme =
        ThemeData(brightness: dark ? Brightness.dark : Brightness.light)
            .textTheme
            .apply(
              fontFamily: fontFamily.isEmpty ? 'Arial' : fontFamily,
              bodyColor: text,
              displayColor: text,
              fontSizeFactor: fontSize / 14,
            );
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: dark ? Brightness.dark : Brightness.light,
      ).copyWith(secondary: secondary),
      scaffoldBackgroundColor: background,
      fontFamily: fontFamily.isEmpty ? 'Arial' : fontFamily,
      textTheme: textTheme.copyWith(
        bodyMedium: textTheme.bodyMedium?.copyWith(fontWeight: fontWeight),
        bodyLarge: textTheme.bodyLarge?.copyWith(fontWeight: fontWeight),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      cardTheme: CardThemeData(elevation: 0, color: surface),
      appBarTheme: AppBarTheme(
        backgroundColor: appBar,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
