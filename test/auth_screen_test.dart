import 'package:fitness_mobile/core/api.dart';
import 'package:fitness_mobile/core/session.dart';
import 'package:fitness_mobile/features/auth/auth_screen.dart';
import 'package:fitness_mobile/features/auth/firebase_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeApi extends ApiClient {
  FakeApi(super.sessions, {this.failWith});

  final ApiException? failWith;
  String? lastPath;
  Map<String, dynamic>? lastBody;

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    lastPath = path;
    lastBody = body as Map<String, dynamic>?;
    if (failWith != null) throw failWith!;
    return {
      'user': {'id': 'u1', 'name': 'Asha', 'email': 'asha@example.test'},
      'access_token': 'access',
      'refresh_token': 'refresh',
    };
  }
}

/// Stands in for Firebase and records what the screen asked it to do.
class FakeFirebase implements FirebaseSignIn {
  final calls = <String>[];
  bool verified = true; // is the email verified?
  bool verifiedAfterCheck = true; // is it verified once the person taps "I have verified"?
  SignInFailed? failWith;
  bool cancelGoogle = false;

  void _maybeFail() {
    if (failWith != null) throw failWith!;
  }

  @override
  Future<String> withGoogle() async {
    calls.add('google');
    if (cancelGoogle) throw const SignInCancelled();
    _maybeFail();
    return 'google-id-token';
  }

  @override
  Future<String?> withEmail(String email, String password) async {
    calls.add('signIn $email');
    _maybeFail();
    return verified ? 'email-id-token' : null;
  }

  @override
  Future<void> createAccount(String name, String email, String password) async {
    calls.add('create $name|$email');
    _maybeFail();
  }

  @override
  Future<String?> verifiedIdToken() async {
    calls.add('checkVerified');
    return verifiedAfterCheck ? 'verified-id-token' : null;
  }

  @override
  Future<void> resendVerification() async => calls.add('resend');

  @override
  Future<void> sendPasswordReset(String email) async => calls.add('reset $email');

  @override
  String? get provider => null;

  @override
  Future<String> confirmItIsYou({String? password}) async => 'fresh-id-token';

  @override
  Future<void> signOut() async => calls.add('signOut');
}

void main() {
  late SessionStore sessions;
  late FakeFirebase firebase;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    sessions = SessionStore();
    firebase = FakeFirebase();
  });

  Future<void> pump(WidgetTester tester, FakeApi api) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(sessions),
        apiProvider.overrideWithValue(api),
        firebaseSignInProvider.overrideWithValue(firebase),
      ],
      child: const MaterialApp(home: AuthScreen()),
    ),
  );

  Future<void> fill(WidgetTester tester, {String password = 'a-test-value'}) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'asha@example.test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), password);
  }

  testWidgets('empty fields are caught before anything is sent', (tester) async {
    final api = FakeApi(sessions);
    await pump(tester, api);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(api.lastPath, isNull);
    expect(firebase.calls, isEmpty);
  });

  testWidgets('signing in with email sends the Firebase token to the backend and stores the session', (tester) async {
    final api = FakeApi(sessions);
    await pump(tester, api);

    await fill(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(firebase.calls, ['signIn asha@example.test']);
    expect(api.lastPath, '/auth/firebase');
    expect(api.lastBody?['id_token'], 'email-id-token');
    expect(api.lastBody?.containsKey('password'), isFalse, reason: 'the password stays with Firebase');
    expect(sessions.signedIn, isTrue);
    expect(sessions.session?.user.name, 'Asha');
  });

  testWidgets('Continue with Google signs in the same way', (tester) async {
    final api = FakeApi(sessions);
    await pump(tester, api);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(api.lastPath, '/auth/firebase');
    expect(api.lastBody?['id_token'], 'google-id-token');
    expect(sessions.signedIn, isTrue);
  });

  testWidgets('closing the Google picker says nothing and signs nobody in', (tester) async {
    firebase.cancelGoogle = true;
    final api = FakeApi(sessions);
    await pump(tester, api);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(api.lastPath, isNull);
    expect(sessions.signedIn, isFalse);
    expect(find.textContaining('went wrong'), findsNothing);
  });

  testWidgets('an unverified email is not signed in: it asks to verify first', (tester) async {
    firebase.verified = false;
    final api = FakeApi(sessions);
    await pump(tester, api);

    await fill(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(api.lastPath, isNull, reason: 'the backend is never asked for a session');
    expect(sessions.signedIn, isFalse);
    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.textContaining('not verified yet'), findsOneWidget);

    // Not tapped the link yet: still waiting.
    firebase.verifiedAfterCheck = false;
    await tester.tap(find.text('I have verified my email'));
    await tester.pumpAndSettle();
    expect(sessions.signedIn, isFalse);
    expect(find.textContaining('Not verified yet'), findsOneWidget);

    // Now they tapped it.
    firebase.verifiedAfterCheck = true;
    await tester.tap(find.text('I have verified my email'));
    await tester.pumpAndSettle();
    expect(api.lastBody?['id_token'], 'verified-id-token');
    expect(sessions.signedIn, isTrue);
  });

  testWidgets('creating an account asks for a name, checks the password, then waits for the email link', (
    tester,
  ) async {
    final api = FakeApi(sessions);
    await pump(tester, api);

    await tester.tap(find.text('New here? Create an account'));
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Asha');
    await fill(tester, password: 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();
    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(firebase.calls, isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'a-test-value');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(firebase.calls, ['create Asha|asha@example.test']);
    expect(api.lastPath, isNull, reason: 'no session until the email is verified');
    expect(sessions.signedIn, isFalse);
    expect(find.text('Verify your email'), findsOneWidget);

    await tester.tap(find.text('Send the email again'));
    await tester.pumpAndSettle();
    expect(firebase.calls.last, 'resend');
  });

  testWidgets('Forgot password sends a reset link and does not say whether the email has an account', (tester) async {
    final api = FakeApi(sessions);
    await pump(tester, api);

    await tester.tap(find.text('Forgot password?'));
    await tester.pump();
    expect(find.widgetWithText(TextFormField, 'Password'), findsNothing);
    expect(find.text('Continue with Google'), findsNothing);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'asha@example.test');
    await tester.tap(find.widgetWithText(FilledButton, 'Send reset link'));
    await tester.pumpAndSettle();

    expect(firebase.calls, ['reset asha@example.test']);
    expect(find.textContaining('If asha@example.test has an account'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget, reason: 'back on the sign-in form');
  });

  testWidgets('a Firebase error is shown and lets you try again', (tester) async {
    firebase.failWith = const SignInFailed('Email or password is incorrect.');
    final api = FakeApi(sessions);
    await pump(tester, api);

    await fill(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    expect(sessions.signedIn, isFalse);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Sign in')).onPressed, isNotNull);
  });

  testWidgets('a backend refusal is shown too', (tester) async {
    final api = FakeApi(sessions, failWith: const ApiException(429, 'too_many_attempts', 'Too many attempts; wait.'));
    await pump(tester, api);

    await fill(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Too many attempts; wait.'), findsOneWidget);
    expect(sessions.signedIn, isFalse);
  });

  test('Firebase error codes become plain messages', () {
    expect(firebaseMessage('invalid-credential'), 'Email or password is incorrect.');
    expect(
      firebaseMessage('user-not-found'),
      firebaseMessage('wrong-password'),
      reason: 'must not reveal which emails exist',
    );
    expect(firebaseMessage('something-new'), contains('something-new'));
  });
}
