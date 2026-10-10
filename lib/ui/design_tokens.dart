import 'package:flutter/material.dart';

/// Visual fallback defaults for the storefront's premium redesign. Every
/// value here is only ever used as the *fallback* passed into
/// colorFromHex/entryDecoration/sectionTextStyle (shared.dart) or into
/// MarketApp's theme builder (main.dart) — an admin-set Firestore value on
/// `settings/theme` or any `settings/section_*` doc always wins. Nothing
/// here bypasses that mechanism; it only changes what "unset" looks like.
class AppTokens {
  AppTokens._();

  // Brand — matches the current reference design's warm red/orange palette
  // (also set as the admin-configurable settings/theme default via
  // scripts/set-theme-colors.cjs; both agree so nothing looks mismatched
  // whichever code path a given widget happens to read through).
  static const primary = Color(0xff16a34a);
  static const primaryDark = Color(0xff0f7a37);
  static const primaryLight = Color(0xffdcfce7);

  // Accent rotation for ad/box/offer cards and category tiles, so a stack of
  // several cards reads as a varied, premium palette rather than monochrome.
  static const accentOrange = Color(0xffff8a3d);
  static const accentBlue = Color(0xff2f80ed);
  static const accentPurple = Color(0xff8e5cf6);
  static const accentGold = Color(0xffe0a400);
  static const accentRed = Color(0xffe4483c);
  static const accentGreen = Color(0xff16a34a);

  static const cardAccents = [primary, accentRed, accentOrange, accentBlue, accentPurple, accentGold];
  static const cardTints = [primaryLight, Color(0xfffde7e4), Color(0xfffff1e6), Color(0xffe8f0fd), Color(0xfff2ecfe), Color(0xfffdf3da)];

  static const background = Color(0xfffff8f0);
  static const surface = Colors.white;
  static const border = Color(0xffe6eae3);
  static const textPrimary = Color(0xff16241c);
  static const textMuted = Color(0xff5b6b61);

  // Spacing scale (px).
  static const space4 = 4.0;
  static const space8 = 8.0;
  static const space12 = 12.0;
  static const space16 = 16.0;
  static const space20 = 20.0;
  static const space24 = 24.0;
  static const space32 = 32.0;

  // Radius scale (px).
  static const radiusSm = 12.0;
  static const radiusMd = 16.0;
  static const radiusLg = 20.0;

  static List<BoxShadow> get shadowSoft => [
    BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 18, offset: const Offset(0, 6)),
  ];

  static List<BoxShadow> get shadowCard => [
    BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 24, offset: const Offset(0, 10)),
  ];

  static Color accentFor(int index) => cardAccents[index % cardAccents.length];
  static Color tintFor(int index) => cardTints[index % cardTints.length];
}
