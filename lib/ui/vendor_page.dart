import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'quick_add.dart';
import 'vendor_registration_form.dart';

// The registration checks live with the registration form (a form must not depend on the page that shows it); re-exported for existing callers.
export 'vendor_registration_form.dart' show vendorApplicationErrors;
import 'vendor_workspace.dart';


class VendorPage extends StatefulWidget {
  const VendorPage({super.key, required this.store});
  final Store store;
  @override
  State<VendorPage> createState() => _VendorPageState();
}

class _VendorPageState extends State<VendorPage> {
  final paymentReference = TextEditingController();
  bool busy = false;
  Store get store => widget.store;
  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try { await action(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!store.live) return _demo();
    final user = store.user;
    if (user == null) return const SizedBox.shrink();
    final actions = [IconButton(tooltip: 'Log out', onPressed: store.logout, icon: const Icon(Icons.logout))];
    // The registration form only exists for a verified email address.
    if (!user.emailVerified) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vendor studio'), actions: actions),
        body: const _Message(title: 'Verify your email first', body: 'Sign out and use "Continue with email link" so we can verify your email. The vendor registration form opens after your email is verified.'),
      );
    }
    final uid = user.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Vendor studio'), actions: actions),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('vendorApplications').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const _Message(title: 'Could not load your application', body: 'Please check your connection and try again.');
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final application = snapshot.data!.data();
          final status = application?['status'];
          // An account the admin created for Quick Add, with no vendor application of its own,
          // goes straight to Quick Add instead of the registration form.
          if (status != 'approved') {
            return QuickAccountGate(store: store, role: 'vendor', quickOnly: () => QuickAddOnly(store: store), otherwise: () => _applicationStage(uid, user, application, status));
          }
          return _applicationStage(uid, user, application, status);
        },
      ),
    );
  }

  Widget _applicationStage(String uid, User user, Map<String, dynamic>? application, Object? status) {
    {
      {
        {
          if (application == null || status == 'rejected') return VendorRegistrationForm(store: store, email: user.email ?? '', previous: application);
          if (status == 'pending') return _pending(application);
          if (status == 'payment_required') return _feePayment(application);
          if (status == 'payment_submitted') return const _Message(title: 'Payment submitted', body: 'Your payment reference was submitted for administrator confirmation.');
          if (status != 'approved') return _Message(title: 'Application $status', body: 'Await administrator review.');
          // Suspension is kept on the vendor record (the application stays "approved"); the server
          // refuses every business action for a suspended vendor, this screen just explains why.
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: store.firestore.collection('vendors').doc(uid).snapshots(),
            builder: (context, vendor) {
              if (vendor.connectionState == ConnectionState.waiting && !vendor.hasData) return const Center(child: CircularProgressIndicator());
              final record = vendor.data?.data();
              if (record?['status'] == 'suspended') return _suspended(record!);
              return VendorWorkspace(store: store, uid: uid);
            },
          );
        }
      }
    }
  }

  Widget _suspended(Map<String, dynamic> vendor) {
    final reason = '${vendor['suspensionReason'] ?? ''}'.trim();
    return Center(child: SingleChildScrollView(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Padding(
      padding: const EdgeInsets.all(24), child: Column(children: [
        const Icon(Icons.block, size: 48),
        const SizedBox(height: 12),
        const Text('Account suspended', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('Your vendor account has been suspended by the administrator. Your shop and products are hidden from customers and you cannot add products, change prices or stock, or handle orders.', textAlign: TextAlign.center),
        if (reason.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Reason: $reason', textAlign: TextAlign.center)),
        const SizedBox(height: 12),
        const Text('Contact the administrator to have your account reinstated. Everything will reappear as before once it is.', textAlign: TextAlign.center),
      ]),
    ))));
  }

  Widget _pending(Map<String, dynamic> application) => Center(child: SingleChildScrollView(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Padding(
    padding: const EdgeInsets.all(24), child: Column(children: [
      const Icon(Icons.hourglass_top, size: 48),
      const SizedBox(height: 12),
      const Text('Pending Approval', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      const Text('Your application is waiting for office or admin approval. You will be notified here as soon as it is reviewed.', textAlign: TextAlign.center),
      const SizedBox(height: 12),
      const Text('Business features (adding products or materials, product photos, prices, stock and orders) stay locked until your application is approved.', textAlign: TextAlign.center),
      const SizedBox(height: 20),
      Card(child: ListTile(title: Text('${application['name']}'), subtitle: Text('${application['ownerName'] ?? ''} • ${application['shopCategory'] ?? ''}\n${application['address'] ?? ''} ${application['pincode'] ?? ''}'))),
      if ('${application['vendorCode'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Your Vendor ID: ${application['vendorCode']}', key: const ValueKey('pending-vendor-id'), style: const TextStyle(fontWeight: FontWeight.bold))),
    ]),
  ))));

  Widget _feePayment(Map<String, dynamic> application) => Center(child: SingleChildScrollView(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Padding(
    padding: const EdgeInsets.all(24), child: Column(children: [
      const Text('Vendor registration reviewed', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Text('Administrator fee: ${application['feeAmount']}'),
      if ((application['decisionReason'] ?? '').toString().trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Administrator note: ${application['decisionReason']}')),
      const SizedBox(height: 8),
      const Text('Complete the vendor fee payment using the instructions provided by the administrator, then enter the payment reference below.'),
      TextField(controller: paymentReference, decoration: const InputDecoration(labelText: 'Payment reference')),
      const SizedBox(height: 16),
      FilledButton(onPressed: busy ? null : () => run(() async { await store.submitVendorFeePayment(paymentReference.text.trim()); }), child: const Text('Submit payment reference')),
    ]),
  ))));

  Widget _demo() => Scaffold(appBar: AppBar(title: const Text('Vendor studio')), body: const Center(child: Text('Connect Firebase to apply and manage a vendor shop.')));
  @override
  void dispose() { paymentReference.dispose(); super.dispose(); }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});
  final String title, body;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
    const SizedBox(height: 12),
    Text(body, textAlign: TextAlign.center),
  ]))));
}
