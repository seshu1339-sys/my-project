import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/catalog.dart';

// Shop and service-provider star ratings (functions/modules/shop-ratings, owner 13 Nov 2026). A shop document and a provider's listing
// carry ratingAvg, ratingCount and ratingRecent (the three latest comments), so the lists and maps show them with no extra read. The
// full list is shopRatings (public: name, stars, comment; never a phone number or an account id).

/// "★ 4.3 (12)" for a shop or a provider listing; '' before the first rating.
String ratingLabel(Entry? place) {
  final count = place?.number('ratingCount') ?? 0;
  if (place == null || count <= 0) return '';
  final avg = place.number('ratingAvg');
  return '★ ${avg.toStringAsFixed(1)} (${count.round()})';
}

/// The latest comments carried on the shop or listing.
List<({String name, int stars, String comment})> recentRatings(Entry? place) => [
  for (final r in (place?.data['ratingRecent'] as List?) ?? const [])
    if (r is Map) (name: '${r['name'] ?? ''}', stars: (r['stars'] as num?)?.round() ?? 0, comment: '${r['comment'] ?? ''}'),
];

String stars(int n) => '★' * n.clamp(0, 5) + '☆' * (5 - n.clamp(0, 5));

/// The average, the latest comments and the "Rate" button, under a shop or a provider. [target] is what the server needs:
/// {'kind': 'shop', 'shopId'} or {'kind': 'provider', 'listingId'}.
class RatingsSection extends StatelessWidget {
  const RatingsSection({super.key, required this.store, required this.place, required this.target, required this.label, this.send});
  final Store store;
  final Entry place;
  final Map<String, dynamic> target;
  final String label;

  /// Test seam: sends the rating (rateShop by default).
  final Future<void> Function(Map<String, dynamic> data)? send;

  @override
  Widget build(BuildContext context) {
    final summary = ratingLabel(place);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(summary.isEmpty ? 'No ratings yet' : summary, key: const ValueKey('rating-summary'), style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        if (store.user != null) RateButton(store: store, target: target, label: label, send: send),
      ]),
      for (final r in recentRatings(place))
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${stars(r.stars)}  ${r.name}: ${r.comment}', key: ValueKey('rating-recent-${r.name}')),
        ),
    ]);
  }
}

/// "Rate": 1 to 5 stars, the name shown with it and an optional comment. Rating again replaces the customer's own rating.
class RateButton extends StatelessWidget {
  const RateButton({super.key, required this.store, required this.target, required this.label, this.send});
  final Store store;
  final Map<String, dynamic> target;
  final String label;
  final Future<void> Function(Map<String, dynamic> data)? send;

  Future<void> _rate(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _RateDialog(label: label, name: store.profileName));
    if (result == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = {...target, ...result};
      if (send != null) {
        await send!(data);
      } else {
        await store.call('rateShop', data);
      }
      messenger.showSnackBar(const SnackBar(content: Text('Thank you for your rating.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''))));
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: ValueKey('rate-${target['kind']}'),
    onPressed: () => _rate(context),
    icon: const Icon(Icons.star_outline, size: 18),
    label: const Text('Rate'),
  );
}

class _RateDialog extends StatefulWidget {
  const _RateDialog({required this.label, required this.name});
  final String label, name;
  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  int stars = 0;
  late final name = TextEditingController(text: widget.name);
  final comment = TextEditingController();

  @override
  void dispose() {
    name.dispose();
    comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Rate ${widget.label}'),
    content: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              key: ValueKey('rate-star-$i'),
              onPressed: () => setState(() => stars = i),
              icon: Icon(i <= stars ? Icons.star : Icons.star_border, color: Colors.amber.shade700, size: 32),
            ),
        ]),
        TextField(key: const ValueKey('rate-name'), controller: name, maxLength: 40, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Your name (shown with the rating)')),
        TextField(key: const ValueKey('rate-comment'), controller: comment, maxLength: 300, maxLines: 3, decoration: const InputDecoration(labelText: 'Comment (optional, no phone numbers)')),
      ]),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        key: const ValueKey('rate-send'),
        onPressed: stars == 0 || name.text.trim().length < 2 ? null : () => Navigator.pop(context, {'stars': stars, 'name': name.text.trim(), 'comment': comment.text.trim()}),
        child: const Text('Send'),
      ),
    ],
  );
}

/// A vendor's or provider's own ratings in their app: every name, star and comment (never who it was). [targetKey] is
/// `shop_<shopId>` or `provider_<uid>`.
class MyRatingsCard extends StatelessWidget {
  const MyRatingsCard({super.key, required this.store, required this.targetKey});
  final Store store;
  final String targetKey;

  @override
  Widget build(BuildContext context) {
    if (!store.live) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('shopRatings').where('targetKey', isEqualTo: targetKey).where('hidden', isEqualTo: false).limit(100).snapshots(),
      builder: (context, snap) {
        final ratings = [for (final d in snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) d.data()]
          ..sort((a, b) => ((b['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
        final avg = ratings.isEmpty ? 0 : ratings.fold<num>(0, (s, r) => s + ((r['stars'] as num?) ?? 0)) / ratings.length;
        return Card(
          key: const ValueKey('my-ratings'),
          child: ExpansionTile(
            leading: const Icon(Icons.star_outline),
            title: const Text('My ratings'),
            subtitle: Text(ratings.isEmpty ? 'No ratings yet' : '★ ${avg.toStringAsFixed(1)} from ${ratings.length} customers'),
            children: [
              for (final r in ratings)
                ListTile(
                  dense: true,
                  title: Text('${stars((r['stars'] as num?)?.round() ?? 0)}  ${r['name'] ?? ''}'),
                  subtitle: '${r['comment'] ?? ''}'.isEmpty ? null : Text('${r['comment']}'),
                ),
            ],
          ),
        );
      },
    );
  }
}
