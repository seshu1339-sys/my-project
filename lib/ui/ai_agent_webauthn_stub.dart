// Non-web stub, selected by ai_agent_webauthn.dart's conditional import on
// every platform except web (Android/iOS native builds of the same app).
// Face ID via WebAuthn is a web-browser-only capability in this design
// (the admin panel is used as a web app in Safari) — fails closed here
// rather than attempting anything on native platforms.
bool isWebauthnSupportedImpl() => false;

Future<Map<String, dynamic>> startRegistrationImpl(Map<String, dynamic> optionsJson) =>
    Future.error(StateError('WebAuthn/Face ID is only available when the AI Agent is opened as a web page.'));

Future<Map<String, dynamic>> startAuthenticationImpl(Map<String, dynamic> optionsJson) =>
    Future.error(StateError('WebAuthn/Face ID is only available when the AI Agent is opened as a web page.'));
