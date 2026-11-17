import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/reach.dart';
import '../data/store.dart';
import '../domain/ads.dart';
import '../domain/catalog.dart';
import '../domain/right_boxes.dart' show rightBoxPlaceholder;
import '../services/ad_tracker.dart';
import '../services/server_clock.dart';
import 'ad_box.dart';
import 'ad_visibility.dart';

/// True while the plans page is open: the bottom ad is then about 30% of the screen's height (owner, 13 Nov 2026), so the vendor sees
/// the ads right where they choose a plan. It is 72 px everywhere else.
final ValueNotifier<bool> appBottomAdTall = ValueNotifier<bool>(false);
const appBottomAdTallShare = 0.3;

/// Puts [AppBottomAd] under every page of the vendor or staff app once someone is signed in. Hidden while the keyboard is open, so
/// it never pushes a form field off the screen.
Widget withAppBottomAd(BuildContext context, Widget? child, Store store, {bool staff = false}) {
  final page = child ?? const SizedBox.shrink();
  if (store.user == null || MediaQuery.viewInsetsOf(context).bottom > 0) return page;
  return Column(children: [
    Expanded(child: MediaQuery.removePadding(context: context, removeBottom: true, child: page)),
    AppBottomAd(store: store, staff: staff),
  ]);
}

/// The ad box at the bottom of the vendor app ([staff] false) and the staff app. It shows the ads the admin aimed at vendors (only
/// those for the vendor's own shop category, when the ad names categories) or at staff ([appAds]), one at a time, each for its
/// seconds. With none live it shows the "your ad here" text. Views and taps are counted like the website's ads (AdsTracker).
class AppBottomAd extends StatefulWidget {
  const AppBottomAd({super.key, required this.store, this.staff = false, this.uid, this.tracker, this.now});
  final Store store;
  final bool staff;
  // The vendor whose shop category decides; null = the signed-in user.
  final String? uid;
  // The tracker to count with; null = AdsTracker.instance, started by the app.
  final AdsTracker? tracker;
  final DateTime Function()? now;

  static const height = 72.0;

  @override
  State<AppBottomAd> createState() => _AppBottomAdState();
}

class _AppBottomAdState extends State<AppBottomAd> {
  int index = 0;
  Timer? rotate, seen;
  String? viewedId;
  DateTime? viewedAt;

  // The server's time, never the phone's: an ad leaves the box exactly when it ends (lib/services/server_clock.dart).
  DateTime get now => (widget.now ?? ServerClock.now)();
  AdsTracker? get tracker => widget.tracker ?? AdsTracker.instance;

  String get shopCategory {
    if (widget.staff) return '';
    final uid = widget.uid ?? widget.store.user?.uid;
    return widget.store.entries('shops').where((s) => s.id == uid || s.text('ownerId') == uid).firstOrNull?.text('category') ?? '';
  }

  /// Where the viewer is: a vendor at their own shop, staff (or a vendor without a shop point) where the app's location is.
  (double, double)? get place {
    final store = widget.store;
    if (!widget.staff) {
      final uid = widget.uid ?? store.user?.uid;
      final shop = store.entries('shops').where((s) => s.id == uid || s.text('ownerId') == uid).firstOrNull;
      final lat = shop?.number('latitude'), lng = shop?.number('longitude');
      if (lat != null && lng != null && !(lat == 0 && lng == 0)) return (lat, lng);
    }
    return store.located ? (store.latitude!, store.longitude!) : null;
  }

  /// An ad posted for a place shows only within the admin's km of its shop (lib/domain/ads.dart appAds).
  bool _reaches(Entry ad) {
    final here = place;
    if (here == null) return false;
    final shop = widget.store.entries('shops').where((s) => s.id == linkedShopId(ad)).firstOrNull;
    return shopWithinKm(shop, here.$1, here.$2, widget.store.reachKm);
  }

  List<Entry> get ads => appAds(widget.store.entries('ads'), now, staff: widget.staff, shopCategory: shopCategory, reaches: _reaches);

  Entry? get current {
    final list = ads;
    return list.isEmpty ? null : list[index % list.length];
  }

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_changed);
    _show();
  }

  void _changed() {
    if (!mounted) return;
    final shown = current;
    setState(() {});
    // A new first ad (or the last one ending) starts its own time and view.
    if (current?.id != shown?.id || rotate == null) _show();
  }

  /// Starts the current ad: a view after one second mostly on screen, then the next ad after its seconds.
  void _show() {
    _leave();
    rotate?.cancel();
    seen?.cancel();
    final ad = current;
    if (ad == null) {
      rotate = null;
      return;
    }
    seen = Timer(const Duration(seconds: 1), () {
      if (!mounted || current?.id != ad.id || !adMostlyOnScreen(context)) return;
      tracker?.view(ad.id);
      viewedId = ad.id;
      viewedAt = now;
    });
    rotate = Timer(Duration(seconds: adSeconds(ad, AdsConfig.from(widget.store.entries('settings')))), () {
      if (!mounted) return;
      setState(() => index++);
      _show();
    });
  }

  /// The seconds the ad that just went stayed on screen after its view.
  void _leave() {
    final id = viewedId, at = viewedAt;
    if (id != null && at != null) tracker?.time(id, now.difference(at).inSeconds - 1);
    viewedId = null;
    viewedAt = null;
  }

  Future<void> _open(Entry ad) async {
    tracker?.tap(ad.id);
    final target = adTarget(ad);
    // A shop page lives in the customer app, not here.
    if (target.isEmpty || target.startsWith('shop:')) return;
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      /* An ad that cannot open must not break the app. */
    }
  }

  @override
  void dispose() {
    _leave();
    rotate?.cancel();
    seen?.cancel();
    widget.store.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = current;
    final config = AdsConfig.from(widget.store.entries('settings'));
    return Material(
      key: const ValueKey('app-bottom-ad'),
      elevation: 6,
      child: SafeArea(
        top: false,
        child: ValueListenableBuilder<bool>(
          valueListenable: appBottomAdTall,
          builder: (context, tall, child) => SizedBox(height: tall ? MediaQuery.sizeOf(context).height * appBottomAdTallShare : AppBottomAd.height, child: child),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: ad == null
                ? DecoratedBox(
                    key: const ValueKey('app-bottom-ad-empty'),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(config.radius)),
                    child: Center(child: Text(rightBoxPlaceholder, style: Theme.of(context).textTheme.titleSmall)),
                  )
                : AdBox(key: ValueKey('app-bottom-ad-${ad.id}'), ad: ad, config: config, mobile: true, onTap: _open),
          ),
        ),
      ),
    );
  }
}
