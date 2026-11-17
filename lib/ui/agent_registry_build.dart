import '../domain/agent_registry.dart';
import '../domain/android_sizes.dart';
import '../domain/design_change.dart';
import 'admin_settings.dart';
import 'agent_ids.dart';
export 'agent_ids.dart';
import 'layout_settings.dart';

// The settings registry (owner spec B, 17 Nov 2026), made from the panel's OWN lists every time it is asked for, so a new page, field,
// layout part or Android size is in it by itself:
//   pages + form fields   adminSettingsIndex() (Settings sections, their form fields, the six groups' pages, the route map's extras)
//   website design        layoutComponents x allFieldsFor() (lib/ui/layout_settings.dart), ranges from dimensionFields
//   Android app design    androidSizeParts (lib/domain/android_sizes.dart), ranges from each field
// test/agent_registry_test.dart checks that every ID is unique and every option has a platform, a path and a "what it does".

/// Which platforms each page belongs to (step 1 of the command box). A page not named here is a website / admin page.
const _vendorPages = {
  'tab:Vendors', 'tab:Shops', 'tab:Products', 'tab:Plans', 'tab:Premium', 'tab:Payments', 'tab:Vendor Offers', 'tab:Support Team chat',
  'categories', 'productImageLibrary', 'module-itemPhotos', 'cityCodes', 'settings', 'shopsLocation', 'ratings', 'reports', 'idReport',
  'staffLinks', 'blockList',
};
const _staffPages = {
  'fieldAssistants', 'tab:Staff Areas', 'staffWork', 'staffRanking', 'idReport', 'staffLinks', 'locations', 'settings', 'cityCodes',
  'tab:Support Team chat',
};
const _userPages = {
  'androidHome', 'homeOffers', 'homePromo', 'homeFresh', 'scrollingText', 'ads', 'rightBoxes', 'categories', 'services', 'serviceProviders',
  'module-transport', 'areaNames', 'settings', 'theme', 'animations', 'layout', 'tab:Orders', 'tab:Complaints', 'tab:Support Team chat',
  'ratings', 'tab:Promotions', 'tab:Vendor Offers', 'productImageLibrary',
};
const _androidOnly = {'androidHome'};

/// Pages whose buttons suspend, delete, deactivate, approve or reject (owner spec I): the box says so before it opens them.
const riskyPages = {
  'tab:Vendors', 'fieldAssistants', 'serviceProviders', 'reports', 'blockList', 'samples', 'staffLinks', 'tab:Complaints', 'tab:Payments',
  'ratings', 'module-itemPhotos',
};

Set<AgentPlatform> platformsOf(String pageKey) => {
  if (!_androidOnly.contains(pageKey)) AgentPlatform.website,
  if (_vendorPages.contains(pageKey)) AgentPlatform.vendor,
  if (_staffPages.contains(pageKey)) AgentPlatform.staff,
  if (_userPages.contains(pageKey)) AgentPlatform.user,
};

String _slug(String key) => registrySlug(key);

final _telugu = RegExp(r'[ఀ-౿]');

/// The readable name of a layout field ("cameraIconColor" -> "Camera icon color").
String designFieldLabel(String key) {
  // The search box's image search icon is the camera people talk about.
  if (key == 'imageIconSize') return 'Camera (image search) icon size';
  final dim = dimensionFields[key];
  if (dim != null) return dim.$1;
  const named = {
    'visible': 'Visible on the site', 'backgroundColor': 'Background color', 'gradientStart': 'Gradient start color',
    'gradientEnd': 'Gradient end color', 'borderColor': 'Border color', 'textColor': 'Text color', 'fontFamily': 'Font family',
    'fontStyle': 'Font style', 'fontWeight': 'Font weight', 'text': 'Text', 'animation': 'Entrance animation',
    'searchIconColor': 'Search icon color', 'micIconColor': 'Mic icon color', 'cameraIconColor': 'Camera icon color',
    'placeholderColor': 'Placeholder text color', 'textAnimation': 'Text animation', 'headingAnimation': 'Heading animation',
    'backgroundImage': 'Background photo', 'alignment': 'Alignment', 'iconUrl': 'Icon picture',
  };
  if (named[key] != null) return named[key]!;
  final words = key.replaceAllMapped(RegExp('[A-Z]'), (m) => ' ${m[0]!.toLowerCase()}').trim();
  return words.isEmpty ? key : words[0].toUpperCase() + words.substring(1);
}

