import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Which layout section key is currently selected in the admin Visual
/// Editor, or `null` for none. Lives for the lifetime of one
/// `VisualEditorPage` — never a global/app-wide notion of selection.
class EditorSelection extends ValueNotifier<String?> {
  EditorSelection() : super(null);
}

/// Live (non-persisted) resize state for the Visual Editor's drag handles.
/// Written directly by `_VisualEditorPageState`'s resize handlers — never via
/// `setState` — so a resize drag never rebuilds anything above the one
/// `ValueListenableBuilder` inside the dragged section's own `SectionTapRegion`.
/// `baseHeight`/`baseWidth` are the committed values when the drag started;
/// `height`/`width` are the live in-progress values, null on the axis/axes not
/// currently being dragged (so the ghost outline only grows/shrinks on the
/// axis the admin is actually moving, and only that axis gets written at the
/// end — a pure-height drag must never also stamp a width value).
class LiveResize {
  const LiveResize(this.key, {required this.baseHeight, required this.baseWidth, this.height, this.width});
  final String key;
  final double baseHeight;
  final double baseWidth;
  final double? height;
  final double? width;
}

/// The resize drag state machine: live (non-persisted) size while a drag is
/// in progress, committed to Firestore exactly once per axis at release.
/// Pure logic with no widget-tree dependency, so it's testable without
/// mounting the real homepage preview (`WireframeHome`) at all — pumping
/// that full live tree in a widget test is a known, pre-existing hang/crash
/// trap in this project's test environment, unrelated to this logic.
class ResizeController {
  final ValueNotifier<LiveResize?> _live = ValueNotifier(null);
  ValueListenable<LiveResize?> get live => _live;

  void start(String key, {required double baseHeight, required double baseWidth}) {
    final current = _live.value;
    if (current != null && current.key == key) return; // a handle on this section is already mid-drag
    _live.value = LiveResize(key, baseHeight: baseHeight, baseWidth: baseWidth);
  }

  void updateHeight(String key, double deltaY) {
    final current = _live.value;
    if (current == null || current.key != key) return;
    final next = ((current.height ?? current.baseHeight) + deltaY).clamp(40.0, 1200.0);
    _live.value = LiveResize(key, baseHeight: current.baseHeight, baseWidth: current.baseWidth, height: next, width: current.width);
  }

  void updateWidth(String key, double deltaX) {
    final current = _live.value;
    if (current == null || current.key != key) return;
    final next = ((current.width ?? current.baseWidth) + deltaX).clamp(80.0, 3840.0);
    _live.value = LiveResize(key, baseHeight: current.baseHeight, baseWidth: current.baseWidth, height: current.height, width: next);
  }

  void updateCorner(String key, Offset delta) {
    final current = _live.value;
    if (current == null || current.key != key) return;
    final nextH = ((current.height ?? current.baseHeight) + delta.dy).clamp(40.0, 1200.0);
    final nextW = ((current.width ?? current.baseWidth) + delta.dx).clamp(80.0, 3840.0);
    _live.value = LiveResize(key, baseHeight: current.baseHeight, baseWidth: current.baseWidth, height: nextH, width: nextW);
  }

  // Writes only the axis(es) actually dragged — a pure-height drag must
  // never also stamp a width value onto the section, and vice versa. This is
  // the ONLY Firestore write the whole gesture makes: no mid-drag writes, so
  // no echo-triggered rebuild storm.
  Future<void> end(String key, {required Future<void> Function(double) saveHeight, required Future<void> Function(double) saveWidth}) async {
    final current = _live.value;
    _live.value = null;
    if (current == null || current.key != key) return;
    if (current.height != null) await saveHeight(current.height!);
    if (current.width != null) await saveWidth(current.width!);
  }

  void dispose() => _live.dispose();
}

enum _ResizeAxis { height, width }

