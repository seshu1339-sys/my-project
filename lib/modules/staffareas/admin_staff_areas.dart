import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../data/store.dart';
import '../../services/file_download.dart';
import '../../services/report_export.dart';
import '../home_module.dart';
import 'admin_hex_cells.dart';
import 'area_map.dart';
import 'staff_area_model.dart';
import 'staff_terms.dart';

Widget _build(Store store) => AdminStaffAreasPage(store: store);

/// The Staff Areas tab of the admin panel (listed in module_admin.dart).
const staffAreasAdminSection = ModuleAdminSection(id: 'staffAreas', title: 'Staff Areas', icon: Icons.map_outlined, hint: 'Areas, daily targets and staff reports', build: _build);

Future<void> _run(BuildContext context, Future<Object?> Function() action, String done) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(done)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''))));
  }
}

/// Admin > Staff Areas: the areas on the map (Free / Pending / Booked with who holds them), the towns' radius, the daily target, the
/// missed days allowed and the Terms & Conditions, the staff the system deactivated, and the reports.
class AdminStaffAreasPage extends StatelessWidget {
  const AdminStaffAreasPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 6,
    child: Column(children: [
      // Cells (owner, 13 Nov 2026): the hexagon cells every new staff member registers. Areas and Towns are the older way, kept.
      const TabBar(isScrollable: true, tabs: [Tab(text: 'Cells'), Tab(text: 'Areas'), Tab(text: 'Towns'), Tab(text: 'Settings'), Tab(text: 'Deactivated'), Tab(text: 'Reports')]),
      Expanded(
        child: TabBarView(children: [
          AdminHexCellsTab(store: store),
          _AreasTab(store: store),
          _TownsTab(store: store),
          _SettingsTab(store: store),
          _DeactivatedTab(store: store),
          StaffAreaReportTab(load: (month) => store.call('staffAreaReport', {'month': month})),
        ]),
      ),
    ]),
  );
}

class _Town {
  const _Town(this.town, this.radiusKm);
  final String town;
  final double radiusKm;
}

Stream<List<_Town>> _towns(Store store) => store.firestore.collection('staffAreaTowns').snapshots().map((s) => [
  for (final d in s.docs) _Town(d.data()['town']?.toString() ?? d.id, (d.data()['radiusKm'] as num?)?.toDouble() ?? 1),
]..sort((a, b) => a.town.compareTo(b.town)));

class _AreasTab extends StatefulWidget {
  const _AreasTab({required this.store});
  final Store store;
  @override
  State<_AreasTab> createState() => _AreasTabState();
}

class _AreasTabState extends State<_AreasTab> {
  String? town;
  String? selected;

