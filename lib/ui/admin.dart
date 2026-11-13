import 'package:flutter/material.dart';

import '../data/store.dart';
import '../modules/module_admin.dart';
import '../services/admin_route.dart';
import 'admin_entry_list.dart';
import 'sample_tag.dart';
import 'admin_frame.dart';
import 'admin_insights.dart';
import 'admin_ai_assistant.dart';
import 'admin_groups.dart';
import 'admin_settings.dart';
import 'admin_settings_search.dart';

// admin.dart is the admin shell: the tabs (Insights, Orders, Products, Vendors, Shops, Complaints, Promotions, Settings)
// and the three top-bar buttons (Search, AI Agent, Sign out). Each moderation/editing concern lives in its own file with no
// shared private helpers between them. Exported (not just imported) so that existing code importing only 'admin.dart' --
// main_admin.dart, admin_auth.dart, and test/admin_test.dart's direct `EntryEditor` usage -- keeps working unchanged.
import 'admin_orders.dart';
import 'complaint_moderation.dart';
import 'provider_moderation.dart';
import 'vendor_moderation.dart';
import 'admin_search.dart';
import 'quick_admin.dart';
import 'ai_agent_page.dart';
export 'admin_fields.dart';
export 'admin_orders.dart';
export 'complaint_moderation.dart';
export 'entry_editor.dart';
export 'vendor_moderation.dart';
export 'admin_search.dart';
export 'ai_agent_page.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.store});
  final Store store;
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  @override
  void initState() {
    super.initState();
    // The sample accounts, for the SAMPLE label on their records (lib/ui/sample_tag.dart).
    if (widget.store.live) SampleOwners.watch(() => widget.store.firestore);
    // A Home Screen shortcut to `<admin route>?open=ai-agent` lands here straight after the normal password+OTP login; this is
    // the only effect of that query param -- nothing about login itself changes. Scheduled for after the first frame since
    // Navigator needs a built context.
    if (wantsAiAgentDirectly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AiAgentPage(store: widget.store)));
      });
    }
  }

  // Owner, 13 Nov 2026: six groups, so the panel is clear at a glance; every earlier page is one item of one group (lib/ui/admin_groups.dart).
  static final _tabs = [for (final g in adminGroups) g.title];

  /// One group: its items beside (wide) or above (phone) the open item. Settings is the index of every setting, by group.
  Widget _group(AdminGroup group) {
    if (group.id == 'settings') return AdminEmbedScope(child: AdminSettingsPage(store: widget.store));
    return AdminGroupPage(
      key: ValueKey('admin-group-${group.id}'),
      items: group.items,
      build: (item) => switch (item.kind) {
        AdminItemKind.tab => _tab(item.id),
        AdminItemKind.section => AdminEmbedScope(child: adminSettingsContent(widget.store, item.id)),
        AdminItemKind.providers => AdminEmbedScope(child: AdminNeedsFirebase(store: widget.store, child: ProviderModerationPage(store: widget.store))),
      },
    );
  }

  Widget _tab(String name) {
    final store = widget.store;
    for (final module in moduleAdminTabs) {
      if (module.title == name) return AdminEmbedScope(child: AdminNeedsFirebase(store: store, child: module.build(store)));
    }
    final page = switch (name) {
      'Insights' => AdminInsightsPage(store: store),
      'Orders' => AdminOrders(store: store),
      'Products' => AdminEntryList(store: store, section: 'products'),
      'Vendors' => AdminNeedsFirebase(store: store, child: _VendorsTab(store: store)),
      'Shops' => AdminEntryList(store: store, section: 'shops'),
      'Complaints' => AdminNeedsFirebase(store: store, child: ComplaintModerationPage(store: store)),
      'Promotions' => AdminEntryList(store: store, section: 'promotions'),
      _ => AdminSettingsPage(store: store),
    };
    return AdminEmbedScope(child: page);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      if (widget.store.live && !widget.store.admin) {
        return Scaffold(
          appBar: AppBar(title: const Text('Admin')),
          body: const Center(child: Text('Sign in with an administrator account to manage your business.')),
        );
      }
      final store = widget.store;
      // The three top-bar buttons always carry a text label. On a phone they sit in a row under the title instead of beside it.
      final narrow = MediaQuery.sizeOf(context).width < 760;
      // The settings search sits at the top of the panel; on a short window (under 700 px high) it opens from a top-bar button instead,
      // so the pages keep their room.
      final tall = MediaQuery.sizeOf(context).height >= 700;
      final buttons = <Widget>[
        if (!tall)
          TextButton.icon(
            key: const ValueKey('top-find-setting'),
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Find a setting')),
              body: Column(children: [AdminSettingsSearchBar(store: store)]),
            ))),
            icon: const Icon(Icons.manage_search),
            label: const Text('Find setting'),
          ),
        TextButton.icon(
          key: const ValueKey('top-search'),
          onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AdminSearchPage(store: store))),
          icon: const Icon(Icons.search),
          label: const Text('Search'),
        ),
        TextButton.icon(
          key: const ValueKey('top-ai-agent'),
          // The AI assistant (Claude Sonnet 5.5, read-only counts). The older AI Agent page stays one tap away in its top bar.
          onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('AI assistant'), actions: [
              TextButton(
                key: const ValueKey('open-old-ai-agent'),
                onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AiAgentPage(store: store))),
                child: const Text('Older AI Agent'),
              ),
            ]),
            body: AdminAiAssistantPage(store: store),
          ))),
          icon: const Icon(Icons.smart_toy_outlined),
          label: const Text('AI Agent'),
        ),
        if (store.live)
          TextButton.icon(
            key: const ValueKey('top-sign-out'),
            onPressed: store.logout,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
      ];
      return DefaultTabController(
        length: _tabs.length,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Business studio'),
            actions: narrow ? null : buttons,
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(kTextTabBarHeight + (narrow ? 44 : 0)),
              child: Column(
                children: [
                  if (narrow)
                    SizedBox(
                      height: 44,
                      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: buttons)),
                    ),
                  TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in _tabs) Tab(text: t)]),
                ],
              ),
            ),
          ),
          body: Column(
            children: [
              // Find any setting by name or number, typed or spoken (lib/ui/admin_settings_search.dart).
              if (tall) AdminSettingsSearchBar(store: store),
              if (!store.live)
                Container(
                  width: double.infinity,
                  color: const Color(0xffffedcb),
                  padding: const EdgeInsets.all(12),
                  child: const Text('Demo studio • Changes are saved on this device. Live access requires an administrator account.'),
                ),
              // Only the open tab is built, so a page never starts reading data before it is shown.
              Expanded(child: Builder(builder: (context) {
                final controller = DefaultTabController.of(context);
                return ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => KeyedSubtree(key: ValueKey(controller.index), child: _group(adminGroups[controller.index])),
                );
              })),
            ],
          ),
        ),
      );
    },
  );
}

/// Vendors: approvals and publishing, with the Quick Add accounts and items beside them (they are vendor and staff operations).
class _VendorsTab extends StatelessWidget {
  const _VendorsTab({required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Column(
      children: [
        const TabBar(isScrollable: true, tabs: [Tab(text: 'Vendors'), Tab(text: 'Service providers'), Tab(text: 'Quick Add accounts'), Tab(text: 'Quick Add items')]),
        Expanded(
          child: Builder(builder: (context) {
            final controller = DefaultTabController.of(context);
            return ListenableBuilder(
              listenable: controller,
              builder: (context, _) => KeyedSubtree(
                key: ValueKey(controller.index),
                child: AdminEmbedScope(
                  child: switch (controller.index) {
                    0 => VendorModerationPage(store: store),
                    // Service providers are under Services > Service providers (one place); this tab only points there.
                    1 => const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Service providers are now under Services > Service providers.', key: ValueKey('providers-moved'), textAlign: TextAlign.center))),
                    2 => QuickAccountsPage(store: store),
                    _ => QuickItemsAdminPage(store: store),
                  },
                ),
              ),
            );
          }),
        ),
      ],
    ),
  );
}
