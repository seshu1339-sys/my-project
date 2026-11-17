import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/store.dart';
import '../../services/location.dart';
import 'area_map.dart';
import 'hex_cell.dart';
import 'staff_terms.dart';

/// Staff app > My cell (owner, 13 Nov 2026), the only way new staff get an area. With location on, the map shows the hexagon cell
/// where the staff member stands and the cells around it: green free, red taken, blue their own. The registration box already holds
/// that cell; the staff member adds their home address and a home pin (within 5 km of the cell's centre), accepts the Terms and
/// registers. The server checks everything again (functions/modules/staff-areas claimHexCell).
class StaffHexCellPage extends StatefulWidget {
  const StaffHexCellPage({super.key, required this.store, this.onDone});
  final Store store;
  // After a successful registration (the caller can refresh or close).
  final VoidCallback? onDone;

  @override
  State<StaffHexCellPage> createState() => _StaffHexCellPageState();
}

class _StaffHexCellPageState extends State<StaffHexCellPage> {
  HexNearby? nearby;
  LatLng? me;
  double? accuracyM;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final p = await currentPosition(action: 'find the cell where you are standing');
      final answer = await widget.store.call('staffHexNearby', {'latitude': p.latitude, 'longitude': p.longitude});
      if (!mounted) return;
      setState(() {
        me = LatLng(p.latitude, p.longitude);
        accuracyM = p.accuracy > 0 ? p.accuracy : null;
        nearby = HexNearby.fromData(answer);
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> _register(HexRegistration r) async {
    await widget.store.call('claimHexCell', {
      'latitude': me!.latitude,
      'longitude': me!.longitude,
      'accuracyM': ?accuracyM,
      'cellId': nearby!.cellId,
      'homeLatitude': r.home.latitude,
      'homeLongitude': r.home.longitude,
      'homeAddress': r.address,
      'termsAccepted': true,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cell ${nearby!.code} is registered for you.')));
    widget.onDone?.call();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    if (error != null || nearby == null || me == null) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        Text(error ?? 'Your cell could not load.', key: const ValueKey('hex-error')),
        const SizedBox(height: 12),
        FilledButton.icon(key: const ValueKey('hex-retry'), onPressed: _load, icon: const Icon(Icons.my_location), label: const Text('Try again')),
      ]);
    }
    return StaffHexCellView(
      nearby: nearby!,
      me: me!,
      onRegister: _register,
      onRefresh: _load,
      onTerms: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => StaffTermsPage(store: widget.store))),
    );
  }
}

/// What the staff member filled in.
class HexRegistration {
  const HexRegistration({required this.home, required this.address});
  final LatLng home;
  final String address;
}

const hexMineColour = Color(0xFF2563EB);
Color hexColour(HexCell c) => c.mine ? hexMineColour : c.free ? areaFreeColour : areaBookedColour;

/// The map and the registration box, for the cells the server sent.
class StaffHexCellView extends StatefulWidget {
  const StaffHexCellView({super.key, required this.nearby, required this.me, required this.onRegister, this.onRefresh, this.onTerms, this.mapHeight = 320});
  final HexNearby nearby;
  final LatLng me;
  final Future<void> Function(HexRegistration registration) onRegister;
  final VoidCallback? onRefresh, onTerms;
  final double mapHeight;

  @override
  State<StaffHexCellView> createState() => _StaffHexCellViewState();
}

class _StaffHexCellViewState extends State<StaffHexCellView> {
  final address = TextEditingController();
  LatLng? home;
  // While on, a tap on the map puts the home pin.
  bool placingHome = false;
  bool accepted = false;
  bool busy = false;
  String? problem;

  @override
  void dispose() {
    address.dispose();
    super.dispose();
  }

  double? get _homeKm => home == null ? null : homeDistanceKm(widget.nearby.center, home!);

  String? _check() {
    final n = widget.nearby;
    if (n.hasArea) return 'You already have a cell (${n.myAreaCode}). One staff member has one cell.';
    if (!n.free) return 'This cell is taken. Only a free (green) cell can be registered.';
    if (address.text.trim().length < 10) return 'Enter your home address.';
    if (home == null) return 'Put the pin on your home on the map.';
    if (_homeKm! > n.homeMaxKm) return 'Your home is ${_homeKm!.toStringAsFixed(1)} km from the centre of this cell. Staff must live within ${n.homeMaxKm.toStringAsFixed(0)} km of their cell\'s centre.';
    if (!accepted) return 'Tick "I accept the Terms & Conditions".';
    return null;
  }

