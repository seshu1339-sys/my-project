// What the admin panel reads from healthStatus/current (functions/modules/health, owner spec F + H, 17 Nov 2026), and the problems of
// the apps (functions/modules/app-problems). Pure: no Firebase here, so the red marks and the "what is not working?" answer are tested
// without a server.

class HealthCheck {
  const HealthCheck({required this.id, required this.name, required this.group, required this.ok, this.error = '', this.registryIds = const [], this.since, this.explain = '', this.ms = 0});
  final String id, name, group, error, explain;
  final bool ok;
  final List<String> registryIds;
  final DateTime? since;
  final int ms;

  factory HealthCheck.from(Map<String, dynamic> m) => HealthCheck(
    id: '${m['id'] ?? ''}',
    name: '${m['name'] ?? m['id'] ?? ''}',
    group: '${m['group'] ?? 'Other'}',
    ok: m['ok'] == true,
    error: '${m['error'] ?? ''}',
    registryIds: [for (final r in (m['registryIds'] as List? ?? const [])) '$r'],
    since: _time(m['since']),
    explain: '${m['explain'] ?? ''}',
    ms: (m['ms'] as num?)?.toInt() ?? 0,
  );
}

class ServerError {
  const ServerError(this.service, this.message, this.count, this.last);
  final String service, message, last;
  final int count;
}

class HealthStatus {
  const HealthStatus({this.at, this.checks = const [], this.serverErrors = const [], this.serverErrorsNote = ''});
  final DateTime? at;
  final List<HealthCheck> checks;
  final List<ServerError> serverErrors;
  final String serverErrorsNote;

  static const empty = HealthStatus();

  factory HealthStatus.from(Map<String, dynamic>? d) {
    if (d == null) return empty;
    final checks = [for (final v in (d['checks'] as Map? ?? const {}).values) if (v is Map) HealthCheck.from(Map<String, dynamic>.from(v))]
      ..sort((a, b) => a.ok == b.ok ? a.group.compareTo(b.group) : (a.ok ? 1 : -1));
    return HealthStatus(
      at: _time(d['at']),
      checks: checks,
      serverErrors: [
        for (final e in (d['serverErrors'] as List? ?? const []))
          if (e is Map) ServerError('${e['service'] ?? ''}', '${e['message'] ?? ''}', (e['count'] as num?)?.toInt() ?? 0, '${e['last'] ?? ''}'),
      ],
      serverErrorsNote: '${d['serverErrorsNote'] ?? ''}',
    );
  }

  List<HealthCheck> get failing => [for (final c in checks) if (!c.ok) c];
  bool get ran => at != null;

  /// The command-box option IDs that get a red mark (owner spec H).
  Set<String> get failingRegistryIds => {for (final c in failing) ...c.registryIds};

  /// The checks of one option ID that fail now.
  List<HealthCheck> failingFor(String registryId) => [for (final c in failing) if (c.registryIds.contains(registryId)) c];
}

/// One problem of an app (an appProblems document).
class AppProblem {
  const AppProblem({required this.id, required this.app, required this.platform, required this.kind, required this.message, this.screen = '', this.count = 1, this.lastAt, this.version = '', this.device = '', this.role = '', this.userCode = '', this.ms});
  final String id, app, platform, kind, message, screen, version, device, role, userCode;
  final int count;
  final DateTime? lastAt;
  final int? ms;

  factory AppProblem.from(String id, Map<String, dynamic> d) => AppProblem(
    id: id,
    app: '${d['app'] ?? ''}',
    platform: '${d['platform'] ?? ''}',
    kind: '${d['kind'] ?? 'error'}',
    message: '${d['message'] ?? ''}',
    screen: '${d['screen'] ?? ''}',
    count: (d['count'] as num?)?.toInt() ?? 1,
    lastAt: _time(d['lastAt']),
    version: '${d['lastVersion'] ?? ''}',
    device: '${d['lastDevice'] ?? ''}',
    role: '${d['lastRole'] ?? ''}',
    userCode: '${d['lastUserCode'] ?? ''}',
    ms: (d['lastMs'] as num?)?.toInt(),
  );
}

/// The tabs of the App Health dashboard: Vendor / Staff / User Android apps, then the website and the admin panel.
const appHealthTabs = <(String, String, String)>[
  ('vendor', 'android', 'Vendor app'),
  ('staff', 'android', 'Staff app'),
  ('customer', 'android', 'User app'),
  ('customer', 'web', 'Website'),
  ('admin', 'web', 'Admin panel'),
];

/// The names of the problem kinds, English and Telugu.
const problemKindNames = <String, String>{
  'crash': 'Crash (క్రాష్)',
  'error': 'Error (ఎర్రర్)',
  'login': 'Login failed (లాగిన్)',
  'otp': 'OTP failed (OTP)',
  'email': 'Email verification failed (ఈమెయిల్)',
  'location': 'Location permission / GPS (లొకేషన్)',
  'upload': 'Photo upload failed (ఫోటో అప్‌లోడ్)',
  'api': 'Server (API) error (సర్వర్)',
  'slow': 'Slow screen (నెమ్మదిగా)',
};

/// Problems newest first; [counts] per kind (from the problems' own counts).
List<AppProblem> newestFirst(List<AppProblem> list) => [...list]..sort((a, b) => (b.lastAt ?? DateTime(2000)).compareTo(a.lastAt ?? DateTime(2000)));

Map<String, int> countsByKind(List<AppProblem> list) {
  final out = <String, int>{};
  for (final p in list) {
    out[p.kind] = (out[p.kind] ?? 0) + p.count;
  }
  return Map.fromEntries(out.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
}

/// The command box's answer to "what is not working?": the failing checks, the server errors and the app problems of the last day.
String notWorkingAnswer(HealthStatus s, {List<AppProblem> recentProblems = const [], int newReports = 0, DateTime? now}) {
  final lines = <String>[];
  if (!s.ran) lines.add('The daily health check has not run yet. Open Health and press "Run now".');
  for (final c in s.failing) {
    lines.add('🔴 ${c.name} — ${c.error}');
  }
  for (final e in s.serverErrors.take(5)) {
    lines.add('🔴 Server ${e.service}: ${e.message} (${e.count}×)');
  }
  final cut = (now ?? DateTime.now()).subtract(const Duration(days: 1));
  final apps = <String, int>{};
  for (final p in recentProblems) {
    if (p.lastAt != null && p.lastAt!.isAfter(cut)) apps['${p.app}/${p.platform}'] = (apps['${p.app}/${p.platform}'] ?? 0) + p.count;
  }
  for (final t in appHealthTabs) {
    final n = apps['${t.$1}/${t.$2}'];
    if (n != null && n > 0) lines.add('🟠 ${t.$3}: $n problems in the last 24 hours (App Health)');
  }
  if (newReports > 0) lines.add('🟠 $newReports new "Report a problem" messages (App Health)');
  if (lines.isEmpty) return 'Everything works: all ${s.checks.length} checks passed${s.at == null ? '' : ' at ${_hm(s.at!)}'}. అన్నీ పని చేస్తున్నాయి.';
  final head = s.failing.isEmpty && s.serverErrors.isEmpty ? 'All checks pass. Problems from the apps:' : 'Not working (పని చేయనివి):';
  return '$head\n${lines.join('\n')}';
}

String _hm(DateTime t) {
  final l = t.toLocal();
  return '${l.day}/${l.month} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

DateTime? _time(Object? v) {
  if (v == null) return null;
  try {
    final dynamic t = v;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    return (t.toDate() as DateTime);
  } catch (_) {
    return null;
  }
}
