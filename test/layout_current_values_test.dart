import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/layout_current_values.dart';
import 'package:ecommerce_app/ui/layout_editor.dart';
import 'package:ecommerce_app/ui/layout_settings.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('a blank or 0 field shows the default the site really uses', () {
    const none = Entry('x', {});
    expect(layoutBracketText('search', 'height', none), '56px');
    expect(layoutBracketText('search', 'iconSize', none), '20px');
    expect(layoutBracketText('search', 'gap', none), '2px');
    expect(layoutBracketText('logo', 'height', none), '36px');
    expect(layoutBracketText('logo', 'iconSize', none), '32px');
    expect(layoutBracketText('cartIcon', 'iconSize', none), '24px');
    expect(layoutBracketText('cartIcon', 'padding', none), '8px');
    expect(layoutBracketText('products', 'padding', none), '12px');
    expect(layoutBracketText('products', 'iconSize', none), '21px');
    expect(layoutBracketText('products', 'imageHeight', none, viewport: 390), '140px');
    expect(layoutBracketText('products', 'imageHeight', none, viewport: 1400), '180px');
    expect(layoutBracketText('nearby', 'height', none), '320px');
    expect(layoutBracketText('ads', 'height', none), '240px');
    expect(layoutBracketText('header', 'padding', none), '0px', reason: 'drawn in a section box: no inner padding');
    expect(layoutBracketText('products', 'mobileScale', none), '1');
    expect(layoutBracketText('products', 'width', none), 'automatic');
    expect(layoutBracketText('products', 'columns', none), 'automatic');
    expect(layoutBracketText('products', 'fontSize', none), 'theme default');
    expect(layoutBracketText('title', 'fontWeight', none), 'Extra bold');
  });

  test('a field that is set shows its own value', () {
    const set = Entry('x', {'height': 80, 'mobileScale': '1.2', 'iconSize': 0, 'textColor': '#112233', 'fontStyle': 'italic', 'visible': false});
    expect(layoutBracketText('search', 'height', set), '80px');
    expect(layoutBracketText('search', 'mobileScale', set), '1.2');
    expect(layoutBracketText('search', 'iconSize', set), '20px', reason: '0 means default');
    expect(layoutBracketText('search', 'textColor', set), '#112233');
    expect(layoutBracketText('search', 'fontStyle', set), 'Italic');
    expect(layoutBracketText('logo', 'visible', set), 'Off');
    expect(labelWithValue('Icon size', '24px'), 'Icon size (24px)');
    expect(layoutBracketText('office', 'text', set), isNull);
  });

  testWidgets('labels show the value, and change right after Save layout', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: LayoutFieldsForm(store: store, component: 'search')))));
    await tester.ensureVisible(find.text('Advanced'));
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.text('Height (0 = automatic) (56px)'), findsOneWidget);
    expect(find.text('Mobile scale (1)'), findsOneWidget);
    expect(find.text('Icon size (20px)'), findsOneWidget);
    // typing alone does not change it: it shows what the site uses now
    await tester.enterText(find.byKey(const ValueKey('search-height')), '90');
    await tester.pump();
    expect(find.text('Height (0 = automatic) (56px)'), findsOneWidget);
    expect(await tester.state<LayoutFieldsFormState>(find.byType(LayoutFieldsForm)).save(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Height (0 = automatic) (90px)'), findsOneWidget);
    expect(find.text('Height (0 = automatic) (56px)'), findsNothing);
  });

  test('every field of every component gets a bracket or is free text', () {
    const none = Entry('x', {});
    for (final component in layoutComponents.keys) {
      for (final key in allFieldsFor(component)) {
        final text = layoutBracketText(component, key, none);
        if (text == null) {
          expect(const {'text'}.contains(key), isTrue, reason: '$component.$key has no bracket');
        } else {
          expect(text.isNotEmpty, isTrue);
        }
      }
    }
  });
}