  @override
  Widget build(BuildContext context) {
    final db = widget.store.firestore;
    return StreamBuilder<List<_Town>>(
      stream: _towns(widget.store),
      builder: (context, towns) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('staffAreas').snapshots(),
        builder: (context, areasSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('staffAreaHolders').snapshots(),
          builder: (context, holdersSnap) {
            final allTowns = towns.data ?? const <_Town>[];
            final shownTown = town ?? (allTowns.isEmpty ? null : allTowns.first.town);
            final holders = {for (final d in holdersSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) d.id: AreaHolder.fromData(d.data())};
            final areas = [
              for (final d in areasSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                if (d.data()['town'] == shownTown) StaffArea.fromData(d.id, d.data()),
            ]..sort((a, b) => a.name.compareTo(b.name));
            return ListView(padding: const EdgeInsets.all(20), children: [
              Row(children: [
                Expanded(child: Text('Staff areas', style: Theme.of(context).textTheme.headlineSmall)),
                FilledButton.icon(
                  key: const ValueKey('staff-area-add'),
                  onPressed: allTowns.isEmpty ? null : () => _edit(context, allTowns, shownTown, areas),
                  icon: const Icon(Icons.add),
                  label: const Text('Add area'),
                ),
              ]),
              const Text('An area is a centre point with the town\'s radius. Areas never overlap. Free (green), Pending (orange, waiting for the staff member\'s approval), Booked (red).'),
              if (allTowns.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Set a town\'s radius first (Towns).')),
              if (allTowns.isNotEmpty)
                DropdownButton<String>(
                  key: const ValueKey('admin-staff-area-town'),
                  value: shownTown,
                  items: [for (final t in allTowns) DropdownMenuItem(value: t.town, child: Text('${t.town} (${t.radiusKm} km)'))],
                  onChanged: (v) => setState(() {
                    town = v;
                    selected = null;
                  }),
                ),
              if (areas.isNotEmpty) ...[
                AreaMap(areas: areas, selectedId: selected, onTapArea: (a) => setState(() => selected = a.id), height: 360),
                const AreaLegend(),
              ],
              const SizedBox(height: 8),
              Text('${areas.length} areas • ${areas.where((a) => a.free).length} free • ${areas.where((a) => a.status == 'booked').length} booked • ${areas.where((a) => a.status == 'pending').length} pending'),
              for (final a in areas)
                Card(
                  shape: a.id == selected ? RoundedRectangleBorder(side: BorderSide(color: areaColour(a.status), width: 2), borderRadius: BorderRadius.circular(12)) : null,
                  child: ListTile(
                    key: ValueKey('admin-staff-area-${a.id}'),
                    onTap: () => setState(() => selected = a.id),
                    leading: CircleAvatar(radius: 8, backgroundColor: areaColour(a.status)),
                    title: Text(a.name),
                    subtitle: Text([
                      areaStatusLabel(a.status),
                      if (holders[a.id] case final h? when !a.free) '${h.staffName} • ${h.staffCode} • ${h.staffPhone}',
                    ].join('\n')),
                    isThreeLine: !a.free,
                    trailing: Wrap(spacing: 4, children: [
                      TextButton(onPressed: () => _edit(context, allTowns, shownTown, areas, a), child: const Text('Edit')),
                      if (!a.free)
                        TextButton(
                          key: ValueKey('admin-staff-area-free-${a.id}'),
                          onPressed: () => _confirm(context, 'Make "${a.name}" free?', 'The staff member loses this area and may choose another.', () => widget.store.call('freeStaffArea', {'areaId': a.id}), 'Area is free'),
                          child: const Text('Free'),
                        ),
                      if (a.free)
                        TextButton(
                          onPressed: () => _confirm(context, 'Delete "${a.name}"?', 'Only a free area can be deleted.', () => widget.store.call('deleteStaffArea', {'areaId': a.id}), 'Deleted'),
                          child: const Text('Delete'),
                        ),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, String title, String body, Future<Object?> Function() action, String done) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(title: Text(title), content: Text(body), actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('admin-staff-area-confirm'), onPressed: () => Navigator.pop(dialog, true), child: const Text('Yes')),
      ]),
    );
    if (yes == true && context.mounted) await _run(context, action, done);
  }

  Future<void> _edit(BuildContext context, List<_Town> towns, String? town, List<StaffArea> areas, [StaffArea? area]) async {
    final fields = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => StaffAreaEditorDialog(towns: [for (final t in towns) t.town], town: area?.town ?? town, area: area, others: areas),
    );
    if (fields != null && context.mounted) await _run(context, () => widget.store.call('saveStaffArea', fields), 'Area saved');
  }
}

/// Name, town and centre (a tap on the map) of an area. Pops the fields to save, or null.
class StaffAreaEditorDialog extends StatefulWidget {
  const StaffAreaEditorDialog({super.key, required this.towns, this.town, this.area, this.others = const []});
  final List<String> towns;
  final String? town;
  final StaffArea? area;
  final List<StaffArea> others;
  @override
  State<StaffAreaEditorDialog> createState() => _StaffAreaEditorDialogState();
}

class _StaffAreaEditorDialogState extends State<StaffAreaEditorDialog> {
  late final name = TextEditingController(text: widget.area?.name ?? '');
  late String? town = widget.town;
  late LatLng? point = widget.area == null ? null : LatLng(widget.area!.latitude, widget.area!.longitude);
  String? error;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void _save() {
    if (name.text.trim().length < 2) return setState(() => error = 'Give the area a name.');
    if (town == null) return setState(() => error = 'Choose the town.');
    if (point == null) return setState(() => error = 'Tap the map to put the centre.');
    Navigator.pop(context, {
      if (widget.area != null) 'areaId': widget.area!.id,
      'name': name.text.trim(),
      'town': town,
      'latitude': point!.latitude,
      'longitude': point!.longitude,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.area == null ? 'Add area' : 'Edit area'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(key: const ValueKey('staff-area-name'), controller: name, decoration: const InputDecoration(labelText: 'Area name', hintText: 'Narsipatnam Main Bazaar')),
          DropdownButton<String>(
            key: const ValueKey('staff-area-edit-town'),
            isExpanded: true,
            value: town,
            hint: const Text('Town'),
            items: [for (final t in widget.towns) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) => setState(() => town = v),
          ),
          const SizedBox(height: 8),
          const Text('Tap the map for the centre of the area.'),
          AreaMap(areas: [for (final a in widget.others) if (a.id != widget.area?.id) a], point: point, onTapMap: (p) => setState(() => point = p), height: 280),
          if (point != null) Text('Centre: ${point!.latitude.toStringAsFixed(5)}, ${point!.longitude.toStringAsFixed(5)}', key: const ValueKey('staff-area-point')),
          if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const ValueKey('staff-area-save'), onPressed: _save, child: const Text('Save')),
    ],
  );
}

class _TownsTab extends StatelessWidget {
  const _TownsTab({required this.store});
  final Store store;

  Future<void> _edit(BuildContext context, [_Town? town]) async {
    final fields = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => StaffTownDialog(town: town?.town, radiusKm: town?.radiusKm));
    if (fields != null && context.mounted) await _run(context, () => store.call('saveStaffAreaTown', fields), 'Town saved');
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<_Town>>(
    stream: _towns(store),
    builder: (context, snapshot) => ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        Expanded(child: Text('Towns', style: Theme.of(context).textTheme.headlineSmall)),
        FilledButton.icon(key: const ValueKey('staff-town-add'), onPressed: () => _edit(context), icon: const Icon(Icons.add), label: const Text('Add town')),
      ]),
      const Text('Each town\'s radius is the size of every area in it: big cities small (1 km), small towns bigger (3-5 km). Change it any time; overlapping areas are refused.'),
      for (final t in snapshot.data ?? const <_Town>[])
        Card(child: ListTile(title: Text(t.town), subtitle: Text('${t.radiusKm} km'), trailing: TextButton(onPressed: () => _edit(context, t), child: const Text('Change')))),
    ]),
  );
}

