import 'package:flutter/material.dart';
import '../../domain/post_duration.dart' show showPostDayChoices;

/// One of the vendor's items the form offers to choose from: its photo is what the box shows.
class OfferItemChoice {
  const OfferItemChoice({required this.id, required this.name, required this.photoUrl, this.price});
  final String id, name, photoUrl;
  final num? price;
}

/// What the vendor filled in.
class OfferFormResult {
  const OfferFormResult({required this.productId, required this.price, required this.days, this.slot});
  final String productId;
  final num price;
  final int days;
  // The box to put it in (replacing what is there); null: the item's own box, else the first free one.
  final int? slot;
}

/// A vendor puts one of their items in Today's Offers: which item (its photo shows), the offer price and how long (1 week to 3 months).
/// Pops an [OfferFormResult], or null when cancelled.
class OfferFormDialog extends StatefulWidget {
  const OfferFormDialog({super.key, required this.items, required this.dayOptions, this.slot, this.initial, this.durationNote});
  final List<OfferItemChoice> items;
  // The admin's post duration, said to the vendor before posting (lib/domain/post_duration.dart).
  final String? durationNote;
  final Map<int, String> dayOptions;
  final int? slot;
  final OfferFormResult? initial;

  @override
  State<OfferFormDialog> createState() => _OfferFormDialogState();
}

class _OfferFormDialogState extends State<OfferFormDialog> {
  final formKey = GlobalKey<FormState>();
  late final price = TextEditingController(text: widget.initial == null ? '' : _plain(widget.initial!.price));
  late String? productId = widget.initial?.productId;
  // With the day choices hidden the longest choice is sent: the admin's post duration (server) ends the offer first.
  late int? days = showPostDayChoices ? widget.initial?.days : (widget.dayOptions.keys.isEmpty ? 7 : widget.dayOptions.keys.reduce((a, b) => a > b ? a : b));
  String? error;

  static String _plain(num p) => p == p.roundToDouble() ? '${p.toInt()}' : '$p';

  @override
  void dispose() {
    price.dispose();
    super.dispose();
  }

  void _send() {
    final ok = formKey.currentState!.validate();
    setState(() => error = productId == null ? 'Choose an item' : days == null ? 'Choose how long it shows' : null);
    if (!ok || error != null) return;
    Navigator.pop(context, OfferFormResult(productId: productId!, price: num.parse(price.text.trim()), days: days!, slot: widget.slot));
  }

  Widget _photo(String url) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: url.isEmpty
        ? const SizedBox(width: 56, height: 56, child: Icon(Icons.image_outlined))
        : Image.network(url, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 56, height: 56, child: Icon(Icons.image_outlined))),
  );

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return AlertDialog(
      title: Text(widget.slot == null ? "Today's Offers" : "Today's Offers: box ${widget.slot}"),
      content: SizedBox(
        width: 400,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Which item? Its photo shows in the box.', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              if (widget.items.isEmpty) const Text('Add an item with a photo first (My items).', key: ValueKey('todays-offer-no-items')),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final item in widget.items)
                  InkWell(
                    key: ValueKey('todays-offer-item-${item.id}'),
                    onTap: () => setState(() {
                      productId = item.id;
                      error = null;
                      if (price.text.trim().isEmpty && item.price != null) price.text = _plain(item.price!);
                    }),
                    child: Container(
                      width: 84,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(border: Border.all(color: productId == item.id ? primary : Colors.black12, width: productId == item.id ? 3 : 1), borderRadius: BorderRadius.circular(8)),
                      child: Column(children: [
                        _photo(item.photoUrl),
                        Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                  ),
              ]),
              TextFormField(
                key: const ValueKey('todays-offer-price'),
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Offer price (₹)'),
                validator: (v) => (num.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Enter a price above 0' : null,
              ),
              const SizedBox(height: 12),
              if (widget.durationNote != null) Text(widget.durationNote!, key: const ValueKey('todays-offer-duration-note')),
              if (showPostDayChoices) const Text("How long should it show in Today's Offers?"),
              if (showPostDayChoices) Wrap(spacing: 8, children: [
                for (final option in widget.dayOptions.entries)
                  ChoiceChip(
                    key: ValueKey('todays-offer-days-${option.key}'),
                    label: Text(option.value),
                    selected: days == option.key,
                    onSelected: (_) => setState(() => days = option.key),
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
}
