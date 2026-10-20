import 'package:flutter/material.dart';

import '../domain/places.dart';
import '../services/places_directory.dart';
import '../services/strings.dart';

/// A search box over the Andhra Pradesh / Telangana places directory: type a
/// town (or the start of one) or a pincode and matching places appear live.
///
/// Used by the customer's location dialog and the admin's Location field. The
/// directory is only fetched when this box is first focused or typed in (or
/// right away with [loadNow], for the dialog, which exists only because the
/// customer asked to set a location) -- never with the home page.
///
/// With [onArea] set (the admin), whole districts and states matching the text
/// are offered too, above the towns.
class PlaceSearchBox extends StatefulWidget {
  const PlaceSearchBox({
    super.key,
    required this.onPlace,
    this.onArea,
    this.label = 'Search your town or pincode',
    this.loadNow = false,
    this.autofocus = false,
    this.limit = 8,
  });
  final ValueChanged<Place> onPlace;
  final ValueChanged<PlaceArea>? onArea;
  final String label;
  final bool loadNow, autofocus;
  final int limit;

  @override
  State<PlaceSearchBox> createState() => _PlaceSearchBoxState();
}

class _PlaceSearchBoxState extends State<PlaceSearchBox> {
  final controller = TextEditingController();
  final focus = FocusNode();
  PlacesIndex? index = PlacesDirectory.instance.ready;
  bool loading = false;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (focus.hasFocus) _ensureLoaded();
    });
    if (widget.loadNow) _ensureLoaded();
  }

  Future<void> _ensureLoaded() async {
    if (index != null || loading) return;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final loaded = await PlacesDirectory.instance.load();
      if (mounted) setState(() => index = loaded);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = controller.text.trim();
    final loaded = index;
    final places = loaded == null
        ? const <Place>[]
        : loaded.search(text, limit: widget.limit);
    final areas = loaded == null || widget.onArea == null
        ? const <PlaceArea>[]
        : loaded.searchAreas(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('place-search'),
          controller: controller,
          focusNode: focus,
          autofocus: widget.autofocus,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: widget.label.tr(context),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          onChanged: (_) {
            _ensureLoaded();
            setState(() {});
          },
        ),
        if (failed)
          Row(
            children: [
              Expanded(
                child: Text(
                  'Could not load the places list. Check your connection and try again.'
                      .tr(context),
                ),
              ),
              TextButton(
                onPressed: _ensureLoaded,
                child: Text('Retry'.tr(context)),
              ),
            ],
          )
        else if (loading && text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Loading places…'.tr(context)),
          ),
        for (final area in areas)
          ListTile(
            key: ValueKey('place-area-${area.token}'),
            dense: true,
            leading: const Icon(Icons.map_outlined),
            title: Text(
              area.isState
                  ? 'All of ${area.name}'
                  : 'All of ${area.name} district',
            ),
            subtitle: Text(area.isState ? 'Whole state' : area.state),
            onTap: () => widget.onArea!(area),
          ),
        for (final place in places)
          ListTile(
            key: ValueKey('place-result-${place.name}-${place.pincode}'),
            dense: true,
            leading: Icon(
              place.village ? Icons.holiday_village_outlined : Icons.location_city,
            ),
            title: Text(place.town == place.name ? place.name : '${place.name} (${place.town})'),
            subtitle: Text(place.subtitle),
            onTap: () => widget.onPlace(place),
          ),
        if (loaded != null &&
            text.length >= 2 &&
            places.isEmpty &&
            areas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No matching place found'.tr(context)),
          ),
      ],
    );
  }
}
