import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/app_health.dart';
import '../domain/catalog.dart';
import '../domain/usage_report.dart';
import '../services/app_monitoring.dart';
import '../services/google_analytics.dart';

/// One line of the Setup check: what it is, whether it works, and what it needs.
class SetupItem {
  const SetupItem(this.title, this.ok, this.detail);
  final String title, detail;
  final bool ok;
}

/// What is connected in the apps and what still needs the owner's step. [pushOn] is how many people have notifications on.
List<SetupItem> setupItems({required bool live, int? pushOn, required bool appsReport, bool googleAnalyticsWeb = false}) => [
  SetupItem('Firebase (database, sign-in, photos)', live, live ? 'Connected: this panel is reading it now.' : 'Not connected: the panel runs in demo mode.'),
  const SetupItem('Usage analytics (this Analytics page)', true, 'On in the customer, vendor and staff apps and the admin panel: screens, buttons, calls, searches...'),
  SetupItem(
    'Push notifications',
    pushOn != null,
    pushOn == null ? 'Customer app (Android and website). The count could not load.' : 'Customer app (Android and website): $pushOn people have notifications on.',
  ),
  SetupItem(
    'App errors and crashes',
    appsReport,
    appsReport ? 'Counted by every app, the website too (below).' : 'Counted from the next app version on: nothing has come in yet.',
  ),
  SetupItem(
    'Speed (how fast each app starts)',
    appsReport,
    appsReport ? 'Counted by every app (below).' : 'Counted from the next app version on: nothing has come in yet.',
  ),
  SetupItem(
    'Google Analytics (live users, retention, paths, phones)',
    googleAnalyticsWeb,
    googleAnalyticsWeb
        ? 'Website (customer, vendor and staff apps): on, in the Firebase console > Analytics. Android apps: not yet (needs the Firebase config file for the three apps).'
        : 'Not in this build: it needs the web measurement id (FIREBASE_MEASUREMENT_ID). Android apps: not yet (needs the Firebase config file for the three apps).',
  ),
  const SetupItem('Firebase Crashlytics and Performance', false, 'Not added: the error and speed counts here cover every app, the website too.'),
  const SetupItem('Uninstalls and installs', false, 'Google Play Console > Statistics (Android apps).'),
];

/// Admin > Insights > Analytics > Setup check: what is set up in each app, and over the last 7 days how often each app started, how
/// fast, and the errors and crashes it had.
class SetupCheckView extends StatefulWidget {
  const SetupCheckView({super.key, required this.store, this.load, this.audience});
  final Store store;
  // Test seams: the usageDaily records of app_start and app_error of the last 7 days, and the push audience.
  final Future<List<Entry>> Function()? load;
  final Future<Map<String, dynamic>> Function()? audience;
  @override
  State<SetupCheckView> createState() => _SetupCheckViewState();
}

class _SetupCheckViewState extends State<SetupCheckView> {
  List<AppHealth>? health;
  int? pushOn;
  String? error;
  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<Entry>> _daily() async {
    final now = DateTime.now();
    final ids = [
      for (var i = 0; i < 7; i++)
        for (final event in const ['app_start', 'app_error']) '${usageDay(now.subtract(Duration(days: i)))}~$event',
    ];
    final snapshot = await store.firestore.collection('usageDaily').where(FieldPath.documentId, whereIn: ids).get();
    return [for (final d in snapshot.docs) Entry(d.id, d.data())];
  }

  Future<void> _load() async {
    try {
      final docs = await (widget.load ?? _daily)();
      if (mounted) setState(() => health = AppHealth.build(UsageReport.build(docs)));
    } catch (e) {
      if (mounted) setState(() => error = 'The counts could not load: $e');
    }
    try {
      final a = widget.audience != null ? await widget.audience!() : await store.call('pushAudience', {});
      if (mounted) setState(() => pushOn = (a['on'] as num?)?.round());
    } catch (_) {
      /* shown as not loaded */
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = health;
    final items = setupItems(
      live: store.live,
      pushOn: pushOn,
      appsReport: h != null && h.any((a) => a.starts > 0 || a.problems.isNotEmpty),
      googleAnalyticsWeb: googleAnalyticsOn,
    );
    final colors = Theme.of(context).colorScheme;
    return ListView(
      key: const ValueKey('setup-check'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('What is set up', style: Theme.of(context).textTheme.titleLarge),
        for (final item in items)
          ListTile(
            dense: true,
            leading: Icon(item.ok ? Icons.check_circle : Icons.info_outline, color: item.ok ? Colors.green : colors.outline),
            title: Text(item.title),
            subtitle: Text(item.detail),
          ),
        const Divider(height: 32),
        Text('Each app, last 7 days', style: Theme.of(context).textTheme.titleLarge),
        if (error != null) Padding(padding: const EdgeInsets.all(8), child: Text(error!, style: TextStyle(color: colors.error))),
        if (h == null && error == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        for (final a in h ?? const <AppHealth>[]) _AppCard(health: a),
      ],
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({required this.health});
  final AppHealth health;

  @override
  Widget build(BuildContext context) {
    final a = health;
    return Card(
      key: ValueKey('setup-app-${a.app}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(healthApps[a.app] ?? a.app, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(a.starts == 0
              ? 'No starts counted yet.'
              : 'Started ${a.starts} times (${a.startsBy.entries.map((e) => '${e.key} ${e.value}').join(', ')}) • ${(a.fastShare * 100).round()}% showed the first screen in under 2 s'),
          if (a.starts > 0)
            Text('Speed: ${[for (final g in AppMonitoring.speedGroups) if ((a.speed[g] ?? 0) > 0) '$g: ${a.speed[g]}'].join(' • ')}', style: const TextStyle(fontSize: 12)),
          Text(
            a.problems.isEmpty ? 'No errors or crashes.' : 'Crashes: ${a.crashes} • errors: ${a.errors}',
            style: TextStyle(color: a.crashes > 0 ? Theme.of(context).colorScheme.error : null),
          ),
          for (final p in a.problems.take(5))
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text('${p.count}× ${p.town}: ${p.label}', style: const TextStyle(fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}
