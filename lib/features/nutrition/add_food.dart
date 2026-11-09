import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/offline_queue.dart';
import '../../core/format.dart';
import '../../core/palette.dart';
import '../../core/widgets.dart';
import 'food_widgets.dart';
import 'nutrition_screen.dart';
import 'recipes_api.dart';

/// The food sheets do two jobs: add food to a meal of the diary, or pick an ingredient
/// (and how much of it) for a recipe.

/// Where food goes when it is added to the diary. Null while picking an ingredient.
typedef _Diary = ({String date, String meal});

/// Opens the food search for one meal of one day. Closes once something was added.
Future<void> showAddFood(BuildContext context, {required String date, required String meal}) =>
    _sheet<void>(context, _AddFoodSheet(diary: (date: date, meal: meal)));

/// Opens one food, such as a recipe or a scanned product, ready to add to a meal of [date].
/// Returns true when it was added.
Future<bool?> showFoodForMeal(BuildContext context, Food food, {required String date, required String meal}) =>
    _sheet<bool>(context, _FoodSheet(food: food, diary: (date: date, meal: meal)));

/// Searches for an ingredient and asks how much of it goes in. Recipes are left out of the
/// search: a recipe cannot go inside another.
Future<Ingredient?> pickIngredient(BuildContext context) => _sheet<Ingredient>(context, const _AddFoodSheet());

/// Changes how much of an ingredient goes in. Returns the new number of servings.
Future<double?> changeIngredient(BuildContext context, Ingredient ingredient) =>
    _sheet<double>(context, _FoodSheet(food: ingredient.food, servings: ingredient.servings, action: 'Save amount'));

Future<T?> _sheet<T>(BuildContext context, Widget sheet) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true, // keeps the top clear of the status bar when the keyboard is open
  useRootNavigator: true, // covers the glass bottom bar too
  builder: (_) => sheet,
);

class _AddFoodSheet extends ConsumerStatefulWidget {
  const _AddFoodSheet({this.diary});

  final _Diary? diary;

  @override
  ConsumerState<_AddFoodSheet> createState() => _AddFoodSheetState();
}

class _AddFoodSheetState extends ConsumerState<_AddFoodSheet> {
  String _search = '';
  Timer? _typing;

  @override
  void dispose() {
    _typing?.cancel();
    super.dispose();
  }

