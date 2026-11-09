import 'dart:math' as math;

import 'package:fitness_mobile/core/api.dart';
import 'package:fitness_mobile/core/format.dart';
import 'package:fitness_mobile/core/offline_queue.dart';
import 'package:fitness_mobile/core/session.dart';
import 'package:fitness_mobile/core/widgets.dart';
import 'package:fitness_mobile/features/nutrition/meals_screen.dart';
import 'package:fitness_mobile/features/nutrition/nutrition_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers like the backend for one day with one food and some water, and records what
/// gets deleted. Deleted things are gone the next time they are asked for.
class _FakeApi extends ApiClient {
  _FakeApi(super.sessions);

  /// Each delete asked for, in order: its path and its query.
  final deletes = <(String, Map<String, dynamic>?)>[];
  final posts = <(String, Object?)>[];
  var offline = false; // no internet: every call fails to connect
  List<String> get deleted => [for (final (path, _) in deletes) path];
  var waterMl = 750;

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    if (offline) throw const ApiException(0, 'network_error', 'Cannot reach the server.');
    posts.add((path, body));
    if (path == '/water') waterMl += (body as Map)['amount_ml'] as int;
    return null;
  }

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async => switch (path) {
    '/diary' => {
      'date': query?['date'],
      'entries': [
        if (!deleted.contains('/diary/e1'))
          {
            'id': 'e1',
            'meal': 'breakfast',
            'food_name': 'Masala oats',
            'serving': '100 g',
            'servings': 0.4,
            'calories': 150,
            'protein_g': 5,
            'carbs_g': 25,
            'fat_g': 3,
          },
      ],
      'totals': {'calories': 150, 'protein_g': 5, 'carbs_g': 25, 'fat_g': 3},
    },
    '/goals' => {'calories': 2000, 'is_default': true},
    '/water' => {'water_ml': waterMl},
    _ => throw StateError('No fake answer for $path'),
  };

  @override
  Future<dynamic> delete(String path, {Map<String, dynamic>? query}) async {
    if (offline) throw const ApiException(0, 'network_error', 'Cannot reach the server.');
    deletes.add((path, query));
    // Like the server: an amount comes off the day and stops at zero, and no amount resets it.
    if (path == '/water') {
      final amount = query?['amount_ml'] as int?;
      waterMl = amount == null ? 0 : math.max(0, waterMl - amount);
    }
    return null;
  }
}

