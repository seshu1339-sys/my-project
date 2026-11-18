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

/// One problem of an app (an appProblems document). [users] is how many different people had it ([usersMore]: more than the 100 the
/// record keeps); [side] is 'user', 'device' or 'our' (AI Agent + Health System, 17 Nov 2026); [devices] and [oses] count the cases per
/// phone model and Android version. Since 18 Nov 2026 the record also keeps its last 3 [examples] and up to 3 [shotPaths] (US bucket).
class AppProblem {
  const AppProblem({required this.id, required this.app, required this.platform, required this.kind, required this.message, this.screen = '', this.count = 1, this.lastAt, this.version = '', this.device = '', this.role = '', this.userCode = '', this.ms, this.users = 1, this.side = 'our', this.cause = '', this.option = '', this.devices = const {}, this.oses = const {}, this.status = 'open', this.lastShot = '', this.network = '', this.usersMore = false, this.examples = const [], this.shotPaths = const []});
  final String id, app, platform, kind, message, screen, version, device, role, userCode, side, cause, option, status, lastShot, network;
  final int count, users;
  final bool usersMore;
  final List<Map<String, dynamic>> examples;
  final List<String> shotPaths;
  final DateTime? lastAt;
  final int? ms;
  final Map<String, int> devices, oses;

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
    users: (d['users'] as num?)?.toInt() ?? 1,
    side: const ['user', 'device', 'our'].contains(d['side']) ? '${d['side']}' : 'our',
    cause: '${d['cause'] ?? ''}',
    option: '${d['option'] ?? ''}',
    devices: _counts(d['devices']),
    oses: _counts(d['oses']),
    status: '${d['status'] ?? 'open'}',
    lastShot: '${d['lastShot'] ?? ''}',
    network: '${d['lastNetwork'] ?? ''}',
    usersMore: d['usersMore'] == true,
    examples: [for (final e in (d['examples'] is List ? d['examples'] as List : const [])) if (e is Map) Map<String, dynamic>.from(e)],
    shotPaths: [for (final s in (d['shotPaths'] is List ? d['shotPaths'] as List : const [])) '$s'],
  );

  /// The screenshots to show: the saved paths (at most 3), else the one of the version before 18 Nov 2026.
  List<String> get screenshots => shotPaths.isNotEmpty ? shotPaths : [if (lastShot.isNotEmpty) lastShot];

  bool get solved => status == 'solved';

  /// The phone models (or Android versions) with their counts, most first: "Redmi 9 ×5, Galaxy A12 ×1".
  static String topOf(Map<String, int> counts, {int take = 3}) {
    final list = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in list.take(take)) '${e.key} ×${e.value}'].join(', ');
  }
}

Map<String, int> _counts(Object? v) => v is Map ? {for (final e in v.entries) '${e.key}': (e.value as num?)?.toInt() ?? 0} : const {};

/// Which side a problem is on, in English and Telugu (owner spec part 2).
const problemSideNames = <String, String>{
  'user': 'User side (వినియోగదారు వైపు)',
  'device': 'Device side (ఫోన్ మోడల్)',
  'our': 'Our side (మా వైపు)',
};

/// Most affected people first, then most errors, then newest (owner spec part 1).
int byImpact(AppProblem a, AppProblem b) {
  final u = b.users.compareTo(a.users);
  if (u != 0) return u;
  final c = b.count.compareTo(a.count);
  if (c != 0) return c;
  return (b.lastAt ?? DateTime(2000)).compareTo(a.lastAt ?? DateTime(2000));
}

List<AppProblem> mostAffectedFirst(List<AppProblem> list) => [...list]..sort(byImpact);

/// An open burst alert (healthAlerts): the same problem many times in a short time.
class HealthAlert {
  const HealthAlert({required this.id, required this.app, required this.platform, required this.message, this.screen = '', this.n = 0, this.minutes = 60, this.side = 'our', this.type = 'burst', this.at});
  final String id, app, platform, message, screen, side, type;
  final int n, minutes;
  final DateTime? at;

  factory HealthAlert.from(String id, Map<String, dynamic> d) => HealthAlert(
    id: id,
    app: '${d['app'] ?? ''}',
    platform: '${d['platform'] ?? ''}',
    message: '${d['message'] ?? ''}',
    screen: '${d['screen'] ?? ''}',
    n: (d['n'] as num?)?.toInt() ?? 0,
    minutes: (d['minutes'] as num?)?.toInt() ?? 60,
    side: '${d['side'] ?? 'our'}',
    type: '${d['type'] ?? 'burst'}',
    at: _time(d['at']),
  );

  /// "Vendor app: 'No answer to Save item' 6 times in 60 min (add_item)".
  String get line {
    if (type == 'billing') return message;
    final where = [for (final t in appHealthTabs) if (t.$1 == app && t.$2 == platform) t.$3].firstOrNull ?? app;
    return '$where: "$message" $n times in $minutes min${screen.isEmpty ? '' : ' ($screen)'}';
  }
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
  'slow': 'Slow screen or save (నెమ్మదిగా)',
  'tap': 'Tapped again and again, no answer (స్పందన లేదు)',
  'freeze': 'App hung / froze (నిలిచిపోయింది)',
  'stuck': 'Screen stuck loading (లోడ్ అవుతూనే ఉంది)',
  'repeat': 'Same save / upload failed again (మళ్ళీ విఫలం)',
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
