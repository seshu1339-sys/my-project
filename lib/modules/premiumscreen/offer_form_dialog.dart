import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/post_duration.dart' show showPostDayChoices;

/// One of the vendor's items (or a catalog item) the form offers to choose from: its photo is what the box shows.
class OfferItemChoice {
  const OfferItemChoice({required this.id, required this.name, required this.photoUrl, this.price, this.keywords = ''});
  final String id, name, photoUrl;
  final num? price;
  // Catalog search words besides the name (the library's tags).
  final String keywords;
}

/// What the vendor filled in: exactly one of [productId] (their item), [libraryItemId] (a catalog item) or [photo] (their own photo, with
/// the item's [name]); the price; an optional short [note]; [days] null = while the plan runs.
class OfferFormResult {
  const OfferFormResult({this.productId = '', this.libraryItemId = '', this.photo, this.name = '', this.note = '', required this.price, this.days, this.slot});
  final String productId, libraryItemId, name, note;
  final Uint8List? photo;
  final num price;
  final int? days;
  // The box to put it in (replacing what is there); null: the item's own box, else the first free one.
  final int? slot;
}

/// Where the box's photo comes from.
enum OfferSource { items, catalog, photo }

/// The longest offer text (functions/modules/todays-offer/rules.js NOTE_MAX).
const offerNoteMax = 60;

/// A vendor fills a Today's Offers box (owner, 13 Nov 2026): one of their items, an item from the catalog, or their own photo (checked
/// automatically), the offer price and a short text. It stays live while the plan runs. Pops an [OfferFormResult], or null when cancelled.
class OfferFormDialog extends StatefulWidget {
  const OfferFormDialog({super.key, required this.items, required this.dayOptions, this.catalog = const [], this.slot, this.initial, this.durationNote, this.pickPhoto});
  final List<OfferItemChoice> items;
  // The catalog (Product Image Library): items with a stock photo.
  final List<OfferItemChoice> catalog;
  // What is said about how long the box shows.
  final String? durationNote;
  final Map<int, String> dayOptions;
  final int? slot;
  final OfferFormResult? initial;
  // Picks and shrinks the vendor's own photo; null uses the phone's gallery.
  final Future<Uint8List?> Function()? pickPhoto;

  @override
  State<OfferFormDialog> createState() => _OfferFormDialogState();
}

class _OfferFormDialogState extends State<OfferFormDialog> {
  final formKey = GlobalKey<FormState>();
  late final price = TextEditingController(text: widget.initial == null ? '' : _plain(widget.initial!.price));
  late final note = TextEditingController(text: widget.initial?.note ?? '');
  final name = TextEditingController();
  final search = TextEditingController();
  late OfferSource source = (widget.initial?.libraryItemId.isNotEmpty ?? false) ? OfferSource.catalog : OfferSource.items;
  late String? productId = (widget.initial?.productId.isEmpty ?? true) ? null : widget.initial!.productId;
  late String? libraryItemId = (widget.initial?.libraryItemId.isEmpty ?? true) ? null : widget.initial!.libraryItemId;
  Uint8List? photo;
  // While the plan runs (owner, 13 Nov 2026), unless the day choices are shown and the vendor picks one.
  late bool untilPlan = !showPostDayChoices || (widget.initial != null && widget.initial!.days == null);
  late int? days = showPostDayChoices ? widget.initial?.days : null;
  String? error;

  static String _plain(num p) => p == p.roundToDouble() ? '${p.toInt()}' : '$p';

