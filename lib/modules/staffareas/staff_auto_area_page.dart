import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../data/store.dart';
import '../../services/location.dart';
import 'area_map.dart';
import 'area_picker_map.dart';
import 'auto_area.dart';
import 'staff_area_claim_page.dart';
import 'staff_terms.dart';

/// Staff app: choose your area (owner, 7 Nov 2026). Search the place, tap the centre on the map. The server counts the buildings
/// around it (free OpenStreetMap data) and sets the radius by itself: dense city small, villages big. The staff member cannot change
/// it. One area per staff member. Registering needs the Terms and standing inside the area with GPS on.
class StaffAutoAreaPage extends StatefulWidget {
  const StaffAutoAreaPage({super.key, required this.store, this.search, this.preview, this.claim, this.locate, this.onDone});
  final Store store;
  // Test seams: the place search, the server's preview and claim, and where the phone is.
  final Future<List<FoundPlace>> Function(String query)? search;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? preview;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? claim;
  final Future<LatLng?> Function()? locate;
  final VoidCallback? onDone;

  @override
  State<StaffAutoAreaPage> createState() => _StaffAutoAreaPageState();
}

class _StaffAutoAreaPageState extends State<StaffAutoAreaPage> {
  final query = TextEditingController();
  final name = TextEditingController();
  List<FoundPlace> found = const [];
  FoundPlace? place;
  LatLng? focus, centre;
  AutoAreaPreview? preview;
  bool accepted = false, busy = false, good = false;
  String? message;
  String town = '';

  @override
  void dispose() {
    query.dispose();
    name.dispose();
    super.dispose();
  }

  void _say(String text, {bool ok = false}) => setState(() {
    message = text;
    good = ok;
  });

