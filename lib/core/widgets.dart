import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'palette.dart';

/// Small building blocks shared by every screen.

/// Padding for a scrolling page. The glass bottom bar floats over the content, so the
/// end of the page gets extra room and the last card can still scroll clear of it.
EdgeInsets pagePadding(BuildContext context, {double top = 16, double bottom = 16}) =>
    EdgeInsets.fromLTRB(16, top, 16, bottom + MediaQuery.paddingOf(context).bottom);

/// A card that lifts and glows white while it is hovered (with a mouse) or pressed (on a
/// touch screen, which has no hover). The same effect as this CSS:
///
///     .card       { background: #151515; border: 1px solid #303030; border-radius: 16px;
///                   transition: all 0.35s ease; }
///     .card:hover { background: #222222; border-color: #ffffff; transform: translateY(-5px);
///                   box-shadow: 0 12px 35px rgba(255, 255, 255, 0.15); }
class GlowCard extends StatefulWidget {
  const GlowCard({super.key, required this.child});

  final Widget child;

  @override
  State<GlowCard> createState() => _GlowCardState();
}

class _GlowCardState extends State<GlowCard> {
  bool _hovered = false;
  bool _pressed = false;

  void _set({bool? hovered, bool? pressed}) => setState(() {
    _hovered = hovered ?? _hovered;
    _pressed = pressed ?? _pressed;
  });

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _pressed;
    final shape = BorderRadius.circular(16);
    return MouseRegion(
      onEnter: (_) => _set(hovered: true),
      onExit: (_) => _set(hovered: false),
      child: Listener(
        onPointerDown: (_) => _set(pressed: true),
        onPointerUp: (_) => _set(pressed: false),
        onPointerCancel: (_) => _set(pressed: false),
        child: AnimatedContainer(
          duration: Hxvy.lift,
          curve: Curves.ease,
          transform: Matrix4.translationValues(0, active ? -5 : 0, 0),
          decoration: BoxDecoration(
            color: active ? Hxvy.cardActive : Hxvy.card,
            borderRadius: shape,
            border: Border.all(color: active ? Hxvy.accent : Hxvy.border),
            boxShadow: [
              BoxShadow(
                color: Hxvy.accent.withValues(alpha: active ? 0.15 : 0),
                blurRadius: 35,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          // Lets buttons and list rows inside show their ripple, kept within the corners.
          child: Material(
            type: MaterialType.transparency,
            borderRadius: shape,
            clipBehavior: Clip.antiAlias,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Height of the glass bottom bar, and its gap above the phone's bottom edge.
const glassBarHeight = 68.0;
const _glassBarGap = 8.0;

/// Keeps a floating button above the glass bottom bar. A Scaffold already keeps it 16
/// above the phone's own bottom edge, but knows nothing of a bar floating over the page.
class AboveBar extends StatelessWidget {
  const AboveBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The bar sits on the phone's own navigation, which is taller with the three buttons than
    // with gestures. Pages under the shell no longer see that edge in their MediaQuery, so it
    // is read from the window itself. The Scaffold puts the button 16 above the view padding
    // the page sees; lift it from there to 12 above the top of the bar.
    final view = View.of(context);
    final edge = view.viewPadding.bottom / view.devicePixelRatio;
    final barTop = math.max(edge, _glassBarGap) + glassBarHeight;
    final lift = math.max(0.0, barTop + 12 - (MediaQuery.viewPaddingOf(context).bottom + 16));
    return Padding(
      padding: EdgeInsets.only(bottom: lift),
      child: child,
    );
  }
}

/// A see-through bar in the style Apple calls Liquid Glass: whatever scrolls behind it is
/// blurred, and the glass is a little brighter at the top, the way light falls on it.
class GlassBar extends StatelessWidget {
  const GlassBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(28);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: _glassBarGap),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: ClipRRect(
          borderRadius: shape,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: shape,
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.04)],
                ),
              ),
              // The SafeArea above already keeps clear of the phone's own bottom edge.
              child: MediaQuery.removePadding(context: context, removeBottom: true, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.action, required this.child});

  final String? title;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlowCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null || action != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (title ?? '').toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    ?action,
                  ],
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

class Stat extends StatelessWidget {
  const Stat({super.key, required this.label, required this.value, this.hint});

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: muted),
        Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        if (hint != null) Text(hint!, style: muted),
      ],
    );
  }
}

/// A ring that fills clockwise as [fraction] goes from 0 to 1, with [child] in the middle:
/// the calories of the day, or its steps, against their goal.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.fraction,
    required this.child,
    this.color = Hxvy.accent,
    this.size = 150,
    this.semanticLabel,
  });

  final double fraction;
  final Widget child;
  final Color color;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(fraction: fraction.clamp(0, 1).toDouble(), color: color),
        child: Center(child: child),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final arc = (Offset.zero & size).deflate(stroke / 2);
    final track = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, 0, math.pi * 2, false, track);
    if (fraction > 0) canvas.drawArc(arc, -math.pi / 2, math.pi * 2 * fraction, false, fill);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.color != color;
}

class GoalBar extends StatelessWidget {
  const GoalBar({super.key, required this.value, required this.label, this.color});

  final double value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    value: '${(value * 100).round()}%',
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(value: value, minHeight: 10, color: color),
    ),
  );
}

class Muted extends StatelessWidget {
  const Muted(this.text, {super.key, this.textAlign});

  final String text;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      textAlign: textAlign,
      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

/// A highlighted note, for something the person should notice before reading on.
class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colors.secondaryContainer, borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(messageOf(error), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}

/// Shows data once it has loaded, a spinner before that and an error with a retry
/// button if it failed. While refreshing, the old data stays on screen.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.onRetry, required this.builder});

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) => value.when(
    data: builder,
    loading: () => const Padding(
      padding: EdgeInsets.all(32),
      child: Center(child: CircularProgressIndicator()),
    ),
    error: (error, _) => ErrorRetry(error: error, onRetry: onRetry),
  );
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Runs an API call from a button: shows [done] if it worked and the server's message
/// if it did not. Returns whether it worked.
Future<bool> runAction(BuildContext context, Future<dynamic> Function() action, {String? done}) async {
  try {
    await action();
    if (done != null && context.mounted) showMessage(context, done);
    return true;
  } catch (error) {
    if (context.mounted) showMessage(context, messageOf(error));
    return false;
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(action)),
      ],
    ),
  );
  return answer ?? false;
}

/// Asks for one line of text or a number. Returns null if cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String? label,
  String initial = '',
  TextInputType? keyboard,
  String action = 'Save',
  bool obscure = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _AskTextDialog(
    title: title,
    label: label,
    initial: initial,
    keyboard: keyboard,
    action: action,
    obscure: obscure,
  ),
);

// The controller belongs to this widget so it is only thrown away once the dialog has
// finished animating out. Disposing it when showDialog returns would be too early.
class _AskTextDialog extends StatefulWidget {
  const _AskTextDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.keyboard,
    required this.action,
    required this.obscure,
  });

  final String title;
  final String? label;
  final String initial;
  final TextInputType? keyboard;
  final String action;
  final bool obscure;

  @override
  State<_AskTextDialog> createState() => _AskTextDialogState();
}

class _AskTextDialogState extends State<_AskTextDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: widget.keyboard,
      obscureText: widget.obscure,
      decoration: InputDecoration(labelText: widget.label),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: Text(widget.action)),
    ],
  );
}
