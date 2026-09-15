import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import 'shared.dart';

class HomeHeroSlide extends StatelessWidget {
  const HomeHeroSlide({super.key, required this.entry, required this.onTap});
  final Entry entry;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final wide = c.maxWidth >= 900;
      return Material(
        color: const Color(0xffdfebd7),
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
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xffcfdfbf),
                  ),
                ),
              ),
              Positioned(
                right: 40,
                bottom: -130,
                child: Container(
                  width: 270,
                  height: 270,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xffe8f0e0),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(wide ? 36 : 24),
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
                              color: Colors.white.withValues(alpha: .65),
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
                                color: Color(0xff176b50),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Flexible(
                            child: Text(
                              entry.text('name'),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: wide ? 44 : 32,
                                height: 1.05,
                                letterSpacing: -1.5,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xff163e2e),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Flexible(
                            child: Text(
                              entry.text('description'),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                height: 1.5,
                                color: Color(0xff46634c),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xff176b50),
                              borderRadius: BorderRadius.circular(12),
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
