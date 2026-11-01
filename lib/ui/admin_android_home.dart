import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/ads.dart';
import '../domain/android_home.dart';
import '../domain/catalog.dart';
import 'shared.dart';

/// Settings > Android App: how many ad boxes show at the top of the Android app and whether they show at all. Saved to
/// settings/androidHome, which only the app reads; the website's own settings (the other pages of Settings) are not touched.
class AdminAndroidHomePage extends StatefulWidget {
  const AdminAndroidHomePage({super.key, required this.store});
  final Store store;
  @override
  State<AdminAndroidHomePage> createState() => _AdminAndroidHomePageState();
}

class _AdminAndroidHomePageState extends State<AdminAndroidHomePage> {
  Store get store => widget.store;
  late bool showAds;
  late TextEditingController slots;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final c = AndroidHomeConfig.from(store.entries('settings'));
    showAds = c.showAds;
    slots = TextEditingController(text: '${c.adSlots}');
  }

  @override
  void dispose() {
    slots.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      final n = (int.tryParse(slots.text.trim()) ?? defaultAndroidAdSlots).clamp(1, 12);
      final fields = AndroidHomeConfig(adSlots: n, showAds: showAds).toFields();
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
        const Text('The ad boxes at the top of the Android app. The website has its own settings in the other pages of Settings; changing this does not change the website.'),
        const SizedBox(height: 16),
        SwitchListTile(
          key: const ValueKey('android-show-ads'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Show the ad boxes in the app'),
          value: showAds,
          onChanged: (on) => setState(() => showAds = on),
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
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerLeft, child: FilledButton(key: const ValueKey('save-android-home'), onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save'))),
      ],
    );
  }
}
