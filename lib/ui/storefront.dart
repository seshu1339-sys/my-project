import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';
import '../services/search.dart';
import 'account.dart';
import 'details.dart';
import 'shared.dart';
import 'wireframe_home.dart';
import 'services_page.dart';

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
  final scroll = ScrollController();
  final categoriesKey = GlobalKey();
  final productsKey = GlobalKey();
  int navigationIndex = 0;
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
    scroll.dispose();
    super.dispose();
  }

  void open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  Future<void> action(String target) async {
    if (target == 'shops') {
      open(ShopsPage(store: store));
    } else if (target.startsWith('category:')) {
      openCategory(target.substring(9));
    } else if (target.startsWith('product:')) {
      final p = store.product(target.substring(8));
      if (p != null) {
        open(ProductPage(store: store, entry: p));
      } else {
        message(context, 'This product is no longer available.');
      }
    } else if (Uri.tryParse(target)?.scheme == 'https') {
      try {
        final opened = await launchUrl(
          Uri.parse(target),
          mode: LaunchMode.externalApplication,
        );
        if (!opened && mounted) message(context, 'Could not open this link.');
      } catch (e) {
        if (mounted) {
          message(context, 'Could not open this link.');
        }
      }
    } else {
      message(context, 'Ask our office for more information about this offer.');
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

  void reveal(GlobalKey key) {
    final target = key.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  void selectCategory(String value) {
    setState(() {
      category = value;
      mode = 'all';
      navigationIndex = 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => reveal(productsKey));
  }

  void openCategory(String value) {
    if (value.isEmpty) {
      selectCategory(value);
      return;
    }
    open(CategoryPage(store: store, categoryId: value));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final mobile = MediaQuery.sizeOf(context).width < 700;
      return Scaffold(
        appBar: null,
        bottomNavigationBar: mobile
            ? NavigationBar(
                selectedIndex: navigationIndex,
                onDestinationSelected: (index) {
                  if (index == 3) {
                    open(AccountPage(store: store));
                    return;
                  }
                  if (index == 2) {
                    open(ShopsPage(store: store));
                    return;
                  }
                  setState(() {
                    navigationIndex = index;
                    if (index == 0) {
                      category = '';
                      mode = 'all';
                      search.clear();
                    }
                  });
                  if (index == 1) {
                    reveal(categoriesKey);
                  } else {
                    scroll.animateTo(
                      0,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOut,
                    );
                  }
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(Icons.grid_view_rounded),
                    label: 'Categories',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.storefront_outlined),
                    label: 'Shops',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    label: 'Account',
                  ),
                ],
              )
            : null,
        body: WireframeHome(
          scroll: scroll,
          categoriesKey: categoriesKey,
          productsKey: productsKey,
          onPromotion: action,
          store: store,
          search: search,
          searchService: widget.searchService,
          onSearch: () => setState(() {}),
          onLocation: location,
          onAssistedSearch: assistedSearch,
          onServices: () => open(ServicesPage(store: store)),
          onAccount: () => open(AccountPage(store: store)),
          onCart: () => open(CartPage(store: store)),
          onProduct: (entry) => open(ProductPage(store: store, entry: entry)),
          onAdd: (entry) {
            store.add(entry);
            message(context, 'Added to bag');
          },
          onCategory: openCategory,
        ),
      );
    },
  );
}
