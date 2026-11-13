import 'package:flutter/material.dart';

import '../data/store.dart';
import '../modules/module_admin.dart';
import 'admin_abuse_reports.dart';
import 'admin_staff_work.dart';
import 'shop_ratings.dart' show AdminRatingsPage;
import 'admin_ai_assistant.dart';
import 'admin_android_home.dart';
import 'admin_area_names.dart';
import 'admin_city_codes.dart';
import 'admin_home_sections.dart';
import 'admin_right_boxes.dart';
import 'admin_samples.dart';
import 'admin_entry_list.dart';
import 'admin_fields.dart';
import 'admin_fresh_strip.dart';
import 'admin_shops_location.dart';
import 'animation_settings_form.dart';
import 'admin_frame.dart';
import 'admin_page_preview.dart';
import 'field_moderation.dart';
import 'layout_editor.dart';
import 'screen_view.dart';
import 'visual_editor.dart';

class _SettingsSection {
  const _SettingsSection(this.key, this.label, this.icon, this.hint);
  final String key, label, hint;
  final IconData icon;
}

/// Everything that is not a daily task lives here, in one place: each setting appears once, in one section.
final _sections = <_SettingsSection>[
  _SettingsSection('categories', 'Categories', Icons.category_outlined, 'The product categories customers browse; their order is the order of the Popular Products tabs'),
  _SettingsSection('services', 'Services', Icons.home_repair_service_outlined, 'Service listings and the service types (their own collection)'),
  _SettingsSection('fieldAssistants', 'Field Assistants', Icons.badge_outlined, 'Approve and manage field staff'),
  _SettingsSection('cityCodes', 'City codes', Icons.pin_outlined, 'Four-letter town codes in vendor IDs (VEN-NRPM-116-325)'),
  _SettingsSection('settings', 'Business Profile', Icons.business_outlined, 'Customers see shops and offers within (km); name, address, phone, limits, payments'),
  _SettingsSection('theme', 'Theme', Icons.palette_outlined, 'Colors and fonts of the whole site'),
  _SettingsSection('animations', 'Animations', Icons.animation, 'Turn animations on or off, choose the type and speed'),
  _SettingsSection('scrollingText', 'Scrolling Text', Icons.text_rotation_none, 'The moving red line at the top of the home page'),
  _SettingsSection('homeOffers', "Today's Offers", Icons.campaign_outlined, "The banner that names your town's offers, with the price chips"),
  _SettingsSection('homePromo', "Today's Offers Box", Icons.view_carousel_outlined, 'The 6 coloured offer boxes and the item offers in them'),
  _SettingsSection('homeFresh', 'Fresh Fruits & Vegetables', Icons.eco_outlined, "The items of the strip under Today's Offers, in your order"),
  _SettingsSection('shopsLocation', 'Shops without location', Icons.location_off_outlined, 'Shops missing latitude and longitude: distance and the road need them'),
  _SettingsSection('ads', 'Right Side Ads', Icons.campaign_outlined, 'The boxes on the right: animation, colours, every ad'),
  _SettingsSection('rightBoxes', 'Right Side Ad Boxes', Icons.view_agenda_outlined, 'Photo boxes down the right side: add, remove, photo, link'),
  _SettingsSection('productImageLibrary', 'Product Image Library', Icons.photo_library_outlined, 'Approved photos vendors can choose'),
  _SettingsSection('layout', 'Layout', Icons.dashboard_customize_outlined, 'Sizes, colors and the order of each part of the page'),
  _SettingsSection('androidHome', 'Android App', Icons.phone_android_outlined, 'Android app only: how many ad boxes show at the top, and whether they show'),
  _SettingsSection('locations', 'Quick Add locations', Icons.place_outlined, 'Extra places for Quick Add (towns come from the pincode list)'),
  _SettingsSection('samples', 'Sample data', Icons.science_outlined, 'Records labelled SAMPLE, and the button that deletes them all'),
  _SettingsSection('areaNames', 'Area names', Icons.place_outlined, 'Fix or stop the area names customers see (Kancharapalem S.O → Kancharapalem)'),
  // Each home module (Transport, ...) that has an admin section brings its own; see lib/modules/module_admin.dart.
  for (final section in moduleAdminSections) _SettingsSection('module-${section.id}', section.title, section.icon, section.hint),
  // The admin's AI assistant (Claude Sonnet 5.5, functions/modules/admin-assistant): last, so the numbers of the others stay the same.
  _SettingsSection('aiAssistant', 'AI assistant', Icons.smart_toy_outlined, 'Ask about your numbers in plain words: vendors, offers, payments, tickets'),
  // Abuse reports, the automatic temporary suspension and the permanent block list (functions/modules/abuse-reports).
  _SettingsSection('reports', 'Reports', Icons.flag_outlined, 'Reported shops, providers and customers; restore or block for good'),
  _SettingsSection('blockList', 'Block list', Icons.block, 'Emails and phones that cannot register or sign in again'),
  _SettingsSection('ratings', 'Ratings', Icons.star_outline, 'Star ratings of shops and service providers; remove fake ones'),
  // Staff work (functions/modules/staff-work, staff-links): performance, targets, pay slabs, ranking, ID report, links.
  _SettingsSection('staffWork', 'Staff work and pay', Icons.badge_outlined, 'Each staff member: linked vendors, daily target (50), month, pay slabs, mark paid'),
  _SettingsSection('staffRanking', 'Staff ranking', Icons.leaderboard_outlined, "This month's best staff: updates, active vendors, target done; by area"),
  _SettingsSection('idReport', 'ID report', Icons.manage_search, 'Type a Vendor, provider or Staff ID: the full report, graphs, Excel and PDF'),
  _SettingsSection('staffLinks', 'Staff links and requests', Icons.link, 'Link any vendor to staff of its area; vendors\' "connect me to local staff" requests'),
];

