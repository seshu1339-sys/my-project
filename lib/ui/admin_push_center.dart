import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/shop_ads.dart';

/// The automatic notifications and their switches (settings/business), on unless switched off.
const automaticNotifications = [
  (
    'priceDropAutoEnabled',
    'priceDrop',
    'Price drops',
    'An item a customer looked at gets cheaper.',
  ),
  (
    'offerNotificationsEnabled',
    'offer',
    'New offers',
    'An offer goes live (each offer can also be set to Always or Never).',
  ),
  (
    'locationOfferNotificationsEnabled',
    'locationOffers',
    'Offers in your town',
    'A customer\'s place changes and there are offers there.',
  ),
  (
    'orderStatusNotificationsEnabled',
    'orderStatus',
    'Order updates',
    'An order is confirmed, sent or cancelled.',
  ),
];

/// Admin > Insights > Analytics > Push notifications: send a notification to everyone with notifications on, to one town or to one
/// person; switch each automatic notification on or off; and see, for each one sent, how many got it, how many opened it, and who
/// did not (functions/push-center.js).
class PushCenterView extends StatefulWidget {
  const PushCenterView({
    super.key,
    required this.store,
    this.history,
    this.typeDays,
    this.audience,
  });
  final Store store;
  // Test seams: the sent notifications, the automatic ones per type and day, and the audience.
  final Stream<List<Entry>>? history;
  final Stream<List<Entry>>? typeDays;
  final Future<Map<String, dynamic>> Function()? audience;
  @override
  State<PushCenterView> createState() => _PushCenterViewState();
}

class _PushCenterViewState extends State<PushCenterView> {
  Store get store => widget.store;
  final title = TextEditingController(),
      body = TextEditingController(),
      person = TextEditingController();
  String audienceKind = 'all';
  String? town;
  bool sending = false;
  Map<String, dynamic>? audience;
  late final Stream<List<Entry>> history =
      widget.history ??
      store.firestore
          .collection('pushLog')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots()
          .map((s) => [for (final d in s.docs) Entry(d.id, d.data())]);
  late final Stream<List<Entry>> typeDays =
      widget.typeDays ??
      store.firestore
          .collection('pushTypeDaily')
          .where(
            'day',
            isGreaterThanOrEqualTo: _day(
              DateTime.now().subtract(const Duration(days: 29)),
            ),
          )
          .limit(400)
          .snapshots()
          .map((s) => [for (final d in s.docs) Entry(d.id, d.data())]);

  static String _day(DateTime d) => d
      .toUtc()
      .add(const Duration(hours: 5, minutes: 30))
      .toIso8601String()
      .substring(0, 10);

  @override
  void initState() {
    super.initState();
    _loadAudience();
  }

