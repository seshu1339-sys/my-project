import 'package:flutter/material.dart';

class AppLocale {
  const AppLocale._();

  static const supported = <Locale>[
    Locale('en'),
    Locale('as'),
    Locale('bn'),
    Locale('brx'),
    Locale('doi'),
    Locale('gu'),
    Locale('hi'),
    Locale('ks'),
    Locale('kn'),
    Locale('kok'),
    Locale('mai'),
    Locale('mni'),
    Locale('ml'),
    Locale('mr'),
    Locale('ne'),
    Locale('or'),
    Locale('pa'),
    Locale('sa'),
    Locale('sat'),
    Locale('sd'),
    Locale('ta'),
    Locale('te'),
    Locale('ur'),
  ];

  static const names = <String, String>{
    'en': 'English',
    'as': 'অসমীয়া',
    'bn': 'বাংলা',
    'brx': 'बड़ो',
    'doi': 'डोगरी',
    'gu': 'ગુજરાતી',
    'hi': 'हिन्दी',
    'ks': 'कॉशुर / کٲشُر',
    'kn': 'ಕನ್ನಡ',
    'kok': 'कोंकणी',
    'mai': 'मैथिली',
    'mni': 'মৈতৈলোন',
    'ml': 'മലയാളം',
    'mr': 'मराठी',
    'ne': 'नेपाली',
    'or': 'ଓଡ଼ିଆ',
    'pa': 'ਪੰਜਾਬੀ',
    'sa': 'संस्कृतम्',
    'sat': 'ᱥᱟᱱᱛᱟᱲᱤ',
    'sd': 'سنڌي',
    'ta': 'தமிழ்',
    'te': 'తెలుగు',
    'ur': 'اردو',
  };

  static Locale fromCode(String code) => supported.firstWhere(
    (locale) => locale.languageCode == code,
    orElse: () => supported.first,
  );

  static String detect(Iterable<Locale> locales) {
    for (final locale in locales) {
      if (supported.any((item) => item.languageCode == locale.languageCode)) {
        return locale.languageCode;
      }
    }
    return 'en';
  }

  static List<Locale> enabled(String value) {
    final codes = value
        .split(',')
        .map((code) => code.trim())
        .where((code) => code.isNotEmpty)
        .toSet();
    if (codes.isEmpty) return supported;
    codes.add('en');
    return supported
        .where((locale) => codes.contains(locale.languageCode))
        .toList();
  }

  static bool isRtl(String code) => code == 'ur';
}
