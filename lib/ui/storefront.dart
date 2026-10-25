import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';
import '../services/place_resolver.dart';
import '../services/search.dart';
import 'account.dart';
import 'details.dart';
import 'location_picker_dialog.dart';
import 'shared.dart';
import 'wireframe_home.dart';
import '../modules/services/services_module.dart';

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

  bool _resolvingPlace = false;
  String _triedPlace = '';
  // A customer whose stored location has a pincode but no town (typed by hand,
  // or saved before towns existed) would otherwise see only the general offers.
  // When some offer is aimed at specific places, look the pincode up once.
  void _resolvePlaceIfNeeded() {
    if (_resolvingPlace || !needsPlaceResolution(store)) return;
    final key = [store.pincode, store.town, store.district].join('|');
    if (key == _triedPlace) return; // already tried for this exact location
    _triedPlace = key;
    _resolvingPlace = true;
    completeStoredPlace(store).whenComplete(() => _resolvingPlace = false);
  }

  @override
  void initState() {
    super.initState();
    store.addListener(_resolvePlaceIfNeeded);
    _resolvePlaceIfNeeded();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    store.removeListener(_resolvePlaceIfNeeded);
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
    } else if (target == 'services') {
      openServices(context, store);
    } else if (target.startsWith('category:')) {
      openCategory(target.substring(9));
    } else if (target.startsWith('product:')) {
      final p = store.product(target.substring(8));
      if (p != null) {
        open(ProductPage(store: store, entry: p));
      } else {
        message(context, 'This product is no longer available.');
      }
    } else if (target.startsWith('shop:')) {
      final id = target.substring(5);
      final shop = store.entries('shops').where((e) => e.id == id).firstOrNull;
      if (shop != null) {
        open(ShopPage(store: store, shop: shop));
      } else {
        message(context, 'This shop is no longer available.');
      }
    } else if (target.startsWith('tel:')) {
      try {
        await launchUrl(Uri.parse(target));
      } catch (e) {
        if (mounted) message(context, 'Could not start the call.');
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

  Future<void> location() => showLocationPickerDialog(context, store);

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
        // Below the phone's status bar (Android draws apps edge to edge): without this the logo sits under the clock.
        body: SafeArea(bottom: false, child: WireframeHome(
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
          onServices: () => openServices(context, store),
          onAccount: () => open(AccountPage(store: store)),
          onCart: () => open(CartPage(store: store)),
          onProduct: (entry) => open(ProductPage(store: store, entry: entry)),
          onAdd: (entry) {
            store.add(entry);
            message(context, 'Added to bag');
          },
          onCategory: openCategory,
        )),
      );
    },
  );
}
