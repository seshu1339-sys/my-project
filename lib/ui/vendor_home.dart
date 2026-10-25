import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../modules/transport/transport_module.dart';
import 'provider_page.dart';
import 'vendor_page.dart';

/// What a signed-in account of the vendor app is. Vendor, service-provider and field-staff accounts are completely separate: one login
/// is only ever one of them. A person who wants more than one registers each with a different email address.
enum VendorAccountRole { none, vendor, provider, staff }

/// The account's role from its records: a vendor application or vendor record (or an admin-made Quick Add vendor account) makes it a
/// vendor account; a service-provider application makes it a provider account. Neither yet: it may become either.
VendorAccountRole vendorAccountRole({
  Map<String, dynamic>? vendorApplication,
  Map<String, dynamic>? vendor,
  Map<String, dynamic>? quickAccount,
  Map<String, dynamic>? providerApplication,
  Map<String, dynamic>? staff,
}) {
  if (vendorApplication != null || vendor != null || quickAccount?['role'] == 'vendor') return VendorAccountRole.vendor;
  if (providerApplication != null) return VendorAccountRole.provider;
  if (staff != null || quickAccount?['role'] == 'staff') return VendorAccountRole.staff;
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
    onServices: () => _open(context, ServiceProviderPage(store: store)),
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
          builder: (context, quick) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: doc('providerApplications').snapshots(),
            builder: (context, provider) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: doc('fieldStaff').snapshots(),
              builder: (context, staff) => _view(
                context,
                vendorAccountRole(
                  vendorApplication: application.data?.data(),
                  vendor: vendor.data?.data(),
                  quickAccount: quick.data?.data(),
                  providerApplication: provider.data?.data(),
                  staff: staff.data?.data(),
                ),
              ),
            ),
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
  static const staffBlocked =
      'This account is a field-staff account. Vendor and service-provider accounts must be separate accounts: sign out and register with a different email address.';

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
        subtitle: role == VendorAccountRole.provider || role == VendorAccountRole.staff ? 'Not for this account' : 'Sell your shop\'s items',
        icon: Icons.storefront_outlined,
        color: const Color(0xff8c4a22),
        enabled: role != VendorAccountRole.provider && role != VendorAccountRole.staff,
        onTap: role == VendorAccountRole.provider
            ? () => _explain(context, 'Vendor', vendorBlocked)
            : role == VendorAccountRole.staff
            ? () => _explain(context, 'Vendor', staffBlocked)
            : onVendor,
      ),
      _Option(
        key: 'services',
        title: 'Services',
        subtitle: role == VendorAccountRole.vendor || role == VendorAccountRole.staff ? 'Not for this account' : 'Offer your service by the hour',
        icon: Icons.home_repair_service_outlined,
        color: const Color(0xFFD97706),
        enabled: role != VendorAccountRole.vendor && role != VendorAccountRole.staff,
        onTap: role == VendorAccountRole.vendor
            ? () => _explain(context, 'Services', servicesBlocked)
            : role == VendorAccountRole.staff
            ? () => _explain(context, 'Services', staffBlocked)
            : onServices,
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
