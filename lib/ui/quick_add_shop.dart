import 'dart:async';
import 'package:flutter/material.dart';
import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/places.dart';
import 'quick_add_core.dart';
import 'quick_add_item.dart';
import 'quick_add_batch.dart';

/// Vendor, once: GPS at the shop -> the nearest town and pincode from the pincode directory -> locked.
class QuickShopSetupPage extends StatefulWidget {
  const QuickShopSetupPage({super.key, required this.store, required this.account, this.env = const QuickEnv()});
  final Store store;
  final Entry account;
  final QuickEnv env;
  @override
  State<QuickShopSetupPage> createState() => _QuickShopSetupPageState();
}

class _QuickShopSetupPageState extends State<QuickShopSetupPage> {
  QuickFix? fix;
  Place? place;
  String error = '';
  bool busy = false;

  Future<void> _find() async {
    setState(() {
      busy = true;
      error = '';
      place = null;
    });
    try {
      final found = await widget.env.fix();
      final nearest = await widget.env.place(found.latitude, found.longitude);
      if (!mounted) return;
      setState(() {
        fix = found;
        place = nearest;
        if (nearest == null) error = 'Your location is outside Andhra Pradesh and Telangana, so a town could not be found.';
      });
    } catch (e) {
      if (mounted) setState(() => error = quickCleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _lock() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.env.run(widget.store, 'setQuickShopLocation', {'latitude': fix!.latitude, 'longitude': fix!.longitude});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your shop location is saved and locked.')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = quickCleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Set my shop location')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Stand inside your shop and turn on GPS. We find your town and pincode from your location.', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 16),
        SizedBox(
          height: 60,
          child: FilledButton.icon(
            key: const ValueKey('quick-find-shop'),
            onPressed: busy ? null : _find,
            icon: const Icon(Icons.my_location),
            label: Text(fix == null ? 'Find my shop' : 'Find again', style: const TextStyle(fontSize: 18)),
          ),
        ),
        if (busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(error, key: const ValueKey('quick-shop-error'), style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
          ),
        if (place != null) ...[
          const SizedBox(height: 16),
          Card(
            key: const ValueKey('quick-shop-found'),
            child: ListTile(
              leading: const Icon(Icons.storefront, size: 32),
              title: Text('${place!.town}, ${place!.district}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              subtitle: Text('${place!.state} • Pincode ${place!.pincode}'),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Once you save this it is locked. You cannot change it yourself later; only the admin can.', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            child: FilledButton(
              key: const ValueKey('quick-lock-shop'),
              onPressed: busy ? null : _lock,
              child: const Text('Save and lock my shop location', style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Step 1: the categories as big buttons.
class QuickCategoryPage extends StatelessWidget {
  const QuickCategoryPage({super.key, required this.store, required this.account, this.env = const QuickEnv()});
  final Store store;
  final Entry account;
  final QuickEnv env;

  @override
  Widget build(BuildContext context) {
    final categories = store.visible('categories').where((c) => c.text('parentId').isEmpty).toList();
    final isVendor = account.text('role') == 'vendor';
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a category')),
      body: GridView.count(
        padding: const EdgeInsets.all(12),
        crossAxisCount: MediaQuery.sizeOf(context).width >= 600 ? 4 : 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: [
          for (final category in categories)
            FilledButton.tonal(
              key: ValueKey('quick-category-${category.id}'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => isVendor
                      ? QuickBatchFormPage(store: store, account: account, category: category, env: env)
                      : QuickItemFormPage(store: store, account: account, category: category, env: env),
                ),
              ),
              child: Text(category.text('name', category.id), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
