import 'package:intl/intl.dart';

/// Dates go to the API as YYYY-MM-DD in the USER'S local time zone, because each
/// person's day ends at their own midnight and the server cannot know where they are.
String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

String todayKey() => dayKey(DateTime.now());

DateTime parseDay(String day) => DateTime.parse('${day}T00:00:00');

/// "2026-11-07" -> "7 Nov"
String shortDate(String day) => DateFormat('d MMM').format(parseDay(day));

/// "2026-11-07" -> "Sat"
String weekday(String day) => DateFormat('E').format(parseDay(day));

/// A time for chat or an inbox: just the time today, otherwise with the date.
String moment(String iso) {
  final d = DateTime.parse(iso).toLocal();
  final time = DateFormat.jm().format(d);
  return dayKey(d) == todayKey() ? time : '${DateFormat('d MMM').format(d)}, $time';
}

/// 12345 -> "12,345"
String number(num n) => NumberFormat.decimalPattern('en_US').format(n.round());

/// 60 -> "60", 62.5 -> "62.5"
String kg(num n) => n == n.roundToDouble() ? '${n.round()}' : n.toStringAsFixed(1);

/// 1 -> "1 day", 3 -> "3 days"
String days(int count) => '$count ${count == 1 ? 'day' : 'days'}';

/// A fraction from 0 to 1 for a progress bar.
double fraction(num value, num goal) => goal <= 0 ? 0 : (value / goal).clamp(0, 1).toDouble();

/// Invite links and codes are both accepted when pasted: keep what is after the last "/".
String codeFromPaste(String text) => text.trim().split('/').last;

/// The first word of a name with a capital first letter, whatever case it was typed in:
/// "shreyansh singh" -> "Shreyansh". An empty name stays empty.
String firstName(String fullName) {
  final first = fullName.trim().split(RegExp(r'\s+')).first;
  if (first.isEmpty) return '';
  final letters = first.runes.toList();
  return String.fromCharCode(letters.first).toUpperCase() + String.fromCharCodes(letters.skip(1));
}

/// The greeting for the time of day on the phone's own clock:
/// 5:00–11:59 morning, 12:00–16:59 afternoon, 17:00–20:59 evening, 21:00–4:59 night.
String greeting(DateTime now) {
  final hour = now.hour;
  if (hour >= 5 && hour < 12) return 'Morning';
  if (hour >= 12 && hour < 17) return 'Afternoon';
  if (hour >= 17 && hour < 21) return 'Evening';
  return 'Night';
}
