import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import 'design_tokens.dart';
import 'shared.dart';
import 'text_animation.dart';

class HomeHeroSlide extends StatelessWidget {
  const HomeHeroSlide({super.key, required this.entry, required this.onTap});
  final Entry entry;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final wide = c.maxWidth >= 900;
      return Material(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        clipBehavior: Clip.antiAlias,
        color: colorFromHex(
          entry.text('backgroundColor'),
          AppTokens.primaryLight,
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned(
                right: -70,
                top: -110,
                child: Container(
                  width: 420,
                  height: 420,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTokens.primary.withValues(alpha: .10),
                  ),
                ),
              ),
              Positioned(
                right: 40,
                bottom: -130,
                child: Container(
                  width: 270,
                  height: 270,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTokens.primary.withValues(alpha: .06),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(
                  clampedNumber(entry, 'padding', wide ? 36 : 24, 0, 48),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .7),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'A LITTLE CLOSER TO HOME',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: 1.3,
                                fontWeight: FontWeight.w700,
                                color: AppTokens.primaryDark,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Flexible(
                            child: animatedText(entry, 'textAnimation', Text(
                              entry.text('name'),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  sectionTextStyle(
                                    entry,
                                    fontSize: wide ? 44 : 32,
                                    fontWeight: FontWeight.w800,
                                  ).copyWith(
                                    height: 1.05,
                                    letterSpacing: -1.5,
                                    color: colorFromHex(
                                      entry.text('textColor'),
                                      AppTokens.textPrimary,
                                    ),
                                  ),
                            )),
                          ),
                          const SizedBox(height: 16),
                          Flexible(
                            child: Text(
                              entry.text('description'),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                height: 1.5,
                                color: AppTokens.textMuted,
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              color: AppTokens.primary,
                              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                              boxShadow: AppTokens.shadowSoft,
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    'Shop the collection',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Icon(
                                  Icons.arrow_forward,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (wide) ...[
                      const SizedBox(width: 36),
                      Expanded(
                        flex: 2,
                        child: Transform.rotate(
                          angle: -.06,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .75),
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: .06),
                                  blurRadius: 30,
                                  offset: const Offset(0, 16),
                                ),
                              ],
                            ),
                            child: ProductArt(
                              entry.text('imageUrl').isEmpty
                                  ? const Entry('p3', {
                                      'name': 'Everyday essentials',
                                    })
                                  : entry,
                              height: 220,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (!wide && entry.text('imageUrl').isNotEmpty) ...[
                      const SizedBox(width: 12),
                      SizedBox(
                        width: c.maxWidth * .2,
                        child: ProductArt(entry, height: 120),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
