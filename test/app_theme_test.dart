import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/services/app_theme.dart';

void main() {
  // The live theme document has fontSize 12. On Android the default text theme leaves some sizes unset,
  // and scaling them used to trip an assertion (a red error screen in debug builds of the Android app).
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.windows]) {
    for (final dark in [false, true]) {
      test('a theme with fontSize 12 builds on $platform (dark: $dark)', () async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        SharedPreferences.setMockInitialValues({});
        final store = Store();
        await store.init();
        store.catalog['settings'] = const [
          Entry('theme', {'fontSize': 12, 'fontWeight': 600, 'mode': 'light'}),
        ];
        final theme = buildAppTheme(store, dark: dark);
        expect(theme.textTheme.bodyMedium, isNotNull);
        final size = theme.textTheme.bodyMedium!.fontSize;
        if (size != null) expect(size, lessThan(14), reason: 'a sized style is scaled by 12/14');
        store.dispose();
      });
    }
  }

  test('the default font size leaves the theme exactly as before', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    store.catalog['settings'] = const [Entry('theme', {'fontSize': 14})];
    expect(() => buildAppTheme(store, dark: false), returnsNormally);
    store.dispose();
  });
}
