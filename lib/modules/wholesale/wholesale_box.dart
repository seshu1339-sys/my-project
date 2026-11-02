import 'package:flutter/material.dart';

import 'wholesale_offer.dart';

/// Reads the offers and shows them. It is given where they come from and what a tap does.
class WholesaleBox extends StatefulWidget {
  const WholesaleBox({super.key, required this.source, required this.onCall});
  final WholesaleOffers source;
  final ValueChanged<String> onCall;

  @override
  State<WholesaleBox> createState() => _WholesaleBoxState();
}

class _WholesaleBoxState extends State<WholesaleBox> {
  late final stream = widget.source.watch();

  @override
  Widget build(BuildContext context) => StreamBuilder<List<WholesaleOffer>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('Wholesale offers could not load.'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      return WholesaleList(offers: snapshot.data!, onCall: widget.onCall);
    },
  );
}

/// The large box: a heading and the cards, scrolling inside the space it is given.
class WholesaleList extends StatelessWidget {
  const WholesaleList({super.key, required this.offers, required this.onCall});
  final List<WholesaleOffer> offers;
  final ValueChanged<String> onCall;

  @override
  Widget build(BuildContext context) => Card(
    key: const ValueKey('wholesale-box'),
    clipBehavior: Clip.antiAlias,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('Wholesale offers', style: TextStyle(fontWeight: FontWeight.bold))),
      Expanded(
        child: offers.isEmpty
            ? const Center(child: Text('No wholesale offers right now.', key: ValueKey('wholesale-empty')))
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: offers.length,
                itemBuilder: (context, i) => _WholesaleCard(offer: offers[i], onCall: onCall),
              ),
      ),
    ]),
  );
}

class _WholesaleCard extends StatelessWidget {
  const _WholesaleCard({required this.offer, required this.onCall});
  final WholesaleOffer offer;
  final ValueChanged<String> onCall;

  String get _price => offer.price == offer.price.roundToDouble() ? '₹${offer.price.round()}' : '₹${offer.price.toStringAsFixed(2)}';
  String get _valid => '${offer.validUntil.day}/${offer.validUntil.month}/${offer.validUntil.year}';

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('wholesale-${offer.id}'),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => onCall(offer.phone),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(offer.photoUrl, width: 84, height: 84, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 84, height: 84, child: Icon(Icons.image_not_supported_outlined))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(offer.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('$_price wholesale', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Minimum: ${offer.minQuantity}'),
              Text('Valid until $_valid'),
              Text(offer.wholesaler),
              Row(children: [
                const Icon(Icons.call_outlined, size: 16),
                const SizedBox(width: 4),
                Flexible(child: Text(offer.phone)),
              ]),
            ]),
          ),
        ]),
      ),
    ),
  );
}
