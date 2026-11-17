import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/admin_ads.dart';
import '../domain/agent_command.dart';
import '../modules/offerdisplay/offerdisplay_module.dart';
import '../services/admin_ads_watch.dart';
import '../services/agent_log.dart';
import '../services/places_directory.dart';
import 'agent_confirm.dart';

/// Where a town is, for the km of an ad: a shop of that town first (no download), else the India Post directory. Null when unknown.
Future<({double lat, double lng, String district, String state})?> resolveAdPlace(Store store, String town) async {
  final want = town.trim().toLowerCase();
  if (want.isEmpty) return null;
  for (final s in store.entries('shops')) {
    if (s.text('town').toLowerCase() == want && s.number('latitude') != 0) {
      return (lat: s.number('latitude'), lng: s.number('longitude'), district: s.text('district'), state: s.text('state'));
    }
  }
  try {
    final index = await PlacesDirectory.instance.load(states: PlacesDirectory.homeStates);
    final p = index.townNamed(town.trim());
    if (p != null && p.hasCoordinates) return (lat: p.latitude, lng: p.longitude, district: p.district, state: p.state);
  } catch (_) {}
  return null;
}

/// The command box's ad flow (owner spec D): the words fill the form (photo, place, km, days), the admin checks the PREVIEW, and OK
/// puts it live. An All-India ad asks to type YES first (owner spec I).
Future<void> openAdFlow(BuildContext context, Store store, AgentCommand command, {XFile? photo}) => Navigator.push(
  context,
  MaterialPageRoute<void>(builder: (_) => AgentAdFormPage(store: store, draft: adminAdFromCommand(command, now: DateTime.now()), photo: photo, command: command.text)),
);

class AgentAdFormPage extends StatefulWidget {
  const AgentAdFormPage({super.key, required this.store, required this.draft, this.photo, this.command = '', this.resolve, this.save, this.upload});
  final Store store;
  final AdminAd draft;
  final XFile? photo;
  final String command;

  /// Test seams: finding a town, saving the ad and uploading the photo.
  final Future<({double lat, double lng, String district, String state})?> Function(String town)? resolve;
  final Future<String> Function(AdminAd ad)? save;
  final Future<String> Function(XFile file)? upload;

  @override
  State<AgentAdFormPage> createState() => _AgentAdFormPageState();
}

class _AgentAdFormPageState extends State<AgentAdFormPage> {
  late AdminAd ad = widget.draft;
  late final title = TextEditingController(text: ad.title);
  late final item = TextEditingController(text: ad.productName);
  late final place = TextEditingController(text: ad.reach == AdReach.district ? ad.district : ad.reach == AdReach.state ? ad.state : ad.town);
  late final km = TextEditingController(text: _n(ad.radiusKm));
  late final days = TextEditingController(text: '${ad.endsAt == null ? 1 : ad.endsAt!.difference(ad.startsAt ?? DateTime.now()).inDays}');
  late final hours = TextEditingController(text: '${ad.endsAt == null ? 0 : ad.endsAt!.difference(ad.startsAt ?? DateTime.now()).inHours % 24}');
  bool busy = false, previewing = false;
  String? note, error;

  Store get store => widget.store;

