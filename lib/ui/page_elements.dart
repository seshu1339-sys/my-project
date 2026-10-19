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
  // --- Home page, remaining sections (round 2) ---
  PageElement(13, 'notice', "Today's Best Offers strip"),
  PageElement(14, 'tickerMarquee', 'Ticker marquee banner'),
  PageElement(15, 'promo', 'Offers banner carousel'),
  PageElement(16, 'categories', 'Categories section'),
  PageElement(17, 'moreCategoriesTile', '"More Categories" tile'),
  PageElement(18, 'popular', 'Popular Products section'),
  PageElement(19, 'popularFilterChips', 'Popular Products filter chips'),
  PageElement(20, 'products', 'Product card template'),
  PageElement(21, 'localServices', 'Local Services section'),
  PageElement(22, 'adsLabel', '"ADS" label'),
  PageElement(23, 'ads', 'Advertisement box template'),
  PageElement(24, 'boxes', 'Promotional box template'),
  PageElement(25, 'nearby', 'Nearby shops section'),
  PageElement(26, 'nearbyShopCard', 'Nearby shop card'),
  PageElement(27, 'footerBadge1', 'Footer badge 1 — Fresh & Premium Quality'),
  PageElement(28, 'footerBadge2', 'Footer badge 2 — Fast & Safe Delivery'),
  PageElement(29, 'footerBadge3', 'Footer badge 3 — Best Prices Always'),
  PageElement(30, 'footerBadge4', 'Footer badge 4 — Easy Returns & Support'),
  PageElement(31, 'footerBadge5', 'Footer badge 5 — Local Shops & Trusted Sellers'),
  PageElement(32, 'footerBadge6', 'Footer badge 6 — Pay on Delivery'),
  // --- Other screens (round 3) -- no live preview exists for these (the
  // admin Visual Editor only ever renders the home page), so these are
  // reachable only via "Go to number" and the Layout Settings dropdown,
  // not by clicking in a live preview, and the "Show numbers" overlay has
  // nothing to draw a badge on for them. ---
  PageElement(33, 'productPageAddButton', 'Product page: "Add to bag" button'),
  PageElement(34, 'productPageBuyButton', 'Product page: "Buy now" button'),
  PageElement(35, 'productPageShareIcon', 'Product page: share icon'),
  PageElement(36, 'productPageWishlistIcon', 'Product page: wishlist icon'),
  PageElement(37, 'productPageRelatedHeading', 'Product page: "Related products" heading'),
  PageElement(38, 'productPageReviewsHeading', 'Product page: "Community reviews" heading'),
  PageElement(39, 'categoryPageHeading', 'Category page: section headings'),
  PageElement(40, 'cartEmptyMessage', 'Cart: empty-bag message'),
  PageElement(41, 'cartEmptyIcon', 'Cart: empty-bag icon'),
  PageElement(42, 'cartSubmitButton', 'Cart: submit order button'),
  PageElement(43, 'servicesPageAppBarTitle', 'Services page: title'),
  PageElement(44, 'shopsPageAppBarTitle', 'Shops page: title'),
  PageElement(45, 'shopsPageHeading', 'Shops page: heading'),
  PageElement(46, 'shopPageDirectionsButton', 'Shop page: "Get directions" button'),
  PageElement(47, 'shopPageRelatedHeading', 'Shop page: "From this shop" heading'),
  PageElement(48, 'accountPageAppBarTitle', 'Account page: title'),
  PageElement(49, 'accountDemoHeading', 'Account page: demo-mode heading'),
  PageElement(50, 'accountOrdersHeading', 'Account page: "Your orders" heading'),
  PageElement(51, 'authFormHeading', 'Sign-in form: heading'),
  PageElement(52, 'wishlistDialogTitle', 'Wishlist dialog: title'),
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
