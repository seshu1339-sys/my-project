import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import 'area_map.dart';
import 'staff_hex_cell_page.dart';
import 'staff_area_model.dart';
import 'staff_offer_form.dart';
import 'staff_terms.dart';

/// Staff app dashboard: my area on the map (a tick on the shops with an offer today), today's count against the target with a
/// progress bar (mine and the vendors' apart), missed days this month, "Add Today's Offer" and the Terms & Conditions. With no area
/// yet: "Choose your area". Warnings come to the phone by themselves: the phone is saved for them when the staff member signs in
/// (owner, 7 Nov 2026), with only Android's own permission question.
class StaffAreaDashboard extends StatefulWidget {
  const StaffAreaDashboard({super.key, required this.store, required this.uid, this.load});
  final Store store;
  final String uid;
  // Test seam: what myStaffAreaToday answers.
  final Future<Map<String, dynamic>> Function()? load;

  @override
  State<StaffAreaDashboard> createState() => _StaffAreaDashboardState();
}

class _StaffAreaDashboardState extends State<StaffAreaDashboard> {
  late Future<AreaToday> today = _load();
  // The phone is saved once per app start and per staff member.
  static String? _registeredFor;

  @override
  void initState() {
    super.initState();
    if (widget.load == null && _registeredFor != widget.uid) _registerPhone();
  }

  Future<AreaToday> _load() async => AreaToday.fromData(await (widget.load ?? () => widget.store.call('myStaffAreaToday', const {}))());

  void _refresh() => setState(() => today = _load());

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => page));
    if (mounted) _refresh();
  }

  /// Saves this phone for the warnings by itself (the users pushTokens collection, the same place as the other apps). Android asks its own
  /// permission question once; if the staff member says no, the dashboard still shows every warning.
  Future<void> _registerPhone() async {
    if (kIsWeb) return;
    _registeredFor = widget.uid;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final tokens = widget.store.firestore.collection('users').doc(widget.uid).collection('pushTokens');
      Future<void> save(String token) => tokens.doc(token).set({'token': token, 'updatedAt': FieldValue.serverTimestamp()});
      final token = await messaging.getToken();
      if (token != null) await save(token);
      messaging.onTokenRefresh.listen((t) => save(t).catchError((_) {}));
    } catch (_) {
      // No warnings on the phone this time; the dashboard still shows them. Tried again at the next app start.
      _registeredFor = null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AreaToday>(
    future: today,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Card(
          child: ListTile(
            title: const Text('Your area could not load.'),
            subtitle: Text('${snapshot.error}'),
            trailing: TextButton(onPressed: _refresh, child: const Text('Try again')),
          ),
        );
      }
      if (!snapshot.hasData) return const Card(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()));
      return StaffAreaDashboardView(
        today: snapshot.data!,
        onRefresh: _refresh,
        // New staff get a hexagon cell (owner, 13 Nov 2026); the older automatic areas page stays in the code, unused.
        onChoose: () => _open(Scaffold(appBar: AppBar(title: const Text('My cell')), body: StaffHexCellPage(store: widget.store, onDone: _refresh))),
        onAddOffer: () => _open(StaffOfferForm(store: widget.store, shops: snapshot.data!.shops)),
        onTerms: () => _open(StaffTermsPage(store: widget.store)),
      );
    },
  );
}

class StaffAreaDashboardView extends StatelessWidget {
  const StaffAreaDashboardView({super.key, required this.today, this.onRefresh, this.onChoose, this.onAddOffer, this.onTerms, this.showMap = true});
  final AreaToday today;
  final VoidCallback? onRefresh, onChoose, onAddOffer, onTerms;
  final bool showMap;

