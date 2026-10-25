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

Widget _identityHeaderSection(String key, Widget child) => child;

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
    this.wrapSection = _identityHeaderSection,
    this.edgePadding = 0,
  });
  // The page's side padding, applied INSIDE the header so the header's own
  // line/background runs edge to edge while its content keeps the page margin.
  final double edgePadding;
  final Store store;
  final TextEditingController search;
  final VoidCallback onSearch, onLocation, onServices, onAccount, onCart;
  final ValueChanged<bool> onAssistedSearch;
  final ValueChanged<Entry> onProduct;
  // Lets the admin Visual Editor overlay click-to-select/number-badge
  // behavior onto each individual header element (logo, title, tagline,
  // greeting, location pill, search box, services icon, the 4 header
  // icons, office) without this widget knowing anything about editing --
  // every real customer render (the only caller that omits this) gets this
  // exact no-op and therefore byte-identical output to before this existed.
  final Widget Function(String sectionKey, Widget child) wrapSection;

  Future<void> wishlist(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialog) {
      final titleLayout = layoutFor(
        dialog,
        store.entries('settings'),
        'wishlistDialogTitle',
      );
      return AlertDialog(
        title: Text(
          titleLayout.entry.text('text', 'Wishlist').tr(dialog),
          style: overrideTextStyle(titleLayout.entry),
        ),
        content: SizedBox(
          width: 320,
          child: store.wishlist.isEmpty
              ? Text('Nothing saved yet.'.tr(dialog))
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final id in store.wishlist)
                      if (store.item(id) case final entry?)
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
      );
    },
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
      if (!await launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          ) &&
          context.mounted) {
        message(context, 'Could not open the seller signup page');
      }
    } catch (e) {
      if (context.mounted)
        message(context, 'Could not open the seller signup page');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = store.entries('settings');
    final header = layoutFor(context, settings, 'header');
    final logo = layoutFor(context, settings, 'logo');
    // An uploaded logo (Business profile > Upload logo) takes the place of the icon + name text: it is shown wider, on its own.
    final hasLogoImage = (logo.entry.text('iconUrl').isNotEmpty ? logo.entry.text('iconUrl') : store.business.text('imageUrl')).isNotEmpty;
    // Three previously-hardcoded header pieces, each now independently
    // admin-editable (text/color/font/size/visibility) — see layout_settings.dart's
    // 'title'/'user'/'location' entries. Every field below falls back to
    // exactly the prior hardcoded value when unset, so the header's default
    // appearance is unchanged until an admin actually sets something.
    final title = layoutFor(context, settings, 'title');
    final tagline = layoutFor(context, settings, 'tagline');
    final greeting = layoutFor(context, settings, 'user');
    final locationLayout = layoutFor(context, settings, 'location');
    final notificationLayout = layoutFor(context, settings, 'notificationIcon');
    final wishlistLayout = layoutFor(context, settings, 'wishlistIcon');
    final cartLayout = layoutFor(context, settings, 'cartIcon');
    final menuLayout = layoutFor(context, settings, 'menuIcon');
    final officeLayout = layoutFor(context, settings, 'office');
    // What the admin types in Business profile > "Header contact box" (address, phone, email, anything) wins over the older layout text.
    final contactText = store.business.text('headerContact').trim().isNotEmpty ? store.business.text('headerContact').trim() : officeLayout.entry.text('text');
    return LayoutSection(
      layout: header,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: edgePadding,
          vertical: edgePadding / 2,
        ),
        child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 900;
          // Thin vertical separators between header sections, matching the
          // wireframe's divider lines (APP LOGO | USER NAME/LOCATION |
          // SEARCH | SERVICES | OFFICE ADDRESS). Hidden once the Wrap
          // starts stacking items onto their own lines at narrow widths,
          // where a floating divider line would look broken rather than
          // separating anything.
          Widget divider() => narrow
              ? const SizedBox.shrink()
              : Container(
                  width: 1.5,
                  height: 32,
                  color: AppTokens.textMuted.withValues(alpha: .25),
                );
          return Directionality(
            // Keep the logo at the physical top-left in every language.
            textDirection: TextDirection.ltr,
            child: _headerRow(
              narrow: narrow,
              spacing: header.gap,
              runSpacing: header.gap,
              children: [
                // Logo icon/image + "Locamarket" wordmark + tagline, matching
                // the reference design's header lockup.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    wrapSection(
                      'logo',
                      Semantics(
                        label: 'App logo',
                        child: SizedBox(
                          height: hasLogoImage ? logo.height(44, floor: 36) : logo.height(36, floor: 28),
                          width: hasLogoImage ? 150 : logo.height(36, floor: 28),
                          child: (logo.entry.text('iconUrl').isNotEmpty
                                      ? logo.entry.text('iconUrl')
                                      : store.business.text('imageUrl'))
                                  .isEmpty
                              ? Icon(
                                  Icons.storefront_rounded,
                                  size: logo.n('iconSize', 32, 20, 96),
                                  color: logo.entry.text('textColor').isEmpty
                                      ? Theme.of(context).colorScheme.primary
                                      : colorFromHex(
                                          logo.entry.text('textColor'),
                                          Theme.of(context).colorScheme.primary,
                                        ),
                                )
                              : Image.network(
                                  logo.entry.text('iconUrl').isNotEmpty
                                      ? logo.entry.text('iconUrl')
                                      : store.business.text('imageUrl'),
                                  fit: BoxFit.contain,
                                  alignment: Alignment.centerLeft,
                                  errorBuilder: (_, error, stack) => const Icon(
                                    Icons.storefront_rounded,
                                    size: 32,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    if (!hasLogoImage) const SizedBox(width: 6),
                    if (!hasLogoImage) ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (title.visible)
                            wrapSection(
                              'title',
                              Text(
                                title.entry.text(
                                  'text',
                                  store.business.text('name', 'Locamarket'),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    sectionTextStyle(
                                      title.entry,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ).copyWith(
                                      color:
                                          title.entry.text('textColor').isEmpty
                                          ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                          : colorFromHex(
                                              title.entry.text('textColor'),
                                              Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                    ),
                              ),
                            ),
                          if (tagline.visible)
                            wrapSection(
                              'tagline',
                              Text(
                                tagline.entry.text(
                                  'text',
                                  store.business.text(
                                    'tagline',
                                    'Local Shops • Local People • Better Prices',
                                  ),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    sectionTextStyle(
                                      tagline.entry,
                                      fontSize: 10,
                                      fontWeight: FontWeight.normal,
                                    ).copyWith(
                                      color:
                                          tagline.entry
                                              .text('textColor')
                                              .isEmpty
                                          ? AppTokens.textMuted
                                          : colorFromHex(
                                              tagline.entry.text('textColor'),
                                              AppTokens.textMuted,
                                            ),
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                divider(),
                // User greeting + compact location pill (matches the
                // reference design's "📍 Narsipatnam ▾" style) — same
                // onLocation callback. Two separate Wrap children (not one
                // nested Row) right after the logo, to match the
                // wireframe's "user name + location" block — a Row here
                // would measure both at their natural width ignoring the
                // Wrap's own bound and can overflow at narrow widths; as
                // separate Wrap children, the pill simply flows to its own
                // line when there's no room instead.
                if (greeting.visible)
                  wrapSection(
                    'user',
                    Text(
                      store.profileName.isEmpty
                          ? greeting.entry.text('text', 'Welcome').tr(context)
                          : 'Hello {name}'.tr(context, {
                              'name': store.profileName,
                            }),
                      style: applyFontFamily(
                        TextStyle(
                          fontWeight: FontWeight.values.firstWhere(
                            (w) =>
                                w.value ==
                                greeting.entry.number('fontWeight', 700),
                            orElse: () => FontWeight.w700,
                          ),
                          fontSize: greeting.entry.number('fontSize') > 0
                              ? clampedNumber(
                                  greeting.entry,
                                  'fontSize',
                                  14,
                                  10,
                                  40,
                                )
                              : null,
                          color: greeting.entry.text('textColor').isEmpty
                              ? null
                              : colorFromHex(
                                  greeting.entry.text('textColor'),
                                  Colors.black87,
                                ),
                          fontStyle:
                              greeting.entry.text('fontStyle') == 'italic'
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                        greeting.entry.text('fontFamily'),
                      ),
                    ),
                  ),
                if (locationLayout.visible)
                  wrapSection(
                    'location',
                    Material(
                      color:
                          locationLayout.entry.text('backgroundColor').isEmpty
                          ? AppTokens.primaryLight
                          : colorFromHex(
                              locationLayout.entry.text('backgroundColor'),
                              AppTokens.primaryLight,
                            ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          locationLayout.entry.number('radius') > 0
                              ? clampedNumber(
                                  locationLayout.entry,
                                  'radius',
                                  AppTokens.radiusLg,
                                  0,
                                  80,
                                )
                              : AppTokens.radiusLg,
                        ),
                        side: locationLayout.entry.text('borderColor').isEmpty
                            ? BorderSide.none
                            : BorderSide(
                                color: colorFromHex(
                                  locationLayout.entry.text('borderColor'),
                                  AppTokens.primary,
                                ),
                                width: 1.5,
                              ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          locationLayout.entry.number('radius') > 0
                              ? clampedNumber(
                                  locationLayout.entry,
                                  'radius',
                                  AppTokens.radiusLg,
                                  0,
                                  80,
                                )
                              : AppTokens.radiusLg,
                        ),
                        onTap: onLocation,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  size: 16,
                                  color: AppTokens.primary,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    store.address.isEmpty
                                        ? (store.pincode.isEmpty
                                              ? locationLayout.entry
                                                    .text(
                                                      'text',
                                                      'Choose your location',
                                                    )
                                                    .tr(context)
                                              : store.pincode)
                                        : store.address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: applyFontFamily(
                                      TextStyle(
                                        fontWeight: FontWeight.values
                                            .firstWhere(
                                              (w) =>
                                                  w.value ==
                                                  locationLayout.entry.number(
                                                    'fontWeight',
                                                    600,
                                                  ),
                                              orElse: () => FontWeight.w600,
                                            ),
                                        fontSize:
                                            locationLayout.entry.number(
                                                  'fontSize',
                                                ) >
                                                0
                                            ? clampedNumber(
                                                locationLayout.entry,
                                                'fontSize',
                                                13,
                                                10,
                                                40,
                                              )
                                            : 13,
                                        color:
                                            locationLayout.entry
                                                .text('textColor')
                                                .isEmpty
                                            ? null
                                            : colorFromHex(
                                                locationLayout.entry.text(
                                                  'textColor',
                                                ),
                                                Colors.black87,
                                              ),
                                        fontStyle:
                                            locationLayout.entry.text(
                                                  'fontStyle',
                                                ) ==
                                                'italic'
                                            ? FontStyle.italic
                                            : FontStyle.normal,
                                      ),
                                      locationLayout.entry.text('fontFamily'),
                                    ),
                                  ),
                                ),
                                const Icon(Icons.keyboard_arrow_down, size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                divider(),
                wrapSection(
                  'search',
                  SizedBox(
                    width: narrow
                        ? c.maxWidth
                        : math.max(260, c.maxWidth * .35),
                    child: ResponsiveSearchBox(
                      layout: layoutFor(context, settings, 'search'),
                      controller: search,
                      onChanged: onSearch,
                      onAssistedSearch: onAssistedSearch,
                    ),
                  ),
                ),
                divider(),
                if (notificationLayout.visible)
                  wrapSection(
                    'notificationIcon',
                    _headerIconButton(
                      context,
                      layout: notificationLayout,
                      icon: Icons.notifications_outlined,
                      tooltip: 'Notifications'.tr(context),
                      onPressed: onAccount,
                    ),
                  ),
                if (wishlistLayout.visible)
                  wrapSection(
                    'wishlistIcon',
                    _headerIconButton(
                      context,
                      layout: wishlistLayout,
                      icon: Icons.favorite_border,
                      tooltip: 'Wishlist'.tr(context),
                      onPressed: () => wishlist(context),
                    ),
                  ),
                if (cartLayout.visible)
                  wrapSection(
                    'cartIcon',
                    _headerIconButton(
                      context,
                      layout: cartLayout,
                      icon: Icons.shopping_bag_outlined,
                      tooltip: 'Shopping bag'.tr(context),
                      onPressed: onCart,
                      badge: store.count > 0 ? '${store.count}' : null,
                    ),
                  ),
                // Everything lower-frequency lives behind one menu icon
                // (matches the reference design's single hamburger icon)
                // instead of each having its own permanently-visible button
                // or box — nothing is removed, just consolidated here.
                if (menuLayout.visible)
                  wrapSection(
                    'menuIcon',
                    PopupMenuButton<String>(
                      tooltip: 'Menu'.tr(context),
                      icon: menuLayout.entry.text('iconUrl').isEmpty
                          ? Icon(
                              Icons.menu,
                              size: menuLayout.entry.number('iconSize') > 0
                                  ? clampedNumber(
                                      menuLayout.entry,
                                      'iconSize',
                                      24,
                                      16,
                                      48,
                                    )
                                  : 24,
                              color: menuLayout.entry.text('textColor').isEmpty
                                  ? null
                                  : colorFromHex(
                                      menuLayout.entry.text('textColor'),
                                      AppTokens.textPrimary,
                                    ),
                            )
                          : Image.network(
                              menuLayout.entry.text('iconUrl'),
                              width: menuLayout.entry.number('iconSize') > 0
                                  ? clampedNumber(
                                      menuLayout.entry,
                                      'iconSize',
                                      24,
                                      16,
                                      48,
                                    )
                                  : 24,
                              height: menuLayout.entry.number('iconSize') > 0
                                  ? clampedNumber(
                                      menuLayout.entry,
                                      'iconSize',
                                      24,
                                      16,
                                      48,
                                    )
                                  : 24,
                              fit: BoxFit.contain,
                              errorBuilder: (_, error, stack) =>
                                  const Icon(Icons.menu),
                            ),
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
                          child: Row(
                            children: [
                              const Icon(Icons.person_outline, size: 18),
                              const SizedBox(width: 10),
                              Text('Your account'.tr(context)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'seller',
                          child: Row(
                            children: [
                              const Icon(Icons.add_business_outlined, size: 18),
                              const SizedBox(width: 10),
                              Text('Become a Seller'.tr(context)),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        for (final locale in AppLocale.enabled(
                          store.business.text('enabledLanguages'),
                        ))
                          PopupMenuItem(
                            value: locale.languageCode,
                            child: Text(AppLocale.names[locale.languageCode]!),
                          ),
                      ],
                    ),
                  ),
              ],
              // Visible office address + phone (was hamburger-menu-only,
              // behind "Office / Head Office") — kept apart from the rest so
              // on a wide screen it sits at the header's far right corner.
              office: !officeLayout.visible
                  ? null
                  : wrapSection(
                    'office',
                    Material(
                      color: officeLayout.entry.text('backgroundColor').isEmpty
                          ? Colors.transparent
                          : colorFromHex(
                              officeLayout.entry.text('backgroundColor'),
                              Colors.transparent,
                            ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          officeLayout.entry.number('radius') > 0
                              ? clampedNumber(
                                  officeLayout.entry,
                                  'radius',
                                  AppTokens.radiusLg,
                                  0,
                                  80,
                                )
                              : AppTokens.radiusLg,
                        ),
                        side: officeLayout.entry.text('borderColor').isEmpty
                            ? (contactText.isEmpty ? BorderSide.none : BorderSide(color: AppTokens.textMuted.withValues(alpha: .45)))
                            : BorderSide(
                                color: colorFromHex(
                                  officeLayout.entry.text('borderColor'),
                                  AppTokens.primary,
                                ),
                                width: 1.5,
                              ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          officeLayout.entry.number('radius') > 0
                              ? clampedNumber(
                                  officeLayout.entry,
                                  'radius',
                                  AppTokens.radiusLg,
                                  0,
                                  80,
                                )
                              : AppTokens.radiusLg,
                        ),
                        onTap: () => office(context),
                        child: Padding(
                          padding: officeLayout.entry.number('padding') > 0
                              ? EdgeInsets.all(
                                  clampedNumber(
                                    officeLayout.entry,
                                    'padding',
                                    4,
                                    0,
                                    48,
                                  ),
                                )
                              : EdgeInsets.symmetric(
                                  horizontal: contactText.isEmpty ? 4 : 10,
                                  vertical: contactText.isEmpty ? 4 : 6,
                                ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: contactText.isEmpty
                                  ? 220
                                  : 360,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // The admin's own text (Layout Settings -> Office
                                // address & phone) wins and is shown exactly as typed.
                                if (contactText.isNotEmpty)
                                  Text(
                                    contactText,
                                    textAlign: TextAlign.right,
                                    style:
                                        sectionTextStyle(
                                          officeLayout.entry,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ).copyWith(
                                          color:
                                              officeLayout.entry
                                                  .text('textColor')
                                                  .isEmpty
                                              ? null
                                              : colorFromHex(
                                                  officeLayout.entry.text(
                                                    'textColor',
                                                  ),
                                                  Colors.black87,
                                                ),
                                        ),
                                  )
                                else ...[
                                if (store.business.text('address').isNotEmpty)
                                  Text(
                                    store.business.text('address'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        sectionTextStyle(
                                          officeLayout.entry,
                                          fontSize: 11,
                                          fontWeight: FontWeight.normal,
                                        ).copyWith(
                                          color:
                                              officeLayout.entry
                                                  .text('textColor')
                                                  .isEmpty
                                              ? AppTokens.textMuted
                                              : colorFromHex(
                                                  officeLayout.entry.text(
                                                    'textColor',
                                                  ),
                                                  AppTokens.textMuted,
                                                ),
                                        ),
                                  ),
                                if (store.business.text('phone').isNotEmpty)
                                  Text(
                                    store.business.text('phone'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        sectionTextStyle(
                                          officeLayout.entry,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ).copyWith(
                                          color:
                                              officeLayout.entry
                                                  .text('textColor')
                                                  .isEmpty
                                              ? null
                                              : colorFromHex(
                                                  officeLayout.entry.text(
                                                    'textColor',
                                                  ),
                                                  Colors.black87,
                                                ),
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            ),
          );
        },
      ),
      ),
    );
  }
}

/// Lays the header out as one wrapping row. On a wide screen the office
/// address/phone is pinned to the far right corner; on a narrow screen it
/// simply wraps in with the rest.
Widget _headerRow({
  required bool narrow,
  required double spacing,
  required double runSpacing,
  required List<Widget> children,
  Widget? office,
}) {
  if (office == null || narrow) {
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [...children, ?office],
    );
  }
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        ),
      ),
      SizedBox(width: spacing),
      Container(
        width: 1.5,
        height: 32,
        color: AppTokens.textMuted.withValues(alpha: .25),
      ),
      SizedBox(width: spacing),
      office,
    ],
  );
}

/// Shared rendering for the 4 plain header icon buttons (notifications,
/// wishlist, cart, menu is built separately since PopupMenuButton has no
/// `icon:` widget replacement path that fits this helper's shape) — each
/// gets its own icon color/size/replace-image/background, falling back to
/// exactly its prior hardcoded look (default IconButton size, no
/// background, theme icon color) when nothing is set.
Widget _headerIconButton(
  BuildContext context, {
  required ComponentLayout layout,
  required IconData icon,
  required String tooltip,
  required VoidCallback onPressed,
  String? badge,
}) {
  final size = layout.entry.number('iconSize') > 0
      ? clampedNumber(layout.entry, 'iconSize', 24, 16, 48)
      : 24.0;
  final color = layout.entry.text('textColor').isEmpty
      ? null
      : colorFromHex(layout.entry.text('textColor'), AppTokens.textPrimary);
  final iconUrl = layout.entry.text('iconUrl');
  Widget iconWidget = iconUrl.isEmpty
      ? Icon(icon, size: size, color: color)
      : Image.network(
          iconUrl,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, error, stack) =>
              Icon(icon, size: size, color: color),
        );
  if (badge != null) {
    iconWidget = Badge(label: Text(badge), child: iconWidget);
  }
  final button = IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    padding: EdgeInsets.all(
      layout.entry.number('padding') > 0
          ? clampedNumber(layout.entry, 'padding', 8, 0, 48)
          : 8,
    ),
    icon: iconWidget,
  );
  final backgroundColor = layout.entry.text('backgroundColor');
  return backgroundColor.isEmpty
      ? button
      : Material(
          color: colorFromHex(backgroundColor, Colors.transparent),
          shape: const CircleBorder(),
          child: button,
        );
}
