import 'package:fitness_mobile/services/health/step_sources.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const samsung = 'com.sec.android.app.shealth';
  const fit = 'com.google.android.apps.fitness';

  group('pickSource', () {
    test('the source with the most steps wins', () {
      expect(pickSource({samsung: 41000, fit: 12000, phoneSensorId: 300}), samsung);
      expect(pickSource({samsung: 0, fit: 9000}), fit);
    });

    test('nobody has steps: nothing is chosen', () {
      expect(pickSource({}), isNull);
      expect(pickSource({samsung: 0, fit: 0, phoneSensorId: 0}), isNull);
    });

    test('a chosen source is kept while it still has steps, even if another passes it', () {
      expect(pickSource({samsung: 500, fit: 9000}, current: samsung), samsung);
    });

    test('a chosen source that has gone quiet is replaced by the best one', () {
      expect(pickSource({samsung: 0, fit: 9000, phoneSensorId: 40}, current: samsung), fit);
      expect(pickSource({fit: 9000}, current: samsung), fit, reason: 'it is not even listed any more');
      expect(pickSource({samsung: 0}, current: samsung), isNull);
    });

    test('a tie goes to the same source every time', () {
      expect(pickSource({samsung: 5000, fit: 5000}), fit);
      expect(pickSource({fit: 5000, samsung: 5000}), fit);
    });
  });

  test('names and backend labels', () {
    expect(sourceName(samsung), 'Samsung Health');
    expect(sourceName(fit), 'Google Fit');
    expect(sourceName(phoneSensorId), "the phone's step sensor");
    expect(sourceName('com.acme.stepper'), 'Stepper', reason: 'an unknown app shows its last word');
    expect(sourceName(''), 'Health Connect', reason: 'never a blank name');
    expect(sourceName('unknown'), 'Health Connect');
    expect(backendSource(samsung), 'samsung');
    expect(backendSource(phoneSensorId), 'phone');
    expect(backendSource(fit), 'health_connect');
    expect(backendSource('com.acme.stepper'), 'health_connect');
  });

  test('the choice is remembered for one person only', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final choice = SourceChoice();
    expect(await choice.read('u1'), isNull);
    await choice.write('u1', samsung);
    expect(await SourceChoice().read('u1'), samsung);
    expect(await SourceChoice().read('u2'), isNull, reason: 'another person on this phone chooses for themselves');
    await choice.write('u1', '');
    expect(await choice.read('u1'), isNull, reason: 'a blank choice is no choice');
    await choice.clear();
    expect(await choice.read('u1'), isNull);
  });
}