/// A town's name and radius (1, 2, 3, 5 km or another). Pops {town, radiusKm}.
class StaffTownDialog extends StatefulWidget {
  const StaffTownDialog({super.key, this.town, this.radiusKm});
  final String? town;
  final double? radiusKm;
  @override
  State<StaffTownDialog> createState() => _StaffTownDialogState();
}

class _StaffTownDialogState extends State<StaffTownDialog> {
  late final town = TextEditingController(text: widget.town ?? '');
  late double? choice = staffAreaRadiusOptions.contains(widget.radiusKm) ? widget.radiusKm : (widget.radiusKm == null ? 2 : null);
  late final custom = TextEditingController(text: choice == null ? '${widget.radiusKm}' : '');
  String? error;

  @override
  void dispose() {
    town.dispose();
    custom.dispose();
    super.dispose();
  }

  void _save() {
    final r = choice ?? double.tryParse(custom.text.trim());
    if (town.text.trim().length < 2) return setState(() => error = 'Enter the town name.');
    if (r == null || r < 0.2 || r > 50) return setState(() => error = 'Enter a radius between 0.2 and 50 km.');
    Navigator.pop(context, {'town': town.text.trim(), 'radiusKm': r});
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.town == null ? 'Add town' : 'Town radius'),
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(key: const ValueKey('staff-town-name'), controller: town, enabled: widget.town == null, decoration: const InputDecoration(labelText: 'Town')),
      const SizedBox(height: 8),
      Wrap(spacing: 6, children: [
        for (final r in staffAreaRadiusOptions)
          ChoiceChip(key: ValueKey('staff-town-radius-${r.toInt()}'), label: Text('${r.toInt()} km'), selected: choice == r, onSelected: (_) => setState(() => choice = r)),
        ChoiceChip(key: const ValueKey('staff-town-radius-custom'), label: const Text('Other'), selected: choice == null, onSelected: (_) => setState(() => choice = null)),
      ]),
      if (choice == null)
        TextField(key: const ValueKey('staff-town-radius-value'), controller: custom, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Radius (km)')),
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const ValueKey('staff-town-save'), onPressed: _save, child: const Text('Save')),
    ],
  );
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => StreamBuilder<StaffAreaSettings>(
    stream: staffAreaSettings(store),
    builder: (context, s) => s.hasData
        ? StaffAreaSettingsForm(key: ValueKey(s.data!.terms.hashCode), settings: s.data!, onSave: (fields) => store.call('saveStaffAreaSettings', fields))
        : const Center(child: CircularProgressIndicator()),
  );
}

