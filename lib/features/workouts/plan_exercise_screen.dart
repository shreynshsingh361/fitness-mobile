import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/palette.dart';
import '../../core/widgets.dart';
import 'exercise_motion.dart';
import 'workouts_api.dart';

/// One set being typed in. It owns its text fields, so it also has to dispose them.
class _SetRow {
  _SetRow(double weight, int reps)
    : weight = TextEditingController(text: weight == 0 ? '' : kg(weight)),
      reps = TextEditingController(text: '$reps');

  final TextEditingController weight;
  final TextEditingController reps;

  /// The weight typed in [unit] (empty is 0, for bodyweight), or null when it is not a number
  /// or is over the heaviest a set may be.
  double? weightIn(String unit) {
    final text = weight.text.trim().replaceAll(',', '.');
    if (text.isEmpty) return 0;
    final w = double.tryParse(text);
    return w != null && w >= 0 && w <= maxWeight(unit) ? w : null;
  }

  int? get repsValue {
    final r = int.tryParse(reps.text.trim());
    return r != null && r >= 1 && r <= 1000 ? r : null;
  }

  void dispose() {
    weight.dispose();
    reps.dispose();
  }
}

/// One exercise of a plan: the clip of how it is done, then its sets, each with its own
/// weight (in kg or lbs) and reps. Up to [maxPlanSets] sets.
class PlanExerciseScreen extends ConsumerStatefulWidget {
  const PlanExerciseScreen({super.key, required this.part, required this.id});

  final String part;
  final String id;

  @override
  ConsumerState<PlanExerciseScreen> createState() => _PlanExerciseScreenState();
}

class _PlanExerciseScreenState extends ConsumerState<PlanExerciseScreen> {
  final _rows = <_SetRow>[];
  String _unit = 'kg';
  bool _filled = false;
  bool _changed = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _fill(PlanExercise item) {
    _unit = item.unit;
    _rows.addAll([for (final s in item.sets) _SetRow(s.weight, s.reps)]);
    if (_rows.isEmpty) _rows.add(_SetRow(0, 10));
    _filled = true;
  }

  void _edited([_]) => setState(() => _changed = true);

  void _setUnit(String unit) {
    if (unit == _unit) return;
    setState(() {
      // The numbers keep meaning the same weight: 40 kg becomes 88 lbs.
      for (final row in _rows) {
        final w = row.weightIn(_unit);
        if (w != null && w > 0) row.weight.text = kg(convertWeight(w, to: unit));
      }
      _unit = unit;
      _changed = true;
    });
  }

  void _addSet() {
    final last = _rows.last; // a new set starts as a copy of the one before
    setState(() {
      _rows.add(_SetRow(last.weightIn(_unit) ?? 0, last.repsValue ?? 10));
      _changed = true;
    });
  }

