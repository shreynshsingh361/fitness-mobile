import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import 'nutrition_screen.dart';

/// The most a recipe can hold, as the backend checks it.
const maxRecipeIngredients = 50;
const maxRecipePortions = 100;
const maxCookedWeight = 50000; // grams

/// One food in a recipe and how many of its servings go in. [food] has the nutrition of
/// ONE serving, so the totals can be worked out again while an amount is being changed.
class Ingredient {
  const Ingredient(this.food, this.servings);

  Ingredient.fromJson(Map<String, dynamic> j)
    : food = Food.fromJson(j['food'] as Map<String, dynamic>),
      servings = (j['servings'] as num).toDouble();

  final Food food;
  final double servings;

  num get calories => food.calories * servings;
  num get protein => food.protein * servings;
  num get carbs => food.carbs * servings;
  num get fat => food.fat * servings;
}

/// A dish someone makes from foods. Its nutrition is for one serving, and its id is also
/// a food id: it goes into a meal like any other food.
class Recipe {
  Recipe.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      portions = j['portions'] as int,
      cookedWeight = (j['cooked_weight_g'] as num?)?.toDouble(),
      serving = j['serving'] as String,
      calories = j['calories'] as num,
      protein = j['protein_g'] as num,
      carbs = j['carbs_g'] as num,
      fat = j['fat_g'] as num,
      ingredients = (j['ingredients'] as List).map((i) => Ingredient.fromJson(i as Map<String, dynamic>)).toList();

  final String id;
  final String name;
  final int portions; // how many servings it makes
  final double? cookedWeight; // grams, the whole dish, if it was weighed
  final String serving; // "1 serving (300 g)" or "1 serving"
  final num calories;
  final num protein;
  final num carbs;
  final num fat;
  final List<Ingredient> ingredients;

  /// The recipe as a food, to add to a meal.
  Food get asFood => Food(
    id: id,
    name: name,
    source: 'recipe',
    serving: serving,
    calories: calories,
    protein: protein,
    carbs: carbs,
    fat: fat,
  );
}

/// What one serving holds: everything in the recipe divided by the servings it makes.
/// The server works this out as well when the recipe is saved. This one is for the screen,
/// while the recipe is still being changed.
({num calories, num protein, num carbs, num fat}) perServing(List<Ingredient> items, int portions) {
  num sum(num Function(Ingredient) part) => items.fold<num>(0, (total, item) => total + part(item));
  final n = portions < 1 ? 1 : portions;
  return (
    calories: sum((i) => i.calories) / n,
    protein: sum((i) => i.protein) / n,
    carbs: sum((i) => i.carbs) / n,
    fat: sum((i) => i.fat) / n,
  );
}

/// "makes 1 serving", "makes 4 servings"
String makes(int portions) => 'makes $portions ${portions == 1 ? 'serving' : 'servings'}';

final recipesProvider = FutureProvider.autoDispose<List<Recipe>>((ref) async {
  final json = await ref.watch(apiProvider).get('/recipes');
  return (json['items'] as List).map((r) => Recipe.fromJson(r as Map<String, dynamic>)).toList();
});
