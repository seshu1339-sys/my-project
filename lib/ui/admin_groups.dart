import 'package:flutter/material.dart';

import '../modules/home_module.dart' show ModuleAdminSection;
import '../modules/module_admin.dart';

// The admin panel in six groups (owner, 13 Nov 2026): similar things together, so the panel is clear at a glance. Every page that was
// a tab or a Settings section before is one item of one group; nothing was taken away. A page shown in two places before is in one
// place now and the other place only points to it (Service providers: Services; the Vendors tab says where they went). The Settings
// group is the index of every section, under the same group names.

enum AdminItemKind { tab, section, providers }

/// One page of a group: an earlier main tab ([AdminItemKind.tab], by its old name), a Settings section (by its key) or the service
/// providers' list.
class AdminItem {
  const AdminItem(this.id, this.label, this.icon, {this.kind = AdminItemKind.section});
  final String id, label;
  final IconData icon;
  final AdminItemKind kind;
}

class AdminGroup {
  const AdminGroup(this.id, this.title, this.icon, this.items);
  final String id, title;
  final IconData icon;
  final List<AdminItem> items;
}

AdminItem _tab(String name, IconData icon, [String? label]) => AdminItem(name, label ?? name, icon, kind: AdminItemKind.tab);
AdminItem _moduleTab(ModuleAdminSection m, [String? label]) => AdminItem(m.title, label ?? m.title, m.icon, kind: AdminItemKind.tab);

/// The six groups, in the order of the top bar. Settings is last (and it lists every section, by group).
final adminGroups = <AdminGroup>[
  AdminGroup('business', 'Business', Icons.insights_outlined, [
    _tab('Insights', Icons.insights_outlined),
    _tab('Orders', Icons.receipt_long_outlined),
    for (final m in moduleAdminTabs) if (m.id == 'flash') _moduleTab(m, 'Support Team inbox'),
    const AdminItem('aiAssistant', 'AI assistant', Icons.smart_toy_outlined),
  ]),
  AdminGroup('vendors', 'Vendors & Shops', Icons.storefront_outlined, [
    _tab('Vendors', Icons.how_to_reg_outlined, 'Vendors (approve)'),
    _tab('Shops', Icons.store_outlined),
    _tab('Products', Icons.inventory_2_outlined),
    const AdminItem('categories', 'Categories', Icons.category_outlined),
    const AdminItem('productImageLibrary', 'Product Image Library', Icons.photo_library_outlined),
    const AdminItem('shopsLocation', 'Shops without location', Icons.location_off_outlined),
    const AdminItem('cityCodes', 'City codes', Icons.pin_outlined),
    for (final m in moduleAdminTabs) if (const {'plans', 'premium', 'payments'}.contains(m.id)) _moduleTab(m),
    _tab('Complaints', Icons.report_problem_outlined),
    const AdminItem('ratings', 'Ratings', Icons.star_outline),
    const AdminItem('reports', 'Reports', Icons.flag_outlined),
    const AdminItem('blockList', 'Block list', Icons.block),
    for (final m in moduleAdminSections) if (m.id == 'itemPhotos') AdminItem('module-${m.id}', m.title, m.icon),
  ]),
  AdminGroup('services', 'Services', Icons.home_repair_service_outlined, [
    const AdminItem('services', 'Services and service types', Icons.home_repair_service_outlined),
    const AdminItem('serviceProviders', 'Service providers', Icons.engineering_outlined, kind: AdminItemKind.providers),
    for (final m in moduleAdminSections) if (m.id == 'transport') AdminItem('module-${m.id}', m.title, m.icon),
  ]),
  AdminGroup('staff', 'Staff', Icons.badge_outlined, [
    const AdminItem('fieldAssistants', 'Field Assistants (approve)', Icons.badge_outlined),
    for (final m in moduleAdminTabs) if (m.id == 'staffAreas') _moduleTab(m),
    const AdminItem('staffWork', 'Staff work and pay', Icons.payments_outlined),
    const AdminItem('staffRanking', 'Staff ranking', Icons.leaderboard_outlined),
    const AdminItem('idReport', 'ID report', Icons.manage_search),
    const AdminItem('staffLinks', 'Staff links and requests', Icons.link),
    const AdminItem('locations', 'Quick Add locations', Icons.place_outlined),
  ]),
  AdminGroup('ads', 'Ads & Offers', Icons.campaign_outlined, [
    _tab('Promotions', Icons.local_offer_outlined),
    for (final m in moduleAdminTabs) if (m.id == 'offers') _moduleTab(m),
    const AdminItem('homeOffers', "Today's Offers", Icons.campaign_outlined),
    const AdminItem('homePromo', "Today's Offers Box", Icons.view_carousel_outlined),
    const AdminItem('homeFresh', 'Fresh Fruits & Vegetables', Icons.eco_outlined),
    const AdminItem('scrollingText', 'Scrolling Text', Icons.text_rotation_none),
    const AdminItem('ads', 'Right Side Ads', Icons.campaign_outlined),
    const AdminItem('rightBoxes', 'Right Side Ad Boxes', Icons.view_agenda_outlined),
  ]),
  AdminGroup('settings', 'Settings', Icons.settings_outlined, [
    const AdminItem('settings', 'Business Profile', Icons.business_outlined),
    const AdminItem('theme', 'Theme', Icons.palette_outlined),
    const AdminItem('animations', 'Animations', Icons.animation),
    const AdminItem('layout', 'Layout', Icons.dashboard_customize_outlined),
    const AdminItem('androidHome', 'Android App', Icons.phone_android_outlined),
    const AdminItem('areaNames', 'Area names', Icons.place_outlined),
    const AdminItem('samples', 'Sample data', Icons.science_outlined),
  ]),
];

/// The group of an earlier main tab or a Settings section, for the search ("Vendors & Shops › Ratings").
String? adminGroupOf(String id) => adminGroups.where((g) => g.items.any((i) => i.id == id)).firstOrNull?.title;

/// One group's page: its items in a list on the left with the open item beside it (wide), or a list whose items open full screen (phone).
class AdminGroupPage extends StatefulWidget {
  const AdminGroupPage({super.key, required this.items, required this.build});
  final List<AdminItem> items;
  final Widget Function(AdminItem item) build;
  @override
  State<AdminGroupPage> createState() => _AdminGroupPageState();
}

class _AdminGroupPageState extends State<AdminGroupPage> {
  late AdminItem open = widget.items.first;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final content = KeyedSubtree(key: ValueKey('admin-item-${open.id}'), child: widget.build(open));
    if (wide) {
      return Row(children: [
        SizedBox(
          width: 230,
          child: ListView(children: [
            for (final item in widget.items)
              ListTile(
                key: ValueKey('group-item-${item.id}'),
                selected: item.id == open.id,
                leading: Icon(item.icon),
                title: Text(item.label),
                onTap: () => setState(() => open = item),
              ),
          ]),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: content),
      ]);
    }
    // A phone: the group's pages as a list; each opens full screen (like the Settings list), so a page keeps all its room.
    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
      for (final item in widget.items)
        ListTile(
          key: ValueKey('group-item-${item.id}'),
          leading: Icon(item.icon),
          title: Text(item.label),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(title: Text(item.label)), body: widget.build(item)))),
        ),
    ]);
  }
}
