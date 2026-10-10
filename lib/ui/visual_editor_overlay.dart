import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Which layout section key is currently selected in the admin Visual
/// Editor, or `null` for none. Lives for the lifetime of one
/// `VisualEditorPage` — never a global/app-wide notion of selection.
class EditorSelection extends ValueNotifier<String?> {
  EditorSelection() : super(null);
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
    this.liveHeightLabel,
    this.onResizeDragStart,
    this.onResizeDragUpdate,
    this.onResizeDragEnd,
    required this.child,
  });
  final String sectionKey;
  final String label;
  final EditorSelection selection;
  final ValueChanged<String> onSelect;
  final bool reorderable;
  // Called with the dragged section's key when it's dropped onto this one.
  final ValueChanged<String>? onReorderDrop;
  // Shown in the resize badge while a resize drag is live, e.g. "320px".
  final String? liveHeightLabel;
  final VoidCallback? onResizeDragStart;
  final ValueChanged<double>? onResizeDragUpdate; // total dy since drag start
  final VoidCallback? onResizeDragEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: selection,
    builder: (context, selected, _) {
      final isSelected = selected == sectionKey;
      final isDimmed = selected != null && !isSelected;
      Widget content = child;
      if (isDimmed) {
        content = IgnorePointer(
          child: AnimatedOpacity(
            opacity: .35,
            duration: const Duration(milliseconds: 150),
            child: content,
          ),
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
                if (onResizeDragUpdate != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: -10,
                    child: Center(
                      child: GestureDetector(
                        key: ValueKey('resize-handle-$sectionKey'),
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: (_) => onResizeDragStart?.call(),
                        onVerticalDragUpdate: (d) => onResizeDragUpdate!(d.localPosition.dy),
                        onVerticalDragEnd: (_) => onResizeDragEnd?.call(),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeRow,
                          child: Container(
                            width: 56,
                            height: 20,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTokens.primary,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                            ),
                            child: liveHeightLabel != null
                                ? Text(liveHeightLabel!, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))
                                : const Icon(Icons.drag_handle, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
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
