import 'catalog.dart';

// Vendor spec section 8: the customer searches an item by name and chooses it; every shop in their town selling it shows on a map
// (the shop's small photo and its price on each pin) and in a list from the lowest price up (photo, name, price, distance).

/// An item name as compared: "  Tomato " and "tomato" are the same item.
String itemNameKey(String name) => name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Whether [product] is the item: the same item of the admin's library, or the same name.
bool isSameItem(Entry product, {required String name, String libraryItemId = ''}) =>
    (libraryItemId.isNotEmpty && product.text('libraryItemId') == libraryItemId) || itemNameKey(product.text('name')) == itemNameKey(name);

/// One item the customer can choose: its name, how many shops sell it and its lowest price.
class ItemChoice {
  const ItemChoice({required this.name, required this.libraryItemId, required this.shops, required this.lowest});
  final String name, libraryItemId;
  final int shops;
  final double lowest;
}

/// The items whose name has every word the customer typed, one per item, the ones starting with the words first, then the ones most
/// shops sell. Only items with a price (a vendor's price runs out after 24 hours) count.
List<ItemChoice> itemChoices(List<Entry> products, String query, {String pincode = '', int max = 8}) {
  final words = itemNameKey(query).split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  final groups = <String, List<Entry>>{};
  for (final p in products) {
    final key = itemNameKey(p.text('name'));
    if (key.isEmpty || p.price(pincode) <= 0 || !words.every(key.contains)) continue;
    groups.putIfAbsent(key, () => []).add(p);
  }
  final choices = [
    for (final group in groups.values)
      ItemChoice(
        name: group.first.text('name').trim(),
        libraryItemId: group.map((p) => p.text('libraryItemId')).firstWhere((id) => id.isNotEmpty, orElse: () => ''),
        shops: {for (final p in group) p.text('shopId', p.id)}.length,
        lowest: group.map((p) => p.price(pincode)).reduce((a, b) => a < b ? a : b),
      ),
  ];
  final first = words.first;
  choices.sort((a, b) {
    final startA = itemNameKey(a.name).startsWith(first) ? 0 : 1, startB = itemNameKey(b.name).startsWith(first) ? 0 : 1;
    if (startA != startB) return startA.compareTo(startB);
    if (a.shops != b.shops) return b.shops.compareTo(a.shops);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return choices.take(max).toList();
}

/// One shop selling the item: the product (its price and unit), the shop, where it is and how far from the customer.
class ItemOffer {
  const ItemOffer({required this.product, required this.shop, required this.price, this.latitude, this.longitude, this.distanceKm});
  final Entry product;
  final Entry? shop;
  final double price;
  final double? latitude, longitude, distanceKm;

  String get shopName => shop?.text('name') ?? product.text('shopName', 'Shop');
  /// The shop's photo for the pin and the list (the item's photo when the shop has none).
  String get photo => shop?.text('imageUrl', product.text('imageUrl')) ?? product.text('imageUrl');
  String get address => shop?.text('address') ?? '';
  String get phone => shop?.text('phone') ?? '';
  String get whatsapp => shop?.text('whatsapp') ?? '';
  String get unit => product.text('unit');
  bool get onMap => latitude != null && longitude != null;
}

double? _coordinate(Entry? e, String key) {
  final v = e?.data[key];
  return v is num && v != 0 ? v.toDouble() : null;
}

/// Whether a shop has its place on the map (latitude and longitude): its distance and the road to it need it.
bool shopOnMap(Entry shop) => _coordinate(shop, 'latitude') != null && _coordinate(shop, 'longitude') != null;

/// Every product of the item that has a price, with its shop: the cheapest first, then the nearest. The place is the shop's, else
/// the product's own; the distance is from the customer when their location is known.
List<ItemOffer> itemOffers(
  List<Entry> products,
  List<Entry> shops, {
  required String name,
  String libraryItemId = '',
  String pincode = '',
  double? latitude,
  double? longitude,
}) {
  final shopById = {for (final s in shops) s.id: s};
  final offers = <ItemOffer>[];
  for (final p in products) {
    if (!isSameItem(p, name: name, libraryItemId: libraryItemId)) continue;
    final price = p.price(pincode);
    if (price <= 0) continue;
    final shop = shopById[p.text('shopId')];
    final lat = _coordinate(shop, 'latitude') ?? _coordinate(p, 'latitude');
    final lng = _coordinate(shop, 'longitude') ?? _coordinate(p, 'longitude');
    final distance = lat != null && lng != null && latitude != null && longitude != null ? distanceKm(latitude, longitude, lat, lng) : null;
    offers.add(ItemOffer(product: p, shop: shop, price: price, latitude: lat, longitude: lng, distanceKm: distance));
  }
  offers.sort((a, b) {
    final byPrice = a.price.compareTo(b.price);
    if (byPrice != 0) return byPrice;
    return (a.distanceKm ?? double.infinity).compareTo(b.distanceKm ?? double.infinity);
  });
  return offers;
}

/// "1.2 km", "350 m", or '' when the distance is not known.
String distanceText(double? km) => km == null ? '' : km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';

/// An item the admin picks from the items the shops already sell (Today's Offers, the Fresh Fruits & Vegetables strip): its name
/// and photo, so no new photo is needed.
class ItemPick {
  const ItemPick({required this.name, this.libraryItemId = '', this.productId = '', this.imageUrl = ''});
  final String name, libraryItemId, productId, imageUrl;

  factory ItemPick.from(Map data) => ItemPick(
    name: '${data['name'] ?? ''}'.trim(),
    libraryItemId: '${data['libraryItemId'] ?? ''}',
    productId: '${data['productId'] ?? ''}',
    imageUrl: '${data['imageUrl'] ?? ''}',
  );

  Map<String, String> toMap() => {'name': name, 'libraryItemId': libraryItemId, 'productId': productId, 'imageUrl': imageUrl};
  String get key => itemNameKey(name);
}

/// The items any shop sells (one per item name) whose name has every word of [query], with a photo where any shop has one; the
/// ones starting with the words first.
List<ItemPick> itemPicks(List<Entry> products, String query, {int max = 12}) {
  final words = itemNameKey(query).split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  final byName = <String, ItemPick>{};
  for (final p in products) {
    final key = itemNameKey(p.text('name'));
    if (key.isEmpty || p.text('kind') == 'service' || !words.every(key.contains)) continue;
    final current = byName[key];
    if (current == null || (current.imageUrl.isEmpty && p.text('imageUrl').isNotEmpty)) {
      byName[key] = ItemPick(name: p.text('name').trim(), libraryItemId: p.text('libraryItemId'), productId: p.id, imageUrl: p.text('imageUrl'));
    }
  }
  final list = byName.values.toList()
    ..sort((a, b) {
      final sa = a.key.startsWith(words.first) ? 0 : 1, sb = b.key.startsWith(words.first) ? 0 : 1;
      return sa != sb ? sa.compareTo(sb) : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return list.take(max).toList();
}
