import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/domain/ad_reports.dart';
import 'package:ecommerce_app/domain/ads.dart';
import 'package:ecommerce_app/domain/android_home.dart';
import 'package:ecommerce_app/domain/catalog.dart';

void main() {
  group('Android home settings', () {
    test('with nothing saved the app shows two ad boxes, and the ads are shown', () {
      final c = AndroidHomeConfig.from([const Entry('adsConfig', {'mobileSlots': 1})]);
      expect((c.adSlots, c.showAds), (2, true));
    });

    test('saved slots and the ads switch are read', () {
      final c = AndroidHomeConfig.from([const Entry('androidHome', {'adSlots': 4, 'showAds': 'false'})]);
      expect((c.adSlots, c.showAds), (4, false));
    });

    test('nothing saved: the usual order, everything visible', () {
      const usual = ['ads', 'scrollingText', 'notice', 'quickFresh', 'promo', 'strip', 'popular', 'localServices', 'nearby'];
      final c = AndroidHomeConfig.from(const []);
      expect(c.arrange(usual), usual);
      expect(c.visibleOrder(usual), usual);
    });

    test('a saved order places those parts first, hidden parts are left out, unknown names are ignored', () {
      const usual = ['ads', 'scrollingText', 'notice', 'promo', 'nearby'];
      final c = AndroidHomeConfig.from([const Entry('androidHome', {'order': 'nearby,bogus,promo,nearby', 'hidden': 'notice,ads', 'showAds': 'true'})]);
      expect(c.arrange(usual), ['nearby', 'promo', 'ads', 'scrollingText', 'notice']);
      expect(c.visibleOrder(usual), ['nearby', 'promo', 'ads', 'scrollingText'], reason: 'notice hidden; ads follow showAds, not hidden');
      final noAds = AndroidHomeConfig.from([const Entry('androidHome', {'showAds': 'false'})]);
      expect(noAds.visibleOrder(usual), ['scrollingText', 'notice', 'promo', 'nearby']);
    });

    test('saving and reading back gives the same choice, and the website settings are not involved', () {
      const saved = AndroidHomeConfig(adSlots: 3, showAds: false, order: ['nearby', 'promo'], hidden: {'notice'});
      final back = AndroidHomeConfig.from([Entry(androidHomeId, saved.toFields())]);
      expect((back.adSlots, back.showAds), (3, false));
      expect(back.order, ['nearby', 'promo']);
      expect(back.hidden, {'notice'});
      final web = AdsConfig.from([Entry(androidHomeId, saved.toFields()), const Entry('adsConfig', {'desktopSlots': 4, 'mobileSlots': 1, 'seconds': 8})]);
      expect((web.desktopSlots, web.mobileSlots, web.seconds), (4, 1, 8));
    });
  });

  group('ad views: website, app, total', () {
    test('views counted before the app are website views', () {
      final t = AdTotals()..add({'views': 10, 'taps': 1});
      expect((t.views, t.webViews, t.appViews), (10, 10, 0));
    });

    test('app views are part of the total', () {
      final t = AdTotals()
        ..add({'views': 10})
        ..add({'views': 5, 'appViews': 5});
      expect((t.views, t.webViews, t.appViews), (15, 10, 5));
    });

    test('the report splits website and app, and the device filter agrees', () {
      final daily = [
        const Entry('a~1', {'adId': 'a', 'day': '2026-11-01', 'views': 3, 'appViews': 1, 'devices': {'web': {'views': 2}, 'android': {'views': 1}}}),
      ];
      final all = AdReport.build(daily);
      expect((all.total.views, all.total.webViews, all.total.appViews), (3, 2, 1));
      final app = AdReport.build(daily, device: 'android');
      expect((app.total.views, app.total.appViews), (1, 1));
      final web = AdReport.build(daily, device: 'web');
      expect((web.total.views, web.total.webViews), (2, 2));
    });
  });
}
