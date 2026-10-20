import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/app_theme.dart';
import '../services/search.dart';
import 'element_groups.dart';
import 'entry_editor.dart';
import 'group_item_design_form.dart';
import 'group_settings_page.dart';
import 'layout_defaults.dart';
import 'layout_editor.dart';
import 'layout_settings.dart';
import 'home_section_config.dart';
import 'page_elements.dart';
import 'shared.dart';
import 'visual_editor_overlay.dart';
import 'wireframe_home.dart';

// Ads/boxes/carousel slides keep this exact prefix -- it predates
// numbering (built for per-ad resize) and HomeAdRail's wrapItem callback
// still produces it. Categories/cross-sell-strip items use their own
// group's keyPrefix from element_groups.dart. isGroupSubKey/
// groupCollectionForKey/groupSubIdForKey (element_groups.dart) handle all
// of these generically from here on.
const _promoKeyPrefix = 'promo-';

// Numbered elements whose settings already live in their OWN dedicated
// Firestore doc with their own full admin editor, rather than the generic
// settings/section_<key> + LayoutFieldsForm pair every other numbered
// element uses. Selecting one of these opens that existing editor instead
// of the inline panel -- same "point at the real editor" pattern already
// used below for Theme/Business Profile/Promotions.
const _externalEditorKeys = {'tickerMarquee': ('settings', 'scrollingText')};

enum _PreviewWidth { desktop, tablet, mobile }

/// The admin "Visual Editor": the real, live `WireframeHome` rendered inside
/// admin, with click-to-select-section focus (dim everything else), an
/// inline settings panel for the selected section with live (auto-saving)
/// preview, Cancel/Undo/Redo, drag-reorder and resize on the selected
/// section's handles, and a desktop/tablet/mobile preview-width toggle.
///
/// Only sections backed by the `layoutComponents` field schema
/// (`lib/ui/layout_settings.dart`) get true inline live editing here, via
/// the shared `LayoutFieldsForm` (also used, unmodified in behavior, by the
/// full-page `LayoutSettingsPage`). Theme, Business Profile and Promotions
/// content are collection/single-doc edits with their own specialized UI
/// (color pickers, image upload, the geo-target map picker) — inlining
/// those beside an already-animating live preview is a real layout/gesture
/// risk not worth taking here, so they get a compact summary chip that
/// opens the existing, completely unmodified `EntryEditor` page instead.
class VisualEditorPage extends StatefulWidget {
  const VisualEditorPage({super.key, required this.store});
  final Store store;
  @override
  State<VisualEditorPage> createState() => _VisualEditorPageState();
}

class _VisualEditorPageState extends State<VisualEditorPage> {
  final selection = EditorSelection();
  final search = TextEditingController();
  final scroll = ScrollController();
  final categoriesKey = GlobalKey();
  final productsKey = GlobalKey();
  final goToNumber = TextEditingController();
  _PreviewWidth previewWidth = _PreviewWidth.desktop;
  // Off by default -- customers never see this (it's purely an admin aid
  // inside this editor) and it must never affect anything until an admin
  // actually turns it on. See SectionTapRegion's `showNumber`/`number`.
  bool _showNumbers = false;
  bool _logoBusy = false;

  // Undo/redo + cancel are scoped to the current edit session only (one
  // selected section at a time) — not a global, app-wide history.
  final List<Map<String, dynamic>> _history = [];
  int _historyIndex = 0;

  // Real drag-to-resize state, held purely locally (never Firestore) while a
  // drag is live — only the dragged section's own SectionTapRegion rebuilds
  // per pointer-move, never the whole page/preview. Persisted exactly once,
  // at drag-end — see _endResize. Extracted into its own class (rather than
  // inline ValueNotifier + methods here) so the drag/commit logic is
  // directly unit-testable without mounting the real WireframeHome preview.
  final ResizeController _resize = ResizeController();

  bool _closing = false;

