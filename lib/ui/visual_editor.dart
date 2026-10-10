import 'dart:async';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/app_theme.dart';
import '../services/search.dart';
import 'entry_editor.dart';
import 'layout_editor.dart';
import 'layout_settings.dart';
import 'shared.dart';
import 'visual_editor_overlay.dart';
import 'wireframe_home.dart';

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

  // Real drag-to-resize state: the handle reports raw local dy on every
  // pointer-move event (can fire 60+ times/sec), so writes are throttled to
  // avoid hammering Firestore while the drag is live, with one final,
  // un-throttled write on release so the committed value always matches
  // exactly where the pointer was let go.
  String? _resizingKey;
  double _resizeBaseHeight = 0;
  double _resizeStartDy = 0;
  bool _resizeOriginSet = false;
  double _resizeLiveHeight = 0;
  DateTime _lastResizeWrite = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    selection.dispose();
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _previewOnly(String what) => message(context, '$what — open the live site to try this for real.');

  void _select(String key) {
    _history
      ..clear()
      ..add(Map<String, dynamic>.from(sectionConfig(widget.store.entries('settings'), key).data));
    _historyIndex = 0;
    selection.value = key;
  }

  Future<void> _closeSelection({required bool restoreSnapshot}) async {
    final key = selection.value;
    if (key != null && restoreSnapshot && _history.isNotEmpty) {
      await widget.store.save('settings', Entry('section_$key', _history.first));
    }
    selection.value = null;
    _history.clear();
    _historyIndex = 0;
  }

  void _onAutoSaved() {
    final key = selection.value;
    if (key == null) return;
    final current = Map<String, dynamic>.from(sectionConfig(widget.store.entries('settings'), key).data);
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
    await widget.store.save('settings', Entry('section_$key', _history[_historyIndex]));
    setState(() {});
  }

  Future<void> _redo() async {
    final key = selection.value;
    if (key == null || _historyIndex >= _history.length - 1) return;
    _historyIndex++;
    await widget.store.save('settings', Entry('section_$key', _history[_historyIndex]));
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
    liveHeightLabel: _resizingKey == key ? '${_resizeLiveHeight.round()}px' : null,
    onResizeDragStart: () => _startResize(key),
    onResizeDragUpdate: (dy) => _updateResize(key, dy),
    onResizeDragEnd: () => _endResize(key),
    child: child,
  );

  void _startResize(String key) {
    final saved = sectionConfig(widget.store.entries('settings'), key);
    final current = saved.number('height', 0);
    setState(() {
      _resizingKey = key;
      // 0/automatic starts from a sensible on-screen size rather than
      // jumping the section to 0px the instant the drag begins.
      _resizeBaseHeight = current > 0 ? current : 240;
      _resizeOriginSet = false;
      _resizeLiveHeight = _resizeBaseHeight;
    });
  }

  void _updateResize(String key, double dy) {
    if (_resizingKey != key) return;
    // First callback of the drag establishes the local-coordinate origin;
    // every later one reports dy relative to the SAME fixed handle origin
    // (GestureDetector's localPosition is relative to the handle itself,
    // which doesn't move during the drag), so the raw delta from the first
    // sample is exactly the total drag distance.
    if (!_resizeOriginSet) {
      _resizeOriginSet = true;
      _resizeStartDy = dy;
    }
    final next = (_resizeBaseHeight + (dy - _resizeStartDy)).clamp(40.0, 1200.0);
    setState(() => _resizeLiveHeight = next);
    final now = DateTime.now();
    if (now.difference(_lastResizeWrite) > const Duration(milliseconds: 120)) {
      _lastResizeWrite = now;
      adjustSectionHeight(widget.store, key, next);
    }
  }

  Future<void> _endResize(String key) async {
    if (_resizingKey != key) return;
    final finalHeight = _resizeLiveHeight;
    setState(() {
      _resizingKey = null;
      _resizeStartDy = 0;
    });
    // Un-throttled final write so the committed value always matches
    // exactly where the pointer was released, even if the last live write
    // was skipped by the throttle window.
    await adjustSectionHeight(widget.store, key, finalHeight);
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
                      child: SingleChildScrollView(
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

  Widget _inlinePanel(String key) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                layoutComponents[key] ?? key,
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
              onPressed: () => _closeSelection(restoreSnapshot: true),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _closeSelection(restoreSnapshot: false),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
      const Divider(),
      Expanded(
        child: SingleChildScrollView(
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
