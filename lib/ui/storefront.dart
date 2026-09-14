import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/search.dart';
import 'account.dart';
import 'admin.dart';
import 'details.dart';
import 'shared.dart';

class Storefront extends StatefulWidget {
  const Storefront({
    super.key,
    required this.store,
    this.searchService = const SmartSearch(),
  });
  final Store store;
  final SmartSearch searchService;
  @override
  State<Storefront> createState() => _StorefrontState();
}

class _StorefrontState extends State<Storefront> {
  final search = TextEditingController();
  String category = '', mode = 'all';
  Timer? timer;
  Store get store => widget.store;
  Future<void> assistedSearch(bool useImage) async {
    try {
      String query;
      if (useImage) {
        final provider = widget.searchService.image;
        if (provider == null) {
          throw StateError(
            'Image search provider is not connected yet. Please type your search.',
          );
        }
        final file = await ImagePicker().pickImage(source: ImageSource.gallery);
        if (file == null) {
          return;
        }
        final bytes = await file.readAsBytes();
        if (bytes.length > 5 * 1024 * 1024) {
          throw StateError('Choose an image smaller than 5 MB.');
        }
        query = await provider.describe(bytes);
      } else {
        final provider = widget.searchService.voice;
        if (provider == null) {
          throw StateError(
            'Voice search provider is not connected yet. Please type your search.',
          );
        }
        query = await provider.transcribe();
      }
      if (mounted) {
        setState(() => search.text = query);
      }
    } catch (e) {
      if (mounted) {
        message(context, e);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    search.dispose();
    super.dispose();
  }

  void open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  Future<void> action(String target) async {
    if (target == 'shops') {
      open(ShopsPage(store: store));
    } else if (target.startsWith('category:')) {
      setState(() {
        category = target.substring(9);
        mode = 'all';
      });
    } else if (target.startsWith('product:')) {
      final p = store.product(target.substring(8));
      if (p != null) {
        open(ProductPage(store: store, entry: p));
      }
    } else if (Uri.tryParse(target)?.scheme == 'https') {
      try {
        await launchUrl(
          Uri.parse(target),
          mode: LaunchMode.externalApplication,
        );
      } catch (e) {
        if (mounted) {
          message(context, 'Could not open this link.');
        }
      }
    }
  }

  Future<void> location() async {
    final pin = TextEditingController(text: store.pincode),
        address = TextEditingController(text: store.address);
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Where are you shopping?'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Set your pincode for local prices, or use GPS to find shops within their service radius.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pin,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Six-digit pincode',
                ),
              ),
              TextField(
                controller: address,
                decoration: const InputDecoration(
                  labelText: 'Area / address (optional)',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    if (!await Geolocator.isLocationServiceEnabled()) {
                      throw StateError('Turn on location services first.');
                    }
                    var permission = await Geolocator.checkPermission();
                    if (permission == LocationPermission.denied) {
                      permission = await Geolocator.requestPermission();
                    }
                    if (permission == LocationPermission.denied ||
                        permission == LocationPermission.deniedForever) {
                      throw StateError(
                        'Location permission is unavailable. You can enter your pincode instead.',
                      );
                    }
                    final position = await Geolocator.getCurrentPosition(
                      locationSettings: const LocationSettings(
                        timeLimit: Duration(seconds: 20),
                      ),
                    );
                    final value = pin.text.trim();
                    if (value.isNotEmpty &&
                        !RegExp(r'^\d{6}$').hasMatch(value)) {
                      throw StateError(
                        'Enter a valid pincode or clear it before using GPS.',
                      );
                    }
                    await store.setLocation(
                      value,
                      address.text.trim().isEmpty
                          ? 'Current GPS location'
                          : address.text.trim(),
                      lat: position.latitude,
                      lng: position.longitude,
                    );
                    if (dialog.mounted) {
                      Navigator.pop(dialog);
                    }
                  } catch (e) {
                    if (dialog.mounted) {
                      message(dialog, e);
                    }
                  }
                },
                icon: const Icon(Icons.my_location),
                label: const Text('Use my current location'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () async {
              if (!RegExp(r'^\d{6}$').hasMatch(pin.text.trim())) {
                message(dialog, 'Enter a valid six-digit pincode');
                return;
              }
              await store.setLocation(pin.text.trim(), address.text.trim());
              if (dialog.mounted) {
                Navigator.pop(dialog);
              }
            },
            child: const Text('Save location'),
          ),
        ],
      ),
    );
    // Controllers are disposed after the closing dialog animation completes.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    pin.dispose();
    address.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final width = MediaQuery.sizeOf(context).width;
      final wide = width >= 1050;
      final categories = store.visible('categories');
      final selected = <String>{category};
      for (var i = 0; i < categories.length; i++) {
        for (final c in categories) {
          if (selected.contains(c.text('parentId')) && category.isNotEmpty) {
            selected.add(c.id);
          }
        }
      }
      final products = widget.searchService
          .text(store.visible('products'), search.text)
          .where(
            (p) =>
                (category.isEmpty || selected.contains(p.text('categoryId'))) &&
                (mode == 'all' || p.text('kind') == mode),
          )
          .toList();
      final promotions = store.visible('promotions');
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 80,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (store.business.text('imageUrl').isNotEmpty)
                SizedBox(
                  width: 36,
                  height: 36,
                  child: ProductArt(store.business, height: 36),
                )
              else
                const Icon(
                  Icons.storefront,
                  color: Color(0xff176b50),
                  size: 32,
                ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  store.business.text('name', 'Neighbourly'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (width > 650)
              TextButton.icon(
                onPressed: location,
                icon: const Icon(Icons.location_on_outlined),
                label: Text(
                  store.pincode.isEmpty ? 'Set location' : store.pincode,
                ),
              ),
            IconButton(
              tooltip: 'Your account',
              onPressed: () => open(AccountPage(store: store)),
              icon: const Icon(Icons.person_outline),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Badge(
                label: Text('${store.count}'),
                isLabelVisible: store.count > 0,
                child: IconButton(
                  tooltip: 'Shopping bag',
                  onPressed: () => open(CartPage(store: store)),
                  icon: const Icon(Icons.shopping_bag_outlined),
                ),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              if (promotions.any((p) => p.text('placement') == 'ticker'))
                TickerStrip(
                  text: promotions
                      .where((p) => p.text('placement') == 'ticker')
                      .map((e) => e.text('name'))
                      .join('     •     '),
                ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Padding(
                    padding: EdgeInsets.all(width < 650 ? 16 : 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: search,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText: width < 450
                                      ? 'Search your neighbourhood'
                                      : 'Search products, services and everyday favourites',
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: search.text.isNotEmpty
                                      ? IconButton(
                                          onPressed: () =>
                                              setState(() => search.clear()),
                                          icon: const Icon(Icons.close),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Voice search',
                              onPressed: () => assistedSearch(false),
                              icon: const Icon(Icons.mic_none),
                            ),
                            IconButton(
                              tooltip: 'Image search',
                              onPressed: () => assistedSearch(true),
                              icon: const Icon(Icons.camera_alt_outlined),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ActionChip(
                              avatar: const Icon(
                                Icons.location_on_outlined,
                                size: 18,
                              ),
                              label: Text(
                                store.pincode.isEmpty && store.latitude == null
                                    ? 'Add location for local prices & nearby shops'
                                    : '${store.address.isEmpty ? 'Shopping in' : store.address} ${store.pincode}',
                              ),
                              onPressed: location,
                            ),
                            ActionChip(
                              avatar: const Icon(
                                Icons.store_outlined,
                                size: 18,
                              ),
                              label: const Text('Nearby shops'),
                              onPressed: () => open(ShopsPage(store: store)),
                            ),
                            if (!store.live)
                              const Chip(label: Text('Demo marketplace')),
                          ],
                        ),
                        if (store.error.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              store.error,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        HeroCarousel(
                          entries: promotions
                              .where((p) => p.text('placement') == 'carousel')
                              .toList(),
                          onTap: action,
                        ),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Find your everyday',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -.6,
                                ),
                              ),
                            ),
                            if (width > 600)
                              const Text(
                                'Local shops. Thoughtful finds.',
                                style: TextStyle(color: Colors.black54),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: const Text('Explore all'),
                                  selected: category.isEmpty,
                                  onSelected: (_) =>
                                      setState(() => category = ''),
                                ),
                              ),
                              for (final c in categories)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(
                                      '${c.text('parentId').isEmpty ? '' : '↳ '}${c.text('name')}',
                                    ),
                                    selected: category == c.id,
                                    onSelected: (_) =>
                                        setState(() => category = c.id),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final item in [
                              ('all', 'All finds'),
                              ('product', 'Products'),
                              ('service', 'Services'),
                            ])
                              FilterChip(
                                label: Text(item.$2),
                                selected: mode == item.$1,
                                onSelected: (_) =>
                                    setState(() => mode = item.$1),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: products.isEmpty
                                  ? const Padding(
                                      padding: EdgeInsets.all(40),
                                      child: Text(
                                        'No matching finds yet. Try another search or category.',
                                      ),
                                    )
                                  : LayoutBuilder(
                                      builder: (context, constraints) {
                                        final columns =
                                            constraints.maxWidth > 850
                                            ? 4
                                            : constraints.maxWidth > 580
                                            ? 3
                                            : constraints.maxWidth > 340
                                            ? 2
                                            : 1;
                                        return GridView.builder(
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          itemCount: products.length,
                                          gridDelegate:
                                              SliverGridDelegateWithFixedCrossAxisCount(
                                                crossAxisCount: columns,
                                                crossAxisSpacing: 16,
                                                mainAxisSpacing: 16,
                                                mainAxisExtent: 370,
                                              ),
                                          itemBuilder: (context, i) =>
                                              productCard(products[i]),
                                        );
                                      },
                                    ),
                            ),
                            if (wide &&
                                promotions.any(
                                  (p) => p.text('placement') == 'ad',
                                )) ...[
                              const SizedBox(width: 24),
                              SizedBox(
                                width: promotions
                                    .where((p) => p.text('placement') == 'ad')
                                    .map(
                                      (p) => p
                                          .number('width', 260)
                                          .clamp(120, 360)
                                          .toDouble(),
                                    )
                                    .fold<double>(120, (a, b) => a > b ? a : b),
                                child: Column(
                                  children: [
                                    for (final p in promotions.where(
                                      (p) => p.text('placement') == 'ad',
                                    ))
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 16,
                                        ),
                                        child: PromoCard(
                                          entry: p,
                                          onTap: () => action(p.text('target')),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 28),
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            for (final p in promotions.where(
                              (p) =>
                                  p.text('placement') == 'box' ||
                                  (!wide && p.text('placement') == 'ad'),
                            ))
                              SizedBox(
                                width: width < 650 ? width - 32 : 400,
                                child: PromoCard(
                                  entry: p,
                                  onTap: () => action(p.text('target')),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 36),
                        const Divider(),
                        const SizedBox(height: 16),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 28,
                          runSpacing: 12,
                          children: [
                            Text(
                              '${store.business.text('name', 'Neighbourly')}\n${store.business.text('tagline', 'Good things. Close to home.')}',
                            ),
                            Text(
                              '${store.business.text('address')}\n${store.business.text('phone')}',
                            ),
                            TextButton.icon(
                              onPressed: () => open(AdminPage(store: store)),
                              icon: const Icon(Icons.dashboard_outlined),
                              label: Text(
                                store.live
                                    ? 'Business admin'
                                    : 'Explore demo admin',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  Widget productCard(Entry p) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => open(ProductPage(store: store, entry: p)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProductArt(p, height: 150),
            const SizedBox(height: 12),
            Text(
              p.text('kind') == 'service'
                  ? 'LOCAL EXPERT'
                  : 'NEIGHBOURHOOD PICK',
              style: const TextStyle(
                fontSize: 10,
                letterSpacing: 1.4,
                color: Color(0xff176b50),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              p.text('name'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        money(p.price(store.pincode)),
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        p.text('unit', 'each'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Add ${p.text('name')} to bag',
                  onPressed: p.number('stock') <= (store.cart[p.id] ?? 0)
                      ? null
                      : () {
                          store.add(p);
                          message(context, '${p.text('name')} added to bag');
                        },
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class PromoCard extends StatelessWidget {
  const PromoCard({super.key, required this.entry, required this.onTap});
  final Entry entry;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xffeee6d6),
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: entry.number('height', 200).clamp(100, 600),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (entry.text('imageUrl').isNotEmpty)
                ProductArt(entry, height: 100),
              Text(
                entry.text('placement') == 'ad'
                    ? 'NEIGHBOURHOOD SPOTLIGHT'
                    : 'CURATED FOR YOU',
                style: const TextStyle(fontSize: 10, letterSpacing: 1.6),
              ),
              const SizedBox(height: 20),
              Text(
                entry.text('name'),
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              Text(entry.text('description')),
              const SizedBox(height: 18),
              const Icon(Icons.arrow_forward),
            ],
          ),
        ),
      ),
    ),
  );
}

class HeroCarousel extends StatefulWidget {
  const HeroCarousel({super.key, required this.entries, required this.onTap});
  final List<Entry> entries;
  final void Function(String) onTap;
  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final controller = PageController();
  Timer? timer;
  int page = 0;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (controller.hasClients &&
          widget.entries.length > 1 &&
          !MediaQuery.of(context).disableAnimations) {
        controller.animateToPage(
          (page + 1) % widget.entries.length,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).width < 600 ? 400 : 340,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: PageView.builder(
              controller: controller,
              itemCount: widget.entries.length,
              onPageChanged: (v) => setState(() => page = v),
              itemBuilder: (context, i) {
                final p = widget.entries[i];
                return Material(
                  color: const Color(0xffdfead8),
                  child: InkWell(
                    onTap: () => widget.onTap(p.text('target')),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'YOUR NEIGHBOURHOOD, REIMAGINED',
                                  style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 1.8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  p.text('name'),
                                  style: TextStyle(
                                    fontSize:
                                        MediaQuery.sizeOf(context).width < 600
                                        ? 32
                                        : 42,
                                    height: 1.05,
                                    letterSpacing: -1.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xff163e2e),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  p.text('description'),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 18),
                                const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Explore local finds',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Icon(Icons.arrow_forward, size: 18),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (MediaQuery.sizeOf(context).width >= 750)
                            Expanded(
                              flex: 2,
                              child: p.text('imageUrl').isEmpty
                                  ? const Icon(
                                      Icons.shopping_basket_outlined,
                                      size: 150,
                                      color: Color(0xff7c9a69),
                                    )
                                  : ProductArt(p, height: 240),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.entries.length; i++)
              IconButton(
                tooltip: 'Show promotion ${i + 1}',
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                padding: EdgeInsets.zero,
                onPressed: () => controller.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                ),
                icon: Icon(
                  i == page ? Icons.circle : Icons.circle_outlined,
                  size: 9,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class TickerStrip extends StatefulWidget {
  const TickerStrip({super.key, required this.text});
  final String text;
  @override
  State<TickerStrip> createState() => _TickerStripState();
}

class _TickerStripState extends State<TickerStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();
  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.text,
    child: Container(
      height: 34,
      decoration: const BoxDecoration(color: Color(0xff174c38)),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, c) => AnimatedBuilder(
          animation: animation,
          builder: (context, _) => Transform.translate(
            offset: Offset(
              MediaQuery.of(context).disableAnimations
                  ? 8
                  : c.maxWidth -
                        animation.value * (c.maxWidth + widget.text.length * 8),
              8,
            ),
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxWidth: double.infinity,
              child: ExcludeSemantics(
                child: Text(
                  widget.text,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    letterSpacing: .6,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
