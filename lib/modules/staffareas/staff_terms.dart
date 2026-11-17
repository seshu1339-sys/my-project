import 'package:flutter/material.dart';

import '../../data/store.dart';
import 'hex_cell.dart';
import 'staff_area_model.dart';

/// The staff Terms & Conditions as the admin wrote them (staffAreaSettings/main.terms), or the default ones.
Stream<StaffAreaSettings> staffAreaSettings(Store store) =>
    store.firestore.collection('staffAreaSettings').doc('main').snapshots().map((doc) => StaffAreaSettings.fromData(doc.data()));

/// Staff app > Terms & Conditions (also opened from the registration's tick box).
class StaffTermsPage extends StatelessWidget {
  const StaffTermsPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Terms & Conditions')),
    body: StreamBuilder<StaffAreaSettings>(
      stream: store.live ? staffAreaSettings(store) : Stream.value(const StaffAreaSettings()),
      builder: (context, settings) => StaffTermsView(settings: settings.data ?? const StaffAreaSettings()),
    ),
  );
}

class StaffTermsView extends StatelessWidget {
  const StaffTermsView({super.key, required this.settings});
  final StaffAreaSettings settings;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    SelectableText(settings.terms, key: const ValueKey('staff-terms-text')),
    const SizedBox(height: 16),
    Text(
      'Now: rate updates on at least ${settings.rateDaysPerWeek} days a week; monthly targets of ${settings.monthlyPhotoTarget} live photos, ${settings.monthlyVendorTarget} vendor registrations and ${settings.monthlyPaidVendorTarget} paid vendor registrations; the account stops at ${settings.maxMissedDays} missed days in a month.',
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 16),
    // Always shown (owner, 13 Nov 2026), also when the admin wrote their own Terms.
    const Text('Your cell', style: TextStyle(fontWeight: FontWeight.bold)),
    const Text(
      'Your area is one hexagon cell, set automatically from where you stand (1, 2 or 5 km by how many people live there). '
      'You register it standing inside it, only if it is free; one cell per staff member, never shared. '
      'You must be local: your home must be within 5 km of the centre of your cell, or the cell cannot be registered. '
      'A cancelled staff ID is closed for good and never given again; its cell becomes free and its vendors move to LOCAMARKET.',
      key: ValueKey('staff-terms-cell-rules'),
    ),
    const SizedBox(height: 12),
    const Text(worldPopCredit, key: ValueKey('staff-terms-worldpop'), style: TextStyle(fontSize: 12, color: Colors.black54)),
  ]);
}
