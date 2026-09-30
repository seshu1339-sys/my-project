// GeoTargetPicker: the admin map-drawing widget for a promotion's target
// area. Covers the two behaviors the picker is specifically responsible for
// (booking-overlap detection with a manual override, and the immediate-
// enable path when there is no conflict) using its `initial*` constructor
// params directly — no map-tap gesture simulation needed, since those params
// already exercise the exact same in-progress-shape code path a real tap
// would produce.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/geo_target_picker.dart';

Future<void> _openPicker(
  WidgetTester tester,
  void Function(GeoTargetResult?) onResult, {
  required List<Entry> promotions,
  String? excludeId,
  DateTime? windowStart,
  DateTime? windowEnd,
  String initialShape = 'circle',
  double initialLatitude = 0,
  double initialLongitude = 0,
  double initialRadiusKm = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await Navigator.push<GeoTargetResult>(
                context,
                MaterialPageRoute(
                  builder: (_) => GeoTargetPicker(
                    promotions: promotions,
                    excludeId: excludeId,
                    windowStart: windowStart,
                    windowEnd: windowEnd,
                    initialShape: initialShape,
                    initialLatitude: initialLatitude,
                    initialLongitude: initialLongitude,
                    initialRadiusKm: initialRadiusKm,
                  ),
                ),
              );
              onResult(result);
            },
            child: const Text('Open picker'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open picker'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a circle with no booked conflicts shows no warning and confirms immediately', (tester) async {
    GeoTargetResult? result;
    await _openPicker(
      tester,
      (r) => result = r,
      promotions: const [],
      initialLatitude: 12.97,
      initialLongitude: 77.59,
      initialRadiusKm: 8,
    );

    expect(find.textContaining('overlaps an active booking'), findsNothing);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Use this area'));
    expect(button.onPressed, isNotNull);

    await tester.tap(find.text('Use this area'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.shape, 'circle');
    expect(result!.latitude, 12.97);
    expect(result!.longitude, 77.59);
    expect(result!.radiusKm, 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an overlapping circle is blocked until the override checkbox is checked', (tester) async {
    const booked = Entry('other', {
      'name': 'Existing ad',
      'active': true,
      'geoShape': 'circle',
      'targetLatitude': 12.97,
      'targetLongitude': 77.59,
      'targetRadiusKm': 10,
    });
    GeoTargetResult? result;
    await _openPicker(
      tester,
      (r) => result = r,
      promotions: const [booked],
      initialLatitude: 12.97,
      initialLongitude: 77.59,
      initialRadiusKm: 5,
    );

    expect(find.textContaining('Existing ad'), findsOneWidget);
    var button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Use this area'));
    expect(button.onPressed, isNull);

    // A disabled FilledButton ignores taps — confirm the picker really is
    // blocked, not just that the button looks disabled.
    await tester.tap(find.text('Use this area'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(result, isNull);

    await tester.tap(find.text('Save anyway (override this overlap)'));
    await tester.pumpAndSettle();
    button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Use this area'));
    expect(button.onPressed, isNotNull);

    await tester.tap(find.text('Use this area'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.shape, 'circle');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a booking outside the edited promotion\'s own display window is not a conflict', (tester) async {
    const booked = Entry('other', {
      'name': 'Long-past ad',
      'active': true,
      'geoShape': 'circle',
      'targetLatitude': 12.97,
      'targetLongitude': 77.59,
      'targetRadiusKm': 10,
      'startsAt': '2020-01-01T00:00:00.000Z',
      'endsAt': '2020-02-01T00:00:00.000Z',
    });
    GeoTargetResult? result;
    await _openPicker(
      tester,
      (r) => result = r,
      promotions: const [booked],
      windowStart: DateTime.utc(2026, 1, 1),
      windowEnd: DateTime.utc(2026, 2, 1),
      initialLatitude: 12.97,
      initialLongitude: 77.59,
      initialRadiusKm: 5,
    );

    expect(find.textContaining('overlaps an active booking'), findsNothing);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Use this area'));
    expect(button.onPressed, isNotNull);
    await tester.tap(find.text('Use this area'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the promotion being edited never conflicts with itself', (tester) async {
    const self = Entry('promo1', {
      'name': 'This promo',
      'active': true,
      'geoShape': 'circle',
      'targetLatitude': 12.97,
      'targetLongitude': 77.59,
      'targetRadiusKm': 10,
    });
    GeoTargetResult? result;
    await _openPicker(
      tester,
      (r) => result = r,
      promotions: const [self],
      excludeId: 'promo1',
      initialLatitude: 12.97,
      initialLongitude: 77.59,
      initialRadiusKm: 5,
    );

    expect(find.textContaining('overlaps an active booking'), findsNothing);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Use this area'));
    expect(button.onPressed, isNotNull);
    await tester.tap(find.text('Use this area'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
