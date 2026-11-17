import 'package:flutter/material.dart';

import '../data/store.dart';
import '../services/health_watch.dart';
import 'app_health_page.dart';

/// The red banner at the top of the admin panel while a burst alert is open (AI Agent + Health System part 1): the same problem many
/// times in a short time (Settings > Health limits, default 6 times in 60 minutes). "Open" shows App Health; "Close" ends the alert.
/// The same alert is also pushed to every browser / phone where the admin turned on alerts (Health page).
class HealthAlertBanner extends StatelessWidget {
  const HealthAlertBanner({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: HealthWatch.instance,
    builder: (context, _) {
      final alerts = HealthWatch.instance.alerts;
      if (alerts.isEmpty) return const SizedBox.shrink();
      return Material(
        key: const ValueKey('health-alert-banner'),
        color: const Color(0xFFC62828),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(children: [
            for (final a in alerts.take(3))
              Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(a.line, key: ValueKey('health-alert-${a.id}'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(title: const Text('App Health')), body: AppHealthPage(store: store)))),
                  child: const Text('Open', style: TextStyle(color: Colors.white)),
                ),
                TextButton(
                  key: ValueKey('health-alert-close-${a.id}'),
                  onPressed: () => HealthWatch.instance.close(store, a.id),
                  child: const Text('Close', style: TextStyle(color: Colors.white70)),
                ),
              ]),
            if (alerts.length > 3) Text('+${alerts.length - 3} more alerts (App Health)', style: const TextStyle(color: Colors.white)),
          ]),
        ),
      );
    },
  );
}
