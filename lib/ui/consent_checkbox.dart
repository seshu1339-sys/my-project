import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../services/strings.dart';
import 'policy_links.dart';

/// "I agree to the Terms & Conditions and the Privacy Policy", with both names opening the pages of locamarket.in. It shows English
/// unless the person chose another language in the customer app. The box is [Store.pendingConsent]: the sign-in screen and the
/// register form share it, and the agreement is saved on the server right after sign-in (lib/data/store_consent.dart).
class ConsentCheckbox extends StatefulWidget {
  const ConsentCheckbox({super.key, required this.store, this.enabled = true});
  final Store store;
  final bool enabled;
  @override
  State<ConsentCheckbox> createState() => _ConsentCheckboxState();
}

class _ConsentCheckboxState extends State<ConsentCheckbox> {
  late final TapGestureRecognizer _terms = TapGestureRecognizer()..onTap = () => PolicyLinks.open('/terms');
  late final TapGestureRecognizer _privacy = TapGestureRecognizer()
    ..onTap = () => PolicyLinks.open(PolicyLinks.privacyPath(widget.store.appRole));

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  /// The sentence with {terms} and {privacy} replaced by tappable names, in whatever order the language puts them.
  List<InlineSpan> _sentence(BuildContext context) {
    final link = TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline);
    final spans = <InlineSpan>[];
    var rest = 'I agree to the {terms} and the {privacy}.'.tr(context);
    final marker = RegExp(r'\{terms\}|\{privacy\}');
    for (var match = marker.firstMatch(rest); match != null; match = marker.firstMatch(rest)) {
      if (match.start > 0) spans.add(TextSpan(text: rest.substring(0, match.start)));
      final isTerms = match.group(0) == '{terms}';
      spans.add(TextSpan(
        text: (isTerms ? 'Terms & Conditions' : 'Privacy Policy').tr(context),
        style: link,
        recognizer: isTerms ? _terms : _privacy,
      ));
      rest = rest.substring(match.end);
    }
    if (rest.isNotEmpty) spans.add(TextSpan(text: rest));
    return spans;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              key: const ValueKey('consent-checkbox'),
              value: widget.store.pendingConsent,
              onChanged: widget.enabled
                  ? (value) {
                      widget.store.pendingConsent = value ?? false;
                      widget.store.consentChanged();
                    }
                  : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text.rich(TextSpan(style: Theme.of(context).textTheme.bodyMedium, children: _sentence(context)), key: const ValueKey('consent-sentence')),
              ),
            ),
          ],
        ),
        if (!widget.store.pendingConsent)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: Text(
              'Tick the box to agree before you continue.'.tr(context),
              key: const ValueKey('consent-hint'),
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}

/// The screen over the app for anyone who is signed in without an agreement for the current version (an account made before this
/// existed, or new pages). One tick and one button; "Log out" is the only other way out. Shown once: after it nobody is asked again.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key, required this.store});
  final Store store;
  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool busy = false;
  String? error;

  Future<void> _agree() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.acceptConsent();
    } catch (_) {
      if (mounted) setState(() => error = 'Your agreement could not be saved. Please try again.'.tr(context));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('consent-screen'),
    child: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text('Before you continue'.tr(context), style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text('To keep using the app, please agree to the Terms & Conditions and the Privacy Policy.'.tr(context)),
              const SizedBox(height: 16),
              ConsentCheckbox(store: widget.store, enabled: !busy),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, key: const ValueKey('consent-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('consent-agree'),
                onPressed: busy || !widget.store.pendingConsent ? null : _agree,
                child: Text('Agree and continue'.tr(context)),
              ),
              TextButton(
                key: const ValueKey('consent-logout'),
                onPressed: busy ? null : widget.store.logout,
                child: Text('Log out'.tr(context)),
              ),
              if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Puts [ConsentScreen] over the app while the signed-in person has not agreed yet. For a MaterialApp builder; the app below stays as it
/// was, so nothing is lost when the person agrees.
Widget withConsentGate(BuildContext context, Widget? child, Store store) => ListenableBuilder(
  listenable: store,
  builder: (context, _) => Stack(
    children: [
      Positioned.fill(child: child ?? const SizedBox.shrink()),
      if (store.showsConsentScreen) Positioned.fill(child: ConsentScreen(store: store)),
    ],
  ),
);
