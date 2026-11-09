import 'package:fitness_mobile/core/api.dart';
import 'package:fitness_mobile/core/session.dart';
import 'package:fitness_mobile/features/workouts/body_part_screen.dart';
import 'package:fitness_mobile/features/workouts/exercise_motion.dart';
import 'package:fitness_mobile/features/workouts/plan_exercise_screen.dart';
import 'package:fitness_mobile/features/workouts/workouts_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Every motion the backend's exercise library uses (workout-service migration 003).
const backendMotions = [
  'deadlift', 'pullup', 'row', 'pulldown', 'cable_row', 'straight_pulldown', //
  'curl', 'cable_curl', 'preacher', 'concentration',
  'pushdown', 'skull', 'overhead_ext', 'bench', 'bench_dip',
  'incline', 'fly_lying', 'fly', 'pushup', 'dip', 'chest_press',
  'squat', 'rdl', 'leg_press', 'lunge', 'leg_extension', 'leg_curl', 'calf_raise',
  'crunch', 'leg_raise', 'hanging_leg_raise', 'cable_crunch', 'plank',
  'press', 'lateral_raise', 'front_raise', 'reverse_fly', 'face_pull',
  // migration 004, the full library
  'pullover', 'incline_curl', 'spider_curl', 'high_cable_curl', 'kickback', 'wrist_curl',
  'reverse_wrist_curl', 'wrist_roller', 'farmer_walk', 'dead_hang', 'hip_thrust',
  'mountain_climber', 'ab_wheel', 'upright_row',
];

Map<String, dynamic> planJson({
  String unit = 'kg',
  List<List<num>> sets = const [
    [40, 10],
    [40, 10],
    [40, 10],
  ],
}) => {
  'id': 'p1',
  'unit': unit,
  'exercise': {
    'id': 'e1',
    'name': 'Barbell Row',
    'muscle_group': 'back',
    'equipment': 'barbell',
    'body_part': 'back',
    'motion': 'row',
    'muscles': 'Lats, rhomboids, rear delts',
  },
  'sets': [
    for (final s in sets) {'weight': s[0], 'reps': s[1]},
  ],
};

