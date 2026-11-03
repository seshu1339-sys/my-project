import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/strings.dart';
import 'shared.dart';

/// The website's bottom strip: the Google Play link for the customer app,
/// the policy pages (static pages under web/, served by firebase.json
/// rewrites) and the business details payment partners such as Razorpay
/// look for. Shown on the website only -- the Android app leaves it out.
class HomeSiteLinks extends StatelessWidget {
  const HomeSiteLinks({super.key});

  static const playStoreUrl = 'https://play.google.com/store/apps/details?id=in.locamarket.locamark';
  static const businessLine = 'Bollapragada Seshu (Sole Proprietor) · 1-1, Beside Bank of India, Ramaraopeta, Narsipatnam, Anakapalli Dt, Andhra Pradesh 531116';
  static const contactLine = '+91 83284 32265 · info@locamarket.in';

  static const pages = [
    ('Premium Vendor Plan', '/pricing'),
    ('Terms & Conditions', '/terms'),
    ('Refund Policy', '/refund-policy'),
    ('Privacy Policy', '/privacy-policy'),
    ('Contact Us', '/contact'),
  ];

  Future<void> open(BuildContext context, String url, {bool newTab = false}) async {
    try {
      if (!await launchUrl(Uri.base.resolve(url), webOnlyWindowName: newTab ? '_blank' : '_self') && context.mounted) {
        message(context, 'Could not open the page');
      }
    } catch (e) {
      if (context.mounted) message(context, 'Could not open the page');
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          FilledButton.icon(
            key: const ValueKey('site-google-play'),
            onPressed: () => open(context, playStoreUrl, newTab: true),
            icon: const Icon(Icons.android),
            label: Text('Get the app on Google Play'.tr(context)),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              for (final (label, path) in pages)
                TextButton(
                  key: ValueKey('site-link-$path'),
                  onPressed: () => open(context, path),
                  child: Text(label.tr(context)),
                ),
            ],
          ),
          Text(businessLine, textAlign: TextAlign.center, style: muted),
          Text(contactLine, textAlign: TextAlign.center, style: muted),
        ],
      ),
    );
  }
}
