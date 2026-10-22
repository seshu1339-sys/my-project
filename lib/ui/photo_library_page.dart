import 'package:flutter/material.dart';

import 'photo_library_data.dart';

/// "Fancy items" for the folder name `fancy-items`: the name the customer sees.
String photoCategoryTitle(String folder) =>
    folder.split('-').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

/// "Bulb holder" for `bulb-holder.webp`.
String photoTitle(String file) {
  final name = file.replaceAll(RegExp(r'\.webp$'), '').replaceAll('-', ' ');
  return name.isEmpty ? name : '${name[0].toUpperCase()}${name.substring(1)}';
}

/// The address of one photo. Folder and file names are lower case with hyphens, e.g. /images/fancy-items/anklet.webp.
String photoUrl(String folder, String file) => Uri.base.resolve('/images/$folder/$file').toString();

/// A page of product photos: one section per category folder, each a grid. The grids are built only as they scroll into view, so a
/// photo is not downloaded until it is about to be seen.
class PhotoLibraryPage extends StatelessWidget {
  const PhotoLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1100 ? 6 : width >= 700 ? 4 : 2;
    return Scaffold(
      appBar: AppBar(title: const Text('Photo library')),
      body: CustomScrollView(
        key: const ValueKey('photo-library'),
        slivers: [
          for (final entry in photoLibrary.entries) ...[
            SliverToBoxAdapter(
              child: Padding(
                key: ValueKey('photo-section-${entry.key}'),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(photoCategoryTitle(entry.key), style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: .85,
                ),
                itemCount: entry.value.length,
                itemBuilder: (context, i) {
                  final file = entry.value[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            photoUrl(entry.key, file),
                            fit: BoxFit.cover,
                            cacheWidth: 400,
                            errorBuilder: (_, _, _) => const ColoredBox(color: Color(0x11000000), child: Icon(Icons.image_not_supported_outlined)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(photoTitle(file), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                    ],
                  );
                },
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