  @override
  void dispose() {
    for (final c in [title, body, person]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAudience() async {
    try {
      final a = widget.audience != null
          ? await widget.audience!()
          : await store.call('pushAudience', {});
      if (mounted) setState(() => audience = a);
    } catch (_) {
      /* the counts are a help, not needed to send */
    }
  }

  void toast(Object m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$m')));

  String get _who => switch (audienceKind) {
    'town' => 'everyone in ${town ?? 'the town'} with notifications on',
    'person' => person.text.trim().isEmpty ? 'one person' : person.text.trim(),
    _ =>
      'everyone with notifications on${audience == null ? '' : ' (${audience!['on']})'}',
  };

  Future<void> _send() async {
    final problem = title.text.trim().length < 2 || body.text.trim().length < 2
        ? 'Write a title and a message.'
        : audienceKind == 'town' && town == null
        ? 'Choose the town.'
        : audienceKind == 'person' && person.text.trim().isEmpty
        ? 'Give the person\'s email or account id.'
        : null;
    if (problem != null) return toast(problem);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Send this notification?'),
        content: Text('"${title.text.trim()}" goes to $_who now.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('push-send-confirm'),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Send now'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => sending = true);
    try {
      final r = await store.call('sendPushNotification', {
        'title': title.text.trim(),
        'body': body.text.trim(),
        'audience': audienceKind,
        if (audienceKind == 'town') 'town': town,
        if (audienceKind == 'person') 'person': person.text.trim(),
      });
      title.clear();
      body.clear();
      toast(
        'Sent to ${r['sent'] ?? 0} of ${r['recipients'] ?? 0} people${(r['noToken'] ?? 0) > 0 ? ' (${r['noToken']} have no device)' : ''}${(r['off'] ?? 0) > 0 ? '; this person turned notifications off' : ''}.',
      );
    } catch (e) {
      toast(e);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _switch(String field, bool on) async {
    try {
      await store.updateFields('settings', 'business', {
        field: on,
      }, fallback: Entry('business', {...store.business.data, field: on}));
    } catch (e) {
      toast(e);
    }
  }

  Future<void> _notOpened(Entry log) async {
    try {
      final r = await store.call('pushNotOpened', {'nid': log.id});
      final people = (r['people'] as List? ?? const []).cast<Map>();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text('Not opened: ${r['total'] ?? people.length}'),
          content: SizedBox(
            width: 420,
            height: 360,
            child: people.isEmpty
                ? const Center(
                    child: Text('Everyone who got it has opened it.'),
                  )
                : ListView(
                    children: [
                      for (final p in people)
                        ListTile(
                          dense: true,
                          title: Text(
                            '${p['name'] ?? ''}'.isEmpty
                                ? '${p['email'] ?? p['uid']}'
                                : '${p['name']}',
                          ),
                          subtitle: '${p['name'] ?? ''}'.isEmpty ? null : Text('${p['email'] ?? ''}'),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      toast(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final towns = [
      for (final t in (audience?['towns'] as List? ?? const []).cast<Map>())
        '${t['town']}',
    ];
    // Not a ListView: the live lists below must stay subscribed while scrolled out of sight.
    return SingleChildScrollView(
      key: const ValueKey('push-center'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Send a notification',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (audience != null)
            Text(
              '${audience!['on']} people have notifications on • ${audience!['off']} turned them off',
              key: const ValueKey('push-audience'),
            ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('Everyone')),
              ButtonSegment(value: 'town', label: Text('A town')),
              ButtonSegment(value: 'person', label: Text('One person')),
            ],
            selected: {audienceKind},
            onSelectionChanged: (v) => setState(() => audienceKind = v.first),
          ),
          if (audienceKind == 'town')
            DropdownButtonFormField<String>(
              key: const ValueKey('push-town'),
              initialValue: town,
              decoration: const InputDecoration(labelText: 'Town'),
              items: [
                for (final t
                    in (audience?['towns'] as List? ?? const []).cast<Map>())
                  DropdownMenuItem(
                    value: '${t['town']}',
                    child: Text('${t['town']} (${t['count']})'),
                  ),
              ],
              onChanged: (v) => setState(() => town = v),
            ),
          if (audienceKind == 'town' && towns.isEmpty)
            const Text('Nobody with notifications on has a town yet.'),
          if (audienceKind == 'person')
            TextField(
              key: const ValueKey('push-person'),
              controller: person,
              decoration: const InputDecoration(
                labelText: 'Email or account id',
              ),
            ),
          TextField(
            key: const ValueKey('push-title'),
            controller: title,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          TextField(
            key: const ValueKey('push-body'),
            controller: body,
            maxLength: 300,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Message'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('push-send'),
              onPressed: sending ? null : _send,
              icon: const Icon(Icons.send),
              label: Text(sending ? 'Sending...' : 'Send'),
            ),
          ),
          const Divider(height: 32),
          Text(
            'Automatic notifications',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          StreamBuilder<List<Entry>>(
            stream: typeDays,
            builder: (context, snapshot) {
              final sums = <String, (int, int)>{};
              for (final d in snapshot.data ?? const <Entry>[]) {
                final s = sums[d.text('type')] ?? (0, 0);
                sums[d.text('type')] = (
                  s.$1 + d.number('sent').round(),
                  s.$2 + d.number('opened').round(),
                );
              }
              return ListenableBuilder(
                listenable: store,
                builder: (context, _) => Column(
                  children: [
                    for (final (field, type, label, help)
                        in automaticNotifications)
                      SwitchListTile(
                        key: ValueKey('push-auto-$type'),
                        value:
                            store.business
                                .text(field, 'true')
                                .trim()
                                .toLowerCase() !=
                            'false',
                        onChanged: (v) => _switch(field, v),
                        title: Text(label),
                        subtitle: Text(
                          '$help\nLast 30 days: sent to ${sums[type]?.$1 ?? 0} devices • opened ${sums[type]?.$2 ?? 0}',
                        ),
                        isThreeLine: true,
                      ),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 32),
          Text('Sent by you', style: Theme.of(context).textTheme.titleLarge),
          StreamBuilder<List<Entry>>(
            stream: history,
            builder: (context, snapshot) {
              final logs = snapshot.data ?? const <Entry>[];
              if (snapshot.hasError) {
                return const Text('The notifications could not load.');
              }
              if (logs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Nothing sent yet.'),
                );
              }
              return Column(
                children: [
                  for (final log in logs)
                    Card(
                      key: ValueKey('push-log-${log.id}'),
                      child: ListTile(
                        title: Text(log.text('title')),
                        subtitle: Text(
                          '${switch (log.text('audience')) {
                            'town' => 'Town: ${log.text('town')}',
                            'person' => 'To: ${log.text('person')}',
                            _ => 'Everyone',
                          }}'
                          '${shopAdTime(log.data['createdAt']) == null ? '' : ' • ${shopAdDate(shopAdTime(log.data['createdAt']))}'}\n'
                          'Got it: ${log.number('sent').round()} of ${log.number('recipients').round()} • opened: ${log.number('opened').round()}'
                          '${log.number('noToken') > 0 ? ' • no device: ${log.number('noToken').round()}' : ''}${log.number('off') > 0 ? ' • notifications off: ${log.number('off').round()}' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: TextButton(
                          key: ValueKey('push-not-opened-${log.id}'),
                          onPressed: () => _notOpened(log),
                          child: const Text('Not opened'),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
