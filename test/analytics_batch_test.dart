// Visitor counters in batches (free-limit plan, 17 Nov 2026): a visit goes at once (with whatever waits); ad views and taps wait up to
// 15 seconds and go together in one call; 30 waiting go at once. Fewer server calls, the same counts.
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/services/analytics.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Map<String, Object?>> calls;
  setUp(() {
    calls = [];
    Analytics.resetForTest();
    Analytics.testTransport = (d) async => calls.add(d);
  });
  tearDown(() => Analytics.testTransport = null);

  List<String> types(Map<String, Object?> call) => [for (final e in call['events'] as List) '${(e as Map)['type']}'];

  test('views and taps of 15 seconds go in one call', () {
    fakeAsync((async) {
      Analytics.impression(const Entry('ad1', {'placement': 'box'}));
      Analytics.impression(const Entry('ad2', {'placement': 'box'}));
      Analytics.click(const Entry('ad1', {'placement': 'box'}));
      async.elapse(const Duration(seconds: 14));
      expect(calls, isEmpty);
      async.elapse(const Duration(seconds: 2));
      expect(calls, hasLength(1));
      expect(types(calls.single), ['adImpression', 'adImpression', 'adClick']);
      expect(calls.single['visitorId'], '0123456789abcdef0123');
    });
  });

  test('an ad seen again within 30 minutes is not counted again; 30 waiting go at once', () {
    fakeAsync((async) {
      Analytics.impression(const Entry('same', {}));
      Analytics.impression(const Entry('same', {}));
      for (var i = 0; i < 29; i++) {
        Analytics.impression(Entry('ad$i', const {}));
      }
      async.flushMicrotasks();
      expect(calls, hasLength(1), reason: '30 waiting: sent without waiting for the timer');
      expect((calls.single['events'] as List).length, 30);
    });
  });

  test('the app going to the background sends what waits', () async {
    Analytics.impression(const Entry('ad9', {}));
    await Analytics.flush();
    expect(types(calls.single), ['adImpression']);
    await Analytics.flush();
    expect(calls, hasLength(1), reason: 'nothing more to send');
  });
}
