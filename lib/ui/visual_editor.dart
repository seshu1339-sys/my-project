import 'dart:async';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/app_theme.dart';
import '../services/search.dart';
import 'entry_editor.dart';
import 'layout_defaults.dart';
import 'layout_editor.dart';
import 'layout_settings.dart';
import 'home_ad_rail.dart';
import 'home_section_config.dart';
import 'shared.dart';
import 'visual_editor_overlay.dart';
import 'wireframe_home.dart';

// Keys for individually-selectable ad/box promotions are namespaced with
// this prefix (e.g. 'promo-<firestoreId>') so they can share EditorSelection
// and ResizeController with the 7 layout-component keys without colliding —
// no promotion id is ever itself a bare layout-component key.
const _promoKeyPrefix = 'promo-';
bool _isPromoKey(String key) => key.startsWith(_promoKeyPrefix);
String _promoId(String key) => key.substring(_promoKeyPrefix.length);

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
  _PreviewWidth previewWidth = _PreviewWidth.desktop;

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
    _resize.dispose();
    super.dispose();
  }

  void _previewOnly(String what) => message(context, '$what — open the live site to try this for real.');

  // A selected key is either one of the 7 layout-component sections (backed
  // by settings/section_<key>) or one individually-selected ad/box promotion
  // (backed by its own promotions/<id> doc, key 'promo-<id>') — these two
  // helpers are the ONE place that distinction is resolved, so selection,
  // undo/redo, cancel and the percent fields all agree on where a key's data
  // actually lives without duplicating this branch everywhere.
  Entry _currentEntryFor(String key) => _isPromoKey(key)
      ? widget.store.entries('promotions').firstWhere((e) => e.id == _promoId(key), orElse: () => Entry(_promoId(key), const {}))
      : sectionConfig(widget.store.entries('settings'), key);

  Future<void> _saveEntryFor(String key, Map<String, dynamic> data) => _isPromoKey(key)
      ? widget.store.save('promotions', Entry(_promoId(key), data))
      : widget.store.save('settings', Entry('section_$key', data));

  void _select(String key) {
    _history
      ..clear()
      ..add(Map<String, dynamic>.from(_currentEntryFor(key).data));
    _historyIndex = 0;
    selection.value = key;
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
        : widget.store.entries(collection).where((e) => e.id == entryId).firstOrNull;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntryEditor(store: widget.store, collection: collection, entry: entry),
      ),
    );
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

  Widget _wrapSection(String key, Widget child) => SectionTapRegion(
    sectionKey: key,
    label: layoutComponents[key] ?? key,
    selection: selection,
    onSelect: _select,
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

  void _startResize(String key) {
    final saved = _currentEntryFor(key);
    final h = saved.number('height', 0);
    final w = saved.number('width', 0);
    // 0/automatic starts from a sensible on-screen size rather than jumping
    // the section to 0px/full-bleed the instant the drag begins.
    _resize.start(key, baseHeight: h > 0 ? h : 240, baseWidth: w > 0 ? w : 600);
  }

  Future<void> _saveHeight(String key, double h) => _isPromoKey(key)
      ? adjustPromoDimension(widget.store, _promoId(key), 'height', h)
      : adjustSectionHeight(widget.store, key, h);

  Future<void> _saveWidth(String key, double w) => _isPromoKey(key)
      ? adjustPromoDimension(widget.store, _promoId(key), 'width', w)
      : adjustSectionWidth(widget.store, key, w);

  Future<void> _endResize(String key) => _resize.end(
    key,
    saveHeight: (h) => _saveHeight(key, h),
    saveWidth: (w) => _saveWidth(key, w),
  );

  // Wraps one individual ad/box promotion (not the whole rail — see
  // home_ad_rail.dart's wrapItem doc comment) in the exact same
  // SectionTapRegion/ResizeController machinery the 7 layout sections use,
  // just keyed by its own Firestore id so each one is selected, resized and
  // saved completely independently of its neighbors. Not reorderable here —
  // ad/box order isn't part of this bug fix's scope.
  Widget _wrapPromoItem(Entry entry, String kind, Widget child) {
    final key = '$_promoKeyPrefix${entry.id}';
    return SectionTapRegion(
      sectionKey: key,
      label: kind == 'ad' ? 'Ad' : 'Box',
      selection: selection,
      onSelect: _select,
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

  Future<void> _dropReorder(String draggedKey, {required String ontoKey}) async {
    final settings = widget.store.entries('settings');
    final ordered = [...reorderableHomeSections]
      ..sort((a, b) => sectionOrder(settings, a.key).compareTo(sectionOrder(settings, b.key)));
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
          SegmentedButton<_PreviewWidth>(
            segments: const [
              ButtonSegment(value: _PreviewWidth.desktop, icon: Icon(Icons.desktop_windows_outlined)),
              ButtonSegment(value: _PreviewWidth.tablet, icon: Icon(Icons.tablet_mac_outlined)),
              ButtonSegment(value: _PreviewWidth.mobile, icon: Icon(Icons.phone_iphone_outlined)),
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
                              size: Size(_simulatedWidth!, MediaQuery.sizeOf(context).height),
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
                        onAssistedSearch: (_) => _previewOnly('Voice/image search'),
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

  // Matches _startResize's own "0/automatic" fallback, so the pixel value
  // shown here is the same number a drag would start from, not a
  // momentarily-misleading 0px.
  double _displayHeight(String key) {
    final h = _currentEntryFor(key).number('height', 0);
    return h > 0 ? h : 240;
  }

  double _displayWidth(String key) {
    final w = _currentEntryFor(key).number('width', 0);
    return w > 0 ? w : 600;
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
                _isPromoKey(key) ? 'Advertisement / promo box' : layoutComponents[key] ?? key,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              onPressed: _closing ? null : () => _closeSelection(restoreSnapshot: true),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _closing ? null : () => _closeSelection(restoreSnapshot: false),
              child: _closing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Done'),
            ),
          ],
        ),
      ),
      // Promo items (ad/box) aren't part of the layoutComponents/
      // LayoutFieldsForm system below (they're individual promotions/<id>
      // docs, not settings/section_<key> docs) — so they get their own
      // pixel width/height row here. The 7 layout sections don't: their
      // Width/Height fields now live in LayoutFieldsForm itself (below,
      // with a "px" suffix), so showing them twice in two different places
      // would be confusing — one spot per field, not two.
      if (_isPromoKey(key))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              PixelField(
                label: 'Width',
                valuePx: _displayWidth(key),
                minPx: 80,
                maxPx: 3840,
                onChangedPx: (px) => _saveWidth(key, px),
              ),
              PixelField(
                label: 'Height',
                valuePx: _displayHeight(key),
                minPx: 40,
                maxPx: 1200,
                onChangedPx: (px) => _saveHeight(key, px),
              ),
            ],
          ),
        ),
      const Divider(),
      Expanded(
        child: _isPromoKey(key)
            ? Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Edit target, schedule, image & more'),
                  onPressed: () => _openFullEditor('promotions', entryId: _promoId(key)),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: LayoutFieldsForm(
                  key: ValueKey(key),
                  store: widget.store,
                  component: key,
                  autoSave: true,
                  onSaved: _onAutoSaved,
                ),
              ),
      ),
    ],
  );
}
