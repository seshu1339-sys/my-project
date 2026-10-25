import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Guards the module and section boundaries: which code each app (customer, admin, vendor, staff) can reach, which sections may know about
// which, and that the vendor sections stand alone. When one of these fails, a change has tied two parts together that were meant to be
// independent; fix the import (usually by moving the shared piece to a neutral file), do not loosen the rule.

Map<String, Set<String>> _graph() {
  final lib = Directory('lib');
  final files = [for (final f in lib.listSync(recursive: true)) if (f is File && f.path.endsWith('.dart')) f];
  String rel(String path) => path.replaceAll('\\', '/').replaceFirst(RegExp(r'^.*?lib/'), '');
  final graph = <String, Set<String>>{};
  for (final file in files) {
    final from = rel(file.path);
    final out = <String>{};
    for (final m in RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true).allMatches(file.readAsStringSync())) {
      final target = m.group(1)!;
      if (target.startsWith('dart:') || (target.startsWith('package:') && !target.startsWith('package:ecommerce_app/'))) continue;
      final resolved = target.startsWith('package:ecommerce_app/')
          ? target.substring('package:ecommerce_app/'.length)
          : Uri.parse('/${from.contains('/') ? from.substring(0, from.lastIndexOf('/')) : ''}/').resolve(target).path.substring(1);
      if (File('lib/$resolved').existsSync()) out.add(resolved);
    }
    graph[from] = out;
  }
  return graph;
}

Set<String> _reach(Map<String, Set<String>> graph, String entry) {
  final seen = <String>{};
  final stack = [entry];
  while (stack.isNotEmpty) {
    final f = stack.removeLast();
    if (!seen.add(f)) continue;
    stack.addAll(graph[f] ?? const {});
  }
  return seen;
}

List<String> _matching(Iterable<String> files, RegExp pattern) => [for (final f in files) if (pattern.hasMatch(f)) f]..sort();

