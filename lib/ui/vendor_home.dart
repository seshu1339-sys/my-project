import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../modules/transport/transport_module.dart';
import 'vendor_page.dart';

/// What a signed-in account of the vendor app is. A vendor account and a service-provider account are completely separate: one login
/// is never both. A person who wants both registers twice, with two different email addresses.
enum VendorAccountRole { none, vendor, provider }

/// The account's role from its records: a vendor application or vendor record (or an admin-made Quick Add vendor account) makes it a
/// vendor account; a service-provider application makes it a provider account. Neither yet: it may become either.
VendorAccountRole vendorAccountRole({
  Map<String, dynamic>? vendorApplication,
  Map<String, dynamic>? vendor,
  Map<String, dynamic>? quickAccount,
  Map<String, dynamic>? providerApplication,
}) {
  if (vendorApplication != null || vendor != null || quickAccount?['role'] == 'vendor') return VendorAccountRole.vendor;
  if (providerApplication != null) return VendorAccountRole.provider;
  return VendorAccountRole.none;
}

/// The vendor app's home after sign-in: Vendor, Services and Transport.
class VendorHomePage extends StatelessWidget {
  const VendorHomePage({super.key, required this.store});
  final Store store;

  void _open(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Widget _view(BuildContext context, VendorAccountRole role) => VendorHomeView(
    role: role,
    onVendor: () => _open(context, VendorPage(store: store)),
    onServices: () => _open(context, const ServiceProviderComingPage()),
    onTransport: () => openTransport(context, store),
    onLogout: store.live ? store.logout : null,
  );

  @override
  Widget build(BuildContext context) {
    final uid = store.user?.uid;
    if (!store.live || uid == null) return _view(context, VendorAccountRole.none);
    DocumentReference<Map<String, dynamic>> doc(String collection) => store.firestore.collection(collection).doc(uid);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: doc('vendorApplications').snapshots(),
      builder: (context, application) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: doc('vendors').snapshots(),
        builder: (context, vendor) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: doc('quickAccounts').snapshots(),
          builder: (context, quick) => _view(
            context,
            vendorAccountRole(vendorApplication: application.data?.data(), vendor: vendor.data?.data(), quickAccount: quick.data?.data()),
          ),
        ),
      ),
    );
  }
}

/// The three options, laid out for any screen width. An option that does not belong to this account explains why instead of opening.
class VendorHomeView extends StatelessWidget {
  const VendorHomeView({super.key, required this.role, required this.onVendor, required this.onServices, required this.onTransport, this.onLogout});
  final VendorAccountRole role;
  final VoidCallback onVendor, onServices, onTransport;
  final VoidCallback? onLogout;

  static const vendorBlocked =
      'This account is registered as a service provider. A vendor account must be a separate account: sign out and register as a vendor with a different email address.';
  static const servicesBlocked =
      'This account is registered as a vendor. A service-provider account must be a separate account: sign out and register as a service provider with a different email address.';

  void _explain(BuildContext context, String title, String body) => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('OK'))],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final options = [
      _Option(
        key: 'vendor',
        title: 'Vendor',
        subtitle: role == VendorAccountRole.provider ? 'Not for this account' : 'Sell your shop\'s items',
        icon: Icons.storefront_outlined,
        color: const Color(0xff8c4a22),
        enabled: role != VendorAccountRole.provider,
        onTap: role == VendorAccountRole.provider ? () => _explain(context, 'Vendor', vendorBlocked) : onVendor,
      ),
      _Option(
        key: 'services',
        title: 'Services',
        subtitle: role == VendorAccountRole.vendor ? 'Not for this account' : 'Offer your service by the hour',
        icon: Icons.home_repair_service_outlined,
        color: const Color(0xFFD97706),
        enabled: role != VendorAccountRole.vendor,
        onTap: role == VendorAccountRole.vendor ? () => _explain(context, 'Services', servicesBlocked) : onServices,
      ),
      _Option(
        key: 'transport',
        title: 'Transport',
        subtitle: 'Coming soon',
        icon: Icons.local_shipping_outlined,
        color: const Color(0xFF0F766E),
        enabled: true,
        onTap: onTransport,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendor studio'),
        actions: [if (onLogout != null) IconButton(tooltip: 'Log out', onPressed: onLogout, icon: const Icon(Icons.logout))],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('What would you like to do?', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                for (final option in options) Padding(padding: const EdgeInsets.only(bottom: 14), child: option),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  _Option({required String key, required this.title, required this.subtitle, required this.icon, required this.color, required this.enabled, required this.onTap})
    : super(key: ValueKey('vendor-home-$key'));
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: enabled ? color : color.withValues(alpha: .45),
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Row(
          children: [
            Icon(icon, size: 48, color: Colors.white),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.white, fontSize: 15)),
                ],
              ),
            ),
            Icon(enabled ? Icons.chevron_right : Icons.block, color: Colors.white),
          ],
        ),
      ),
    ),
  );
}

/// Services until service-provider registration is added (next part of this work): says it is on its way.
class ServiceProviderComingPage extends StatelessWidget {
  const ServiceProviderComingPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Services')),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Service-provider registration opens here soon.',
          key: ValueKey('services-coming'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}
