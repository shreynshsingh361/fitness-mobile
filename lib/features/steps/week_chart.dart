import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/palette.dart';
import 'steps_api.dart';

/// Daily steps as bars with the goal as a dashed line. One series, so no legend: the
/// card's title names it. Exact numbers appear on touch, and the same data opens as a
/// table for anyone who cannot use the chart.
///
/// White bars on the near-black card: far above the 3:1 contrast that shapes need.
class WeekChart extends StatelessWidget {
  const WeekChart({super.key, required this.history, required this.today});

  final StepsHistory history;
  final String today;

  static const _barColor = Hxvy.accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final labelStyle = theme.textTheme.bodySmall?.copyWith(color: muted);
    final days = history.days;
    final top = max(history.goal, days.fold<int>(0, (m, d) => max(m, d.steps))) * 1.15;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Above the chart, not on the line: a label inside the plot would run into tall bars.
        Text('Dashed line: your goal of ${number(history.goal)} steps', style: labelStyle),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              maxY: top,
              minY: 0,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(
                show: true,
                border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final day = days[value.toInt()];
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          weekday(day.date),
                          style: labelStyle?.copyWith(
                            fontWeight: day.date == today ? FontWeight.bold : null,
                            color: day.date == today ? theme.colorScheme.onSurface : muted,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(y: history.goal.toDouble(), color: muted, strokeWidth: 1, dashArray: const [4, 4]),
                ],
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipColor: (_) => theme.colorScheme.surfaceContainerHighest,
                  getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                    '${number(rod.toY)} steps\n${shortDate(days[group.x].date)}',
                    TextStyle(color: theme.colorScheme.onSurface, fontSize: 12),
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < days.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: days[i].steps.toDouble(),
                        width: 22,
                        color: _barColor,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Show as table', style: labelStyle),
          children: [
            for (final d in days)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(shortDate(d.date))),
                    Expanded(child: Text(number(d.steps))),
                    Expanded(child: Text(d.goalMet ? 'goal reached' : 'not reached')),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
