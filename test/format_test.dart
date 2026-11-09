import 'package:fitness_mobile/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a day key is the local date with leading zeros', () {
    expect(dayKey(DateTime(2026, 3, 7, 23, 59)), '2026-03-07');
  });

  test('dates read the way people say them', () {
    expect(shortDate('2026-11-07'), '7 Nov');
    expect(weekday('2026-11-07'), 'Sat');
  });

  test('numbers get separators and are rounded', () {
    expect(number(12345), '12,345');
    expect(number(12345.6), '12,346');
    expect(number(0), '0');
  });

  test('weights only show a decimal when there is one', () {
    expect(kg(60), '60');
    expect(kg(60.0), '60');
    expect(kg(62.5), '62.5');
  });

  test('day counts read correctly', () {
    expect(days(0), '0 days');
    expect(days(1), '1 day');
    expect(days(3), '3 days');
  });

  test('a progress fraction stays between 0 and 1', () {
    expect(fraction(5000, 10000), 0.5);
    expect(fraction(15000, 10000), 1);
    expect(fraction(0, 10000), 0);
    expect(fraction(5, 0), 0); // no goal must not divide by zero
  });

  test('a pasted invite can be a bare code or a whole link', () {
    expect(codeFromPaste('  abc123  '), 'abc123');
    expect(codeFromPaste('http://localhost:3000/join/friend/abc123'), 'abc123');
  });

  test('the first word of the name gets a capital letter', () {
    expect(firstName('shreyansh singh'), 'Shreyansh');
    expect(firstName('  asha rao '), 'Asha');
    expect(firstName('ASHA'), 'ASHA', reason: 'only the first letter is changed');
    expect(firstName('éva'), 'Éva');
    expect(firstName('priya'), 'Priya');
    expect(firstName(''), '');
    expect(firstName('   '), '');
  });

  test('the greeting follows the time of day', () {
    String at(int hour, [int minute = 0]) => greeting(DateTime(2026, 11, 8, hour, minute));
    expect(at(4, 59), 'Night');
    expect(at(5), 'Morning');
    expect(at(11, 59), 'Morning');
    expect(at(12), 'Afternoon');
    expect(at(16, 59), 'Afternoon');
    expect(at(17), 'Evening');
    expect(at(20, 59), 'Evening');
    expect(at(21), 'Night');
    expect(at(0), 'Night');
  });
}
