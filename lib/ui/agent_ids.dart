// The command box's option IDs that other files need without loading the whole registry (lib/ui/agent_registry_build.dart): kept in this
// small file with no imports, so the panel's pages can use them without an import loop.

/// The registry ID of a page of the panel (a Settings section key, 'tab:Plans', 'serviceProviders').
String pageRegistryId(String key) => 'page.${registrySlug(key)}';

String registrySlug(String key) => key.replaceFirst('tab:', 'tab.').replaceAll(RegExp(r'[^A-Za-z0-9.]+'), '-').toLowerCase();
