// Web-only implementation, selected by ai_agent_webauthn.dart's conditional
// import. Bridges to the @simplewebauthn/browser UMD bundle loaded in
// web/index.html — that library (same vendor as functions/ai-agent-webauthn.js's
// @simplewebauthn/server) already speaks the exact JSON shape the server
// sends/expects, so this file only needs to round-trip plain JSON through
// JSON.stringify/parse, never encode or decode any WebAuthn binary data itself.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('SimpleWebAuthnBrowser')
external JSObject? get _simpleWebAuthnBrowser;

@JS('JSON.stringify')
external JSString _jsonStringify(JSAny? value);

@JS('JSON.parse')
external JSAny _jsonParse(JSString text);

bool isWebauthnSupportedImpl() => _simpleWebAuthnBrowser != null;

Future<Map<String, dynamic>> _call(String method, Map<String, dynamic> optionsJson) async {
  final ns = _simpleWebAuthnBrowser;
  if (ns == null) throw StateError('WebAuthn is not available in this browser.');
  final argument = _jsonParse(jsonEncode({'optionsJSON': optionsJson}).toJS);
  final promise = ns.callMethod<JSPromise<JSAny?>>(method.toJS, argument);
  final result = await promise.toDart;
  if (result == null) throw StateError('No response from the authenticator.');
  return jsonDecode(_jsonStringify(result).toDart) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> startRegistrationImpl(Map<String, dynamic> optionsJson) =>
    _call('startRegistration', optionsJson);

Future<Map<String, dynamic>> startAuthenticationImpl(Map<String, dynamic> optionsJson) =>
    _call('startAuthentication', optionsJson);
