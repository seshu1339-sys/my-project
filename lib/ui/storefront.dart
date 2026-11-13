import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';
import '../services/first_location.dart';
import '../services/place_resolver.dart';
import '../services/search.dart';
import '../services/search_providers.dart';
import 'account.dart';
import 'android_layout.dart';
import 'details.dart';
import 'location_picker_dialog.dart';
import 'shared.dart';
import 'wireframe_home.dart';
import '../modules/services/services_module.dart';
import '../modules/flash/flash_module.dart' show customerFlashButton;
import '../services/usage.dart';
import '../services/strings.dart';

class Storefront extends StatefulWidget {
  const Storefront({
    super.key,
    required this.store,
    this.searchService = const SmartSearch(
      voice: DeviceVoiceSearch(),
      image: CloudImageSearch(),
    ),
    this.firstPosition,
  });
  final Store store;
  final SmartSearch searchService;

  /// The first open's location question and position ([positionWithPermission] by default); replaced in tests.
  final Future<Position?> Function()? firstPosition;
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
        if (FirebaseAuth.instance.currentUser == null) {
          throw StateError('Please sign in to search by photo.');
        }
        final file = await ImagePicker().pickImage(
          source: isAndroidApp() ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 1024,
          imageQuality: 70,
        );
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
        // The phone's own recogniser listens in the app's language (Telugu or English); no server, no AI cost.
        final voice = provider is DeviceVoiceSearch && provider.localeId == null ? DeviceVoiceSearch(localeId: voiceLocaleFor(store.language)) : provider;
        query = await voice.transcribe();
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
  // A place saved before areas and distance-only offers (a pincode or town without a point, or a point without an area name) is
  // completed once, so the customer sees the shops around them and their area's name without choosing again.
  void _resolvePlaceIfNeeded() {
    // Only with Firebase connected (the demo and the tests never look places up by themselves).
    if (!store.live || _resolvingPlace || !needsPlaceResolution(store)) return;
    final key = [store.pincode, store.town, store.latitude, store.longitude].join('|');
    if (key == _triedPlace) return; // already tried for this exact location
    _triedPlace = key;
    _resolvingPlace = true;
    completeStoredPlace(store).whenComplete(() => _resolvingPlace = false);
  }

  /// The very first open, in the app and on the website alike: the location question, then GPS or the place picker
  /// (lib/services/first_location.dart). Only with Firebase connected (not the demo or the tests).
  Future<void> _askLocationOnce() async {
    if (!store.live) return;
    await askLocationOnFirstOpen(store, position: widget.firstPosition, pick: () async {
      if (mounted) await location();
    });
  }

  @override
  void initState() {
    super.initState();
    Usage.screen('home');
    store.addListener(_resolvePlaceIfNeeded);
    _resolvePlaceIfNeeded();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askLocationOnce());
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
      final p = store.item(target.substring(8));
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
        // The Help chat (lib/modules/flash); signed out, it opens the account page to sign in first.
        floatingActionButton: store.live ? customerFlashButton(store, onSignIn: (context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AccountPage(store: store)))) : null,
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
                destinations: [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home'.tr(context),
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(Icons.grid_view_rounded),
                    label: 'Categories'.tr(context),
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.storefront_outlined),
                    label: 'Shops'.tr(context),
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    label: 'Account'.tr(context),
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