/// The small pill on a resize handle showing the live dimension while a drag
/// on that axis is active (e.g. "320px"), or a plain drag icon otherwise.
/// Listens to [liveResize] directly so only this pill repaints during a drag,
/// not the whole page.
class _ResizeBadge extends StatelessWidget {
  const _ResizeBadge({required this.liveResize, required this.sectionKey, required this.axis, this.vertical = false});
  final ValueListenable<LiveResize?> liveResize;
  final String sectionKey;
  final _ResizeAxis axis;
  final bool vertical;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<LiveResize?>(
    valueListenable: liveResize,
    builder: (context, live, _) {
      final value = live != null && live.key == sectionKey
          ? (axis == _ResizeAxis.height ? live.height : live.width)
          : null;
      return Container(
        width: vertical ? 20 : 56,
        height: vertical ? 56 : 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTokens.primary,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: value != null
            ? Text('${value.round()}px', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))
            : const Icon(Icons.drag_handle, size: 14, color: Colors.white),
      );
    },
  );
}

/// An editable pixel-value control: shows [valuePx] as a whole number of
/// pixels with a "px" suffix, +/- buttons (10px per tap), and a text field
/// for typing an exact value — whatever number is typed becomes exactly
/// that many pixels, clamped to [minPx]/[maxPx] (the same bounds
/// `ResizeController` enforces for a live drag), never reinterpreted as a
/// percentage. All three paths call [onChangedPx] — one commit path shared
/// with dragging a resize handle, a typed entry, and +/-, not three
/// separate ones.
class PixelField extends StatefulWidget {
  const PixelField({
    super.key,
    required this.label,
    required this.valuePx,
    required this.minPx,
    required this.maxPx,
    required this.onChangedPx,
  });
  final String label;
  final double valuePx;
  final double minPx;
  final double maxPx;
  final ValueChanged<double> onChangedPx;

  @override
  State<PixelField> createState() => _PixelFieldState();
}

class _PixelFieldState extends State<PixelField> {
  late final TextEditingController _controller;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.valuePx.round().toString());
  }

  @override
  void didUpdateWidget(PixelField old) {
    super.didUpdateWidget(old);
    // Never overwrite what the admin is actively typing — only resync the
    // displayed text from an external change (e.g. a drag elsewhere) while
    // this field doesn't have focus.
    if (!_focus.hasFocus && old.valuePx != widget.valuePx) {
      _controller.text = widget.valuePx.round().toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commitPx(double px) => widget.onChangedPx(px.clamp(widget.minPx, widget.maxPx).toDouble());

  void _nudge(double deltaPx) => _commitPx(widget.valuePx + deltaPx);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(width: 48, child: Text(widget.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
      IconButton(
        key: ValueKey('px-minus-${widget.label}'),
        icon: const Icon(Icons.remove_circle_outline, size: 18),
        tooltip: 'Decrease by 10px',
        onPressed: () => _nudge(-10),
      ),
      SizedBox(
        width: 76,
        child: TextField(
          key: ValueKey('px-field-${widget.label}'),
          controller: _controller,
          focusNode: _focus,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(isDense: true, suffixText: 'px', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8)),
          onSubmitted: (text) {
            final parsed = double.tryParse(text.trim());
            if (parsed != null) _commitPx(parsed);
          },
        ),
      ),
      IconButton(
        key: ValueKey('px-plus-${widget.label}'),
        icon: const Icon(Icons.add_circle_outline, size: 18),
        tooltip: 'Increase by 10px',
        onPressed: () => _nudge(10),
      ),
    ],
  );
}

