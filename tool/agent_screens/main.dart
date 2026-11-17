// A local preview of the new admin screens (owner spec A-H, 17 Nov 2026) for the screenshots before any deploy. NOT part of any app:
// it shows the real widgets with SAMPLE data (no Firebase, no server, no AI). Build:
//   flutter build web -t tool/agent_screens/main.dart -o build/agent_screens_web
// Open ?screen=command | ask | ad | design | health | apphealth
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/admin_ads.dart';
import 'package:ecommerce_app/domain/agent_command.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/health_status.dart';
import 'package:ecommerce_app/ui/admin.dart';
import 'package:ecommerce_app/ui/agent_ad_flow.dart';
import 'package:ecommerce_app/ui/agent_command_box.dart';
import 'package:ecommerce_app/ui/agent_design_flow.dart';
import 'package:ecommerce_app/ui/agent_intents.dart';
import 'package:ecommerce_app/ui/agent_registry_build.dart';
import 'package:ecommerce_app/ui/app_health_page.dart';
import 'package:ecommerce_app/ui/health_page.dart';
import 'package:flutter/material.dart';

const _photo = 'assets/assets/images/categories/fresh_fruits.webp';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  await store.init();
  store.catalog['settings'] = [
    ...store.entries('settings').where((e) => e.id != 'section_search' && e.id != 'agent'),
    const Entry('section_search', {'imageIconSize': 24, 'cameraIconColor': '#FF757575'}),
    const Entry('agent', {'aiExplain': 'true'}),
  ];
  final screen = Uri.base.queryParameters['screen'] ?? 'command';
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'LOCAMARKET admin preview',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF1565C0), useMaterial3: true),
    home: _Sample(child: _screen(screen, store)),
  ));
}

