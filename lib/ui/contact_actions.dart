import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/strings.dart';
import 'shared.dart';

class ContactActions extends StatelessWidget {
  const ContactActions({
    super.key,
    required this.phone,
    this.whatsapp = '',
    this.email = '',
    this.website = '',
    this.onUsed,
  });
  final String phone, whatsapp, email, website;
  // Told which way the customer made contact ('call', 'whatsapp', 'email', 'website'), e.g. to count it.
  final ValueChanged<String>? onUsed;
  Future<void> launch(BuildContext context, Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          context.mounted) {
        message(context, 'Could not open contact app');
      }
    } catch (e) {
      if (context.mounted) message(context, 'Could not open contact app');
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    children: [
      if (phone.isNotEmpty)
        OutlinedButton.icon(
          onPressed: () {
            onUsed?.call('call');
            launch(context, Uri(scheme: 'tel', path: phone));
          },
          icon: const Icon(Icons.call_outlined),
          label: Text('Call'.tr(context)),
        ),
      if (whatsapp.isNotEmpty || phone.isNotEmpty)
        OutlinedButton.icon(
          onPressed: () {
            onUsed?.call('whatsapp');
            launch(
              context,
              Uri.https(
                'wa.me',
                '/${(whatsapp.isEmpty ? phone : whatsapp).replaceAll(RegExp(r'\D'), '')}',
              ),
            );
          },
          icon: const Icon(Icons.chat_outlined),
          label: const Text('WhatsApp'),
        ),
      if (email.isNotEmpty)
        OutlinedButton.icon(
          onPressed: () {
            onUsed?.call('email');
            launch(context, Uri(scheme: 'mailto', path: email));
          },
          icon: const Icon(Icons.email_outlined),
          label: const Text('Email'),
        ),
      if (website.isNotEmpty)
        OutlinedButton.icon(
          onPressed: () {
            onUsed?.call('website');
            launch(context, Uri.parse(website));
          },
          icon: const Icon(Icons.public_outlined),
          label: const Text('Website'),
        ),
    ],
  );
}
