import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'shared.dart';
import 'layout_editor.dart';

const adminSections = <String, String>{
  'products': 'Products & services',
  'categories': 'Categories',
  'shops': 'Shops',
  'promotions': 'Promotions',
  'settings': 'Business profile',
  'scrollingText': 'Scrolling Text Settings',
  'theme': 'Theme Settings',
  'sectionSettings': 'Section Customization',
};

const fields = <String, Map<String, String>>{
  'products': {
    'name': 'Name',
    'description': 'Description',
    'categoryId': 'Category',
    'shopId': 'Shop',
    'kind': 'Type',
    'price': 'Base price (₹)',
    'compareAtPrice': 'Original price for discount badge (optional)',
    'unit': 'Unit, e.g. each / per visit',
    'stock': 'Available quantity / booking slots',
    'imageUrl': 'Main image URL',
    'images': 'Additional image URLs (one per line)',
    'tags': 'Search keywords',
    'prices': 'Pincode prices (one per line: 560001=249)',
    'order': 'Display order',
  },
  'categories': {
    'name': 'Category name',
    'parentId': 'Parent category (optional)',
    'imageUrl': 'Category image URL (optional)',
    'order': 'Display order',
  },
  'shops': {
    'name': 'Shop name',
    'description': 'About this shop',
    'address': 'Street address',
    'phone': 'Phone',
    'whatsapp': 'WhatsApp number (country code included)',
    'pincode': 'Pincode',
    'latitude': 'Latitude',
    'longitude': 'Longitude',
    'radiusKm': 'Nearby radius (km)',
    'imageUrl': 'Shop image URL',
    'order': 'Display order',
  },
  'promotions': {
    'name': 'Headline / ticker text',
    'description': 'Supporting text',
    'placement': 'Display location',
    'target': 'Click action (shops / category:ID / product:ID / https://…)',
    'imageUrl': 'Image URL',
    'width': 'Width (0 = automatic, up to 3840 px)',
    'height': 'Height (120-1200 px)',
    'startsAt': 'Starts at (optional)',
    'endsAt': 'Ends at (optional)',
    'order': 'Display order',
    'backgroundColor': 'Box background (#RRGGBB)',
    'backgroundImage': 'Box background image URL (optional)',
    'textColor': 'Box text color (#RRGGBB)',
    'fontSize': 'Box heading size',
    'fontWeight': 'Box heading weight',
    'borderColor': 'Border color (#RRGGBB)',
    'borderWidth': 'Border width',
    'radius': 'Corner radius',
    'shadow': 'Shadow strength (0-1)',
    'brightness': 'Brightness (0.2-2)',
    'opacity': 'Opacity (0-1)',
    'padding': 'Box padding',
    'spacing': 'Section spacing',
    'animationMs': 'Animation timing (milliseconds)',
    'position': 'Horizontal position (start / center / end)',
    'scrollEnabled': 'Scroll bottom-to-top (true / false)',
    'stopAfter': 'Stop scrolling after seconds (0 = continuous)',
    'direction': 'Movement direction (rtl / ltr)',
    'speed': 'Movement speed',
  },
  'settings': {
    'name': 'Business name',
    'tagline': 'Tagline',
    'address': 'Business address',
    'phone': 'Phone',
    'whatsapp': 'WhatsApp number (country code included)',
    'description': 'Office / head office details',
    'imageUrl': 'Logo URL',
    'radiusKm': 'Default nearby radius (km)',
    'enabledLanguages': 'Enabled languages (comma-separated codes)',
  },
  'sectionSettings': {
    'section': 'Section (header, logo, user, search, notice, promo, offers, categories, products, boxes, ads, background)',
    'visible': 'Visible (true / false)',
    'fontFamily': 'Font family',
    'fontSize': 'Font size',
    'fontWeight': 'Font weight',
    'fontStyle': 'Font style (normal / italic)',
    'textColor': 'Text color (#RRGGBB)',
    'backgroundColor': 'Background color (#RRGGBB)',
    'backgroundImage': 'Background image URL',
    'gradientStart': 'Gradient start (#RRGGBB)',
    'gradientEnd': 'Gradient end (#RRGGBB)',
    'borderColor': 'Border color (#RRGGBB)',
    'borderWidth': 'Border thickness',
    'radius': 'Border radius',
    'shadow': 'Shadow strength (0-1)',
    'brightness': 'Brightness (0.2-2)',
    'opacity': 'Opacity (0-1)',
    'width': 'Width',
    'height': 'Height',
    'padding': 'Padding',
    'margin': 'Margin',
    'alignment': 'Alignment (start / center / end)',
    'order': 'Display order',
    'animation': 'Animation (none / fade / slide)',
    'animationSpeed': 'Animation speed',
    'displayDuration': 'Display duration (milliseconds)',
  },
  'scrollingText': {
    'name': 'Settings name',
    'text': 'Scrolling text (any language)',
    'textColor': 'Text color (#RRGGBB)',
    'backgroundColor': 'Background color (#RRGGBB)',
    'backgroundImage': 'Background image URL (optional)',
    'brightness': 'Brightness (0.2-2)',
    'opacity': 'Opacity (0-1)',
    'borderColor': 'Border color (#RRGGBB)',
    'borderWidth': 'Border thickness',
    'radius': 'Border radius',
    'fontFamily': 'Font family (optional)',
    'fontSize': 'Font size',
    'fontWeight': 'Font weight (100-900)',
    'speed': 'Scroll speed (pixels/second)',
    'height': 'Bar height',
    'padding': 'Bar padding',
    'direction': 'Scroll direction (rtl / ltr)',
    'translations': 'Translated text (one line per language: hi=...)',
    'startsAt': 'Display starts at (optional)',
    'endsAt': 'Display ends at (optional)',
    'noticeType': 'Notice type',
    'importantNews': 'Important news',
    'importantUpdates': 'Important updates',
    'customerNotices': 'Customer notices',
    'offers': 'Offers',
    'deliveryInformation': 'Delivery information',
    'serviceAnnouncements': 'Service announcements',
    'stateSpecificNotices': 'State-specific notices',
    'generalAlerts': 'General alerts',
    'playback': 'Playback (running / stopped / paused)',
  },
  'theme': {
    'name': 'Theme settings',
    'mode': 'Theme mode (light / dark / custom)',
    'primary': 'Primary color (#RRGGBB)',
    'secondary': 'Secondary or accent color (#RRGGBB)',
    'background': 'Main background color (#RRGGBB)',
    'surface': 'Card or section background (#RRGGBB)',
    'appBar': 'Header / AppBar color (#RRGGBB)',
    'text': 'Text color (#RRGGBB)',
    'fontFamily': 'Global font family (optional)',
    'fontSize': 'Global font size',
    'fontWeight': 'Global font weight',
    'backgroundImage': 'Main background image URL (optional)',
    'gradientStart': 'Gradient start (#RRGGBB)',
    'gradientEnd': 'Gradient end (#RRGGBB)',
    'brightness': 'Background brightness (0.2-2)',
    'opacity': 'Background opacity (0-1)',
    'darkPrimary': 'Dark theme primary color (#RRGGBB)',
    'darkSecondary': 'Dark theme accent color (#RRGGBB)',
    'darkBackground': 'Dark theme background (#RRGGBB)',
    'darkSurface': 'Dark theme card background (#RRGGBB)',
    'darkAppBar': 'Dark theme AppBar color (#RRGGBB)',
    'darkText': 'Dark theme text color (#RRGGBB)',
  },
};

