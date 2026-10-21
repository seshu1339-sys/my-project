import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'admin_entry_list.dart';
import 'admin_frame.dart';
import 'admin_page_preview.dart';
import 'entry_editor.dart';
import 'field_moderation.dart';
import 'layout_editor.dart';
import 'visual_editor.dart';

class _SettingsSection {
  const _SettingsSection(this.key, this.label, this.icon, this.hint);
  final String key, label, hint;
  final IconData icon;
}

/// Everything that is not a daily task lives here, in one place: each setting appears once, in one section.
const _sections = <_SettingsSection>[
  _SettingsSection('categories', 'Categories', Icons.category_outlined, 'The product categories customers browse'),
  _SettingsSection('fieldAssistants', 'Field Assistants', Icons.badge_outlined, 'Approve and manage field staff'),
  _SettingsSection('settings', 'Business Profile', Icons.business_outlined, 'Name, address, phone, limits, payments'),
  _SettingsSection('theme', 'Theme', Icons.palette_outlined, 'Colors and fonts of the whole site'),
  _SettingsSection('scrollingText', 'Scrolling Text', Icons.text_rotation_none, 'The moving text banner'),
  _SettingsSection('productImageLibrary', 'Product Image Library', Icons.photo_library_outlined, 'Approved photos vendors can choose'),
  _SettingsSection('layout', 'Layout', Icons.dashboard_customize_outlined, 'Sizes, colors and the order of each part of the page'),
  _SettingsSection('locations', 'Quick Add locations', Icons.place_outlined, 'Extra places for Quick Add (towns come from the pincode list)'),
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
      // One record each: the form opens directly, with no list and no "Add new".
      case 'settings':
      case 'theme':
      case 'scrollingText':
        return AdminSingleRecord(store: widget.store, section: key);
      default:
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

/// A setting that exists once (Business Profile, Theme, Scrolling Text): its form, straight away. A project that has never saved it
/// gets the same form, empty, and the first Save creates it.
class AdminSingleRecord extends StatelessWidget {
  const AdminSingleRecord({super.key, required this.store, required this.section});
  final Store store;
  final String section;

  static String recordId(String section) => section == 'settings' ? 'business' : section;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final Entry? record = store.entries('settings').where((e) => e.id == recordId(section)).firstOrNull;
      // Keyed by "exists yet": the form is rebuilt once when the first Save creates the record.
      return EntryEditor(key: ValueKey('single-$section-${record != null}'), store: store, collection: section, entry: record, embedded: true);
    },
  );
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
