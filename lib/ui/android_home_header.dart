import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/localization.dart';
import '../services/strings.dart';
import '../services/usage.dart';
import 'design_tokens.dart';
import 'layout_settings.dart';
import 'responsive_header.dart';

/// The top of the Android home page: one small row, left to right: logo, location (a pin and the town), the search box (with its mic
/// and camera) and a small settings icon. The settings icon opens a menu with what used to sit in the header: Notifications, Wishlist,
/// Shopping bag, Settings (your account), Become a Seller, Office and the language choices. Each does what it did before.
/// No "Welcome" and no tagline. Used only in the Android app (see wireframe_home.dart); the website keeps [ResponsiveHeader].
class AndroidHomeHeader extends StatelessWidget {
  const AndroidHomeHeader({
    super.key,
    required this.store,
    required this.search,
    required this.onSearch,
    required this.onLocation,
    required this.onAccount,
    required this.onCart,
    required this.onAssistedSearch,
    required this.onProduct,
    this.edgePadding = 6,
  });
  final Store store;
  final TextEditingController search;
  final VoidCallback onSearch, onLocation, onAccount, onCart;
  final ValueChanged<bool> onAssistedSearch;
  final ValueChanged<Entry> onProduct;
  final double edgePadding;

  /// The town, else the address, else the pincode; empty when no location is chosen yet (the pin alone is shown).
  String get place => store.town.isNotEmpty ? store.town : store.address.isNotEmpty ? store.address : store.pincode;

  @override
  Widget build(BuildContext context) {
    final settings = store.entries('settings');
    final logo = layoutFor(context, settings, 'logo');
    final logoUrl = logo.entry.text('iconUrl').isNotEmpty ? logo.entry.text('iconUrl') : store.business.text('imageUrl');
    final searchLayout = layoutFor(context, settings, 'search');
    // The search box as the header has it, only slimmer and using all the room the row leaves it.
    final slim = ComponentLayout(
      Entry(searchLayout.entry.id, {...searchLayout.entry.data, 'width': 0, 'mobileWidth': 0, 'tabletWidth': 0, 'minWidth': 0, 'margin': 0, 'padding': 0, 'height': 44, 'minHeight': 0, 'gap': 0}),
      searchLayout.viewport,
    );
    // Wishlist, the seller page and the office dialog are the same ones the website header opens.
    final base = ResponsiveHeader(
      store: store,
      search: search,
      onSearch: onSearch,
      onLocation: onLocation,
      onServices: () {},
      onAccount: onAccount,
      onCart: onCart,
      onAssistedSearch: onAssistedSearch,
      onProduct: onProduct,
    );
    final label = place;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        key: const ValueKey('android-header'),
        padding: EdgeInsets.symmetric(horizontal: edgePadding, vertical: 2),
        child: Row(
          children: [
            Semantics(
              label: 'App logo',
              child: SizedBox(
                height: 32,
                width: logoUrl.isEmpty ? 28 : 72,
                child: logoUrl.isEmpty
                    ? Icon(Icons.storefront_rounded, size: 26, color: Theme.of(context).colorScheme.primary)
                    : Image.network(logoUrl, fit: BoxFit.contain, alignment: Alignment.centerLeft, errorBuilder: (_, error, stack) => const Icon(Icons.storefront_rounded, size: 26)),
              ),
            ),
            const SizedBox(width: 2),
            InkWell(
              key: const ValueKey('android-location'),
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Usage.button('header_location');
                onLocation();
              },
              child: Semantics(
                label: 'Choose your location'.tr(context),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 84, minHeight: 40),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on, size: 20, color: AppTokens.primary),
                        if (label.isNotEmpty) Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: ResponsiveSearchBox(layout: slim, controller: search, onChanged: onSearch, onAssistedSearch: onAssistedSearch),
            ),
            PopupMenuButton<String>(
              key: const ValueKey('android-settings-menu'),
              tooltip: 'Settings'.tr(context),
              padding: EdgeInsets.zero,
              icon: Badge(isLabelVisible: store.count > 0, label: Text('${store.count}'), child: const Icon(Icons.settings_outlined, size: 22)),
              onSelected: (value) async {
                switch (value) {
                  case 'notifications':
                    Usage.button('header_notifications');
                    onAccount();
                  case 'wishlist':
                    Usage.button('header_wishlist');
                    await base.wishlist(context);
                  case 'bag':
                    Usage.button('header_cart');
                    onCart();
                  case 'settings':
                    onAccount();
                  case 'seller':
                    await base.becomeASeller(context);
                  case 'office':
                    await base.office(context);
                  default:
                    if (context.mounted) await store.setLanguage(value);
                }
              },
              itemBuilder: (_) => [
                _item('notifications', Icons.notifications_outlined, 'Notifications'.tr(context)),
                _item('wishlist', Icons.favorite_border, 'Wishlist'.tr(context)),
                _item('bag', Icons.shopping_bag_outlined, 'Shopping bag'.tr(context) + (store.count > 0 ? ' (${store.count})' : '')),
                _item('settings', Icons.person_outline, 'Your account'.tr(context)),
                _item('seller', Icons.add_business_outlined, 'Become a Seller'.tr(context)),
                _item('office', Icons.store_mall_directory_outlined, 'Office / Head Office'.tr(context)),
                const PopupMenuDivider(),
                for (final locale in AppLocale.enabled(store.business.text('enabledLanguages'))) PopupMenuItem(value: locale.languageCode, child: Text(AppLocale.names[locale.languageCode]!)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _item(String value, IconData icon, String text) => PopupMenuItem(
    value: value,
    child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 10), Flexible(child: Text(text, overflow: TextOverflow.ellipsis))]),
  );
}
