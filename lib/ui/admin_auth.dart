import 'dart:async';
import 'package:flutter/material.dart';

import '../data/store.dart';
import 'admin.dart';
import 'shared.dart';

/// The admin panel's real entry point (see services/admin_route.dart for the
/// hidden URL that reaches it). Two mandatory steps gate access: password
/// sign-in to an account holding the admin claim, then a one-time email code
/// (functions/admin-otp.js). Neither step's success is remembered across a
/// reload — main.dart signs out any persisted session before this widget is
/// ever built, and the OTP flag below lives only in this State, so a fresh
/// visit to the URL always starts at the password step again.
class AdminEntryApp extends StatelessWidget {
  const AdminEntryApp({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Business studio',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b50)),
      ),
      home: AdminGate(store: store),
    ),
  );
}

class AdminGate extends StatefulWidget {
  const AdminGate({super.key, required this.store});
  final Store store;
  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  bool _otpVerified = false;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    if (store.user == null || !store.admin) {
      // Mutating a field during build (never calling setState here) only
      // affects what the *next* rebuild sees; it never causes one itself.
      _otpVerified = false;
      return AdminPasswordPage(store: store);
    }
    if (!_otpVerified) {
      return AdminOtpPage(
        store: store,
        onVerified: () => setState(() => _otpVerified = true),
      );
    }
    return AdminPage(store: store);
  }
}

class AdminPasswordPage extends StatefulWidget {
  const AdminPasswordPage({super.key, required this.store});
  final Store store;
  @override
  State<AdminPasswordPage> createState() => _AdminPasswordPageState();
}

class _AdminPasswordPageState extends State<AdminPasswordPage> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      await widget.store.login(email.text.trim(), password.text);
      await widget.store.refreshEmailVerification();
      // First factor failed: either these are not an admin's credentials, or
      // this account has not verified its email yet. Either way, do not leave
      // a signed-in-but-unqualified session sitting on the admin route.
      if (!widget.store.admin) {
        await widget.store.logout();
        throw StateError('Invalid administrator credentials.');
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> forgotPassword() async {
    final address = email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)) {
      message(context, 'Enter your administrator email address first.');
      return;
    }
    try {
      await widget.store.resetPassword(address);
      if (mounted) {
        message(context, 'If an account exists, a password reset email has been sent.');
      }
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Business studio')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Sign in with your administrator email and password. A verification code will be emailed to this account afterwards.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(labelText: 'Email address'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: password,
                enabled: !busy,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Password'),
                onSubmitted: (_) {
                  if (!busy) submit();
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(busy ? 'Signing in…' : 'Sign in'),
              ),
              TextButton(
                onPressed: busy ? null : forgotPassword,
                child: const Text('Forgot password?'),
              ),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    ),
  );
}

class AdminOtpPage extends StatefulWidget {
  const AdminOtpPage({super.key, required this.store, required this.onVerified});
  final Store store;
  final VoidCallback onVerified;
  @override
  State<AdminOtpPage> createState() => _AdminOtpPageState();
}

class _AdminOtpPageState extends State<AdminOtpPage> {
  final code = TextEditingController();
  bool busy = false, sent = false;
  int cooldown = 0;
  Timer? _ticker;
  String? info;

  @override
  void initState() {
    super.initState();
    requestCode();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    code.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _ticker?.cancel();
    setState(() => cooldown = seconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => cooldown = cooldown > 0 ? cooldown - 1 : 0);
      if (cooldown == 0) timer.cancel();
    });
  }

  Future<void> requestCode() async {
    setState(() {
      busy = true;
      info = null;
    });
    try {
      final result = await widget.store.call('requestAdminOtp', const {});
      final cooldownSeconds = (result['cooldownSeconds'] as num?)?.toInt() ?? 45;
      if (mounted) {
        setState(() {
          sent = true;
          info = 'A verification code has been emailed to your administrator address.';
        });
        _startCooldown(cooldownSeconds);
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      await widget.store.call('verifyAdminOtp', {'code': code.text.trim()});
      widget.onVerified();
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signOut() async {
    await widget.store.logout();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verify it’s you')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the 6-digit verification code sent to your administrator email address. It expires in 5 minutes and can be used once.',
                textAlign: TextAlign.center,
              ),
              if (info != null) ...[
                const SizedBox(height: 12),
                Text(info!, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              TextField(
                controller: code,
                enabled: !busy,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, letterSpacing: 8),
                decoration: const InputDecoration(labelText: 'Verification code', counterText: ''),
                onSubmitted: (_) {
                  if (!busy) submit();
                },
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy || !sent ? null : submit,
                child: Text(busy ? 'Verifying…' : 'Verify'),
              ),
              TextButton(
                onPressed: busy || cooldown > 0 ? null : requestCode,
                child: Text(cooldown > 0 ? 'Resend code (${cooldown}s)' : 'Resend code'),
              ),
              TextButton(
                onPressed: busy ? null : signOut,
                child: const Text('Sign out'),
              ),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    ),
  );
}
