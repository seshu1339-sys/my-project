import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/ads.dart';
import '../domain/android_home.dart';
import '../domain/catalog.dart';
import 'android_layout.dart';
import 'shared.dart';

/// The name and icon of each part of the Android home screen, as the admin sees them here.
const androidPartInfo = <String, (String, String, IconData)>{
  'ads': ('Ad boxes', 'The small ad boxes that slide along.', Icons.ad_units_outlined),
  'scrollingText': ('Scrolling Text', 'The red moving banner.', Icons.text_rotation_none),
  'notice': ("Today's Offers banner", "The banner that names your town's offers, with the price chips.", Icons.campaign_outlined),
  'quickFresh': ('Fresh today', 'Showing items in your location, and the Fresh today strip.', Icons.bolt_outlined),
  'promo': ("Today's Offers cards", 'The offer cards, two side by side.', Icons.view_carousel_outlined),
  'strip': ('Fresh Fruits & Vegetables and Transport', "The product cards and the Transport / Services boxes under Today's Offers.", Icons.eco_outlined),
  'popular': ('Products', 'Products and services.', Icons.shopping_bag_outlined),
  'localServices': ('Local Services', 'Local service listings.', Icons.home_repair_service_outlined),
  'nearby': ('Shops', 'Shops near the customer.', Icons.storefront_outlined),
};

/// Settings > Android App: the ad boxes, and where each part of the Android home screen goes (its place, 1, 2, 3 ..., and whether it
/// shows). Saved to settings/androidHome, which only the Android app reads, and applied at once without an app update; the website's own
/// settings (the other pages of Settings) are not touched. Nothing saved means everything shown in the usual order.
class AdminAndroidHomePage extends StatefulWidget {
  const AdminAndroidHomePage({super.key, required this.store});
  final Store store;
  @override
  State<AdminAndroidHomePage> createState() => _AdminAndroidHomePageState();
}

class _AdminAndroidHomePageState extends State<AdminAndroidHomePage> {
  Store get store => widget.store;
  late bool showAds;
  late List<String> order;
  late Set<String> hidden;
  late TextEditingController slots;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final settings = store.entries('settings');
    final c = AndroidHomeConfig.from(settings);
    showAds = c.showAds;
    hidden = {...c.hidden};
    order = c.arrange(androidDefaultOrder(settings));
    slots = TextEditingController(text: '${c.adSlots}');
  }

  @override
  void dispose() {
    slots.dispose();
    super.dispose();
  }

  void _move(int i, int by) {
    final j = i + by;
    if (j < 0 || j >= order.length) return;
    setState(() => order.insert(j, order.removeAt(i)));
  }

  bool _shown(String part) => part == 'ads' ? showAds : !hidden.contains(part);

  void _show(String part, bool on) => setState(() {
    if (part == 'ads') {
      showAds = on;
    } else if (on) {
      hidden.remove(part);
    } else {
      hidden.add(part);
    }
  });

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      final n = (int.tryParse(slots.text.trim()) ?? defaultAndroidAdSlots).clamp(1, 12);
      final fields = AndroidHomeConfig(adSlots: n, showAds: showAds, order: order, hidden: hidden).toFields();
      await store.updateFields('settings', androidHomeId, fields, fallback: Entry(androidHomeId, {'name': 'Android app home', ...fields}));
      if (mounted) {
        slots.text = '$n';
        message(context, 'Saved. The Android app shows it at once; the website is not changed.');
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seconds = AdsConfig.from(store.entries('settings')).seconds;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Android App', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text('Where the parts of the home screen go in the Android app, and whether each shows. The website has its own settings in the other pages of Settings; changing this does not change the website.'),
        const SizedBox(height: 16),
        SwitchListTile(
          key: const ValueKey('android-show-ad-boxes'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Show the ad boxes in the app'),
          value: showAds,
          onChanged: (on) => _show('ads', on),
        ),
        SizedBox(
          width: 260,
          child: TextField(
            key: const ValueKey('android-ad-slots'),
            controller: slots,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Ad boxes shown at once (1 to 12)', isDense: true, border: OutlineInputBorder()),
          ),
        ),
        const SizedBox(height: 4),
        Text('Each ad stays $seconds seconds by default: the same "Seconds each ad stays (default)" setting as the website (Right Side Ads).', key: const ValueKey('android-slide-time')),
        const SizedBox(height: 16),
        Text('Parts of the home screen, top to bottom (under the logo, location and search row)', style: Theme.of(context).textTheme.titleMedium),
        for (var i = 0; i < order.length; i++)
          Card(
            key: ValueKey('android-part-${order[i]}'),
            child: ListTile(
              leading: CircleAvatar(radius: 14, child: Text('${i + 1}', key: ValueKey('android-place-${order[i]}'))),
              title: Row(children: [Icon(androidPartInfo[order[i]]!.$3, size: 18), const SizedBox(width: 8), Flexible(child: Text(androidPartInfo[order[i]]!.$1))]),
              subtitle: Text(_shown(order[i]) ? androidPartInfo[order[i]]!.$2 : 'Hidden in the app'),
              trailing: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(key: ValueKey('android-up-${order[i]}'), tooltip: 'Move up', onPressed: i == 0 ? null : () => _move(i, -1), icon: const Icon(Icons.arrow_upward)),
                  IconButton(key: ValueKey('android-down-${order[i]}'), tooltip: 'Move down', onPressed: i == order.length - 1 ? null : () => _move(i, 1), icon: const Icon(Icons.arrow_downward)),
                  Switch(key: ValueKey('android-show-${order[i]}'), value: _shown(order[i]), onChanged: (on) => _show(order[i], on)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerLeft, child: FilledButton(key: const ValueKey('save-android-home'), onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save'))),
      ],
    );
  }
}
