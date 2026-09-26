import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/localization.dart';
import '../services/strings.dart';
import 'layout_settings.dart';
import 'shared.dart';

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
  });
  final Store store;
  final TextEditingController search;
  final VoidCallback onSearch, onLocation, onServices, onAccount, onCart;
  final ValueChanged<bool> onAssistedSearch;

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
            ContactActions(
              phone: store.business.text('phone'),
              whatsapp: store.business.text('whatsapp'),
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

  @override
  Widget build(BuildContext context) {
    final settings = store.entries('settings');
    final header = layoutFor(context, settings, 'header');
    final logo = layoutFor(context, settings, 'logo');
    final user = layoutFor(context, settings, 'user');
    final services = layoutFor(context, settings, 'services');
    final officeLayout = layoutFor(context, settings, 'office');
    return LayoutSection(
      layout: header,
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 700;
          Widget box(
            ComponentLayout layout,
            double defaultWidth,
            Widget child,
          ) => Container(
            width: layout.width(
              c.maxWidth - layout.margin * 2,
              fallback: defaultWidth,
              floor: layout == logo ? 56 : 140,
            ),
            margin: EdgeInsets.all(layout.margin),
            constraints: BoxConstraints(
              minHeight: layout.height(56, floor: 48),
            ),
            padding: EdgeInsets.all(layout.padding.clamp(0, c.maxWidth / 10)),
            decoration: entryDecoration(
              layout.entry,
              fallback: Theme.of(context).colorScheme.surface,
              defaultRadius: 12,
            ),
            child: DefaultTextStyle.merge(
              style: sectionTextStyle(layout.styled(context)),
              child: child,
            ),
          );
          final actions = Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Your account'.tr(context),
                onPressed: onAccount,
                icon: const Icon(Icons.person_outline),
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
              IconButton(
                tooltip: 'Settings'.tr(context),
                onPressed: onAccount,
                icon: const Icon(Icons.settings_outlined),
              ),
              PopupMenuButton<String>(
                tooltip: 'Language'.tr(context),
                icon: const Icon(Icons.language),
                onSelected: (value) async {
                  try {
                    await store.setLanguage(value);
                  } catch (e) {
                    if (context.mounted) message(context, e);
                  }
                },
                itemBuilder: (_) => [
                  for (final locale in AppLocale.enabled(
                    store.business.text('enabledLanguages'),
                  ))
                    PopupMenuItem(
                      value: locale.languageCode,
                      child: Text(AppLocale.names[locale.languageCode]!),
                    ),
                ],
              ),
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Keep the logo at the physical top-left in every language.
              Directionality(
                textDirection: TextDirection.ltr,
                child: Wrap(
                  spacing: header.gap,
                  runSpacing: header.gap,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    box(
                      logo,
                      logo.width(c.maxWidth, fallback: narrow ? 64 : 88),
                      Semantics(
                        label: 'App logo',
                        child: SizedBox(
                          height: logo.height(narrow ? 40 : 54, floor: 32),
                          child: store.business.text('imageUrl').isEmpty
                              ? Icon(
                                  Icons.storefront_rounded,
                                  size: logo.n(
                                    'iconSize',
                                    narrow ? 36 : 48,
                                    24,
                                    96,
                                  ),
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
                    ),
                    box(
                      user,
                      narrow ? math.max(160, c.maxWidth - 110) : 260,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            store.profileName.isEmpty
                                ? 'Welcome'.tr(context)
                                : store.profileName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            store.address.isEmpty
                                ? (store.pincode.isEmpty
                                      ? 'Choose your location'.tr(context)
                                      : store.pincode)
                                : '${store.address} ${store.pincode}',
                          ),
                          TextButton.icon(
                            onPressed: onLocation,
                            icon: const Icon(
                              Icons.location_on_outlined,
                              size: 18,
                            ),
                            label: Text(
                              (store.pincode.isEmpty && store.latitude == null
                                      ? 'Set location'
                                      : 'Change location')
                                  .tr(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions,
                  ],
                ),
              ),
              SizedBox(height: header.gap),
              LayoutBuilder(
                builder: (context, c) {
                  final serviceWidth = services.width(
                    c.maxWidth,
                    fallback: narrow ? 140 : 164,
                  );
                  final officeWidth = officeLayout.width(
                    c.maxWidth,
                    fallback:
                        narrow && c.maxWidth - serviceWidth - header.gap >= 160
                        ? c.maxWidth - serviceWidth - header.gap
                        : narrow
                        ? c.maxWidth
                        : 260,
                  );
                  final canShare =
                      c.maxWidth -
                          serviceWidth -
                          officeWidth -
                          header.gap * 2 >=
                      340;
                  final searchWidth = canShare
                      ? c.maxWidth - serviceWidth - officeWidth - header.gap * 2
                      : c.maxWidth;
                  return Wrap(
                    spacing: header.gap,
                    runSpacing: header.gap,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: searchWidth,
                        child: ResponsiveSearchBox(
                          layout: layoutFor(context, settings, 'search'),
                          controller: search,
                          onChanged: onSearch,
                          onAssistedSearch: onAssistedSearch,
                        ),
                      ),
                      if (services.visible)
                        box(
                          services,
                          serviceWidth,
                          TextButton(
                            onPressed: onServices,
                            child: Wrap(
                              spacing: services.gap,
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Icon(
                                  Icons.home_repair_service_outlined,
                                  size: services.n('iconSize', 24, 16, 48),
                                ),
                                Text(
                                  'Services'.tr(context),
                                  style: sectionTextStyle(
                                    services.styled(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (officeLayout.visible)
                        box(
                          officeLayout,
                          officeWidth,
                          InkWell(
                            onTap: () => office(context),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Office / Head Office'.tr(context),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  store.business.text('address').isEmpty
                                      ? 'Contact our office'.tr(context)
                                      : store.business.text('address'),
                                ),
                                TextButton(
                                  onPressed: () => office(context),
                                  child: Text('Contact details'.tr(context)),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class ResponsiveSearchBox extends StatelessWidget {
  const ResponsiveSearchBox({
    super.key,
    required this.layout,
    required this.controller,
    required this.onChanged,
    required this.onAssistedSearch,
  });
  final ComponentLayout layout;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final ValueChanged<bool> onAssistedSearch;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final margin = layout.margin.clamp(0, c.maxWidth / 20).toDouble();
      final available = c.maxWidth - margin * 2;
      final width = layout.width(available, floor: math.min(available, 260));
      final padding = layout.padding.clamp(0, width / 24).toDouble();
      final gap = layout.n('gap', 2, 0, math.min(16, width / 32));
      final font = layout.font(
        Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16,
      );
      final height = layout.height(
        56,
        floor:
            math.max(48, MediaQuery.textScalerOf(context).scale(font) * 1.5) +
            padding * 2,
      );
      Widget icon(
        String tooltip,
        IconData icon,
        String field,
        VoidCallback action,
      ) => IconButton(
        tooltip: tooltip,
        onPressed: action,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
        icon: Icon(icon, size: layout.n(field, 22, 16, width < 360 ? 28 : 48)),
      );
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          key: const ValueKey('responsive-search-box'),
          margin: EdgeInsets.all(margin),
          width: width,
          height: height,
          padding: EdgeInsets.all(padding),
          decoration: entryDecoration(
            Entry(layout.entry.id, {
              'borderColor': '#CCD8CE',
              'borderWidth': 1,
              ...layout.entry.data,
            }),
            fallback: Theme.of(context).colorScheme.surface,
          ),
          child: Row(
            children: [
              icon('Search products'.tr(context), Icons.search, 'iconSize', onChanged),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onChanged(),
                  style: sectionTextStyle(layout.styled(context))
                      .copyWith(fontSize: font),
                  decoration: InputDecoration(
                    hintText: 'Search products'.tr(context),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              SizedBox(width: gap),
              icon(
                'Voice search'.tr(context),
                Icons.mic_none,
                'voiceIconSize',
                () => onAssistedSearch(false),
              ),
              SizedBox(width: gap),
              icon(
                'Camera search'.tr(context),
                Icons.camera_alt_outlined,
                'imageIconSize',
                () => onAssistedSearch(true),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class ContactActions extends StatelessWidget {
  const ContactActions({super.key, required this.phone, this.whatsapp = ''});
  final String phone, whatsapp;
  Future<void> launch(BuildContext context, Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          context.mounted) {
        message(context, 'Could not open contact app');
      }
    } catch (e) {
      if (context.mounted) message(context, 'Could not open contact app');
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    children: [
      if (phone.isNotEmpty)
        OutlinedButton.icon(
          onPressed: () => launch(context, Uri(scheme: 'tel', path: phone)),
          icon: const Icon(Icons.call_outlined),
          label: Text('Call'.tr(context)),
        ),
      if (whatsapp.isNotEmpty || phone.isNotEmpty)
        OutlinedButton.icon(
          onPressed: () => launch(
            context,
            Uri.https(
              'wa.me',
              '/${(whatsapp.isEmpty ? phone : whatsapp).replaceAll(RegExp(r'\D'), '')}',
            ),
          ),
          icon: const Icon(Icons.chat_outlined),
          label: const Text('WhatsApp'),
        ),
    ],
  );
}
