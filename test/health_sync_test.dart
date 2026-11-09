import 'package:fitness_mobile/core/api.dart';
import 'package:fitness_mobile/core/format.dart';
import 'package:fitness_mobile/core/session.dart';
import 'package:fitness_mobile/services/health/health_sync.dart';
import 'package:fitness_mobile/services/health/health_types.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeHealth implements HealthSource {
  FakeHealth({this.allowed = true, this.available = true});

  final bool allowed;
  @override
  final bool available;

  @override
  String get displayName => 'Fake Health';
  @override
  String get sourceId => 'apple_health';
  @override
  Future<bool> requestAccess() async => allowed;
  @override
  Future<List<DayCount>> readDays(int days) async => [DayCount('2026-11-07', 4321)];
}

class FakeApi extends ApiClient {
  FakeApi(super.sessions);

  final posts = <String, Object?>{};

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    posts[path] = body;
    return null;
  }
}

Session sessionFor(String id) => Session(
  access: 'a',
  refresh: 'r',
  user: User(id: id, name: id, email: '$id@example.test'),
);

void main() {
  group('history', historyTests);

  late SessionStore sessions;
  late FakeApi api;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    sessions = SessionStore();
    await sessions.save(sessionFor('asha'));
    api = FakeApi(sessions);
  });

  test('connecting asks permission, remembers it and sends the steps', () async {
    final sync = HealthSync(api, sessions, FakeHealth());
    expect(await sync.isConnected(), isFalse);

    expect(await sync.connect(), isTrue);

    expect(await sync.isConnected(), isTrue);
    expect(api.posts['/steps/sync'], {
      'source': 'apple_health',
      'days': [
        {'date': '2026-11-07', 'steps': 4321},
      ],
    });
  });

  test('syncing again sends only the days whose count changed', () async {
    final phone = _ChangingHealth();
    final sync = HealthSync(api, sessions, phone);
    expect(await sync.sync(), 2);
    api.posts.clear();

    expect(await sync.sync(), 0, reason: 'nothing moved');
    expect(api.posts, isEmpty);

    phone.today = 5100;
    expect(await sync.sync(days: 1), 1);
    expect(api.posts['/steps/sync'], {
      'source': 'apple_health',
      'days': [
        {'date': '2026-11-08', 'steps': 5100},
      ],
    });
  });

  test('another person signing in gets their counts sent, not skipped as already sent', () async {
    final sync = HealthSync(api, sessions, _ChangingHealth());
    await sync.sync();
    api.posts.clear();
    await sessions.save(sessionFor('ben'));
    expect(await sync.sync(), 2);
  });

  test('a refused permission changes nothing and sends nothing', () async {
    final sync = HealthSync(api, sessions, FakeHealth(allowed: false));
    expect(await sync.connect(), isFalse);
    expect(await sync.isConnected(), isFalse);
    expect(api.posts, isEmpty);
  });

  test('someone else signing in on the phone does not get its steps', () async {
    final sync = HealthSync(api, sessions, FakeHealth());
    await sync.connect();

    await sessions.save(sessionFor('ben'));

    expect(await sync.isConnected(), isFalse);
  });

  test('disconnecting stops the syncing', () async {
    final sync = HealthSync(api, sessions, FakeHealth());
    await sync.connect();
    await sync.disconnect();
    expect(await sync.isConnected(), isFalse);
  });

  test('a browser has nothing to connect to', () async {
    final sync = HealthSync(api, sessions, FakeHealth(available: false));
    expect(await sync.isConnected(), isFalse);
  });
}

/// Yesterday's count, then today's, which can be moved to act like a walk.
class _ChangingHealth implements HealthSource {
  var today = 5000;

  @override
  bool get available => true;
  @override
  String get displayName => 'Fake Health';
  @override
  String get sourceId => 'apple_health';
  @override
  Future<bool> requestAccess() async => true;
  @override
  Future<List<DayCount>> readDays(int days) async => [
    if (days > 1) const DayCount('2026-11-07', 8000),
    DayCount('2026-11-08', today),
  ];
}

