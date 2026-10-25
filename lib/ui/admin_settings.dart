import 'package:flutter/material.dart';

import '../data/store.dart';
import '../modules/module_admin.dart';
import 'admin_city_codes.dart';
import 'admin_home_sections.dart';
import 'admin_right_boxes.dart';
import 'admin_entry_list.dart';
import 'animation_settings_form.dart';
import 'admin_frame.dart';
import 'admin_page_preview.dart';
import 'field_moderation.dart';
import 'layout_editor.dart';
import 'visual_editor.dart';

class _SettingsSection {
  const _SettingsSection(this.key, this.label, this.icon, this.hint);
  final String key, label, hint;
  final IconData icon;
}

/// Everything that is not a daily task lives here, in one place: each setting appears once, in one section.
final _sections = <_SettingsSection>[
  _SettingsSection('categories', 'Categories', Icons.category_outlined, 'The product categories customers browse'),
  _SettingsSection('services', 'Services', Icons.home_repair_service_outlined, 'Service listings and the service types (their own collection)'),
  _SettingsSection('fieldAssistants', 'Field Assistants', Icons.badge_outlined, 'Approve and manage field staff'),
  _SettingsSection('cityCodes', 'City codes', Icons.pin_outlined, 'Four-letter town codes in vendor IDs (VEN-NRPM-116-325)'),
  _SettingsSection('settings', 'Business Profile', Icons.business_outlined, 'Name, address, phone, limits, payments'),
  _SettingsSection('theme', 'Theme', Icons.palette_outlined, 'Colors and fonts of the whole site'),
  _SettingsSection('animations', 'Animations', Icons.animation, 'Turn animations on or off, choose the type and speed'),
  _SettingsSection('scrollingText', 'Scrolling Text', Icons.text_rotation_none, 'The moving red line at the top of the home page'),
  _SettingsSection('homeOffers', "Today's Offers", Icons.campaign_outlined, "The banner that names your town's offers, with the price chips"),
  _SettingsSection('homePromo', "Today's Offers Box", Icons.view_carousel_outlined, 'The row of coloured offer boxes'),
  _SettingsSection('ads', 'Right Side Ads', Icons.campaign_outlined, 'The boxes on the right: animation, colours, every ad'),
  _SettingsSection('rightBoxes', 'Right Side Ad Boxes', Icons.view_agenda_outlined, 'Photo boxes down the right side: add, remove, photo, link'),
  _SettingsSection('productImageLibrary', 'Product Image Library', Icons.photo_library_outlined, 'Approved photos vendors can choose'),
  _SettingsSection('layout', 'Layout', Icons.dashboard_customize_outlined, 'Sizes, colors and the order of each part of the page'),
  _SettingsSection('locations', 'Quick Add locations', Icons.place_outlined, 'Extra places for Quick Add (towns come from the pincode list)'),
  // Each home module (Transport, ...) that has an admin section brings its own; see lib/modules/module_admin.dart.
  for (final section in moduleAdminSections) _SettingsSection('module-${section.id}', section.title, section.icon, section.hint),
];

/// The Settings tab: a list of sections on the left (a plain list on a phone) and the chosen section beside it.
class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key, required this.store});
  final Store store;
  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  String selected = _sections.first.key;

  Widget _content(String key) {
    switch (key) {
      case 'fieldAssistants':
        return AdminEmbedScope(child: AdminNeedsFirebase(store: widget.store, child: FieldModerationPage(store: widget.store)));
      case 'layout':
        return _LayoutMenu(store: widget.store);
      case 'animations':
        return AdminAnimationsForm(store: widget.store);
      case 'scrollingText':
        return AdminHomeSectionPage(store: widget.store, part: 'scrollingText');
      case 'homeOffers':
        return AdminHomeSectionPage(store: widget.store, part: 'notice');
      case 'homePromo':
        return AdminHomeSectionPage(store: widget.store, part: 'promo');
      case 'ads':
        return AdminHomeSectionPage(store: widget.store, part: 'ads');
      case 'cityCodes':
        return AdminCityCodesPage(store: widget.store);
      case 'rightBoxes':
        return AdminRightBoxesPage(store: widget.store);
      // One record each: the form opens directly, with no list and no "Add new".
      case 'settings':
      case 'theme':
        return AdminSingleRecord(store: widget.store, section: key);
      default:
        if (key.startsWith('module-')) {
          final section = moduleAdminSections.where((s) => 'module-${s.id}' == key).firstOrNull;
          if (section != null) return section.build(widget.store);
        }
        return AdminEntryList(store: widget.store, section: key);
    }
  }

  void _open(_SettingsSection s) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      setState(() => selected = s.key);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(title: Text(s.label)), body: _content(s.key))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final list = ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final s in _sections)
          ListTile(
            key: ValueKey('settings-${s.key}'),
            selected: wide && selected == s.key,
            leading: Icon(s.icon),
            title: Text(s.label),
            subtitle: wide ? null : Text(s.hint),
            trailing: wide ? null : const Icon(Icons.chevron_right),
            onTap: () => _open(s),
          ),
      ],
    );
    if (!wide) return list;
    return Row(
      children: [
        SizedBox(width: 280, child: list),
        const VerticalDivider(width: 1),
        Expanded(child: _content(selected)),
      ],
    );
  }
}

/// Settings → Layout: the three ways of changing how the site looks.
class _LayoutMenu extends StatelessWidget {
  const _LayoutMenu({required this.store});
  final Store store;

  void _push(BuildContext context, String title, Widget body) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: body)));

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Card(
        child: ListTile(
          key: const ValueKey('layout-settings'),
          leading: const Icon(Icons.dashboard_customize_outlined),
          title: const Text('Layout settings'),
          subtitle: const Text('Every numbered part of the site: size, colors, fonts'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => LayoutSettingsPage(store: store))),
        ),
      ),
      Card(
        child: ListTile(
          key: const ValueKey('layout-visual-editor'),
          leading: const Icon(Icons.auto_fix_high_outlined),
          title: const Text('Visual Editor'),
          subtitle: const Text('Click a part on the live preview to edit it'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => VisualEditorPage(store: store))),
        ),
      ),
      Card(
        child: ListTile(
          key: const ValueKey('layout-page-view'),
          leading: const Icon(Icons.view_agenda_outlined),
          title: const Text('Page view'),
          subtitle: const Text('The home page as a list: reorder and resize its sections'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _push(
            context,
            'Page view',
            AdminPagePreview(
              store: store,
              onOpenSection: (section) => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => AdminEntryListPage(store: store, section: section)),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