/// A thin "SAMPLE DATA" ribbon so nobody mistakes a screenshot for live numbers.
class _Sample extends StatelessWidget {
  const _Sample({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Banner(message: 'SAMPLE DATA', location: BannerLocation.topEnd, color: Colors.deepOrange, child: child);
}

Widget _screen(String screen, Store store) {
  final now = DateTime.now();
  switch (screen) {
    case 'ask':
      return Scaffold(
        appBar: AppBar(title: const Text('Business studio')),
        body: Column(children: [
          AdminSettingsSearchBar(
            store: store,
            count: (c) async => countAnswerSample(c),
            intents: AgentIntentHandlers(
              health: (context, store) async => notWorkingAnswer(_status(), newReports: 2, recentProblems: _problems().$1, now: now),
              healthPage: (s) => HealthPage(store: s, status: _status()),
              ad: (context, store, command, photo) async {},
              design: (context, store, command, matches, platform) async {},
            ),
          ),
        ]),
      );
    case 'ad':
      final c = parseAgentCommand("this photo, Today's Offers, Narsipatnam, 10 km, 2 days", places: const ['Narsipatnam']);
      return AgentAdFormPage(
        store: store,
        draft: adminAdFromCommand(c, now: now, photoUrl: _photo).copyWith(title: 'Fresh fruits 20% off'),
        command: c.text,
        resolve: (t) async => (lat: 17.6676, lng: 82.6129, district: 'Anakapalli', state: 'Andhra Pradesh'),
        save: (a) async => 'sample',
      );
    case 'design':
      final entry = buildAgentRegistry().singleWhere((e) => e.id == 'design.web.search.imageIconSize');
      return DesignChangePage(store: store, entry: entry, command: parseAgentCommand('search box camera icon size 60'), saveHistory: (r) async {});
    case 'health':
      return Scaffold(
        appBar: AppBar(title: const Text('Health')),
        body: HealthPage(
          store: store,
          status: _status(),
          runNow: () async => {'ok': false, 'failed': 2},
          explain: (c) async => 'కారణం: వెండర్ వెబ్ యాప్ సైట్ 503 ఇస్తోంది — Firebase Hosting లో vendor సైట్ deploy కాలేదు లేదా పాత build పోయింది.\n'
              'ఎలా సరిచేయాలి: vendor web build మళ్ళీ తీసి vendor hosting target కి deploy చేయండి.\n'
              '```\nThe health check "Vendor web app opens" fails with HTTP 503 on https://e-commerce-app-a3897-vendor.web.app/. Find why the vendor hosting site is not served, fix it with tests, and do not deploy without my approval.\n```',
        ),
      );
    case 'apphealth':
      return Scaffold(appBar: AppBar(title: const Text('App Health')), body: AppHealthPage(store: store, load: (app, platform) async => app == 'vendor' ? _problems() : (<AppProblem>[], <Map<String, dynamic>>[])));
    default:
      return AdminPage(store: store);
  }
}

String countAnswerSample(AgentCommand c) => 'SAMPLE: 3 vendors registered in ${c.place.isEmpty ? 'all towns' : c.place} today.\n${c.place}లో ఈరోజు 3 వెండర్లు చేరారు.';

HealthStatus _status() => HealthStatus.from({
  'at': DateTime.now().subtract(const Duration(hours: 3)),
  'checks': {
    for (final (i, c) in const [
      ('site:1', 'Customer website (Firebase) opens', 'Pages', true, '', <String>[]),
      ('site:2', 'Admin panel site opens', 'Pages', true, '', <String>[]),
      ('site:3', 'Vendor web app opens', 'Pages', false, 'HTTP 503', ['page.tab.vendors']),
      ('site:5', 'locamarket.in (Hostinger) opens', 'Pages', true, '', <String>[]),
      ('api:placeOrder', 'Server function placeOrder answers', 'Server functions', true, '', <String>[]),
      ('api:submitVendorAd', 'Server function submitVendorAd answers', 'Server functions', false, 'Not found: the function is not deployed', ['page.ads']),
      ('save:firestore', 'A test record saves, reads back and is deleted', 'Saves', true, '', <String>[]),
      ('save:storage', 'A test photo uploads and is deleted', 'Saves', true, '', <String>[]),
      ('ads:radius', 'Location / radius ads reach the right km', 'Ads', true, '', <String>[]),
      ('config:remote', 'Android apps can read their design settings (remote config)', 'Remote config', true, '', <String>[]),
    ].indexed)
      'c$i': {'id': c.$1, 'name': c.$2, 'group': c.$3, 'ok': c.$4, 'error': c.$5, 'registryIds': c.$6, 'ms': 120 + i * 37, 'since': DateTime.now().subtract(const Duration(hours: 3))},
  },
  'serverErrors': [
    {'service': 'placeorder', 'message': 'TypeError: Cannot read properties of undefined (reading \'price\')', 'count': 4, 'last': '2026-11-17T08:12:00Z'},
  ],
});

(List<AppProblem>, List<Map<String, dynamic>>) _problems() {
  final now = DateTime.now();
  return (
    newestFirst([
      AppProblem(id: 'p1', app: 'vendor', platform: 'android', kind: 'otp', message: 'verifyEmailLoginCode: invalid-argument The code is wrong or old', screen: 'vendor_login', count: 7, lastAt: now.subtract(const Duration(minutes: 20)), version: '1.0.12+22', device: 'Xiaomi Redmi 9 (Android 11)', userCode: 'VEN-NRPM-116-325'),
      AppProblem(id: 'p2', app: 'vendor', platform: 'android', kind: 'upload', message: 'Photo upload (vendorProducts): unauthorized', screen: 'vendor_products', count: 3, lastAt: now.subtract(const Duration(hours: 2)), version: '1.0.12+22', device: 'Samsung SM-A125F (Android 12)', userCode: 'VEN-NRPM-116-341'),
      AppProblem(id: 'p3', app: 'vendor', platform: 'android', kind: 'location', message: 'Location permission deniedForever (register your shop)', screen: 'vendor_register', count: 2, lastAt: now.subtract(const Duration(hours: 5)), version: '1.0.12+22', device: 'Vivo 1906 (Android 10)'),
      AppProblem(id: 'p4', app: 'vendor', platform: 'android', kind: 'slow', message: 'Slow screen vendor_products', screen: 'vendor_products', count: 4, lastAt: now.subtract(const Duration(hours: 9)), version: '1.0.12+22', device: 'Itel A60 (Android 11)', ms: 4300),
      AppProblem(id: 'p5', app: 'vendor', platform: 'android', kind: 'crash', message: "RangeError (index): Invalid value: Valid value range is empty: 0", screen: 'vendor_rates', count: 1, lastAt: now.subtract(const Duration(days: 1)), version: '1.0.11+21', device: 'Realme RMX2185 (Android 10)'),
    ]),
    [
      {'id': 'r1', 'text': 'Price save button తిరుగుతూనే ఉంది, save అవ్వట్లేదు', 'status': 'new', 'userCode': 'VEN-NRPM-116-325', 'version': '1.0.12+22', 'device': 'Xiaomi Redmi 9', 'screen': 'vendor_products'},
      {'id': 'r2', 'text': 'OTP రావట్లేదు', 'status': 'seen', 'userCode': 'VEN-TUNI-118-012', 'version': '1.0.12+22', 'device': 'Samsung SM-A125F', 'screen': 'vendor_login'},
    ],
  );
}
