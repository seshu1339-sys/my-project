import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/ads.dart';
import '../domain/ads_admin.dart';
import '../domain/catalog.dart';
import '../domain/towns.dart';
import 'ad_box.dart';
import 'admin_ad_reports.dart';
import 'admin_list_labels.dart';
import 'ads_column.dart';
import 'color_picker_field.dart';
import 'shared.dart';

/// The number the Ads section carries everywhere (the old "Advertisement boxes" number); each ad is a sub-number, e.g. 23.2.
const adsSectionNumber = 23;

String _label(String label, Object? current) => current == null ? label : '$label ($current)';

/// Settings -> Ads: the settings that apply to ALL ads (one form), then the list of ads (add, edit, duplicate, delete, renew, reorder).
class AdminAdsPage extends StatefulWidget {
  const AdminAdsPage({super.key, required this.store, this.decide, this.remove});
  final Store store;
  // How the admin's decisions reach the server (the functions decideVendorAd / removeVendorAd); replaced in tests.
  final Future<void> Function(String submissionId, bool approved, String reason)? decide;
  final Future<void> Function(String adId, String reason)? remove;
  @override
  State<AdminAdsPage> createState() => _AdminAdsPageState();
}

class _AdminAdsPageState extends State<AdminAdsPage> {
  final search = TextEditingController();
  String? status;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Store get store => widget.store;

