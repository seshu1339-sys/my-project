import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import '../modules/stafflinks/stafflinks_module.dart';
import 'field_add_page.dart';
import 'screen_view.dart';
import '../services/usage.dart';

/// Shown only once the staff member's fieldStaff doc is 'active'. The staff member's ID, Add (link a vendor or service provider who
/// registered themselves, by their ID within 30 minutes), and "Vendors I registered", read only. Staff never create vendors or change
/// their items or prices (owner decision, 6 November 2026); the server re-checks everything whatever this screen shows.
/// [areaDashboard] is the Staff Area part (my area, today's offers, the daily target), given by the app.
class FieldWorkspace extends StatefulWidget {
  const FieldWorkspace({super.key, required this.store, required this.uid, this.areaDashboard});
  final Store store;
  final String uid;
  final Widget? areaDashboard;
  @override
  State<FieldWorkspace> createState() => _FieldWorkspaceState();
}

class _FieldWorkspaceState extends State<FieldWorkspace> {
  Store get store => widget.store;
  String get uid => widget.uid;

  @override
  Widget build(BuildContext context) => ScreenView('staff_workspace', child: _page(context));

  Widget _page(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('fieldStaff').doc(uid).snapshots(),
        builder: (context, snapshot) {
          final code = snapshot.data?.data()?['staffCode'] as String?;
          if (code == null) return const SizedBox.shrink();
          return Text('Staff ID: $code', key: const ValueKey('staff-id'), style: Theme.of(context).textTheme.titleMedium);
        },
      ),
      const SizedBox(height: 12),
      if (widget.areaDashboard != null) ...[widget.areaDashboard!, const SizedBox(height: 16)],
      FilledButton.icon(
        key: const ValueKey('field-add'),
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
        onPressed: () {
          Usage.button('staff_add_button');
          Navigator.push(context, MaterialPageRoute<void>(builder: (_) => FieldAddPage(store: store)));
        },
        icon: const Icon(Icons.link),
        label: const Text('Add (link a vendor or service)', style: TextStyle(fontSize: 18)),
      ),
      const SizedBox(height: 16),
      StaffLinkedList(store: store, uid: uid),
    ],
  );
}
