/// Master "element number" registry for the admin's numbered "Go to
/// number" search and the on-preview number badges (see visual_editor.dart,
/// visual_editor_overlay.dart). Each entry's `key` is the exact
/// `layoutComponents` key (lib/ui/layout_settings.dart) that number opens.
///
/// Numbers are permanent once assigned here: a later round that numbers
/// more of the page only ever appends new entries after the highest
/// existing number, never renumbers one already given out, so a number an
/// admin has already learned keeps meaning the same element.
///
/// This first round covers the Header only (elements 1-12). Every other
/// section (ticker, offers, categories, popular, local services, ads/boxes,
/// nearby, footer) is still unnumbered and will be appended here in a later
/// round.
class PageElement {
  const PageElement(this.number, this.key, this.label);
  final int number;
  final String key;
  final String label;
}

const pageElements = <PageElement>[
  PageElement(1, 'logo', 'Logo'),
  PageElement(2, 'title', 'Local Market title'),
  PageElement(3, 'tagline', 'Tagline'),
  PageElement(4, 'user', 'Welcome text'),
  PageElement(5, 'location', 'Choose your location'),
  PageElement(6, 'search', 'Search box'),
  PageElement(7, 'services', 'Services icon'),
  PageElement(8, 'notificationIcon', 'Notifications icon'),
  PageElement(9, 'wishlistIcon', 'Wishlist icon'),
  PageElement(10, 'cartIcon', 'Shopping bag icon'),
  PageElement(11, 'menuIcon', 'Menu icon'),
  PageElement(12, 'office', 'Office address & phone'),
];

PageElement? pageElementByNumber(int number) => pageElements.where((e) => e.number == number).firstOrNull;
PageElement? pageElementByKey(String key) => pageElements.where((e) => e.key == key).firstOrNull;

/// "3 – Welcome text" when [key] has a number yet, otherwise just the plain
/// [fallbackLabel] -- used anywhere a component's label is shown in the
/// admin so numbered elements are instantly recognizable without changing
/// the label of every not-yet-numbered section.
String numberedLabel(String key, String fallbackLabel) {
  final element = pageElementByKey(key);
  return element == null ? fallbackLabel : '${element.number} – $fallbackLabel';
}
