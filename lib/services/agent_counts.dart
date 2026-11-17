import '../data/store.dart';
import '../domain/agent_command.dart';
import '../domain/agent_counts.dart';
import '../domain/agent_registry.dart';

/// Reads the live number one count command asks for (lib/domain/agent_counts.dart). The admin reads these collections directly
/// (firestore.rules: usageDaily, vendors, shops, products), so no server function and no AI is used.
Future<String> answerCount(Store store, AgentCommand c, {DateTime? now}) async {
  final m = c.metric!;
  final event = usageEventOf(m);
  final db = store.firestore;
  if (event != null) {
    final days = periodDays(c.period, now ?? DateTime.now().toUtc());
    final docs = await Future.wait([for (final d in days) db.collection('usageDaily').doc('$d~$event').get()]);
    return countAnswer(c, sumUsage([for (final d in docs) if (d.exists) d.data()!], c.place));
  }
  final Future<int?> n = switch (m) {
    AgentMetric.vendorsWaiting => db.collection('vendors').where('status', isEqualTo: 'pending').count().get().then((r) => r.count),
    AgentMetric.vendorsApproved => db.collection('vendors').where('status', isEqualTo: 'approved').count().get().then((r) => r.count),
    AgentMetric.shops => c.place.isEmpty
        ? db.collection('shops').count().get().then((r) => r.count)
        : Future.value(store.entries('shops').where((s) => agentNormalize(s.text('town')).contains(agentNormalize(c.place))).length),
    _ => db.collection('products').count().get().then((r) => r.count),
  };
  // Vendors waiting / approved and products are counted for everywhere: the answer does not name a place it did not use.
  final used = m == AgentMetric.shops ? c : AgentCommand(c.intent, c.text, metric: m, period: c.period);
  return countAnswer(used, await n ?? 0);
}