/// The daily target, the missed days allowed a month, and the Terms & Conditions the staff accept.
class StaffAreaSettingsForm extends StatefulWidget {
  const StaffAreaSettingsForm({super.key, required this.settings, required this.onSave});
  final StaffAreaSettings settings;
  final Future<Object?> Function(Map<String, dynamic> fields) onSave;
  @override
  State<StaffAreaSettingsForm> createState() => _StaffAreaSettingsFormState();
}

class _StaffAreaSettingsFormState extends State<StaffAreaSettingsForm> {
  // One box per target: daily / weekly / monthly x live photos, shops visited, new vendors, new Premium vendors (0 = no target).
  late final targets = {
    for (final p in staffTargetPeriods.keys)
      for (final m in staffTargetMeasures.keys) '$p${m}Target': TextEditingController(text: '${widget.settings.target(p, m)}'),
  };
  // The automatic area size: 4 bands of buildings per km² and their radius (the last band is "fewer than the band above").
  late final bandMin = [for (final b in widget.settings.densityBands) TextEditingController(text: '${b.$1}')];
  late final bandKm = [for (final b in widget.settings.densityBands) TextEditingController(text: b.$2 == b.$2.roundToDouble() ? '${b.$2.toInt()}' : '${b.$2}')];
  late final rateDays = TextEditingController(text: '${widget.settings.rateDaysPerWeek}');
  late final missed = TextEditingController(text: '${widget.settings.maxMissedDays}');
  late final terms = TextEditingController(text: widget.settings.terms);
  String? error;

  @override
  void dispose() {
    for (final c in [...targets.values, ...bandMin, ...bandKm, rateDays, missed]) {
      c.dispose();
    }
    terms.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    int? n(TextEditingController c) => int.tryParse(c.text.trim());
    final values = {for (final e in targets.entries) e.key: n(e.value)};
    if (values.values.any((v) => v == null || v < 0 || v > 10000)) return setState(() => error = 'Enter every target as a whole number from 0 to 10000 (0 = no target).');
    final r = n(rateDays), m = n(missed);
    if (r == null || r < 1 || r > 7) return setState(() => error = 'Enter 1 to 7 rate update days a week.');
    if (m == null || m < 1 || m > 31) return setState(() => error = 'Enter 1 to 31 missed days.');
    if (terms.text.trim().length < 20) return setState(() => error = 'Write the Terms & Conditions.');
    final mins = [for (var i = 0; i < 3; i++) int.tryParse(bandMin[i].text.trim()), 0];
    final kms = [for (final c in bandKm) double.tryParse(c.text.trim())];
    if (mins.any((v) => v == null || v < 0) || !(mins[0]! > mins[1]! && mins[1]! > mins[2]! && mins[2]! > 0)) {
      return setState(() => error = 'Area size: each band needs fewer buildings than the band above it (whole numbers).');
    }
    if (kms.any((v) => v == null || v < 0.5 || v > 30)) return setState(() => error = 'Area size: enter each radius from 0.5 to 30 km.');
    setState(() => error = null);
    await _run(
      context,
      () => widget.onSave({
        ...values,
        'rateDaysPerWeek': r,
        'maxMissedDays': m,
        'terms': terms.text.trim(),
        'densityBands': [for (var i = 0; i < 4; i++) {'minPerKm2': mins[i], 'radiusKm': kms[i]}],
      }),
      'Saved',
    );
  }

