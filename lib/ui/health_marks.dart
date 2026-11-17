import 'package:flutter/material.dart';

import '../services/health_watch.dart';

/// The red mark next to an option whose health check fails now (owner spec H). Nothing when it works.
class HealthMark extends StatelessWidget {
  const HealthMark({super.key, required this.registryId});
  final String registryId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: HealthWatch.instance,
    builder: (context, _) {
      final failing = HealthWatch.instance.status.failingFor(registryId);
      if (failing.isEmpty) return const SizedBox.shrink();
      return Tooltip(
        message: [for (final c in failing) '${c.name}: ${c.error}'].join('\n'),
        child: Container(key: ValueKey('health-mark-$registryId'), width: 10, height: 10, margin: const EdgeInsets.symmetric(horizontal: 4), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
      );
    },
  );
}

/// The title of a list row with the red mark after it.
Widget withHealthMark(Widget title, String registryId) => Row(children: [Flexible(child: title), HealthMark(registryId: registryId)]);
