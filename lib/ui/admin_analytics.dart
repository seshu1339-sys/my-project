import 'package:flutter/material.dart';

import '../data/store.dart';
import 'admin_analytics_people.dart';
import 'admin_analytics_reports.dart';
import 'admin_inactive_accounts.dart';
import 'admin_push_center.dart';
import 'screen_view.dart';

/// One part of the Analytics page: its tab and what it shows. Each part is its own file, so a part can be added or removed alone.
class AnalyticsSection {
  const AnalyticsSection(this.title, this.icon, this.build);
  final String title;
  final IconData icon;
  final Widget Function(Store store) build;
}

/// The parts, in tab order.
final analyticsSections = <AnalyticsSection>[
  AnalyticsSection('Reports', Icons.insights_outlined, (store) => AnalyticsReportsView(store: store)),
  AnalyticsSection('People', Icons.people_outline, (store) => AnalyticsPeopleView(store: store)),
  AnalyticsSection('Push notifications', Icons.notifications_active_outlined, (store) => ScreenView('admin_push_center', child: PushCenterView(store: store))),
  AnalyticsSection('Inactive accounts', Icons.person_off_outlined, (store) => ScreenView('admin_inactive_accounts', child: InactiveAccountsView(store: store))),
];

/// Admin > Insights > Analytics: what people do in the apps (reports with Excel, each person's use), and the parts added with it.
/// Only the open tab is built, so a part reads its data only when it is shown.
class AdminAnalyticsPage extends StatelessWidget {
  const AdminAnalyticsPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => ScreenView(
    'admin_analytics',
    child: DefaultTabController(
      length: analyticsSections.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Analytics'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final s in analyticsSections) Tab(text: s.title, icon: Icon(s.icon))],
          ),
        ),
        body: Builder(
          builder: (context) {
            final controller = DefaultTabController.of(context);
            return ListenableBuilder(
              listenable: controller,
              builder: (context, _) => KeyedSubtree(key: ValueKey(controller.index), child: analyticsSections[controller.index].build(store)),
            );
          },
        ),
      ),
    ),
  );
}

/// The way in, at the top of Insights.
class AnalyticsEntryCard extends StatelessWidget {
  const AnalyticsEntryCard({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      key: const ValueKey('open-analytics'),
      leading: const Icon(Icons.insights_outlined, size: 32),
      title: const Text('Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text('Reports of what people do in the apps, each person\'s use, Excel downloads${analyticsSections.length > 2 ? ', and ${analyticsSections.skip(2).map((s) => s.title.toLowerCase()).join(', ')}' : ''}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdminAnalyticsPage(store: store))),
    ),
  );
}