  Widget _cell(String period, String measure) => Padding(
    padding: const EdgeInsets.all(4),
    child: TextField(
      key: ValueKey('staff-target-$period-$measure'),
      controller: targets['$period${measure}Target'],
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
    ),
  );

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    Text('Staff targets and rules', style: Theme.of(context).textTheme.headlineSmall),
    const Text('The same for every staff member. Type 0 when there is no target for that period. A month counts for a staff member only when every monthly target is complete.'),
    const SizedBox(height: 12),
    Text('Targets', style: Theme.of(context).textTheme.titleMedium),
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 520, maxWidth: 720),
        child: Table(
          key: const ValueKey('staff-targets-table'),
          columnWidths: const {0: FlexColumnWidth(2.2)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(children: [
              const SizedBox.shrink(),
              for (final words in ['Each day', 'Each week', 'Each month']) Padding(padding: const EdgeInsets.all(4), child: Text(words, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
            ]),
            for (final m in staffTargetMeasures.entries)
              TableRow(children: [
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(switch (m.key) {
                    'Photo' => 'Live photos (rate updates with a live camera photo)',
                    'Shop' => 'Shops visited (different shops with a live-photo rate update)',
                    'Vendor' => 'New vendors linked',
                    _ => 'New Premium (paid) vendors linked',
                  }),
                ),
                for (final p in staffTargetPeriods.keys) _cell(p, m.key),
              ]),
          ],
        ),
      ),
    ),
    const SizedBox(height: 16),
    Text('Automatic area size', style: Theme.of(context).textTheme.titleMedium),
    const Text(
      'When a staff member taps the centre of their area, the app counts the houses and buildings within 1 km (free OpenStreetMap data) '
      'and gives the area this radius. Staff cannot change it. Areas already registered keep their size.',
    ),
    for (var i = 0; i < 4; i++)
      Padding(
        key: ValueKey('staff-density-band-$i'),
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          Expanded(
            flex: 3,
            child: i < 3
                ? TextField(
                    key: ValueKey('staff-density-min-$i'),
                    controller: bandMin[i],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: i == 0 ? 'Buildings per km²: this many or more' : 'or more (and fewer than above)', isDense: true, border: const OutlineInputBorder()),
                  )
                : const Text('Fewer than the band above', key: ValueKey('staff-density-last')),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward)),
          Expanded(
            flex: 2,
            child: TextField(
              key: ValueKey('staff-density-km-$i'),
              controller: bandKm[i],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Radius (km)', isDense: true, border: OutlineInputBorder()),
            ),
          ),
        ]),
      ),
    const SizedBox(height: 16),
    Text('Rate days and missed days', style: Theme.of(context).textTheme.titleMedium),
    TextField(
      key: const ValueKey('staff-area-rate-days'),
      controller: rateDays,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: 'Rate update days a week', helperText: 'A staff member must update shop rates on at least this many days every week'),
    ),
    TextField(
      key: const ValueKey('staff-area-max-missed'),
      controller: missed,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: 'Missed days a month that stop the staff ID',
        helperText: 'A warning goes to the staff phone on the morning of the last day, and again at 5 PM',
        helperMaxLines: 2,
      ),
    ),
    const SizedBox(height: 12),
    const Text('Terms & Conditions (shown in the staff app only: at registration and in its settings)'),
    TextField(key: const ValueKey('staff-area-terms-edit'), controller: terms, maxLines: 14, minLines: 8, decoration: const InputDecoration(border: OutlineInputBorder())),
    if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, key: const ValueKey('staff-settings-error'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
    const SizedBox(height: 12),
    Align(alignment: Alignment.centerLeft, child: FilledButton(key: const ValueKey('staff-area-settings-save'), onPressed: _save, child: const Text('Save'))),
  ]);
}

