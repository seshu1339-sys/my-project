import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A field whose label is [label] followed by its current value in brackets, e.g. "Icon size (24px)".
/// [kind] is the widget type to return, e.g. find.byType(TextFormField).
Finder labelled(Finder kind, String label) => find.ancestor(
  of: find.byWidgetPredicate((w) => w is Text && (w.data == label || (w.data ?? '').startsWith('$label ('))),
  matching: kind,
);
