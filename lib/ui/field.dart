// This file used to contain the entire Field Assistant (staff) app UI
// directly. It has been split into focused files (see each export below) to
// keep individual files small, matching the vendor module's own split; this
// barrel re-exports them unchanged so every existing `import 'field.dart'`
// keeps working with no call-site changes required.
export 'field_home_page.dart';
export 'field_registration_form.dart';
export 'field_workspace.dart';
export 'field_entry_form.dart';
