import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/palette.dart';
import '../../core/widgets.dart';
import 'add_food.dart';
import 'food_widgets.dart';
import 'nutrition_screen.dart';

/// One day's food, meal by meal. Each meal adds and removes its own foods, recipes
/// included (they show first in its search).
class MealsScreen extends ConsumerWidget {
  const MealsScreen({super.key, required this.date});

  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diary = ref.watch(diaryProvider(date));
    final title = date == todayKey() ? 'Today' : shortDate(date);
    return Scaffold(
      appBar: AppBar(
        title: Text('Meals · $title'),
        actions: [
          IconButton(
            tooltip: 'Recipes',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => context.push('/food/recipes'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(diaryProvider(date)),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: pagePadding(context),
          children: [
            const PendingBanner(),
            AsyncBody(
              value: diary,
              onRetry: () => ref.invalidate(diaryProvider(date)),
              builder: (day) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DayTotal(day: day),
                  const SizedBox(height: 16),
                  for (final meal in meals.keys) ...[
                    _MealSection(date: date, meal: meal, entries: day.entries.where((e) => e.meal == meal).toList()),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayTotal extends StatelessWidget {
  const _DayTotal({required this.day});

  final DiaryDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(number(day.calories), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Padding(padding: const EdgeInsets.only(bottom: 4), child: Muted('kcal today')),
        const SizedBox(width: 12),
        // The macros take the room that is left and wrap, rather than run off a narrow screen.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'P ${kg(day.protein)} · C ${kg(day.carbs)} · F ${kg(day.fat)} g',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

class _MealSection extends ConsumerWidget {
  const _MealSection({required this.date, required this.meal, required this.entries});

  final String date;
  final String meal;
  final List<DiaryEntry> entries;

  Future<void> _remove(BuildContext context, WidgetRef ref, DiaryEntry entry) async {
    // Asked first, so a stray tap on the cross does not delete the log.
    final sure = await confirm(
      context,
      title: 'Delete this food?',
      body: '${entry.foodName} (${amountText(entry)}) will be removed from ${meals[meal]!.toLowerCase()}.',
      action: 'Delete',
    );
    if (!sure || !context.mounted) return;
    final worked = await runAction(
      context,
      () => ref.read(apiProvider).delete('/diary/${entry.id}'),
      done: '${entry.foodName} removed.',
    );
    if (worked && context.mounted) ref.invalidate(diaryProvider(date));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final kcal = entries.fold<num>(0, (sum, e) => sum + e.calories);
    return GlowCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(meals[meal]!, style: theme.textTheme.titleMedium)),
                Text('${number(kcal)} kcal', style: theme.textTheme.titleSmall),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => showAddFood(context, date: date, meal: meal),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (entries.isEmpty)
              const Padding(padding: EdgeInsets.only(bottom: 8), child: Muted('Nothing yet.'))
            else
              for (final entry in entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.foodName, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${amountText(entry)} · P ${kg(entry.protein)} · C ${kg(entry.carbs)} · F ${kg(entry.fat)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: Hxvy.textMuted),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${number(entry.calories)} kcal'),
                      IconButton(
                        tooltip: 'Remove ${entry.foodName}',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _remove(context, ref, entry),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// "250 g" when the serving has a weight, otherwise "1.5 × 1 medium".
String amountText(DiaryEntry entry) => servingsAmount(entry.serving, entry.servings);