class _DeactivatedTab extends StatelessWidget {
  const _DeactivatedTab({required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('staffAreaStaff').snapshots(),
    builder: (context, snapshot) {
      final rows = [
        for (final d in snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
          if (d.data()['deactivatedAt'] is Timestamp) d,
      ]..sort((a, b) => (b.data()['deactivatedAt'] as Timestamp).compareTo(a.data()['deactivatedAt'] as Timestamp));
      return ListView(padding: const EdgeInsets.all(20), children: [
        Text('Deactivated staff', style: Theme.of(context).textTheme.headlineSmall),
        const Text('Deactivated automatically for missing the daily target too often. Reactivate when their area is still free; the vendors of the area stayed live.'),
        if (rows.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Nobody is deactivated.')),
        for (final d in rows)
          FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: store.firestore.collection('fieldStaff').doc(d.id).get(),
            builder: (context, staff) {
              final s = staff.data?.data() ?? const {};
              final at = (d.data()['deactivatedAt'] as Timestamp).toDate();
              return Card(
                child: ListTile(
                  key: ValueKey('staff-deactivated-${d.id}'),
                  title: Text('${s['name'] ?? ''} • ${s['staffCode'] ?? d.id}'),
                  subtitle: Text('${dayLabel(istDayOf(at))} • ${d.data()['deactivatedReason'] ?? ''}\nArea: ${d.data()['deactivatedAreaName'] ?? ''}'),
                  isThreeLine: true,
                  trailing: TextButton(
                    key: ValueKey('staff-reactivate-${d.id}'),
                    onPressed: () => _run(context, () => store.call('reactivateAreaStaff', {'staffUid': d.id}), 'Reactivated with their area'),
                    child: const Text('Reactivate'),
                  ),
                ),
              );
            },
          ),
      ]);
    },
  );
}

/// The reports for a month: per staff member and per town, with an Excel download.
class StaffAreaReportTab extends StatefulWidget {
  const StaffAreaReportTab({super.key, required this.load, this.download});
  final Future<Map<String, dynamic>> Function(String month) load;
  // Test seam: how the file is saved.
  final Future<void> Function(String name, List<ReportTable> tables)? download;
  @override
  State<StaffAreaReportTab> createState() => _StaffAreaReportTabState();
}

Object _cell(Object? v) => v ?? '';

List<ReportTable> staffAreaReportTables(Map<String, dynamic> r) {
  final staff = (r['staff'] as List? ?? const []).whereType<Map>().toList();
  final towns = (r['towns'] as List? ?? const []).whereType<Map>().toList();
  return [
    ReportTable('Staff ${r['month']}', ['Staff ID', 'Name', 'Phone', 'Status', 'Area', 'Town', 'Live photos', 'Vendors registered', 'Paid vendors registered', 'Services registered', 'Month target complete', 'Days worked', 'Missed days', 'Offers by staff', 'Offers by vendors'], [
      for (final s in staff)
        [
          for (final k in ['staffCode', 'name', 'phone', 'status', 'area', 'town', 'photos', 'vendorsLinked', 'paidVendorsLinked', 'providersLinked']) _cell(s[k]),
          s['monthComplete'] == true ? 'Yes' : 'No',
          for (final k in ['daysWorked', 'missedDays', 'staffOffers', 'vendorOffers']) _cell(s[k]),
        ],
    ]),
    ReportTable('Towns ${r['month']}', ['Town', 'Areas', 'Free', 'Booked', 'Pending', 'Deactivated this month'], [
      for (final t in towns) [_cell(t['town']), for (final k in ['total', 'free', 'booked', 'pending', 'deactivatedThisMonth']) t[k] ?? 0],
    ]),
  ];
}

class _StaffAreaReportTabState extends State<StaffAreaReportTab> {
  late String month = istDayOf(DateTime.now()).substring(0, 7);
  late Future<Map<String, dynamic>> data = widget.load(month);

  String _shift(int by) {
    final p = month.split('-').map(int.parse).toList();
    final d = DateTime(p[0], p[1] + by);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: data,
    builder: (context, snapshot) {
      final r = snapshot.data;
      final tables = r == null ? const <ReportTable>[] : staffAreaReportTables(r);
      return ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          Expanded(child: Text('Reports: $month', style: Theme.of(context).textTheme.headlineSmall)),
          IconButton(tooltip: 'Month before', onPressed: () => setState(() => data = widget.load(month = _shift(-1))), icon: const Icon(Icons.chevron_left)),
          IconButton(tooltip: 'Month after', onPressed: () => setState(() => data = widget.load(month = _shift(1))), icon: const Icon(Icons.chevron_right)),
          FilledButton.icon(
            key: const ValueKey('staff-area-report-export'),
            onPressed: r == null
                ? null
                : () => _run(
                    context,
                    () => (widget.download ?? (name, t) => downloadFile(name, buildXlsx(t), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'))('staff-areas-$month.xlsx', tables),
                    'Downloaded',
                  ),
            icon: const Icon(Icons.download),
            label: const Text('Excel'),
          ),
        ]),
        if (snapshot.hasError) Text('The report could not load: ${snapshot.error}'),
        if (!snapshot.hasData && !snapshot.hasError) const LinearProgressIndicator(),
        for (final t in tables) ...[
          const SizedBox(height: 12),
          Text(t.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [for (final h in t.header) DataColumn(label: Text(h))],
              rows: [for (final row in t.rows) DataRow(cells: [for (final c in row) DataCell(Text('$c'))])],
            ),
          ),
        ],
      ]);
    },
  );
}
