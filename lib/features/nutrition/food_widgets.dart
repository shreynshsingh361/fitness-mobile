import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/offline_queue.dart';
import '../../core/palette.dart';
import '../../core/widgets.dart';

/// Where the food data comes from. Open Food Facts (ODbL) and the Indian Nutrient Databank
/// (CC BY 4.0) both ask for this credit.
const foodDataCredit =
    'Food data: USDA FoodData Central · Open Food Facts (ODbL) · Indian Nutrient Databank (CC BY 4.0)';

/// The meals of a day, in the order they are shown.
const meals = {'breakfast': 'Breakfast', 'lunch': 'Lunch', 'snack': 'Snacks', 'dinner': 'Dinner'};

/// How much one serving weighs, read from its label: "1 cup (158 g)" is 158 g and
/// "250 ml" is 250 ml. Null when the label gives no weight ("1 medium").
({double amount, String unit})? servingSize(String serving) {
  final matches = RegExp(r'(\d+(?:[.,]\d+)?)\s*(g|gm|gram|grams|ml)\b', caseSensitive: false).allMatches(serving);
  if (matches.isEmpty) return null;
  final last = matches.last; // "1 slice (4 in) (46 g)": the weight is the last number
  final amount = double.tryParse(last.group(1)!.replaceAll(',', '.'));
  if (amount == null || amount <= 0) return null;
  return (amount: amount, unit: last.group(2)!.toLowerCase() == 'ml' ? 'ml' : 'g');
}

/// How much of a food that is, for a list: "250 g" when a serving has a weight, otherwise
/// "1.5 × 1 medium".
String servingsAmount(String serving, num servings) {
  final size = servingSize(serving);
  if (size == null) return '${kg(servings)} × $serving';
  return '${kg(servings * size.amount)} ${size.unit}';
}

/// The meal that fits the time of day, as the starting choice when adding food.
String mealForNow(DateTime now) {
  final hour = now.hour;
  if (hour < 11) return 'breakfast';
  if (hour < 16) return 'lunch';
  if (hour < 19) return 'snack';
  return 'dinner';
}

/// A ring that fills as the day's calories add up, with what is left in the middle.
class CalorieRing extends StatelessWidget {
  const CalorieRing({super.key, required this.eaten, required this.goal, this.size = 150});

  final num eaten;
  final num goal;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final left = goal - eaten;
    final over = left < 0;
    return ProgressRing(
      size: size,
      semanticLabel: '${number(eaten)} of ${number(goal)} calories eaten',
      // Past the goal the whole ring turns red, and stays so however far over it goes.
      fraction: fraction(eaten, goal),
      color: over ? Hxvy.over : Hxvy.accent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            number(left.abs()),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: over ? Hxvy.over : null,
            ),
          ),
          Text(
            over ? 'kcal over' : 'kcal left',
            style: theme.textTheme.bodySmall?.copyWith(color: over ? Hxvy.over : Hxvy.textMuted),
          ),
        ],
      ),
    );
  }
}

/// How the calories split between protein, carbs and fat (4, 4 and 9 kcal per gram), as
/// one bar in three shades with the grams and share written under it.
class MacroBar extends StatelessWidget {
  const MacroBar({super.key, required this.protein, required this.carbs, required this.fat});

  final num protein;
  final num carbs;
  final num fat;

  static const _shades = [Hxvy.accent, Color(0xFFA1A1A1), Color(0xFF5C5C5C)];

  @override
  Widget build(BuildContext context) {
    final parts = [('Protein', protein, 4), ('Carbs', carbs, 4), ('Fat', fat, 9)];
    final kcal = [for (final p in parts) p.$2 * p.$3];
    final total = kcal.fold<num>(0, (sum, k) => sum + k);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: total <= 0
                ? const ColoredBox(color: Color(0xFF2A2A2A))
                : Row(
                    children: [
                      for (var i = 0; i < parts.length; i++)
                        if (kcal[i] > 0)
                          Expanded(
                            flex: math.max(1, (kcal[i] / total * 1000).round()),
                            child: Container(
                              color: _shades[i],
                              // A 2px gap between the parts keeps them apart.
                              margin: EdgeInsets.only(right: i < parts.length - 1 ? 2 : 0),
                            ),
                          ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < parts.length; i++)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 5, right: 6),
                      decoration: BoxDecoration(color: _shades[i], shape: BoxShape.circle),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${kg(parts[i].$2)} g', style: theme.textTheme.titleSmall),
                          Text(
                            total <= 0 ? parts[i].$1 : '${parts[i].$1} ${(kcal[i] / total * 100).round()}%',
                            style: theme.textTheme.bodySmall?.copyWith(color: Hxvy.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Says what is waiting for the internet (food and water added without a connection), and tells
/// about a change the server refused. Nothing is shown when there is nothing to say.
class PendingBanner extends ConsumerWidget {
  const PendingBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(offlineQueueProvider);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        final waiting = queue.pending;
        final problems = queue.problems;
        if (waiting.isEmpty && problems.isEmpty) return const SizedBox.shrink();
        const shownMax = 4;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlowCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (waiting.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.cloud_off_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            waiting.length == 1
                                ? '1 change waiting for internet'
                                : '${waiting.length} changes waiting for internet',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Muted(
                      '${waiting.take(shownMax).map((o) => o.label).join(', ')}'
                      '${waiting.length > shownMax ? ' and ${waiting.length - shownMax} more' : ''}. '
                      'They are saved on your phone and sent by themselves.',
                    ),
                  ],
                  for (final problem in problems)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Could not save: $problem', style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  if (problems.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(onPressed: queue.clearProblems, child: const Text('OK')),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
