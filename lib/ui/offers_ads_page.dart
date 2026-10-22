import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/ads.dart';
import '../domain/catalog.dart';
import 'ad_box.dart';

/// "Offers & Ads": every ad that is live right now for the customer's location, one after another in the same box as on the home page.
class OffersAdsPage extends StatelessWidget {
  const OffersAdsPage({super.key, required this.store, required this.onAd});
  final Store store;
  final ValueChanged<Entry> onAd;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final config = AdsConfig.from(store.entries('settings'));
      final live = liveAds(store.entries('ads'), DateTime.now(), town: store.town, district: store.district, state: store.state, latitude: store.latitude, longitude: store.longitude);
      final width = MediaQuery.sizeOf(context).width;
      final columns = width >= 1100 ? 3 : width >= 700 ? 2 : 1;
      return Scaffold(
        appBar: AppBar(title: const Text('Offers & Ads')),
        body: live.isEmpty
            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No offers right now for your location. Please check again later.', textAlign: TextAlign.center)))
            : GridView.builder(
                key: const ValueKey('offers-ads-list'),
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: config.gap,
                  crossAxisSpacing: config.gap,
                  mainAxisExtent: config.boxHeight,
                ),
                itemCount: live.length,
                itemBuilder: (context, i) => AdBox(ad: live[i], config: config, onTap: onAd, mobile: width < 700),
              ),
      );
    },
  );
}