  // The cross on a set asks first, so a stray tap does not lose it.
  Future<void> _removeSet(int index) async {
    final row = _rows[index];
    final weight = row.weightIn(_unit);
    final reps = row.repsValue;
    final what = weight == null || reps == null
        ? ''
        : weight == 0
        ? ' ($reps reps)'
        : ' (${kg(weight)} ${unitLabel(_unit)} × $reps)';
    final sure = await confirm(
      context,
      title: 'Remove set ${index + 1}?',
      body: 'Set ${index + 1}$what will be removed from this exercise.',
      action: 'Remove',
    );
    if (!sure || !mounted || !_rows.contains(row)) return;
    setState(() {
      _rows.remove(row);
      _changed = true;
    });
    // After the frame: the text fields are still attached until it has been drawn.
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  bool get _valid => _rows.every((r) => r.weightIn(_unit) != null && r.repsValue != null);

  Future<void> _save() async {
    setState(() => _saving = true);
    final body = {
      'unit': _unit,
      'sets': [for (final r in _rows) PlanSet(r.weightIn(_unit)!, r.repsValue!).toJson()],
    };
    final worked = await runAction(
      context,
      () => ref.read(apiProvider).put('/plans/${widget.part}/exercises/${widget.id}', body: body),
      done: 'Saved.',
    );
    if (!mounted) return;
    if (worked) {
      ref.invalidate(planProvider(widget.part));
      FocusScope.of(context).unfocus();
    }
    setState(() {
      _saving = false;
      if (worked) _changed = false;
    });
  }

  Future<void> _remove(String name) async {
    final sure = await confirm(
      context,
      title: 'Remove $name?',
      body: 'It leaves your ${bodyParts[widget.part]!.toLowerCase()} plan with its sets.',
      action: 'Remove',
    );
    if (!sure || !mounted) return;
    final worked = await runAction(
      context,
      () => ref.read(apiProvider).delete('/plans/${widget.part}/exercises/${widget.id}'),
      done: '$name removed.',
    );
    if (worked && mounted) {
      ref.invalidate(planProvider(widget.part));
      ref.invalidate(planSummariesProvider);
      context.pop();
    }
  }

  Future<void> _leave() async {
    final leave = await confirm(
      context,
      title: 'Leave without saving?',
      body: 'Your changes to these sets will be lost.',
      action: 'Leave',
    );
    if (leave && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(planProvider(widget.part));
    final item = plan.value?.where((p) => p.id == widget.id).firstOrNull;
    if (!_filled && item != null) _fill(item);

    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(item?.exercise.name ?? ''),
          actions: [
            if (item != null)
              IconButton(
                tooltip: 'Remove from plan',
                icon: const Icon(Icons.delete_outline),
                onPressed: _saving ? null : () => _remove(item.exercise.name),
              ),
          ],
        ),
        body: item != null && _filled
            ? _body(context, item.exercise)
            : plan.hasError
            ? Center(
                child: ErrorRetry(error: plan.error!, onRetry: () => ref.invalidate(planProvider(widget.part))),
              )
            : plan.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const Center(child: Text('This exercise is no longer in your plan.')),
      ),
    );
  }

  Widget _body(BuildContext context, Exercise exercise) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(color: Hxvy.textMuted, letterSpacing: 0.8);
    return ListView(
      padding: pagePadding(context),
      children: [
        _Clip(exercise: exercise),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Text('Sets', style: theme.textTheme.titleMedium)),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'kg', label: Text('kg')),
                ButtonSegment(value: 'lb', label: Text('lbs')),
              ],
              selected: {_unit},
              showSelectedIcon: false,
              onSelectionChanged: (picked) => _setUnit(picked.first),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(width: 40, child: Text('SET', style: muted)),
            Expanded(child: Text('WEIGHT (${unitLabel(_unit).toUpperCase()})', style: muted)),
            const SizedBox(width: 12),
            Expanded(child: Text('REPS', style: muted)),
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Hxvy.border),
                      ),
                      child: Text('${i + 1}', style: theme.textTheme.labelMedium),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _rows[i].weight,
                    onChanged: _edited,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '0',
                      suffixText: unitLabel(_unit),
                      errorText: _rows[i].weightIn(_unit) == null ? '0 to ${kg(maxWeight(_unit))}' : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _rows[i].reps,
                    onChanged: _edited,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      suffixText: 'reps',
                      errorText: _rows[i].repsValue == null ? '1 to 1000' : null,
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: _rows.length > 1
                      ? IconButton(
                          tooltip: 'Remove set ${i + 1}',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => _removeSet(i),
                        )
                      : null,
                ),
              ],
            ),
          ),
        Row(
          children: [
            TextButton.icon(
              onPressed: _rows.length >= maxPlanSets ? null : _addSet,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add set'),
            ),
            const Spacer(),
            Muted('${_rows.length} of $maxPlanSets sets'),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving || !_changed || !_valid ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}

/// The looping clip, with what the exercise trains under it.
class _Clip extends StatelessWidget {
  const _Clip({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // "Lats, rhomboids" → Lats · Rhomboids, one chip each.
    final muscles = exercise.muscles
        .split(',')
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .map((m) => m[0].toUpperCase() + m.substring(1));
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Hxvy.border),
        gradient: const RadialGradient(
          center: Alignment(0, -0.2),
          radius: 0.9,
          colors: [Color(0xFF1C1C1C), Color(0xFF0E0E0E)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 230,
            child: Semantics(
              label: 'Animation of ${exercise.name}',
              child: ExerciseAnimation(motion: exercise.motion, equipment: exercise.equipment),
            ),
          ),
          const SizedBox(height: 12),
          Text('WORKS', style: theme.textTheme.labelSmall?.copyWith(color: Hxvy.textMuted, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in muscles)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Hxvy.border),
                  ),
                  child: Text(m, style: theme.textTheme.labelMedium),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
