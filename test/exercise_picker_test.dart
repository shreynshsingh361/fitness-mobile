import 'package:fitness_mobile/core/api.dart';
import 'package:fitness_mobile/core/session.dart';
import 'package:fitness_mobile/features/workouts/body_part_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> exercise(String id, String name, String part, String muscles) => {
  'id': id,
  'name': name,
  'muscle_group': 'arms',
  'equipment': 'barbell',
  'body_part': part,
  'motion': 'curl',
  'muscles': muscles,
};

/// Answers the biceps list with a forearms exercise mixed in, to prove the card keeps it out.
class _FakeApi extends ApiClient {
  _FakeApi(super.sessions);

  final asked = <Map<String, dynamic>?>[];

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    if (path == '/exercises') {
      asked.add(query);
      return {
        'items': [
          exercise('1', 'Barbell Curl', 'biceps', 'Biceps'),
          exercise('2', 'Hammer Curl', 'biceps', 'Brachialis, forearms'),
          exercise('3', 'Reverse Curl', 'forearms', 'Brachioradialis, forearms'),
        ],
        'total': 3,
      };
    }
    if (path == '/plans/biceps') return {'body_part': 'biceps', 'exercises': <dynamic>[]};
    throw StateError('No fake answer for $path');
  }
}

void main() {
  testWidgets('searching in a card only ever shows that card\'s exercises', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = _FakeApi(SessionStore());
    await tester.pumpWidget(
      ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [apiProvider.overrideWithValue(api)],
        child: MaterialApp(
          builder: (context, child) =>
              MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(onPressed: () => showExercisePicker(context, 'biceps'), child: const Text('Add')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(api.asked.single, containsPair('body_part', 'biceps'), reason: 'the server is asked for biceps only');
    expect(find.text('Barbell Curl'), findsOneWidget);
    expect(find.text('Reverse Curl'), findsNothing);

    await tester.enterText(find.byType(TextField), 'curl');
    await tester.pump();
    expect(find.text('Barbell Curl'), findsOneWidget);
    expect(find.text('Hammer Curl'), findsOneWidget);
    expect(find.text('Reverse Curl'), findsNothing, reason: 'a forearms exercise never shows under biceps');

    await tester.enterText(find.byType(TextField), 'forearms');
    await tester.pump();
    expect(find.text('Hammer Curl'), findsOneWidget, reason: 'a biceps exercise that also works the forearms');
    expect(find.text('Reverse Curl'), findsNothing);
  });
}
