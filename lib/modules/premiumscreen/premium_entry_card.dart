import 'package:flutter/material.dart';

/// The card in the vendor workspace that opens the Premium screen. Shown only to Premium vendors, by whoever places it.
class PremiumEntryCard extends StatelessWidget {
  const PremiumEntryCard({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      key: const ValueKey('premium-entry'),
      leading: const Icon(Icons.local_offer_outlined),
      title: const Text("Today's Offer", style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle: const Text('Your offer for nearby customers, and wholesale offers'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onOpen,
    ),
  );
}