void main() {
  late SessionStore sessions;
  late _FakeApi api;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    sessions = SessionStore();
    api = _FakeApi(sessions);
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [sessionStoreProvider.overrideWithValue(sessions), apiProvider.overrideWithValue(api)],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  // The Food tab is a lazy list: what is further down is only built once scrolled to.
  Future<void> scrollTo(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);

  Future<void> toTheTop(WidgetTester tester) async {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
    await tester.pumpAndSettle();
  }

  testWidgets('the cross on a food asks first, and only Delete removes it', (tester) async {
    await show(tester, const MealsScreen(date: '2026-11-09'));
    expect(find.text('Masala oats'), findsOneWidget);

    await tap(tester, find.byTooltip('Remove Masala oats'));
    expect(find.text('Delete this food?'), findsOneWidget);
    expect(find.text('Masala oats (40 g) will be removed from breakfast.'), findsOneWidget);
    await tap(tester, find.text('Cancel'));
    expect(api.deleted, isEmpty, reason: 'a stray tap on the cross must not delete the log');
    expect(find.text('Masala oats'), findsOneWidget);

    await tap(tester, find.byTooltip('Remove Masala oats'));
    await tap(tester, find.widgetWithText(FilledButton, 'Delete'));
    expect(api.deleted, ['/diary/e1']);
    expect(find.text('Masala oats'), findsNothing);
  });

  testWidgets('resetting the day\'s water asks first', (tester) async {
    await show(tester, const NutritionScreen());
    final reset = find.widgetWithText(TextButton, 'Reset day');
    await scrollTo(tester, reset);

    await tap(tester, reset);
    expect(find.text('Reset water for this day?'), findsOneWidget);
    await tap(tester, find.text('Cancel'));
    expect(api.deleted, isEmpty);
    expect(find.text('750 ml'), findsOneWidget);

    await tap(tester, reset);
    await tap(tester, find.widgetWithText(FilledButton, 'Reset'));
    expect(api.deleted, ['/water']);
    expect(api.deletes.single.$2, {'date': todayKey()}, reason: 'a reset sends no amount');
    expect(find.text('0 ml'), findsOneWidget);
  });

  testWidgets('−250 ml takes a glass back without asking, and is off once the day is empty', (tester) async {
    api.waterMl = 250;
    await show(tester, const NutritionScreen());
    final minus = find.widgetWithText(OutlinedButton, '−250 ml');
    await scrollTo(tester, minus);

    await tap(tester, minus);
    expect(find.byType(AlertDialog), findsNothing, reason: '+250 ml undoes it, so there is nothing to confirm');
    expect(api.deleted, ['/water']);
    final query = api.deletes.single.$2!;
    expect({...query}..remove('client_op_id'), {'date': todayKey(), 'amount_ml': 250});
    expect(query['client_op_id'], isA<String>(), reason: 'a retry of this tap must not take 250 ml off twice');
    expect(find.text('0 ml'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(minus).onPressed, isNull, reason: 'nothing is left to take back');
    final reset = find.widgetWithText(TextButton, 'Reset day');
    expect(tester.widget<TextButton>(reset).onPressed, isNull);
  });

  testWidgets('+250 ml without internet shows at once, waits on the phone, and is sent when the connection is back', (
    tester,
  ) async {
    api.offline = true;
    await show(tester, const NutritionScreen());
    final plus = find.widgetWithText(OutlinedButton, '+250 ml');
    await scrollTo(tester, plus);

    await tap(tester, plus);
    expect(find.text('1,000 ml'), findsOneWidget, reason: '750 ml + the 250 ml that is waiting, shown right away');
    expect(find.textContaining('No internet. Saved on your phone'), findsOneWidget);
    expect(api.posts, isEmpty);
    await toTheTop(tester);
    expect(find.text('1 change waiting for internet'), findsOneWidget);
    await scrollTo(tester, plus);

    // Tapping again while offline adds a second change, and each has its own id.
    await tap(tester, plus);
    expect(find.text('1,250 ml'), findsOneWidget);
    await toTheTop(tester);
    expect(find.text('2 changes waiting for internet'), findsOneWidget);

    // The connection is back: what waits is sent, and the banner goes.
    api.offline = false;
    final container = ProviderScope.containerOf(tester.element(find.byType(NutritionScreen)));
    expect(await container.read(offlineQueueProvider).flush(), 2);
    container.invalidate(waterProvider(todayKey()));
    await tester.pumpAndSettle();
    expect(api.posts.length, 2);
    final ids = {for (final (_, body) in api.posts) (body as Map)['client_op_id']};
    expect(ids.length, 2, reason: 'two taps, two different ids, so the server counts both');
    expect(find.textContaining('waiting for internet'), findsNothing);
    await scrollTo(tester, plus);
    expect(find.text('1,250 ml'), findsOneWidget, reason: 'the server now has 750 + 250 + 250');
  });

  testWidgets('water has only +250 ml and −250 ml', (tester) async {
    await show(tester, const NutritionScreen());
    final minus = find.widgetWithText(OutlinedButton, '−250 ml');
    await scrollTo(tester, minus);
    expect(find.widgetWithText(OutlinedButton, '+250 ml'), findsOneWidget);
    expect(find.textContaining('500'), findsNothing, reason: 'the +500 ml button is gone');
    expect(find.byType(OutlinedButton), findsNWidgets(2));
  });

  testWidgets('the Food tab shows calories, what was eaten meal by meal, then water', (tester) async {
    await show(tester, const NutritionScreen());
    await scrollTo(tester, find.text('WATER')); // section titles are shown in capitals
    final calories = tester.getTopLeft(find.text('CALORIES')).dy;
    final eaten = tester.getTopLeft(find.text('WHAT YOU ATE')).dy;
    final water = tester.getTopLeft(find.text('WATER')).dy;
    expect(calories, lessThan(eaten));
    expect(eaten, lessThan(water));

    // Every meal in order, with what was eaten in it.
    final names = ['Breakfast', 'Lunch', 'Snacks', 'Dinner'];
    final tops = [for (final n in names) tester.getTopLeft(find.text(n)).dy];
    expect(tops, [...tops]..sort());
    expect(find.text('Masala oats  40 g', findRichText: true), findsOneWidget);
    final inEaten = find.descendant(
      of: find.ancestor(of: find.text('WHAT YOU ATE'), matching: find.byType(SectionCard)).first,
      matching: find.text('150 kcal'),
    );
    expect(inEaten, findsNWidgets(2), reason: 'the food, and breakfast in all');
    expect(find.text('Nothing yet'), findsNWidgets(3));

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000)); // to the very end
    await tester.pumpAndSettle();
    expect(find.text('RECIPES'), findsNothing);
    expect(find.text('WATER'), findsOneWidget, reason: 'water is the last section');
  });
}
