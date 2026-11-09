import 'package:fitness_mobile/core/api.dart';
import 'package:fitness_mobile/core/format.dart';
import 'package:fitness_mobile/core/palette.dart';
import 'package:fitness_mobile/core/offline_queue.dart';
import 'package:fitness_mobile/core/session.dart';
import 'package:fitness_mobile/features/nutrition/food_widgets.dart';
import 'package:fitness_mobile/features/nutrition/nutrition_screen.dart';
import 'package:fitness_mobile/features/nutrition/scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

const _iceCream = {
  'id': 'f1',
  'name': 'Ice Cream',
  'brand': 'The Kroger Co.',
  'source': 'off',
  'serving': '64g',
  'calories': 209,
  'protein_g': 3.1,
  'carbs_g': 28.1,
  'fat_g': 9.4,
};

class _FakeApi extends ApiClient {
  _FakeApi(super.sessions);

  /// What the barcode lookup answers, by code; a code that is not here is "not found".
  final foods = <String, Object>{'0011110531568': _iceCream};
  final asked = <String>[];
  final diaryDays = <String>[];
  final posted = <Map<String, dynamic>>[];
  final months = <String>[];
  var monthDays = <String, int>{};
  Object? lookupError;
  Object? postError; // thrown by every save while set (no internet, say)

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    if (path.startsWith('/foods/barcode/')) {
      asked.add(path.split('/').last);
      final error = lookupError;
      if (error != null) throw error;
      return foods[path.split('/').last] ??
          (throw const ApiException(404, 'not_found', 'no product with that barcode'));
    }
    switch (path) {
      case '/diary':
        diaryDays.add(query!['date'] as String);
        return {
          'date': query['date'],
          'entries': [],
          'totals': {'calories': 0, 'protein_g': 0, 'carbs_g': 0, 'fat_g': 0},
        };
      case '/goals':
        return {'calories': 2000, 'is_default': true};
      case '/water':
        return {'water_ml': 0};
      case '/diary/month':
        months.add(query!['month'] as String);
        return {
          'month': query['month'],
          'days': [
            for (final e in monthDays.entries) {'date': e.key, 'calories': e.value},
          ],
        };
    }
    throw StateError('No fake answer for $path');
  }

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    if (postError != null) throw postError!;
    posted.add({'path': path, ...(body as Map<String, dynamic>)});
    return {};
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

  group('calorie ring', () {
    Future<void> ring(WidgetTester tester, num eaten) => show(
      tester,
      Scaffold(
        body: Center(child: CalorieRing(eaten: eaten, goal: 2000)),
      ),
    );

    Color? colorOf(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style?.color;

    testWidgets('turns red once the goal is passed, however far over', (tester) async {
      await ring(tester, 2230);
      expect(find.text('230'), findsOneWidget);
      expect(colorOf(tester, '230'), Hxvy.over);
      expect(colorOf(tester, 'kcal over'), Hxvy.over);

      await ring(tester, 5000);
      expect(colorOf(tester, '3,000'), Hxvy.over);
    });

    testWidgets('stays white up to the goal', (tester) async {
      await ring(tester, 1800);
      expect(colorOf(tester, '200'), isNot(Hxvy.over));
      expect(colorOf(tester, 'kcal left'), Hxvy.textMuted);
      await ring(tester, 2000);
      expect(find.text('kcal left'), findsOneWidget, reason: 'exactly on the goal is not over it');
    });
  });

  group('calendar', () {
    final now = DateTime.now();
    final monthKey = DateFormat('yyyy-MM').format(now);
    String key(int day) => dayKey(DateTime(now.year, now.month, day));
    // Some other day of this month than today, which is always allowed.
    final other = now.day == 1 ? 2 : 1;

    testWidgets('shows the calories eaten under each day, red when over the goal', (tester) async {
      api.monthDays = {key(now.day): 1850, key(other): 2300};
      await show(tester, const NutritionScreen());

      await tester.tap(find.text('Today, ${shortDate(todayKey())}'));
      await tester.pumpAndSettle();
      expect(find.text(DateFormat('MMMM y').format(now)), findsOneWidget);
      expect(api.months, [monthKey]);
      expect(find.text('1,850'), findsOneWidget);
      expect(tester.widget<Text>(find.text('1,850')).style?.color, isNot(Hxvy.over), reason: 'under the goal');
      expect(find.text('2,300'), findsOneWidget);
      expect(tester.widget<Text>(find.text('2,300')).style?.color, Hxvy.over, reason: 'over the goal');
    });

    testWidgets('picking a day shows that day', (tester) async {
      api.monthDays = {key(other): 2300};
      await show(tester, const NutritionScreen());
      api.diaryDays.clear();

      await tester.tap(find.text('Today, ${shortDate(todayKey())}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2,300'));
      await tester.pumpAndSettle();

      expect(find.text('Previous month'), findsNothing, reason: 'the calendar closed');
      expect(api.diaryDays, contains(key(other)), reason: 'the tab asked for the day that was picked');
      expect(find.text(shortDate(key(other))), findsOneWidget);
    });

    testWidgets('moves between months, asking for each', (tester) async {
      await show(tester, const NutritionScreen());
      await tester.tap(find.text('Today, ${shortDate(todayKey())}'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      final before = DateTime(now.year, now.month - 1);
      expect(find.text(DateFormat('MMMM y').format(before)), findsOneWidget);
      expect(api.months.last, DateFormat('yyyy-MM').format(before));
    });
  });

  group('barcode scanner', () {
    // Stands in for the camera: one button per "packet" it can read.
    Widget camera(BuildContext context, void Function(String) onCode) => Center(
      child: Wrap(
        spacing: 8,
        children: [
          for (final code in const ['0011110531568', '9999999999999'])
            ElevatedButton(onPressed: () => onCode(code), child: Text('read $code')),
        ],
      ),
    );

    // A page that opens the scanner and reports what it came back with.
    Future<void> open(WidgetTester tester, List<bool?> results) =>
        show(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async => results.add(
                    await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => ScanScreen(date: '2026-11-08', camera: camera),
                      ),
                    ),
                  ),
                  child: const Text('Scan'),
                ),
              ),
            ),
          ),
        ).then((_) async {
          await tester.tap(find.text('Scan'));
          await tester.pumpAndSettle();
        });

    testWidgets('a scanned barcode opens the food, and adding it logs it on the day', (tester) async {
      final results = <bool?>[];
      await open(tester, results);
      expect(find.text('Point the camera at the barcode on the packet'), findsOneWidget);

      await tester.tap(find.text('read 0011110531568'));
      await tester.pumpAndSettle();
      expect(api.asked, ['0011110531568']);
      expect(find.text('Ice Cream'), findsOneWidget);
      expect(find.text('The Kroger Co.'), findsOneWidget);

      await tester.tap(
        find.byWidgetPredicate((w) => w is FilledButton && (w.child as Text).data!.startsWith('Add to ')),
      );
      await tester.pumpAndSettle();
      expect(api.posted, hasLength(1));
      expect(api.posted.single['path'], '/diary');
      expect(api.posted.single['food_id'], 'f1');
      expect(api.posted.single['eaten_on'], '2026-11-08', reason: 'the day the Food tab was on');
      expect(results, [true], reason: 'the scanner closed once the food was added');
    });

    testWidgets('adding a scanned food without internet keeps it on the phone and still closes the scanner', (
      tester,
    ) async {
      api.postError = const ApiException(0, 'network_error', 'Cannot reach the server.');
      final results = <bool?>[];
      await open(tester, results);
      await tester.tap(find.text('read 0011110531568'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate((w) => w is FilledButton && (w.child as Text).data!.startsWith('Add to ')),
      );
      await tester.pumpAndSettle();

      expect(api.posted, isEmpty, reason: 'nothing reached the server');
      expect(results, [true], reason: 'the food is safe on the phone, so the scanner closes');
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      final waiting = container.read(offlineQueueProvider).pending;
      expect(waiting, hasLength(1));
      expect(waiting.single.body?['food_id'], 'f1');
      expect(waiting.single.body?['client_op_id'], waiting.single.id);

      // The connection is back: it is sent with the same id.
      api.postError = null;
      expect(await container.read(offlineQueueProvider).flush(), 1);
      expect(api.posted.single['client_op_id'], waiting.single.id);
    });

    testWidgets('closing the food without adding goes back to scanning', (tester) async {
      final results = <bool?>[];
      await open(tester, results);
      await tester.tap(find.text('read 0011110531568'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(200, 100)); // outside the sheet
      await tester.pumpAndSettle();
      expect(api.posted, isEmpty);
      expect(results, isEmpty, reason: 'still on the scanner');
      expect(find.text('Point the camera at the barcode on the packet'), findsOneWidget);
    });

    testWidgets('an unknown barcode says so, and the next packet can still be scanned', (tester) async {
      final results = <bool?>[];
      await open(tester, results);

      await tester.tap(find.text('read 9999999999999'));
      await tester.pumpAndSettle();
      expect(find.text('No product found for that barcode. Search for it by name instead.'), findsOneWidget);
      expect(api.posted, isEmpty);

      await tester.tap(find.text('read 0011110531568'));
      await tester.pumpAndSettle();
      expect(find.text('Ice Cream'), findsOneWidget);
      expect(find.text('No product found for that barcode. Search for it by name instead.'), findsNothing);
    });

    testWidgets('a product without nutrition and a lost connection each get their own message', (tester) async {
      await open(tester, []);

      api.lookupError = const ApiException(404, 'no_nutrition', 'that product has no nutrition information yet');
      await tester.tap(find.text('read 9999999999999'));
      await tester.pumpAndSettle();
      expect(find.textContaining('has no nutrition information yet'), findsOneWidget);

      api.lookupError = const ApiException(0, 'network', 'Cannot reach the server.');
      await tester.tap(find.text('read 9999999999999'));
      await tester.pumpAndSettle();
      expect(find.text('Cannot reach the server.'), findsOneWidget);
    });
  });

  testWidgets('the Food tab has a small Scan button above Add food', (tester) async {
    await show(tester, const NutritionScreen());
    final scan = tester.getTopLeft(find.byTooltip('Scan barcode')).dy;
    final add = tester.getTopLeft(find.text('Add food')).dy;
    expect(scan, lessThan(add));
  });
}
