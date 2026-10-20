import 'package:flutter/material.dart';

import '../domain/places.dart';
import '../domain/towns.dart';
import 'place_search_box.dart';

/// The Location field of an offer or ad (admin Content): where it shows.
///
/// Search towns and pincodes in Andhra Pradesh / Telangana and tap a result to
/// add it; typing a district or state name also offers "All of ... district" /
/// "All of ... " for the whole area. Pick as many as needed. Left empty, the
/// offer shows in every town.
///
/// The value is the comma-separated text in [controller] (the same plain
/// field it always was, so older offers keep working and the text can still be
/// edited by hand): `Rajahmundry (East Godavari)`, `district:East Godavari`,
/// `state:Telangana`, or just `Rajahmundry` in older offers. Towns listed in
/// Business settings ("Towns you serve") still appear as quick chips.
class LocationTargetField extends StatelessWidget {
  const LocationTargetField({
    super.key,
    required this.controller,
    required this.label,
    this.quickTowns = const [],
  });
  final TextEditingController controller;
  final String label;
  final List<ServiceTown> quickTowns;

  List<String> get _tokens => parseLocationList(controller.text);

  bool _has(String token) =>
      _tokens.any((t) => t.toLowerCase() == token.toLowerCase());

  void _set(List<String> tokens) => controller.text = tokens.join(', ');

  void _add(String token) {
    if (!_has(token)) _set([..._tokens, token]);
  }

  void _remove(String token) =>
      _set(_tokens.where((t) => t.toLowerCase() != token.toLowerCase()).toList());

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final tokens = _tokens;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          if (tokens.isEmpty)
            const Text('Nothing chosen: this shows in every town.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final token in tokens)
                  InputChip(
                    key: ValueKey('location-token-$token'),
                    label: Text(describeLocationToken(token)),
                    onDeleted: () => _remove(token),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          PlaceSearchBox(
            label: 'Search a town or pincode to add',
            onPlace: (place) => _add(townToken(place)),
            onArea: (area) => _add(area.token),
          ),
          if (quickTowns.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final town in quickTowns)
                  FilterChip(
                    key: ValueKey('location-chip-${town.name}'),
                    label: Text(town.name),
                    selected: _has(town.name),
                    onSelected: (_) =>
                        _has(town.name) ? _remove(town.name) : _add(town.name),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          TextFormField(
            key: const ValueKey('locations-text'),
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Locations (comma-separated)',
              helperText:
                  'e.g. Rajahmundry (East Godavari), district:Krishna, state:Telangana',
            ),
          ),
        ],
      );
    },
  );
}