/// One thing the admin can search for at the top of the admin panel: a Settings section ("5 Business Profile") or one field of it
/// ("5.12 Business Profile › Post duration"). [serial] is its number in the Settings list.
class AdminSettingHit {
  const AdminSettingHit({required this.serial, required this.title, required this.sectionKey, this.section = '', this.hint = ''});
  final String serial, title, sectionKey, section, hint;
  bool get isField => section.isNotEmpty;
  String get label => isField ? '$section › $title' : title;
}

/// Every Settings section, numbered from 1 in the order of the list, and the fields of the sections that are one form (Business
/// Profile, Theme, Scrolling Text: lib/ui/admin_fields.dart), numbered 5.1, 5.2 ...
List<AdminSettingHit> adminSettingsIndex() => [
  for (final (i, s) in _sections.indexed) ...[
    AdminSettingHit(serial: '${i + 1}', title: s.label, sectionKey: s.key, hint: s.hint),
    for (final (j, f) in (fields[s.key]?.entries ?? const Iterable<MapEntry<String, String>>.empty()).indexed)
      AdminSettingHit(serial: '${i + 1}.${j + 1}', title: f.value, sectionKey: s.key, section: s.label, hint: f.key),
  ],
];

/// The settings that match what the admin typed or said: a number finds that serial (and the fields under a section number); words
/// find every entry whose name, section or hint holds all of them. Sections come before fields.
List<AdminSettingHit> searchAdminSettings(String query, {List<AdminSettingHit>? index}) {
  final all = index ?? adminSettingsIndex();
  final q = query.trim().toLowerCase().replaceAll(RegExp(r'^(no\.?|number|serial|నంబర్)\s*'), '');
  if (q.isEmpty) return const [];
  if (RegExp(r'^\d+(\.\d+)?$').hasMatch(q)) {
    return [for (final h in all) if (h.serial == q || (!q.contains('.') && h.serial.startsWith('$q.'))) h];
  }
  final words = q.split(RegExp(r'\s+'));
  final hits = [for (final h in all) if (words.every('${h.serial} ${h.title} ${h.section} ${h.hint}'.toLowerCase().contains)) h];
  return [...hits.where((h) => !h.isField), ...hits.where((h) => h.isField)];
}

/// One Settings section as its own page (the search opens it straight away). [focus] names the field the admin looked for.
Widget adminSettingsSectionPage(Store store, String key, {String? focus}) {
  final section = _sections.where((s) => s.key == key).firstOrNull;
  return Scaffold(
    appBar: AppBar(title: Text(focus == null ? (section?.label ?? 'Settings') : '${section?.label ?? 'Settings'} › $focus')),
    body: adminSettingsContent(store, key),
  );
}

/// What one Settings section shows.
Widget adminSettingsContent(Store store, String key) {
  switch (key) {
      case 'aiAssistant':
        return AdminAiAssistantPage(store: store);
      case 'reports':
        return AdminReportsPage(store: store);
      case 'blockList':
        return AdminBlockListPage(store: store);
      case 'ratings':
        return AdminRatingsPage(store: store);
      case 'staffWork':
        return AdminStaffWorkPage(store: store);
      case 'staffRanking':
        return AdminStaffRankingPage(store: store);
      case 'idReport':
        return AdminIdReportPage(store: store);
      case 'staffLinks':
        return AdminLinkRequestsPage(store: store);
      case 'fieldAssistants':
        return AdminEmbedScope(child: AdminNeedsFirebase(store: store, child: FieldModerationPage(store: store)));
      case 'layout':
        return _LayoutMenu(store: store);
      case 'animations':
        return AdminAnimationsForm(store: store);
      case 'scrollingText':
        return AdminHomeSectionPage(store: store, part: 'scrollingText');
      case 'homeOffers':
        return AdminHomeSectionPage(store: store, part: 'notice');
      case 'homePromo':
        return AdminHomeSectionPage(store: store, part: 'promo');
      case 'homeFresh':
        return ScreenView('admin_fresh_strip', child: AdminFreshStripPage(store: store));
      case 'shopsLocation':
        return ScreenView('admin_shops_location', child: AdminShopsLocationPage(store: store));
      case 'ads':
        return AdminHomeSectionPage(store: store, part: 'ads');
      case 'androidHome':
        return AdminAndroidHomePage(store: store);
      case 'cityCodes':
        return AdminCityCodesPage(store: store);
      case 'areaNames':
        return AdminAreaNamesPage(store: store);
      case 'samples':
        return ScreenView('admin_samples', child: AdminNeedsFirebase(store: store, child: AdminSamplesPage(store: store)));
      case 'rightBoxes':
        return ScreenView('admin_right_boxes', child: AdminRightBoxesPage(store: store));
      // One record each: the form opens directly, with no list and no "Add new".
      case 'settings':
      case 'theme':
        return AdminSingleRecord(store: store, section: key);
      default:
        if (key.startsWith('module-')) {
          final section = moduleAdminSections.where((s) => 'module-${s.id}' == key).firstOrNull;
          if (section != null) return section.build(store);
        }
        return AdminEntryList(store: store, section: key);
    }
  }

/// The Settings tab: a list of sections on the left (a plain list on a phone) and the chosen section beside it.
class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key, required this.store});
  final Store store;
  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  String selected = _sections.first.key;

  Widget _content(String key) => adminSettingsContent(widget.store, key);

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
