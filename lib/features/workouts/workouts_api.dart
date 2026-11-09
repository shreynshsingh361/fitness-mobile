import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';

class Exercise {
  Exercise.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      muscleGroup = j['muscle_group'] as String,
      equipment = (j['equipment'] as String?) ?? '',
      bodyPart = (j['body_part'] as String?) ?? '',
      motion = (j['motion'] as String?) ?? 'none',
      muscles = (j['muscles'] as String?) ?? '';

  final String id;
  final String name;
  final String muscleGroup;
  final String equipment; // barbell, dumbbell, kettlebell, cable, machine, band or bodyweight
  final String bodyPart; // one of [bodyParts]
  final String motion; // which animation shows it (see exercise_motion.dart)
  final String muscles; // what it trains, in words: "Lats, biceps"
}

/// The body parts someone can build a plan for, in the order the app shows them.
const bodyParts = {
  'back': 'Back',
  'biceps': 'Biceps',
  'triceps': 'Triceps',
  'forearms': 'Forearms',
  'chest': 'Chest',
  'legs': 'Legs',
  'abs': 'Abs',
  'shoulders': 'Shoulders',
};

/// The exercise each body part's card shows: its motion and what is held.
const bodyPartLook = {
  'back': ('row', 'barbell'),
  'biceps': ('curl', 'dumbbell'),
  'triceps': ('pushdown', 'cable'),
  'forearms': ('wrist_curl', 'dumbbell'),
  'chest': ('bench', 'barbell'),
  'legs': ('squat', 'barbell'),
  'abs': ('crunch', 'bodyweight'),
  'shoulders': ('lateral_raise', 'dumbbell'),
};

/// The most a plan can hold, as the backend checks it.
const maxPlanSets = 10;

/// The heaviest weight a set may have, the same for every exercise: 250 kg, which is 551 lbs.
double maxWeight(String unit) => unit == 'lb' ? 551 : 250;

class PlanSet {
  const PlanSet(this.weight, this.reps);

  PlanSet.fromJson(Map<String, dynamic> j) : weight = (j['weight'] as num).toDouble(), reps = j['reps'] as int;

  final double weight; // in the exercise's unit
  final int reps;

  Map<String, dynamic> toJson() => {'weight': weight, 'reps': reps};
}

/// One exercise in someone's plan for a body part, with the sets they aim for.
class PlanExercise {
  PlanExercise.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      exercise = Exercise.fromJson(j['exercise'] as Map<String, dynamic>),
      unit = j['unit'] as String,
      sets = (j['sets'] as List).map((s) => PlanSet.fromJson(s as Map<String, dynamic>)).toList();

  final String id;
  final Exercise exercise;
  final String unit; // kg or lb
  final List<PlanSet> sets;
}

/// "kg" or "lbs", as people say it.
String unitLabel(String unit) => unit == 'lb' ? 'lbs' : 'kg';

/// A plan exercise in one line: "3 sets · 40 kg × 10", "4 sets · 95–135 lbs × 6–12", or
/// "3 sets × 10 reps" when no weight is set.
String setsSummary(PlanExercise p) {
  final n = p.sets.length;
  final count = '$n ${n == 1 ? 'set' : 'sets'}';
  if (n == 0) return count;
  String range(Iterable<num> values, String Function(num) show) {
    final low = values.reduce((a, b) => a < b ? a : b), high = values.reduce((a, b) => a > b ? a : b);
    return low == high ? show(low) : '${show(low)}–${show(high)}';
  }

  final reps = range(p.sets.map((s) => s.reps), (r) => '$r');
  if (p.sets.every((s) => s.weight == 0)) return '$count × $reps reps';
  return '$count · ${range(p.sets.map((s) => s.weight), kg)} ${unitLabel(p.unit)} × $reps';
}

/// Changes a weight to the other unit, to the nearest half: 40 kg is 88 lbs.
double convertWeight(double weight, {required String to}) {
  const lbPerKg = 2.20462;
  final converted = to == 'lb' ? weight * lbPerKg : weight / lbPerKg;
  return (converted * 2).round() / 2;
}

final planSummariesProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final json = await ref.watch(apiProvider).get('/plans');
  return {for (final item in json['items'] as List) item['body_part'] as String: item['exercise_count'] as int};
});

final planProvider = FutureProvider.autoDispose.family<List<PlanExercise>, String>((ref, part) async {
  final json = await ref.watch(apiProvider).get('/plans/$part');
  return (json['exercises'] as List).map((e) => PlanExercise.fromJson(e as Map<String, dynamic>)).toList();
});

/// The ready-made exercises for a body part.
final libraryProvider = FutureProvider.autoDispose.family<List<Exercise>, String>((ref, part) async {
  final json = await ref.watch(apiProvider).get('/exercises', query: {'body_part': part, 'limit': 100});
  return (json['items'] as List).map((e) => Exercise.fromJson(e as Map<String, dynamic>)).toList();
});