  @override
  void dispose() {
    selection.dispose();
    search.dispose();
    scroll.dispose();
    goToNumber.dispose();
    _resize.dispose();
    super.dispose();
  }

  void _previewOnly(String what) =>
      message(context, '$what — open the live site to try this for real.');

  // A selected key is one of: a layout-component section (backed by
  // settings/section_<key>), an item inside a repeating group (backed by
  // its own doc in that group's real collection -- element_groups.dart
  // resolves exactly which), or a key with its own fully separate editor
  // (_externalEditorKeys). These two helpers are the ONE place that
  // distinction is resolved, so selection, undo/redo, cancel and the
  // design form all agree on where a key's data actually lives without
  // duplicating this branch everywhere.
  Entry _currentEntryFor(String key) {
    if (isGroupSubKey(key)) return groupSubEntry(widget.store, key);
    final external = _externalEditorKeys[key];
    if (external != null) {
      return widget.store
          .entries(external.$1)
          .firstWhere(
            (e) => e.id == external.$2,
            orElse: () => Entry(external.$2, const {}),
          );
    }
    return sectionConfig(widget.store.entries('settings'), key);
  }

  Future<void> _saveEntryFor(String key, Map<String, dynamic> data) {
    if (isGroupSubKey(key))
      return widget.store.save(
        groupCollectionForKey(key),
        Entry(groupSubIdForKey(key), data),
      );
    final external = _externalEditorKeys[key];
    if (external != null)
      return widget.store.save(external.$1, Entry(external.$2, data));
    return widget.store.save('settings', Entry('section_$key', data));
  }

  void _select(String key) {
    _history
      ..clear()
      ..add(Map<String, dynamic>.from(_currentEntryFor(key).data));
    _historyIndex = 0;
    selection.value = key;
  }

  // "Go to number": typing a number (plain "16" or a group item's own
  // "16.2"), or an item's name, jumps straight to its edit panel exactly
  // as if its live-preview region had been clicked -- it reuses `_select`,
  // so undo/redo/cancel all work identically either way.
  void _goToNumber(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final key = _resolveGoTo(trimmed);
    if (key == null) {
      message(context, 'No element matching "$trimmed" yet.');
      return;
    }
    _select(key);
    goToNumber.clear();
  }

  String? _resolveGoTo(String query) {
    final dot = query.indexOf('.');
    if (dot > 0) {
      final main = int.tryParse(query.substring(0, dot));
      final sub = int.tryParse(query.substring(dot + 1));
      if (main != null && sub != null)
        return resolveSubKey(widget.store, main, sub);
      return null;
    }
    final number = int.tryParse(query);
    if (number != null) return pageElementByNumber(number)?.key;
    // Not a number at all -- search by name: every standalone element's
    // own label, plus every group item's own content name (so typing
    // "Fruits" finds that one category without knowing its number).
    final lower = query.toLowerCase();
    for (final element in pageElements) {
      if (element.label.toLowerCase().contains(lower)) return element.key;
    }
    for (final group in elementGroups) {
      if (group.isStatic) {
        for (final key in group.staticKeys!) {
          if ((layoutComponents[key] ?? key).toLowerCase().contains(lower))
            return key;
        }
        continue;
      }
      final members = group.members(widget.store);
      for (final member in members) {
        if (member.text('name').toLowerCase().contains(lower))
          return '${group.keyPrefix}-${member.id}';
      }
    }
    return null;
  }

