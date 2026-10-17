import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/localization.dart';
import '../services/strings.dart';
import 'contact_actions.dart';
import 'design_tokens.dart';
import 'layout_settings.dart';
import 'responsive_search_box.dart';
import 'shared.dart';

/// Single-row header (logo+tagline, search, location, greeting, wishlist,
/// cart, menu) matching the reference design — wraps onto additional lines
/// at narrow widths via the outer Wrap rather than a fixed two-row split.
class ResponsiveHeader extends StatelessWidget {
  const ResponsiveHeader({
    super.key,
    required this.store,
    required this.search,
    required this.onSearch,
    required this.onLocation,
    required this.onServices,
    required this.onAccount,
    required this.onCart,
    required this.onAssistedSearch,
    required this.onProduct,
  });
  final Store store;
  final TextEditingController search;
  final VoidCallback onSearch, onLocation, onServices, onAccount, onCart;
  final ValueChanged<bool> onAssistedSearch;
  final ValueChanged<Entry> onProduct;

  Future<void> wishlist(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text('Wishlist'.tr(dialog)),
      content: SizedBox(
        width: 320,
        child: store.wishlist.isEmpty
            ? Text('Nothing saved yet.'.tr(dialog))
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final id in store.wishlist)
                    if (store.product(id) case final entry?)
                      ListTile(
                        title: Text(entry.text('name')),
                        subtitle: Text(money(entry.price(store.pincode))),
                        onTap: () {
                          Navigator.pop(dialog);
                          onProduct(entry);
                        },
                      ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: Text('Close'.tr(dialog)),
        ),
      ],
    ),
  );

  Future<void> office(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text('Office / Head Office'.tr(dialog)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(store.business.text('address')),
            if (store.business.text('description').isNotEmpty)
              Text(store.business.text('description')),
            const SizedBox(height: 16),
            SelectableText(store.business.text('phone')),
            if (store.business.text('supportEmail').isNotEmpty)
              SelectableText(store.business.text('supportEmail')),
            if (store.business.text('websiteUrl').isNotEmpty)
              SelectableText(store.business.text('websiteUrl')),
            ContactActions(
              phone: store.business.text('phone'),
              whatsapp: store.business.text('whatsapp'),
              email: store.business.text('supportEmail'),
              website: store.business.text('websiteUrl'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: Text('Close'.tr(dialog)),
        ),
      ],
    ),
  );

  // Vendor onboarding is a genuinely separate Flutter app/Hosting site (see
  // lib/main_vendor.dart) — it is never bundled into this customer build.
  // "Become a Seller" simply opens that site in a new tab, exactly like any
  // other external link (ContactActions below does the same for phone/email/
  // website), so the two apps stay fully independent and nothing here needs
  // to know about vendor registration internals.
  Future<void> becomeASeller(BuildContext context) async {
    final url = store.business.text(
      'vendorSignupUrl',
      'https://e-commerce-app-a3897-vendor.web.app',
    );
    try {
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication) &&
          context.mounted) {
        message(context, 'Could not open the seller signup page');
      }
    } catch (e) {
      if (context.mounted) message(context, 'Could not open the seller signup page');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = store.entries('settings');
    final header = layoutFor(context, settings, 'header');
    final logo = layoutFor(context, settings, 'logo');
    return LayoutSection(
      layout: header,
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 900;
          return Directionality(
            // Keep the logo at the physical top-left in every language.
            textDirection: TextDirection.ltr,
            child: Wrap(
              spacing: header.gap,
              runSpacing: header.gap,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Logo icon/image + "Locamarket" wordmark + tagline, matching
                // the reference design's header lockup.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      label: 'App logo',
                      child: SizedBox(
                        height: logo.height(44, floor: 32),
                        width: logo.height(44, floor: 32),
                        child: store.business.text('imageUrl').isEmpty
                            ? Icon(
                                Icons.storefront_rounded,
                                size: logo.n('iconSize', 40, 24, 96),
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : Image.network(
                                store.business.text('imageUrl'),
                                fit: BoxFit.contain,
                                errorBuilder: (_, error, stack) => const Icon(
                                  Icons.storefront_rounded,
                                  size: 40,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            store.business.text('name', 'Locamarket'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          Text(
                            store.business.text('tagline', 'Local Shops • Local People • Better Prices'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: AppTokens.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // User greeting + compact location pill (matches the
                // reference design's "📍 Narsipatnam ▾" style) — same
                // onLocation callback. Grouped together, right after the
                // logo, to match the wireframe's "user name + location"
                // block.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      store.profileName.isEmpty
                          ? 'Welcome'.tr(context)
                          : 'Hello {name}'.tr(context, {'name': store.profileName}),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: AppTokens.primaryLight,
                      borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                        onTap: onLocation,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_on, size: 16, color: AppTokens.primary),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    store.address.isEmpty
                                        ? (store.pincode.isEmpty
                                              ? 'Choose your location'.tr(context)
                                              : store.pincode)
                                        : store.address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                ),
                                const Icon(Icons.keyboard_arrow_down, size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  width: narrow ? c.maxWidth : math.max(260, c.maxWidth * .35),
                  child: ResponsiveSearchBox(
                    layout: layoutFor(context, settings, 'search'),
                    controller: search,
                    onChanged: onSearch,
                    onAssistedSearch: onAssistedSearch,
                  ),
                ),
                // Visible "Services" shortcut (was hamburger-menu-only) —
                // matches the wireframe showing it directly in the header.
                OutlinedButton.icon(
                  onPressed: onServices,
                  icon: const Icon(Icons.home_repair_service_outlined, size: 18),
                  label: Text('Services'.tr(context)),
                ),
                // Visible office address + phone (was hamburger-menu-only,
                // behind "Office / Head Office") — matches the wireframe
                // showing it directly in the header.
                InkWell(
                  borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                  onTap: () => office(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (store.business.text('address').isNotEmpty)
                            Text(
                              store.business.text('address'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: AppTokens.textMuted),
                            ),
                          if (store.business.text('phone').isNotEmpty)
                            Text(
                              store.business.text('phone'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Notifications'.tr(context),
                  onPressed: onAccount,
                  icon: const Icon(Icons.notifications_outlined),
                ),
                IconButton(
                  tooltip: 'Wishlist'.tr(context),
                  onPressed: () => wishlist(context),
                  icon: const Icon(Icons.favorite_border),
                ),
                IconButton(
                  tooltip: 'Shopping bag'.tr(context),
                  onPressed: onCart,
                  icon: Badge(
                    isLabelVisible: store.count > 0,
                    label: Text('${store.count}'),
                    child: const Icon(Icons.shopping_bag_outlined),
                  ),
                ),
                // Everything lower-frequency lives behind one menu icon
                // (matches the reference design's single hamburger icon)
                // instead of each having its own permanently-visible button
                // or box — nothing is removed, just consolidated here.
                PopupMenuButton<String>(
                  tooltip: 'Menu'.tr(context),
                  icon: const Icon(Icons.menu),
                  onSelected: (value) async {
                    switch (value) {
                      case 'account':
                        onAccount();
                      case 'seller':
                        await becomeASeller(context);
                      default:
                        if (context.mounted) await store.setLanguage(value);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'account',
                      child: Row(children: [
                        const Icon(Icons.person_outline, size: 18),
                        const SizedBox(width: 10),
                        Text('Your account'.tr(context)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'seller',
                      child: Row(children: [
                        const Icon(Icons.add_business_outlined, size: 18),
                        const SizedBox(width: 10),
                        Text('Become a Seller'.tr(context)),
                      ]),
                    ),
                    const PopupMenuDivider(),
                    for (final locale in AppLocale.enabled(store.business.text('enabledLanguages')))
                      PopupMenuItem(
                        value: locale.languageCode,
                        child: Text(AppLocale.names[locale.languageCode]!),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
