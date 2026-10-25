import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import 'field_registration_form.dart';
import 'quick_add.dart';
import 'field_workspace.dart';

/// Why this login cannot register as field staff: vendor, service-provider and field-staff accounts are completely separate, so an
/// account that is already a vendor or a service provider is told to use another email address. Null when it may register.
String? fieldAccountBlock({
  Map<String, dynamic>? vendorApplication,
  Map<String, dynamic>? vendor,
  Map<String, dynamic>? quickAccount,
  Map<String, dynamic>? providerApplication,
  Map<String, dynamic>? provider,
}) {
  const after = 'Field staff must use a separate account: sign out and register as staff with a different email address.';
  if (vendorApplication != null || vendor != null || quickAccount?['role'] == 'vendor') return 'This account is a vendor account. $after';
  if (providerApplication != null || provider != null) return 'This account is a service-provider account. $after';
  return null;
}

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
          final status = snapshot.data!.data()?['status'];
          if (status == 'active') return FieldWorkspace(store: store, uid: user.uid);
          // An account the admin created for Quick Add goes straight to Quick Add.
          return QuickAccountGate(store: store, role: 'staff', quickOnly: () => QuickAddOnly(store: store), otherwise: () => _fieldStage(snapshot.data!, status));
        },
      ),
    );
  }

  Widget _fieldStage(DocumentSnapshot<Map<String, dynamic>> snapshot, Object? status) {
    {
      {
        {
          if (!snapshot.exists) return _SeparateAccountCheck(store: store);
          if (status == 'suspended') {
            return const _Message(title: 'Access suspended', body: 'Your field staff access has been suspended by the administrator. Contact them to have it reinstated.');
          }
          if (status == 'rejected') {
            return const _Message(title: 'Access request not approved', body: 'Your field staff access request was not approved. Contact the administrator for details.');
          }
          final code = '${snapshot.data()?['staffCode'] ?? ''}';
          return _Message(
            title: 'Waiting for approval',
            body: 'Your access request is waiting for administrator approval. You will be able to submit entries here once it is approved.'
                '${code.isEmpty ? '' : '\n\nYour Staff ID: $code'}',
          );
        }
      }
    }
  }
}

/// No staff record yet: the registration form, unless this login is already a vendor or a service-provider account.
class _SeparateAccountCheck extends StatelessWidget {
  const _SeparateAccountCheck({required this.store});
  final Store store;

  Future<String?> _block() async {
    final uid = store.user!.uid;
    Future<Map<String, dynamic>?> read(String collection) async => (await store.firestore.collection(collection).doc(uid).get()).data();
    final docs = await Future.wait([for (final c in ['vendorApplications', 'vendors', 'quickAccounts', 'providerApplications', 'providers']) read(c)]);
    return fieldAccountBlock(vendorApplication: docs[0], vendor: docs[1], quickAccount: docs[2], providerApplication: docs[3], provider: docs[4]);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _block(),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      // When the check itself fails the form still opens; the server refuses a second kind of account anyway.
      final block = snapshot.hasError ? null : snapshot.data;
      if (block != null) return _Message(title: 'Use a separate account', body: block);
      return FieldRegistrationForm(store: store, displayName: store.user?.displayName ?? '');
    },
  );
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
