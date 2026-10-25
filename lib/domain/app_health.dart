import 'usage_report.dart';

// The admin's Setup check: how each app starts and what goes wrong in it, from the usage counts the apps send
// (lib/services/app_monitoring.dart):
//   app_start  key <app>/<platform>/<speed group>
//   app_error  key <app>/<platform>/<crash|error>/<id>, label the message

/// The apps, in the order the admin sees them, with their names.
const healthApps = {'customer': 'Customer app', 'vendor': 'Vendor app', 'staff': 'Staff app', 'admin': 'Admin panel'};

class AppHealth {
  AppHealth(this.app);
  final String app;
  final startsBy = <String, int>{}; // by platform
  final speed = <String, int>{}; // by speed group
  final errorsBy = <String, int>{}; // 'crash' / 'error'
  final problems = <UsageKeyRow>[]; // the messages, the most first
  int get starts => startsBy.values.fold(0, (a, b) => a + b);
  int get errors => errorsBy['error'] ?? 0;
  int get crashes => errorsBy['crash'] ?? 0;

  /// The share of starts that showed the first screen in under 2 seconds (0 with no starts).
  double get fastShare => starts == 0 ? 0 : ((speed['under 1 s'] ?? 0) + (speed['1-2 s'] ?? 0)) / starts;

  /// Every app in [healthApps] (and any other that reported), from a range's report.
  static List<AppHealth> build(UsageReport report) {
    final apps = {for (final a in healthApps.keys) a: AppHealth(a)};
    for (final row in report.top('app_start', max: 1000)) {
      final parts = row.key.split('/');
      if (parts.length < 3) continue;
      final h = apps[parts[0]] ??= AppHealth(parts[0]);
      h.startsBy[parts[1]] = (h.startsBy[parts[1]] ?? 0) + row.count;
      h.speed[parts[2]] = (h.speed[parts[2]] ?? 0) + row.count;
    }
    for (final row in report.top('app_error', max: 1000)) {
      final parts = row.key.split('/');
      if (parts.length < 4) continue;
      final h = apps[parts[0]] ??= AppHealth(parts[0]);
      h.errorsBy[parts[2]] = (h.errorsBy[parts[2]] ?? 0) + row.count;
      h.problems.add(UsageKeyRow(row.key, row.label, parts[1], row.count));
    }
    return apps.values.toList();
  }
}
