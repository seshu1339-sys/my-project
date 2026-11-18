import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/store.dart';
import '../../services/photo_compress.dart';
import 'company_messages_data.dart';

/// Admin > Vendors & Shops > Vendor Messages (owner, 18 Nov 2026: cost cuts part 5), and the same page in the staff app for staff the
/// admin allowed ([staff]: only their own vendors, never Payment / charges; the server checks both). Write a message with an optional
/// photo, choose who gets it (all vendors / towns + categories / Vendor IDs), an optional "show until" day, see "This will go to N
/// vendors", send (free push). The log below: who sent it, when, to whom, how many it was for and how many read it; edit (vendors see
/// "edited", the old words stay here) or delete (hidden from vendors, kept here).
class CompanyComposePage extends StatefulWidget {
  const CompanyComposePage({super.key, required this.store, this.staff = false, this.call, this.loadLog, this.pickPhoto});
  final Store store;
  final bool staff;

  /// Test seams: a server call, the log, and the photo picker (bytes or null).
  final Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> data)? call;
  final Future<List<CompanyMessage>> Function()? loadLog;
  final Future<List<int>?> Function()? pickPhoto;
  @override
  State<CompanyComposePage> createState() => _CompanyComposePageState();
}

class _CompanyComposePageState extends State<CompanyComposePage> {
  Store get store => widget.store;
  final title = TextEditingController(), body = TextEditingController(), oldAmount = TextEditingController(), newAmount = TextEditingController();
  final codes = TextEditingController(), senders = TextEditingController();
  String type = 'general', who = 'all', startsOn = '', showUntil = '';
  final towns = <String>{}, categories = <String>{};
  String? photo, note, previewText;
  bool busy = false;
  late Future<List<CompanyMessage>> log = _loadLog();

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) => (widget.call ?? store.call)(name, data);

  Future<List<CompanyMessage>> _loadLog() async {
    if (widget.loadLog != null) return widget.loadLog!();
    if (!store.live) return const [];
    Query<Map<String, dynamic>> q = store.firestore.collection('companyMessages');
    if (widget.staff) q = q.where('sentBy.uid', isEqualTo: store.user?.uid ?? '');
    final snap = await q.orderBy('sentAt', descending: true).limit(100).get();
    return [for (final d in snap.docs) CompanyMessage.from(d.id, d.data())];
  }

  @override
  void dispose() {
    for (final c in [title, body, oldAmount, newAmount, codes, senders]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _townOptions => ({for (final s in store.entries('shops')) if (companyTownKey(s.text('town')).isNotEmpty) companyTownKey(s.text('town'))}.toList()..sort());
  List<String> get _categoryOptions => ({
        for (final s in store.entries('shops')) if (companyCategoryKey(s.text('category')).isNotEmpty) companyCategoryKey(s.text('category')),
        for (final c in store.entries('categories')) if (c.text('name').isNotEmpty) companyCategoryKey(c.text('name')),
      }.toList()..sort());

  Map<String, dynamic> get _target => switch (who) {
    'all' => {'all': true},
    'codes' => {'vendorCodes': [for (final c in codes.text.split(RegExp(r'[,\s]+'))) if (c.trim().isNotEmpty) c.trim().toUpperCase()]},
    _ => {'towns': towns.toList(), 'categories': categories.toList()},
  };

  Map<String, dynamic> get _message => {
    'type': type,
    'title': title.text.trim(),
    'body': body.text.trim(),
    if (type == 'payment') ...{'oldAmount': num.tryParse(oldAmount.text.trim()) ?? '', 'newAmount': num.tryParse(newAmount.text.trim()) ?? '', 'startsOn': startsOn},
    if (showUntil.isNotEmpty) 'showUntil': showUntil,
    'target': _target,
    'photo': ?photo,
  };

  String _error(Object e) => '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '').replaceFirst('Bad state: ', '');

  Future<void> _preview() async {
    setState(() { busy = true; note = null; });
    try {
      final r = await _call('previewCompanyMessage', {'target': _target});
      setState(() => previewText = 'This will go to ${r['count']} vendors.');
    } catch (e) {
      setState(() => previewText = _error(e));
    }
    setState(() => busy = false);
  }

  Future<void> _send() async {
    setState(() { busy = true; note = null; });
    try {
      final r = await _call('sendCompanyMessage', _message);
      setState(() {
        note = 'Sent to ${r['meantFor']} vendors.';
        title.clear();
        body.clear();
        oldAmount.clear();
        newAmount.clear();
        photo = null;
        previewText = null;
        log = _loadLog();
      });
    } catch (e) {
      setState(() => note = _error(e));
    }
    setState(() => busy = false);
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = widget.pickPhoto != null ? await widget.pickPhoto!() : await (await ImagePicker().pickImage(source: ImageSource.gallery))?.readAsBytes();
      if (picked == null) return;
      final small = await shrinkProblemShotInBackground(picked is Uint8List ? picked : Uint8List.fromList(picked));
      if (small == null) return setState(() => note = 'That file is not a photo.');
      setState(() => photo = base64Encode(small));
    } catch (e) {
      setState(() => note = _error(e));
    }
  }

  Future<void> _date(void Function(String ymd) set) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 730)), initialDate: now);
    if (d != null) setState(() => set(d.toIso8601String().substring(0, 10)));
  }

  Future<void> _edit(CompanyMessage m) async {
    final t = TextEditingController(text: m.title), b = TextEditingController(text: m.body);
    final o = TextEditingController(text: m.oldAmount?.toString() ?? ''), n = TextEditingController(text: m.newAmount?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Change the message'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const ValueKey('cm-edit-title'), controller: t, decoration: const InputDecoration(labelText: 'Title')),
            TextField(key: const ValueKey('cm-edit-body'), controller: b, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'Message')),
            if (m.type == 'payment') ...[
              TextField(controller: o, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Old amount (₹)')),
              TextField(controller: n, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'New amount (₹)')),
            ],
            const SizedBox(height: 8),
            const Text('Vendors will see "edited". The old words stay in this log. No new push.', style: TextStyle(fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('cm-edit-save'), onPressed: () => Navigator.pop(d, true), child: const Text('Save change')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _call('editCompanyMessage', {
          'id': m.id, 'type': m.type, 'title': t.text.trim(), 'body': b.text.trim(), 'showUntil': m.showUntil,
          if (m.type == 'payment') ...{'oldAmount': num.tryParse(o.text.trim()) ?? '', 'newAmount': num.tryParse(n.text.trim()) ?? '', 'startsOn': m.startsOn},
        });
        setState(() { note = 'Changed.'; log = _loadLog(); });
      } catch (e) {
        setState(() => note = _error(e));
      }
    }
    for (final c in [t, b, o, n]) {
      c.dispose();
    }
  }

  Future<void> _delete(CompanyMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete this message?'),
        content: const Text('Vendors will not see it any more. It stays in this log, marked deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('cm-delete-yes'), onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _call('deleteCompanyMessage', {'id': m.id});
      setState(() { note = 'Deleted for vendors; kept in the log.'; log = _loadLog(); });
    } catch (e) {
      setState(() => note = _error(e));
    }
  }

  Future<void> _whoRead(CompanyMessage m) async {
    var names = <String>[];
    if (store.live) {
      final q = await store.firestore.collection('companyMessageReads').where('read', arrayContains: m.id).limit(500).get();
      final shops = {for (final s in store.entries('shops')) s.id: s};
      names = [for (final d in q.docs) [shops[d.id]?.text('name') ?? '', shops[d.id]?.text('vendorCode') ?? d.id].where((x) => x.isNotEmpty).join(' · ')];
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Read by ${m.readCount} of ${m.meantFor}'),
        content: SizedBox(width: 400, child: names.isEmpty ? const Text('Nobody yet.') : ListView(shrinkWrap: true, children: [for (final n in names) Text(n)])),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _saveSenders() async {
    try {
      final r = await _call('saveCompanyMessageSenders', {'staffCodes': [for (final c in senders.text.split(RegExp(r'[,\s]+'))) if (c.trim().isNotEmpty) c.trim()]});
      setState(() => note = 'Saved: ${(r['staff'] as List? ?? const []).length} staff may send.');
    } catch (e) {
      setState(() => note = _error(e));
    }
  }

  Widget _versions(CompanyMessage m) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Text('Earlier words (${m.versions.length})', style: const TextStyle(fontSize: 13)),
    children: [
      for (final v in m.versions)
        ListTile(
          dense: true,
          title: Text('${v['title'] ?? ''}'),
          subtitle: Text('${v['body'] ?? ''}${v['oldAmount'] != null ? '\n${rupees((v['oldAmount'] as num?)?.toDouble())} → ${rupees((v['newAmount'] as num?)?.toDouble())}' : ''}\nreplaced ${companyTime(v['replacedAt'] is Timestamp ? (v['replacedAt'] as Timestamp).toDate() : null)} by ${v['replacedBy'] ?? ''}'),
        ),
    ],
  );

  Widget _logCard(CompanyMessage m) => Card(
    key: ValueKey('cm-log-${m.id}'),
    color: m.deleted ? const Color(0xFFF5F5F5) : null,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Chip(label: Text(m.typeLabel), visualDensity: VisualDensity.compact),
          if (m.deleted) const Chip(label: Text('Deleted'), visualDensity: VisualDensity.compact),
          if (m.edited) const Text('edited', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
        ]),
        Text(m.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(m.body, maxLines: 3, overflow: TextOverflow.ellipsis),
        if (m.type == 'payment') Text('${rupees(m.oldAmount)} → ${rupees(m.newAmount)} from ${companyDay(m.startsOn)}'),
        const SizedBox(height: 4),
        Text(
          'Sent ${companyTime(m.sentAt)} by ${m.sentByRole == 'staff' ? 'staff ' : ''}${m.sentByCode} · to ${m.targetText}'
          '${m.showUntil.isNotEmpty ? ' · until ${companyDay(m.showUntil)}' : ''}',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        Text('For ${m.meantFor} vendors · read by ${m.readCount} · ${m.pushes} push${m.pushes == 1 ? '' : 'es'}',
            key: ValueKey('cm-counts-${m.id}'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        Wrap(spacing: 4, children: [
          TextButton(onPressed: () => _whoRead(m), child: const Text('Who read it')),
          if (!m.deleted) TextButton(key: ValueKey('cm-edit-${m.id}'), onPressed: () => _edit(m), child: const Text('Edit')),
          if (!m.deleted) TextButton(key: ValueKey('cm-delete-${m.id}'), onPressed: () => _delete(m), child: const Text('Delete')),
        ]),
        if (m.versions.isNotEmpty) _versions(m),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final types = {for (final e in companyMessageTypes.entries) if (!widget.staff || e.key != 'payment') e.key: e.value};
    if (!types.containsKey(type)) type = 'general';
    InputDecoration box(String label) => InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder());
    return ListView(
      key: const ValueKey('admin-company-messages'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Vendor Messages', style: Theme.of(context).textTheme.titleLarge),
        Text(widget.staff
            ? 'Messages from the LOCAMARKET Team to the vendors of your area. Payment and charges messages come only from the admin.'
            : 'Official messages from the LOCAMARKET Team. Vendors see them with the LOCAMARKET Team badge in the bell at the top of their app, and get a free push.'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const ValueKey('cm-type'),
          initialValue: type,
          decoration: box('Message type'),
          items: [for (final e in types.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => type = v ?? 'general'),
        ),
        const SizedBox(height: 8),
        TextField(key: const ValueKey('cm-title'), controller: title, maxLength: 80, decoration: box('Title')),
        TextField(key: const ValueKey('cm-body'), controller: body, minLines: 3, maxLines: 8, maxLength: 1500, decoration: box('Message')),
        if (type == 'payment') ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(width: 180, child: TextField(key: const ValueKey('cm-old'), controller: oldAmount, keyboardType: TextInputType.number, decoration: box('Old amount (₹)'))),
            SizedBox(width: 180, child: TextField(key: const ValueKey('cm-new'), controller: newAmount, keyboardType: TextInputType.number, decoration: box('New amount (₹)'))),
            OutlinedButton(key: const ValueKey('cm-starts'), onPressed: () => _date((d) => startsOn = d), child: Text(startsOn.isEmpty ? 'Starts on…' : 'Starts on ${companyDay(startsOn)}')),
          ]),
          const SizedBox(height: 8),
        ],
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(onPressed: _pickPhoto, icon: const Icon(Icons.image_outlined), label: Text(photo == null ? 'Add a photo (optional)' : 'Photo added')),
          if (photo != null) IconButton(tooltip: 'Remove photo', onPressed: () => setState(() => photo = null), icon: const Icon(Icons.close)),
          OutlinedButton(onPressed: () => _date((d) => showUntil = d), child: Text(showUntil.isEmpty ? 'Show until… (optional)' : 'Show until ${companyDay(showUntil)}')),
          if (showUntil.isNotEmpty) IconButton(tooltip: 'No end day', onPressed: () => setState(() => showUntil = ''), icon: const Icon(Icons.close)),
        ]),
        const SizedBox(height: 12),
        Text('Who gets it', style: Theme.of(context).textTheme.titleMedium),
        SegmentedButton<String>(
          key: const ValueKey('cm-who'),
          segments: [
            ButtonSegment(value: 'all', label: Text(widget.staff ? 'All my vendors' : 'All vendors')),
            const ButtonSegment(value: 'place', label: Text('Town / category')),
            const ButtonSegment(value: 'codes', label: Text('Vendor IDs')),
          ],
          selected: {who},
          onSelectionChanged: (s) => setState(() { who = s.first; previewText = null; }),
        ),
        if (who == 'place') ...[
          const SizedBox(height: 8),
          const Text('Towns (none = every town)'),
          Wrap(spacing: 6, children: [
            for (final t in _townOptions)
              FilterChip(key: ValueKey('cm-town-$t'), label: Text(t), selected: towns.contains(t), onSelected: (on) => setState(() { on ? towns.add(t) : towns.remove(t); previewText = null; })),
          ]),
          const SizedBox(height: 8),
          const Text('Categories (none = every category)'),
          Wrap(spacing: 6, children: [
            for (final c in _categoryOptions)
              FilterChip(key: ValueKey('cm-cat-$c'), label: Text(c), selected: categories.contains(c), onSelected: (on) => setState(() { on ? categories.add(c) : categories.remove(c); previewText = null; })),
          ]),
        ],
        if (who == 'codes')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(key: const ValueKey('cm-codes'), controller: codes, minLines: 1, maxLines: 4, decoration: box('Vendor IDs, separated by commas (VEN-NRPM-116-325, ...)')),
          ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton(key: const ValueKey('cm-preview'), onPressed: busy ? null : _preview, child: const Text('How many will get it?')),
          FilledButton.icon(key: const ValueKey('cm-send'), onPressed: busy ? null : _send, icon: const Icon(Icons.send), label: const Text('Send')),
          if (previewText != null) Text(previewText!, key: const ValueKey('cm-preview-text'), style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        if (note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note!, key: const ValueKey('cm-note'))),
        if (!widget.staff) ...[
          const Divider(height: 32),
          Text('Staff who may send', style: Theme.of(context).textTheme.titleMedium),
          const Text('Only to the vendors linked to them (their area), never Payment / charges. Staff IDs separated by commas; empty = only the admin.'),
          const SizedBox(height: 6),
          if (store.live)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: store.firestore.collection('companyMessageSenders').doc('main').snapshots(),
              builder: (context, snap) {
                final list = (snap.data?.data()?['staff'] as List? ?? const []).whereType<Map>().toList();
                return Text(list.isEmpty ? 'Now: only the admin.' : 'Now: ${list.map((s) => '${s['code']} ${s['name'] ?? ''}'.trim()).join(', ')}');
              },
            ),
          Row(children: [
            Expanded(child: TextField(key: const ValueKey('cm-senders'), controller: senders, decoration: box('Staff IDs'))),
            const SizedBox(width: 8),
            OutlinedButton(key: const ValueKey('cm-senders-save'), onPressed: _saveSenders, child: const Text('Save')),
          ]),
        ],
        const Divider(height: 32),
        Text('Sent messages', style: Theme.of(context).textTheme.titleMedium),
        FutureBuilder<List<CompanyMessage>>(
          future: log,
          builder: (context, snap) {
            if (snap.hasError) return Text('The log could not load: ${_error(snap.error!)}');
            if (!snap.hasData) return const LinearProgressIndicator();
            if (snap.data!.isEmpty) return const Text('No messages sent yet.');
            return Column(children: [for (final m in snap.data!) _logCard(m)]);
          },
        ),
      ],
    );
  }
}
