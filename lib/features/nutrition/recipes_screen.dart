import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import 'add_food.dart';
import 'food_widgets.dart';
import 'recipes_api.dart';

// The recipe screens are pushed on top of where they were opened from, so going back
// returns there (the meals screen, or the list of recipes).
void openRecipe(BuildContext context, String id) => context.push('/food/recipes/$id');
void newRecipe(BuildContext context) => context.push('/food/recipes/new');

/// Every recipe someone made. Each opens to be changed, or goes straight into a meal.
class RecipesScreen extends ConsumerWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recipesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recipes')),
      floatingActionButton: AboveBar(
        child: FloatingActionButton.extended(
          onPressed: () => newRecipe(context),
          icon: const Icon(Icons.add),
          label: const Text('New recipe'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(recipesProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: pagePadding(context, bottom: 88),
          children: [
            AsyncBody(
              value: recipes,
              onRetry: () => ref.invalidate(recipesProvider),
              builder: (list) => list.isEmpty
                  ? const SectionCard(child: _NoRecipes())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final recipe in list) ...[_RecipeCard(recipe: recipe), const SizedBox(height: 12)],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = recipe.ingredients.map((i) => i.food.name).join(', ');
    return GlowCard(
      child: InkWell(
        onTap: () => openRecipe(context, recipe.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(recipe.name, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      '${number(recipe.calories)} kcal a serving · ${makes(recipe.portions)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      names,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Add ${recipe.name} to a meal',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () =>
                    showFoodForMeal(context, recipe.asFood, date: todayKey(), meal: mealForNow(DateTime.now())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoRecipes extends StatelessWidget {
  const _NoRecipes();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Muted(
        'Save a dish you make often from its ingredients, like your dal or a protein shake. '
        'Then add it to any meal in one go.',
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => newRecipe(context),
        icon: const Icon(Icons.add),
        label: const Text('New recipe'),
      ),
    ],
  );
}
