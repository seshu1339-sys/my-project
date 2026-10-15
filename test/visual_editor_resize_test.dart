import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/ui/visual_editor_overlay.dart';

// These tests exercise ResizeController directly — the real drag/commit
// state machine used by VisualEditorPage's resize handles — with no widget
// tree involved at all. Pumping the full VisualEditorPage (which mounts the
// real, live WireframeHome preview: network images, carousel/promo timers,
// Firestore snapshot listeners) is a known, pre-existing hang/stack-overflow
// trap in this project's test environment, confirmed unrelated to this
// logic — no existing test in this project has ever pumped that combination,
// and switching between simulated gestures and direct callback invocation
// made no difference, since the failure came from WireframeHome itself, not
// from anything resize-specific. Testing ResizeController in isolation
// exercises the exact same production code with none of that risk.
void main() {
  group('ResizeController', () {
    test('dragging height writes exactly once, on release, and only the height field', () async {
      final writes = <String>[];
      final resize = ResizeController();
      resize.start('popular', baseHeight: 240, baseWidth: 600);
      for (var i = 0; i < 5; i++) {
        resize.updateHeight('popular', 5);
      }
      expect(writes, isEmpty, reason: 'no write should happen while the drag is still live');
      await resize.end(
        'popular',
        saveHeight: (h) async {
          writes.add('height:$h');
        },
        saveWidth: (w) async {
          writes.add('width:$w');
        },
      );
      expect(writes, ['height:265.0']);
      resize.dispose();
    });

    test('dragging width writes exactly once, on release, and only the width field', () async {
      final writes = <String>[];
      final resize = ResizeController();
      resize.start('popular', baseHeight: 240, baseWidth: 600);
      for (var i = 0; i < 5; i++) {
        resize.updateWidth('popular', 5);
      }
      expect(writes, isEmpty);
      await resize.end(
        'popular',
        saveHeight: (h) async {
          writes.add('height:$h');
        },
        saveWidth: (w) async {
          writes.add('width:$w');
        },
      );
      expect(writes, ['width:625.0']);
      resize.dispose();
    });

    test('dragging the corner writes both axes exactly once each, on release', () async {
      final writes = <String>[];
      final resize = ResizeController();
      resize.start('popular', baseHeight: 240, baseWidth: 600);
      for (var i = 0; i < 5; i++) {
        resize.updateCorner('popular', const Offset(4, 4));
      }
      expect(writes, isEmpty);
      await resize.end(
        'popular',
        saveHeight: (h) async {
          writes.add('height:$h');
        },
        saveWidth: (w) async {
          writes.add('width:$w');
        },
      );
      expect(writes, ['height:260.0', 'width:620.0']);
      resize.dispose();
    });

    test('starting a second drag while one is already live on the same section is a no-op (guards re-entry)', () async {
      final writes = <String>[];
      final resize = ResizeController();
      resize.start('popular', baseHeight: 240, baseWidth: 600);
      resize.updateHeight('popular', 20);
      resize.start('popular', baseHeight: 999, baseWidth: 999); // must not reset the live base back to this
      await resize.end(
        'popular',
        saveHeight: (h) async {
          writes.add('height:$h');
        },
        saveWidth: (w) async {
          writes.add('width:$w');
        },
      );
      expect(writes, ['height:260.0']);
      resize.dispose();
    });

    test('updates for a different section than the one that started the drag are ignored', () async {
      final resize = ResizeController();
      resize.start('popular', baseHeight: 240, baseWidth: 600);
      resize.updateHeight('notice', 500); // not the live section — must be a no-op
      final live = resize.live.value!;
      expect(live.key, 'popular');
      expect(live.height, isNull);
      resize.dispose();
    });

    test('height clamps to the 40-1200 range', () async {
      final resize = ResizeController();
      resize.start('popular', baseHeight: 240, baseWidth: 600);
      resize.updateHeight('popular', -10000);
      expect(resize.live.value!.height, 40.0);
      resize.updateHeight('popular', 100000);
      expect(resize.live.value!.height, 1200.0);
      resize.dispose();
    });

    test('width clamps to the 80-3840 range', () async {
      final resize = ResizeController();
      resize.start('popular', baseHeight: 240, baseWidth: 600);
      resize.updateWidth('popular', -10000);
      expect(resize.live.value!.width, 80.0);
      resize.updateWidth('popular', 100000);
      expect(resize.live.value!.width, 3840.0);
      resize.dispose();
    });
  });
}
