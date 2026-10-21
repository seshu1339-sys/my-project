import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/ui/layout_editor.dart';
import 'package:ecommerce_app/ui/responsive_header_bar.dart';
import 'package:ecommerce_app/ui/text_animation.dart';

Future<Store> _store([Map<String, Map<String, dynamic>> sections = const {}]) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  for (final e in sections.entries) {
    await store.save('settings', Entry('section_${e.key}', {...e.value, 'section': e.key}));
  }
  return store;
}

void _wide(WidgetTester tester, [double width = 1600]) {
  tester.view.physicalSize = Size(width, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _form(WidgetTester tester, Store store, String component) async {
  _wide(tester, 1000);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LayoutFieldsForm(store: store, component: component),
        ),
      ),
    ),
  );
  // the exact pixel sizes (and their sliders) are under "Advanced"
  if (find.text('Advanced').evaluate().isNotEmpty) {
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
  }
}

const _bannerLabel = 'Banner text animation (e.g. "Big Savings Everyday")';
const _headingLabel = '"Today\'s Offers" heading animation';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('every number setting shows its current value, and the slider follows what is typed', (tester) async {
    final store = await _store({'categories': {'height': 180}});
    await _form(tester, store, 'categories');
    expect(find.byKey(const ValueKey('categories-height-current')), findsOneWidget);
    expect(find.text('Current value: 180 px'), findsOneWidget);
    expect(tester.widget<Slider>(find.byKey(const ValueKey('categories-height-slider'))).value, 180);
    // an unset setting says so instead of pretending to be at the minimum
    expect(find.text('Current value: not set (default)'), findsWidgets);
    // typing moves the slider and the label
    await tester.enterText(find.widgetWithText(TextFormField, 'Height (0 = automatic)'), '300');
    await tester.pump();
    expect(find.text('Current value: 300 px'), findsOneWidget);
    expect(tester.widget<Slider>(find.byKey(const ValueKey('categories-height-slider'))).value, 300);
  });

  testWidgets('dragging a slider writes the number into the saved setting', (tester) async {
    final store = await _store();
    await _form(tester, store, 'categories');
    final slider = find.byKey(const ValueKey('categories-radius-slider'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(60, 0));
    await tester.pump();
    final shown = RegExp(r'Current value: (\d+) px').firstMatch(
      tester.widget<Text>(find.byKey(const ValueKey('categories-radius-current'))).data!,
    );
    expect(shown, isNotNull);
    await tester.state<LayoutFieldsFormState>(find.byType(LayoutFieldsForm)).save();
    expect(
      store.entries('settings').firstWhere((e) => e.id == 'section_categories').number('radius'),
      double.parse(shown!.group(1)!),
    );
  });

  testWidgets('Search Box has its own colour for the search icon, mic, camera, placeholder and border', (tester) async {
    final store = await _store();
    await _form(tester, store, 'search');
    for (final label in ['Search icon color', 'Mic icon color', 'Camera icon color', 'Placeholder text color', 'Border color']) {
      expect(find.widgetWithText(InputDecorator, label), findsOneWidget, reason: label);
    }
  });

  testWidgets('the colour settings are only in the Search Box, not on other elements', (tester) async {
    final store = await _store();
    await _form(tester, store, 'categories');
    for (final label in ['Search icon color', 'Mic icon color', 'Camera icon color', 'Placeholder text color']) {
      expect(find.text(label), findsNothing, reason: label);
    }
  });

  testWidgets('the storefront search box uses the chosen colours', (tester) async {
    final store = await _store({
      'search': {'searchIconColor': '#112233', 'micIconColor': '#445566', 'cameraIconColor': '#778899', 'placeholderColor': '#AA0000'},
    });
    _wide(tester);
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    Color iconColor(IconData icon) => tester.widget<Icon>(find.byIcon(icon).first).color!;
    expect(iconColor(Icons.mic_none), const Color(0xFF445566));
    expect(iconColor(Icons.camera_alt_outlined), const Color(0xFF778899));
    final search = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.search).first);
    expect(search.style!.foregroundColor!.resolve({}), const Color(0xFF112233));
    final field = tester.widget<TextField>(
      find.descendant(of: find.byKey(const ValueKey('responsive-search-box')), matching: find.byType(TextField)),
    );
    expect(field.decoration!.hintStyle!.color, const Color(0xFFAA0000));
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('the logo can be changed from Layout Settings with an upload', (tester) async {
    final store = await _store();
    await _form(tester, store, 'logo');
    expect(find.widgetWithText(TextFormField, 'Icon image URL (optional)'), findsOneWidget);
    expect(find.text('Upload image'), findsOneWidget);
  });

  testWidgets('the storefront shows the uploaded logo', (tester) async {
    final store = await _store({'logo': {'iconUrl': 'https://example.test/logo.png'}});
    _wide(tester);
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    final urls = tester.widgetList<Image>(find.byType(Image)).map((i) => i.image).whereType<NetworkImage>().map((i) => i.url);
    expect(urls, contains('https://example.test/logo.png'));
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('Office address & phone: a text box, shown exactly as typed at the far right', (tester) async {
    const typed = 'Locamarket HQ\n12 Main Road, Rajahmundry 533101\n+91 98765 43210';
    final store = await _store({'office': {'text': typed}});
    await _form(tester, store, 'office');
    expect(find.widgetWithText(TextFormField, 'Office address and phone (shown exactly as typed)'), findsOneWidget);
    _wide(tester);
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    final office = find.text(typed);
    expect(office, findsOneWidget);
    expect(tester.getTopRight(office).dx, greaterThan(1600 - 60), reason: 'pinned to the right corner');
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('the header line runs from the left edge to the right edge of the screen', (tester) async {
    final store = await _store();
    _wide(tester);
    await tester.pumpWidget(MarketApp(store: store));
    await tester.pump();
    final header = find.byType(ResponsiveHeader);
    expect(tester.getTopLeft(header).dx, 0);
    expect(tester.getSize(header).width, 1600);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('Option 15 (banner carousel) has animation choices for its texts', (tester) async {
    final store = await _store();
    await _form(tester, store, 'promo');
    expect(find.widgetWithText(DropdownButtonFormField<String>, _headingLabel), findsOneWidget);
    final dropdown = find.widgetWithText(DropdownButtonFormField<String>, _bannerLabel);
    expect(dropdown, findsOneWidget);
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zoom in').last);
    await tester.pumpAndSettle();
    await tester.state<LayoutFieldsFormState>(find.byType(LayoutFieldsForm)).save();
    expect(store.entries('settings').firstWhere((e) => e.id == 'section_promo').text('textAnimation'), 'zoom');
  });

  testWidgets('an animated text plays its animation and none leaves the text alone', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            animatedText(const Entry('a', {'textAnimation': 'slideUp'}), 'textAnimation', const Text('Big Savings Everyday')),
            animatedText(const Entry('b', {}), 'textAnimation', const Text('Plain')),
          ],
        ),
      ),
    );
    expect(find.byType(TextEffect), findsOneWidget);
    final before = tester.getTopLeft(find.text('Big Savings Everyday')).dy;
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.getTopLeft(find.text('Big Savings Everyday')).dy, lessThan(before));
    expect(find.text('Plain'), findsOneWidget);
  });

  group('3D text animations', () {
    const threeD = ['flip3d', 'rotate3d', 'spin', 'flipLeft', 'flipRight', 'cube'];

    test('the six new options are offered alongside the original seven', () {
      expect(textAnimationLabels.keys, containsAll(['fade', 'slideUp', 'slideLeft', 'slideRight', 'zoom', 'bounce', 'pulse']));
      expect(textAnimationLabels.keys, containsAll(threeD));
      expect(textAnimationLabels.length, 13);
      expect(textAnimationLabels['flip3d'], startsWith('3D Flip'));
      expect(textAnimationLabels['rotate3d'], startsWith('3D Rotate'));
      expect(textAnimationLabels['spin'], startsWith('Spin in'));
      expect(textAnimationLabels['flipLeft'], 'Flip from left');
      expect(textAnimationLabels['flipRight'], 'Flip from right');
      expect(textAnimationLabels['cube'], startsWith('Cube rotate'));
    });

    for (final type in threeD) {
      testWidgets('$type starts turned away and settles flat; animations stay off when not chosen', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: animatedText(Entry('a', {'textAnimation': type}), 'textAnimation', const Text('Hello')),
          ),
        );
        Matrix4 matrix() => tester
            .widgetList<Transform>(find.descendant(of: find.byType(TextEffect), matching: find.byType(Transform)))
            .map((t) => t.transform)
            .first;
        final start = matrix();
        expect(start.isIdentity(), isFalse, reason: 'starts turned');
        // perspective (Matrix4 setEntry(3, 2, 0.001)) shows up in the bottom row once turned
        if (type != 'spin') expect([start.entry(3, 0), start.entry(3, 1), start.entry(3, 2)].any((v) => v.abs() > 1e-6), isTrue, reason: 'with perspective');
        await tester.pump(const Duration(milliseconds: 900));
        final end = matrix();
        for (final i in [0, 5, 10]) {
          expect(end.storage[i], closeTo(1, 1e-6), reason: 'flat at the end ($i)');
        }
        if (type != 'spin') expect(end.entry(3, 2), closeTo(0.001, 1e-9), reason: 'perspective kept');
        for (final i in [1, 2, 4, 6, 8, 9]) {
          expect(end.storage[i], closeTo(0, 1e-6), reason: 'no tilt at the end ($i)');
        }
        expect(find.text('Hello'), findsOneWidget);
      });
    }

    testWidgets('an unset or unknown animation adds no effect at all (off by default)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              animatedText(const Entry('a', {}), 'textAnimation', const Text('One')),
              animatedText(const Entry('b', {'textAnimation': 'none'}), 'textAnimation', const Text('Two')),
            ],
          ),
        ),
      );
      expect(find.byType(TextEffect), findsNothing);
    });

    testWidgets('each new option can be picked in the #15 dropdown and is saved', (tester) async {
      for (final entry in {
        'flip3d': '3D Flip (flips in on the horizontal axis)',
        'rotate3d': '3D Rotate (turns in on the vertical axis)',
        'spin': 'Spin in (360 degrees while appearing)',
        'flipLeft': 'Flip from left',
        'flipRight': 'Flip from right',
        'cube': 'Cube rotate (turns like a cube face)',
      }.entries) {
        final store = await _store();
        await _form(tester, store, 'promo');
        final dropdown = find.widgetWithText(DropdownButtonFormField<String>, _bannerLabel);
        await tester.ensureVisible(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.value).last);
        await tester.pumpAndSettle();
        await tester.state<LayoutFieldsFormState>(find.byType(LayoutFieldsForm)).save();
        expect(store.entries('settings').firstWhere((e) => e.id == 'section_promo').text('textAnimation'), entry.key);
        await tester.pumpWidget(const SizedBox());
        store.dispose();
      }
    });
  });
}
