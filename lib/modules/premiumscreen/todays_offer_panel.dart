import 'package:flutter/material.dart';

import 'offer_form_dialog.dart';

/// What the panel shows of one running box.
class RunningOffer {
  const RunningOffer({required this.photoUrl, required this.price, required this.endsAt, this.slot = 1, this.productId = '', this.name = '', this.days = 0});
  final String photoUrl, productId, name;
  final num price;
  final DateTime endsAt;
  final int slot, days;
}

/// The vendor's Today's Offers boxes (as many as the plan gives): each running box with its item, price and end, marked LIVE in its own
/// colour, and a button to fill an empty box or change one.
class TodaysOfferPanel extends StatefulWidget {
  const TodaysOfferPanel({super.key, required this.offers, required this.boxes, required this.items, required this.dayOptions, required this.onSubmit, this.onRemove, this.durationNote});
  final List<RunningOffer> offers;
  // The admin's post duration, said before posting (lib/domain/post_duration.dart).
  final String? durationNote;
  final int boxes;
  final List<OfferItemChoice> items;
  final Map<int, String> dayOptions;
  final Future<void> Function(OfferFormResult result) onSubmit;
  final Future<void> Function(int slot)? onRemove;

  /// The colour a live box is marked in, here and in the vendor's item list.
  static const liveColour = Color(0xFFE65100);

  @override
  State<TodaysOfferPanel> createState() => _TodaysOfferPanelState();
}

class _TodaysOfferPanelState extends State<TodaysOfferPanel> {
  bool busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _fill(int slot, RunningOffer? running) async {
    final result = await showDialog<OfferFormResult>(
      context: context,
      builder: (_) => OfferFormDialog(
        items: widget.items,
        dayOptions: widget.dayOptions,
        durationNote: widget.durationNote,
        slot: slot,
        initial: running == null ? null : OfferFormResult(productId: running.productId, price: running.price, days: running.days, slot: slot),
      ),
    );
    if (result == null || !mounted) return;
    await _run(() => widget.onSubmit(result), 'Your offer is live');
  }

  String _date(DateTime t) => '${t.day}/${t.month}/${t.year}';
  String _price(num p) => p == p.roundToDouble() ? '₹${p.round()}' : '₹${p.toStringAsFixed(2)}';

  Widget _box(int slot) {
    final running = widget.offers.where((o) => o.slot == slot).firstOrNull;
    return Card(
      key: ValueKey('todays-offer-box-$slot'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: running == null ? const BorderSide(color: Colors.black12) : const BorderSide(color: TodaysOfferPanel.liveColour, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          if (running != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(running.photoUrl, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 56, height: 56, child: Icon(Icons.image_not_supported_outlined))),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: running == null
                ? Text('Box $slot is empty. Choose one of your items to show here.', key: ValueKey('todays-offer-empty-$slot'))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        key: ValueKey('todays-offer-live-$slot'),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: TodaysOfferPanel.liveColour, borderRadius: BorderRadius.circular(4)),
                        child: const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                      const SizedBox(width: 6),
                      Flexible(child: Text(running.name.isEmpty ? 'Box $slot' : running.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                    ]),
                    Text(_price(running.price), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: TodaysOfferPanel.liveColour)),
                    Text('Shows until ${_date(running.endsAt)}', key: ValueKey('todays-offer-until-$slot')),
                  ]),
          ),
          const SizedBox(width: 8),
          Column(mainAxisSize: MainAxisSize.min, children: [
            FilledButton(key: ValueKey('todays-offer-fill-$slot'), onPressed: busy ? null : () => _fill(slot, running), child: Text(running == null ? 'Choose' : 'Change')),
            if (running != null && widget.onRemove != null)
              TextButton(key: ValueKey('todays-offer-remove-$slot'), onPressed: busy ? null : () => _run(() => widget.onRemove!(slot), 'Box $slot is empty now'), child: const Text('Remove')),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('todays-offer-panel'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          widget.boxes == 0
              ? "Your plan has no Today's Offers boxes."
              : "Your plan gives ${widget.boxes} Today's Offers ${widget.boxes == 1 ? 'box' : 'boxes'}. Customers within your plan's km see them.",
          key: const ValueKey('todays-offer-count'),
        ),
      ),
      for (var slot = 1; slot <= widget.boxes; slot++) _box(slot),
    ],
  );
}
