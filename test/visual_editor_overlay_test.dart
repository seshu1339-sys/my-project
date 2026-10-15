import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/ui/visual_editor_overlay.dart';

void main() {
  group('SectionTapRegion', () {
    testWidgets('a tap on the wrapped content selects the section, never the content\'s own onTap', (tester) async {
      final selection = EditorSelection();
      var selected = '';
      var innerTapped = false;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SectionTapRegion(
        sectionKey: 'popular',
        label: 'Popular',
        selection: selection,
        onSelect: (key) => selected = key,
        child: GestureDetector(
          onTap: () => innerTapped = true,
          child: const SizedBox(width: 200, height: 100, child: Text('product card')),
        ),
      ))));
      await tester.tap(find.byKey(const ValueKey('section-tap-popular')));
      await tester.pump();
      expect(selected, 'popular');
      expect(innerTapped, isFalse,
          reason: 'AbsorbPointer must stop the tap from also reaching the real content underneath');
      selection.dispose();
    });

    testWidgets('once selected, the content stays non-interactive too', (tester) async {
      final selection = EditorSelection()..value = 'popular';
      var innerTapped = false;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SectionTapRegion(
        sectionKey: 'popular',
        label: 'Popular',
        selection: selection,
        onSelect: (_) {},
        child: GestureDetector(
          onTap: () => innerTapped = true,
          child: const SizedBox(width: 200, height: 100, child: Text('product card')),
        ),
      ))));
      await tester.tap(find.text('product card'));
      await tester.pump();
      expect(innerTapped, isFalse);
      selection.dispose();
    });

    testWidgets('a dimmed (other-section-selected) region is also non-interactive', (tester) async {
      final selection = EditorSelection()..value = 'other-section';
      var innerTapped = false;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SectionTapRegion(
        sectionKey: 'popular',
        label: 'Popular',
        selection: selection,
        onSelect: (_) {},
        child: GestureDetector(
          onTap: () => innerTapped = true,
          child: const SizedBox(width: 200, height: 100, child: Text('product card')),
        ),
      ))));
      await tester.tap(find.text('product card'));
      await tester.pump();
      expect(innerTapped, isFalse);
      selection.dispose();
    });
  });

  group('SectionTapRegion resize handles', () {
    Widget host({
      required EditorSelection selection,
      ValueListenable<LiveResize?>? liveResize,
      VoidCallback? onHeightStart,
      ValueChanged<double>? onHeightUpdate,
      VoidCallback? onHeightEnd,
      VoidCallback? onWidthStart,
      ValueChanged<double>? onWidthUpdate,
      VoidCallback? onWidthEnd,
      VoidCallback? onCornerStart,
      ValueChanged<Offset>? onCornerUpdate,
      VoidCallback? onCornerEnd,
    }) => MaterialApp(home: Scaffold(body: SectionTapRegion(
      sectionKey: 'popular',
      label: 'Popular',
      selection: selection,
      onSelect: (_) {},
      liveResize: liveResize,
      onHeightDragStart: onHeightStart,
      onHeightDragUpdate: onHeightUpdate,
      onHeightDragEnd: onHeightEnd,
      onWidthDragStart: onWidthStart,
      onWidthDragUpdate: onWidthUpdate,
      onWidthDragEnd: onWidthEnd,
      onCornerDragStart: onCornerStart,
      onCornerDragUpdate: onCornerUpdate,
      onCornerDragEnd: onCornerEnd,
      child: const SizedBox(width: 200, height: 100, child: Text('product card')),
    )));

    // All eight: four side-centers (top/bottom/left/right) + four corners
    // (tl/tr/bl/br).
    const sideKeys = [
      ValueKey('resize-handle-top-popular'),
      ValueKey('resize-handle-popular'), // bottom — pre-existing key, unchanged
      ValueKey('resize-handle-left-popular'),
      ValueKey('resize-handle-width-popular'), // right — pre-existing key, unchanged
    ];
    const cornerKeys = [
      ValueKey('resize-handle-corner-tl-popular'),
      ValueKey('resize-handle-corner-tr-popular'),
      ValueKey('resize-handle-corner-bl-popular'),
      ValueKey('resize-handle-corner-br-popular'),
    ];

    testWidgets('no resize handles render while the section is unselected', (tester) async {
      final selection = EditorSelection();
      await tester.pumpWidget(host(
        selection: selection,
        liveResize: ValueNotifier(null),
        onHeightUpdate: (_) {},
        onWidthUpdate: (_) {},
        onCornerUpdate: (_) {},
      ));
      for (final key in [...sideKeys, ...cornerKeys]) {
        expect(find.byKey(key), findsNothing, reason: '$key must not render while unselected');
      }
      selection.dispose();
    });

    testWidgets('all eight handles render exactly once when selected and wired', (tester) async {
      final selection = EditorSelection()..value = 'popular';
      await tester.pumpWidget(host(
        selection: selection,
        liveResize: ValueNotifier(null),
        onHeightUpdate: (_) {},
        onWidthUpdate: (_) {},
        onCornerUpdate: (_) {},
      ));
      for (final key in [...sideKeys, ...cornerKeys]) {
        expect(find.byKey(key), findsOneWidget, reason: '$key must render exactly once when selected');
      }
      selection.dispose();
    });

    testWidgets('side handles are omitted when their own callback is absent; corners need onCornerDragUpdate', (tester) async {
      final selection = EditorSelection()..value = 'popular';
      await tester.pumpWidget(host(selection: selection, liveResize: ValueNotifier(null), onHeightUpdate: (_) {}));
      expect(find.byKey(const ValueKey('resize-handle-top-popular')), findsOneWidget);
      expect(find.byKey(const ValueKey('resize-handle-popular')), findsOneWidget);
      expect(find.byKey(const ValueKey('resize-handle-left-popular')), findsNothing);
      expect(find.byKey(const ValueKey('resize-handle-width-popular')), findsNothing);
      for (final key in cornerKeys) {
        expect(find.byKey(key), findsNothing);
      }
      selection.dispose();
    });

    testWidgets('every handle stays fully inside the section\'s own bounds (no overflow onto a sibling)', (tester) async {
      final selection = EditorSelection()..value = 'popular';
      await tester.pumpWidget(host(
        selection: selection,
        liveResize: ValueNotifier(null),
        onHeightUpdate: (_) {},
        onWidthUpdate: (_) {},
        onCornerUpdate: (_) {},
      ));
      final regionRect = tester.getRect(find.byKey(const ValueKey('section-tap-popular')));
      for (final key in [...sideKeys, ...cornerKeys]) {
        final handleRect = tester.getRect(find.byKey(key));
        expect(
          regionRect.contains(handleRect.topLeft) && regionRect.contains(handleRect.bottomRight - const Offset(1, 1)),
          isTrue,
          reason: '$key at $handleRect must stay within the section\'s own box $regionRect — '
              'any handle poking outside it risks being painted over by the next section in the page.',
        );
      }
      selection.dispose();
    });

    testWidgets('dragging the bottom (height) handle forwards the vertical delta as-is', (tester) async {
      final selection = EditorSelection()..value = 'popular';
      var started = false, ended = false;
      double? forwarded;
      await tester.pumpWidget(host(
        selection: selection,
        liveResize: ValueNotifier(null),
        onHeightStart: () => started = true,
        onHeightUpdate: (dy) => forwarded = dy,
        onHeightEnd: () => ended = true,
      ));
      final gd = tester.widget<GestureDetector>(find.byKey(const ValueKey('resize-handle-popular')));
      gd.onVerticalDragStart!(DragStartDetails());
      gd.onVerticalDragUpdate!(DragUpdateDetails(delta: const Offset(0, 7), globalPosition: Offset.zero));
      gd.onVerticalDragEnd!(DragEndDetails());
      expect(started, isTrue);
      expect(forwarded, 7.0, reason: 'dragging the bottom edge down should grow the section (positive)');
      expect(ended, isTrue);
      selection.dispose();
    });

    testWidgets('dragging the top (height) handle inverts the sign — dragging up grows', (tester) async {
      final selection = EditorSelection()..value = 'popular';
      var started = false, ended = false;
      double? forwarded;
      await tester.pumpWidget(host(
        selection: selection,
        liveResize: ValueNotifier(null),
        onHeightStart: () => started = true,
        onHeightUpdate: (dy) => forwarded = dy,
        onHeightEnd: () => ended = true,
      ));
      final gd = tester.widget<GestureDetector>(find.byKey(const ValueKey('resize-handle-top-popular')));
      gd.onVerticalDragStart!(DragStartDetails());
      gd.onVerticalDragUpdate!(DragUpdateDetails(delta: const Offset(0, 7), globalPosition: Offset.zero));
      gd.onVerticalDragEnd!(DragEndDetails());
      expect(started, isTrue);
      expect(forwarded, -7.0, reason: 'dragging the top edge DOWN should shrink — same magnitude, opposite sign from the bottom handle');
      expect(ended, isTrue);
      selection.dispose();
    });

    testWidgets('dragging the right (width) handle forwards the horizontal delta as-is', (tester) async {
      final selection = EditorSelection()..value = 'popular';
      var started = false, ended = false;
      double? forwarded;
      await tester.pumpWidget(host(
        selection: selection,
        liveResize: ValueNotifier(null),
        onWidthStart: () => started = true,
        onWidthUpdate: (dx) => forwarded = dx,
        onWidthEnd: () => ended = true,
      ));
      final gd = tester.widget<GestureDetector>(find.byKey(const ValueKey('resize-handle-width-popular')));
      gd.onHorizontalDragStart!(DragStartDetails());
      gd.onHorizontalDragUpdate!(DragUpdateDetails(delta: const Offset(9, 0), globalPosition: Offset.zero));
      gd.onHorizontalDragEnd!(DragEndDetails());
      expect(started, isTrue);
      expect(forwarded, 9.0);
      expect(ended, isTrue);
      selection.dispose();
    });

    testWidgets('dragging the left (width) handle inverts the sign — dragging left grows', (tester) async {
      final selection = EditorSelection()..value = 'popular';
      var started = false, ended = false;
      double? forwarded;
      await tester.pumpWidget(host(
        selection: selection,
        liveResize: ValueNotifier(null),
        onWidthStart: () => started = true,
        onWidthUpdate: (dx) => forwarded = dx,
        onWidthEnd: () => ended = true,
      ));
      final gd = tester.widget<GestureDetector>(find.byKey(const ValueKey('resize-handle-left-popular')));
      gd.onHorizontalDragStart!(DragStartDetails());
      gd.onHorizontalDragUpdate!(DragUpdateDetails(delta: const Offset(9, 0), globalPosition: Offset.zero));
      gd.onHorizontalDragEnd!(DragEndDetails());
      expect(started, isTrue);
      expect(forwarded, -9.0);
      expect(ended, isTrue);
      selection.dispose();
    });

    // The four corners: each must forward (dx*signX, dy*signY) so dragging
    // outward (away from the section's center) always grows, regardless of
    // which corner — this is the real-design-tool convention.
    final cornerExpectations = <ValueKey<String>, Offset>{
      const ValueKey('resize-handle-corner-tl-popular'): const Offset(-3, -5),
      const ValueKey('resize-handle-corner-tr-popular'): const Offset(3, -5),
      const ValueKey('resize-handle-corner-bl-popular'): const Offset(-3, 5),
      const ValueKey('resize-handle-corner-br-popular'): const Offset(3, 5),
    };
    for (final entry in cornerExpectations.entries) {
      testWidgets('dragging ${entry.key} forwards ${entry.value} for a (3,5) raw drag', (tester) async {
        final selection = EditorSelection()..value = 'popular';
        var started = false, ended = false;
        Offset? forwarded;
        await tester.pumpWidget(host(
          selection: selection,
          liveResize: ValueNotifier(null),
          onCornerStart: () => started = true,
          onCornerUpdate: (d) => forwarded = d,
          onCornerEnd: () => ended = true,
        ));
        final gd = tester.widget<GestureDetector>(find.byKey(entry.key));
        gd.onPanStart!(DragStartDetails());
        gd.onPanUpdate!(DragUpdateDetails(delta: const Offset(3, 5), globalPosition: Offset.zero));
        gd.onPanEnd!(DragEndDetails());
        expect(started, isTrue);
        expect(forwarded, entry.value);
        expect(ended, isTrue);
        selection.dispose();
      });
    }

    testWidgets('the ghost outline is absent until a live resize is active for this section', (tester) async {
      final selection = EditorSelection()..value = 'popular';
      final live = ValueNotifier<LiveResize?>(null);
      final ghost = find.byKey(const ValueKey('ghost-outline-popular'));
      await tester.pumpWidget(host(selection: selection, liveResize: live, onHeightUpdate: (_) {}));
      expect(ghost, findsNothing, reason: 'no ghost outline while nothing is live');
      live.value = const LiveResize('popular', baseHeight: 240, baseWidth: 600, height: 300);
      await tester.pump();
      expect(ghost, findsOneWidget, reason: 'ghost outline appears once this section is live-resizing');
      live.value = const LiveResize('other-section', baseHeight: 240, baseWidth: 600, height: 300);
      await tester.pump();
      expect(ghost, findsNothing, reason: 'ghost outline must not show for a different section');
      selection.dispose();
      live.dispose();
    });

    testWidgets('the live dimension badge shows the in-progress value in pixels', (tester) async {
      final selection = EditorSelection()..value = 'popular';
      final live = ValueNotifier<LiveResize?>(null);
      await tester.pumpWidget(host(selection: selection, liveResize: live, onHeightUpdate: (_) {}));
      expect(find.text('300px'), findsNothing);
      live.value = const LiveResize('popular', baseHeight: 240, baseWidth: 600, height: 300);
      await tester.pump();
      // Both the top and bottom height handles show the same live value —
      // there's one shared height, not a separate value per handle.
      expect(find.text('300px'), findsNWidgets(2));
      selection.dispose();
      live.dispose();
    });
  });
}
