import 'package:fitness_mobile/app/app.dart';
import 'package:fitness_mobile/core/api.dart';
import 'package:fitness_mobile/core/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers like the backend and counts how often each address is asked for.
class FakeApi extends ApiClient {
  FakeApi(super.sessions);

  final gets = <String, int>{};

  int count(String path) => gets[path] ?? 0;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    gets[path] = count(path) + 1;
    return switch (path) {
      '/plans' => {
        'items': [
          for (final part in ['back', 'biceps', 'triceps', 'forearms', 'chest', 'legs', 'abs', 'shoulders'])
            {'body_part': part, 'exercise_count': 0},
        ],
      },
      '/nudges' => {'unread': 0, 'items': <dynamic>[]},
      '/diary' => {
        'date': query?['date'],
        'entries': <dynamic>[],
        'totals': {'calories': 0, 'protein_g': 0, 'carbs_g': 0, 'fat_g': 0},
      },
      '/goals' => {'calories': 2000, 'is_default': true},
      '/water' => {'water_ml': 0},
      '/steps/today' => {
        'date': '2026-11-07',
        'steps': 100,
        'goal': 10000,
        'goal_met': false,
        'distance_km': 0.08,
        'calories': 4,
        'current_streak': 0,
        'sources': <dynamic>[],
      },
      '/steps/history' => {
        'goal': 10000,
        'total_steps': 100,
        'average_steps': 14,
        'days': [
          for (var day = 1; day <= 7; day++) {'date': '2026-11-0$day', 'steps': 100, 'goal_met': false},
        ],
      },
      '/steps/stats' => {
        'longest_streak': 0,
        'best_day': null,
        'best_week': null,
        'lifetime_steps': 100,
        'lifetime_distance_km': 0.08,
        'this_week': {'steps': 100, 'days_goal_met': 0},
        'achievements': <dynamic>[],
        'country_rank': null,
      },
      _ => throw StateError('No fake answer for $path'),
    };
  }
}

void main() {
  late SessionStore sessions;
  late FakeApi api;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    sessions = SessionStore();
    api = FakeApi(sessions);
  });

  Future<void> startApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [sessionStoreProvider.overrideWithValue(sessions), apiProvider.overrideWithValue(api)],
        child: const HxvyApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(NavigationDestination, label));
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester) async {
    await sessions.save(
      const Session(
        access: 'a',
        refresh: 'r',
        user: User(id: 'u1', name: 'Asha', email: 'asha@example.test'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('without a login only the login screen is reachable', (tester) async {
    await startApp(tester);
    expect(find.text('Sign in to track your training'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(api.count('/plans'), 0);
  });

  testWidgets('signing in opens the Workout tab and signing out leads back to the login', (tester) async {
    await startApp(tester);

    await signIn(tester);
    expect(find.textContaining(', Asha'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(find.widgetWithText(NavigationDestination, 'Workout'), findsOneWidget);
    expect(find.widgetWithText(NavigationDestination, 'Food'), findsOneWidget);
    expect(find.widgetWithText(NavigationDestination, 'Steps'), findsOneWidget);
    expect(find.byTooltip('Account'), findsOneWidget);

    await sessions.save(null);
    await tester.pumpAndSettle();
    expect(find.text('Sign in to track your training'), findsOneWidget);
  });

  testWidgets('a tab loads once when first opened and again when you come back to it', (tester) async {
    await startApp(tester);
    await signIn(tester);
    expect(api.count('/plans'), 1);

    await openTab(tester, 'Steps');
    expect(api.count('/steps/today'), 1, reason: 'opening a tab should not fetch everything twice');

    await openTab(tester, 'Workout');
    expect(api.count('/plans'), 2, reason: 'what changed elsewhere must show when you come back');

    await openTab(tester, 'Steps');
    expect(api.count('/steps/today'), 2);
  });

  // The Food tab has no meals card any more, so Add food is the only way to the day's meals.
  testWidgets('Add food on the Food tab opens today\'s meals', (tester) async {
    await startApp(tester);
    await signIn(tester);
    await openTab(tester, 'Food');

    await tester.tap(find.text('Add food'));
    await tester.pumpAndSettle();
    expect(find.text('Meals · Today'), findsOneWidget);
    expect(find.text('Breakfast'), findsOneWidget);
  });
}
