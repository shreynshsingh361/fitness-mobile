import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';

class StepsDay {
  StepsDay.fromJson(Map<String, dynamic> j)
    : date = j['date'] as String,
      steps = j['steps'] as int,
      goal = j['goal'] as int,
      goalMet = j['goal_met'] as bool,
      distanceKm = (j['distance_km'] as num).toDouble(),
      calories = j['calories'] as int,
      streak = j['current_streak'] as int;

  final String date;
  final int steps;
  final int goal;
  final bool goalMet;
  final double distanceKm;
  final int calories;
  final int streak;
}

class HistoryDay {
  HistoryDay.fromJson(Map<String, dynamic> j)
    : date = j['date'] as String,
      steps = j['steps'] as int,
      goalMet = j['goal_met'] as bool;

  final String date;
  final int steps;
  final bool goalMet;
}

class StepsHistory {
  StepsHistory.fromJson(Map<String, dynamic> j)
    : goal = j['goal'] as int,
      total = j['total_steps'] as int,
      average = j['average_steps'] as int,
      days = (j['days'] as List).map((d) => HistoryDay.fromJson(d as Map<String, dynamic>)).toList();

  final int goal;
  final int total;
  final int average;
  final List<HistoryDay> days;
}

class Achievement {
  Achievement.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String,
      description = j['description'] as String,
      period = j['period'] as String,
      earned = j['earned'] as bool,
      earnedOn = j['earned_on'] as String?;

  final String id;
  final String title;
  final String description;
  final String period; // daily, weekly or all_time
  final bool earned;
  final String? earnedOn;
}

class CountryRank {
  CountryRank.fromJson(Map<String, dynamic> j)
    : country = j['country'] as String,
      rank = j['rank'] as int,
      totalUsers = j['total_users'] as int,
      top100 = j['top_100'] as bool;

  final String country;
  final int rank;
  final int totalUsers;
  final bool top100;
}

class StepsStats {
  StepsStats.fromJson(Map<String, dynamic> j)
    : longestStreak = j['longest_streak'] as int,
      bestDaySteps = j['best_day']?['steps'] as int?,
      bestDayDate = j['best_day']?['date'] as String?,
      bestWeekSteps = j['best_week']?['steps'] as int?,
      bestWeekFrom = j['best_week']?['from'] as String?,
      lifetimeSteps = j['lifetime_steps'] as int,
      lifetimeKm = (j['lifetime_distance_km'] as num).toDouble(),
      weekSteps = j['this_week']['steps'] as int,
      weekGoalDays = j['this_week']['days_goal_met'] as int,
      achievements = (j['achievements'] as List).map((a) => Achievement.fromJson(a as Map<String, dynamic>)).toList(),
      countryRank = j['country_rank'] == null ? null : CountryRank.fromJson(j['country_rank'] as Map<String, dynamic>);

  final int longestStreak;
  final int? bestDaySteps;
  final String? bestDayDate;
  final int? bestWeekSteps;
  final String? bestWeekFrom;
  final int lifetimeSteps;
  final double lifetimeKm;
  final int weekSteps;
  final int weekGoalDays;
  final List<Achievement> achievements;
  final CountryRank? countryRank;
}

class StepSettings {
  StepSettings.fromJson(Map<String, dynamic> j) : dailyGoal = j['daily_goal'] as int, country = j['country'] as String?;

  final int dailyGoal;
  final String? country;
}

final stepsDayProvider = FutureProvider.autoDispose.family<StepsDay, String>((ref, date) async {
  final json = await ref.watch(apiProvider).get('/steps/today', query: {'date': date});
  return StepsDay.fromJson(json as Map<String, dynamic>);
});

final stepsHistoryProvider = FutureProvider.autoDispose.family<StepsHistory, String>((ref, to) async {
  final json = await ref.watch(apiProvider).get('/steps/history', query: {'to': to});
  return StepsHistory.fromJson(json as Map<String, dynamic>);
});

/// The steps walked on each day of a month ("2026-11"), for the days that have any. It
/// reads the history endpoint, which already answers for any range of up to a year.
final stepsMonthProvider = FutureProvider.autoDispose.family<Map<String, int>, String>((ref, month) async {
  final first = DateTime.parse('$month-01');
  final last = DateTime(first.year, first.month + 1, 0);
  final json = await ref.watch(apiProvider).get('/steps/history', query: {'from': dayKey(first), 'to': dayKey(last)});
  return {
    for (final d in (json['days'] as List))
      if ((d['steps'] as int) > 0) d['date'] as String: d['steps'] as int,
  };
});

final stepsStatsProvider = FutureProvider.autoDispose.family<StepsStats, String>((ref, date) async {
  final json = await ref.watch(apiProvider).get('/steps/stats', query: {'date': date});
  return StepsStats.fromJson(json as Map<String, dynamic>);
});

final stepSettingsProvider = FutureProvider.autoDispose<StepSettings>((ref) async {
  final json = await ref.watch(apiProvider).get('/steps/settings');
  return StepSettings.fromJson(json as Map<String, dynamic>);
});
