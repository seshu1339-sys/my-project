import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../data/store.dart';
import '../../services/location.dart';
import 'area_map.dart';
import 'staff_area_model.dart';
import 'staff_terms.dart';

/// Staff app: choose your area. The town's map shows the areas, green free and red booked. The staff member picks a free one, stands
/// inside it with GPS on, ticks "I accept the Terms & Conditions" and registers it. From far away it is refused (the server checks the
/// place too): "Please go to this area to register it."
class StaffAreaClaimPage extends StatefulWidget {
  const StaffAreaClaimPage({super.key, required this.store, this.areas, this.locate, this.onClaim, this.onDone});
  final Store store;
  // Test seams: the areas, where the phone is, and what claiming does.
  final Stream<List<StaffArea>>? areas;
  final Future<LatLng?> Function()? locate;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? onClaim;
  // After a successful claim (the page that shows it can move on).
  final VoidCallback? onDone;

  @override
  State<StaffAreaClaimPage> createState() => _StaffAreaClaimPageState();
}

class _StaffAreaClaimPageState extends State<StaffAreaClaimPage> {
  String? town;
  StaffArea? chosen;
  LatLng? me;
  bool accepted = false, busy = false;
  String? message;
  bool good = false;

  Stream<List<StaffArea>> _areas() => widget.areas ??
      widget.store.firestore.collection('staffAreas').snapshots().map((s) => [for (final d in s.docs) StaffArea.fromData(d.id, d.data())]);

  Future<LatLng?> _locate() async {
    if (widget.locate != null) return widget.locate!();
    final p = await currentPosition(action: 'check that you are standing in the area');
    return LatLng(p.latitude, p.longitude);
  }

  void _say(String text, {bool ok = false}) => setState(() {
    message = text;
    good = ok;
  });

  Future<void> _claim() async {
    final area = chosen;
    if (area == null) return _say('Tap a green (free) area on the map first.');
    if (!area.free) return _say('This area is already taken. Choose a green (free) area.');
    if (!accepted) return _say('Tick "I accept the Terms & Conditions" to finish.');
    setState(() => busy = true);
    try {
      final at = await _locate();
      if (at == null) {
        _say('Turn on GPS (location) so we can check that you are in the area.');
      } else {
        setState(() => me = at);
        const d = Distance();
        if (d.as(LengthUnit.Meter, at, LatLng(area.latitude, area.longitude)) > area.radiusKm * 1000) {
          _say('Please go to this area to register it. You are not inside "${area.name}" now.');
        } else {
          final data = {'areaId': area.id, 'latitude': at.latitude, 'longitude': at.longitude, 'termsAccepted': true};
          final r = await (widget.onClaim ?? (data) => widget.store.call('claimStaffArea', data))(data);
          _say(r['status'] == 'booked' ? '"${area.name}" is your area now.' : '"${area.name}" is held for you until the admin approves you.', ok: true);
          widget.onDone?.call();
        }
      }
    } catch (e) {
      _say('$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<StaffArea>>(
    stream: _areas(),
    builder: (context, snapshot) {
      final all = snapshot.data ?? const <StaffArea>[];
      final towns = {for (final a in all) a.town}.toList()..sort();
      final shownTown = town ?? (towns.isEmpty ? null : towns.first);
      final areas = [for (final a in all) if (a.town == shownTown) a];
      final current = chosen == null ? null : areas.where((a) => a.id == chosen!.id).firstOrNull;
      return ListView(padding: const EdgeInsets.all(16), children: [
        Text('Choose your area', style: Theme.of(context).textTheme.headlineSmall),
        const Text('One area per staff member. Green areas are free, red ones are taken. Go to the area, then register it here.'),
        const SizedBox(height: 8),
        if (snapshot.hasData && towns.isEmpty) const Text('No areas yet. The admin adds the areas of each town.', key: ValueKey('staff-area-none')),
        if (towns.isNotEmpty)
          DropdownButton<String>(
            key: const ValueKey('staff-area-town'),
            value: shownTown,
            items: [for (final t in towns) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) => setState(() {
              town = v;
              chosen = null;
            }),
          ),
        if (areas.isNotEmpty) ...[
          AreaMap(areas: areas, selectedId: current?.id, me: me, onTapArea: (a) => setState(() => chosen = a)),
          const SizedBox(height: 4),
          const AreaLegend(),
          const SizedBox(height: 8),
          for (final a in areas)
            Card(
              child: ListTile(
                key: ValueKey('staff-area-${a.id}'),
                leading: Icon(current?.id == a.id ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: a.free ? areaColour(a.status) : Colors.grey),
                enabled: a.free,
                onTap: a.free ? () => setState(() => chosen = a) : null,
                title: Text(a.name),
                subtitle: Text('${areaStatusLabel(a.status)} • ${a.radiusKm.toStringAsFixed(a.radiusKm % 1 == 0 ? 0 : 1)} km around the centre', style: TextStyle(color: areaColour(a.status))),
              ),
            ),
        ],
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const ValueKey('staff-area-terms'),
          contentPadding: EdgeInsets.zero,
          value: accepted,
          onChanged: (v) => setState(() => accepted = v ?? false),
          title: const Text('I accept the Terms & Conditions'),
          subtitle: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('staff-area-terms-read'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StaffTermsPage(store: widget.store))),
              child: const Text('Read the Terms & Conditions'),
            ),
          ),
        ),
        FilledButton.icon(
          key: const ValueKey('staff-area-claim'),
          onPressed: busy ? null : _claim,
          icon: const Icon(Icons.my_location),
          label: Text(busy ? 'Checking your place...' : 'I am here: register this area'),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(message!, key: const ValueKey('staff-area-message'), style: TextStyle(color: good ? areaFreeColour : Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
          ),
      ]);
    },
  );
}
