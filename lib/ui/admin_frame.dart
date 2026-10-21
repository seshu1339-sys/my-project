import 'package:flutter/material.dart';

import '../data/store.dart';

/// Tells the admin pages below whether they are shown INSIDE a tab or a Settings section (no title bar of their
/// own, the tab already says where you are) or opened on their own as a full page.
class AdminEmbedScope extends InheritedWidget {
  const AdminEmbedScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdminEmbedScope>() != null;

  @override
  bool updateShouldNotify(AdminEmbedScope oldWidget) => false;
}

/// Pages that read Firebase directly (approvals, complaints, Quick Add) only work for a signed-in administrator on a connected
/// project. In the offline demo studio they show this note instead of failing.
class AdminNeedsFirebase extends StatelessWidget {
  const AdminNeedsFirebase({super.key, required this.store, required this.child});
  final Store store;
  final Widget child;
  @override
  Widget build(BuildContext context) => store.live
      ? child
      : const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('This page works with live data. It is available when Firebase is connected.', textAlign: TextAlign.center),
          ),
        );
}

/// A page's frame: a normal Scaffold with a title bar when it stands alone, or just its body (with its action
/// buttons in a small row above it) when it sits inside a tab. Every admin page uses it, so a page looks the same
/// whichever way it is reached.
class AdminPageFrame extends StatelessWidget {
  const AdminPageFrame({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.floatingActionButton,
  });
  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    if (!AdminEmbedScope.of(context)) {
      return Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        floatingActionButton: floatingActionButton,
        body: body,
      );
    }
    // Inside a tab: Material gives Ink/ListTile their surface, a Stack carries the floating button.
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Column(
            children: [
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(alignment: Alignment.centerRight, child: Wrap(spacing: 8, children: actions)),
                ),
              Expanded(child: body),
            ],
          ),
          if (floatingActionButton != null) Positioned(right: 16, bottom: 16, child: floatingActionButton!),
        ],
      ),
    );
  }
}