  /// Waits for a short pause in typing, so one word is not one request per letter.
  void _onSearch(String text) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _search = text.trim());
    });
  }

  Future<void> _open(Food food) async {
    final diary = widget.diary;
    if (diary == null) {
      final servings = await _sheet<double>(context, _FoodSheet(food: food));
      if (servings != null && mounted) Navigator.pop(context, Ingredient(food, servings));
    } else {
      final added = await _sheet<bool>(context, _FoodSheet(food: food, diary: diary));
      if (added == true && mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diary = widget.diary;
    final foods = ref.watch(foodsProvider(_search));
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Padding(
          // Keeps the fields above the on-screen keyboard.
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                diary == null ? 'Add an ingredient' : 'Add to ${meals[diary.meal]!.toLowerCase()}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                onChanged: _onSearch,
                decoration: const InputDecoration(
                  labelText: 'Search foods',
                  hintText: 'rice, dal, Amul butter…',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: AsyncBody(
                  value: foods,
                  onRetry: () => ref.invalidate(foodsProvider(_search)),
                  builder: (found) {
                    final items = diary == null ? found.where((f) => f.source != 'recipe').toList() : found;
                    if (items.isEmpty) {
                      return Padding(padding: const EdgeInsets.all(16), child: Muted('No foods match "$_search".'));
                    }
                    return ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _FoodRow(food: items[i], onTap: () => _open(items[i])),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              const Center(child: Muted(foodDataCredit)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoodRow extends StatelessWidget {
  const _FoodRow({required this.food, required this.onTap});

  final Food food;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final from = food.source == 'recipe' ? 'Your recipe' : food.brand;
    final detail = [if (from.isNotEmpty) from, food.serving].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      title: Text(food.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(number(food.calories), style: theme.textTheme.titleMedium),
          Text('kcal', style: theme.textTheme.bodySmall?.copyWith(color: Hxvy.textMuted)),
        ],
      ),
    );
  }
}

/// One food, large: how much (in grams or servings), its calories for that amount and how
/// they split. For the diary it saves the food to a meal and returns true. For a recipe it
/// saves nothing and returns the number of servings instead.
class _FoodSheet extends ConsumerStatefulWidget {
  const _FoodSheet({required this.food, this.diary, this.servings = 1, this.action = 'Add to recipe'});

  final Food food;
  final _Diary? diary;
  final double servings; // to start with
  final String action; // the button's words when picking an ingredient

  @override
  ConsumerState<_FoodSheet> createState() => _FoodSheetState();
}

class _FoodSheetState extends ConsumerState<_FoodSheet> {
  // The backend takes servings; grams typed here are turned into servings. A recipe can
  // use more of a food than one meal can (2 kg of rice is 20 servings of "100 g").
  static const _minServings = 0.01;
  late final _maxServings = widget.diary == null ? 1000.0 : 100.0;

  late final _size = servingSize(widget.food.serving);
  late double _servings = widget.servings;
  late final _amount = TextEditingController(text: _size == null ? '' : kg(_servings * _size.amount));
  late String _meal = widget.diary?.meal ?? 'lunch';
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Typed grams (or ml) → servings.
  void _onAmount(String text) {
    final size = _size;
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    if (size == null || value == null) return;
    setState(() => _servings = value / size.amount);
  }

  /// The −/+ buttons change whole and half servings, and keep the grams box in step.
  void _step(double by) {
    final next = ((_servings * 2).round() / 2 + by).clamp(0.5, _maxServings).toDouble();
    setState(() => _servings = next);
    final size = _size;
    if (size != null) _amount.text = kg(next * size.amount);
  }

  bool get _valid => _servings >= _minServings && _servings <= _maxServings;

  double get _sent => double.parse(_servings.toStringAsFixed(4));

  Future<void> _done() async {
    final diary = widget.diary;
    if (diary == null) {
      Navigator.pop(context, _sent);
      return;
    }

    final food = widget.food;
    setState(() => _saving = true);
    // Without internet the entry is kept on the phone and sent later (see OfflineQueue). The
    // client_op_id lets the server recognise a copy it already saved.
    final opId = const Uuid().v4();
    final op = PendingOp(
      id: opId,
      kind: 'food',
      method: 'post',
      path: '/diary',
      label: '${food.name} (${meals[_meal]!.toLowerCase()})',
      date: diary.date,
      body: {'client_op_id': opId, 'food_id': food.id, 'meal': _meal, 'servings': _sent, 'eaten_on': diary.date},
    );
    var worked = false;
    try {
      final sentNow = await ref.read(offlineQueueProvider).send(op);
      worked = true;
      if (mounted) {
        showMessage(context, sentNow ? '${food.name} added to ${meals[_meal]!.toLowerCase()}.' : savedOffline);
      }
    } catch (error) {
      if (mounted) showMessage(context, messageOf(error));
    }
    if (!mounted) return;
    ref.invalidate(diaryProvider(diary.date));
    if (worked) {
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final food = widget.food;
    final forMeal = widget.diary != null;
    final theme = Theme.of(context);
    final size = _size;
    final s = _servings;
    final source = switch (food.source) {
      'usda' => 'USDA FoodData Central',
      'off' => 'Open Food Facts',
      'indb' => 'Indian Nutrient Databank',
      'recipe' => 'your recipe',
      _ => 'Hxvy',
    };

    return SafeArea(
      child: Padding(
        // Keeps the grams box above the on-screen keyboard.
        padding: EdgeInsets.fromLTRB(20, 20, 20, 12 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(food.name, style: theme.textTheme.titleLarge),
              if (food.brand.isNotEmpty) Muted(food.brand),
              const SizedBox(height: 20),
              Center(
                child: Column(
                  children: [
                    Text(
                      _valid ? number(food.calories * s) : '–',
                      style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text('kcal', style: theme.textTheme.bodyMedium?.copyWith(color: Hxvy.textMuted)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  IconButton.outlined(
                    tooltip: 'Less',
                    onPressed: s > 0.5 ? () => _step(-0.5) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: size == null
                        ? Text(
                            '${kg(s)} × ${food.serving}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleSmall,
                          )
                        : TextField(
                            controller: _amount,
                            onChanged: _onAmount,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: size.unit == 'ml' ? 'Millilitres' : 'Grams',
                              suffixText: size.unit,
                              isDense: true,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.outlined(
                    tooltip: 'More',
                    onPressed: s < _maxServings ? () => _step(0.5) : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Center(
                child: Muted(
                  _valid
                      ? '1 serving = ${food.serving} · ${number(food.calories)} kcal'
                      : 'Enter between ${kg(_minServings * (size?.amount ?? 1))} and ${number(_maxServings * (size?.amount ?? 1))} ${size?.unit ?? 'servings'}',
                ),
              ),
              const SizedBox(height: 20),
              if (_valid) MacroBar(protein: food.protein * s, carbs: food.carbs * s, fat: food.fat * s),
              const SizedBox(height: 20),
              if (forMeal) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final meal in meals.entries)
                      ChoiceChip(
                        label: Text(meal.value),
                        selected: _meal == meal.key,
                        onSelected: (_) => setState(() => _meal = meal.key),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              FilledButton(
                onPressed: _saving || !_valid ? null : _done,
                child: Text(
                  !forMeal
                      ? widget.action
                      : _saving
                      ? 'Adding…'
                      : 'Add to ${meals[_meal]!.toLowerCase()}',
                ),
              ),
              const SizedBox(height: 8),
              Center(child: Muted('Data: $source')),
            ],
          ),
        ),
      ),
    );
  }
}
