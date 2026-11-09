import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';
import '../core/palette.dart';
import 'widgets.dart';

/// What a calendar shows under each day of a month ("2026-11"): the figure for each day
/// that has one, such as the calories eaten or the steps walked.
typedef MonthFigures = AsyncValue<Map<String, int>> Function(WidgetRef ref, String month);

/// What the calendar shows and how, so the Food and Steps tabs share one.
class DayCalendar {
  const DayCalendar({
    required this.figures,
    required this.unit,
    required this.nothing,
    required this.legend,
    required this.standsOut,
    this.outColor = Hxvy.accent,
  });

  /// The figures of a month. Watched, so the calendar redraws when they arrive.
  final MonthFigures figures;

  /// "kcal" or "steps", for a screen reader.
  final String unit;

  /// What a screen reader says for a day without a figure.
  final String nothing;

  /// The line under the calendar.
  final String legend;

  /// Whether a day's figure is worth marking (over the calorie goal, or the steps goal met).
  final bool Function(int figure) standsOut;

  /// The colour of a figure that stands out.
  final Color outColor;
}

/// A calendar of months with a figure written under each day. Returns the day picked, as
/// "2026-11-09", or null if it was dismissed.
Future<String?> pickDay(BuildContext context, {required String selected, required DayCalendar calendar}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true, // covers the glass bottom bar too
      builder: (_) => _DaySheet(selected: selected, calendar: calendar),
    );

class _DaySheet extends ConsumerStatefulWidget {
  const _DaySheet({required this.selected, required this.calendar});

  final String selected;
  final DayCalendar calendar;

  @override
  ConsumerState<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends ConsumerState<_DaySheet> {
  static final _first = DateTime(2020);
  late DateTime _month = DateTime(parseDay(widget.selected).year, parseDay(widget.selected).month);

  // Tomorrow is the furthest ahead a day can be picked, as it always was.
  DateTime get _last => DateTime.now().add(const Duration(days: 1));

  bool get _canGoBack => _month.isAfter(_first);
  bool get _canGoForward => DateTime(_month.year, _month.month + 1).isBefore(_last);

  void _move(int months) => setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthKey = DateFormat('yyyy-MM').format(_month);
    final calendar = widget.calendar;
    final figures = calendar.figures(ref, monthKey);
    final byDay = figures.value ?? const <String, int>{};
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    // Weeks start on Monday: DateTime's Monday is 1, so the first day sits that far from the left.
    final blanks = DateTime(_month.year, _month.month).weekday - 1;
    final today = todayKey();
    final muted = theme.textTheme.labelSmall?.copyWith(color: Hxvy.textMuted);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: _canGoBack ? () => _move(-1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    DateFormat('MMMM y').format(_month),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: _canGoForward ? () => _move(1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final letter in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                  Expanded(
                    child: Center(child: Text(letter, style: muted)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.78,
              children: [
                for (var i = 0; i < blanks; i++) const SizedBox.shrink(),
                for (var day = 1; day <= daysInMonth; day++)
                  _DayCell(
                    date: dayKey(DateTime(_month.year, _month.month, day)),
                    day: day,
                    figure: byDay[dayKey(DateTime(_month.year, _month.month, day))],
                    calendar: calendar,
                    selected: dayKey(DateTime(_month.year, _month.month, day)) == widget.selected,
                    isToday: dayKey(DateTime(_month.year, _month.month, day)) == today,
                    enabled: !DateTime(_month.year, _month.month, day).isAfter(_last),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: figures.hasError
                  ? Muted('Could not load this month.')
                  : Muted(calendar.legend, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.day,
    required this.figure,
    required this.calendar,
    required this.selected,
    required this.isToday,
    required this.enabled,
  });

  final String date;
  final int day;
  final int? figure;
  final DayCalendar calendar;
  final bool selected;
  final bool isToday;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = figure;
    final out = value != null && calendar.standsOut(value);
    final textColor = enabled ? Hxvy.text : Hxvy.textMuted.withValues(alpha: 0.4);
    // On the white selected day the figure is black, unless it is red, which still reads.
    final figureColor = out ? (selected && calendar.outColor == Hxvy.accent ? Hxvy.onButton : calendar.outColor) : null;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        button: true,
        label: '$day ${value == null ? calendar.nothing : '${number(value)} ${calendar.unit}'}',
        child: InkWell(
          onTap: enabled ? () => Navigator.pop(context, date) : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: selected ? Hxvy.accent : null,
              border: isToday && !selected ? Border.all(color: Hxvy.accent) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: selected ? Hxvy.onButton : textColor,
                    fontWeight: selected || isToday ? FontWeight.w700 : null,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value == null ? ' ' : number(value),
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: figureColor ?? (selected ? Hxvy.onButton : Hxvy.textMuted),
                      fontWeight: out ? FontWeight.w700 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