  Future<void> _send() async {
    final wrong = _check();
    setState(() => problem = wrong);
    if (wrong != null) return;
    setState(() => busy = true);
    try {
      await widget.onRegister(HexRegistration(home: home!, address: address.text.trim()));
    } catch (e) {
      if (mounted) setState(() => problem = '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _map() {
    final n = widget.nearby;
    return SizedBox(
      key: const ValueKey('hex-map'),
      height: widget.mapHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: widget.me,
            initialZoom: n.sizeKm == 5 ? 11.5 : n.sizeKm == 2 ? 13 : 14.2,
            onTap: (_, at) {
              if (placingHome) {
                setState(() {
                  home = at;
                  placingHome = false;
                  problem = null;
                });
              }
            },
          ),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'in.locamarket.staff'),
            PolygonLayer(polygons: [
              for (final c in n.cells)
                if (c.outline.length >= 3)
                  Polygon(
                    points: c.outline,
                    color: hexColour(c).withValues(alpha: c.cellId == n.cellId ? 0.32 : 0.16),
                    borderColor: hexColour(c),
                    borderStrokeWidth: c.cellId == n.cellId ? 4 : 1.2,
                  ),
            ]),
            CircleLayer(circles: [
              // The 5 km home limit around the cell's centre.
              CircleMarker(point: n.center, radius: n.homeMaxKm * 1000, useRadiusInMeter: true, color: Colors.transparent, borderColor: Colors.black38, borderStrokeWidth: 1),
            ]),
            MarkerLayer(markers: [
              Marker(point: widget.me, width: 28, height: 28, child: const Icon(Icons.my_location, color: hexMineColour, size: 26)),
              if (home != null) Marker(point: home!, width: 34, height: 34, alignment: Alignment.topCenter, child: const Icon(Icons.home, color: Colors.deepOrange, size: 32)),
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.nearby;
    final cellColour = n.status == 'mine' ? hexMineColour : n.free ? areaFreeColour : areaBookedColour;
    final km = _homeKm;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text('Your cell here', style: Theme.of(context).textTheme.titleLarge)),
        if (widget.onRefresh != null) IconButton(key: const ValueKey('hex-refresh'), tooltip: 'Find my place again', onPressed: widget.onRefresh, icon: const Icon(Icons.my_location)),
      ]),
      Text(
        '${n.code} • ${hexSizeLabel(n.sizeKm)} • ${n.status == 'mine' ? 'Your cell' : n.free ? 'Free' : 'Taken'}',
        key: const ValueKey('hex-here'),
        style: TextStyle(color: cellColour, fontWeight: FontWeight.bold, fontSize: 16),
      ),
      const SizedBox(height: 8),
      _map(),
      const SizedBox(height: 6),
      const Wrap(spacing: 12, children: [
        _Legend(colour: areaFreeColour, label: 'Free'),
        _Legend(colour: areaBookedColour, label: 'Taken'),
        _Legend(colour: hexMineColour, label: 'Yours'),
      ]),
      const Text('The cell size is set automatically from how many people live there: 1 km in dense cities, 2 km in towns, 5 km in villages.', style: TextStyle(fontSize: 12)),
      const Text(worldPopCredit, key: ValueKey('hex-credit'), style: TextStyle(fontSize: 11, color: Colors.black54)),
      const SizedBox(height: 12),
      if (n.hasArea)
        Card(
          child: ListTile(
            key: const ValueKey('hex-has-area'),
            leading: const Icon(Icons.check_circle, color: hexMineColour),
            title: Text('Your cell: ${n.myAreaCode}'),
            subtitle: const Text('One staff member has one cell. It stays yours while your staff ID is active.'),
          ),
        )
      else
        Card(
          key: const ValueKey('hex-register-box'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Register this cell', style: Theme.of(context).textTheme.titleMedium),
              Text('Cell: ${n.code} (${hexSizeLabel(n.sizeKm)}), set from where you stand. You can register it only while standing inside it, and only if it is free.', key: const ValueKey('hex-register-cell')),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('hex-home-address'),
                controller: address,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Your home address', helperText: 'Staff must be local: home within 5 km of the cell\'s centre'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('hex-home-pin'),
                onPressed: () => setState(() => placingHome = !placingHome),
                icon: const Icon(Icons.home_outlined),
                label: Text(placingHome ? 'Now tap your home on the map' : home == null ? 'Put my home pin on the map' : 'Move my home pin'),
              ),
              if (km != null)
                Text(
                  'Home is ${km.toStringAsFixed(1)} km from the cell\'s centre${km > n.homeMaxKm ? ' (more than ${n.homeMaxKm.toStringAsFixed(0)} km: too far)' : ''}',
                  key: const ValueKey('hex-home-distance'),
                  style: TextStyle(color: km > n.homeMaxKm ? Theme.of(context).colorScheme.error : areaFreeColour, fontWeight: FontWeight.w600),
                ),
              CheckboxListTile(
                key: const ValueKey('hex-terms'),
                contentPadding: EdgeInsets.zero,
                value: accepted,
                onChanged: (v) => setState(() => accepted = v ?? false),
                title: const Text('I accept the Terms & Conditions'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (widget.onTerms != null) TextButton(key: const ValueKey('hex-terms-open'), onPressed: widget.onTerms, child: const Text('Read the Terms & Conditions')),
              if (problem != null) Text(problem!, key: const ValueKey('hex-problem'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const ValueKey('hex-register'),
                onPressed: busy || !n.free ? null : _send,
                icon: const Icon(Icons.how_to_reg),
                label: Text(n.free ? 'Register ${n.code}' : 'This cell is taken'),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.colour, required this.label});
  final Color colour;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 12, height: 12, decoration: BoxDecoration(color: colour.withValues(alpha: 0.4), border: Border.all(color: colour))),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 12)),
  ]);
}