  static String _n(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

  @override
  void initState() {
    super.initState();
    if (widget.photo != null) _usePhoto(widget.photo!);
    if (ad.reach == AdReach.radius && ad.town.isNotEmpty) _findPlace();
  }

  @override
  void dispose() {
    for (final c in [title, item, place, km, days, hours]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _usePhoto(XFile file) async {
    setState(() { busy = true; note = 'Uploading the photo…'; });
    try {
      final url = await (widget.upload ?? (f) => store.upload(f, folder: 'catalog'))(file);
      if (mounted) setState(() { ad = ad.copyWith(photoUrl: url); note = null; });
    } catch (e) {
      if (mounted) setState(() => error = 'Photo: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600);
    if (file != null) await _usePhoto(file);
  }

  Future<void> _findPlace() async {
    final name = place.text.trim();
    if (name.isEmpty) return;
    final found = await (widget.resolve ?? (t) => resolveAdPlace(store, t))(name);
    if (!mounted) return;
    setState(() {
      if (found == null) {
        error = 'Could not find "$name". Type another spelling, or choose Town instead of km.';
      } else {
        error = null;
        ad = ad.copyWith(latitude: found.lat, longitude: found.lng, town: name, district: ad.district.isEmpty ? found.district : null, state: ad.state.isEmpty ? found.state : null);
      }
    });
  }

  /// The form's values into the ad.
  AdminAd _read() {
    final start = ad.startsAt ?? DateTime.now();
    final d = int.tryParse(days.text.trim()) ?? 0, h = int.tryParse(hours.text.trim()) ?? 0;
    final p = place.text.trim();
    return ad.copyWith(
      title: title.text.trim(),
      productName: item.text.trim(),
      radiusKm: double.tryParse(km.text.trim()) ?? ad.radiusKm,
      town: ad.reach == AdReach.town || ad.reach == AdReach.radius ? p : null,
      district: ad.reach == AdReach.district ? p : null,
      state: ad.reach == AdReach.state ? p : null,
      startsAt: start,
      endsAt: start.add(Duration(days: d, hours: h)),
    );
  }

  Future<void> _preview() async {
    if (ad.reach == AdReach.radius && place.text.trim().isNotEmpty && (ad.latitude == null || ad.town != place.text.trim())) await _findPlace();
    final next = _read();
    setState(() {
      ad = next;
      error = next.missing.isEmpty ? null : next.missing;
      previewing = next.missing.isEmpty;
    });
  }

  Future<void> _goLive() async {
    final ready = _read();
    if (ready.missing.isNotEmpty) return setState(() => error = ready.missing);
    if (ready.reach == AdReach.allIndia &&
        !await confirmRiskyAction(context, title: 'Show this ad in ALL of India?', detail: 'Every customer in India will see it in ${ready.placement == AdminAdPlacement.rightBox ? 'the right-side boxes' : "Today's Offers"} for the time you chose.')) {
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final id = await (widget.save ??
          (a) async => (await store.firestore.collection('adminAds').add({...a.toData(), 'createdBy': store.user?.uid ?? '', 'createdAt': FieldValue.serverTimestamp()})).id)(ready);
      AgentLog.write(store, action: 'ad_live', command: widget.command, target: id, details: {'placement': ready.placement.name, 'reach': ready.reachLabel, 'ends': ready.endsAt?.toIso8601String() ?? ''});
      if (mounted) setState(() { note = 'Live now: it joins the rotation of ${ready.reachLabel}.'; previewing = false; });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _previewBoxes() {
    final rate = ad.isRate ? liveRateOf(store, ad.productName) : null;
    final photo = ad.photoUrl.isNotEmpty ? ad.photoUrl : (ad.isRate ? rateItemPhoto(store, ad.productName) : '');
    final end = ad.endsAt?.toLocal();
    return Card(
      key: const ValueKey('agent-ad-preview'),
      color: const Color(0xFFF1F8E9),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('PREVIEW', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
          const SizedBox(height: 8),
          Wrap(spacing: 16, runSpacing: 12, children: [
            if (ad.showsIn(AdminAdPlacement.todaysOffers))
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("Today's Offers box", style: TextStyle(fontSize: 12)),
                SizedBox(
                  width: 150,
                  height: 190,
                  child: VendorOfferBox(
                    photoUrl: photo,
                    price: ad.isRate ? (rate == null ? 'No price yet' : '₹${rate.round()}') : ad.title,
                    note: ad.isRate ? "Today's rate: ${ad.productName}" : '',
                    frame: BoxDecoration(color: const Color(0xFFE53935), borderRadius: BorderRadius.circular(20)),
                    colour: const Color(0xFFE53935),
                    radius: 15,
                    onTap: () {},
                  ),
                ),
              ]),
            if (ad.showsIn(AdminAdPlacement.rightBox))
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Right-side ad box', style: TextStyle(fontSize: 12)),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 220,
                    height: 140,
                    child: Stack(fit: StackFit.expand, children: [
                      photo.isEmpty ? const ColoredBox(color: Color(0xFFEEEEEE), child: Icon(Icons.image_outlined)) : Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, e, s) => const ColoredBox(color: Color(0xFFEEEEEE))),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(width: double.infinity, color: const Color(0xAA000000), padding: const EdgeInsets.all(6), child: Text(ad.isRate ? "Today's rate: ${ad.productName}" : ad.title, maxLines: 2, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                      ),
                    ]),
                  ),
                ),
              ]),
          ]),
          const SizedBox(height: 10),
          Text(
            key: const ValueKey('agent-ad-summary'),
            '${switch (ad.placement) { AdminAdPlacement.todaysOffers => "Today's Offers", AdminAdPlacement.rightBox => 'Right-side ad boxes', AdminAdPlacement.both => "Today's Offers + right-side boxes" }} · ${ad.reachLabel} · '
            'until ${end == null ? '?' : '${end.day}/${end.month} ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}'}\n'
            'It joins the same rotation as the vendor boxes of that place (one box every few seconds), with no priority.',
          ),
          const SizedBox(height: 10),
          Row(children: [
            FilledButton.icon(key: const ValueKey('agent-ad-ok'), onPressed: busy ? null : _goLive, icon: const Icon(Icons.check), label: const Text('OK — make it live')),
            const SizedBox(width: 12),
            TextButton(onPressed: () => setState(() => previewing = false), child: const Text('Change')),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ad by command')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.command.isNotEmpty) Text('"${widget.command}"', key: const ValueKey('agent-ad-command'), style: const TextStyle(fontStyle: FontStyle.italic)),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'photo', label: Text('Photo ad'), icon: Icon(Icons.image_outlined)), ButtonSegment(value: 'rate', label: Text('Live rate'), icon: Icon(Icons.currency_rupee))],
          selected: {ad.kind},
          onSelectionChanged: (s) => setState(() { ad = ad.copyWith(kind: s.first); previewing = false; }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<AdminAdPlacement>(
          key: const ValueKey('agent-ad-placement'),
          initialValue: ad.placement,
          decoration: const InputDecoration(labelText: 'Where', border: OutlineInputBorder(), isDense: true),
          items: const [
            DropdownMenuItem(value: AdminAdPlacement.todaysOffers, child: Text("Today's Offers")),
            DropdownMenuItem(value: AdminAdPlacement.rightBox, child: Text('Right-side ad boxes')),
            DropdownMenuItem(value: AdminAdPlacement.both, child: Text('Both')),
          ],
          onChanged: (v) => setState(() { ad = ad.copyWith(placement: v); previewing = false; }),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: const Color(0xFFEEEEEE), borderRadius: BorderRadius.circular(8)),
            clipBehavior: Clip.antiAlias,
            child: ad.photoUrl.isEmpty ? const Icon(Icons.image_outlined) : Image.network(ad.photoUrl, fit: BoxFit.cover, errorBuilder: (_, e, s) => const Icon(Icons.broken_image_outlined)),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(key: const ValueKey('agent-ad-photo'), onPressed: busy ? null : _pickPhoto, icon: const Icon(Icons.upload), label: Text(ad.photoUrl.isEmpty ? 'Choose photo' : 'Change photo')),
        ]),
        const SizedBox(height: 12),
        if (ad.isRate)
          TextField(key: const ValueKey('agent-ad-item'), controller: item, decoration: const InputDecoration(labelText: 'Item whose live rate shows (e.g. Tomato)', border: OutlineInputBorder(), isDense: true))
        else
          TextField(key: const ValueKey('agent-ad-title'), controller: title, maxLength: 60, decoration: const InputDecoration(labelText: 'Text on the ad (optional)', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 12),
        const Text('Who sees it', style: TextStyle(fontWeight: FontWeight.w600)),
        Wrap(spacing: 8, children: [
          for (final r in AdReach.values)
            ChoiceChip(
              key: ValueKey('agent-ad-reach-${r.name}'),
              label: Text(switch (r) { AdReach.radius => 'Place + km', AdReach.town => 'Town', AdReach.district => 'District', AdReach.state => 'State', AdReach.allIndia => 'All India' }),
              selected: ad.reach == r,
              onSelected: (_) => setState(() { ad = ad.copyWith(reach: r); previewing = false; }),
            ),
        ]),
        const SizedBox(height: 8),
        if (ad.reach != AdReach.allIndia)
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('agent-ad-place'),
                controller: place,
                onSubmitted: (_) => _findPlace(),
                decoration: InputDecoration(
                  labelText: switch (ad.reach) { AdReach.district => 'District', AdReach.state => 'State', _ => 'Town / place' },
                  helperText: ad.reach == AdReach.radius && ad.latitude != null ? 'Found: ${ad.latitude!.toStringAsFixed(4)}, ${ad.longitude!.toStringAsFixed(4)}' : null,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            if (ad.reach == AdReach.radius) ...[
              const SizedBox(width: 8),
              SizedBox(width: 90, child: TextField(key: const ValueKey('agent-ad-km'), controller: km, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'km', border: OutlineInputBorder(), isDense: true))),
            ],
          ]),
        const SizedBox(height: 12),
        Row(children: [
          SizedBox(width: 110, child: TextField(key: const ValueKey('agent-ad-days'), controller: days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Days', border: OutlineInputBorder(), isDense: true))),
          const SizedBox(width: 8),
          SizedBox(width: 110, child: TextField(key: const ValueKey('agent-ad-hours'), controller: hours, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Hours', border: OutlineInputBorder(), isDense: true))),
          const SizedBox(width: 12),
          const Expanded(child: Text('Starts now.')),
        ]),
        const SizedBox(height: 16),
        if (note != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(note!, key: const ValueKey('agent-ad-note'), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600))),
        if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error!, key: const ValueKey('agent-ad-error'), style: const TextStyle(color: Colors.red))),
        if (previewing) _previewBoxes() else FilledButton.icon(key: const ValueKey('agent-ad-preview-button'), onPressed: busy ? null : _preview, icon: const Icon(Icons.preview_outlined), label: const Text('PREVIEW')),
      ],
    ),
  );
}

/// Ads & Offers > Ads by command: every admin ad made by command, running first, with Stop (nothing is deleted).
class AdminAdsPage extends StatelessWidget {
  const AdminAdsPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    if (!store.live) return const Center(child: Text('Ads by command need the live panel.'));
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('adminAds').orderBy('createdAt', descending: true).limit(100).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final now = DateTime.now();
        final ads = [for (final d in snap.data!.docs) AdminAd.from(d.id, d.data())];
        if (ads.isEmpty) return const Center(child: Text('No ads by command yet. Try: "this photo, Today\'s Offers, Narsipatnam, 10 km, 2 days".'));
        return ListView(children: [
          for (final a in ads)
            ListTile(
              leading: a.photoUrl.isEmpty ? const Icon(Icons.campaign_outlined) : Image.network(a.photoUrl, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, e, s) => const Icon(Icons.campaign_outlined)),
              title: Text(a.isRate ? "Live rate: ${a.productName}" : (a.title.isEmpty ? 'Photo ad' : a.title)),
              subtitle: Text('${a.placement.name} · ${a.reachLabel} · ${a.liveAt(now) ? 'LIVE' : a.active ? 'not running now' : 'stopped'}'),
              trailing: a.active
                  ? TextButton(
                      onPressed: () async {
                        await store.firestore.collection('adminAds').doc(a.id).update({'active': false});
                        AgentLog.write(store, action: 'ad_stop', target: a.id);
                      },
                      child: const Text('Stop'),
                    )
                  : null,
            ),
        ]);
      },
    );
  }
}
