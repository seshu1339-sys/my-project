import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../services/strings.dart';
import 'design_tokens.dart';
import 'shared.dart';

class PromoCard extends StatelessWidget {
  const PromoCard({super.key, required this.entry, required this.onTap});
  final Entry entry;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final decoration = entryDecoration(entry, fallback: AppTokens.tintFor(entry.id.hashCode));
    // The wireframe's "ADS" rail wants plain, uniform boxes -- no eyebrow
    // label, no countdown badge -- unlike other promo placements (boxes,
    // offers), which keep their full card treatment unchanged.
    final isAd = entry.text('placement') == 'ad';
    final countdownSeconds = isAd ? 0 : entry.number('countdownSeconds', 0).round();
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(
        clampedNumber(entry, 'radius', AppTokens.radiusLg, 0, 80),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            _CardBody(entry: entry, decoration: decoration, showEyebrow: !isAd),
            if (countdownSeconds > 0)
              Positioned(
                top: 8,
                right: 8,
                child: _CountdownBadge(seconds: countdownSeconds),
              ),
          ],
        ),
      ),
    );
  }
}

class _CountdownBadge extends StatefulWidget {
  const _CountdownBadge({required this.seconds});
  final int seconds;
  @override
  State<_CountdownBadge> createState() => _CountdownBadgeState();
}

class _CountdownBadgeState extends State<_CountdownBadge> {
  late int remaining = widget.seconds;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => remaining = remaining > 0 ? remaining - 1 : widget.seconds);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = remaining ~/ 60;
    final secs = remaining % 60;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.entry, required this.decoration, this.showEyebrow = true});
  final Entry entry;
  final BoxDecoration decoration;
  final bool showEyebrow;
  @override
  Widget build(BuildContext context) {
    return Container(
          decoration: decoration.boxShadow == null
              ? decoration.copyWith(boxShadow: AppTokens.shadowSoft)
              : decoration,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: clampedNumber(entry, 'height', 200, 100, 1200),
            ),
            child: LayoutBuilder(
              builder: (context, c) => Padding(
                padding: EdgeInsets.all(
                  clampedNumber(entry, 'padding', 24, 0, c.maxWidth / 8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (entry.text('imageUrl').isNotEmpty)
                      ProductArt(entry, height: 100),
                    if (showEyebrow) ...[
                      Text(
                        (entry.text('placement') == 'ad'
                                ? 'NEIGHBOURHOOD SPOTLIGHT'
                                : 'CURATED FOR YOU')
                            .tr(context),
                        style: TextStyle(
                          fontSize: clampedNumber(
                            entry,
                            'labelFontSize',
                            10,
                            10,
                            24,
                          ),
                          color: colorFromHex(
                            entry.text('textColor'),
                            AppTokens.primaryDark,
                          ),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Text(
                      entry.text('name'),
                      style: TextStyle(
                        fontSize: clampedNumber(entry, 'fontSize', 25, 10, 40),
                        fontWeight: FontWeight.values.firstWhere(
                          (weight) =>
                              weight.value == entry.number('fontWeight', 700),
                          orElse: () => FontWeight.w700,
                        ),
                        color: colorFromHex(
                          entry.text('textColor'),
                          AppTokens.textPrimary,
                        ),
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      entry.text('description'),
                      style: TextStyle(
                        color: colorFromHex(
                          entry.text('textColor'),
                          AppTokens.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Icon(Icons.arrow_forward, color: colorFromHex(entry.text('textColor'), AppTokens.primary)),
                  ],
                ),
              ),
            ),
          ),
        );
  }
}

class CompactBanner extends StatelessWidget {
  const CompactBanner({super.key, required this.entry, required this.onTap});
  final Entry entry;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Container(
        decoration: entryDecoration(entry, fallback: AppTokens.primaryLight),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(clampedNumber(entry, 'padding', 16, 0, 40)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.text('imageUrl').isNotEmpty)
                  ProductArt(entry, height: 120),
                Text(
                  entry.text('name'),
                  style: sectionTextStyle(
                    entry,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(entry.text('description')),
                const SizedBox(height: 12),
                const Icon(Icons.arrow_forward),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
