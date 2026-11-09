import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/api.dart';
import '../../core/session.dart' hide User;
import '../../firebase_options.dart';

/// Signing in goes in two steps:
///  1. Firebase checks who you are (your Google account, or your email and password,
///     with the email verified by a link Firebase sends).
///  2. The app sends Firebase's ID token to our backend (POST /auth/firebase), which
///     checks it and answers with the app's own session, like the old login did.
///
/// This class is step 1. Screens talk to it, never to Firebase directly, so tests can
/// swap in a fake.
abstract class FirebaseSignIn {
  /// Signs in with a Google account. Returns the Firebase ID token.
  /// Throws [SignInCancelled] if the person closed the account picker.
  Future<String> withGoogle();

  /// Signs in with email and password. Returns the ID token, or null when the email is
  /// not verified yet (they stay signed in to Firebase so [verifiedIdToken] can follow).
  Future<String?> withEmail(String email, String password);

  /// Makes a Firebase account and emails a link to verify the address.
  Future<void> createAccount(String name, String email, String password);

  /// After the person tapped the link in the email: the ID token if the email is now
  /// verified, else null.
  Future<String?> verifiedIdToken();

  Future<void> resendVerification();

  /// Emails a link to choose a new password. Says nothing about whether the email has
  /// an account, so nobody can use it to find out who uses the app.
  Future<void> sendPasswordReset(String email);

  /// How the person on this phone signed in: 'google.com', 'password', or null for an
  /// account from before Firebase.
  String? get provider;

  /// Proves again that it is really them (for deleting the account). Google asks to
  /// pick the account again; email needs the password. Returns a fresh ID token.
  Future<String> confirmItIsYou({String? password});

  Future<void> signOut();
}

class SignInCancelled implements Exception {
  const SignInCancelled();
}

/// A message to show on the sign-in screen.
class SignInFailed implements Exception {
  const SignInFailed(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Whether this build can use Firebase at all (the phone apps can; web and desktop not yet).
bool get firebaseSupported =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Called once from main(), before the first screen.
Future<void> startFirebase() async {
  if (!firebaseSupported) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

final firebaseSignInProvider = Provider<FirebaseSignIn>((ref) => RealFirebaseSignIn());

/// Trades a Firebase ID token for the app's own session and saves it. [name] is used
/// only for a brand-new account when Firebase has none.
Future<void> finishSignIn(WidgetRef ref, String idToken, {String? name}) async {
  final json = await ref
      .read(apiProvider)
      .post('/auth/firebase', body: {'id_token': idToken, if (name != null && name.isNotEmpty) 'name': name});
  // Saving the session makes the router leave the sign-in screen by itself.
  await ref.read(sessionStoreProvider).save(Session.fromAuthResponse(json as Map<String, dynamic>));
}

class RealFirebaseSignIn implements FirebaseSignIn {
  FirebaseAuth get _auth {
    if (!firebaseSupported) throw const SignInFailed('Sign-in works in the phone app.');
    return FirebaseAuth.instance;
  }

  Future<void>? _googleReady;

  Future<GoogleSignInAccount> _pickGoogleAccount() async {
    final google = GoogleSignIn.instance;
    _googleReady ??= google.initialize(
      clientId: defaultTargetPlatform == TargetPlatform.iOS ? DefaultFirebaseOptions.googleIosClientId : null,
      serverClientId: DefaultFirebaseOptions.googleServerClientId,
    );
    await _googleReady;
    try {
      return await google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw const SignInCancelled();
      throw SignInFailed('Google sign-in did not work (${e.code.name}). Please try again.');
    }
  }

  OAuthCredential _googleCredential(GoogleSignInAccount account) {
    final idToken = account.authentication.idToken;
    if (idToken == null) throw const SignInFailed('Google did not confirm the account. Please try again.');
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  @override
  Future<String> withGoogle() async {
    final account = await _pickGoogleAccount();
    final result = await _guard(() => _auth.signInWithCredential(_googleCredential(account)));
    return _token(result.user!);
  }

  @override
  Future<String?> withEmail(String email, String password) async {
    final result = await _guard(() => _auth.signInWithEmailAndPassword(email: email.trim(), password: password));
    final user = result.user!;
    return user.emailVerified ? _token(user) : null;
  }

  @override
  Future<void> createAccount(String name, String email, String password) async {
    final result = await _guard(() => _auth.createUserWithEmailAndPassword(email: email.trim(), password: password));
    final user = result.user!;
    await _guard(() => user.updateDisplayName(name.trim()));
    await _guard(user.sendEmailVerification);
  }

  @override
  Future<String?> verifiedIdToken() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    await _guard(user.reload);
    final fresh = _auth.currentUser!;
    return fresh.emailVerified ? _token(fresh) : null;
  }

  @override
  Future<void> resendVerification() async {
    final user = _auth.currentUser;
    if (user != null) await _guard(user.sendEmailVerification);
  }

  @override
  Future<void> sendPasswordReset(String email) => _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  String? get provider {
    if (!firebaseSupported) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final ids = user.providerData.map((p) => p.providerId).toList();
    return ids.contains('google.com') ? 'google.com' : (ids.contains('password') ? 'password' : null);
  }

  @override
  Future<String> confirmItIsYou({String? password}) async {
    final user = _auth.currentUser;
    if (user == null) throw const SignInFailed('Please sign out and sign in again first.');
    final AuthCredential credential;
    if (provider == 'google.com') {
      credential = _googleCredential(await _pickGoogleAccount());
    } else {
      credential = EmailAuthProvider.credential(email: user.email ?? '', password: password ?? '');
    }
    final result = await _guard(() => user.reauthenticateWithCredential(credential));
    return _token(result.user!);
  }

  @override
  Future<void> signOut() async {
    if (!firebaseSupported) return;
    await FirebaseAuth.instance.signOut();
    try {
      await _googleReady;
      if (_googleReady != null) await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Signing out of Google only makes it ask for the account next time; nothing to show.
    }
  }

  Future<String> _token(User user) async {
    final token = await _guard(() => user.getIdToken(true));
    if (token == null) throw const SignInFailed('Firebase did not answer. Please try again.');
    return token;
  }

  /// Turns Firebase's errors into messages for the screen.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on FirebaseAuthException catch (e) {
      throw SignInFailed(firebaseMessage(e.code));
    }
  }
}

@visibleForTesting
String firebaseMessage(String code) => switch (code) {
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' ||
  'invalid-login-credentials' => 'Email or password is incorrect.',
  'email-already-in-use' => 'An account with this email already exists. Sign in instead.',
  'invalid-email' => 'Enter a valid email.',
  'weak-password' => 'Use a stronger password (at least 8 characters).',
  'too-many-requests' => 'Too many tries. Wait a few minutes and try again.',
  'network-request-failed' => 'No internet connection. Check it and try again.',
  'user-disabled' => 'This account has been turned off.',
  'requires-recent-login' => 'Please sign in again, then try once more.',
  'user-mismatch' => 'That is a different account from the one signed in.',
  'account-exists-with-different-credential' =>
    'This email already signs in another way. Use email and password, or the way you used before.',
  _ => 'Sign-in did not work ($code). Please try again.',
};