/// A phone that keeps three months of steps in two apps, and can give older ones once allowed.
class HistoryHealth extends FakeHealth implements StepHistory {
  HistoryHealth({this.historyOn = true});

  bool historyOn;
  final asked = <(DateTime, DateTime)>[];

  @override
  Future<bool> historyNeedsPermission() async => true;
  @override
  Future<bool> historyAllowed() async => historyOn;
  @override
  Future<bool> requestHistory() async => historyOn = true;

  @override
  Future<Map<String, List<DayCount>>> readHistory(DateTime from, DateTime to) async {
    asked.add((from, to));
    // Steps only exist in the last 90 days.
    final oldest = DateTime.now().subtract(const Duration(days: 90));
    if (to.isBefore(oldest)) return {};
    return {
      'samsung': [DayCount(dayKey(to.subtract(const Duration(days: 1))), 5000)],
      'health_connect': [DayCount(dayKey(to.subtract(const Duration(days: 2))), 3000)],
    };
  }
}

class CountingApi extends FakeApi {
  CountingApi(super.sessions);

  final syncs = <Map<String, dynamic>>[];

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    if (path == '/steps/sync') syncs.add(body as Map<String, dynamic>);
    return super.post(path, body: body);
  }
}

void historyTests() {
  late SessionStore sessions;
  late CountingApi api;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    sessions = SessionStore();
    await sessions.save(sessionFor('asha'));
    api = CountingApi(sessions);
  });

  test('earlier months of every app are saved to the account, each under its own source', () async {
    final phone = HistoryHealth();
    final sync = HealthSync(api, sessions, phone);
    await sync.connect();
    api.syncs.clear();

    final sent = await sync.backfill();

    expect(sent, greaterThan(0));
    expect(api.syncs.map((s) => s['source']).toSet(), {'samsung', 'health_connect'});
    for (final s in api.syncs) {
      expect((s['days'] as List).length, lessThanOrEqualTo(60), reason: 'the backend takes 60 days per request');
    }
    expect(phone.asked.length, lessThan(36), reason: 'stops once several months in a row are empty');
    expect(phone.asked.first.$1.isBefore(phone.asked.first.$2), isTrue);
  });

  test('it is done once: opening the app again does not read the past again', () async {
    final phone = HistoryHealth();
    final sync = HealthSync(api, sessions, phone);
    await sync.connect();
    await sync.backfill();
    final reads = phone.asked.length;

    expect(await sync.backfill(), 0);
    expect(phone.asked.length, reads);
  });

  test('done without the permission for older steps: it runs again once that is given', () async {
    final phone = HistoryHealth(historyOn: false);
    final sync = HealthSync(api, sessions, phone);
    await sync.connect();
    await sync.backfill();
    final reads = phone.asked.length;
    expect(await sync.backfill(), 0, reason: 'nothing new can be read yet');
    expect(phone.asked.length, reads);

    await phone.requestHistory();
    expect(await sync.backfill(), greaterThan(0));
    expect(phone.asked.length, greaterThan(reads));
  });

  test('nothing is read for someone who has not connected, or on a phone without history', () async {
    final phone = HistoryHealth();
    expect(await HealthSync(api, sessions, phone).backfill(), 0, reason: 'not connected');
    expect(phone.asked, isEmpty);

    final plain = HealthSync(api, sessions, FakeHealth());
    await plain.connect();
    expect(await plain.backfill(), 0);
  });

  test('another person signing in gets their own backfill', () async {
    final phone = HistoryHealth();
    final sync = HealthSync(api, sessions, phone);
    await sync.connect();
    await sync.backfill();

    await sessions.save(sessionFor('ravi'));
    FlutterSecureStorage.setMockInitialValues({'fitness.step_backfill': '{"user":"asha","with_history":true}'});
    expect(await sync.backfill(), 0, reason: 'Ravi has not connected on this phone');
  });
}
