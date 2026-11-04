/// Switches for parts of the app that are written but kept out of sight.
///
/// Loca Market sends an order request to the vendor and does not deliver or take money, so its own promises about delivery and payment
/// on delivery are hidden. Set this to true to show them again: the "Fast & Safe Delivery" and "Pay on Delivery" footer badges, the two
/// delivery ads in the starter data, the "Cash on delivery" payment choice, and the "Free delivery" line of the starter notice.
/// (The delivery charge the admin sets by distance is not behind this switch: it is shown whenever the admin has set it.)
const bool showDeliveryPromises = false;
