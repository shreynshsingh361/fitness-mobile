import 'package:fitness_mobile/app/app.dart';
import 'package:fitness_mobile/core/api.dart';
import 'package:fitness_mobile/core/format.dart';
import 'package:fitness_mobile/core/session.dart';
import 'package:fitness_mobile/core/widgets.dart';
import 'package:fitness_mobile/services/health/health_sync.dart';
import 'package:fitness_mobile/services/health/health_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// Answers the Steps tab like the backend: [steps] per day, a goal of 10,000.
class _FakeApi extends ApiClient {
  _FakeApi(super.sessions);

  var steps = <String, int>{};
  final dayAsked = <String>[];
  final ranges = <String>[];
  final puts = <String, Object?>{};
  final syncs = <Object?>[];
  var settings = <String, dynamic>{'daily_goal': 10000, 'country': 'IN'};

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    puts[path] = body;
    settings = Map<String, dynamic>.from(body! as Map);
    return settings;
  }

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    if (path == '/steps/sync') syncs.add(body);
    return null;
  }

  Map<String, dynamic> _day(String date) {
    final n = steps[date] ?? 0;
    return {
      'date': date,
      'steps': n,
      'goal': 10000,
      'goal_met': n >= 10000,
      'distance_km': 1.5,
      'calories': 60,
      'current_streak': 0,
      'sources': <dynamic>[],
    };
  }

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    switch (path) {
      case '/plans':
        return {'items': <dynamic>[]};
      case '/nudges':
        return {'unread': 0, 'items': <dynamic>[]};
      case '/steps/today':
        dayAsked.add(query!['date'] as String);
        return _day(query['date'] as String);
      case '/steps/history':
        final to = DateTime.parse(query!['to'] as String);
        final from = query['from'] == null
            ? to.subtract(const Duration(days: 6))
            : DateTime.parse(query['from'] as String);
        if (query['from'] != null) ranges.add('${query['from']}..${query['to']}');
        final days = [
          for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1)))
            {'date': dayKey(d), 'steps': steps[dayKey(d)] ?? 0, 'goal_met': (steps[dayKey(d)] ?? 0) >= 10000},
        ];
        return {'goal': 10000, 'total_steps': 0, 'average_steps': 0, 'days': days};
      case '/steps/settings':
        return settings;
      case '/steps/stats':
        return {
          'longest_streak': 4,
          'best_day': {'steps': 15000, 'date': '2026-11-02'},
          'best_week': {'steps': 70000, 'from': '2026-10-26'},
          'lifetime_steps': 250000,
          'lifetime_distance_km': 190.5,
          'this_week': {'steps': 30000, 'days_goal_met': 2},
          'achievements': [
            {'id': 'a', 'title': 'First 10k', 'description': 'Walk 10,000', 'period': 'daily', 'earned': true},
          ],
          'country_rank': {'country': 'IN', 'rank': 3, 'total_users': 40, 'top_100': true, 'from': '', 'to': ''},
        };
    }
    throw StateError('No fake answer for $path');
  }
}

