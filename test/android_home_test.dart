import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/domain/ad_reports.dart';
import 'package:ecommerce_app/domain/ads.dart';
import 'package:ecommerce_app/domain/android_home.dart';
import 'package:ecommerce_app/domain/catalog.dart';

void main() {
  group('Android home settings', () {
    test('with nothing saved the app starts from the website\'s phone value and the default order, everything shown', () {
      final c = AndroidHomeConfig.from([const Entry('adsConfig', {'mobileSlots': 2})]);
      expect(c.adSlots, 2);
      expect(c.visibleParts, androidHomeParts);
    });

    test('saved slots, order and hidden parts are read; missing and unknown parts are handled', () {
      final c = AndroidHomeConfig.from([const Entry('androidHome', {'adSlots': 4, 'order': 'ads,notice,bogus', 'hidden': 'boxes,nonsense'})]);
      expect(c.adSlots, 4);
      expect(c.order, ['ads', 'notice', 'scrollingText', 'promo', 'boxes']);
      expect(c.visibleParts, ['ads', 'notice', 'scrollingText', 'promo']);
    });

    test('saving and reading back gives the same choice, and the website settings are not involved', () {
      const saved = AndroidHomeConfig(adSlots: 3, order: ['promo', 'ads', 'notice', 'scrollingText', 'boxes'], hidden: {'notice'});
      final back = AndroidHomeConfig.from([Entry(androidHomeId, saved.toFields())]);
      expect(back.adSlots, 3);
      expect(back.order, saved.order);
      expect(back.hidden, saved.hidden);
      // the website's ad settings are what they were
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
