import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import 'field_registration_form.dart';
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
    if (!user.emailVerified) {
      return Scaffold(
        appBar: AppBar(title: const Text('Field Assistant'), actions: actions),
        body: const _Message(
          title: 'Verify your email first',
          body: 'Sign out and use "Continue with email link" so we can verify your email. Registration opens once your email is verified.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Field Assistant'), actions: actions),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('fieldStaff').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const _Message(title: 'Could not load your access status', body: 'Please check your connection and try again.');
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (!snapshot.data!.exists) return FieldRegistrationForm(store: store);
          final status = snapshot.data!.data()?['status'];
          if (status == 'active') return FieldWorkspace(store: store, uid: user.uid);
          if (status == 'suspended') {
            return const _Message(title: 'Access suspended', body: 'Your field staff access has been suspended by the administrator. Contact them to have it reinstated.');
          }
          if (status == 'rejected') {
            return const _Message(title: 'Access request not approved', body: 'Your field staff access request was not approved. Contact the administrator for details.');
          }
          return const _Message(
            title: 'Waiting for approval',
            body: 'Your access request is waiting for administrator approval. You will be able to submit entries here once it is approved.',
          );
        },
      ),
    );
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
