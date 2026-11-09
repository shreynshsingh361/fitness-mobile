import 'package:fitness_mobile/features/nutrition/food_widgets.dart';
import 'package:fitness_mobile/features/nutrition/nutrition_screen.dart';
import 'package:fitness_mobile/features/nutrition/recipes_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the starting meal follows the time of day', () {
    String at(int hour) => mealForNow(DateTime(2026, 11, 8, hour));
    expect(at(7), 'breakfast');
    expect(at(10), 'breakfast');
    expect(at(11), 'lunch');
    expect(at(15), 'lunch');
    expect(at(16), 'snack');
    expect(at(19), 'dinner');
    expect(at(23), 'dinner');
  });

  test('a food reads its brand and source, and copes when they are missing', () {
    final packaged = Food.fromJson({
      'id': 'f1',
      'name': 'Peanut butter',
      'brand': 'Pintola',
      'source': 'off',
      'serving': '2 tbsp (32 g)',
      'calories': 190,
      'protein_g': 8,
      'carbs_g': 6,
      'fat_g': 16,
    });
    expect(packaged.brand, 'Pintola');
    expect(packaged.source, 'off');

    final older = Food.fromJson({
      'id': 'f2',
      'name': 'Egg, whole',
      'serving': '1 large egg (50 g)',
      'calories': 72,
      'protein_g': 6.3,
      'carbs_g': 0.4,
      'fat_g': 4.8,
    });
    expect(older.brand, '');
    expect(older.source, 'hxvy');
  });

  testWidgets('the macro bar shows each part as grams and a share of the calories', (tester) async {
    // 10 g protein = 40 kcal, 10 g carbs = 40 kcal, 0 g fat: an even 50/50 split.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MacroBar(protein: 10, carbs: 10, fat: 0))));
    expect(find.text('Protein 50%'), findsOneWidget);
    expect(find.text('Carbs 50%'), findsOneWidget);
    expect(find.text('Fat 0%'), findsOneWidget);
  });

  testWidgets('the ring says how much is left, or how much over', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CalorieRing(eaten: 1500, goal: 2000)));
    expect(find.text('500'), findsOneWidget);
    expect(find.text('kcal left'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: CalorieRing(eaten: 2300, goal: 2000)));
    expect(find.text('300'), findsOneWidget);
    expect(find.text('kcal over'), findsOneWidget);
  });

  test('the weight of a serving is read from its label', () {
    expect(servingSize('1 cup (158 g)'), (amount: 158.0, unit: 'g'));
    expect(servingSize('100 g'), (amount: 100.0, unit: 'g'));
    expect(servingSize('100.0g'), (amount: 100.0, unit: 'g'));
    expect(servingSize('2 pieces (11 g)'), (amount: 11.0, unit: 'g'));
    expect(servingSize('250 ml'), (amount: 250.0, unit: 'ml'));
    expect(servingSize('1 slice, regular (4" x 5") (46 g)'), (amount: 46.0, unit: 'g'));
    expect(servingSize('1 medium'), isNull);
  });

  group('recipes', () {
    Map<String, dynamic> food(String id, String name, String serving, num kcal, num p, num c, num f) => {
      'id': id,
      'name': name,
      'source': 'hxvy',
      'serving': serving,
      'calories': kcal,
      'protein_g': p,
      'carbs_g': c,
      'fat_g': f,
    };

    final json = {
      'id': 'r1',
      'name': "Mom's dal",
      'portions': 4,
      'cooked_weight_g': 1200,
      'serving': '1 serving (300 g)',
      'calories': 117,
      'protein_g': 6.8,
      'carbs_g': 15.1,
      'fat_g': 3.7,
      'ingredients': [
        {'food': food('f1', 'Lentils', '100 g', 116, 9, 20.1, 0.4), 'servings': 3},
        {'food': food('f2', 'Olive oil', '1 tbsp (14 g)', 119, 0, 0, 13.5), 'servings': 1},
      ],
      'updated_at': '2026-11-08T12:00:00Z',
    };

    test('a recipe reads its ingredients and becomes a food for the diary', () {
      final recipe = Recipe.fromJson(json);
      expect(recipe.portions, 4);
      expect(recipe.cookedWeight, 1200);
      expect(recipe.ingredients.map((i) => i.food.name), ['Lentils', 'Olive oil']);
      expect(recipe.ingredients.first.servings, 3);

      final asFood = recipe.asFood;
      expect(asFood.id, 'r1');
      expect(asFood.source, 'recipe');
      expect(asFood.serving, '1 serving (300 g)');
      expect(asFood.calories, 117);

      final unweighed = Recipe.fromJson({...json, 'cooked_weight_g': null, 'serving': '1 serving'});
      expect(unweighed.cookedWeight, isNull);
    });

    test('one serving is everything in it divided by the servings it makes', () {
      final items = Recipe.fromJson(json).ingredients; // 348 + 119 = 467 kcal in all
      expect(perServing(items, 1).calories, 467);
      expect(perServing(items, 4).calories, closeTo(116.75, 0.001));
      expect(perServing(items, 4).fat, closeTo((1.2 + 13.5) / 4, 0.001));
      expect(perServing(items, 0).calories, 467, reason: 'an empty or zero box counts as one serving');
      expect(perServing(const [], 2).calories, 0);
    });

    test('amounts read in grams when the serving has a weight', () {
      expect(servingsAmount('100 g', 2.5), '250 g');
      expect(servingsAmount('1 tbsp (14 g)', 1), '14 g');
      expect(servingsAmount('1 medium', 1.5), '1.5 × 1 medium');
      expect(makes(1), 'makes 1 serving');
      expect(makes(4), 'makes 4 servings');
    });
  });
}
