import 'dart:math';

typedef Json = Map<String, dynamic>;

class Entry {
  final String id;
  final Json data;
  const Entry(this.id, this.data);
  String text(String key, [String fallback = '']) =>
      data[key]?.toString() ?? fallback;
  double number(String key, [double fallback = 0]) => (data[key] is num)
      ? (data[key] as num).toDouble()
      : double.tryParse(text(key)) ?? fallback;
  bool get active => data['active'] != false;
  bool visibleAt(DateTime now) {
    final start = DateTime.tryParse(text('startsAt'));
    final end = DateTime.tryParse(text('endsAt'));
    return active &&
        (start == null || !now.isBefore(start)) &&
        (end == null || now.isBefore(end));
  }

  double price(String pincode) {
    final prices = data['prices'];
    return prices is Map && prices[pincode] is num
        ? (prices[pincode] as num).toDouble()
        : number('price');
  }
}

double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  double radians(double value) => value * pi / 180;
  final a =
      pow(sin(radians(lat2 - lat1) / 2), 2) +
      cos(radians(lat1)) *
          cos(radians(lat2)) *
          pow(sin(radians(lon2 - lon1) / 2), 2);
  return 6371 * 2 * atan2(sqrt(a), sqrt(1 - a.clamp(0, 1)));
}

const collections = [
  'products',
  'categories',
  'shops',
  'promotions',
  'settings',
];

Map<String, List<Entry>> demoCatalog() => {
  'settings': [
    const Entry('business', {
      'name': 'Neighbourly',
      'tagline': 'Good things. Close to home.',
      'address': 'Your local marketplace',
      'phone': '+91 90000 00000',
      'radiusKm': 10,
      'active': true,
    }),
  ],
  'categories': [
    for (final (i, name) in [
      'Fresh & daily',
      'Home & living',
      'Electronics',
      'Local services',
      'Pantry',
    ].indexed)
      Entry('c$i', {'name': name, 'order': i, 'active': true, 'parentId': ''}),
  ],
  'shops': [
    const Entry('s1', {
      'name': 'The Corner Store',
      'address': 'MG Road, Bengaluru',
      'phone': '+91 90000 00001',
      'latitude': 12.9716,
      'longitude': 77.5946,
      'pincode': '560001',
      'radiusKm': 10,
      'description': 'Everyday essentials from your neighbourhood.',
      'active': true,
    }),
    const Entry('s2', {
      'name': 'Home Helpers',
      'address': 'Indiranagar, Bengaluru',
      'phone': '+91 90000 00002',
      'latitude': 12.9784,
      'longitude': 77.6408,
      'pincode': '560038',
      'radiusKm': 15,
      'description': 'Skilled local professionals for your home.',
      'active': true,
    }),
  ],
  'products': [
    for (final (i, item) in <(String, String, double, String)>[
      (
        'Farm-fresh vegetable box',
        'c0',
        249,
        'A colourful selection of seasonal vegetables. Packed fresh by your local shop.',
      ),
      (
        'Everyday ceramic mug',
        'c1',
        349,
        'A warm companion for your morning coffee. 350 ml ceramic mug.',
      ),
      (
        'Wireless headphones',
        'c2',
        1499,
        'Comfortable everyday listening with a rechargeable battery.',
      ),
      (
        'Organic pantry essentials',
        'c4',
        599,
        'Stock your kitchen with a thoughtful selection of daily essentials.',
      ),
      (
        'Plumbing visit',
        'c3',
        299,
        'Book an inspection. Materials and additional work quoted separately.',
      ),
      (
        'Electrician visit',
        'c3',
        349,
        'Local electrical inspection and service consultation.',
      ),
      (
        'Mason consultation',
        'c3',
        499,
        'Discuss repairs and renovation with a local professional.',
      ),
      (
        'Labour assistance',
        'c3',
        699,
        'Daily assistance. Confirm scope and duration with the provider.',
      ),
    ].indexed)
      Entry('p$i', {
        'name': item.$1,
        'categoryId': item.$2,
        'price': item.$3,
        'description': item.$4,
        'kind': i >= 4 ? 'service' : 'product',
        'shopId': i >= 4 ? 's2' : 's1',
        'stock': 30,
        'order': i,
        'active': true,
        'imageUrl': '',
        'prices': {'560001': item.$3},
        'unit': i >= 4 ? 'per visit' : 'each',
      }),
  ],
  'promotions': [
    const Entry('welcome', {
      'name': 'Fresh finds, familiar faces.',
      'description': 'Discover everyday essentials and trusted services from shops around you.',
      'placement': 'carousel',
      'target': 'category:c0',
      'order': 0,
      'active': true,
    }),
    const Entry('local', {
      'name': 'A little closer. A lot better.',
      'description':
          'Bring your neighbourhood home. Explore local shops today.',
      'placement': 'carousel',
      'target': 'shops',
      'order': 1,
      'active': true,
    }),
    const Entry('ticker', {
      'name': 'SHOP LOCAL • Fresh picks every day • Trusted services in your neighbourhood',
      'placement': 'ticker',
      'order': 0,
      'active': true,
    }),
    const Entry('ad', {
      'name': 'A helping hand, nearby.',
      'description': 'Plumbers, electricians and more. Find your local expert.',
      'placement': 'ad',
      'target': 'category:c3',
      'width': 260,
      'height': 280,
      'order': 0,
      'active': true,
    }),
    const Entry('box', {
      'name': 'Your daily essentials, sorted.',
      'description': 'Explore the pantry collection',
      'placement': 'box',
      'target': 'category:c4',
      'height': 160,
      'order': 1,
      'active': true,
    }),
  ],
};
