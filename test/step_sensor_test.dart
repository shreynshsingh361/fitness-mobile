import 'package:fitness_mobile/services/health/step_sensor.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  final monday = DateTime(2026, 11, 9, 9, 0);

  test('counts from the first reading on: the steps before it are unknown', () async {
    final tally = SensorTally();
    expect(await tally.record(userId: 'u1', count: 5000, now: monday), {'2026-11-09': 0});
    expect(await tally.record(userId: 'u1', count: 5120, now: monday), {'2026-11-09': 120});
    expect(await tally.record(userId: 'u1', count: 5120, now: monday), {
      '2026-11-09': 120,
    }, reason: 'same reading, same total');
    expect(await tally.record(userId: 'u1', count: 5300, now: monday), {'2026-11-09': 300});
  });

  test('each day gets the steps walked while it was that day', () async {
    final tally = SensorTally();
    await tally.record(userId: 'u1', count: 100, now: monday);
    await tally.record(userId: 'u1', count: 400, now: monday);
    final tuesday = monday.add(const Duration(days: 1));
    expect(await tally.record(userId: 'u1', count: 450, now: tuesday), {'2026-11-09': 300, '2026-11-10': 50});
  });

  test('a phone restart sets the sensor back to 0 and nothing is lost or counted twice', () async {
    final tally = SensorTally();
    await tally.record(userId: 'u1', count: 9000, now: monday);
    await tally.record(userId: 'u1', count: 9500, now: monday); // 500
    expect(await tally.record(userId: 'u1', count: 40, now: monday), {
      '2026-11-09': 540,
    }, reason: '40 steps since restart');
  });

  test('the totals survive the app being closed', () async {
    await SensorTally().record(userId: 'u1', count: 100, now: monday);
    await SensorTally().record(userId: 'u1', count: 250, now: monday);
    final reopened = SensorTally(); // a new run of the app reads what was saved
    expect(await reopened.record(userId: 'u1', count: 260, now: monday), {'2026-11-09': 160});
  });

  test('another person signing in on this phone starts from nothing', () async {
    final tally = SensorTally();
    await tally.record(userId: 'u1', count: 100, now: monday);
    await tally.record(userId: 'u1', count: 900, now: monday);
    expect(await tally.record(userId: 'u2', count: 950, now: monday), {'2026-11-09': 0});
    expect(await tally.record(userId: 'u2', count: 1000, now: monday), {'2026-11-09': 50});
  });

  test('old days are forgotten after a month', () async {
    final tally = SensorTally();
    await tally.record(userId: 'u1', count: 100, now: monday);
    await tally.record(userId: 'u1', count: 200, now: monday);
    final later = monday.add(const Duration(days: 40));
    final days = await tally.record(userId: 'u1', count: 230, now: later);
    expect(days.keys, ['2026-12-19'], reason: 'only the new day is left');
  });
}
