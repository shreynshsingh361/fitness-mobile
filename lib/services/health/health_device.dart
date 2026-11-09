import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/format.dart';
import 'health_types.dart';
import 'step_sensor.dart';
import 'step_sources.dart';

const _types = [HealthDataType.STEPS];
const _access = [HealthDataAccess.READ]; // this app only ever reads

/// The most the backend accepts for one day. One odd reading must not get the whole sync
/// rejected, so anything above it is capped.
const _maxStepsPerDay = 100000;

/// Apple Health on an iPhone; on Android, every app that holds steps.
///
/// Phones differ: one has Samsung Health, another Google Fit, another a watch app, and
/// Health Connect is where those apps put their steps (one permission covers them all).
/// So on Android the steps are read per app, the phone's own step sensor is counted as one
/// more, and the one with the most steps over the last week is used. That choice is
/// remembered, so the count does not jump between apps.
class _DeviceHealth implements HealthSource, StepSensorAccess, StepHistory {
  _DeviceHealth(this._userId);

  final String? Function() _userId;
  final _health = Health();
  final _tally = SensorTally();
  final _choice = SourceChoice();
  bool _configured = false;

  // The sensor, listened to once and kept: its latest reading is always ready to use.
  StreamSubscription<StepCount>? _sensor;
  int? _sensorCount;

  String? _chosen; // the source in use: an app's package name or phoneSensorId
  String? _chosenFor; // for whom it was chosen
  String _lastSource = Platform.isIOS ? 'apple_health' : 'health_connect';

  @override
  final ValueNotifier<String?> activeSource = ValueNotifier<String?>(null);

  @override
  bool get available => Platform.isIOS || Platform.isAndroid;

  @override
  String get displayName => Platform.isIOS ? 'Apple Health' : 'Health Connect';

  /// Where the steps just read came from (the backend keeps the highest count of any source).
  @override
  String get sourceId => _lastSource;

  @override
  Future<bool> sensorAllowed() async => Platform.isAndroid && await Permission.activityRecognition.isGranted;

  @override
  Future<bool> requestSensor() async =>
      Platform.isAndroid && (await Permission.activityRecognition.request()).isGranted;

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<bool> requestAccess() async {
    await _configure();

    // The phone's own sensor first: it needs nothing installed.
    final sensor = Platform.isAndroid && await requestSensor();

    // Older Android phones need the Health Connect app installed first.
    if (!await _health.isHealthConnectAvailable()) {
      if (!sensor) await _health.installHealthConnect();
      return sensor;
    }

    // Apple never tells an app whether it may read: it answers null here, and later true
    // even if the person said no (those reads then simply find no steps). Android answers
    // properly. Asking again when access is already granted can hang, so ask only if needed.
    // On Android this one permission lets Hxvy see the steps of every app in Health Connect.
    if (await _health.hasPermissions(_types, permissions: _access) == true) return true;
    final health = await _health.requestAuthorization(_types, permissions: _access);
    return health || sensor;
  }

