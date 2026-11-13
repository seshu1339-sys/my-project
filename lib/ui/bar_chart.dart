import 'package:flutter/material.dart';

/// A small bar chart: one bar per (label, value), the value over each bar and every few labels under it. Optional [target] draws a
/// dashed line (a daily target, for example). Read only.
class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.values, this.target, this.height = 160});
  final List<(String, int)> values;
  final int? target;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return SizedBox(height: height / 2, child: const Center(child: Text('No updates in this time yet.')));
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _BarPainter(values, target, scheme.primary, scheme.error, Theme.of(context).textTheme.labelSmall ?? const TextStyle(fontSize: 10)),
        size: Size.infinite,
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.values, this.target, this.bar, this.line, this.text);
  final List<(String, int)> values;
  final int? target;
  final Color bar, line;
  final TextStyle text;

  void _label(Canvas canvas, String s, Offset at, double maxWidth) {
    final p = TextPainter(text: TextSpan(text: s, style: text), textDirection: TextDirection.ltr, maxLines: 1)..layout(maxWidth: maxWidth < 1 ? 1 : maxWidth);
    p.paint(canvas, Offset(at.dx - p.width / 2, at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 16.0, top = 14.0;
    final chart = size.height - bottom - top;
    final most = [for (final (_, v) in values) v, target ?? 0].reduce((a, b) => a > b ? a : b);
    final scale = most <= 0 ? 0.0 : chart / most;
    final slot = size.width / values.length;
    final paint = Paint()..color = bar;
    final every = (values.length / 8).ceil().clamp(1, 1000);
    for (final (i, (label, v)) in values.indexed) {
      final h = v * scale;
      final x = i * slot;
      canvas.drawRect(Rect.fromLTWH(x + slot * 0.15, top + chart - h, slot * 0.7, h), paint);
      if (v > 0 && slot > 14) _label(canvas, '$v', Offset(x + slot / 2, top + chart - h - 12), slot);
      if (i % every == 0) _label(canvas, label, Offset(x + slot / 2, size.height - bottom + 2), slot * every);
    }
    if (target != null && target! > 0 && scale > 0) {
      final y = top + chart - target! * scale;
      final dash = Paint()..color = line..strokeWidth = 1.5;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), dash);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.values != values || old.target != target;
}
