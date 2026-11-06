import 'package:flutter/material.dart';

/// The paid vendor's screen: the Today's Offers boxes on top (scrolling when there are many) and the large box below it, filling the
/// screen to the bottom.
class PremiumOfferScreen extends StatelessWidget {
  const PremiumOfferScreen({super.key, required this.offerBox, required this.largeBox});
  final Widget offerBox, largeBox;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Today's Offers")),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(
          builder: (context, size) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ConstrainedBox(constraints: BoxConstraints(maxHeight: size.maxHeight * 0.55), child: SingleChildScrollView(child: offerBox)),
            Expanded(child: largeBox),
          ]),
        ),
      ),
    ),
  );
}

/// Shown instead when the plan ended while the screen was open.
class PremiumEndedScreen extends StatelessWidget {
  const PremiumEndedScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Today's Offers")),
    body: const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Your plan has ended. Choose a plan to use this again.', key: ValueKey('premium-ended'), textAlign: TextAlign.center))),
  );
}
