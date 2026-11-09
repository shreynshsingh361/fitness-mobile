import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/format.dart';

/// The phone's step sensor only knows one number: the steps since the phone last
/// started. A day's steps are the difference between two readings, so this keeps the last
/// reading and a running total for each day.
///
/// Steps are counted from the first reading on. The sensor cannot tell how many were
/// walked before that. Steps walked while Hxvy was closed are added to the day Hxvy next
/// reads the sensor.
class SensorTally {
  SensorTally([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'fitness.step_sensor';
  static const _keepDays = 30;

  final FlutterSecureStorage _storage;
  bool _loaded = false;
  String? _user;
  int? _last; // the sensor's reading last time
  final _days = <String, int>{};

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _user = json['user'] as String?;
      _last = json['last'] as int?;
      for (final e in (json['days'] as Map<String, dynamic>).entries) {
        _days[e.key] = e.value as int;
      }
    } catch (_) {
      // Unreadable: start counting again from now.
      _user = null;
      _last = null;
      _days.clear();
    }
  }

  /// Takes one sensor reading ([count] = steps since the phone started) and returns the
  /// total for every day it knows, by date.
  Future<Map<String, int>> record({required String userId, required int count, required DateTime now}) async {
    await _load();
    if (_user != userId) {
      // Another person signed in on this phone: their totals are not this person's.
      _user = userId;
      _last = null;
      _days.clear();
    }
    final last = _last;
    // The sensor starts again from 0 when the phone restarts, so a lower number than last
    // time means everything it now says was walked after the restart.
    final delta = last == null ? 0 : (count >= last ? count - last : count);
    final today = dayKey(now);
    if (delta > 0 || last != count) {
      _days[today] = (_days[today] ?? 0) + delta;
      _last = count;
      _forget(now);
      await _save();
    }
    return Map.of(_days);
  }

  void _forget(DateTime now) {
    final oldest = dayKey(DateTime(now.year, now.month, now.day - _keepDays));
    _days.removeWhere((date, _) => date.compareTo(oldest) < 0);
  }

  Future<void> _save() async {
    try {
      await _storage.write(key: _key, value: jsonEncode({'user': _user, 'last': _last, 'days': _days}));
    } catch (_) {
      // Could not save: the totals still work until the app is closed.
    }
  }

  /// Forget everything (the person turned counting off).
  Future<void> clear() async {
    _loaded = true;
    _user = null;
    _last = null;
    _days.clear();
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}
