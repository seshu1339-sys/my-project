import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../modules/flash/flash_module.dart' show vendorAppFlashButton;

import '../data/store.dart';
import '../modules/transport/transport_module.dart';
import 'big_option_tile.dart';
import 'provider_page.dart';
import 'vendor_page.dart';
import 'screen_view.dart';
import '../services/usage.dart';

/// The words for the vendor app's two logins of one email.
String vendorRoleName(String role) => role == 'provider' ? 'Service provider' : 'Vendor';

/// The vendor app's home after sign-in: Vendor, Services and Transport. One email has a separate login as a vendor and as a service
/// provider (functions/role-logins.js), each with its own ID, records and approval; the app is signed in as one of them at a time, and
/// Vendor / Services move to the other one (the Switch button too).
class VendorHomePage extends StatelessWidget {
  const VendorHomePage({super.key, required this.store});
  final Store store;

  void _open(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  /// Moves to the email's [role] login (when signed in as the other one). False, after saying why, when that login is blocked.
  Future<bool> _switchTo(BuildContext context, String role) async {
    if (!store.live || store.sessionRole == role) return true;
    try {
      await store.switchVendorRole(role);
      return true;
    } catch (e) {
      if (context.mounted) {
        final text = e is FirebaseFunctionsException ? (e.message ?? 'Could not switch. Please try again.') : 'Could not switch. Check your connection and try again.';
        await showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(vendorRoleName(role)),
            content: Text(text),
            actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('OK'))],
          ),
        );
      }
      return false;
    }
  }

  Future<void> _openAs(BuildContext context, String role, Widget Function() page) async {
    if (!await _switchTo(context, role)) return;
    if (context.mounted) _open(context, page());
  }

  @override
  Widget build(BuildContext context) => ScreenView(
    'vendor_home',
    child: VendorHomeView(
      signedInAs: store.live ? store.sessionRole : '',
      email: store.live ? store.signedInEmail : '',
      chatButton: store.live ? vendorAppFlashButton(store) : null,
      onVendor: () {
        Usage.button('vendor_home_vendor');
        _openAs(context, 'vendor', () => VendorPage(store: store));
      },
      onServices: () {
        Usage.button('vendor_home_services');
        _openAs(context, 'provider', () => ServiceProviderPage(store: store));
      },
      onTransport: () {
        Usage.button('vendor_home_transport');
        openTransport(context, store);
      },
      onSwitch: store.live ? (to) => _switchTo(context, to) : null,
      onLogout: store.live ? store.logout : null,
    ),
  );
}

/// The three options, laid out for any screen width, with which login the app is signed in as and a Switch button.
class VendorHomeView extends StatelessWidget {
  const VendorHomeView({
    super.key,
    this.signedInAs = '',
    this.email = '',
    required this.onVendor,
    required this.onServices,
    required this.onTransport,
    this.onSwitch,
    this.onLogout,
    this.chatButton,
  });

  /// 'vendor' or 'provider': the login the app is signed in as ('' in the demo).
  final String signedInAs;
  final String email;
  final VoidCallback onVendor, onServices, onTransport;
  final void Function(String to)? onSwitch;
  final VoidCallback? onLogout;
  // The floating Help chat button (lib/modules/flash).
  final Widget? chatButton;

  @override
  Widget build(BuildContext context) {
    final asProvider = signedInAs == 'provider', asVendor = signedInAs == 'vendor';
    final other = asProvider ? 'vendor' : 'provider';
    final options = [
      _Option(
        key: 'vendor',
        title: 'Vendor',
        subtitle: asProvider ? 'Switch to your vendor account' : 'Sell your shop\'s items',
        icon: Icons.storefront_outlined,
        color: const Color(0xff8c4a22),
        onTap: onVendor,
      ),
      _Option(
        key: 'services',
        title: 'Services',
        subtitle: asVendor ? 'Switch to your service-provider account' : 'Offer your service by the hour',
        icon: Icons.home_repair_service_outlined,
        color: const Color(0xFFD97706),
        onTap: onServices,
      ),
      _Option(
        key: 'transport',
        title: 'Transport',
        subtitle: 'Coming soon',
        icon: Icons.local_shipping_outlined,
        color: const Color(0xFF0F766E),
        onTap: onTransport,
      ),
    ];
    return Scaffold(
      floatingActionButton: chatButton,
      appBar: AppBar(
        title: const Text('Loca Market Vendor'),
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
                if (signedInAs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          'Signed in as ${vendorRoleName(signedInAs)}${email.isEmpty ? '' : ' ($email)'}',
                          key: const ValueKey('vendor-signed-in-as'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (onSwitch != null)
                          OutlinedButton.icon(
                            key: const ValueKey('vendor-switch-role'),
                            onPressed: () => onSwitch!(other),
                            icon: const Icon(Icons.swap_horiz),
                            label: Text('Switch to ${vendorRoleName(other)}'),
                          ),
                      ],
                    ),
                  ),
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

/// After the first sign-in in the vendor app: "Vendor or Service provider?". The answer is remembered on this phone, and the home
/// screen switches later. A login that is blocked says so here; the other one still works.
class VendorRoleChooser extends StatefulWidget {
  const VendorRoleChooser({super.key, required this.store});
  final Store store;
  @override
  State<VendorRoleChooser> createState() => _VendorRoleChooserState();
}

class _VendorRoleChooserState extends State<VendorRoleChooser> {
  bool busy = false;

  Future<void> _choose(String role) async {
    setState(() => busy = true);
    try {
      await widget.store.chooseVendorRole(role);
    } catch (_) {
      /* store.roleBlock says why; it is shown below. */
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    Widget option(String role, String subtitle, IconData icon, Color color) {
      final blocked = store.blockedRole == role;
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: BigOptionTile(
          key: ValueKey('choose-$role'),
          title: vendorRoleName(role),
          subtitle: blocked ? 'This account is blocked' : subtitle,
          icon: icon,
          color: color,
          enabled: !blocked,
          onTap: busy ? () {} : () => _choose(role),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Continue as', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Your vendor account and your service-provider account are separate, each with its own ID and approval. You can switch at any time.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        option('vendor', 'Sell your shop\'s items', Icons.storefront_outlined, const Color(0xff8c4a22)),
        option('provider', 'Offer your service by the hour', Icons.home_repair_service_outlined, const Color(0xFFD97706)),
        if (store.roleBlock != null)
          Text(store.roleBlock!, key: const ValueKey('role-block'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        TextButton(onPressed: busy ? null : store.logout, child: const Text('Use another email')),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  _Option({required String key, required this.title, required this.subtitle, required this.icon, required this.color, required this.onTap})
    : super(key: ValueKey('vendor-home-$key'));
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => BigOptionTile(title: title, subtitle: subtitle, icon: icon, color: color, onTap: onTap);
}
