import 'package:flutter/material.dart';

import '../../data/store.dart';

/// Settings > Transport. Its own section, empty for now. Bus tracking and where seats are free or full are added here later.
class AdminTransportSection extends StatelessWidget {
  const AdminTransportSection({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Transport', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text('On the website: the Transport box under Today\'s Offers opens the Transport page, which says "త్వరలో వస్తుంది" (coming soon).'),
      const SizedBox(height: 16),
      const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nothing to set here yet. Bus tracking and which seats are free or full will be added here later.', key: ValueKey('admin-transport-empty')),
        ),
      ),
    ],
  );
}
