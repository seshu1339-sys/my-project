# Admin panel clean-up (branch admin-cleanup)

Request of 2026-10-21: simpler admin ("Business studio"), everything in its proper place, no option removed.

## Step A -- navigation (done)
- Tabs: Insights (home), Orders, Products, Vendors, Shops, Complaints, Promotions, Settings. Only the open tab is built.
- Vendors tab: Vendors | Quick Add accounts | Quick Add items (sub-tabs).
- Settings tab: Categories, Field Assistants, Business Profile, Theme, Scrolling Text, Product Image Library, Layout
  (Layout settings, Visual Editor, Page view), Quick Add locations. (Animations arrives in step D.)
- Top bar: Search, AI Agent, Sign out -- each with a text label; on a phone they sit in a row under the title.
- The old chip row, the gear/other-settings menu, the layout and visual-editor icons and the "More" menu are gone; every item
  they led to is reachable in exactly one place above.
- Files: `admin.dart` (shell), `admin_frame.dart` (AdminPageFrame / AdminEmbedScope / AdminNeedsFirebase),
  `admin_entry_list.dart` (the list of one collection), `admin_settings.dart`, `admin_page_preview.dart` (Page view).
- Insights is now the first page, so two phone-width overflows in it were fixed.
