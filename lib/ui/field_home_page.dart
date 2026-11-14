import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import 'field_registration_form.dart';
import '../modules/staffareas/staffareas_module.dart';
import '../modules/flash/flash_module.dart' show staffAppFlashButton;
import 'field_workspace.dart';

/// Streams the signed-in staff member's own fieldStaff/{uid} doc and shows the
/// right screen for its status. Unlike before, no fieldStaff/{uid} doc existing
/// yet no longer auto-requests access: it shows FieldRegistrationForm instead,
/// since a staff photo (and now name/phone) is mandatory and can only be
/// collected through a form, not silently from the auth token.
class FieldHomePage extends StatefulWidget {
  const FieldHomePage({super.key, required this.store});
  final Store store;
  @override
  State<FieldHomePage> createState() => _FieldHomePageState();
}

class _FieldHomePageState extends State<FieldHomePage> {
  Store get store => widget.store;

  @override
  Widget build(BuildContext context) {
    final user = store.user;
    if (user == null) return const SizedBox.shrink();
    final actions = [IconButton(tooltip: 'Log out', onPressed: store.logout, icon: const Icon(Icons.logout))];
    if (!store.emailConfirmed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loca Market staff'), actions: actions),
        body: const _Message(
          title: 'Verify your email first',
          body: 'Sign out and sign in again with Google or an email code so we can verify your email. Registration opens once your email is verified.',
        ),
      );
    }
    return Scaffold(
      floatingActionButton: staffAppFlashButton(store),
      appBar: AppBar(title: const Text('Loca Market staff'), actions: actions),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('fieldStaff').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const _Message(title: 'Could not load your access status', body: 'Please check your connection and try again.');
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final status = snapshot.data!.data()?['status'];
          if (status == 'active') return FieldWorkspace(store: store, uid: user.uid, areaDashboard: StaffAreaDashboard(store: store, uid: user.uid));
          // Quick Add is closed (owner, 6 Nov 2026): every staff account goes through registration and the area.
          return _fieldStage(snapshot.data!, status);
        },
      ),
    );
  }

  Widget _fieldStage(DocumentSnapshot<Map<String, dynamic>> snapshot, Object? status) {
    {
      {
        {
          // The staff app signs in with the email's own staff login (functions/role-logins.js), so the same email may also be a
          // customer, vendor or service provider: those are separate logins with their own records. Sending this form makes the
          // pending staff record; nothing can be submitted until an administrator approves it.
          if (!snapshot.exists) return FieldRegistrationForm(store: store, displayName: store.user?.displayName ?? '');
          if (status == 'suspended') {
            return const _Message(title: 'Access suspended', body: 'Your field staff access has been suspended by the administrator. Contact them to have it reinstated.');
          }
          if (status == 'cancelled') {
            return const _Message(title: 'Staff ID closed', body: 'Your staff ID was cancelled by LOCAMARKET and is closed for good. Your cell is free for a new staff member. Contact the LOCAMARKET office if you have questions.');
          }
          if (status == 'rejected') {
            return const _Message(title: 'Access request not approved', body: 'Your field staff access request was not approved. Contact the administrator for details.');
          }
          final code = '${snapshot.data()?['staffCode'] ?? ''}';
          // Registration finishes with the area: the staff member chooses a free one standing inside it and accepts the Terms
          // (lib/modules/staffareas). The area stays Pending, held for them, until the admin approves them.
          return _PendingStaff(store: store, uid: snapshot.id, staffCode: code);
        }
      }
    }
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});
  final String title, body;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(body, textAlign: TextAlign.center),
        ]),
      ),
    ),
  );
}

/// A registered staff member waiting for approval: first their area (claimed standing inside it, Terms accepted), then the wait.
class _PendingStaff extends StatelessWidget {
  const _PendingStaff({required this.store, required this.uid, required this.staffCode});
  final Store store;
  final String uid, staffCode;

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('staffAreaStaff').doc(uid).snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final mine = snapshot.data!.data();
      final area = mine?['areaId'] == null ? null : '${mine?['areaName'] ?? ''}';
      // New staff register a hexagon cell (owner, 13 Nov 2026); the older claim page stays in the code, unused.
      if (area == null) return StaffHexCellPage(store: store);
      return _Message(
        title: 'Waiting for approval',
        body: 'Your registration is waiting for administrator approval. Your area "$area" is held for you until then; nobody else can take it.'
            '${staffCode.isEmpty ? '' : '\n\nYour Staff ID: $staffCode'}',
      );
    },
  );
}
