import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import 'provider_registration_form.dart';
import 'text_prompt_dialog.dart';

/// Services in the vendor app: the service provider's own flow. Registration (verified email first), then waiting for the admin, then
/// the live service with the charge per hour, which the provider can change. A provider account is separate from vendor accounts.
class ServiceProviderPage extends StatelessWidget {
  const ServiceProviderPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    final user = store.user;
    final actions = [if (store.live) IconButton(tooltip: 'Log out', onPressed: store.logout, icon: const Icon(Icons.logout))];
    Widget page(Widget body) => Scaffold(appBar: AppBar(title: const Text('Services'), actions: actions), body: body);
    if (!store.live || user == null) return page(const _Message(title: 'Services', body: 'Connect Firebase to register as a service provider.'));
    if (!user.emailVerified) {
      return page(const _Message(title: 'Verify your email first', body: 'Sign out and use "Continue with email link" so we can verify your email. The service-provider registration opens after that.'));
    }
    return page(
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('providerApplications').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const _Message(title: 'Could not load your application', body: 'Please check your connection and try again.');
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final application = snapshot.data!.data();
          final status = application?['status'];
          if (application == null || status == 'rejected') return ProviderRegistrationForm(store: store, email: user.email ?? '', previous: application);
          if (status == 'pending') return ProviderStatusView(application: application);
          return ProviderStatusView(application: application, onChangeRate: (rate) => store.updateProviderRate(rate));
        },
      ),
    );
  }
}

/// A submitted application: waiting for the admin, or approved and live (then the provider can change the charge per hour).
class ProviderStatusView extends StatelessWidget {
  const ProviderStatusView({super.key, required this.application, this.onChangeRate});
  final Map<String, dynamic> application;
  final Future<void> Function(double rate)? onChangeRate;

  Future<void> _changeRate(BuildContext context) async {
    final text = await askText(context, title: 'Your charge per hour', label: '₹ per hour', initial: '${application['hourlyRate'] ?? ''}', keyboardType: const TextInputType.numberWithOptions(decimal: true), fieldKey: const ValueKey('provider-new-rate'));
    final value = double.tryParse(text ?? '');
    if (value == null || value <= 0 || !context.mounted) return;
    try {
      await onChangeRate!(value);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved. Customers see your new charge now.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final approved = application['status'] == 'approved';
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(approved ? Icons.verified_outlined : Icons.hourglass_top, size: 64),
                const SizedBox(height: 12),
                Text(approved ? 'Your service is live' : 'Pending Approval', key: const ValueKey('provider-status'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  approved
                      ? 'Customers near you can find you under ${application['serviceName'] ?? 'your service'} and call you.'
                      : 'Your application is waiting for the admin\'s approval. You will see it here as soon as it is reviewed.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    title: Text('${application['name'] ?? ''}'),
                    subtitle: Text('${application['serviceName'] ?? ''} • ₹${application['hourlyRate'] ?? ''} per hour\n${application['address'] ?? ''} ${application['pincode'] ?? ''}\n${application['phone'] ?? ''}'),
                    isThreeLine: true,
                  ),
                ),
                if (approved && onChangeRate != null)
                  OutlinedButton.icon(key: const ValueKey('provider-change-rate'), onPressed: () => _changeRate(context), icon: const Icon(Icons.currency_rupee), label: const Text('Change charge per hour')),
              ],
            ),
          ),
        ),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
