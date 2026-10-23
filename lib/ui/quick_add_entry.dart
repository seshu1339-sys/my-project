import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/quick_items.dart';
import 'quick_add_core.dart';
import 'quick_add_shop.dart';
import 'quick_add_items.dart';

/// True when [uid] has a Quick Add account (any status): the vendor and staff apps then show
/// Quick Add even if the person has no vendor application / field-staff record.
class QuickAccountGate extends StatelessWidget {
  const QuickAccountGate({super.key, required this.store, required this.role, required this.otherwise, required this.quickOnly});
  final Store store;
  final String role;
  // Shown when there is no Quick Add account of this role.
  final Widget Function() otherwise;
  // Shown to a Quick Add account that is not also a regular approved vendor / active staff.
  final Widget Function() quickOnly;
  @override
  Widget build(BuildContext context) {
    final uid = store.user?.uid;
    if (uid == null) return otherwise();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('quickAccounts').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (data != null && data['role'] == role) return quickOnly();
        return otherwise();
      },
    );
  }
}

/// A Quick Add account's whole screen when it has no regular vendor/staff access.
class QuickAddOnly extends StatelessWidget {
  const QuickAddOnly({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Welcome', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text('Add the day’s items in a few taps. The admin approves each item before customers see it.'),
      QuickAddHome(store: store),
    ],
  );
}

/// The signed-in Staff/Vendor's Quick Add record, or the reason they cannot use it.
class QuickAddHome extends StatelessWidget {
  const QuickAddHome({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    final uid = store.user?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('quickAccounts').doc(uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          // Not a Quick Add account (or still loading): show nothing, the rest of the app is unchanged.
          return const SizedBox.shrink();
        }
        final account = Entry(uid, snapshot.data!.data()!);
        // How many items were added today (the limit counts a day in India time).
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: store.firestore
              .collection('quickItems')
              .where('ownerUid', isEqualTo: uid)
              .where('dayKey', isEqualTo: quickDayKey(DateTime.now()))
              .snapshots(),
          builder: (context, today) => QuickAddPanel(
            store: store,
            account: account,
            usedToday: today.data?.size,
            dailyLimit: quickDailyLimit(account.text('role'), store.business),
          ),
        );
      },
    );
  }
}

class QuickAddPanel extends StatelessWidget {
  const QuickAddPanel({super.key, required this.store, required this.account, this.env = const QuickEnv(), this.usedToday, this.dailyLimit});
  final Store store;
  final Entry account;
  final QuickEnv env;
  // Items added today and the daily limit; null while still loading.
  final int? usedToday, dailyLimit;
  bool get limitReached => usedToday != null && dailyLimit != null && usedToday! >= dailyLimit!;
  bool get active => account.data['active'] == true;
  bool get isVendor => account.text('role') == 'vendor';
  bool get shopLocked => account.data['shopLocked'] == true;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.bolt, size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text('Quick Add Item', style: Theme.of(context).textTheme.titleLarge)),
            Text(account.text('code'), key: const ValueKey('quick-code'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          if (!isVendor)
            const Text('Your town and pincode are found from your location when you take the photo.')
          else if (shopLocked)
            Row(children: [
              const Icon(Icons.lock_outline, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Your shop: ${account.text('locationTown')}, ${account.text('locationDistrict')} • ${account.text('locationPincode')} (locked)',
                  key: const ValueKey('quick-shop-locked'),
                ),
              ),
            ])
          else
            const Text('First set your shop location. Stand at your shop and tap the button below. It is locked for good once saved.'),
          if (usedToday != null && dailyLimit != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                limitReached ? 'Daily limit reached: $usedToday of $dailyLimit items today.' : 'Today: $usedToday of $dailyLimit items added.',
                key: const ValueKey('quick-today'),
                style: TextStyle(fontWeight: FontWeight.w600, color: limitReached ? Colors.red : null),
              ),
            ),
          const SizedBox(height: 12),
          if (!active)
            const Text(
              'Your account is inactive, contact admin.',
              key: ValueKey('quick-inactive'),
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
            )
          else ...[
            if (isVendor && !shopLocked)
              SizedBox(
                height: 64,
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('quick-shop-setup'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => QuickShopSetupPage(store: store, account: account, env: env)),
                  ),
                  icon: const Icon(Icons.my_location, size: 28),
                  label: const Text('Set my shop location', style: TextStyle(fontSize: 20)),
                ),
              )
            else ...[
              SizedBox(
                height: 64,
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('quick-add-button'),
                  onPressed: limitReached ? null : () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => QuickCategoryPage(store: store, account: account, env: env)),
                  ),
                  icon: const Icon(Icons.add_a_photo_outlined, size: 28),
                  label: Text(isVendor ? 'Add items' : 'Add an item', style: const TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 56,
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('quick-my-items-button'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => QuickMyItemsPage(store: store, account: account, env: env)),
                  ),
                  icon: const Icon(Icons.list_alt),
                  label: const Text('My Items', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ],
        ],
      ),
    ),
  );
}