void main() {
  group('motions', () {
    test('every exercise in the library has an animation', () {
      for (final name in backendMotions) {
        expect(motions, contains(name), reason: name);
      }
    });

    test('limbs keep their length and the anchor stays put through the whole lift', () {
      for (final MapEntry(key: name, value: motion) in motions.entries) {
        final start = Figure.of(motion, 0);
        for (var i = 1; i <= 10; i++) {
          final f = Figure.of(motion, i / 10);
          final anchor = switch (motion.anchor) {
            Anchor.hip => (f.hip, start.hip),
            Anchor.foot => (f.legs.first.ankle, start.legs.first.ankle),
            Anchor.toe => (f.legs.first.toe, start.legs.first.toe),
            Anchor.hand => (f.hand, start.hand),
          };
          expect((anchor.$1 - anchor.$2).distance, lessThan(0.001), reason: '$name anchor at ${i / 10}');
          final thigh = (f.legs.first.knee - f.legs.first.hip).distance;
          expect(thigh, closeTo(36, 0.001), reason: '$name thigh');
          if (!motion.foreshorten && motion.start.reach == 1 && motion.end.reach == 1) {
            expect((f.arms.first.elbow - f.arms.first.shoulder).distance, closeTo(27, 0.001), reason: '$name arm');
          }
        }
      }
    });

    test('the loop pauses, lifts, holds at the top and comes back down', () {
      expect(liftProgress(0.05), 0);
      expect(liftProgress(0.3), inExclusiveRange(0, 1));
      expect(liftProgress(0.5), 1);
      expect(liftProgress(0.8), inExclusiveRange(0, 1));
      expect(liftProgress(0.97), 0);
      expect(liftProgress(1.5), 1, reason: 'the second time round is the same as the first');
    });
  });

  group('plans', () {
    test('a plan exercise reads its exercise, unit and sets', () {
      final p = PlanExercise.fromJson(planJson(unit: 'lb'));
      expect(p.exercise.motion, 'row');
      expect(p.exercise.bodyPart, 'back');
      expect(p.unit, 'lb');
      expect(p.sets.map((s) => s.reps), [10, 10, 10]);
    });

    test('the summary of the sets fits on one line', () {
      String summary(List<List<num>> sets, [String unit = 'kg']) =>
          setsSummary(PlanExercise.fromJson(planJson(unit: unit, sets: sets)));
      expect(
        summary([
          [40, 10],
          [40, 10],
          [40, 10],
        ]),
        '3 sets · 40 kg × 10',
      );
      expect(
        summary([
          [95, 12],
          [115, 10],
          [135, 6],
        ], 'lb'),
        '3 sets · 95–135 lbs × 6–12',
      );
      expect(
        summary([
          [0, 15],
          [0, 12],
        ]),
        '2 sets × 12–15 reps',
      );
      expect(
        summary([
          [0, 10],
        ]),
        '1 set × 10 reps',
      );
    });

    test('search matches every word in the name, equipment or muscles', () {
      final row = PlanExercise.fromJson(planJson()).exercise; // Barbell Row, barbell, lats...
      expect(matchesSearch(row, ''), isTrue);
      expect(matchesSearch(row, 'row'), isTrue);
      expect(matchesSearch(row, 'BARBELL lats'), isTrue);
      expect(matchesSearch(row, 'rhomb'), isTrue);
      expect(matchesSearch(row, 'dumbbell row'), isFalse);
    });

    test('weights change unit to the nearest half', () {
      expect(convertWeight(40, to: 'lb'), 88);
      expect(convertWeight(100, to: 'lb'), 220.5);
      expect(convertWeight(135, to: 'kg'), 61);
      expect(convertWeight(20, to: 'kg'), 9);
    });
  });

  group('sets screen', () {
    late _FakeApi api;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      api = _FakeApi(SessionStore());
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: Center(
                child: TextButton(onPressed: () => context.push('/p1'), child: const Text('Open')),
              ),
            ),
            routes: [
              GoRoute(
                path: 'p1',
                builder: (context, state) => const PlanExerciseScreen(part: 'back', id: 'p1'),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          retry: (retryCount, error) => null,
          overrides: [apiProvider.overrideWithValue(api)],
          child: MaterialApp.router(
            routerConfig: router,
            // A still figure instead of the loop, so the test can wait for everything to settle.
            builder: (context, child) =>
                MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('shows the clip and the sets, switches to lbs, adds sets up to ten and saves', (tester) async {
      await open(tester);
      expect(find.text('Barbell Row'), findsOneWidget);
      expect(find.byType(ExerciseAnimation), findsOneWidget);
      expect(find.text('Rhomboids'), findsOneWidget);
      expect(find.widgetWithText(TextField, '40'), findsNWidgets(3));
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);

      // lbs: the same weight in the other unit.
      await tester.tap(find.text('lbs'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '88'), findsNWidgets(3));

      // Up to ten sets, then the button stops.
      for (var i = 0; i < 7; i++) {
        await tapVisible(tester, find.text('Add set'));
      }
      expect(find.text('10 of 10 sets'), findsOneWidget);
      final addSet = find.ancestor(
        of: find.text('Add set'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(tester.widget<ButtonStyleButton>(addSet).onPressed, isNull);

      await tapVisible(tester, find.widgetWithText(FilledButton, 'Save'));
      final sent = api.puts['/plans/back/exercises/p1']! as Map<String, dynamic>;
      expect(sent['unit'], 'lb');
      expect((sent['sets'] as List).length, 10);
      expect((sent['sets'] as List).first, {'weight': 88.0, 'reps': 10});
    });

    testWidgets('no set may be heavier than 250 kg, or 551 lbs', (tester) async {
      await open(tester);
      final weight = find.widgetWithText(TextField, '40').first;
      await tester.enterText(weight, '251');
      await tester.pump();
      expect(find.text('0 to 250'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, '251'), '250');
      await tester.pump();
      expect(find.text('0 to 250'), findsNothing);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNotNull);

      // 250 kg is 551 lbs, still allowed; one pound more is not.
      await tester.tap(find.text('lbs'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '551'), findsOneWidget);
      expect(find.text('0 to 551'), findsNothing);
      await tester.enterText(find.widgetWithText(TextField, '551'), '552');
      await tester.pump();
      expect(find.text('0 to 551'), findsOneWidget);
    });

    testWidgets('the cross on a set asks first, and only Remove takes it off', (tester) async {
      await open(tester);
      expect(find.widgetWithText(TextField, '40'), findsNWidgets(3));

      await tapVisible(tester, find.byTooltip('Remove set 2'));
      expect(find.text('Remove set 2?'), findsOneWidget);
      expect(find.text('Set 2 (40 kg × 10) will be removed from this exercise.'), findsOneWidget);
      await tapVisible(tester, find.text('Cancel'));
      expect(find.widgetWithText(TextField, '40'), findsNWidgets(3), reason: 'a stray tap must not remove the set');

      await tapVisible(tester, find.byTooltip('Remove set 2'));
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Remove'));
      expect(find.widgetWithText(TextField, '40'), findsNWidgets(2));
      expect(find.text('2 of 10 sets'), findsOneWidget);
    });

    testWidgets('a set without reps cannot be saved', (tester) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextField, '10').first, '');
      await tester.pump();
      expect(find.text('1 to 1000'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
    });
  });
}

class _FakeApi extends ApiClient {
  _FakeApi(super.sessions);

  final puts = <String, Object?>{};

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async => switch (path) {
    '/plans/back' => {
      'body_part': 'back',
      'exercises': [planJson()],
    },
    _ => throw StateError('No fake answer for $path'),
  };

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    puts[path] = body;
    return planJson();
  }
}