  @override
  Widget build(BuildContext context) {
    final area = today.area;
    final error = Theme.of(context).colorScheme.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(area == null ? 'My area' : 'My area: ${area.name}', style: Theme.of(context).textTheme.titleLarge)),
            if (onRefresh != null) IconButton(key: const ValueKey('staff-area-refresh'), tooltip: 'Refresh', onPressed: onRefresh, icon: const Icon(Icons.refresh)),
          ]),
          if (today.warning.isNotEmpty)
            Container(
              key: const ValueKey('staff-area-warning'),
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: error.withValues(alpha: 0.08), border: Border.all(color: error), borderRadius: BorderRadius.circular(8)),
              child: Text(today.warning, style: TextStyle(color: error, fontWeight: FontWeight.w600)),
            ),
          if (area == null) ...[
            const Text('You have no cell yet. Go to a free (green) cell near your home and register it.'),
            const SizedBox(height: 8),
            FilledButton.icon(key: const ValueKey('staff-area-choose'), onPressed: onChoose, icon: const Icon(Icons.map_outlined), label: const Text('Choose your cell')),
          ] else ...[
            Text(
              area.hex
                  ? '${area.hexCode} • ${area.hexSizeKm} km cell • ${area.town}${area.status == 'pending' ? ' • waiting for approval' : ''}'
                  : '${area.town} • ${area.radiusKm.toStringAsFixed(area.radiusKm % 1 == 0 ? 0 : 1)} km${area.status == 'pending' ? ' • waiting for approval' : ''}',
              key: const ValueKey('staff-area-line'),
            ),
            if (showMap) ...[
              const SizedBox(height: 8),
              AreaMap(areas: [area], selectedId: area.id, shops: today.shops, height: 220),
            ],
            const SizedBox(height: 12),
            // Today's and this week's targets (only those the admin set), then the month's.
            for (final period in ['daily', 'weekly'])
              if (today.targets[period]?.entries.where((t) => t.value.target > 0).toList() case final set? when set.isNotEmpty) ...[
                Text(staffTargetPeriods[period]!, style: Theme.of(context).textTheme.titleMedium),
                for (final t in set) _Target(key: ValueKey('staff-target-$period-${t.key}'), label: staffTargetMeasures[t.key]!, p: t.value),
                const SizedBox(height: 8),
              ],
            Text('This month', style: Theme.of(context).textTheme.titleMedium),
            _Target(key: const ValueKey('staff-target-photos'), label: 'Live photos', p: today.photos),
            if (today.targets['monthly']?['Shop'] case final shops? when shops.target > 0) _Target(key: const ValueKey('staff-target-shops'), label: 'Shops visited', p: shops),
            _Target(key: const ValueKey('staff-target-vendors'), label: 'New vendors', p: today.vendors),
            _Target(key: const ValueKey('staff-target-paid'), label: 'New Premium (paid) vendors', p: today.paidVendors),
            Text(
              today.monthComplete ? 'Monthly target complete: this month counts.' : 'The month counts only when every target is complete.',
              key: const ValueKey('staff-month-complete'),
              style: TextStyle(fontWeight: FontWeight.w600, color: today.monthComplete ? areaFreeColour : null),
            ),
            const SizedBox(height: 8),
            _Target(key: const ValueKey('staff-target-rate-days'), label: 'Rate update days this week', p: today.rateDays),
            Text('Today: ${today.todayUpdates} rate update${today.todayUpdates == 1 ? '' : 's'} • offers in your area today: ${today.staffCount + today.vendorCount}', key: const ValueKey('staff-area-split')),
            Text(
              'Missed days this month: ${today.missedThisMonth} / ${today.maxMissedDays}',
              key: const ValueKey('staff-area-missed'),
              style: TextStyle(color: today.missedThisMonth >= today.maxMissedDays ? error : null, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('staff-area-add-offer'),
              onPressed: area.status == 'booked' ? onAddOffer : null,
              icon: const Icon(Icons.local_offer_outlined),
              label: const Text("Update a rate (live photo)"),
            ),
            const SizedBox(height: 12),
            Text('Shops in my area (${today.shops.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (today.shops.isEmpty) const Text('No shop with a map place is inside your area yet.'),
            for (final s in today.shops)
              ListTile(
                key: ValueKey('staff-area-shop-${s.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(s.offerToday ? Icons.check_circle : Icons.storefront, color: s.offerToday ? areaFreeColour : null),
                title: Text(s.name),
                subtitle: Text(s.offerToday ? 'Has an offer today' : 'No offer today'),
              ),
          ],
          const Divider(),
          Wrap(spacing: 8, children: [
            TextButton.icon(key: const ValueKey('staff-area-terms-open'), onPressed: onTerms, icon: const Icon(Icons.description_outlined), label: const Text('Terms & Conditions')),
          ]),
        ]),
      ),
    );
  }
}

/// One target with its progress bar: "Live photos: 12 / 100".
class _Target extends StatelessWidget {
  const _Target({super.key, required this.label, required this.p});
  final String label;
  final TargetProgress p;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$label: ${p.done} / ${p.target}${p.complete ? ' ✓' : ''}'),
      const SizedBox(height: 2),
      ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: p.progress, minHeight: 8, color: p.complete ? areaFreeColour : null)),
    ]),
  );
}