void main() {
  late SessionStore sessions;
  late _FakeApi api;
  final now = DateTime.now();
  final today = todayKey();
  String key(int day) => dayKey(DateTime(now.year, now.month, day));
  final other = now.day == 1 ? 2 : 1; // another day of this month that can be picked

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    sessions = SessionStore();
    api = _FakeApi(sessions);
  });

  Future<void> toTheBottom(WidgetTester tester) async {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
    await tester.pumpAndSettle();
  }

  Future<void> openSteps(WidgetTester tester, {HealthSync? health}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [
          sessionStoreProvider.overrideWithValue(sessions),
          apiProvider.overrideWithValue(api),
          if (health != null) healthSyncProvider.overrideWithValue(health),
        ],
        child: const HxvyApp(),
      ),
    );
    await sessions.save(
      const Session(
        access: 'a',
        refresh: 'r',
        user: User(id: 'u1', name: 'Asha', email: 'asha@example.test'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'Steps'));
    await tester.pumpAndSettle();
  }

  testWidgets('today\'s steps sit in a ring that fills toward the goal', (tester) async {
    api.steps = {today: 7432};
    await openSteps(tester);
    final ring = tester.widget<ProgressRing>(find.byType(ProgressRing));
    expect(ring.fraction, closeTo(0.7432, 0.0001));
    expect(find.descendant(of: find.byType(ProgressRing), matching: find.text('7,432')), findsOneWidget);
    expect(find.text('of 10,000'), findsOneWidget);
    expect(find.text('2,568 steps to go'), findsOneWidget);
  });

  testWidgets('the ring is full once the goal is reached', (tester) async {
    api.steps = {today: 12000};
    await openSteps(tester);
    expect(tester.widget<ProgressRing>(find.byType(ProgressRing)).fraction, 1);
    expect(find.text('Goal reached'), findsOneWidget);
  });

  testWidgets('the calendar shows each day\'s steps, and picking one shows that day', (tester) async {
    api.steps = {today: 4200, key(other): 11500};
    await openSteps(tester);

    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.text(DateFormat('MMMM y').format(now)), findsOneWidget);
    final first = DateTime(now.year, now.month);
    final last = DateTime(now.year, now.month + 1, 0);
    expect(api.ranges, ['${dayKey(first)}..${dayKey(last)}'], reason: 'the whole month in one request');
    expect(find.text('4,200'), findsWidgets);
    final met = tester.widget<Text>(find.text('11,500'));
    expect(met.style?.fontWeight, FontWeight.w700, reason: 'a day at goal stands out');

    await tester.tap(find.text('11,500'));
    await tester.pumpAndSettle();
    expect(api.dayAsked.last, key(other));
    expect(find.text(shortDate(key(other)).toUpperCase()), findsOneWidget, reason: 'the card is titled with the day');
    expect(tester.widget<ProgressRing>(find.byType(ProgressRing)).fraction, 1);

    await tester.tap(find.text('Back to today'));
    await tester.pumpAndSettle();
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Back to today'), findsNothing);
  });

  testWidgets('no Sync now button: steps sync by themselves, every second while the app is open', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'fitness.health_connected': 'u1'});
    final phone = _CountingHealth();
    await openSteps(tester, health: HealthSync(api, sessions, phone));
    await toTheBottom(tester); // the Automatic counting card is the last one on the page
    expect(phone.reads, greaterThanOrEqualTo(1));
    expect(api.syncs, hasLength(1), reason: 'the first read is sent');
    expect(find.text('Sync now'), findsNothing);
    expect(find.textContaining('sync from Fake Health by themselves'), findsOneWidget);

    final before = phone.reads;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(phone.reads, before + 1, reason: 'read again 1 second later');
    expect(api.syncs, hasLength(1), reason: 'the same count is not sent again');

    phone.steps = 1300; // a few steps walked
    final asked = api.dayAsked.length;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.syncs, hasLength(2), reason: 'a changed count is sent');
    expect(api.dayAsked.length, greaterThan(asked), reason: 'and the tab reloads to show it');
  });

  testWidgets('connected but the health app holds no steps: says so instead of a silent 0', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'fitness.health_connected': 'u1'});
    final phone = _CountingHealth()..empty = true;
    await openSteps(tester, health: HealthSync(api, sessions, phone));
    await toTheBottom(tester); // the Automatic counting card is the last one on the page
    expect(find.textContaining('has no steps from the last 2 weeks'), findsOneWidget);

    // The one-day reads every second say nothing about the two weeks, so the note stays.
    phone.empty = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('has no steps from the last 2 weeks'), findsOneWidget);
  });

  testWidgets('connected but the phone sensor is not allowed yet: an Allow button asks for it', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'fitness.health_connected': 'u1'});
    final phone = _SensorHealth();
    await openSteps(tester, health: HealthSync(api, sessions, phone));
    await toTheBottom(tester); // the Automatic counting card is the last one on the page
    expect(find.textContaining('Physical activity'), findsOneWidget);
    expect(phone.asked, 0, reason: 'nothing is asked until the person taps Allow');
    // The note about an empty Health Connect waits until the sensor may be used.
    expect(find.textContaining('has no steps from the last 2 weeks'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
    await tester.pumpAndSettle();
    expect(phone.asked, 1);
    expect(find.textContaining('Physical activity'), findsNothing);
    expect(find.text('Counting steps with your phone.'), findsOneWidget);
  });

  testWidgets('the card says which app the steps come from, with no extra buttons', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'fitness.health_connected': 'u1'});
    final phone = _SensorHealth()..allowed = true;
    await openSteps(tester, health: HealthSync(api, sessions, phone));
    await toTheBottom(tester); // the Automatic counting card is the last one on the page
    expect(find.textContaining('Counting with'), findsNothing, reason: 'no app chosen yet');

    phone.activeSource.value = 'Samsung Health';
    await tester.pump();
    expect(find.text('Counting with Samsung Health.'), findsOneWidget);
    expect(find.text('Check again'), findsNothing);
  });

  testWidgets('the Steps card never lists the apps or says "highest count"', (tester) async {
    await openSteps(tester);
    expect(find.textContaining('From Health Connect'), findsNothing);
    expect(find.textContaining('highest count'), findsNothing);
    expect(find.textContaining('count the same walk'), findsNothing);
  });

  testWidgets('Automatic counting is the last card on the Steps tab', (tester) async {
    await openSteps(tester);
    await toTheBottom(tester);
    final goal = tester.getTopLeft(find.text('DAILY GOAL')).dy;
    final counting = tester.getTopLeft(find.text('AUTOMATIC COUNTING')).dy;
    expect(counting, greaterThan(goal), reason: 'set up once, so it sits below everything else');
  });

  testWidgets('Records has only the streak, best day, this week and all time', (tester) async {
    await openSteps(tester);
    await tester.scrollUntilVisible(find.text('All time'), 200, scrollable: find.byType(Scrollable).first);
    for (final line in ['Longest streak', 'Best day', 'This week', 'All time']) {
      expect(find.text(line), findsOneWidget);
    }
    expect(find.text('Best week'), findsNothing);
    expect(find.textContaining('Set your country'), findsNothing);
    expect(find.textContaining('in IN this week'), findsNothing, reason: 'no rank line either');
  });

  testWidgets('the Daily goal card replaces Achievements and saves a new goal', (tester) async {
    await openSteps(tester);
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.scrollUntilVisible(save, 200, scrollable: find.byType(Scrollable).first);
    // On to the very end, so the card is clear of the glass bar floating over the page.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text('ACHIEVEMENTS'), findsNothing);
    expect(find.text('DAILY GOAL'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'the goal is already 10,000');

    await tester.tap(find.widgetWithText(ChoiceChip, '8,000'));
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(api.puts['/steps/settings'], {'daily_goal': 8000, 'country': 'IN'}, reason: 'the country is kept');
    expect(find.text('Daily goal set to 8,000 steps.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '8000'), '500');
    await tester.pump();
    expect(find.text('1,000 to 100,000'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
  });
}

/// The phone's step store, counting how often it is read.
/// Like a real Android phone whose step sensor has not been allowed yet.
class _SensorHealth extends _CountingHealth implements StepSensorAccess {
  var asked = 0;
  var allowed = false;
  @override
  final ValueNotifier<String?> activeSource = ValueNotifier<String?>(null);

  @override
  Future<bool> sensorAllowed() async => allowed;
  @override
  Future<bool> requestSensor() async {
    asked++;
    return allowed = true;
  }
}

class _CountingHealth implements HealthSource {
  var reads = 0;
  var steps = 1234;
  var empty = false;

  @override
  bool get available => true;
  @override
  String get displayName => 'Fake Health';
  @override
  String get sourceId => 'health_connect';
  @override
  Future<bool> requestAccess() async => true;
  @override
  Future<List<DayCount>> readDays(int days) async {
    reads++;
    return empty ? [] : [DayCount(todayKey(), steps)];
  }
}
