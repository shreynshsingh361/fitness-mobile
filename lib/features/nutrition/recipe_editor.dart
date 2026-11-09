import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';
import 'add_food.dart';
import 'food_widgets.dart';
import 'nutrition_screen.dart';
import 'recipes_api.dart';

/// Makes a new recipe ([id] null) or changes one: its name, how many servings it makes,
/// optionally its cooked weight, and the foods that go in. One serving's calories update
/// while it is being changed.
class RecipeEditor extends ConsumerStatefulWidget {
  const RecipeEditor({super.key, this.id});

  final String? id;

  @override
  ConsumerState<RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends ConsumerState<RecipeEditor> {
  final _name = TextEditingController();
  final _portions = TextEditingController(text: '1');
  final _weight = TextEditingController();
  List<Ingredient> _items = const [];

  late bool _loaded = widget.id == null; // a recipe being changed loads first
  Object? _loadError;
  bool _saving = false;
  bool _changed = false; // since it was opened, so leaving can warn

  @override
  void initState() {
    super.initState();
    if (!_loaded) _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _portions.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final json = await ref.read(apiProvider).get('/recipes/${widget.id}');
      final recipe = Recipe.fromJson(json as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _name.text = recipe.name;
        _portions.text = '${recipe.portions}';
        _weight.text = recipe.cookedWeight == null ? '' : kg(recipe.cookedWeight!);
        _items = recipe.ingredients;
        _loaded = true;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  void _edited([_]) => setState(() => _changed = true);

  /// The servings it makes, or null when that box does not hold 1 to 100.
  int? get _portionCount {
    final n = int.tryParse(_portions.text.trim());
    return n != null && n >= 1 && n <= maxRecipePortions ? n : null;
  }

  /// The cooked weight in grams (null when left empty), and whether the box is fine.
  ({bool ok, double? grams}) get _cookedWeight {
    final text = _weight.text.trim().replaceAll(',', '.');
    if (text.isEmpty) return (ok: true, grams: null);
    final grams = double.tryParse(text);
    return (ok: grams != null && grams >= 1 && grams <= maxCookedWeight, grams: grams);
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _portionCount != null &&
      _cookedWeight.ok &&
      _items.isNotEmpty &&
      _items.length <= maxRecipeIngredients;

  Future<void> _addIngredient() async {
    final picked = await pickIngredient(context);
    if (picked == null || !mounted) return;
    setState(() {
      _items = [..._items, picked];
      _changed = true;
    });
  }

  Future<void> _changeAmount(int index) async {
    final item = _items[index];
    final servings = await changeIngredient(context, item);
    if (servings == null || !mounted) return;
    setState(() {
      _items = [..._items]..[index] = Ingredient(item.food, servings);
      _changed = true;
    });
  }

  void _remove(int index) => setState(() {
    _items = [..._items]..removeAt(index);
    _changed = true;
  });

  Future<void> _save() async {
    final id = widget.id;
    final name = _name.text.trim();
    final body = {
      'name': name,
      'portions': _portionCount,
      'cooked_weight_g': _cookedWeight.grams,
      'ingredients': [
        for (final item in _items)
          {'food_id': item.food.id, 'servings': double.parse(item.servings.toStringAsFixed(4))},
      ],
    };
    final api = ref.read(apiProvider);

    setState(() => _saving = true);
    final worked = await runAction(
      context,
      () => id == null ? api.post('/recipes', body: body) : api.put('/recipes/$id', body: body),
      done: '$name saved.',
    );
    if (!mounted) return;
    if (worked) {
      _refreshLists();
      context.pop();
    } else {
      setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final name = _name.text.trim();
    final sure = await confirm(
      context,
      title: 'Delete $name?',
      body: 'Meals you already logged it in keep it.',
      action: 'Delete',
    );
    if (!sure || !mounted) return;
    final worked = await runAction(
      context,
      () => ref.read(apiProvider).delete('/recipes/${widget.id}'),
      done: '$name deleted.',
    );
    if (worked && mounted) {
      _refreshLists();
      context.pop();
    }
  }

  /// The recipe shows in the recipe lists and in food search.
  void _refreshLists() {
    ref.invalidate(recipesProvider);
    ref.invalidate(foodsProvider);
  }

  /// Back with unsaved changes asks first, so a long recipe is not lost to one swipe.
  Future<void> _leave() async {
    final leave = await confirm(
      context,
      title: 'Leave without saving?',
      body: 'Your changes to this recipe will be lost.',
      action: 'Leave',
    );
    if (leave && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.id != null;
    final error = _loadError;
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(editing ? 'Edit recipe' : 'New recipe'),
          actions: [
            if (editing && _loaded)
              IconButton(
                tooltip: 'Delete recipe',
                icon: const Icon(Icons.delete_outline),
                onPressed: _saving ? null : _delete,
              ),
          ],
        ),
        body: _loaded
            ? _form(context)
            : error != null
            ? Center(
                child: ErrorRetry(error: error, onRetry: _load),
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    final portions = _portionCount;
    final weight = _cookedWeight;
    final one = perServing(_items, portions ?? 1);
    final whole = perServing(_items, 1);
    final grams = weight.grams;

    return ListView(
      padding: pagePadding(context),
      children: [
        TextField(
          controller: _name,
          onChanged: _edited,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Name', hintText: "Mom's dal, protein shake…", counterText: ''),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _portions,
                onChanged: _edited,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Servings it makes',
                  errorText: portions == null ? '1 to $maxRecipePortions' : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _weight,
                onChanged: _edited,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Cooked weight',
                  suffixText: 'g',
                  helperText: 'Optional',
                  errorText: weight.ok ? null : '1 to ${number(maxCookedWeight)} g',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Muted(
          grams != null && weight.ok && portions != null
              ? 'One serving weighs ${kg(grams / portions)} g, so you can log it in grams.'
              : 'Weigh the cooked dish if you want to log it in grams.',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'One serving',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    number(one.calories),
                    style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  const Muted('kcal'),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Muted('${number(whole.calories)} kcal in all'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              MacroBar(protein: one.protein, carbs: one.carbs, fat: one.fat),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Ingredients',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Muted('Add each food that goes in, and how much.'),
                ),
              for (var i = 0; i < _items.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _changeAmount(i),
                  title: Text(_items[i].food.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(servingsAmount(_items[i].food.serving, _items[i].servings)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${number(_items[i].calories)} kcal'),
                      IconButton(
                        tooltip: 'Remove ${_items[i].food.name}',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _remove(i),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _items.length >= maxRecipeIngredients ? null : _addIngredient,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add ingredient'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _saving || !_valid ? null : _save, child: Text(_saving ? 'Saving…' : 'Save recipe')),
      ],
    );
  }
}