  @override
  void dispose() {
    price.dispose();
    note.dispose();
    name.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final pick = widget.pickPhoto ??
        () async {
          final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 75);
          return file?.readAsBytes();
        };
    final bytes = await pick();
    if (bytes != null && mounted) setState(() => photo = bytes);
  }

  String? _missing() => switch (source) {
    OfferSource.items => productId == null ? 'Choose an item' : null,
    OfferSource.catalog => libraryItemId == null ? 'Choose an item from the catalog' : null,
    OfferSource.photo => photo == null ? 'Add your photo' : name.text.trim().length < 2 ? 'Enter the item name' : null,
  };

  void _send() {
    final ok = formKey.currentState!.validate();
    setState(() => error = _missing() ?? (!untilPlan && days == null ? 'Choose how long it shows' : null));
    if (!ok || error != null) return;
    Navigator.pop(
      context,
      OfferFormResult(
        productId: source == OfferSource.items ? productId! : '',
        libraryItemId: source == OfferSource.catalog ? libraryItemId! : '',
        photo: source == OfferSource.photo ? photo : null,
        name: source == OfferSource.photo ? name.text.trim() : '',
        note: note.text.trim(),
        price: num.parse(price.text.trim()),
        days: untilPlan ? null : days,
        slot: widget.slot,
      ),
    );
  }

  Widget _photo(String url) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: url.isEmpty
        ? const SizedBox(width: 56, height: 56, child: Icon(Icons.image_outlined))
        : Image.network(url, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 56, height: 56, child: Icon(Icons.image_outlined))),
  );

  Widget _choices(List<OfferItemChoice> list, String keyPrefix, String? chosen, void Function(OfferItemChoice item) onTap) {
    final primary = Theme.of(context).colorScheme.primary;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final item in list)
        InkWell(
          key: ValueKey('$keyPrefix${item.id}'),
          onTap: () => setState(() {
            onTap(item);
            error = null;
            if (price.text.trim().isEmpty && item.price != null) price.text = _plain(item.price!);
          }),
          child: Container(
            width: 84,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(border: Border.all(color: chosen == item.id ? primary : Colors.black12, width: chosen == item.id ? 3 : 1), borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              _photo(item.photoUrl),
              Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
    ]);
  }

  List<Widget> _sourcePart() {
    switch (source) {
      case OfferSource.items:
        return [
          const Text('Which item? Its photo shows in the box.', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (widget.items.isEmpty) const Text('Add an item with a photo first (My items), or choose from the catalog.', key: ValueKey('todays-offer-no-items')),
          _choices(widget.items, 'todays-offer-item-', productId, (item) => productId = item.id),
        ];
      case OfferSource.catalog:
        final query = search.text.trim().toLowerCase();
        final found = [
          for (final item in widget.catalog)
            if (query.isEmpty || '${item.name} ${item.keywords}'.toLowerCase().contains(query)) item,
        ].take(24).toList();
        return [
          TextField(
            key: const ValueKey('todays-offer-catalog-search'),
            controller: search,
            decoration: const InputDecoration(labelText: 'Search the catalog', prefixIcon: Icon(Icons.search)),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          if (found.isEmpty) const Text('Nothing in the catalog matches. Add your own photo instead.', key: ValueKey('todays-offer-catalog-empty')),
          _choices(found, 'todays-offer-catalog-', libraryItemId, (item) => libraryItemId = item.id),
        ];
      case OfferSource.photo:
        return [
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: photo == null
                  ? const SizedBox(width: 72, height: 72, child: Icon(Icons.add_a_photo_outlined))
                  : Image.memory(photo!, key: const ValueKey('todays-offer-photo-preview'), width: 72, height: 72, fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('todays-offer-photo-pick'),
                onPressed: _pick,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(photo == null ? 'Choose a photo' : 'Change photo'),
              ),
            ),
          ]),
          const Text('Your photo is checked automatically. Drugs, weapons, alcohol, cigarettes or tobacco and adult photos are not allowed.', style: TextStyle(fontSize: 12)),
          TextFormField(
            key: const ValueKey('todays-offer-name'),
            controller: name,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'Item name'),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.slot == null ? "Today's Offers" : "Today's Offers: box ${widget.slot}"),
    content: SizedBox(
      width: 420,
      child: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SegmentedButton<OfferSource>(
              key: const ValueKey('todays-offer-source'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: OfferSource.items, label: Text('My items', key: ValueKey('todays-offer-source-items'))),
                ButtonSegment(value: OfferSource.catalog, label: Text('Catalog', key: ValueKey('todays-offer-source-catalog'))),
                ButtonSegment(value: OfferSource.photo, label: Text('My photo', key: ValueKey('todays-offer-source-photo'))),
              ],
              selected: {source},
              onSelectionChanged: (v) => setState(() {
                source = v.first;
                error = null;
              }),
            ),
            const SizedBox(height: 10),
            ..._sourcePart(),
            TextFormField(
              key: const ValueKey('todays-offer-price'),
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Offer price (₹)'),
              validator: (v) => (num.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Enter a price above 0' : null,
            ),
            TextFormField(
              key: const ValueKey('todays-offer-note'),
              controller: note,
              maxLength: offerNoteMax,
              decoration: const InputDecoration(labelText: 'Offer text (optional)', hintText: 'e.g. 2 kg only today'),
            ),
            const SizedBox(height: 4),
            if (widget.durationNote != null) Text(widget.durationNote!, key: const ValueKey('todays-offer-duration-note')),
            if (showPostDayChoices) const Text("How long should it show in Today's Offers?"),
            if (showPostDayChoices)
              Wrap(spacing: 8, children: [
                ChoiceChip(
                  key: const ValueKey('todays-offer-days-plan'),
                  label: const Text('While my plan runs'),
                  selected: untilPlan,
                  onSelected: (_) => setState(() {
                    untilPlan = true;
                    days = null;
                  }),
                ),
                for (final option in widget.dayOptions.entries)
                  ChoiceChip(
                    key: ValueKey('todays-offer-days-${option.key}'),
                    label: Text(option.value),
                    selected: !untilPlan && days == option.key,
                    onSelected: (_) => setState(() {
                      untilPlan = false;
                      days = option.key;
                    }),
                  ),
              ]),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, key: const ValueKey('todays-offer-error'), style: const TextStyle(color: Colors.red))),
          ]),
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const ValueKey('todays-offer-send'), onPressed: _send, child: const Text('Go live')),
    ],
  );
}
