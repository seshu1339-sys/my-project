import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import 'shared.dart';

class HomeSectionHeading extends StatelessWidget {
  const HomeSectionHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
    this.actionLabel = 'View all',
    this.appearance,
  });
  final String title, subtitle, actionLabel;
  final VoidCallback? action;
  final Entry? appearance;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: LayoutBuilder(
      builder: (context, c) {
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: sectionTextStyle(
                appearance ?? const Entry('', {}),
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        );
        final button = action == null
            ? null
            : TextButton(onPressed: action, child: Text(actionLabel));
        if (c.maxWidth < 600 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, ?button],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            ?button,
          ],
        );
      },
    ),
  );
}
