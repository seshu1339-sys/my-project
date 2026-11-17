// The command box's live numbers without AI (owner spec A, 17 Nov 2026): "how many vendors added today in Narsipatnam" is read from the
// day counts the server already keeps (functions/usage.js usageDaily/<day>~<event>, one document per day and event, with a count per
// town / item), so one question costs at most one read per day asked about (31 for "this month"). Vendors waiting / approved, shops and
// products are count() queries (one read per 1000). This file is the pure part: which documents, and how to add them up.
import 'agent_command.dart';
import 'agent_registry.dart';

/// The usage event behind a metric, or null when the metric is a count() query.
String? usageEventOf(AgentMetric m) => switch (m) {
  AgentMetric.vendorsAdded => 'vendor_register',
  AgentMetric.itemsAdded => 'item_added',
  AgentMetric.pricesChanged => 'price_changed',
  AgentMetric.staffAdded => 'staff_added',
  AgentMetric.searches => 'search',
  _ => null,
};

/// The Indian days (YYYY-MM-DD) a period covers, newest first.
List<String> periodDays(AgentPeriod p, DateTime nowUtc) {
  final ist = nowUtc.toUtc().add(const Duration(hours: 5, minutes: 30));
  String day(DateTime d) => d.toIso8601String().substring(0, 10);
  final today = DateTime.utc(ist.year, ist.month, ist.day);
  return switch (p) {
    AgentPeriod.today => [day(today)],
    AgentPeriod.yesterday => [day(today.subtract(const Duration(days: 1)))],
    AgentPeriod.week => [for (var i = 0; i < 7; i++) day(today.subtract(Duration(days: i)))],
    AgentPeriod.month => [for (var i = 0; i < ist.day; i++) day(today.subtract(Duration(days: i)))],
  };
}

/// Adds up usageDaily documents: the total, or only the keys whose town (or label / key) is [place].
int sumUsage(List<Map<String, dynamic>> docs, String place) {
  final want = agentNormalize(place);
  var total = 0;
  for (final d in docs) {
    if (want.isEmpty) {
      total += (d['total'] as num?)?.toInt() ?? 0;
      continue;
    }
    final keys = d['keys'];
    if (keys is! Map) continue;
    for (final k in keys.values) {
      if (k is! Map) continue;
      final where = [k['town'], k['label'], k['key']].map((v) => agentNormalize('${v ?? ''}')).toList();
      // "Narsipatnam", "Narsipatnam Rural", "Krishna Bazar (Narsipatnam)" (the brackets are gone after agentNormalize).
      if (where.any((w) => w.isNotEmpty && (w == want || w.startsWith('$want ') || w.endsWith(' $want')))) {
        total += (k['count'] as num?)?.toInt() ?? 0;
      }
    }
  }
  return total;
}

String metricName(AgentMetric m) => switch (m) {
  AgentMetric.vendorsAdded => 'vendors registered',
  AgentMetric.vendorsWaiting => 'vendors waiting for approval',
  AgentMetric.vendorsApproved => 'approved vendors',
  AgentMetric.itemsAdded => 'items added',
  AgentMetric.pricesChanged => 'prices changed',
  AgentMetric.staffAdded => 'vendors added by staff',
  AgentMetric.searches => 'searches',
  AgentMetric.shops => 'shops',
  AgentMetric.products => 'products',
};

String metricTe(AgentMetric m) => switch (m) {
  AgentMetric.vendorsAdded => 'వెండర్లు చేరారు',
  AgentMetric.vendorsWaiting => 'వెండర్లు ఆమోదం కోసం వేచి ఉన్నారు',
  AgentMetric.vendorsApproved => 'ఆమోదించిన వెండర్లు',
  AgentMetric.itemsAdded => 'ఐటమ్స్ చేర్చారు',
  AgentMetric.pricesChanged => 'ధరలు మార్చారు',
  AgentMetric.staffAdded => 'స్టాఫ్ చేర్చిన వెండర్లు',
  AgentMetric.searches => 'సెర్చ్‌లు',
  AgentMetric.shops => 'షాపులు',
  AgentMetric.products => 'ప్రొడక్ట్స్',
};

String periodName(AgentPeriod p) => switch (p) {
  AgentPeriod.today => 'today',
  AgentPeriod.yesterday => 'yesterday',
  AgentPeriod.week => 'in the last 7 days',
  AgentPeriod.month => 'this month',
};

String periodTe(AgentPeriod p) => switch (p) {
  AgentPeriod.today => 'ఈరోజు',
  AgentPeriod.yesterday => 'నిన్న',
  AgentPeriod.week => 'గత 7 రోజుల్లో',
  AgentPeriod.month => 'ఈ నెలలో',
};

/// The answer line, English then Telugu. A count() metric (waiting, approved, shops, products) is "now", not for a period.
String countAnswer(AgentCommand c, int n) {
  final m = c.metric!;
  final now = usageEventOf(m) == null;
  final where = c.place.isEmpty ? '' : ' in ${c.place}';
  final whereTe = c.place.isEmpty ? '' : '${c.place}లో ';
  final en = now ? '$n ${metricName(m)}$where now.' : '$n ${metricName(m)}$where ${periodName(c.period)}.';
  final te = now ? '$whereTe$n ${metricTe(m)}.' : '$whereTe${periodTe(c.period)} $n ${metricTe(m)}.';
  return '$en\n$te';
}
