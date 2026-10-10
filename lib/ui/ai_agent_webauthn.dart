import 'package:flutter/material.dart';

import '../data/store.dart';
import 'ai_agent_webauthn_stub.dart' if (dart.library.js_interop) 'ai_agent_webauthn_web.dart';

/// Face ID via browser WebAuthn/passkeys. The private key never leaves the
/// iPhone's Secure Enclave — only a public key is ever sent to the server
/// (functions/ai-agent-webauthn.js), which is the only place verification
/// happens. On any platform other than web (this same app also builds for
/// Android/iOS), this fails closed rather than attempting anything, via the
/// conditional import above. Removing this file denies protected access.
bool isWebauthnSupported() => isWebauthnSupportedImpl();

/// One-time Face ID registration, after the trusted-device check has passed.
Future<bool> registerFaceId(BuildContext context, Store store) async {
  if (!isWebauthnSupported()) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Face ID registration needs a browser that supports WebAuthn.')));
    return false;
  }
  try {
    final options = await store.call('beginWebauthnRegistration', const {});
    final response = await startRegistrationImpl(options);
    await store.call('completeWebauthnRegistration', {'response': response});
    return true;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    return false;
  }
}

/// Face ID verification, the second step of the protected-access gate.
Future<bool> verifyFaceId(BuildContext context, Store store) async {
  if (!isWebauthnSupported()) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Face ID needs a browser that supports WebAuthn.')));
    return false;
  }
  try {
    final options = await store.call('beginWebauthnAssertion', const {});
    final response = await startAuthenticationImpl(options);
    await store.call('completeWebauthnAssertion', {'response': response});
    return true;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    return false;
  }
}

/// A plain button, used both in AiAgentSettings and (so registration is
/// reachable at all the first time — it would otherwise be locked behind the
/// gate it unlocks) directly in the gatekeeper's Face ID step. [onRegistered]
/// lets a caller advance automatically after a successful registration.
class RegisterFaceIdButton extends StatelessWidget {
  const RegisterFaceIdButton({super.key, required this.store, this.onRegistered});
  final Store store;
  final VoidCallback? onRegistered;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    icon: const Icon(Icons.face_retouching_natural),
    label: const Text('Register Face ID for the AI Agent'),
    onPressed: () async {
      final ok = await registerFaceId(context, store);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Face ID registered.' : 'Face ID registration was not completed.')));
      }
      if (ok) onRegistered?.call();
    },
  );
}
