import 'package:flutter/material.dart';

import '../../data/store.dart';
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
  ]);
}