  String _clean(Object e) => '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '');

  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    setState(() => busy = true);
    try {
      final list = await (widget.search ?? searchPlaces)(query.text);
      setState(() {
        found = list;
        message = list.isEmpty ? 'No place found. Try another spelling or a bigger place nearby.' : null;
        good = false;
      });
    } catch (e) {
      _say(_clean(e));
    }
    if (mounted) setState(() => busy = false);
  }

  void _choosePlace(FoundPlace p) => setState(() {
    place = p;
    town = p.town;
    if (name.text.trim().isEmpty || name.text == (place?.name ?? '')) name.text = p.name;
    focus = LatLng(p.latitude, p.longitude);
    found = const [];
    message = 'Now tap the centre of your area on the map.';
    good = true;
  });

  Future<void> _tap(LatLng at) async {
    final b = blockOf(at.latitude, at.longitude);
    setState(() {
      centre = LatLng(b.latitude, b.longitude);
      preview = null;
      busy = true;
      message = 'Counting the buildings around this place...';
      good = true;
    });
    try {
      final r = AutoAreaPreview.fromData(await (widget.preview ?? (d) => widget.store.call('previewAutoStaffArea', d))({'latitude': at.latitude, 'longitude': at.longitude}));
      setState(() {
        preview = r;
        centre = LatLng(r.latitude, r.longitude);
        message = r.free ? null : r.problem;
        good = r.free;
      });
    } catch (e) {
      _say(_clean(e));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<LatLng?> _locate() async {
    if (widget.locate != null) return widget.locate!();
    final p = await currentPosition(action: 'check that you are standing in the area');
    return LatLng(p.latitude, p.longitude);
  }

  Future<void> _register() async {
    final p = preview;
    if (p == null) return _say('Tap the centre of your area on the map first.');
    if (!p.free) return _say(p.problem.isEmpty ? 'Tap another place.' : p.problem);
    if (!accepted) return _say('Tick "I accept the Terms & Conditions" to finish.');
    setState(() => busy = true);
    try {
      final at = await _locate();
      if (at == null) {
        _say('Turn on GPS (location) so we can check that you are in the area.');
      } else {
        const d = Distance();
        if (d.as(LengthUnit.Meter, at, LatLng(p.latitude, p.longitude)) > p.radiusKm * 1000) {
          _say('Please go to this area to register it. You are not inside it now.');
        } else {
          final r = await (widget.claim ?? (data) => widget.store.call('claimAutoStaffArea', data))({
            'latitude': p.latitude, 'longitude': p.longitude, 'gpsLatitude': at.latitude, 'gpsLongitude': at.longitude,
            'name': name.text.trim(), 'town': town, 'termsAccepted': true,
          });
          _say(r['status'] == 'booked' ? 'This is your area now (${p.radiusText}).' : 'This area is held for you until the admin approves you (${p.radiusText}).', ok: true);
          widget.onDone?.call();
        }
      }
    } catch (e) {
      _say(_clean(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = preview;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Choose your area', style: Theme.of(context).textTheme.headlineSmall),
      const Text('1. Search your place.  2. Tap the centre of your area on the map.  3. The app sets the area size by itself from how many houses and buildings are around (a busy town gets a small area, villages a big one).  4. Stand inside the area and register it. One area per staff member.'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            key: const ValueKey('auto-area-search'),
            controller: query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: const InputDecoration(labelText: 'Search a place (for example Narsipatnam Main Road)', isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(key: const ValueKey('auto-area-search-go'), onPressed: busy ? null : _search, child: const Text('Search')),
      ]),
      for (final (i, f) in found.indexed)
        ListTile(
          key: ValueKey('auto-area-place-$i'),
          dense: true,
          leading: const Icon(Icons.place_outlined),
          title: Text(f.name),
          subtitle: Text(f.detail, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => _choosePlace(f),
        ),
      const SizedBox(height: 8),
      // Made once; a search only moves its camera.
      AreaPickerMap(
        key: const ValueKey('auto-area-map'),
        start: const LatLng(17.668, 82.612),
        focus: focus,
        centre: centre,
        radiusKm: p?.radiusKm,
        free: p?.free ?? true,
        onTap: busy ? (_) {} : _tap,
      ),
      if (p != null)
        Card(
          key: const ValueKey('auto-area-result'),
          color: (p.free ? areaFreeColour : areaBookedColour).withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your area: ${p.radiusText} around the centre', key: const ValueKey('auto-area-radius'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('About ${p.buildings} houses and buildings within 1 km (${p.densityPerKm2} per km²). The size is set by the app; it cannot be changed.'),
              if (!p.free) Text(p.problem, style: const TextStyle(color: areaBookedColour, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      TextField(key: const ValueKey('auto-area-name'), controller: name, decoration: const InputDecoration(labelText: 'Area name (for example Main Bazaar)')),
      CheckboxListTile(
        key: const ValueKey('auto-area-terms'),
        contentPadding: EdgeInsets.zero,
        value: accepted,
        onChanged: (v) => setState(() => accepted = v ?? false),
        title: const Text('I accept the Terms & Conditions'),
        subtitle: Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StaffTermsPage(store: widget.store))),
            child: const Text('Read the Terms & Conditions'),
          ),
        ),
      ),
      FilledButton.icon(
        key: const ValueKey('auto-area-register'),
        onPressed: busy ? null : _register,
        icon: const Icon(Icons.my_location),
        label: Text(busy ? 'Please wait...' : 'I am here: register this area'),
      ),
      if (message != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(message!, key: const ValueKey('auto-area-message'), style: TextStyle(color: good ? areaFreeColour : Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
        ),
      const Divider(height: 32),
      TextButton.icon(
        key: const ValueKey('auto-area-office'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(appBar: AppBar(title: const Text('Areas made by the office')), body: StaffAreaClaimPage(store: widget.store, onDone: widget.onDone)),
        )),
        icon: const Icon(Icons.list_alt_outlined),
        label: const Text('Or choose an area the office made'),
      ),
    ]);
  }
}
