import 'package:flutter/material.dart';

/// The field the command box asked for (owner spec A, 17 Nov 2026): the page it opens is wrapped in this scope, and the one form field
/// with that key scrolls into view and glows (see [AgentFocusTarget]). A page with no such field just opens.
class AgentFocusScope extends InheritedWidget {
  const AgentFocusScope({super.key, required this.field, required super.child});
  final String field;

  static String? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AgentFocusScope>()?.field;

  @override
  bool updateShouldNotify(AgentFocusScope old) => old.field != field;
}

/// Wraps one form field. When the scope names [fieldKey], it scrolls to it after the page is built and is highlighted (an amber frame
/// that stays a few seconds, then fades to a thin outline so the admin still sees which one it was).
class AgentFocusTarget extends StatefulWidget {
  const AgentFocusTarget({super.key, required this.fieldKey, required this.child});
  final String fieldKey;
  final Widget child;

  @override
  State<AgentFocusTarget> createState() => _AgentFocusTargetState();
}

class _AgentFocusTargetState extends State<AgentFocusTarget> {
  bool _strong = true;
  bool _scrolled = false;

  bool get _focused => AgentFocusScope.of(context) == widget.fieldKey && widget.fieldKey.isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_focused && !_scrolled) {
      _scrolled = true;
      // Twice: once the page is laid out, and again after an "Advanced" part has opened around the field.
      for (final wait in const [Duration(milliseconds: 50), Duration(milliseconds: 450)]) {
        Future<void>.delayed(wait, () {
          if (!mounted) return;
          Scrollable.ensureVisible(context, alignment: .25, duration: const Duration(milliseconds: 350));
        });
      }
      Future<void>.delayed(const Duration(seconds: 6), () {
        if (mounted) setState(() => _strong = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_focused) return widget.child;
    return AnimatedContainer(
      key: ValueKey('agent-focus-${widget.fieldKey}'),
      duration: const Duration(milliseconds: 600),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _strong ? const Color(0x33FFC107) : Colors.transparent,
        border: Border.all(color: const Color(0xFFFFA000), width: _strong ? 3 : 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: widget.child,
    );
  }
}

/// A form's list: a normal ListView, or, when the command box opened the page at one field, every row built at once (a scroll view
/// with a column), so a field far down exists and can be scrolled to and highlighted.
class AgentFormList extends StatelessWidget {
  const AgentFormList({super.key, required this.children, this.padding});
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    if (AgentFocusScope.of(context) == null) return ListView(padding: padding, children: children);
    return SingleChildScrollView(padding: padding, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
  }
}
