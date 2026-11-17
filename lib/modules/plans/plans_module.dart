// Subscription Plans module: the admin makes plans, the vendor app shows exactly those names and prices. A plan never hides a shop; it only
// unlocks the special services the admin chooses, while it runs. Own folder, own collections (functions/modules/plans/store.js), and no
// import from another module. The vendor pays through whatever [VendorPlansSection.onPay] the app passes in.
export 'plan_badge.dart';
export 'vendor_plans_section.dart';

const plansRoute = '/plans';
