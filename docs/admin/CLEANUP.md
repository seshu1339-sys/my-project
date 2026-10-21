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

## Step B -- single-record settings (done)
- Business Profile, Theme and Scrolling Text open straight as one form (`AdminSingleRecord`, `EntryEditor(embedded: true)`):
  no list, no "Add new", saving keeps you on the form. A project that never saved one gets the form empty; the first Save creates it.
- The Theme record had no name, so its own form refused to save ("Enter a name"): the name field now starts as "Theme", and a nameless
  record shows its section name in lists. (Animations becomes the fourth single-record section in step D.)

## Step C -- lists (done)
- Technical ids (prod-apple, cat-fruits ...) are gone from every list row; rows show category and shop instead.
- Products: search box (name, keywords, category, shop), "No shop only", Category, All/Published/Draft, "Clear filters", and the count
  "N of M products". "Select several" + "Select all N shown" + "Assign shop" sets one shop on all selected products at once
  (`Store.updateMany`, batched writes live).
- Order numbers: products, categories, promotions and shops can be dragged into a new order (numbers become 1..n); a banner appears
  when numbers repeat or skip, with a "Renumber" button. Nothing is renumbered unless you press it or drag. Dragging is off while a
  search/filter is active (a partial list cannot be reordered safely).
- Promotions show what they lead to in the title ("Today's Offer — Category: Personal care") and where they sit (Banner / Advertisement ...).

## Step D -- Animations (done)
Why animation changes were not applied (found in the code and the live settings):
1. `animationSpeed` (the live Search Box and Logo have 200 / 600 saved) only drove the rotating banners; an entrance always took a fixed 450 ms.
2. An entrance played once, when the section was first built, and never again, so a change made in the admin showed nothing on a page
   that was already open; it also moved only 24 px.
3. Banner rotation (`animationType`) is off: `section_promo` has `animation=slide` but no `animationType`.
4. There was no global control, and entrance animation existed on 11 parts only through 11 separate forms.

What was built: Settings -> Animations (`settings/animations`, `animation_settings_form.dart`): a global on/off, a default type and speed,
and per part (Header, Ticker, Offers banner, Categories, Popular, Local Services, Fresh strip, Ads, Boxes, Nearby, Page background) an
on/off, a type (None / Fade / Slide / Zoom), a speed 1-10 and, for the banner and ads, how pictures change. The site reads it through
`effectiveSectionConfig` (used by `layoutFor`): the part's own settings with the Animations record on top. With no record the site is
exactly as before (450 ms, own types). Entrances and animated texts are now keyed by their type and speed, so a change replays at once on
an open page. The admin's forms still read the raw record, so Animations values are never copied into a part's settings.
New: "Zoom in" entrance (also added to the per-part Entrance animation dropdown).

## Step E -- layout settings (done)
- Contradictory sizes are refused with the reason: width below its minimum, height below its minimum, a size above its maximum, a
  minimum above the maximum (also the mobile/tablet/desktop widths). Example: "The width (900 px) is smaller than the minimum width
  (1000 px). Raise the width or lower the minimum." Saving shows "Not saved: ...", opens Advanced and marks both fields; the Visual
  Editor's auto-save writes nothing while sizes contradict. Blank / 0 (automatic) never conflicts. (`layoutConflicts` in layout_settings.dart)
- Size: Small / Medium / Large on every component that has size fields: sets the screen scales (85% / normal / 120%), else font
  size, else icon size; colours, text and everything else are never touched. Shown as "Custom sizes" when numbers are typed by hand.
- Every pixel/scale field is under "Advanced" (closed by default); behaviour pages (speed, direction ...) are not split.

## Step F: "Reset to default" with confirmation

- Every reset (a component's layout, Settings > Animations, a settings record in the editor) first shows a dialog listing each setting as "current -> default" and asks Reset / Cancel. Cancel changes nothing.
- After a confirmed reset the record is read back from the database; a dialog says "Reset complete" (and lists what changed) or "Reset incomplete" with the settings that could not be cleared.
- Likely cause of "reset did nothing": leftover stored values the form does not show (e.g. an old width or colour) kept changing the site. The reset now clears those too (marked "not shown in the form"). Behaviour settings (speed, banner count, ...) are kept; they have their own pages.
- "Nothing to reset" is shown when a component already uses its defaults.
- New: "Reset animations to default" button on Settings > Animations.
- Not checkable here: real Firestore read-back and the live site after a reset (needs admin login).
