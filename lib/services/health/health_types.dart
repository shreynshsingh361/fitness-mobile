import 'package:flutter/foundation.dart';

/// One day's step count as read from the phone.
class DayCount {
  const DayCount(this.date, this.steps);

  final String date; // YYYY-MM-DD, local
  final int steps;

  Map<String, dynamic> toJson() => {'date': date, 'steps': steps};
}

/// Reading steps from the phone's health store. Two real versions exist behind this:
/// Apple Health on iPhone and Health Connect on Android. A browser has neither, so
/// there [available] is false and people type their steps in.
abstract class HealthSource {
  /// Can this device read steps at all?
  bool get available;

  /// The name to show people, such as "Apple Health".
  String get displayName;

  /// The source id the backend expects, such as "apple_health".
  String get sourceId;

  /// Asks permission. Only call this when the person turns the feature on, never at launch.
  Future<bool> requestAccess();

  /// Daily totals for the last [days] days, oldest first.
  Future<List<DayCount>> readDays(int days);
}

/// Implemented by the Android source: besides Health Connect it reads the phone's own step
/// sensor, which Android lets an app use only once the person allows "Physical activity".
/// It also compares every app that holds steps and uses the one with the most.
abstract interface class StepSensorAccess {
  Future<bool> sensorAllowed();
  Future<bool> requestSensor();

  /// The name of the app (or sensor) the steps are being read from, once one was chosen.
  ValueListenable<String?> get activeSource;
}

/// Implemented by sources that can hand over the steps of past months, so the whole history
/// can be saved to the account, not only the last two weeks.
abstract interface class StepHistory {
  /// Whether the phone has a separate permission for steps from before the app was allowed
  /// (Android's Health Connect keeps only the last 30 days readable without it).
  Future<bool> historyNeedsPermission();

  /// Whether that permission is given. True where none is needed.
  Future<bool> historyAllowed();

  Future<bool> requestHistory();

  /// The steps of every app for the days from [from] to [to], by the source label the backend
  /// takes ("samsung", "health_connect", ...). Days with no steps are left out.
  Future<Map<String, List<DayCount>>> readHistory(DateTime from, DateTime to);
}
