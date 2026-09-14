import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'shared.dart';
import 'account.dart';

class ProductPage extends StatefulWidget {
  const ProductPage({super.key, required this.store, required this.entry});
  final Store store;
  final Entry entry;
  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  Store get store => widget.store;
  Entry get entry => widget.entry;
  @override
  void initState() {
    super.initState();
    store.trackItemView(entry);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final p = store.product(entry.id) ?? entry;
      final shop = store
          .visible('shops')
          .where((s) => s.id == p.text('shopId'))
          .firstOrNull;
      final images = [
        p.text('imageUrl'),
        if (p.data['images'] is List)
          ...(p.data['images'] as List).map((e) => e.toString()),
      ];
      return Scaffold(
        appBar: AppBar(title: Text(p.text('name'))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                SizedBox(
                  height: 300,
                  child: PageView(
                    children: [
                      for (final url in images)
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: ProductArt(
                            Entry(p.id, {...p.data, 'imageUrl': url}),
                            height: 300,
                          ),
                        ),
                    ],
                  ),
                ),
                if (images.length > 1)
                  Center(child: Text('Swipe to view ${images.length} images')),
                const SizedBox(height: 24),
                Text(
                  p.text('name'),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${money(p.price(store.pincode))} / ${p.text('unit', 'each')}',
                  style: const TextStyle(
                    fontSize: 24,
                    color: Color(0xff176b50),
                  ),
                ),
                if (store.pincode.isEmpty)
                  const Text(
                    'Base price shown. Set a pincode on the home page for local pricing.',
                  ),
                const SizedBox(height: 20),
                Text(
                  p.text('description'),
                  style: const TextStyle(fontSize: 17, height: 1.6),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed:
                      !p.active || p.number('stock') <= (store.cart[p.id] ?? 0)
                      ? null
                      : () {
                          store.add(p);
                          message(context, 'Added to bag');
                        },
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: Text(
                    p.number('stock') <= 0
                        ? 'Currently unavailable'
                        : p.text('kind') == 'service'
                        ? 'Add service to bag'
                        : 'Add to bag',
                  ),
                ),
                if (shop != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.storefront),
                    title: Text(shop.text('name')),
                    subtitle: const Text('View shop & directions'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ShopPage(store: store, shop: shop),
                      ),
                    ),
                  ),
                const Divider(height: 40),
                Reviews(store: store, productId: p.id),
              ],
            ),
          ),
        ),
      );
    },
  );
}

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
      const Text(
        'Community reviews',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
                        '${'★' * (d.data()['rating'] as num).toInt()} • ${d.data()['name']}',
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
                      await FirebaseFirestore.instance
                          .collection('products')
                          .doc(widget.productId)
                          .collection('reviews')
                          .doc(widget.store.user!.uid)
                          .set({
                            'userId': widget.store.user!.uid,
                            'name': widget.store.profileName.isEmpty
                                ? 'Neighbour'
                                : widget.store.profileName,
                            'rating': rating,
                            'text': review.text.trim(),
                            'updatedAt': FieldValue.serverTimestamp(),
                          });
                      if (context.mounted) {
                        message(context, 'Review saved');
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

class ShopsPage extends StatelessWidget {
  const ShopsPage({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) {
    final shops = store.nearby();
    return Scaffold(
      appBar: AppBar(title: const Text('Around your neighbourhood')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Good shops, close by.',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            store.latitude == null
                ? 'Showing shops in your pincode. Use GPS on the home page to search by service radius.'
                : 'Showing shops within each shop’s service radius.',
          ),
          const SizedBox(height: 20),
          if (shops.isEmpty)
            const Text(
              'No nearby shops found. Set or change your location on the home page.',
            ),
          if (shops.isNotEmpty)
            ShopMap(
              shops: shops,
              latitude: store.latitude,
              longitude: store.longitude,
            ),
          for (final shop in shops)
            Card(
              child: ListTile(
                leading: const Icon(Icons.storefront),
                title: Text(shop.text('name')),
                subtitle: Text(
                  '${shop.text('address')}\n${store.latitude != null ? '${distanceKm(store.latitude!, store.longitude!, shop.number('latitude'), shop.number('longitude')).toStringAsFixed(1)} km away' : shop.text('pincode')}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ShopPage(store: store, shop: shop),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ShopMap extends StatelessWidget {
  const ShopMap({
    super.key,
    required this.shops,
    this.latitude,
    this.longitude,
  });
  final List<Entry> shops;
  final double? latitude, longitude;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 300,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: FlutterMap(
        options: MapOptions(
          initialCenter: LatLng(
            shops.first.number('latitude'),
            shops.first.number('longitude'),
          ),
          initialZoom: 12,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.neighbourly.ecommerce',
          ),
          MarkerLayer(
            markers: [
              for (final shop in shops)
                Marker(
                  point: LatLng(
                    shop.number('latitude'),
                    shop.number('longitude'),
                  ),
                  width: 50,
                  height: 50,
                  child: Tooltip(
                    message: shop.text('name'),
                    child: const Icon(
                      Icons.location_on,
                      size: 42,
                      color: Color(0xff176b50),
                    ),
                  ),
                ),
              if (latitude != null && longitude != null)
                Marker(
                  point: LatLng(latitude!, longitude!),
                  child: const Icon(Icons.my_location, color: Colors.blue),
                ),
            ],
          ),
          RichAttributionWidget(
            attributions: [
              TextSourceAttribution(
                'OpenStreetMap contributors',
                onTap: () => launchUrl(
                  Uri.parse('https://www.openstreetmap.org/copyright'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class ShopPage extends StatelessWidget {
  const ShopPage({super.key, required this.store, required this.shop});
  final Store store;
  final Entry shop;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(shop.text('name'))),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              shop.text('name'),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(shop.text('description')),
            Text('${shop.text('address')} • ${shop.text('pincode')}'),
            Text(shop.text('phone')),
            const SizedBox(height: 20),
            ShopMap(
              shops: [shop],
              latitude: store.latitude,
              longitude: store.longitude,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                final uri = Uri.https('www.google.com', '/maps/dir/', {
                  'api': '1',
                  'destination':
                      '${shop.number('latitude')},${shop.number('longitude')}',
                  if (store.latitude != null)
                    'origin': '${store.latitude},${store.longitude}',
                });
                try {
                  if (!await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      ) &&
                      context.mounted) {
                    message(context, 'Could not open directions');
                  }
                } catch (e) {
                  if (context.mounted) {
                    message(context, 'Could not open directions');
                  }
                }
              },
              icon: const Icon(Icons.directions),
              label: const Text('Get directions'),
            ),
            const SizedBox(height: 24),
            const Text(
              'From this shop',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            for (final p
                in store
                    .visible('products')
                    .where((e) => e.text('shopId') == shop.id))
              ListTile(
                title: Text(p.text('name')),
                subtitle: Text(money(p.price(store.pincode))),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ProductPage(store: store, entry: p),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class CartPage extends StatefulWidget {
  const CartPage({super.key, required this.store});
  final Store store;
  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final address = TextEditingController();
  bool busy = false;
  final requestId = DateTime.now().microsecondsSinceEpoch.toString();
  @override
  void initState() {
    super.initState();
    address.text = widget.store.address;
  }

  @override
  void dispose() {
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Your shopping bag')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (widget.store.cart.isEmpty) ...[
                const SizedBox(height: 60),
                const Icon(Icons.shopping_bag_outlined, size: 72),
                const SizedBox(height: 20),
                const Center(
                  child: Text(
                    'Your next local find belongs here.',
                    style: TextStyle(fontSize: 22),
                  ),
                ),
              ] else ...[
                for (final line in widget.store.cart.entries)
                  Builder(
                    builder: (context) {
                      final p = widget.store.product(line.key);
                      if (p == null) {
                        return ListTile(
                          title: const Text('Item no longer available'),
                          trailing: IconButton(
                            onPressed: () {
                              widget.store.cart.remove(line.key);
                              setState(() {});
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        );
                      }
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.text('name'),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      money(
                                        p.price(widget.store.pincode) *
                                            line.value,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove one',
                                    onPressed: busy
                                        ? null
                                        : () => widget.store.add(p, -1),
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                  Text('${line.value}'),
                                  IconButton(
                                    tooltip: 'Add one',
                                    onPressed: busy
                                        ? null
                                        : () => widget.store.add(p),
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 24),
                Text(
                  'Subtotal ${money(widget.store.total)}',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Prices and availability are checked again when you submit. Payment is arranged with the shop; online payments are not enabled.',
                ),
                const SizedBox(height: 20),
                if (widget.store.pincode.isEmpty)
                  const Text(
                    'Add a delivery pincode on the home page before ordering.',
                  ),
                TextField(
                  controller: address,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Delivery / service address',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (widget.store.pincode.isEmpty ||
                              address.text.trim().length < 10) {
                            message(
                              context,
                              'Set your pincode and enter a complete address (at least 10 characters).',
                            );
                            return;
                          }
                          if (widget.store.live && widget.store.user == null) {
                            await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    AccountPage(store: widget.store),
                              ),
                            );
                            return;
                          }
                          setState(() => busy = true);
                          try {
                            final id = await widget.store.checkout(
                              address.text.trim(),
                              requestId,
                            );
                            if (context.mounted) {
                              message(
                                context,
                                'Order $id submitted. The shop will confirm fulfilment.',
                              );
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
                  child: Text(
                    busy
                        ? 'Submitting…'
                        : widget.store.live
                        ? 'Submit order request'
                        : 'Preview checkout',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
