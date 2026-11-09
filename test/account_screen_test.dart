import 'package:fitness_mobile/core/api.dart';
import 'package:fitness_mobile/core/session.dart';
import 'package:fitness_mobile/features/account/account_screen.dart';
import 'package:fitness_mobile/features/auth/firebase_sign_in.dart';
import 'package:fitness_mobile/services/health/health_sync.dart';
import 'package:fitness_mobile/services/health/health_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends ApiClient {
  _Api(super.sessions);

  final patches = <(String, Object?)>[];
  var posts = <String>[];

  @override
  Future<dynamic> patch(String path, {Object? body}) async {
    patches.add((path, body));
    final name = (body as Map)['name'];
    return {'id': 'u1', 'name': name, 'email': 'asha@example.test', 'created_at': '2026-11-09T00:00:00Z'};
  }

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    posts.add(path);
    return null;
  }
}

class _Health implements HealthSource {
  @override
  bool get available => true;
  @override
  String get displayName => 'Health Connect';
  @override
  String get sourceId => 'health_connect';
  @override
  Future<bool> requestAccess() async => true;
  @override
  Future<List<DayCount>> readDays(int days) async => const [];
}

class _Firebase implements FirebaseSignIn {
  @override
  Future<String> withGoogle() async => '';
  @override
  Future<String?> withEmail(String email, String password) async => null;
  @override
  Future<void> createAccount(String name, String email, String password) async {}
  @override
  Future<String?> verifiedIdToken() async => null;
  @override
  Future<void> resendVerification() async {}
  @override
  Future<void> sendPasswordReset(String email) async {}
  @override
  String? get provider => 'google.com';
  @override
  Future<String> confirmItIsYou({String? password}) async => '';
  @override
  Future<void> signOut() async {}
}

void main() {
  late SessionStore sessions;
  late _Api api;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({'fitness.health_connected': 'u1'});
    sessions = SessionStore();
    await sessions.save(
      const Session(
        access: 'a',
        refresh: 'r',
        user: User(id: 'u1', name: 'Asha Rao', email: 'asha@example.test'),
      ),
    );
    api = _Api(sessions);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [
          sessionStoreProvider.overrideWithValue(sessions),
          apiProvider.overrideWithValue(api),
          firebaseSignInProvider.overrideWithValue(_Firebase()),
          healthSyncProvider.overrideWithValue(HealthSync(api, sessions, _Health())),
        ],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('everything is on one page: no Settings row, no goal, country or hidden people cards', (tester) async {
    await open(tester);

    for (final title in ['PROFILE', 'STEP COUNTING', 'PRIVACY', 'HOW STEPS ARE COUNTED', 'ABOUT', 'DELETE ACCOUNT']) {
      expect(find.text(title, skipOffstage: false), findsOneWidget, reason: title);
    }
    expect(find.text('Settings'), findsNothing);
    expect(find.textContaining('Hidden people'), findsNothing);
    expect(find.textContaining('Step goal and country'), findsNothing);
    expect(find.textContaining('Country'), findsNothing);
    expect(find.text('Sign out', skipOffstage: false), findsOneWidget);
    expect(find.text('Delete my account', skipOffstage: false), findsOneWidget);
    expect(find.text('Google'), findsOneWidget, reason: 'how this person signed in');
  });

  testWidgets('Edit name saves the new name and the page shows it', (tester) async {
    await open(tester);

    await tester.tap(find.text('Edit name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Asha Sharma ');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(api.patches, hasLength(1));
    expect(api.patches.single.$1, '/auth/me');
    expect(api.patches.single.$2, {'name': 'Asha Sharma'});
    expect(sessions.session?.user.name, 'Asha Sharma');
    expect(find.text('Asha Sharma'), findsWidgets);
    expect(sessions.session?.access, 'a', reason: 'still signed in');
  });

  testWidgets('an empty name is not sent', (tester) async {
    await open(tester);
    await tester.tap(find.text('Edit name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(api.patches, isEmpty);
    expect(sessions.session?.user.name, 'Asha Rao');
  });

  testWidgets('Stop counting turns step counting off', (tester) async {
    await open(tester);
    expect(find.textContaining('Counting your steps from Health Connect'), findsOneWidget);

    await tester.tap(find.text('Stop counting'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Step counting is off'), findsOneWidget);
    expect(find.text('Stop counting'), findsNothing);
  });
}
