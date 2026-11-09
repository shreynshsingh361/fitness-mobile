import 'package:fitness_mobile/features/groups/groups_api.dart';
import 'package:fitness_mobile/features/steps/steps_api.dart';
import 'package:flutter_test/flutter_test.dart';

// These shapes are copied from the API contract in fitness-backend/contracts/openapi.yaml.
// If parsing one of them fails, the screen that uses it would show an error.

Map<String, dynamic> stepsDayJson() => {
  'date': '2026-11-07',
  'steps': 4200,
  'goal': 10000,
  'goal_met': false,
  'distance_km': 3.2,
  'calories': 168,
  'current_streak': 2,
  'sources': [
    {'source': 'health_connect', 'steps': 4200},
  ],
};

void main() {
  test('a whole-number distance from the server still reads as a number', () {
    final day = StepsDay.fromJson({...stepsDayJson(), 'distance_km': 3});
    expect(day.distanceKm, 3.0);
  });

  test('stats work before anything has been recorded', () {
    final stats = StepsStats.fromJson({
      'longest_streak': 0,
      'best_day': null,
      'best_week': null,
      'lifetime_steps': 0,
      'lifetime_distance_km': 0,
      'this_week': {'from': '2026-11-02', 'to': '2026-11-08', 'steps': 0, 'days_goal_met': 0},
      'achievements': <dynamic>[],
      'country_rank': null,
    });
    expect(stats.bestDaySteps, isNull);
    expect(stats.bestWeekSteps, isNull);
    expect(stats.countryRank, isNull);
  });

  group('leaderboard steps', () {
    LeaderboardRow row(int? steps, {bool hidden = false}) => LeaderboardRow.fromJson({
      'rank': 1,
      'user_id': 'u1',
      'name': 'Asha',
      'steps': steps,
      'steps_hidden': hidden,
      'is_me': false,
    });

    test('a visible count is shown as it is', () => expect(row(12345).stepsText, '12,345'));
    test('mystery mode hides the whole number', () => expect(row(null, hidden: true).stepsText, '🎭 Hidden'));
    test('a count missing today reads as "at least"', () => expect(row(900, hidden: true).stepsText, '900+'));
  });

  test('page counts round up and there is always one page', () {
    Leaderboard board(int total) => Leaderboard.fromJson({
      'from': '2026-11-07',
      'to': '2026-11-07',
      'mystery_active': false,
      'limit': 50,
      'total': total,
      'items': <dynamic>[],
      'me': null,
    });
    expect(board(0).pages, 1);
    expect(board(50).pages, 1);
    expect(board(51).pages, 2);
  });
}
