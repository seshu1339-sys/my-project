import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/ads.dart';
import '../domain/android_home.dart';
import '../domain/catalog.dart';
import 'admin_home_sections.dart';
import 'shared.dart';

/// Settings > Android App: where the parts of the home screen go in the Android app, and how many ads show. Saved to
/// settings/androidHome, which only the app reads; the website's own settings (the other pages of Settings) are not touched.
class AdminAndroidHomePage extends StatefulWidget {
  const AdminAndroidHomePage({super.key, required this.store});
  final Store store;
  @override
  State<AdminAndroidHomePage> createState() => _AdminAndroidHomePageState();
}

class _AdminAndroidHomePageState extends State<AdminAndroidHomePage> {
  Store get store => widget.store;
  late List<String> order;
  late Set<String> hidden;
  late TextEditingController slots;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final c = AndroidHomeConfig.from(store.entries('settings'));
    order = [...c.order];
    hidden = {...c.hidden};
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

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      final n = (int.tryParse(slots.text.trim()) ?? 1).clamp(1, 12);
      final fields = AndroidHomeConfig(adSlots: n, order: order, hidden: hidden).toFields();
      await store.updateFields('settings', androidHomeId, fields, fallback: Entry(androidHomeId, {'name': 'Android app home', ...fields}));
      if (mounted) {
        slots.text = '$n';
        message(context, 'Saved. Only the Android app uses this; the website is not changed.');
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
        const Text('Where the parts of the home screen go in the Android app. The website has its own settings in the other pages of Settings; changing this does not change the website.'),
        const SizedBox(height: 16),
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
        Text('Each ad stays $seconds seconds by default: the same "Seconds each ad stays (default)" setting as the website (Right Side Ads), and any ad with its own time keeps it.', key: const ValueKey('android-slide-time')),
        const SizedBox(height: 16),
        Text('Parts of the home screen, top to bottom', style: Theme.of(context).textTheme.titleMedium),
        for (var i = 0; i < order.length; i++)
          Card(
            key: ValueKey('android-part-${order[i]}'),
            child: ListTile(
              leading: Icon(homeSectionInfos[order[i]]!.icon),
              title: Text(homeSectionInfos[order[i]]!.title),
              subtitle: Text(hidden.contains(order[i]) ? 'Hidden in the app' : 'Shown in the app'),
              trailing: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(key: ValueKey('android-up-${order[i]}'), tooltip: 'Move up', onPressed: i == 0 ? null : () => _move(i, -1), icon: const Icon(Icons.arrow_upward)),
                  IconButton(key: ValueKey('android-down-${order[i]}'), tooltip: 'Move down', onPressed: i == order.length - 1 ? null : () => _move(i, 1), icon: const Icon(Icons.arrow_downward)),
                  Switch(
                    key: ValueKey('android-show-${order[i]}'),
                    value: !hidden.contains(order[i]),
                    onChanged: (on) => setState(() => on ? hidden.remove(order[i]) : hidden.add(order[i])),
                  ),
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
