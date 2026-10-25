import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The home modules (Transport, Services) must stay independent: each in its own folder, importing nothing from another module,
// nor from Shops, Promotions, vendor, Quick Add, admin or ads files. Removing or changing one must not break the others.

List<String> _imports(File file) => [
  for (final m in RegExp(r'''^import\s+['"]([^'"]+)['"]''', multiLine: true).allMatches(file.readAsStringSync())) m.group(1)!,
];

String _resolve(File from, String import) {
  if (import.startsWith('package:ecommerce_app/')) return 'lib/${import.substring('package:ecommerce_app/'.length)}';
  if (import.startsWith('package:') || import.startsWith('dart:')) return import;
  return Uri.file(from.path.replaceAll('\\', '/')).resolve(import).toFilePath(windows: false).replaceAll('\\', '/');
}

String _rel(String path) {
  final p = path.replaceAll('\\', '/');
  final i = p.indexOf('lib/');
  return i >= 0 ? p.substring(i) : p;
}

void main() {
  final modulesDir = Directory('lib/modules');
  final moduleIds = [
    for (final e in modulesDir.listSync())
      if (e is Directory) e.uri.pathSegments.where((s) => s.isNotEmpty).last,
  ];
  const forbidden = ['shop', 'promo', 'vendor', 'quick_add', 'admin', 'ads_', 'ad_box', 'home_', 'wireframe', 'storefront', 'store_'];

  test('there is a folder per module', () {
    expect(moduleIds, containsAll(['transport', 'services']));
  });

  for (final id in moduleIds) {
    test('module "$id" imports nothing from another module, the registry, Shops, Promotions, vendor, Quick Add, admin or ads', () {
      final files = Directory('lib/modules/$id').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
      expect(files, isNotEmpty);
      for (final file in files) {
        for (final import in _imports(file)) {
          final target = _rel(_resolve(file, import));
          if (target.startsWith('dart:') || target.startsWith('package:')) continue;
          final here = _rel(file.path);
          expect(target.startsWith('lib/modules/') && !target.startsWith('lib/modules/$id/') && target != 'lib/modules/home_module.dart', isFalse,
              reason: '$here imports another module: $import');
          expect(target, isNot('lib/modules/modules.dart'), reason: '$here imports the registry');
          expect(target, isNot('lib/modules/module_admin.dart'), reason: '$here imports the admin registry');
          if (target.startsWith('lib/ui/')) {
            final name = target.split('/').last;
            for (final word in forbidden) {
              expect(name.contains(word), isFalse, reason: '$here imports $import (a "$word" file)');
            }
          }
        }
      }
    });
  }

  test('outside code reaches a module only through the registries, the contract, a module file, or the Services listing helper', () {
    final allowed = {
      'lib/modules/modules.dart',
      'lib/modules/module_admin.dart',
      'lib/modules/home_module.dart',
      for (final id in moduleIds) 'lib/modules/$id/${id}_module.dart',
      'lib/modules/services/services_page.dart', // localServiceEntries, used by the home Local Services section
    };
    final all = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    for (final file in all) {
      final here = _rel(file.path);
      if (here.startsWith('lib/modules/')) continue;
      for (final import in _imports(file)) {
        final target = _rel(_resolve(file, import));
        if (target.startsWith('lib/modules/')) {
          expect(allowed.contains(target), isTrue, reason: '$here imports module internals: $import');
        }
      }
    }
  });

  test('every module has its own route name and they are all different', () {
    final routes = <String>[];
    for (final id in moduleIds) {
      final text = File('lib/modules/$id/${id}_module.dart').readAsStringSync();
      final m = RegExp("const ${id}Route = '(/[a-z-]+)'").firstMatch(text);
      expect(m, isNotNull, reason: '$id has no route constant');
      routes.add(m!.group(1)!);
    }
    expect(routes.toSet().length, routes.length);
  });

  test('a module file never imports its admin screen (so the vendor app can open a module without admin code)', () {
    for (final id in moduleIds) {
      final file = File('lib/modules/$id/${id}_module.dart');
      for (final import in _imports(file)) {
        expect(import.contains('admin'), isFalse, reason: '${file.path} imports $import');
      }
    }
  });
}
