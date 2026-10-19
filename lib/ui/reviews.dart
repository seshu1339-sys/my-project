import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import 'account.dart';
import 'layout_settings.dart';
import 'shared.dart';

class Reviews extends StatefulWidget {
  const Reviews({super.key, required this.store, required this.productId});
  final Store store;
  final String productId;
  @override
  State<Reviews> createState() => _ReviewsState();
}

class _ReviewsState extends State<Reviews> {
  final review = TextEditingController();
  int rating = 5;
  bool busy = false;
  @override
  void dispose() {
    review.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      pageHeadingText(
        context,
        layout: layoutFor(
          context,
          widget.store.entries('settings'),
          'productPageReviewsHeading',
        ),
        defaultText: 'Community reviews',
      ),
      const SizedBox(height: 12),
      if (!widget.store.live)
        const Text('Reviews are available when Firebase is connected.')
      else ...[
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('products')
              .doc(widget.productId)
              .collection('reviews')
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Text('Reviews could not load. Please retry later.');
            }
            if (!snap.hasData) {
              return const LinearProgressIndicator();
            }
            if (snap.data!.docs.isEmpty) {
              return const Text('No reviews yet. Share your experience.');
            }
            return Column(
              children: snap.data!.docs
                  .map(
                    (d) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${'★' * (d.data()['rating'] as num).toInt()} • ${(d.data()['name'] as String?)?.isNotEmpty == true ? d.data()['name'] : 'Neighbour'}',
                      ),
                      subtitle: Text(d.data()['text'] as String),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        if (widget.store.user != null) ...[
          const SizedBox(height: 16),
          Wrap(
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  tooltip: '$i stars',
                  onPressed: () => setState(() => rating = i),
                  icon: Icon(
                    i <= rating ? Icons.star : Icons.star_border,
                    color: Colors.amber.shade800,
                  ),
                ),
            ],
          ),
          TextField(
            controller: review,
            maxLength: 1000,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Your review'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (review.text.trim().isEmpty) {
                      message(context, 'Write a review first');
                      return;
                    }
                    setState(() => busy = true);
                    try {
                      await widget.store.call('submitVerifiedReview', {
                        'productId': widget.productId,
                        'name': widget.store.profileName.isEmpty
                            ? 'Neighbour'
                            : widget.store.profileName,
                        'rating': rating,
                        'text': review.text.trim(),
                      });
                      if (context.mounted) {
                        message(context, 'Verified review saved');
                        review.clear();
                      }
                    } catch (e) {
                      if (context.mounted) {
                        message(context, e);
                      }
                    } finally {
                      if (mounted) {
                        setState(() => busy = false);
                      }
                    }
                  },
            child: const Text('Publish review'),
          ),
        ] else
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => AccountPage(store: widget.store),
              ),
            ),
            child: const Text('Sign in to write a review'),
          ),
      ],
    ],
  );
}
