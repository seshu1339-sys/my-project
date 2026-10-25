import 'package:flutter/material.dart';

import '../../services/strings.dart';

/// The text on the Transport page until the real feature (bus tracking, free and full seats) is added.
const transportComingSoon = 'త్వరలో వస్తుంది';

/// The Transport page. Empty for now: it only says it is coming soon.
class TransportPage extends StatelessWidget {
  const TransportPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Transport'.tr(context))),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          transportComingSoon,
          key: ValueKey('transport-coming-soon'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}
