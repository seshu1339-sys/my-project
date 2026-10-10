import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../ui/design_tokens.dart';
import '../ui/shared.dart';

/// Resolves the merchant's `settings/theme` doc into a real `ThemeMode`.
/// Pulled out of `main.dart` (was a private method on `MarketApp`) so the
/// admin Visual Editor can build the same themed preview the customer app
/// actually sees — `AdminEntryApp` otherwise never reads this doc at all.
ThemeMode resolveThemeMode(Store store) {
  final mode = store
      .entries('settings')
      .firstWhere(
        (entry) => entry.id == 'theme',
        orElse: () => const Entry('theme', {}),
      )
      .text('mode', 'light');
  return mode == 'dark' ? ThemeMode.dark : ThemeMode.light;
}

/// Resolves the merchant's `settings/theme` doc into a real `ThemeData`, for
/// the given brightness. Pulled out of `main.dart` verbatim — identical
/// output, now reusable by the admin Visual Editor's live preview.
ThemeData buildAppTheme(Store store, {required bool dark}) {
  final settings = store
      .entries('settings')
      .firstWhere(
        (entry) => entry.id == 'theme',
        orElse: () => const Entry('theme', {}),
      );
  final primary = colorFromHex(
    settings.text(dark ? 'darkPrimary' : 'primary'),
    AppTokens.primary,
  );
  final background = colorFromHex(
    settings.text(dark ? 'darkBackground' : 'background'),
    dark ? const Color(0xff101512) : AppTokens.background,
  );
  final surface = colorFromHex(
    settings.text(dark ? 'darkSurface' : 'surface'),
    dark ? const Color(0xff1a211d) : AppTokens.surface,
  );
  final text = colorFromHex(
    settings.text(dark ? 'darkText' : 'text'),
    dark ? Colors.white : Colors.black87,
  );
  final appBar = colorFromHex(
    settings.text(dark ? 'darkAppBar' : 'appBar'),
    background,
  );
  final secondary = colorFromHex(
    settings.text(dark ? 'darkSecondary' : 'secondary'),
    primary,
  );
  final fontFamily = settings.text('fontFamily').trim();
  final fontSize = settings.number('fontSize', 14).clamp(10, 30).toDouble();
  final fontWeight = FontWeight.values.firstWhere(
    (weight) => weight.value == settings.number('fontWeight', 400).round(),
    orElse: () => FontWeight.normal,
  );
  final textTheme =
      ThemeData(brightness: dark ? Brightness.dark : Brightness.light)
          .textTheme
          .apply(
            fontFamily: fontFamily.isEmpty ? 'Arial' : fontFamily,
            bodyColor: text,
            displayColor: text,
            fontSizeFactor: fontSize / 14,
          );
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: dark ? Brightness.dark : Brightness.light,
    ).copyWith(secondary: secondary),
    scaffoldBackgroundColor: background,
    fontFamily: fontFamily.isEmpty ? 'Arial' : fontFamily,
    textTheme: textTheme.copyWith(
      bodyMedium: textTheme.bodyMedium?.copyWith(fontWeight: fontWeight),
      bodyLarge: textTheme.bodyLarge?.copyWith(fontWeight: fontWeight),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: AppTokens.surface,
    ),
    cardTheme: CardThemeData(elevation: 0, color: surface),
    appBarTheme: AppBarTheme(
      backgroundColor: appBar,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