  Future<void> _edit([Entry? ad]) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AdEditorPage(store: store, ad: ad)));
    if (mounted) setState(() {});
  }

  Future<void> _delete(Entry ad) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete this ad?'),
        content: Text('"${ad.text('title', ad.text('name'))}" is removed from the site and from this list. This cannot be undone. To keep it, switch it off instead.'),
        actions: [
          TextButton(key: const ValueKey('ad-delete-cancel'), onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('ad-delete-confirm'), onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await store.delete('ads', ad.id);
    await store.delete('adsPrivate', ad.id);
  }

  /// Asks the admin for a reason the vendor will read. Returns null when cancelled (and, when [required], when left empty).
  Future<String?> _askReason(String title, {required bool required}) =>
      showDialog<String>(context: context, builder: (_) => _ReasonDialog(title: title, required: required));

  Future<void> _decide(Entry submission, bool approved) async {
    var reason = '';
    if (!approved) {
      final asked = await _askReason('Reject this ad?', required: true);
      if (asked == null) return;
      reason = asked;
    }
    try {
      final decide = widget.decide ?? (id, ok, why) => store.call('decideVendorAd', {'submissionId': id, 'approved': ok, 'reason': why});
      await decide(submission.id, approved, reason);
      if (mounted) message(context, approved ? 'Approved. The ad is live now.' : 'Rejected. The vendor has been told why.');
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  Future<void> _removeVendorAd(Entry ad) async {
    final reason = await _askReason('Remove this vendor ad?', required: false);
    if (reason == null) return;
    try {
      final remove = widget.remove ?? (id, why) => store.call('removeVendorAd', {'adId': id, 'reason': why});
      await remove(ad.id, reason);
      if (mounted) message(context, 'Removed. The vendor has been told.');
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  Widget _pendingCard(Entry s, AdsConfig config) {
    final current = s.text('adId').isEmpty ? null : store.entries('ads').where((a) => a.id == s.text('adId')).firstOrNull;
    return Card(
      key: ValueKey('pending-${s.id}'),
      color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: .4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.text('kind') == 'change' ? 'Change to a live ad — ${s.text('shopName')} ${s.text('vendorCode')}' : 'New ad — ${s.text('shopName')} ${s.text('vendorCode')}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Plan ${adPackages[s.text('package')] ?? 'Normal'}, ${s.number('durationDays').round()} days'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (current != null) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Live now', style: TextStyle(fontSize: 12)), SizedBox(width: 220, height: 140, child: AdBox(ad: current, config: config))]),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(current != null ? 'Wants to change to' : 'New ad', style: const TextStyle(fontSize: 12)), SizedBox(width: 220, height: 140, child: AdBox(ad: s, config: config))]),
              ],
            ),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton.icon(key: ValueKey('approve-${s.id}'), onPressed: () => _decide(s, true), icon: const Icon(Icons.check), label: const Text('Approve')),
              const SizedBox(width: 8),
              OutlinedButton.icon(key: ValueKey('reject-${s.id}'), onPressed: () => _decide(s, false), icon: const Icon(Icons.close), label: const Text('Reject')),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _duplicate(Entry ad) async {
    final all = store.entries('ads');
    final order = all.isEmpty ? 1 : all.map((a) => a.number('order')).reduce((a, b) => a > b ? a : b) + 1;
    final id = 'ad${DateTime.now().microsecondsSinceEpoch}';
    await store.save('ads', duplicateAd(ad, id, order.round()));
    final privateData = await store.freshRecord('adsPrivate', ad.id);
    if (privateData != null) await store.save('adsPrivate', Entry(id, privateData));
    if (mounted) message(context, 'Copy created (switched off). Edit it, then switch it on.');
  }

  Future<void> _renew(Entry ad, String by) async {
    var end = renewedEnd(ad, DateTime.now(), by: by);
    if (by == 'custom') {
      final picked = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 30)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 1500)));
      if (picked == null) return;
      end = DateTime(picked.year, picked.month, picked.day, 23, 59).toIso8601String();
    }
    await store.updateFields('ads', ad.id, {'endsAt': end, 'active': true});
    if (mounted) message(context, 'Renewed: now runs until ${end.substring(0, 10)}.');
  }

  /// Copies the old ad boxes into the unified list (the old ones stay where they are). Switched on as they were.
  Future<void> _import() async {
    final todo = adsToImport(store.entries('promotions'), store.entries('ads'));
    final start = store.entries('ads').length;
    for (final (i, p) in todo.indexed) {
      await store.save('ads', adFromPromotion(p, start + i + 1));
    }
    if (mounted) message(context, '${todo.length} ad box(es) copied into the Ads list. The old ones are untouched.');
  }

  Future<void> _toggle(Entry ad) => store.updateFields('ads', ad.id, {'active': !ad.active});

  Future<void> _reorder(List<Entry> sorted, int oldIndex, int newIndex) async {
    final changes = reorderChanges(sorted, oldIndex, newIndex);
    if (changes.isNotEmpty) await store.updateMany('ads', changes);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Entry>>(
    stream: store.watchEntries('adSubmissions'),
    builder: (context, submissionsSnapshot) => _body(context, [for (final s in submissionsSnapshot.data ?? const <Entry>[]) if (s.text('status') == 'pending') s]),
  );

  Widget _body(BuildContext context, List<Entry> pendingSubmissions) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final now = DateTime.now();
      final all = sortedByOrder(store.entries('ads'));
      final shown = status == 'pending' ? <Entry>[] : filterAds(all, now, status: status, query: search.text);
      final adsConfig = AdsConfig.from(store.entries('settings'));
      final canReorder = status == null && search.text.trim().isEmpty;
      final soon = adsEndingSoon(all, now);
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Ads  ·  $adsSectionNumber', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text('Every ad uses the same box, size and rules. Each ad below is a sub-number of this section.'),
          const SizedBox(height: 12),
          if (soon.isNotEmpty)
            Card(
              key: const ValueKey('ads-expiring'),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${soon.length} ${soon.length == 1 ? 'ad ends' : 'ads end'} within 3 days', style: const TextStyle(fontWeight: FontWeight.bold)),
                    for (final ad in soon)
                      Row(
                        children: [
                          Expanded(child: Text('${ad.text('title', ad.text('name'))} — ${adDaysLeft(ad, now)} day(s) left')),
                          TextButton(onPressed: () => _renew(ad, 'week'), child: const Text('+1 week')),
                          TextButton(onPressed: () => _renew(ad, 'month'), child: const Text('+1 month')),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          if (pendingSubmissions.isNotEmpty && (status == null || status == 'pending')) ...[
            Text('Pending approval (${pendingSubmissions.length})', key: const ValueKey('ads-pending-title'), style: Theme.of(context).textTheme.titleLarge),
            const Text('Vendors sent these. Nothing is shown to customers until you approve it.'),
            for (final s in pendingSubmissions) _pendingCard(s, adsConfig),
            const Divider(),
          ],
          ExpansionTile(
            key: const ValueKey('ads-common-settings'),
            tilePadding: EdgeInsets.zero,
            title: Text('Common settings for all ads  ·  $adsSectionNumber', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Slots, box size, corners, gap, border, shadow, animation, speed, seconds'),
            children: [AdsConfigForm(store: store)],
          ),
          const Divider(),
          Row(
            children: [
              Expanded(child: Text('All ads (${all.length})', style: Theme.of(context).textTheme.titleLarge)),
              if (adsToImport(store.entries('promotions'), all).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton.icon(key: const ValueKey('ad-import'), onPressed: _import, icon: const Icon(Icons.download), label: const Text('Copy current ad boxes here')),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton.icon(
                  key: const ValueKey('ad-reports'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AdminAdReportsPage(store: store))),
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('Reports'),
                ),
              ),
              FilledButton.icon(key: const ValueKey('ad-add'), onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add Ad')),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('ad-search'),
            controller: search,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search by shop name, vendor code (VN…) or title', isDense: true, border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(key: const ValueKey('ad-filter-all'), label: Text('All (${all.length})'), selected: status == null, onSelected: (_) => setState(() => status = null)),
              for (final e in adStatusLabels.entries)
                ChoiceChip(
                  key: ValueKey('ad-filter-${e.key}'),
                  label: Text('${e.value} (${e.key == 'pending' ? pendingSubmissions.length : all.where((a) => adStatus(a, now) == e.key).length})'),
                  selected: status == e.key,
                  onSelected: (_) => setState(() => status = status == e.key ? null : e.key),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (status == 'pending')
            const SizedBox.shrink()
          else if (shown.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('No ads here. Use "Add Ad" to create one.'))
          else if (canReorder)
            ReorderableListView.builder(
              key: const ValueKey('ads-reorderable'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: shown.length,
              onReorderItem: (a, b) => _reorder(all, a, b >= a ? b + 1 : b),
              itemBuilder: (context, i) => _row(context, shown[i], i, now, drag: true),
            )
          else
            for (final ad in shown) _row(context, ad, all.indexOf(ad), now),
        ],
      );
    },
  );

  Widget _row(BuildContext context, Entry ad, int index, DateTime now, {bool drag = false}) {
    final st = adStatus(ad, now);
    final left = adDaysLeft(ad, now);
    final color = switch (st) {
      'live' => Colors.green,
      'scheduled' => Colors.blue,
      'expired' || 'rejected' => Colors.red,
      'pending' => Colors.orange,
      _ => Colors.grey,
    };
    return Card(
      key: ValueKey('ad-row-${ad.id}'),
      child: ListTile(
        leading: SizedBox(
          width: 96,
          child: Row(
            children: [
              if (drag) ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_indicator)),
              Text('$adsSectionNumber.${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        title: Text(ad.text('title', ad.text('name', '(no title)'))),
        subtitle: Text([
          if (ad.text('shopName').isNotEmpty) ad.text('shopName'),
          if (ad.text('vendorCode').isNotEmpty) ad.text('vendorCode'),
          if (left != null) st == 'expired' ? 'ended' : '$left day(s) left',
          adPackages[ad.text('package')] ?? 'Normal',
        ].join('  ·  ')),
        trailing: Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(label: Text(adStatusLabels[st] ?? st), backgroundColor: color.withValues(alpha: .15), side: BorderSide(color: color)),
            Switch(key: ValueKey('ad-active-${ad.id}'), value: ad.active, onChanged: (_) => _toggle(ad)),
            PopupMenuButton<String>(
              key: ValueKey('ad-menu-${ad.id}'),
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _edit(ad);
                  case 'duplicate':
                    _duplicate(ad);
                  case 'remove':
                    _removeVendorAd(ad);
                  case 'delete':
                    _delete(ad);
                  default:
                    _renew(ad, v);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                if (ad.text('vendorId').isNotEmpty) const PopupMenuItem(value: 'remove', child: Text('Remove vendor ad…')),
                const PopupMenuItem(value: 'week', child: Text('Renew +1 week')),
                const PopupMenuItem(value: 'month', child: Text('Renew +1 month')),
                const PopupMenuItem(value: 'custom', child: Text('Renew to a date…')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
        onTap: () => _edit(ad),
      ),
    );
  }
}

/// The settings for ALL ads, with each setting's current value in brackets next to its name.
class AdsConfigForm extends StatefulWidget {
  const AdsConfigForm({super.key, required this.store});
  final Store store;
  @override
  State<AdsConfigForm> createState() => _AdsConfigFormState();
}

class _AdsConfigFormState extends State<AdsConfigForm> {
  late Map<String, dynamic> values;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    values = {...widget.store.entries('settings').where((e) => e.id == 'adsConfig').firstOrNull?.data ?? const {}}..remove('name');
  }

  AdsConfig get current => AdsConfig.from(widget.store.entries('settings'));

  /// How many test devices are saved right now (shown next to the field).
  int get _testDeviceCount => ((widget.store.entries('settings').where((e) => e.id == 'adsConfig').firstOrNull?.text('testDevices') ?? '')).split(RegExp(r'[,\s]+')).where((x) => x.isNotEmpty).length;

  void _set(String key, Object? value) => setState(() => value == null || '$value'.isEmpty ? values.remove(key) : values[key] = value);

  Widget _number(String key, String label, Object currentValue, {String suffix = ''}) => SizedBox(
    width: 260,
    child: TextFormField(
      key: ValueKey('ads-config-$key-${values[key]}'),
      initialValue: values[key] == null ? '' : '${values[key]}',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: _label(label, '$currentValue$suffix'), isDense: true, border: const OutlineInputBorder()),
      onChanged: (v) {
        final n = double.tryParse(v.trim());
        if (n == null) {
          values.remove(key);
        } else {
          values[key] = n == n.roundToDouble() ? n.round() : n;
        }
      },
    ),
  );

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await widget.store.save('settings', Entry('adsConfig', {'name': 'Ads settings', ...values}));
      if (mounted) message(context, 'Ads settings saved. They apply to every ad.');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final c = current;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _number('desktopSlots', 'Ad boxes on a computer screen', c.desktopSlots),
                _number('mobileSlots', 'Ad boxes on a phone', c.mobileSlots),
                _number('boxHeight', 'Box height, px (largest)', c.boxHeight.round(), suffix: 'px'),
                _number('radius', 'Corner radius', c.radius.round(), suffix: 'px'),
                _number('gap', 'Gap between boxes', c.gap.round(), suffix: 'px'),
                _number('borderWidth', 'Border thickness', c.borderWidth.round(), suffix: 'px'),
                _number('shadow', 'Shadow strength (0–1)', c.shadow),
                _number('seconds', 'Seconds each ad stays (default)', c.seconds),
                _number('animationSpeed', 'Animation speed (1 slow – 10 fast)', c.animationSpeed),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('ads-config-animation-${values['animation']}'),
                    initialValue: values['animation'] as String? ?? c.animation,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: _label('Change animation', adAnimations[c.animation] ?? 'Mix of all'), isDense: true, border: const OutlineInputBorder()),
                    items: [
                      for (final e in adAnimations.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                      const DropdownMenuItem(value: 'mix', child: Text('Mix of all')),
                    ],
                    onChanged: (v) => _set('animation', v),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    key: ValueKey('ads-config-label-${values['label']}'),
                    initialValue: values['label'] as String? ?? '',
                    decoration: InputDecoration(labelText: _label('Label on every ad', c.label), isDense: true, border: const OutlineInputBorder()),
                    onChanged: (v) => v.trim().isEmpty ? values.remove('label') : values['label'] = v.trim(),
                  ),
                ),
                SizedBox(
                  width: 540,
                  child: TextFormField(
                    key: ValueKey('ads-config-testDevices-${values['testDevices']}'),
                    initialValue: values['testDevices'] as String? ?? '',
                    decoration: InputDecoration(
                      labelText: _label('Test devices: views from these device ids are never counted (comma-separated)', _testDeviceCount == 0 ? 'none' : '$_testDeviceCount device(s)'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => v.trim().isEmpty ? values.remove('testDevices') : values['testDevices'] = v.trim(),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: ColorPickerField(label: _label('Border color', c.borderColor), value: values['borderColor'] as String? ?? '', onChanged: (v) => _set('borderColor', v)),
                ),
              ],
            ),
            SwitchListTile(
              key: const ValueKey('ads-config-fit'),
              contentPadding: EdgeInsets.zero,
              title: Text(_label('Fit the boxes to the screen height so none is cut off', c.fitToScreen ? 'On' : 'Off')),
              value: values['fitToScreen'] != 'false',
              onChanged: (v) => _set('fitToScreen', v ? null : 'false'),
            ),
            SwitchListTile(
              key: const ValueKey('ads-config-pause'),
              contentPadding: EdgeInsets.zero,
              title: Text(_label('Pause when the mouse is over an ad or it is touched', c.pauseOnHover ? 'On' : 'Off')),
              value: values['pauseOnHover'] != 'false',
              onChanged: (v) => _set('pauseOnHover', v ? null : 'false'),
            ),
            FilledButton(key: const ValueKey('ads-config-save'), onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save ads settings')),
          ],
        ),
      );
    },
  );
}

/// One ad on one screen: Active switch on top, then four groups (Content, When & where, How much, Shop & payment).
class AdEditorPage extends StatefulWidget {
  const AdEditorPage({super.key, required this.store, this.ad});
  final Store store;
  final Entry? ad;
  @override
  State<AdEditorPage> createState() => _AdEditorPageState();
}

class _AdEditorPageState extends State<AdEditorPage> {
  late final String id = widget.ad?.id ?? 'ad${DateTime.now().microsecondsSinceEpoch}';
  late Map<String, dynamic> values = {...?widget.ad?.data};
  final text = <String, TextEditingController>{};
  bool busy = false;
  String? error;

  TextEditingController _c(String key) => text.putIfAbsent(key, () => TextEditingController(text: values[key] == null ? '' : '${values[key]}'));

  @override
  void initState() {
    super.initState();
    values.putIfAbsent('active', () => true);
    values.putIfAbsent('status', () => 'approved');
    values.putIfAbsent('contentType', () => 'image');
    if (widget.ad == null) values.addAll(packageFill('normal'));
    _loadPrivate();
  }

  Future<void> _loadPrivate() async {
    if (widget.ad == null) return;
    final data = await widget.store.freshRecord('adsPrivate', id);
    if (data == null || !mounted) return;
    setState(() {
      values.addAll(data);
      for (final k in adPrivateFields) {
        text[k]?.text = data[k] == null ? '' : '${data[k]}';
      }
    });
  }

  @override
  void dispose() {
    for (final c in text.values) {
      c.dispose();
    }
    super.dispose();
  }

  String s(String key) => values[key] == null ? '' : '${values[key]}';
  void _set(String key, Object? v) => setState(() => v == null || '$v'.isEmpty ? values.remove(key) : values[key] = v);

  Widget _field(String key, String label, {int lines = 1, TextInputType? type, String? hint}) => TextField(
    key: ValueKey('ad-field-$key'),
    controller: _c(key),
    minLines: lines,
    maxLines: lines,
    keyboardType: type,
    decoration: InputDecoration(labelText: label, hintText: hint, isDense: true, border: const OutlineInputBorder()),
    onChanged: (v) => v.trim().isEmpty ? values.remove(key) : values[key] = v.trim(),
  );

  Future<void> _upload(String key) async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      setState(() => busy = true);
      final url = await widget.store.upload(file, folder: 'ads');
      if (mounted) _set(key, url);
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pickDate(String key, {required bool end}) async {
    final initial = DateTime.tryParse(s(key)) ?? DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2024), lastDate: DateTime(2100));
    if (picked == null) return;
    _set(key, (end ? DateTime(picked.year, picked.month, picked.day, 23, 59) : DateTime(picked.year, picked.month, picked.day)).toIso8601String());
  }

  Future<void> _addSlot() async {
    final from = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0), helpText: 'From');
    if (from == null || !mounted) return;
    final to = await showTimePicker(context: context, initialTime: TimeOfDay(hour: (from.hour + 3) % 24, minute: 0), helpText: 'Until');
    if (to == null) return;
    final slots = adSlots(Entry(id, values))..add((from.hour * 60 + from.minute, to.hour * 60 + to.minute));
    _set('slots', slotsToText(slots));
  }

  String? _validate() {
    if (s('title').isEmpty && s('imageUrl').isEmpty) return 'Add a title or a picture.';
    final start = DateTime.tryParse(s('startsAt')), end = DateTime.tryParse(s('endsAt'));
    if (start != null && end != null && end.isBefore(start)) return 'The end date is before the start date.';
    final action = s('tapAction');
    if ((action == 'call' || action == 'whatsapp') && s('tapValue').replaceAll(RegExp(r'[^0-9]'), '').length < 10) return 'Enter a 10-digit phone number for the tap action.';
    if ((action == 'link') && !s('tapValue').startsWith('https://')) return 'A link must start with https://';
    if (action == 'shop' && s('tapValue').isEmpty) return 'Choose the shop.';
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    setState(() => error = problem);
    if (problem != null) return;
    setState(() => busy = true);
    try {
      final all = widget.store.entries('ads');
      final next = all.isEmpty ? 1 : all.map((a) => a.number('order')).reduce((a, b) => a > b ? a : b) + 1;
      values['order'] ??= next.round();
      values['title'] = s('title');
      final split = splitAdFields(values);
      await widget.store.save('ads', Entry(id, split.public));
      await widget.store.save('adsPrivate', Entry(id, split.private));
      if (mounted) {
        message(context, 'Ad saved.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _group(String title, String key, List<Widget> children) => Card(
    child: ExpansionTile(
      key: ValueKey('ad-group-$key'),
      initiallyExpanded: true,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final w in children) Padding(padding: const EdgeInsets.only(top: 12), child: w)],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final config = AdsConfig.from(widget.store.entries('settings'));
    final previewHeight = adBoxHeight(config, MediaQuery.sizeOf(context).height, config.desktopSlots);
    final days = adDays(Entry(id, values));
    final slots = adSlots(Entry(id, values));
    final package = s('package').isEmpty ? 'normal' : s('package');
    final type = s('contentType');
    final shops = widget.store.entries('shops');
    final towns = parseServiceTowns(widget.store.business.text('serviceTowns')).map((t) => t.name).toList();
    final chosenTowns = parseLocationList(s('locations')).map((t) => t.toLowerCase()).toSet();
    final number = widget.ad == null ? '$adsSectionNumber.${widget.store.entries('ads').length + 1}' : '$adsSectionNumber.${sortedByOrder(widget.store.entries('ads')).indexWhere((a) => a.id == id) + 1}';
    return Scaffold(
      appBar: AppBar(title: Text(widget.ad == null ? 'Add Ad  ·  $number' : 'Edit Ad  ·  $number')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile(
            key: const ValueKey('ad-active'),
            title: Text(_label('This ad is', values['active'] == false ? 'Inactive' : 'Active'), style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Inactive ads are saved but never shown to customers.'),
            value: values['active'] != false,
            onChanged: (v) => _set('active', v),
          ),
          _group('1 · Content', 'content', [
            SegmentedButton<String>(
              key: const ValueKey('ad-content-type'),
              segments: const [
                ButtonSegment(value: 'image', label: Text('Ready image')),
                ButtonSegment(value: 'text', label: Text('Text only')),
                ButtonSegment(value: 'imageText', label: Text('Image + text')),
              ],
              selected: {type},
              onSelectionChanged: (v) => _set('contentType', v.first),
            ),
            if (type != 'text') ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(key: const ValueKey('ad-upload'), onPressed: busy ? null : () => _upload('imageUrl'), icon: const Icon(Icons.upload), label: Text(s('imageUrl').isEmpty ? 'Upload image' : 'Replace image')),
                if (s('imageUrl').isNotEmpty) OutlinedButton.icon(key: const ValueKey('ad-remove-image'), onPressed: () => _set('imageUrl', null), icon: const Icon(Icons.delete_outline), label: const Text('Remove image')),
                OutlinedButton.icon(key: const ValueKey('ad-upload-mobile'), onPressed: busy ? null : () => _upload('mobileImageUrl'), icon: const Icon(Icons.phone_android), label: Text(s('mobileImageUrl').isEmpty ? 'Separate phone image (optional)' : 'Replace phone image')),
                if (s('mobileImageUrl').isNotEmpty) OutlinedButton.icon(onPressed: () => _set('mobileImageUrl', null), icon: const Icon(Icons.delete_outline), label: const Text('Remove phone image')),
              ]),
            ],
            if (type != 'image') ...[
              _field('title', 'Title'),
              _field('text', 'Small text', lines: 2),
              Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(width: 240, child: ColorPickerField(label: _label('Text color', s('textColor').isEmpty ? 'default' : s('textColor')), value: s('textColor'), onChanged: (v) => _set('textColor', v))),
                SizedBox(width: 240, child: ColorPickerField(label: _label('Background color', s('backgroundColor').isEmpty ? 'default' : s('backgroundColor')), value: s('backgroundColor'), onChanged: (v) => _set('backgroundColor', v))),
              ]),
            ] else
              _field('title', 'Title (kept for the admin list; not drawn on a ready image)'),
            Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('ad-badge-${s('badge')}'),
                  isExpanded: true,
                  initialValue: const ['', 'New', 'Offer'].contains(s('badge')) ? s('badge') : 'custom',
                  decoration: InputDecoration(labelText: _label('Badge', s('badge').isEmpty ? 'none' : s('badge')), isDense: true, border: const OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('No badge')),
                    DropdownMenuItem(value: 'New', child: Text('New')),
                    DropdownMenuItem(value: 'Offer', child: Text('Offer')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom (e.g. 50% Off)')),
                  ],
                  onChanged: (v) => _set('badge', v == 'custom' ? '50% Off' : v),
                ),
              ),
              if (!const ['', 'New', 'Offer'].contains(s('badge'))) SizedBox(width: 240, child: _field('badge', 'Custom badge text')),
              SizedBox(width: 240, child: _field('coupon', 'Coupon code (optional)')),
            ]),
            Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('ad-tap-${s('tapAction')}'),
                  isExpanded: true,
                  initialValue: s('tapAction'),
                  decoration: InputDecoration(labelText: _label('When tapped', const {'call': 'Call', 'whatsapp': 'WhatsApp', 'shop': 'Open shop page', 'link': 'Open link'}[s('tapAction')] ?? 'nothing'), isDense: true, border: const OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Nothing')),
                    DropdownMenuItem(value: 'call', child: Text('Call')),
                    DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp')),
                    DropdownMenuItem(value: 'shop', child: Text('Open shop page')),
                    DropdownMenuItem(value: 'link', child: Text('Open link')),
                  ],
                  onChanged: (v) {
                    values.remove('tapValue');
                    text['tapValue']?.clear();
                    _set('tapAction', v);
                  },
                ),
              ),
              if (s('tapAction') == 'shop')
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('ad-tap-shop-${s('tapValue')}'),
                    isExpanded: true,
                    initialValue: shops.any((x) => x.id == s('tapValue')) ? s('tapValue') : null,
                    decoration: const InputDecoration(labelText: 'Shop', isDense: true, border: OutlineInputBorder()),
                    items: [for (final x in shops) DropdownMenuItem(value: x.id, child: Text(x.text('name')))],
                    onChanged: (v) => _set('tapValue', v),
                  ),
                )
              else if (s('tapAction').isNotEmpty)
                SizedBox(width: 240, child: _field('tapValue', s('tapAction') == 'link' ? 'Link (https://…)' : 'Phone number')),
            ]),
            Text('Preview — the box on the website (${config.desktopSlots} fit the screen; the picture is cropped to fill it)', style: const TextStyle(fontSize: 12)),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(key: const ValueKey('ad-preview'), width: 300, height: previewHeight, child: AdBox(ad: Entry(id, values), config: config)),
            ),
          ]),
          _group('2 · When & where', 'when', [
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(key: const ValueKey('ad-start'), onPressed: () => _pickDate('startsAt', end: false), icon: const Icon(Icons.event), label: Text(s('startsAt').isEmpty ? 'Start date: from now' : 'Start: ${s('startsAt').substring(0, 10)}')),
              if (s('startsAt').isNotEmpty) TextButton(onPressed: () => _set('startsAt', null), child: const Text('Clear')),
              OutlinedButton.icon(key: const ValueKey('ad-end'), onPressed: () => _pickDate('endsAt', end: true), icon: const Icon(Icons.event_busy), label: Text(s('endsAt').isEmpty ? 'End date: never' : 'End: ${s('endsAt').substring(0, 10)}')),
              if (s('endsAt').isNotEmpty) TextButton(onPressed: () => _set('endsAt', null), child: const Text('Clear')),
              if (widget.ad != null) ...[
                TextButton(key: const ValueKey('ad-renew-week'), onPressed: () => _set('endsAt', renewedEnd(Entry(id, values), DateTime.now(), by: 'week')), child: const Text('Renew +1 week')),
                TextButton(key: const ValueKey('ad-renew-month'), onPressed: () => _set('endsAt', renewedEnd(Entry(id, values), DateTime.now(), by: 'month')), child: const Text('Renew +1 month')),
              ],
            ]),
            Text(_label('Days of the week', days.length == 7 ? 'every day' : days.map((d) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1]).join(', ')), style: const TextStyle(fontWeight: FontWeight.w600)),
            Wrap(spacing: 6, children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  key: ValueKey('ad-day-$d'),
                  label: Text(const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1]),
                  selected: days.contains(d),
                  onSelected: (on) {
                    final next = {...days};
                    on ? next.add(d) : next.remove(d);
                    _set('days', next.length == 7 || next.isEmpty ? null : (next.toList()..sort()).join(','));
                  },
                ),
            ]),
            Text(_label('Daily time slots', slots.isEmpty ? 'all day' : slotsToText(slots)), style: const TextStyle(fontWeight: FontWeight.w600)),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final (i, slot) in slots.indexed)
                InputChip(
                  key: ValueKey('ad-slot-chip-$i'),
                  label: Text(slotsToText([slot]).replaceAll('-', ' – ')),
                  onDeleted: () => _set('slots', slotsToText([...slots]..removeAt(i))),
                ),
              ActionChip(key: const ValueKey('ad-add-slot'), avatar: const Icon(Icons.add), label: const Text('Add time slot'), onPressed: _addSlot),
            ]),
            Text(_label('Show only in these places', s('locations').isEmpty ? 'everywhere' : s('locations')), style: const TextStyle(fontWeight: FontWeight.w600)),
            Wrap(spacing: 6, runSpacing: 6, children: [
              FilterChip(
                key: const ValueKey('ad-loc-ap'),
                label: const Text('All Andhra Pradesh'),
                selected: chosenTowns.contains('andhra pradesh'),
                onSelected: (on) => _set('locations', on ? 'Andhra Pradesh' : null),
              ),
              for (final t in towns)
                FilterChip(
                  label: Text(t),
                  selected: chosenTowns.contains(t.toLowerCase()),
                  onSelected: (on) {
                    final next = parseLocationList(s('locations')).where((x) => x.toLowerCase() != t.toLowerCase() && x.toLowerCase() != 'andhra pradesh').toList();
                    if (on) next.add(t);
                    _set('locations', next.isEmpty ? null : next.join(', '));
                  },
                ),
            ]),
            _field('locations', 'Places (comma-separated; blank = everywhere)'),
          ]),
          _group('3 · How much', 'howmuch', [
            DropdownButtonFormField<String>(
              key: ValueKey('ad-package-$package'),
              isExpanded: true,
              initialValue: package,
              decoration: InputDecoration(labelText: _label('Package', adPackages[package]), isDense: true, border: const OutlineInputBorder()),
              items: [for (final e in adPackages.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() {
                values.addAll(packageFill(v ?? 'normal'));
                for (final k in const ['rounds', 'seconds', 'maxPerDay']) {
                  text[k]?.text = '${values[k]}';
                }
              }),
            ),
            Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(width: 240, child: DropdownButtonFormField<int>(
                key: ValueKey('ad-rounds-${adRounds(Entry(id, values))}'),
                isExpanded: true,
                initialValue: adRounds(Entry(id, values)),
                decoration: InputDecoration(labelText: _label('Times per rotation round', '${adRounds(Entry(id, values))}x'), isDense: true, border: const OutlineInputBorder()),
                items: const [DropdownMenuItem(value: 1, child: Text('1x')), DropdownMenuItem(value: 2, child: Text('2x')), DropdownMenuItem(value: 3, child: Text('3x'))],
                onChanged: (v) => _set('rounds', v),
              )),
              SizedBox(width: 240, child: _field('seconds', _label('Seconds on screen each time', adSeconds(Entry(id, values), config)), type: TextInputType.number)),
              SizedBox(width: 240, child: _field('maxPerDay', _label('Max times per day (0 = no limit)', s('maxPerDay').isEmpty ? 0 : s('maxPerDay')), type: TextInputType.number)),
            ]),
            SwitchListTile(
              key: const ValueKey('ad-pinned'),
              contentPadding: EdgeInsets.zero,
              title: Text(_label('Pin to top (always shown first)', values['pinned'] == true ? 'On' : 'Off')),
              value: values['pinned'] == true,
              onChanged: (v) => _set('pinned', v ? true : null),
            ),
          ]),
          _group('4 · Shop & payment (only you can see this)', 'shop', [
            Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(width: 240, child: _field('shopName', 'Shop name')),
              SizedBox(width: 240, child: _field('vendorCode', 'Vendor code (VN…)')),
              SizedBox(width: 240, child: _field('contactPerson', 'Contact person')),
              SizedBox(width: 240, child: _field('phone', 'Phone', type: TextInputType.phone)),
              SizedBox(width: 240, child: _field('amount', 'Amount (₹)', type: TextInputType.number)),
            ]),
            SwitchListTile(
              key: const ValueKey('ad-paid'),
              contentPadding: EdgeInsets.zero,
              title: Text(_label('Payment', values['paid'] == true ? 'Paid' : 'Unpaid')),
              value: values['paid'] == true,
              onChanged: (v) => _set('paid', v ? true : null),
            ),
            _field('notes', 'Notes', lines: 3),
          ]),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, key: const ValueKey('ad-error'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(key: const ValueKey('ad-save'), onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save ad')),
          ),
        ],
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.required});
  final String title;
  final bool required;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const ValueKey('ad-reason'),
      controller: controller,
      autofocus: true,
      maxLength: 300,
      decoration: InputDecoration(labelText: widget.required ? 'Reason (the vendor will see it)' : 'Reason (optional, the vendor will see it)'),
    ),
    actions: [
      TextButton(key: const ValueKey('ad-reason-cancel'), onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        key: const ValueKey('ad-reason-ok'),
        onPressed: () {
          final text = controller.text.trim();
          if (widget.required && text.isEmpty) return;
          Navigator.pop(context, text);
        },
        child: const Text('OK'),
      ),
    ],
  );
}
