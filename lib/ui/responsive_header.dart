// This file used to contain the header bar, search box and contact-actions
// widgets directly. They have been split into focused files (see each export
// below) to keep individual files small; this barrel re-exports them
// unchanged so every existing `import 'responsive_header.dart'` keeps
// working with no call-site changes required.
export 'responsive_header_bar.dart';
export 'responsive_search_box.dart';
export 'contact_actions.dart';
