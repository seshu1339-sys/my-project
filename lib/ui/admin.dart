import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import 'shared.dart';

const fields = <String, Map<String, String>>{
  'products': {
    'name': 'Name',
    'description': 'Description',
    'categoryId': 'Category',
    'shopId': 'Shop',
    'kind': 'Type',
    'price': 'Base price (₹)',
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
    'order': 'Display order',
  },
  'shops': {
    'name': 'Shop name',
    'description': 'About this shop',
    'address': 'Street address',
    'phone': 'Phone',
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
    'width': 'Web width (120–360 px)',
    'height': 'Height (100–600 px)',
    'startsAt': 'Starts at (optional)',
    'endsAt': 'Ends at (optional)',
    'order': 'Display order',
  },
  'settings': {
    'name': 'Business name',
    'tagline': 'Tagline',
    'address': 'Business address',
    'phone': 'Phone',
    'imageUrl': 'Logo URL',
    'radiusKm': 'Default nearby radius (km)',
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
      final entries = widget.store.entries(section);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Business studio'),
          actions: [
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
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in collections)
                    ChoiceChip(
                      label: Text(
                        item == 'products'
                            ? 'Products & services'
                            : item[0].toUpperCase() + item.substring(1),
                      ),
                      selected: section == item,
                      onSelected: (_) => setState(() => section = item),
                    ),
                ],
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
                            trailing: const Icon(Icons.edit_outlined),
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
    'stock',
    'order',
    'latitude',
    'longitude',
    'radiusKm',
    'width',
    'height',
  };
  @override
  void initState() {
    super.initState();
    active = widget.entry?.active ?? true;
    controllers = fields[widget.collection]!.map((key, label) {
      final value = widget.entry?.data[key];
      final text = key == 'prices' && value is Map
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
              : '${widget.collection.substring(0, 1)}${DateTime.now().microsecondsSinceEpoch}');
      await widget.store.save(widget.collection, Entry(id, data));
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

  Widget field(String key, String label) {
    List<DropdownMenuItem<String>>? options;
    if (['categoryId', 'parentId', 'shopId'].contains(key)) {
      options = [
        const DropdownMenuItem(value: '', child: Text('None')),
        ...widget.store
            .entries(key == 'shopId' ? 'shops' : 'categories')
            .where((e) => e.id != widget.entry?.id)
            .map(
              (e) => DropdownMenuItem(value: e.id, child: Text(e.text('name'))),
            ),
      ];
    } else if (key == 'kind' || key == 'placement') {
      options =
          (key == 'kind'
                  ? ['product', 'service']
                  : ['carousel', 'ticker', 'ad', 'box'])
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
      minLines: ['description', 'prices', 'images'].contains(key) ? 3 : 1,
      maxLines: ['description', 'prices', 'images'].contains(key) ? 5 : 1,
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
