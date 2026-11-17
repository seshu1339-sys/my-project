import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/health_status.dart';
import '../domain/support_limits.dart';
import '../services/admin_push.dart';
import '../services/agent_log.dart';

// Parts of the Health page added by the AI Agent + Health System (17 Nov 2026, part 1): the alerts on this device, the top problems of
// every app with the most affected people first, and the admin's limits (burst alert, slow / stuck / hang times, AI Support reply days).

/// "Alerts on this device": push the moment a problem keeps happening (lib/services/admin_push.dart).
class HealthAlertsSwitch extends StatefulWidget {
  const HealthAlertsSwitch({super.key, required this.store, this.isOn, this.turn});
  final Store store;

  /// Test seams.
  final Future<bool> Function()? isOn;
  final Future<void> Function(bool on)? turn;

  @override
  State<HealthAlertsSwitch> createState() => _HealthAlertsSwitchState();
}

class _HealthAlertsSwitchState extends State<HealthAlertsSwitch> {
  bool? on;
  String? error;

  @override
  void initState() {
    super.initState();
    (widget.isOn ?? () => AdminPush.isOn(widget.store))().then((v) {
      if (mounted) setState(() => on = v);
    });
  }

  Future<void> _set(bool v) async {
    setState(() => error = null);
    try {
      await (widget.turn ?? (v) => v ? AdminPush.turnOn(widget.store) : AdminPush.turnOff(widget.store))(v);
      AgentLog.write(widget.store, action: v ? 'admin_alerts_on' : 'admin_alerts_off', target: 'this device');
      if (mounted) setState(() => on = v);
    } catch (e) {
      if (mounted) setState(() => error = '$e'.replaceFirst('Bad state: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(
        key: const ValueKey('health-alerts-switch'),
        secondary: const Icon(Icons.notifications_active_outlined),
        title: const Text('Alerts on this device (ఈ డివైస్‌కి అలర్ట్)'),
        subtitle: const Text('A notification the moment the same problem keeps happening (limits below). Turn it on in each browser / phone you use.'),
        value: on ?? false,
        onChanged: on == null ? null : _set,
      ),
      if (error != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
    ]),
  );
}

/// The open problems of every app in the last 7 days, most affected people first (the 10 biggest).
class TopProblemsCard extends StatefulWidget {
  const TopProblemsCard({super.key, required this.store, this.load, required this.openAppHealth});
  final Store store;
  final Future<List<AppProblem>> Function()? load;
  final VoidCallback openAppHealth;

  @override
  State<TopProblemsCard> createState() => _TopProblemsCardState();
}

class _TopProblemsCardState extends State<TopProblemsCard> {
  late final Future<List<AppProblem>> data = (widget.load ?? _live)();

  Future<List<AppProblem>> _live() async {
    if (!widget.store.live) return const [];
    final since = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 7)));
    final q = await widget.store.firestore.collection('appProblems').where('lastAt', isGreaterThan: since).limit(300).get();
    return mostAffectedFirst([for (final d in q.docs) AppProblem.from(d.id, d.data())].where((p) => !p.solved && p.side != 'user').toList());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<AppProblem>>(
    future: data,
    builder: (context, snap) {
      final list = snap.data ?? const <AppProblem>[];
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Top problems, all apps (last 7 days, most affected first)', style: Theme.of(context).textTheme.titleSmall),
            const Text('Our side and device side only; user-side problems (location off, no internet…) are in App Health.', style: TextStyle(fontSize: 12)),
            if (!snap.hasData && !snap.hasError) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
            if (snap.hasData && list.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No open problems. 👍', key: ValueKey('health-top-none'))),
            for (final p in list.take(10))
              ListTile(
                key: ValueKey('health-top-${p.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 16, backgroundColor: p.side == 'device' ? Colors.purple : Colors.red, child: Text('${p.users}', style: const TextStyle(color: Colors.white, fontSize: 12))),
                title: Text(p.message, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text([
                  [for (final t in appHealthTabs) if (t.$1 == p.app && t.$2 == p.platform) t.$3].firstOrNull ?? p.app,
                  '${p.users} people, ${p.count} times',
                  if (p.screen.isNotEmpty) p.screen,
                  if (p.side == 'device' && p.devices.isNotEmpty) AppProblem.topOf(p.devices, take: 2),
                ].join(' · ')),
                onTap: widget.openAppHealth,
              ),
          ]),
        ),
      );
    },
  );
}

/// The admin's limits (lib/domain/support_limits.dart), saved field by field into settings/health and settings/support.
class HealthLimitsCard extends StatefulWidget {
  const HealthLimitsCard({super.key, required this.store});
  final Store store;
  @override
  State<HealthLimitsCard> createState() => _HealthLimitsCardState();
}

class _HealthLimitsCardState extends State<HealthLimitsCard> {
  late final controllers = {for (final l in supportLimits) l.id: TextEditingController(text: '${limitValue(widget.store.entries('settings'), l.id)}')};
  late bool aiOn = supportAiOn(widget.store.entries('settings'));
  String? note;
  bool saving = false;

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final changes = <String, Map<String, dynamic>>{};
    for (final l in supportLimits) {
      final v = num.tryParse(controllers[l.id]!.text.trim());
      if (v == null || v < l.min || v > l.max) {
        setState(() => note = '"${l.label}" must be between ${l.min} and ${l.max}.');
        return;
      }
      changes.putIfAbsent(l.record, () => {})[l.id] = v;
    }
    changes.putIfAbsent('support', () => {})['aiOn'] = aiOn;
    setState(() { saving = true; note = null; });
    try {
      for (final e in changes.entries) {
        final current = widget.store.entries('settings').where((x) => x.id == e.key).firstOrNull;
        await widget.store.updateFields('settings', e.key, e.value, fallback: Entry(e.key, {...?current?.data, ...e.value}));
      }
      AgentLog.write(widget.store, action: 'health_limits', target: 'settings/health, settings/support', details: {for (final e in changes.entries) ...e.value});
      if (mounted) setState(() => note = 'Saved.');
    } catch (e) {
      if (mounted) setState(() => note = 'Could not save: $e');
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) => Card(
    key: const ValueKey('health-limits'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Limits (పరిమితులు)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final l in supportLimits)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              key: ValueKey('health-limit-${l.id}'),
              controller: controllers[l.id],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l.label, suffixText: l.unit, helperText: '${l.min}–${l.max}, default ${l.defaultValue}', border: const OutlineInputBorder(), isDense: true),
            ),
          ),
        SwitchListTile(
          key: const ValueKey('health-limit-aiOn'),
          contentPadding: EdgeInsets.zero,
          title: const Text('AI Support box may use AI (Claude Haiku)'),
          subtitle: const Text('Only for unknown problems and typed questions, up to the daily number above. Known problems use free pre-written steps. Off = no AI cost.'),
          value: aiOn,
          onChanged: (v) => setState(() => aiOn = v),
        ),
        Row(children: [
          FilledButton(key: const ValueKey('health-limits-save'), onPressed: saving ? null : _save, child: Text(saving ? 'Saving…' : 'Save limits')),
          const SizedBox(width: 12),
          if (note != null) Expanded(child: Text(note!, key: const ValueKey('health-limits-note'))),
        ]),
      ]),
    ),
  );
}
