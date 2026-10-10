import 'package:flutter/material.dart';

import '../data/store.dart';
import 'shared.dart';

/// Saved-payment-card fields on the account page. `busy`/`run` are the
/// parent page's shared state/helper, passed in unchanged so this section's
/// buttons keep disabling together with the rest of the page exactly as
/// before the split.
class AccountPaymentCardSection extends StatelessWidget {
  const AccountPaymentCardSection({
    super.key,
    required this.store,
    required this.busy,
    required this.run,
    required this.cardBrand,
    required this.cardLast4,
  });
  final Store store;
  final bool busy;
  final Future<void> Function(Future<void> Function() action) run;
  final TextEditingController cardBrand;
  final TextEditingController cardLast4;

  Future<void> _manageSavedCards(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Manage saved cards'),
        content: Text(
          store.paymentLast4.isEmpty
              ? 'No saved cards.'
              : '${store.paymentBrand} ending in ${store.paymentLast4}',
        ),
        actions: [
          if (store.paymentLast4.isNotEmpty)
            TextButton(
              onPressed: () async {
                try {
                  await store.removePaymentCard();
                  if (dialog.mounted) Navigator.pop(dialog);
                } catch (e) {
                  if (dialog.mounted) message(dialog, e);
                }
              },
              child: const Text('Remove card'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Payment card', style: TextStyle(fontSize: 20)),
      const Text('Only the card brand and last four digits are stored.'),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: cardBrand,
              decoration: const InputDecoration(labelText: 'Brand'),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: TextField(
              controller: cardLast4,
              maxLength: 4,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Last 4'),
            ),
          ),
        ],
      ),
      OutlinedButton(
        onPressed: busy
            ? null
            : () => run(() async {
                if (!RegExp(r'^\d{4}$').hasMatch(cardLast4.text.trim())) {
                  throw StateError('Enter the last four card digits.');
                }
                await store.setPaymentCard(
                  cardBrand.text.trim().isEmpty ? 'Card' : cardBrand.text.trim(),
                  cardLast4.text.trim(),
                );
                if (context.mounted) {
                  message(context, 'Payment card saved');
                }
              }),
        child: const Text('Save payment card'),
      ),
      OutlinedButton.icon(
        onPressed: () => _manageSavedCards(context),
        icon: const Icon(Icons.credit_card_outlined),
        label: const Text('Manage saved cards'),
      ),
    ],
  );
}