/// Wraps one homepage section inside the Visual Editor's live preview:
/// unselected while nothing (or something else) is selected it renders the
/// section completely unchanged; while another section is selected it dims
/// and ignores pointer events; while THIS section is selected it draws a
/// highlight border, a real drag-to-resize handle on its bottom edge, and
/// (when `reorderable` is true) a real drag-to-reorder handle — both are
/// genuine pointer-drag gestures, not buttons. This is pure composition
/// around the child, never a widget-type swap, so a running
/// `AnimationController` inside (HeroCarousel, ScheduledPromo) is never torn
/// down by selecting, dragging or resizing a section.
class SectionTapRegion extends StatelessWidget {
  const SectionTapRegion({
    super.key,
    required this.sectionKey,
    required this.label,
    required this.selection,
    required this.onSelect,
    this.reorderable = false,
    this.onReorderDrop,
    this.liveResize,
    this.onHeightDragStart,
    this.onHeightDragUpdate,
    this.onHeightDragEnd,
    this.onWidthDragStart,
    this.onWidthDragUpdate,
    this.onWidthDragEnd,
    this.onCornerDragStart,
    this.onCornerDragUpdate,
    this.onCornerDragEnd,
    this.number,
    this.showNumber = false,
    required this.child,
  });
  final String sectionKey;
  final String label;
  final EditorSelection selection;
  final ValueChanged<String> onSelect;
  final bool reorderable;
  // The element's permanent admin-facing number (lib/ui/page_elements.dart),
  // or null while this section hasn't been numbered yet. Shown as a small
  // badge whenever [showNumber] is true, regardless of selection state --
  // unlike the [label] chip above (which only appears on the currently
  // selected section), this is meant to be visible on every numbered
  // element at once, so an admin can see "which part is which" while
  // toggled on. Default off: it must never affect an unrelated render.
  final int? number;
  final bool showNumber;
  // Called with the dragged section's key when it's dropped onto this one.
  final ValueChanged<String>? onReorderDrop;
  // Drives the ghost-outline overlay and the live dimension badges while a
  // resize drag is active on this section. Never written via setState —
  // updating it only rebuilds the narrow ValueListenableBuilders below.
  final ValueListenable<LiveResize?>? liveResize;
  final VoidCallback? onHeightDragStart;
  final ValueChanged<double>? onHeightDragUpdate; // delta dy this callback
  final VoidCallback? onHeightDragEnd;
  final VoidCallback? onWidthDragStart;
  final ValueChanged<double>? onWidthDragUpdate; // delta dx this callback
  final VoidCallback? onWidthDragEnd;
  final VoidCallback? onCornerDragStart;
  final ValueChanged<Offset>? onCornerDragUpdate; // delta (dx,dy) this callback
  final VoidCallback? onCornerDragEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: selection,
    builder: (context, selected, _) {
      final isSelected = selected == sectionKey;
      final isDimmed = selected != null && !isSelected;
      // The real rendered homepage content has its own interactive taps
      // (product cards, category tiles, "add to cart"...). With the outer
      // tap-to-select GestureDetector below using HitTestBehavior.translucent,
      // Flutter's gesture arena lets a tap on this content ALSO fire the
      // content's own onTap at the same time — a tap meant to select this
      // section for editing could instead (or also) trigger a live-site-only
      // action. AbsorbPointer blocks ALL pointer delivery into the content
      // unconditionally, in every state, so only the outer section-select tap
      // and the explicit resize/drag handles (Stack siblings below, not
      // descendants of content) can ever receive input.
      Widget content = AbsorbPointer(absorbing: true, child: child);
      if (isDimmed) {
        content = AnimatedOpacity(
          opacity: .35,
          duration: const Duration(milliseconds: 150),
          child: content,
        );
      }
      Widget region = GestureDetector(
        key: ValueKey('section-tap-$sectionKey'),
        behavior: HitTestBehavior.translucent,
        onTap: selected == null ? () => onSelect(sectionKey) : null,
        child: Container(
          decoration: isSelected
              ? BoxDecoration(
                  border: Border.all(color: AppTokens.primary, width: 2),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              content,
              if (showNumber && number != null)
                Positioned(
                  key: ValueKey('number-badge-$sectionKey'),
                  top: 4,
                  left: 4,
                  child: IgnorePointer(
                    child: Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Colors.black87,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)],
                      ),
                      child: Text(
                        '$number',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              if (isSelected) ...[
                Positioned(
                  top: 4,
                  right: 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Material(
                        color: AppTokens.primary,
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      if (reorderable) ...[
                        const SizedBox(width: 4),
                        Draggable<String>(
                          key: ValueKey('drag-handle-$sectionKey'),
                          data: sectionKey,
                          feedback: Material(
                            color: Colors.transparent,
                            child: _HandleIcon(icon: Icons.drag_indicator, filled: true),
                          ),
                          childWhenDragging: _HandleIcon(icon: Icons.drag_indicator, dim: true),
                          child: const Tooltip(
                            message: 'Drag to reorder',
                            child: _HandleIcon(icon: Icons.drag_indicator),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Ghost outline: shows exactly how much bigger/smaller this
                // section will become, with zero knowledge of its real
                // rendered pixel size. Giving a Positioned both left+right
                // (or top+bottom) sizes it to stackSize - left - right, so a
                // negative right/bottom extends it past the real content's
                // edge by exactly the live drag delta. Pure local state —
                // zero Firestore round-trips while the drag is live.
                if (liveResize != null)
                  ValueListenableBuilder<LiveResize?>(
                    valueListenable: liveResize!,
                    builder: (context, live, _) {
                      if (live == null || live.key != sectionKey) return const SizedBox.shrink();
                      final dw = (live.width ?? live.baseWidth) - live.baseWidth;
                      final dh = (live.height ?? live.baseHeight) - live.baseHeight;
                      if (dw == 0 && dh == 0) return const SizedBox.shrink();
                      return Positioned(
                        key: ValueKey('ghost-outline-$sectionKey'),
                        left: 0,
                        top: 0,
                        right: -dw,
                        bottom: -dh,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppTokens.primary.withValues(alpha: .08),
                              border: Border.all(color: AppTokens.primary, width: 2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                // Eight resize handles — four side-centers (each moves one
                // axis) and four corners (each moves both). All eight sit at
                // a small POSITIVE inset from the edge, fully inside this
                // section's own Stack — never a negative offset overflowing
                // past it. That overflow was the real bug behind "handles
                // not visible": a Positioned that overflows a Column child's
                // bounds paints fine on its own, but the NEXT section in the
                // page's Column paints after (on top of) that overflow,
                // silently hiding whatever poked into its territory. Staying
                // fully inside this section's own box means nothing here can
                // ever be painted over by a sibling, regardless of paint
                // order. Top/left handles reuse the exact same
                // onHeightDrag*/onWidthDrag* callbacks as bottom/right (only
                // the delta's sign flips, right at the call site below) —
                // dragging the top edge up or the left edge left grows the
                // section, matching ordinary resize-handle conventions —
                // so no change to ResizeController or the caller is needed.
                if (onHeightDragUpdate != null) ...[
                  Positioned(
                    top: 2,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        key: ValueKey('resize-handle-top-$sectionKey'),
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: (_) => onHeightDragStart?.call(),
                        onVerticalDragUpdate: (d) => onHeightDragUpdate!(-d.delta.dy),
                        onVerticalDragEnd: (_) => onHeightDragEnd?.call(),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeRow,
                          child: _ResizeBadge(liveResize: liveResize!, sectionKey: sectionKey, axis: _ResizeAxis.height),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 2,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        key: ValueKey('resize-handle-$sectionKey'),
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: (_) => onHeightDragStart?.call(),
                        onVerticalDragUpdate: (d) => onHeightDragUpdate!(d.delta.dy),
                        onVerticalDragEnd: (_) => onHeightDragEnd?.call(),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeRow,
                          child: _ResizeBadge(liveResize: liveResize!, sectionKey: sectionKey, axis: _ResizeAxis.height),
                        ),
                      ),
                    ),
                  ),
                ],
                if (onWidthDragUpdate != null) ...[
                  Positioned(
                    left: 2,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: GestureDetector(
                        key: ValueKey('resize-handle-left-$sectionKey'),
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (_) => onWidthDragStart?.call(),
                        onHorizontalDragUpdate: (d) => onWidthDragUpdate!(-d.delta.dx),
                        onHorizontalDragEnd: (_) => onWidthDragEnd?.call(),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: _ResizeBadge(liveResize: liveResize!, sectionKey: sectionKey, axis: _ResizeAxis.width, vertical: true),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: GestureDetector(
                        key: ValueKey('resize-handle-width-$sectionKey'),
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (_) => onWidthDragStart?.call(),
                        onHorizontalDragUpdate: (d) => onWidthDragUpdate!(d.delta.dx),
                        onHorizontalDragEnd: (_) => onWidthDragEnd?.call(),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: _ResizeBadge(liveResize: liveResize!, sectionKey: sectionKey, axis: _ResizeAxis.width, vertical: true),
                        ),
                      ),
                    ),
                  ),
                ],
                if (onCornerDragUpdate != null) ...[
                  _cornerHandle(
                    sectionKey: sectionKey,
                    keySuffix: 'tl',
                    top: 2,
                    left: 2,
                    cursor: SystemMouseCursors.resizeUpLeftDownRight,
                    signX: -1,
                    signY: -1,
                    onStart: onCornerDragStart,
                    onUpdate: onCornerDragUpdate!,
                    onEnd: onCornerDragEnd,
                  ),
                  _cornerHandle(
                    sectionKey: sectionKey,
                    keySuffix: 'tr',
                    top: 2,
                    right: 2,
                    cursor: SystemMouseCursors.resizeUpRightDownLeft,
                    signX: 1,
                    signY: -1,
                    onStart: onCornerDragStart,
                    onUpdate: onCornerDragUpdate!,
                    onEnd: onCornerDragEnd,
                  ),
                  _cornerHandle(
                    sectionKey: sectionKey,
                    keySuffix: 'bl',
                    bottom: 2,
                    left: 2,
                    cursor: SystemMouseCursors.resizeUpRightDownLeft,
                    signX: -1,
                    signY: 1,
                    onStart: onCornerDragStart,
                    onUpdate: onCornerDragUpdate!,
                    onEnd: onCornerDragEnd,
                  ),
                  _cornerHandle(
                    sectionKey: sectionKey,
                    keySuffix: 'br',
                    bottom: 2,
                    right: 2,
                    cursor: SystemMouseCursors.resizeUpLeftDownRight,
                    signX: 1,
                    signY: 1,
                    onStart: onCornerDragStart,
                    onUpdate: onCornerDragUpdate!,
                    onEnd: onCornerDragEnd,
                  ),
                ],
              ],
            ],
          ),
        ),
      );
      if (reorderable && onReorderDrop != null) {
        region = DragTarget<String>(
          onWillAcceptWithDetails: (details) => details.data != sectionKey,
          onAcceptWithDetails: (details) => onReorderDrop!(details.data),
          builder: (context, candidates, _) => candidates.isEmpty
              ? region
              : DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTokens.accentGold, width: 3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: region,
                ),
        );
      }
      return region;
    },
  );
}

/// One corner resize handle, fully inside the section's own bounds (see the
/// doc comment above its call sites in [SectionTapRegion.build] for why).
/// [signX]/[signY] flip the raw drag delta so dragging a top/left corner
/// outward (up/left) grows the section exactly like dragging a bottom/right
/// corner outward (down/right) does.
Widget _cornerHandle({
  required String sectionKey,
  required String keySuffix,
  double? top,
  double? bottom,
  double? left,
  double? right,
  required MouseCursor cursor,
  required double signX,
  required double signY,
  required VoidCallback? onStart,
  required ValueChanged<Offset> onUpdate,
  required VoidCallback? onEnd,
}) => Positioned(
  top: top,
  bottom: bottom,
  left: left,
  right: right,
  child: GestureDetector(
    key: ValueKey('resize-handle-corner-$keySuffix-$sectionKey'),
    behavior: HitTestBehavior.opaque,
    onPanStart: (_) => onStart?.call(),
    onPanUpdate: (d) => onUpdate(Offset(d.delta.dx * signX, d.delta.dy * signY)),
    onPanEnd: (_) => onEnd?.call(),
    child: MouseRegion(
      cursor: cursor,
      child: const _HandleIcon(icon: Icons.open_in_full, filled: true),
    ),
  ),
);

class _HandleIcon extends StatelessWidget {
  const _HandleIcon({required this.icon, this.filled = false, this.dim = false});
  final IconData icon;
  final bool filled, dim;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: dim ? .3 : 1,
    child: Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? AppTokens.primary : Colors.black87,
        shape: BoxShape.circle,
        boxShadow: filled ? const [BoxShadow(color: Colors.black38, blurRadius: 6)] : null,
      ),
      child: Icon(icon, size: 16, color: Colors.white),
    ),
  );
}
