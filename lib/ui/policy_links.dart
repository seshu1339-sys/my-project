import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The policy pages of locamarket.in (static pages under web/), as small links under the sign-in of the customer, vendor and staff
/// apps. Each app points at its own Privacy Policy (web/privacy, web/privacy-vendor, web/privacy-staff); the rest are shared.
class PolicyLinks extends StatelessWidget {
  const PolicyLinks({super.key, required this.appRole});
  final String appRole;

  static String privacyPath(String appRole) => switch (appRole) {
    'vendor' => '/privacy-vendor',
    'staff' => '/privacy-staff',
    _ => '/privacy',
  };

  static List<(String, String)> pages(String appRole) => [
    ('Privacy Policy', privacyPath(appRole)),
    ('Terms & Conditions', '/terms'),
    if (appRole == 'vendor') ('Refund Policy', '/refund-policy'),
    if (appRole == 'vendor') ('Digital Delivery & Refund Policy', '/digital-delivery'),
    ('Contact Us', '/contact'),
  ];

  Future<void> _open(String path) async {
    try {
      await launchUrl(Uri.https('locamarket.in', path), mode: LaunchMode.externalApplication);
    } catch (_) {
      /* A link that cannot open must not break sign-in. */
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    children: [
      for (final (label, path) in pages(appRole))
        TextButton(
          key: ValueKey('policy-link-$path'),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12)),
          onPressed: () => _open(path),
          child: Text(label),
        ),
    ],
  );
}