  Future<void> _closeSelection({required bool restoreSnapshot}) async {
    final key = selection.value;
    setState(() => _closing = true);
    try {
      if (key != null && restoreSnapshot && _history.isNotEmpty) {
        await _saveEntryFor(key, _history.first);
      }
      selection.value = null;
      _history.clear();
      _historyIndex = 0;
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  void _onAutoSaved() {
    final key = selection.value;
    if (key == null) return;
    final current = Map<String, dynamic>.from(_currentEntryFor(key).data);
    // Drop any "future" redo states once a new edit happens after an undo.
    _history.removeRange(_historyIndex + 1, _history.length);
    _history.add(current);
    _historyIndex = _history.length - 1;
    setState(() {});
  }

  Future<void> _undo() async {
    final key = selection.value;
    if (key == null || _historyIndex <= 0) return;
    _historyIndex--;
    await _saveEntryFor(key, _history[_historyIndex]);
    setState(() {});
  }

  Future<void> _redo() async {
    final key = selection.value;
    if (key == null || _historyIndex >= _history.length - 1) return;
    _historyIndex++;
    await _saveEntryFor(key, _history[_historyIndex]);
    setState(() {});
  }

  Future<void> _openFullEditor(String collection, {String? entryId}) async {
    final entry = entryId == null
        ? null
        : widget.store
              .entries(collection)
              .where((e) => e.id == entryId)
              .firstOrNull;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntryEditor(
          store: widget.store,
          collection: collection,
          entry: entry,
        ),
      ),
    );
  }

