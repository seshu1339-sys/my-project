import 'package:flutter/material.dart';

import 'offer_form_dialog.dart';

/// What the panel shows of the vendor's running offer.
class RunningOffer {
  const RunningOffer({required this.photoUrl, required this.price, required this.endsAt});
  final String photoUrl;
  final num price;
  final DateTime endsAt;
}

/// The Today's Offer box: the running offer if there is one, and the button to make one or replace it.
class TodaysOfferPanel extends StatefulWidget {
  const TodaysOfferPanel({super.key, required this.offer, required this.hourOptions, required this.onSubmit, this.pickPhoto});
  final RunningOffer? offer;
  final List<int> hourOptions;
  final Future<void> Function(OfferFormResult result) onSubmit;
  final PickOfferPhoto? pickPhoto;

  @override
  State<TodaysOfferPanel> createState() => _TodaysOfferPanelState();
}

class _TodaysOfferPanelState extends State<TodaysOfferPanel> {
  bool busy = false;

  Future<void> _create() async {
    final result = await showDialog<OfferFormResult>(context: context, builder: (_) => OfferFormDialog(hourOptions: widget.hourOptions, pickPhoto: widget.pickPhoto));
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      await widget.onSubmit(result);
      messenger.showSnackBar(const SnackBar(content: Text('Your offer is live')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() => busy = false);
  }

  String _time(DateTime t) => '${t.day}/${t.month}/${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  String _price(num p) => p == p.roundToDouble() ? '₹${p.round()}' : '₹${p.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    return Card(
      key: const ValueKey('todays-offer-panel'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          if (offer != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(offer.photoUrl, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 64, height: 64, child: Icon(Icons.image_not_supported_outlined))),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: offer == null
                ? const Text('No offer is running. Add a photo and a price; it goes live at once.', key: ValueKey('todays-offer-none'))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_price(offer.price), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    Text('Live until ${_time(offer.endsAt)}', key: const ValueKey('todays-offer-until')),
                  ]),
          ),
          const SizedBox(width: 8),
          FilledButton(key: const ValueKey('todays-offer-create'), onPressed: busy ? null : _create, child: Text(offer == null ? 'Create' : 'Replace')),
        ]),
      ),
    );
  }
}