class AdminOrders extends StatelessWidget {
  const AdminOrders({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Order requests')),
    body: !store.live
        ? const Center(
            child: Text(
              'Live customer orders will appear here when Firebase is connected.',
            ),
          )
        : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('orders')
                .orderBy('createdAt', descending: true)
                .limit(100)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    'Orders could not load. Check administrator access.',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.docs.isEmpty) {
                return const Center(
                  child: Text('New order requests will appear here.'),
                );
              }
              return ListView(
                children: snapshot.data!.docs.map((doc) {
                  final order = doc.data();
                  return Card(
                    margin: const EdgeInsets.all(16),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order ${doc.id}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text('${order['address']} • ${order['pincode']}'),
                          for (final line in order['lines'] as List)
                            Text('${line['quantity']} × ${line['name']}'),
                          Text('Total ${money(order['total'] as num)}'),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: order['status'] as String,
                            decoration: const InputDecoration(
                              labelText: 'Order status',
                            ),
                            items:
                                [
                                      'submitted',
                                      'confirmed',
                                      'fulfilled',
                                      'cancelled',
                                    ]
                                    .map(
                                      (s) => DropdownMenuItem(
                                        value: s,
                                        child: Text(s),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (status) async {
                              if (status == null) {
                                return;
                              }
                              try {
                                await doc.reference.update({'status': status});
                              } catch (e) {
                                if (context.mounted) {
                                  message(context, e);
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
  );
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.store});
  final Store store;
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  String section = 'products';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      if (widget.store.live && !widget.store.admin) {
        return Scaffold(
          appBar: AppBar(title: const Text('Admin')),
          body: const Center(
            child: Text(
              'Sign in with an administrator account to manage your business.',
            ),
          ),
        );
      }
      final entries = widget.store
          .entries(
            section == 'scrollingText' ||
                    section == 'theme' ||
                    section == 'sectionSettings'
                ? 'settings'
                : section,
          )
          .where(
            (entry) => section == 'settings'
                ? entry.id == 'business'
                : section == 'sectionSettings'
                ? entry.id.startsWith('section_')
                : section != 'scrollingText' && section != 'theme' ||
                      entry.id == section,
          )
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: const Text('Business studio'),
          actions: [
            IconButton(
              tooltip: 'UI Customization / Layout Settings',
              icon: const Icon(Icons.dashboard_customize_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => LayoutSettingsPage(store: widget.store),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AdminOrders(store: widget.store),
                ),
              ),
              icon: const Icon(Icons.receipt_long),
              label: const Text('Orders'),
            ),
          ],
        ),
        body: Column(
          children: [
            if (!widget.store.live)
              Container(
                width: double.infinity,
                color: const Color(0xffffedcb),
                padding: const EdgeInsets.all(12),
                child: const Text(
                  'Demo studio • Changes are saved on this device. Live access requires an administrator account.',
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in adminSections.keys)
                      ChoiceChip(
                        label: Text(adminSections[item]!),
                        selected: section == item,
                        onSelected: (_) => setState(() => section = item),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${entries.length} ${section == 'settings' ? 'business profiles' : section}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: section == 'settings' && entries.isNotEmpty
                        ? null
                        : () => edit(null),
                    icon: const Icon(Icons.add),
                    label: const Text('Add new'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: entries.isEmpty
                  ? const Center(
                      child: Text('Start by adding your first item.'),
                    )
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 5,
                          ),
                          child: ListTile(
                            leading: Icon(
                              e.active
                                  ? Icons.check_circle_outline
                                  : Icons.pause_circle_outline,
                            ),
                            title: Text(e.text('name')),
                            subtitle: Text(
                              '${e.id} • ${e.active ? 'Published' : 'Hidden'} • Order ${e.number('order').toInt()}',
                            ),
                            trailing: Wrap(
                              spacing: 2,
                              children: [
                                IconButton(
                                  tooltip: 'Delete',
                                  onPressed: section == 'settings'
                                      ? null
                                      : () => remove(e),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                                const Icon(Icons.edit_outlined),
                              ],
                            ),
                            onTap: () => edit(e),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
  Future<void> edit(Entry? entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            EntryEditor(store: widget.store, collection: section, entry: entry),
      ),
    );
  }

  Future<void> remove(Entry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Remove ${entry.text('name', entry.id)} permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.store.delete(
        section == 'scrollingText' ||
                section == 'theme' ||
                section == 'sectionSettings'
            ? 'settings'
            : section,
        entry.id,
      );
      if (mounted) message(context, 'Deleted');
    } catch (e) {
      if (mounted) message(context, e);
    }
  }
}

class EntryEditor extends StatefulWidget {
  const EntryEditor({
    super.key,
    required this.store,
    required this.collection,
    this.entry,
  });
  final Store store;
  final String collection;
  final Entry? entry;
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> controllers;
  bool active = true, busy = false;
  final numeric = {
    'price',
    'compareAtPrice',
    'stock',
    'order',
    'latitude',
    'longitude',
    'radiusKm',
    'width',
    'height',
    'fontSize',
    'fontWeight',
    'animationSpeed',
    'displayDuration',
    'speed',
    'padding',
    'borderWidth',
    'radius',
    'shadow',
    'brightness',
    'opacity',
    'spacing',
    'animationMs',
    'stopAfter',
  };
  @override
  void initState() {
    super.initState();
    active = widget.entry?.active ?? true;
    controllers = fields[widget.collection]!.map((key, label) {
      final value = widget.entry?.data[key];
      final text = key == 'translations' && value is Map
          ? value.entries.map((e) => '${e.key}=${e.value}').join('\n')
          : key == 'prices' && value is Map
          ? value.entries.map((e) => '${e.key}=${e.value}').join('\n')
          : key == 'images' && value is List
          ? value.join('\n')
          : value?.toString() ??
                ({
                      'stock': '10',
                      'order': '0',
                      'price': '0',
                      'radiusKm': '10',
                      'kind': 'product',
                      'placement': 'carousel',
                      'width': '260',
                      'height': '280',
                      'fontSize': '12',
                      'fontWeight': '400',
                      'speed': '70',
                      'padding': '9',
                      'direction': 'rtl',
                      'radius': '20',
                      'shadow': '0',
                      'brightness': '1',
                      'opacity': '1',
                      'spacing': '16',
                      'animationMs': '6000',
                      'stopAfter': '0',
                      'scrollEnabled': 'false',
                      'position': 'start',
                      'animationSpeed': '600',
                      'displayDuration': '6000',
                      'section': 'header',
                      'borderWidth': '0',
                      'name': key == 'scrollingText'
                          ? 'Scrolling text'
                          : key == 'theme'
                          ? 'Theme'
                          : null,
                      'mode': 'light',
                    }[key] ??
                    '');
      return MapEntry(key, TextEditingController(text: text));
    });
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      return;
    }
    setState(() => busy = true);
    try {
      final data = <String, dynamic>{...?widget.entry?.data, 'active': active};
      for (final field in controllers.entries) {
        final value = field.value.text.trim();
        if (numeric.contains(field.key)) {
          data[field.key] = num.tryParse(value) ?? 0;
        } else if (field.key == 'prices') {
          data[field.key] = <String, num>{};
          for (final line
              in value.split('\n').where((l) => l.trim().isNotEmpty)) {
            final parts = line.split('=');
            if (parts.length != 2 ||
                !RegExp(r'^\d{6}$').hasMatch(parts[0].trim()) ||
                num.tryParse(parts[1]) == null ||
                num.parse(parts[1]) < 0) {
              throw StateError('Use pincode=price, for example 560001=249.');
            }
            (data[field.key] as Map)[parts[0].trim()] = num.parse(parts[1]);
          }
        } else if (field.key == 'translations') {
          data[field.key] = <String, String>{};
          for (final line
              in value.split('\n').where((l) => l.trim().isNotEmpty)) {
            final separator = line.indexOf('=');
            if (separator < 2) {
              throw StateError('Use language=text, for example hi=नमस्ते.');
            }
            (data[field.key] as Map)[line.substring(0, separator).trim()] = line
                .substring(separator + 1)
                .trim();
          }
        } else if (field.key == 'images') {
          data[field.key] = value
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .toList();
        } else {
          data[field.key] = value;
        }
      }
      final start = DateTime.tryParse(data['startsAt']?.toString() ?? '');
      final end = DateTime.tryParse(data['endsAt']?.toString() ?? '');
      if (start != null && end != null && !end.isAfter(start)) {
        throw StateError('End time must be after start time.');
      }
      if (start != null) {
        data['startsAt'] = start.toUtc().toIso8601String();
      }
      if (end != null) {
        data['endsAt'] = end.toUtc().toIso8601String();
      }
      final id =
          widget.entry?.id ??
          (widget.collection == 'settings'
              ? 'business'
              : widget.collection == 'sectionSettings'
              ? 'section_${controllers['section']!.text.trim().toLowerCase()}'
              : widget.collection == 'scrollingText'
              ? 'scrollingText'
              : widget.collection == 'theme'
              ? 'theme'
              : '${widget.collection.substring(0, 1)}${DateTime.now().microsecondsSinceEpoch}');
      final collection =
          widget.collection == 'scrollingText' ||
              widget.collection == 'theme' ||
              widget.collection == 'sectionSettings'
          ? 'settings'
          : widget.collection;
      await widget.store.save(collection, Entry(id, data));
      if (mounted) {
        Navigator.pop(context);
        message(context, 'Saved successfully');
      }
    } catch (e) {
      if (mounted) {
        message(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  void preview() {
    final title = controllers['section']?.text.trim().isNotEmpty == true
        ? controllers['section']!.text.trim()
        : widget.collection;
    final sample = controllers['name']?.text.trim().isNotEmpty == true
        ? controllers['name']!.text.trim()
        : 'Preview';
    showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('$title preview'),
        content: Container(
          width: 420,
          padding: EdgeInsets.all(
            double.tryParse(controllers['padding']?.text ?? '') ?? 16,
          ),
          decoration: BoxDecoration(
            color: colorFromHex(
              controllers['backgroundColor']?.text ?? '',
              Theme.of(context).colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(
              double.tryParse(controllers['radius']?.text ?? '') ?? 12,
            ),
            border: Border.all(
              color: colorFromHex(
                controllers['borderColor']?.text ?? '',
                Colors.transparent,
              ),
              width:
                  double.tryParse(controllers['borderWidth']?.text ?? '') ?? 0,
            ),
          ),
          child: Text(
            sample,
            style: sectionTextStyle(
              Entry('', {
                'textColor': controllers['textColor']?.text ?? '',
                'fontFamily': controllers['fontFamily']?.text ?? '',
                'fontSize': double.tryParse(
                  controllers['fontSize']?.text ?? '',
                ),
                'fontWeight': double.tryParse(
                  controllers['fontWeight']?.text ?? '',
                ),
                'fontStyle': controllers['fontStyle']?.text ?? '',
              }),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> resetSection() async {
    if (widget.entry == null) {
      for (final controller in controllers.values) {
        controller.clear();
      }
      return;
    }
    final id = widget.entry!.id;
    await widget.store.delete('settings', id);
    if (mounted) {
      message(context, 'Reset to default');
      Navigator.pop(context);
    }
  }

  Widget field(String key, String label) {
    List<DropdownMenuItem<String>>? options;
    if (['position', 'scrollEnabled'].contains(key)) {
      options =
          (key == 'position' ? ['start', 'center', 'end'] : ['false', 'true'])
              .map((v) => DropdownMenuItem(value: v, child: Text(v)))
              .toList();
    } else if (['categoryId', 'parentId', 'shopId'].contains(key)) {
      options = [
        const DropdownMenuItem(value: '', child: Text('None')),
        ...widget.store
            .entries(key == 'shopId' ? 'shops' : 'categories')
            .where((e) => e.id != widget.entry?.id)
            .map(
              (e) => DropdownMenuItem(value: e.id, child: Text(e.text('name'))),
            ),
      ];
    } else if (key == 'section') {
      options =
          [
                'header',
                'logo',
                'user',
                'search',
                'notice',
                'promo',
                'offers',
                'categories',
                'products',
                'boxes',
                'ads',
                'background',
              ]
              .map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              )
              .toList();
    } else if (key == 'kind' ||
        key == 'placement' ||
        key == 'mode' ||
        key == 'direction' ||
        key == 'noticeType' ||
        key == 'playback') {
      options =
          (key == 'kind'
                  ? ['product', 'service']
                  : key == 'placement'
                  ? ['carousel', 'ticker', 'ad', 'box']
                  : key == 'mode'
                  ? ['light', 'dark', 'custom']
                  : key == 'noticeType'
                  ? [
                      'importantNews',
                      'importantUpdates',
                      'customerNotices',
                      'offers',
                      'deliveryInformation',
                      'serviceAnnouncements',
                      'stateSpecificNotices',
                      'generalAlerts',
                    ]
                  : key == 'playback'
                  ? ['running', 'stopped', 'paused']
                  : ['rtl', 'ltr'])
              .map((v) => DropdownMenuItem(value: v, child: Text(v)))
              .toList();
    }
    if (options != null) {
      return DropdownButtonFormField<String>(
        initialValue: options.any((e) => e.value == controllers[key]!.text)
            ? controllers[key]!.text
            : '',
        decoration: InputDecoration(labelText: label),
        items: options,
        onChanged: (v) => controllers[key]!.text = v ?? '',
        validator: (v) =>
            ['categoryId', 'shopId'].contains(key) && (v ?? '').isEmpty
            ? 'Choose a $label'
            : null,
      );
    }
    return TextFormField(
      controller: controllers[key],
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: ['startsAt', 'endsAt'].contains(key)
            ? IconButton(
                tooltip: 'Choose date and time',
                icon: const Icon(Icons.calendar_month),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate:
                        DateTime.tryParse(controllers[key]!.text) ??
                        DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (date == null || !mounted) {
                    return;
                  }
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (time != null && mounted) {
                    setState(
                      () => controllers[key]!.text = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      ).toIso8601String(),
                    );
                  }
                },
              )
            : null,
      ),
      minLines:
          ['description', 'prices', 'images', 'translations'].contains(key)
          ? 3
          : 1,
      maxLines:
          ['description', 'prices', 'images', 'translations'].contains(key)
          ? 5
          : 1,
      keyboardType: numeric.contains(key)
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      validator: (raw) {
        final v = raw?.trim() ?? '';
        if (key == 'name' && v.isEmpty) {
          return 'Enter a name';
        }
        if (numeric.contains(key)) {
          final n = num.tryParse(v);
          if (n == null || !n.isFinite) {
            return 'Enter a valid number';
          }
          if (!['latitude', 'longitude'].contains(key) && n < 0) {
            return 'Use zero or more';
          }
          if (key == 'latitude' && n.abs() > 90 ||
              key == 'longitude' && n.abs() > 180) {
            return 'Outside coordinate range';
          }
          if (key == 'stock' && n != n.round()) {
            return 'Use a whole number';
          }
        }
        if (['startsAt', 'endsAt'].contains(key) &&
            v.isNotEmpty &&
            DateTime.tryParse(v) == null) {
          return 'Use YYYY-MM-DDTHH:MM:SS, optionally with a timezone';
        }
        if (key == 'pincode' && !RegExp(r'^\d{6}$').hasMatch(v)) {
          return 'Enter six digits';
        }
        if (key == 'imageUrl' &&
            v.isNotEmpty &&
            Uri.tryParse(v)?.scheme != 'https') {
          return 'Use an HTTPS image URL';
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.entry == null
            ? 'Add ${widget.collection}'
            : 'Edit ${widget.entry!.text('name')}',
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Make it yours',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const Text(
                'Update the details below. Hide an item any time without deleting it.',
              ),
              const SizedBox(height: 24),
              for (final f in fields[widget.collection]!.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: field(f.key, f.value),
                ),
              if (controllers.containsKey('imageUrl'))
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          try {
                            final file = await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                            );
                            if (file == null) {
                              return;
                            }
                            setState(() => busy = true);
                            final url = await widget.store.upload(file);
                            if (mounted) {
                              setState(
                                () => controllers['imageUrl']!.text = url,
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
                  icon: const Icon(Icons.upload),
                  label: const Text('Upload image'),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : preview,
                      icon: const Icon(Icons.preview_outlined),
                      label: const Text('Preview'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : resetSection,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Reset to default'),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                value: active,
                onChanged: (v) => setState(() => active = v),
                title: const Text('Published'),
                subtitle: const Text(
                  'Turn off to hide this item from customers.',
                ),
              ),
              FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? 'Saving…' : 'Save changes'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