  /// The sensor's latest reading, or null without permission or without a step sensor.
  Future<int?> _sensorReading() async {
    if (!Platform.isAndroid || !await sensorAllowed()) return null;
    _sensor ??= Pedometer.stepCountStream.listen(
      (e) => _sensorCount = e.steps,
      onError: (_) {}, // no step sensor on this phone: the apps alone then
      cancelOnError: false,
    );
    // The first reading arrives a moment after listening starts.
    for (var wait = 0; _sensorCount == null && wait < 20; wait++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return _sensorCount;
  }

  @override
  Future<List<DayCount>> readDays(int days) async {
    await _configure();
    return Platform.isAndroid ? _readAndroid(days) : _readApple(days);
  }

  // ---- Android ----

  Future<List<DayCount>> _readAndroid(int days) async {
    final user = _userId();
    if (user == null) return const [];
    if (_chosenFor != user) {
      _chosenFor = user;
      _chosen = await _choice.read(user);
      activeSource.value = _chosen == null ? null : sourceName(_chosen!);
    }

    final now = DateTime.now();
    // Choosing needs the last week of every app. After that only the chosen app is read, and
    // normally only today: that is what runs every second.
    final choosing = _chosen == null || days >= compareDays;
    final span = choosing ? (days < compareDays ? compareDays : days) : days;

    final perApp = _chosen == phoneSensorId ? <String, Map<String, int>>{} : await _readApps(span, now);
    final sensorDays = await _readSensor(user, now);
    final perSource = {...perApp, if (sensorDays.isNotEmpty) phoneSensorId: sensorDays};

    if (choosing) {
      final from = dayKey(DateTime(now.year, now.month, now.day - (compareDays - 1)));
      final totals = {
        for (final e in perSource.entries)
          e.key: e.value.entries.where((d) => d.key.compareTo(from) >= 0).fold(0, (sum, d) => sum + d.value),
      };
      // The sensor's total only exists when the apps were not read (the sensor is the chosen one).
      final picked = pickSource(totals, current: _chosen);
      if (picked != _chosen) {
        _chosen = picked;
        if (picked != null) await _choice.write(user, picked);
        activeSource.value = picked == null ? null : sourceName(picked);
      }
    }

    final source = _chosen;
    if (source == null) return const [];
    _lastSource = backendSource(source);
    final counts = perSource[source] ?? const {};
    final oldest = dayKey(DateTime(now.year, now.month, now.day - (span - 1)));
    return [
      for (final e in counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        if (e.value > 0 && e.key.compareTo(oldest) >= 0) DayCount(e.key, min(e.value, _maxStepsPerDay)),
    ];
  }

  /// Each app's steps for the last [days] days, by app and date.
  Future<Map<String, Map<String, int>>> _readApps(int days, DateTime now) =>
      _readAppsBetween(DateTime(now.year, now.month, now.day - (days - 1)), now);

  /// Each app's steps from [start] to [end], by app and date. Steps typed in by hand are
  /// left out: Hxvy only counts steps a phone or watch measured.
  Future<Map<String, Map<String, int>>> _readAppsBetween(DateTime start, DateTime end) async {
    if (!await _health.isHealthConnectAvailable()) return {};
    final List<HealthDataPoint> points;
    try {
      points = await _health.getHealthDataFromTypes(
        types: _types,
        startTime: start,
        endTime: end,
        recordingMethodsToFilter: [RecordingMethod.manual],
      );
    } catch (_) {
      return {}; // not allowed yet, or Health Connect is busy: the next read tries again
    }
    final apps = <String, Map<String, int>>{};
    for (final p in points) {
      final value = p.value;
      if (value is! NumericHealthValue) continue;
      // Android puts the app's package name in the source name; the id can be empty.
      final app = p.sourceId.isNotEmpty ? p.sourceId : p.sourceName;
      final byDate = apps.putIfAbsent(app.isEmpty ? 'unknown' : app, () => {});
      final date = dayKey(p.dateFrom);
      byDate[date] = (byDate[date] ?? 0) + value.numericValue.toInt();
    }
    return apps;
  }

  Future<Map<String, int>> _readSensor(String user, DateTime now) async {
    final reading = await _sensorReading();
    if (reading == null) return {};
    return _tally.record(userId: user, count: reading, now: now);
  }

  // ---- history ----

  @override
  Future<bool> historyNeedsPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _health.isHealthDataHistoryAvailable();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> historyAllowed() async {
    if (!await historyNeedsPermission()) return true;
    try {
      return await _health.isHealthDataHistoryAuthorized();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestHistory() async {
    if (!await historyNeedsPermission()) return true;
    try {
      return await _health.requestHealthDataHistoryAuthorization();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, List<DayCount>>> readHistory(DateTime from, DateTime to) async {
    await _configure();
    if (Platform.isIOS) {
      final days = <DayCount>[];
      for (
        var day = DateTime(from.year, from.month, from.day);
        !day.isAfter(to);
        day = DateTime(day.year, day.month, day.day + 1)
      ) {
        final next = DateTime(day.year, day.month, day.day + 1);
        final steps = await _health.getTotalStepsInInterval(
          day,
          next.isAfter(DateTime.now()) ? DateTime.now() : next,
          includeManualEntry: false,
        );
        if (steps != null && steps > 0) days.add(DayCount(dayKey(day), min(steps, _maxStepsPerDay)));
      }
      return {if (days.isNotEmpty) 'apple_health': days};
    }

    // Apps that share a backend label (all the plain Health Connect ones) are merged with the
    // higher count per day, never added: two apps may have counted the same walk.
    final byLabel = <String, Map<String, int>>{};
    final apps = await _readAppsBetween(from, to);
    for (final app in apps.entries) {
      final merged = byLabel.putIfAbsent(backendSource(app.key), () => {});
      for (final day in app.value.entries) {
        if (day.value > (merged[day.key] ?? 0)) merged[day.key] = day.value;
      }
    }
    return {
      for (final e in byLabel.entries)
        e.key: [
          for (final d in (e.value.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
            if (d.value > 0) DayCount(d.key, min(d.value, _maxStepsPerDay)),
        ],
    };
  }

  // ---- Apple Health ----

  Future<List<DayCount>> _readApple(int days) async {
    final now = DateTime.now();
    final counts = <DayCount>[];
    for (var back = days - 1; back >= 0; back--) {
      // Building dates from the calendar handles month ends and daylight saving. Adding
      // 24-hour durations would drift by an hour on the days the clocks change.
      final start = DateTime(now.year, now.month, now.day - back);
      final end = back == 0 ? now : DateTime(now.year, now.month, now.day - back + 1);

      // This total, unlike adding up the raw records, does not count a walk twice when
      // both a phone and a watch recorded it.
      final steps = await _health.getTotalStepsInInterval(start, end, includeManualEntry: false);
      if (steps != null && steps > 0) {
        counts.add(DayCount(dayKey(start), min(steps, _maxStepsPerDay)));
      }
    }
    return counts;
  }
}

HealthSource createHealthSource(String? Function() userId) => _DeviceHealth(userId);