void main() {
  final graph = _graph();

  group('what each app can reach', () {
    // Screens of the customer site and the admin panel: the vendor and staff apps must not carry them.
    final customerOnly = RegExp(r'^ui/(home_|layout_|animation_settings|wireframe|responsive_header|section_animations|page_widgets|notice_independence|offers_ads|storefront|cart_page|account|product_page|shop_page|shops_page|category_page|reviews|visual_|admin_|ai_agent|page_elements|element_groups)');

    test('the vendor app has none of the customer or admin screens', () {
      expect(_matching(_reach(graph, 'main_vendor.dart'), customerOnly), isEmpty);
    });

    test('the staff app has none of the customer, admin or vendor screens', () {
      expect(_matching(_reach(graph, 'main_field.dart'), RegExp('${customerOnly.pattern}|^ui/vendor_')), isEmpty);
    });

    test('the vendor app opens the Transport module page but carries no module admin screen and not the customer Services page', () {
      final reach = _reach(graph, 'main_vendor.dart');
      expect(reach, contains('modules/transport/transport_page.dart'));
      expect(_matching(reach, RegExp(r'^modules/(module_admin|modules).dart$|^modules/[^/]+/admin_|^modules/services/services_page')), isEmpty);
    });

    test('the staff app opens the Transport module page from Add, and carries no module admin screen', () {
      final reach = _reach(graph, 'main_field.dart');
      expect(reach, contains('modules/transport/transport_page.dart'));
      expect(_matching(reach, RegExp(r'^modules/(module_admin|modules).dart$|^modules/[^/]+/admin_')), isEmpty);
    });

    test('the vendor app does not carry the staff screens, and the staff app not the vendor ones', () {
      expect(_matching(_reach(graph, 'main_vendor.dart'), RegExp(r'^ui/field_')), isEmpty);
      expect(_matching(_reach(graph, 'main_field.dart'), RegExp(r'^ui/vendor_')), isEmpty);
    });
  });

  group('sections do not know each other', () {
    test('no home section, the header or the page file imports an admin, vendor, staff, Quick Add or AI screen', () {
      final bad = <String>[];
      for (final e in graph.entries) {
        if (!RegExp(r'^ui/(home_|responsive_header|wireframe_home)').hasMatch(e.key)) continue;
        for (final d in e.value) {
          if (RegExp(r'^ui/(admin_|vendor_|field_|quick_add|quick_admin|ai_agent|visual_)').hasMatch(d)) bad.add('${e.key} -> $d');
        }
      }
      expect(bad, isEmpty);
    });

    test('a home section imports the pieces it uses, not a barrel that pulls in other sections', () {
      final bad = <String>[];
      for (final e in graph.entries) {
        if (!RegExp(r'^ui/home_').hasMatch(e.key) || RegExp(r'^ui/home_(promotions|widgets)\.dart$').hasMatch(e.key)) continue;
        for (final d in e.value) {
          if (const {'ui/details.dart', 'ui/home_promotions.dart', 'ui/home_widgets.dart'}.contains(d)) bad.add('${e.key} -> $d');
        }
      }
      expect(bad, isEmpty);
    });

    test('the vendor sections only share the small kit, never each other', () {
      final bad = <String>[];
      for (final e in graph.entries) {
        if (!e.key.startsWith('ui/vendor_section_') || e.key == 'ui/vendor_section_kit.dart') continue;
        for (final d in e.value) {
          if (d.startsWith('ui/vendor_') && d != 'ui/vendor_section_kit.dart') bad.add('${e.key} -> $d');
        }
      }
      expect(bad, isEmpty);
      expect(graph.keys.where((f) => f.startsWith('ui/vendor_section_')).length, greaterThanOrEqualTo(6));
    });

    test('the Quick Add parts depend on the core and on each other only downwards (core imports no part)', () {
      expect(graph['ui/quick_add_core.dart']!.where((d) => d.startsWith('ui/quick_add_')), isEmpty);
    });

    test('the admin panel does not import the vendor sections', () {
      final bad = [for (final e in graph.entries) if (e.key.startsWith('ui/admin_')) for (final d in e.value) if (d.startsWith('ui/vendor_section_')) '${e.key} -> $d'];
      expect(bad, isEmpty);
    });
  });

  group('layers', () {
    test('domain code imports only domain code; services and data import no screens (only the shared design tokens and helpers)', () {
      final bad = <String>[];
      for (final e in graph.entries) {
        for (final d in e.value) {
          if (e.key.startsWith('domain/') && !d.startsWith('domain/')) bad.add('${e.key} -> $d');
          // the shared kernel: design tokens and the small helpers every app uses
          const kernel = {'ui/design_tokens.dart', 'ui/shared.dart'};
          if ((e.key.startsWith('services/') || e.key.startsWith('data/')) && d.startsWith('ui/') && !kernel.contains(d)) bad.add('${e.key} -> $d');
        }
      }
      expect(bad, isEmpty);
    });

    test('the helpers every app shares do not pull in the customer layout engine', () {
      expect(graph['ui/shared.dart']!.where((d) => d.startsWith('ui/') && d != 'ui/design_tokens.dart'), isEmpty);
    });
  });

  group('no tangles', () {
    test('no import cycles except the Store extensions and the shop page / product page pair', () {
      final index = <String, int>{}, low = <String, int>{}, onStack = <String>{}, stack = <String>[];
      final cycles = <List<String>>[];
      var counter = 0;
      void visit(String v) {
        index[v] = low[v] = counter++;
        stack.add(v);
        onStack.add(v);
        for (final w in graph[v] ?? const <String>{}) {
          if (!index.containsKey(w)) {
            visit(w);
            low[v] = low[v]! < low[w]! ? low[v]! : low[w]!;
          } else if (onStack.contains(w)) {
            low[v] = low[v]! < index[w]! ? low[v]! : index[w]!;
          }
        }
        if (low[v] == index[v]) {
          final group = <String>[];
          String w;
          do {
            w = stack.removeLast();
            onStack.remove(w);
            group.add(w);
          } while (w != v);
          if (group.length > 1) cycles.add(group..sort());
        }
      }

      for (final f in graph.keys) {
        if (!index.containsKey(f)) visit(f);
      }
      final allowed = {
        'data/store.dart,data/store_uploads.dart,data/store_vendor_actions.dart',
        'ui/product_page.dart,ui/shop_page.dart',
      };
      expect({for (final c in cycles) c.join(',')}.difference(allowed), isEmpty);
    });
  });
}
