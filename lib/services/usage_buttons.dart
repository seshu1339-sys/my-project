/// Every screen and button the apps count (Usage.screen / Usage.button, lib/services/usage.dart), with the app it is in and what it
/// is, so the admin's Analytics can also show the ones nobody used. Add an entry here when a new screen or button is counted.
class UsageItem {
  const UsageItem(this.id, this.app, this.kind, this.label);
  final String id, app, kind, label;
}

const usageItems = [
  // ---- customer: screens
  UsageItem('home', 'customer', 'screen', 'Home'),
  UsageItem('product', 'customer', 'screen', 'Item page'),
  UsageItem('cart', 'customer', 'screen', 'Bag'),
  UsageItem('account', 'customer', 'screen', 'Account'),
  UsageItem('shop', 'customer', 'screen', 'Shop page'),
  UsageItem('shops', 'customer', 'screen', 'Shops'),
  UsageItem('category', 'customer', 'screen', 'Category'),
  UsageItem('services', 'customer', 'screen', 'Services'),
  UsageItem('transport', 'customer', 'screen', 'Transport (coming soon)'),
  UsageItem('where_to_buy', 'customer', 'screen', 'Where to buy (map and price list)'),
  UsageItem('nearby_search', 'customer', 'screen', 'Search products near me'),
  UsageItem('offers', 'customer', 'screen', 'Offers'),
  // ---- customer: buttons
  UsageItem('header_location', 'customer', 'button', 'Header: choose location'),
  UsageItem('header_voice_search', 'customer', 'button', 'Header: voice search'),
  UsageItem('header_camera_search', 'customer', 'button', 'Header: camera search'),
  UsageItem('header_notifications', 'customer', 'button', 'Header: notifications'),
  UsageItem('header_wishlist', 'customer', 'button', 'Header: wishlist'),
  UsageItem('header_cart', 'customer', 'button', 'Header: bag'),
  UsageItem('home_services', 'customer', 'button', 'Home: Services box'),
  UsageItem('home_transport', 'customer', 'button', 'Home: Transport box'),
  UsageItem('product_add_to_bag', 'customer', 'button', 'Item: Add to bag'),
  UsageItem('product_buy_now', 'customer', 'button', 'Item: Buy now'),
  UsageItem('product_compare_shops', 'customer', 'button', 'Item: Compare shops selling this'),
  UsageItem('product_wishlist', 'customer', 'button', 'Item: wishlist'),
  UsageItem('where_to_buy_choice', 'customer', 'button', 'Search: Where to buy choice'),
  UsageItem('where_to_buy_open_item', 'customer', 'button', 'Where to buy: Open the item'),
  // ---- vendor app
  UsageItem('vendor_home', 'vendor', 'screen', 'Vendor app home'),
  UsageItem('vendor_workspace', 'vendor', 'screen', 'Vendor workspace'),
  UsageItem('provider_page', 'vendor', 'screen', 'Service provider page'),
  UsageItem('vendor_my_ads', 'vendor', 'screen', 'My Ads'),
  UsageItem('vendor_home_vendor', 'vendor', 'button', 'Home: Vendor'),
  UsageItem('vendor_home_services', 'vendor', 'button', 'Home: Services'),
  UsageItem('vendor_home_transport', 'vendor', 'button', 'Home: Transport'),
  UsageItem('vendor_item_save', 'vendor', 'button', 'Add an item: Save'),
  UsageItem('vendor_add_another', 'vendor', 'button', 'Add another item'),
  UsageItem('vendor_shop_ad_tick', 'vendor', 'button', 'Ad for your shop: tick'),
  UsageItem('vendor_open_my_ads', 'vendor', 'button', 'Open My Ads'),
  UsageItem('provider_change_rate', 'vendor', 'button', 'Provider: change charge per hour'),
  // ---- staff app
  UsageItem('staff_workspace', 'staff', 'screen', 'Staff workspace'),
  UsageItem('staff_add', 'staff', 'screen', 'Add (Vendor / Services / Transport)'),
  UsageItem('staff_add_vendor', 'staff', 'screen', 'Add a vendor'),
  UsageItem('staff_add_provider', 'staff', 'screen', 'Add a service provider'),
  UsageItem('staff_service_types', 'staff', 'screen', 'Which service?'),
  UsageItem('staff_add_button', 'staff', 'button', 'Add'),
  UsageItem('staff_new_entry', 'staff', 'button', 'New entry'),
  UsageItem('staff_new_price', 'staff', 'button', 'My vendors: New price'),
  // ---- admin panel (each section opened)
  UsageItem('admin_analytics', 'admin', 'screen', 'Analytics'),
  UsageItem('admin_staff_additions', 'admin', 'screen', 'Added by staff'),
  UsageItem('admin_staff_report', 'admin', 'screen', 'Staff report'),
  UsageItem('admin_right_boxes', 'admin', 'screen', 'Right Side Ad Boxes'),
  UsageItem('admin_push_center', 'admin', 'screen', 'Push notifications'),
  UsageItem('admin_inactive_accounts', 'admin', 'screen', 'Inactive accounts'),
  UsageItem('admin_setup_check', 'admin', 'screen', 'Setup check'),
];
