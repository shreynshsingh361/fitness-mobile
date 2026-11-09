import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../account/account_widgets.dart';
import '../../core/api.dart';
import '../../core/day_calendar.dart';
import '../../core/format.dart';
import '../../core/offline_queue.dart';
import '../../core/palette.dart';
import '../../core/widgets.dart';
import 'food_widgets.dart';
import 'scan_screen.dart';

class DiaryEntry {
  DiaryEntry.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      meal = j['meal'] as String,
      foodName = j['food_name'] as String,
      serving = j['serving'] as String,
      servings = j['servings'] as num,
      calories = j['calories'] as num,
      protein = j['protein_g'] as num,
      carbs = j['carbs_g'] as num,
      fat = j['fat_g'] as num;

  final String id;
  final String meal;
  final String foodName;
  final String serving;
  final num servings;
  final num calories;
  final num protein;
  final num carbs;
  final num fat;
}

class DiaryDay {
  DiaryDay.fromJson(Map<String, dynamic> j)
    : entries = (j['entries'] as List).map((e) => DiaryEntry.fromJson(e as Map<String, dynamic>)).toList(),
      calories = j['totals']['calories'] as num,
      protein = j['totals']['protein_g'] as num,
      carbs = j['totals']['carbs_g'] as num,
      fat = j['totals']['fat_g'] as num;

  final List<DiaryEntry> entries;
  final num calories;
  final num protein;
  final num carbs;
  final num fat;
}

/// The goal until the user sets their own, the same as the server's.
const defaultCalorieGoal = 2000;

class CalorieGoal {
  CalorieGoal.fromJson(Map<String, dynamic> j) : calories = j['calories'] as int, isDefault = j['is_default'] as bool;

  final int calories;
  final bool isDefault;
}