  // Writes ONLY the business profile's 'imageUrl' field -- merging onto a
  // fresh read of the current data, never a full replace -- so uploading
  // or removing the logo photo can never touch the shop name, tagline, or
  // any other Business Profile field, even though they all live in the
  // same settings/business doc. Same read-merge-save shape as
  // adjustSectionField elsewhere in this app for exactly this "touch one
  // field only" need.
  Future<void> _uploadLogo() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      setState(() => _logoBusy = true);
      final url = await widget.store.upload(file);
      await widget.store.save(
        'settings',
        Entry('business', {...widget.store.business.data, 'imageUrl': url}),
      );
      if (mounted) message(context, 'Logo photo updated');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  Future<void> _removeLogo() async {
    setState(() => _logoBusy = true);
    try {
      final data = {...widget.store.business.data}..remove('imageUrl');
      await widget.store.save('settings', Entry('business', data));
      if (mounted)
        message(context, 'Logo photo removed — showing the fallback icon');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  Future<void> _saveDefault() async {
    try {
      await saveAsDefault(widget.store);
      if (mounted) message(context, 'Saved as My Default');
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  Future<void> _resetDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Reset to My Default?'),
        content: const Text(
          'This replaces every current layout/colour/size setting with whatever you last saved as "My Default". This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await resetToDefault(widget.store);
      if (mounted) message(context, 'Restored to My Default');
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  double? get _simulatedWidth => switch (previewWidth) {
    _PreviewWidth.desktop => null,
    _PreviewWidth.tablet => 900,
    _PreviewWidth.mobile => 390,
  };

  // A plain layoutComponents key can ALSO be a static group's own fixed
  // member (e.g. 'footerBadge3', one of the 6 fixed footer badges) --
  // unlike a dynamic group's synthetic 'prefix-id' keys, these keep using
  // this exact same section path (their own settings/section_<key> doc,
  // full LayoutFieldsForm) and only need a decimal "28.3" display number
  // instead of the flat whole number they used to have before the footer
  // badges were consolidated under one main number.
  Widget _wrapSection(String key, Widget child) {
    final subPosition = subNumberForKey(widget.store, key);
    return SectionTapRegion(
      sectionKey: key,
      label: layoutComponents[key] ?? key,
      selection: selection,
      onSelect: _select,
      number: subPosition == null ? pageElementByKey(key)?.number : null,
      numberLabel: subPosition == null
          ? null
          : '${subPosition.$1}.${subPosition.$2}',
      showNumber: _showNumbers,
      reorderable: reorderableHomeSections.any((d) => d.key == key),
      onReorderDrop: (draggedKey) => _dropReorder(draggedKey, ontoKey: key),
      liveResize: _resize.live,
      onHeightDragStart: () => _startResize(key),
      onHeightDragUpdate: (dy) => _resize.updateHeight(key, dy),
      onHeightDragEnd: () => _endResize(key),
      onWidthDragStart: () => _startResize(key),
      onWidthDragUpdate: (dx) => _resize.updateWidth(key, dx),
      onWidthDragEnd: () => _endResize(key),
      onCornerDragStart: () => _startResize(key),
      onCornerDragUpdate: (d) => _resize.updateCorner(key, d),
      onCornerDragEnd: () => _endResize(key),
      child: child,
    );
  }

  void _startResize(String key) {
    final saved = _currentEntryFor(key);
    final h = saved.number('height', 0);
    final w = saved.number('width', 0);
    // 0/automatic starts from a sensible on-screen size rather than jumping
    // the section to 0px/full-bleed the instant the drag begins.
    _resize.start(key, baseHeight: h > 0 ? h : 240, baseWidth: w > 0 ? w : 600);
  }

  Future<void> _saveHeight(String key, double h) =>
      adjustSectionHeight(widget.store, key, h);

  Future<void> _saveWidth(String key, double w) =>
      adjustSectionWidth(widget.store, key, w);

  Future<void> _endResize(String key) => _resize.end(
    key,
    saveHeight: (h) => _saveHeight(key, h),
    saveWidth: (w) => _saveWidth(key, w),
  );

  // Wraps one individual item inside a repeating group (one ad, one box,
  // one category...) in click-to-select only -- deliberately NO resize
  // handles, unlike a real section: size lives only on the group's own
  // main number now (see element_groups.dart's doc comment), so an
  // individual item can never drift to a different size than its
  // siblings. Not reorderable here either -- group order comes from each
  // item's own `order` field (edited in its content editor), not drag.
  Widget _wrapGroupItem(String key, String label, Widget child) {
    final position = subNumberForKey(widget.store, key);
    return SectionTapRegion(
      sectionKey: key,
      label: label,
      selection: selection,
      onSelect: _select,
      numberLabel: position == null ? null : '${position.$1}.${position.$2}',
      showNumber: _showNumbers,
      child: child,
    );
  }

  Widget _wrapPromoItem(Entry entry, String kind, Widget child) =>
      _wrapGroupItem(
        '$_promoKeyPrefix${entry.id}',
        kind == 'ad' ? 'Ad' : 'Box',
        child,
      );

  Future<void> _dropReorder(
    String draggedKey, {
    required String ontoKey,
  }) async {
    final settings = widget.store.entries('settings');
    final ordered = [...reorderableHomeSections]
      ..sort(
        (a, b) => sectionOrder(
          settings,
          a.key,
        ).compareTo(sectionOrder(settings, b.key)),
      );
    final oldIndex = ordered.indexWhere((d) => d.key == draggedKey);
    final newIndex = ordered.indexWhere((d) => d.key == ontoKey);
    if (oldIndex == -1 || newIndex == -1 || oldIndex == newIndex) return;
    await reorderHomeSections(widget.store, oldIndex, newIndex);
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: buildAppTheme(widget.store, dark: false),
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Visual Editor'),
        actions: [
          SizedBox(
            width: 200,
            child: TextField(
              controller: goToNumber,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Go to number or name',
                prefixIcon: Icon(Icons.pin_outlined, size: 18),
                border: OutlineInputBorder(),
              ),
              onSubmitted: _goToNumber,
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            avatar: const Icon(Icons.numbers, size: 18),
            label: const Text('Show numbers'),
            selected: _showNumbers,
            onSelected: (v) => setState(() => _showNumbers = v),
          ),
          const SizedBox(width: 12),
          SegmentedButton<_PreviewWidth>(
            segments: const [
              ButtonSegment(
                value: _PreviewWidth.desktop,
                icon: Icon(Icons.desktop_windows_outlined),
              ),
              ButtonSegment(
                value: _PreviewWidth.tablet,
                icon: Icon(Icons.tablet_mac_outlined),
              ),
              ButtonSegment(
                value: _PreviewWidth.mobile,
                icon: Icon(Icons.phone_iphone_outlined),
              ),
            ],
            selected: {previewWidth},
            onSelectionChanged: (s) => setState(() => previewWidth = s.first),
          ),
          const SizedBox(width: 12),
          ActionChip(
            avatar: const Icon(Icons.palette_outlined, size: 18),
            label: const Text('Theme'),
            onPressed: () => _openFullEditor('theme', entryId: 'theme'),
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.storefront_outlined, size: 18),
            label: const Text('Business Profile'),
            onPressed: () => _openFullEditor('settings', entryId: 'business'),
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.local_offer_outlined, size: 18),
            label: const Text('Promotions'),
            onPressed: () => _openFullEditor('promotions'),
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('Save as My Default'),
            onPressed: _saveDefault,
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.restore_outlined, size: 18),
            label: const Text('Reset to My Default'),
            onPressed: _resetDefault,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: const Color(0xffe9ebe7),
              child: Center(
                child: ClipRect(
                  child: SizedBox(
                    width: _simulatedWidth,
                    child: MediaQuery(
                      data: _simulatedWidth == null
                          ? MediaQuery.of(context)
                          : MediaQuery.of(context).copyWith(
                              size: Size(
                                _simulatedWidth!,
                                MediaQuery.sizeOf(context).height,
                              ),
                            ),
                      // WireframeHome already scrolls itself internally
                      // (bound to `scroll` below) — wrapping it in a second,
                      // outer SingleChildScrollView here nests two unbounded
                      // vertical scrollables, which Flutter cannot lay out
                      // (the inner viewport is handed an unbounded height)
                      // and throws a layout error that crashed/froze this
                      // page. WireframeHome just needs the bounded height
                      // its ancestors (Expanded/Scaffold) already give it.
                      child: WireframeHome(
                        store: widget.store,
                        search: search,
                        searchService: const SmartSearch(),
                        onSearch: () => setState(() {}),
                        onLocation: () => _previewOnly('Location picker'),
                        onAssistedSearch: (_) =>
                            _previewOnly('Voice/image search'),
                        onServices: () => _previewOnly('Services page'),
                        onAccount: () => _previewOnly('Account page'),
                        onCart: () => _previewOnly('Cart page'),
                        onProduct: (_) => _previewOnly('Product page'),
                        onAdd: (_) => _previewOnly('Add to cart'),
                        onCategory: (_) => _previewOnly('Category page'),
                        onPromotion: (_) => _previewOnly('Promotion target'),
                        scroll: scroll,
                        categoriesKey: categoriesKey,
                        productsKey: productsKey,
                        wrapSection: _wrapSection,
                        wrapPromoItem: _wrapPromoItem,
                        wrapCategoryItem: (category, child) => _wrapGroupItem(
                          'category-${category.id}',
                          'Category',
                          child,
                        ),
                        wrapProductItem: (product, child) => _wrapGroupItem(
                          'crossSellProduct-${product.id}',
                          'Product',
                          child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<String?>(
            valueListenable: selection,
            builder: (context, key, _) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: key == null ? 0 : 340,
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: const Border(top: BorderSide(color: Colors.black12)),
              ),
              child: key == null ? null : _inlinePanel(key),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _panelBody(String key) {
    if (isGroupSubKey(key)) {
      final collection = groupCollectionForKey(key);
      final id = groupSubIdForKey(key);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text(
                'Edit content (text, image, link, schedule...)',
              ),
              onPressed: () => _openFullEditor(collection, entryId: id),
            ),
            const SizedBox(height: 8),
            Text(
              'Design only — size is set once for the whole group on its main number.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            GroupItemDesignForm(
              key: ValueKey(key),
              store: widget.store,
              collection: collection,
              id: id,
              onSaved: _onAutoSaved,
            ),
          ],
        ),
      );
    }
    final external = _externalEditorKeys[key];
    if (external != null) {
      return Center(
        child: TextButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open its full settings editor'),
          onPressed: () => _openFullEditor(external.$1, entryId: external.$2),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (key == 'logo') _logoPhotoRow(),
          LayoutFieldsForm(
            key: ValueKey(key),
            store: widget.store,
            component: key,
            autoSave: true,
            onSaved: _onAutoSaved,
          ),
        ],
      ),
    );
  }

  // The logo's actual photo lives in Business Profile (settings/business's
  // 'imageUrl'), not in its own settings/section_logo doc -- LayoutFieldsForm
  // below only ever edits section_logo (size/color/visibility). This row
  // gives the logo number its own upload/remove control without touching
  // Business Profile's page, and _uploadLogo/_removeLogo above write only
  // the 'imageUrl' field, so the shop name and tagline (separate fields on
  // that same document) are never affected.
  Widget _logoPhotoRow() {
    final imageUrl = widget.store.business.text('imageUrl');
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (imageUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrl,
                  width: 48,
                  height: 48,
                  fit: BoxFit.contain,
                  errorBuilder: (_, error, stack) =>
                      const SizedBox(width: 48, height: 48),
                ),
              ),
            ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _logoBusy ? null : _uploadLogo,
                  icon: const Icon(Icons.upload, size: 18),
                  label: const Text('Upload logo photo'),
                ),
                if (imageUrl.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: _logoBusy ? null : _removeLogo,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Remove logo photo'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // "16.2 – Fruits" for a group item (its own live display name, with the
  // sub-number recomputed from current order -- never stored, so it can
  // never drift from what "Go to number" would resolve right now), or the
  // usual "N – Label" for everything else.
  String _titleFor(String key) {
    if (isGroupSubKey(key)) {
      final position = subNumberForKey(widget.store, key);
      final entry = _currentEntryFor(key);
      final name = entry.text('name', 'Item');
      return position == null ? name : '${position.$1}.${position.$2} – $name';
    }
    // A static group's own fixed member (e.g. 'footerBadge3') -- same
    // decimal-number display as a dynamic group item above, but it keeps
    // its plain layoutComponents label since it already has real content
    // (text/icon) of its own, unlike a group item's generic "name".
    final subPosition = subNumberForKey(widget.store, key);
    if (subPosition != null) {
      return '${subPosition.$1}.${subPosition.$2} – ${layoutComponents[key] ?? key}';
    }
    return numberedLabel(
      key,
      layoutComponents[key] ?? pageElementByKey(key)?.label ?? key,
    );
  }

  Widget _inlinePanel(String key) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _titleFor(key),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Undo',
              icon: const Icon(Icons.undo),
              onPressed: _historyIndex > 0 ? _undo : null,
            ),
            IconButton(
              tooltip: 'Redo',
              icon: const Icon(Icons.redo),
              onPressed: _historyIndex < _history.length - 1 ? _redo : null,
            ),
            OutlinedButton(
              onPressed: _closing
                  ? null
                  : () => _closeSelection(restoreSnapshot: true),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _closing
                  ? null
                  : () => _closeSelection(restoreSnapshot: false),
              child: _closing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Done'),
            ),
          ],
        ),
      ),
      // Group items (one ad, one category, ...) deliberately get NO
      // width/height row here -- size lives only on the group's own main
      // number (its Width/Height fields are in LayoutFieldsForm, selected
      // separately), so every item in a group is always the same size.
      if (behaviorSettingsFields.containsKey(key))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Scrolling / behavior settings'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GroupSettingsPage(
                    store: widget.store,
                    component: key,
                    title: '${layoutComponents[key] ?? key} Settings',
                    fields: behaviorSettingsFields[key]!,
                  ),
                ),
              ),
            ),
          ),
        ),
      const Divider(),
      Expanded(child: _panelBody(key)),
    ],
  );
}
