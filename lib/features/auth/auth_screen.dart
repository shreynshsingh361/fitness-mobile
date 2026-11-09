import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import 'firebase_sign_in.dart';

enum _Mode { signIn, signUp, forgot, verify }

/// Sign in, sign up and "forgot password", all through Firebase (see firebase_sign_in.dart).
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  FirebaseSignIn get _firebase => ref.read(firebaseSignInProvider);

  void _go(_Mode mode) => setState(() {
    _mode = mode;
    _error = null;
    _notice = null;
  });

  /// Runs one step with the spinner on, and shows what went wrong.
  Future<void> _run(Future<void> Function() step) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await step();
    } on SignInCancelled {
      // They closed the Google account picker: nothing to say.
    } on SignInFailed catch (e) {
      _error = e.message;
    } on ApiException catch (e) {
      _error = e.code == 'email_not_verified' ? 'Verify your email first.' : e.message;
    } catch (_) {
      _error = 'Something went wrong. Please try again.';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _google() => _run(() async {
    final token = await _firebase.withGoogle();
    await finishSignIn(ref, token);
  });

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    switch (_mode) {
      case _Mode.signIn:
        await _run(() async {
          final token = await _firebase.withEmail(_email.text, _password.text);
          if (token == null) {
            _mode = _Mode.verify;
            _notice = 'Your email is not verified yet. Open the link we sent to ${_email.text.trim()}.';
            return;
          }
          await finishSignIn(ref, token);
        });
      case _Mode.signUp:
        await _run(() async {
          await _firebase.createAccount(_name.text, _email.text, _password.text);
          _mode = _Mode.verify;
          _notice = 'We sent a link to ${_email.text.trim()}. Open it to verify your email, then come back.';
        });
      case _Mode.forgot:
        await _run(() async {
          await _firebase.sendPasswordReset(_email.text);
          _mode = _Mode.signIn;
          _notice =
              'If ${_email.text.trim()} has an account, a link to choose a new password is on its way. '
              'Check spam too.';
        });
      case _Mode.verify:
        break;
    }
  }

  Future<void> _verified() => _run(() async {
    final token = await _firebase.verifiedIdToken();
    if (token == null) {
      _notice = 'Not verified yet. Tap the link in the email first (check spam too).';
      return;
    }
    await finishSignIn(ref, token, name: _name.text.trim());
  });

  Future<void> _resend() => _run(() async {
    await _firebase.resendVerification();
    _notice = 'Sent again. Check your inbox and spam.';
  });

  Future<void> _useAnotherAccount() async {
    await _firebase.signOut();
    _go(_Mode.signIn);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = switch (_mode) {
      _Mode.signIn => 'Sign in to track your training',
      _Mode.signUp => 'Create your account',
      _Mode.forgot => 'Reset your password',
      _Mode.verify => 'Verify your email',
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Hxvy',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    if (_error != null) ...[
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                      const SizedBox(height: 12),
                    ],
                    if (_notice != null) ...[
                      Text(_notice!, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 12),
                    ],
                    ...switch (_mode) {
                      _Mode.verify => _verifyParts(),
                      _ => _formParts(),
                    },
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _verifyParts() => [
    FilledButton(onPressed: _busy ? null : _verified, child: Text(_busy ? 'Please wait…' : 'I have verified my email')),
    const SizedBox(height: 8),
    OutlinedButton(onPressed: _busy ? null : _resend, child: const Text('Send the email again')),
    const SizedBox(height: 8),
    TextButton(onPressed: _busy ? null : _useAnotherAccount, child: const Text('Use another account')),
  ];

  List<Widget> _formParts() {
    final signUp = _mode == _Mode.signUp;
    final forgot = _mode == _Mode.forgot;
    return [
      if (!forgot) ...[
        OutlinedButton.icon(
          onPressed: _busy ? null : _google,
          icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          label: const Text('Continue with Google'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 16),
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or')),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
      ],
      if (signUp) ...[
        TextFormField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          maxLength: 80,
          validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
        ),
        const SizedBox(height: 4),
      ],
      TextFormField(
        controller: _email,
        decoration: const InputDecoration(labelText: 'Email'),
        keyboardType: TextInputType.emailAddress,
        textInputAction: forgot ? TextInputAction.done : TextInputAction.next,
        autocorrect: false,
        autofillHints: const [AutofillHints.email],
        onFieldSubmitted: forgot ? (_) => _submit() : null,
        validator: (v) =>
            RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email',
      ),
      if (!forgot) ...[
        const SizedBox(height: 12),
        TextFormField(
          controller: _password,
          decoration: InputDecoration(labelText: 'Password', helperText: signUp ? 'At least 8 characters' : null),
          obscureText: true,
          autofillHints: [signUp ? AutofillHints.newPassword : AutofillHints.password],
          onFieldSubmitted: (_) => _submit(),
          validator: (v) {
            if ((v ?? '').isEmpty) return 'Enter your password';
            if (signUp && v!.length < 8) return 'Use at least 8 characters';
            return null;
          },
        ),
      ],
      if (_mode == _Mode.signIn)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _busy ? null : () => _go(_Mode.forgot), child: const Text('Forgot password?')),
        )
      else
        const SizedBox(height: 20),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(
          _busy
              ? 'Please wait…'
              : switch (_mode) {
                  _Mode.signUp => 'Create account',
                  _Mode.forgot => 'Send reset link',
                  _ => 'Sign in',
                },
        ),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _busy ? null : () => _go(_mode == _Mode.signIn ? _Mode.signUp : _Mode.signIn),
        child: Text(_mode == _Mode.signIn ? 'New here? Create an account' : 'Back to sign in'),
      ),
      if (_mode == _Mode.signIn) ...[
        const SizedBox(height: 8),
        Text(
          'Had an account before? Use Google with the same email, or create an account with the same email: '
          'your workouts and steps stay.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    ];
  }
}