class Food {
  const Food({
    required this.id,
    required this.name,
    this.brand = '',
    this.source = 'hxvy',
    required this.serving,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  Food.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      brand = (j['brand'] as String?) ?? '',
      source = (j['source'] as String?) ?? 'hxvy',
      serving = j['serving'] as String,
      calories = j['calories'] as num,
      protein = j['protein_g'] as num,
      carbs = j['carbs_g'] as num,
      fat = j['fat_g'] as num;

  final String id;
  final String name;
  final String brand; // empty for generic foods
  final String source; // hxvy, usda, off (Open Food Facts), indb (Indian dishes) or recipe (the user's own)
  final String serving;
  final num calories; // per one serving
  final num protein;
  final num carbs;
  final num fat;
}

final diaryProvider = FutureProvider.autoDispose.family<DiaryDay, String>((ref, date) async {
  final json = await ref.watch(apiProvider).get('/diary', query: {'date': date});
  return DiaryDay.fromJson(json as Map<String, dynamic>);
});

final goalProvider = FutureProvider.autoDispose<CalorieGoal>((ref) async {
  final json = await ref.watch(apiProvider).get('/goals');
  return CalorieGoal.fromJson(json as Map<String, dynamic>);
});

final waterProvider = FutureProvider.autoDispose.family<int, String>((ref, date) async {
  final json = await ref.watch(apiProvider).get('/water', query: {'date': date});
  return json['water_ml'] as int;
});

/// The calories eaten on each day of a month ("2026-11"), for the days that have food.
final monthCaloriesProvider = FutureProvider.autoDispose.family<Map<String, int>, String>((ref, month) async {
  final json = await ref.watch(apiProvider).get('/diary/month', query: {'month': month});
  return {for (final d in json['days'] as List) d['date'] as String: d['calories'] as int};
});

final foodsProvider = FutureProvider.autoDispose.family<List<Food>, String>((ref, search) async {
  final json = await ref.watch(apiProvider).get('/foods', query: {'limit': 25, 'search': search});
  return (json['items'] as List).map((f) => Food.fromJson(f as Map<String, dynamic>)).toList();
});

class NutritionScreen extends ConsumerStatefulWidget {
  const NutritionScreen({super.key});

  @override
  ConsumerState<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends ConsumerState<NutritionScreen> {
  String _date = todayKey();

  void _moveDay(int days) {
    setState(() => _date = dayKey(parseDay(_date).add(Duration(days: days, hours: 12))));
  }

  // A calendar with the calories eaten written under each day, to jump to a day from.
  Future<void> _pickDay() async {
    final goal = ref.read(goalProvider).value?.calories ?? defaultCalorieGoal;
    final picked = await pickDay(
      context,
      selected: _date,
      calendar: DayCalendar(
        figures: (ref, month) => ref.watch(monthCaloriesProvider(month)),
        unit: 'kcal',
        nothing: 'nothing logged',
        legend: 'Calories eaten each day · red is over your ${number(goal)} kcal goal',
        standsOut: (kcal) => kcal > goal,
        outColor: Hxvy.over,
      ),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _scan() async {
    final added = await scanFood(context, date: _date);
    if (added == true && mounted) ref.invalidate(diaryProvider(_date));
  }

  Future<void> _changeGoal(int current) async {
    final text = await askText(
      context,
      title: 'Daily calorie goal',
      label: 'Calories',
      initial: '$current',
      keyboard: TextInputType.number,
    );
    if (text == null || !mounted) return;
    final calories = int.tryParse(text.trim());
    if (calories == null) {
      showMessage(context, 'The goal must be a whole number.');
      return;
    }
    final worked = await runAction(context, () => ref.read(apiProvider).put('/goals', body: {'calories': calories}));
    if (worked && mounted) ref.invalidate(goalProvider);
  }

  // Wiping the day's water is asked about first, so a stray tap does not lose it.
  Future<void> _resetWater(int ml) async {
    final date = _date;
    final sure = await confirm(
      context,
      title: 'Reset water for this day?',
      body: 'The ${number(ml)} ml logged for ${shortDate(date)} will be deleted.',
      action: 'Reset',
    );
    if (!sure || !mounted) return;
    final worked = await runAction(context, () => ref.read(apiProvider).delete('/water', query: {'date': date}));
    if (worked && mounted) ref.invalidate(waterProvider(date));
  }

  // The Add food button is the way into the day's meals; the tab itself only sums the day up.
  void _openMeals() => context.go('/food/meals?date=$_date');

  @override
  Widget build(BuildContext context) {
    final date = _date;
    final diary = ref.watch(diaryProvider(date));
    final goal = ref.watch(goalProvider);
    final water = ref.watch(waterProvider(date));
    const gap = SizedBox(height: 12);

    return Scaffold(
      appBar: tabBar(),
      floatingActionButton: AboveBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Scans the barcode on a packet and logs that food.
            FloatingActionButton.small(
              heroTag: 'scan',
              tooltip: 'Scan barcode',
              onPressed: _scan,
              child: const Icon(Icons.qr_code_scanner),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'add-food',
              onPressed: _openMeals,
              icon: const Icon(Icons.add),
              label: const Text('Add food'),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(diaryProvider(date));
          ref.invalidate(goalProvider);
          ref.invalidate(waterProvider(date));
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(), // pull-to-refresh works on a short list too
          padding: pagePadding(context, top: 8, bottom: 88),
          children: [
            const PendingBanner(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous day',
                  onPressed: () => _moveDay(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                TextButton(
                  onPressed: _pickDay,
                  child: Text(date == todayKey() ? 'Today, ${shortDate(date)}' : shortDate(date)),
                ),
                IconButton(tooltip: 'Next day', onPressed: () => _moveDay(1), icon: const Icon(Icons.chevron_right)),
              ],
            ),
            SectionCard(
              title: 'Calories',
              action: goal.hasValue
                  ? TextButton(onPressed: () => _changeGoal(goal.value!.calories), child: const Text('Change goal'))
                  : null,
              child: AsyncBody(
                value: diary,
                onRetry: () => ref.invalidate(diaryProvider(date)),
                builder: (day) => AsyncBody(
                  value: goal,
                  onRetry: () => ref.invalidate(goalProvider),
                  builder: (target) => _Summary(day: day, goal: target),
                ),
              ),
            ),
            gap,
            SectionCard(
              title: 'What you ate',
              child: AsyncBody(
                value: diary,
                onRetry: () => ref.invalidate(diaryProvider(date)),
                builder: (day) => _Eaten(day: day),
              ),
            ),
            gap,
            SectionCard(
              title: 'Water',
              // Up here like Change goal, which leaves the row below room to take a glass back.
              action: water.hasValue
                  ? TextButton(
                      onPressed: water.value == 0 ? null : () => _resetWater(water.value!),
                      child: const Text('Reset day'),
                    )
                  : null,
              child: AsyncBody(
                value: water,
                onRetry: () => ref.invalidate(waterProvider(date)),
                builder: (ml) => _Water(date: date, ml: ml),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.day, required this.goal});

  final DiaryDay day;
  final CalorieGoal goal;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          CalorieRing(eaten: day.calories, goal: goal.calories),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stat(label: 'Eaten', value: '${number(day.calories)} kcal'),
                const SizedBox(height: 12),
                Stat(
                  label: 'Goal',
                  value: '${number(goal.calories)} kcal',
                  hint: goal.isDefault ? 'default, change it to fit you' : null,
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      MacroBar(protein: day.protein, carbs: day.carbs, fat: day.fat),
    ],
  );
}

/// Everything eaten on the day, meal by meal: breakfast, lunch, snacks, then dinner, each
/// with its foods and calories. Foods are added and removed on the meals screen (Add food).
class _Eaten extends StatelessWidget {
  const _Eaten({required this.day});

  final DiaryDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: Hxvy.textMuted);
    final mealNames = meals.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < mealNames.length; i++) ...[
          if (i > 0) const Divider(height: 20),
          Builder(
            builder: (context) {
              final entries = day.entries.where((e) => e.meal == mealNames[i].key).toList();
              final kcal = entries.fold<num>(0, (sum, e) => sum + e.calories);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          mealNames[i].value,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text('${number(kcal)} kcal', style: theme.textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (entries.isEmpty)
                    Text('Nothing yet', style: muted)
                  else
                    for (final entry in entries)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  text: entry.foodName,
                                  children: [
                                    TextSpan(text: '  ${servingsAmount(entry.serving, entry.servings)}', style: muted),
                                  ],
                                ),
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text('${number(entry.calories)} kcal', style: muted),
                          ],
                        ),
                      ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

/// What was drunk on the day, with buttons to take a glass back or add one. A tap without internet
/// is kept on the phone and sent later (see [OfflineQueue]); the total shows it right away.
class _Water extends ConsumerWidget {
  const _Water({required this.date, required this.ml});

  final String date;
  final int ml;

  Future<void> _change(BuildContext context, WidgetRef ref, int delta) async {
    final opId = const Uuid().v4();
    final adding = delta > 0;
    final op = PendingOp(
      id: opId,
      kind: 'water',
      method: adding ? 'post' : 'delete',
      path: '/water',
      label: '${adding ? '+' : '−'}250 ml water',
      date: date,
      deltaMl: delta,
      body: adding ? {'amount_ml': 250, 'date': date, 'client_op_id': opId} : null,
      query: adding ? null : {'date': date, 'amount_ml': 250, 'client_op_id': opId},
    );
    try {
      final sent = await ref.read(offlineQueueProvider).send(op);
      if (!context.mounted) return;
      if (sent) {
        ref.invalidate(waterProvider(date));
      } else {
        showMessage(context, savedOffline);
      }
    } catch (error) {
      if (context.mounted) showMessage(context, messageOf(error));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(offlineQueueProvider);
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        final shown = math.max(0, ml + queue.pendingWaterMl(date));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stat(label: 'Drunk', value: '${number(shown)} ml'),
            const SizedBox(height: 12),
            GoalBar(value: fraction(shown, 2000), label: 'Water compared with a 2 litre reference'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Takes a glass back without asking, since +250 ml undoes it just as easily. The server
                // takes it off the newest logs and never goes below zero; the button is off at zero.
                OutlinedButton(
                  onPressed: shown == 0 ? null : () => _change(context, ref, -250),
                  child: const Text('−250 ml'),
                ),
                OutlinedButton(onPressed: () => _change(context, ref, 250), child: const Text('+250 ml')),
              ],
            ),
          ],
        );
      },
    );
  }
}
