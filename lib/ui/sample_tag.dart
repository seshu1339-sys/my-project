import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../domain/samples.dart';

/// The sample accounts (_sampleAccounts, readable by the admin only), kept up to date while the admin panel is open, so a record a
/// sample vendor or staff member made through the apps carries the SAMPLE label too.
class SampleOwners {
  SampleOwners._();
  static final ValueNotifier<Set<String>> owners = ValueNotifier(const {});
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  /// Starts following _sampleAccounts (once). Without access (not the admin), or without Firebase (tests), the set just stays empty.
  static void watch(FirebaseFirestore Function() firestore) {
    if (_sub != null) return;
    try {
      _sub = firestore().collection('_sampleAccounts').limit(2000).snapshots().listen(
        (s) => owners.value = {for (final d in s.docs) d.id},
        onError: (Object _) {},
      );
    } catch (_) {
      // No Firebase app: no sample labels.
    }
  }
}

/// The orange SAMPLE label the admin panel shows on every sample record.
class SampleTag extends StatelessWidget {
  const SampleTag({super.key});
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('sample-tag'),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE0B2),
      border: Border.all(color: const Color(0xFFE65100)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: const Text('SAMPLE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFE65100), letterSpacing: .5)),
  );
}

/// [title] with the SAMPLE label after it when the record ([id], [data]) is sample data; just [title] otherwise.
class SampleTitle extends StatelessWidget {
  const SampleTitle(this.title, {super.key, required this.id, required this.data, this.style});
  final String title, id;
  final Map<String, dynamic> data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Set<String>>(
    valueListenable: SampleOwners.owners,
    builder: (context, owners, _) {
      final text = Text(title, style: style, overflow: TextOverflow.ellipsis);
      if (!isSampleData(id, data, owners)) return text;
      return Row(mainAxisSize: MainAxisSize.min, children: [Flexible(child: text), const SizedBox(width: 6), const SampleTag()]);
    },
  );
}