/// Every option of the admin panel. Made fresh each call (cheap: a few thousand small objects); the box keeps one copy while open.
List<RegistryEntry> buildAgentRegistry() {
  final out = <RegistryEntry>[];
  final index = adminSettingsIndex();
  for (final h in index) {
    final words = h.aliases.split(' | ').where((w) => w.trim().isNotEmpty).toList();
    final te = [for (final w in words) if (_telugu.hasMatch(w)) w];
    final en = [for (final w in words) if (!_telugu.hasMatch(w)) w];
    if (h.isField) {
      out.add(RegistryEntry(
        id: 'field.${h.sectionKey}.${h.hint}',
        name: h.title,
        path: 'Settings > ${h.section} > ${h.title}',
        platforms: platformsOf(h.sectionKey),
        what: '${h.title} (${h.section})',
        open: h.sectionKey,
        field: h.hint,
        serial: h.serial,
        kind: RegistryKind.field,
        risky: riskyPages.contains(h.sectionKey),
      ));
    } else {
      final extra = h.serial.startsWith('R');
      out.add(RegistryEntry(
        id: 'page.${_slug(h.sectionKey)}${extra ? '.${_slug(h.title)}' : ''}',
        name: h.title,
        path: h.sectionKey.startsWith('tab:') || h.sectionKey == 'serviceProviders' || extra ? '${h.hint} > ${h.title}' : 'Settings > ${h.title}',
        platforms: platformsOf(h.sectionKey),
        what: h.sectionKey.startsWith('tab:') || extra ? '${h.title} page' : h.hint,
        open: h.sectionKey,
        serial: h.serial,
        en: en,
        te: te,
        risky: riskyPages.contains(h.sectionKey),
      ));
    }
  }
  // Website design: every part of Settings > Layout and each of its properties.
  for (final c in layoutComponents.entries) {
    for (final f in allFieldsFor(c.key)) {
      final range = dimensionFields[f];
      out.add(RegistryEntry(
        id: 'design.web.${c.key}.$f',
        name: '${c.value} › ${designFieldLabel(f)}',
        path: 'Settings > Layout > ${c.value} > ${designFieldLabel(f)}',
        platforms: const {AgentPlatform.website, AgentPlatform.user},
        what: range == null ? '${designFieldLabel(f)} of ${c.value}' : '${designFieldLabel(f)} of ${c.value} (${_n(range.$2)} to ${_n(range.$3)})',
        open: 'layout:${c.key}',
        field: f,
        kind: RegistryKind.design,
        min: range?.$2,
        max: range?.$3,
        en: [c.key],
      ));
    }
  }
  // Values that were fixed in the code, now in settings/design (owner spec E): Settings > Design texts & sizes.
  for (final f in designFields) {
    out.add(RegistryEntry(
      id: 'design.web.design.${f.id}',
      name: f.label,
      path: 'Settings > Design texts & sizes > ${f.label}',
      platforms: const {AgentPlatform.website, AgentPlatform.user},
      what: f.isNumber ? '${f.label} (${_n(f.min!)} to ${_n(f.max!)}, default ${f.defaultValue})' : '${f.label} (default "${f.defaultValue}")',
      open: 'designTexts',
      field: f.id,
      kind: RegistryKind.design,
      min: f.min,
      max: f.max,
      te: f.te,
    ));
  }
  // Android app design: the sizes of Settings > Android App (the app reads them from the server, no Play Store update).
  for (final part in androidSizeParts) {
    for (final field in part.fields) {
      out.add(RegistryEntry(
        id: 'design.user.${part.id}.${field.id}',
        name: 'Android ${part.title} › ${field.label}',
        path: 'Settings > Android App > Sizes > ${part.title} > ${field.label}',
        platforms: const {AgentPlatform.user},
        what: '${field.label} of ${part.title} in the User app (${_n(field.min)} to ${_n(field.max)})',
        open: 'androidSizes',
        field: AndroidSizes.key(part.id, field.id),
        kind: RegistryKind.design,
        min: field.min,
        max: field.max,
        en: ['android', 'app', part.id],
        te: const ['ఆండ్రాయిడ్', 'యాప్'],
      ));
    }
  }
  return out;
}

String _n(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
