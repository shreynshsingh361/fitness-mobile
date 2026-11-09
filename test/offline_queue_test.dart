import 'package:fitness_mobile/core/api.dart';
import 'package:fitness_mobile/core/offline_queue.dart';
import 'package:fitness_mobile/core/session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// A server that can be switched off, and that records what reached it.
class _Api extends ApiClient {
  _Api(super.sessions);

  Object? failWith; // thrown by every call while set
  final calls = <String>[];
  final bodies = <Map<String, dynamic>?>[];

  void _call(String what, Map<String, dynamic>? body) {
    if (failWith != null) throw failWith!;
    calls.add(what);
    bodies.add(body);
  }

  @override
  Future<dynamic> post(String path, {Object? body}) async => _call('post $path', body as Map<String, dynamic>?);

  @override
  Future<dynamic> delete(String path, {Map<String, dynamic>? query}) async => _call('delete $path', query);
}

const _offline = ApiException(0, 'network_error', 'Cannot reach the server.');

PendingOp _food(String id, {String date = '2026-11-09'}) => PendingOp(
  id: id,
  kind: 'food',
  method: 'post',
  path: '/diary',
  label: 'Idli (breakfast)',
  date: date,
  body: {'client_op_id': id, 'food_id': 'f1', 'meal': 'breakfast', 'servings': 2, 'eaten_on': date},
);

PendingOp _water(String id, int ml, {String date = '2026-11-09'}) => PendingOp(
  id: id,
  kind: 'water',
  method: ml > 0 ? 'post' : 'delete',
  path: '/water',
  label: '${ml > 0 ? '+' : '−'}250 ml water',
  date: date,
  deltaMl: ml,
  body: ml > 0 ? {'amount_ml': 250, 'date': date, 'client_op_id': id} : null,
  query: ml > 0 ? null : {'date': date, 'amount_ml': 250, 'client_op_id': id},
);

void main() {
  late SessionStore sessions;
  late _Api api;
  String? user;

  OfflineQueue newQueue() => OfflineQueue(api, () => user);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    sessions = SessionStore();
    api = _Api(sessions);
    user = 'asha';
  });

  test('with internet it is sent at once and nothing is kept', () async {
    final queue = newQueue();
    expect(await queue.send(_food('a')), isTrue);
    expect(api.calls, ['post /diary']);
    expect(queue.hasPending, isFalse);
  });

  test('without internet it is kept, and the same request is sent later with the same id', () async {
    final queue = newQueue();
    api.failWith = _offline;
    expect(await queue.send(_food('a')), isFalse);
    expect(queue.pending.single.label, 'Idli (breakfast)');
    expect(api.calls, isEmpty);

    expect(await queue.flush(), 0, reason: 'still offline: nothing goes, nothing is lost');
    expect(queue.hasPending, isTrue);

    api.failWith = null;
    expect(await queue.flush(), 1);
    expect(queue.hasPending, isFalse);
    expect(api.bodies.single?['client_op_id'], 'a', reason: 'the server tells a repeat by this id');
    expect(api.bodies.single?['servings'], 2);
  });

  test('what was kept survives closing the app', () async {
    api.failWith = _offline;
    await newQueue().send(_food('a'));
    await newQueue().send(_water('b', 250));

    final reopened = newQueue();
    await reopened.load();
    expect(reopened.pending.map((o) => o.id), ['a', 'b']);

    api.failWith = null;
    await reopened.flush();
    expect(api.calls, ['post /diary', 'post /water']);
    expect(await newQueue().flush(), 0, reason: 'sent changes are forgotten, not sent again');
  });

  test('changes go in the order they were made, also when the connection comes back between them', () async {
    final queue = newQueue();
    api.failWith = _offline;
    await queue.send(_water('a', 250));
    api.failWith = null; // back online, and a new tap arrives while the first still waits
    expect(await queue.send(_water('b', -250)), isTrue, reason: 'the waiting one is sent first, then this');
    expect(api.calls, ['post /water', 'delete /water']);
  });

  test('a refusal for good is not kept: it is reported and the rest carries on', () async {
    final queue = newQueue();
    api.failWith = _offline;
    await queue.send(_food('a'));
    await queue.send(_water('b', 250));

    api.failWith = null;
    final real = _Api(sessions);
    final refusing = _RefuseFirst(real);
    final q2 = OfflineQueue(refusing, () => user);
    await q2.load();
    expect(await q2.flush(), 1, reason: 'the water went through');
    expect(q2.hasPending, isFalse);
    expect(q2.problems.single, contains('Idli (breakfast)'));
    expect(q2.problems.single, contains('That food no longer exists'));
    q2.clearProblems();
    expect(q2.problems, isEmpty);
  });

  test('a refusal when sending directly is thrown, not kept', () async {
    final queue = newQueue();
    api.failWith = const ApiException(422, 'validation_error', 'Servings are too many.');
    await expectLater(queue.send(_food('a')), throwsA(isA<ApiException>()));
    expect(queue.hasPending, isFalse);
  });

  test('an expired login or a server hiccup keeps the change instead of losing it', () async {
    for (final status in [401, 429, 502, 503, 504]) {
      final queue = newQueue();
      api.failWith = ApiException(status, 'x', 'later');
      expect(await queue.send(_food('s$status')), isFalse, reason: 'status $status');
      await queue.flush();
      expect(queue.hasPending, isTrue, reason: 'status $status must stay waiting');
      FlutterSecureStorage.setMockInitialValues({});
    }
    expect(isRetryable(const ApiException(400, 'x', 'no')), isFalse);
    expect(isRetryable(const ApiException(404, 'x', 'no')), isFalse);
    expect(isRetryable(const ApiException(422, 'x', 'no')), isFalse);
    expect(isRetryable(StateError('bug')), isFalse);
  });

  test('another person signing in on the phone does not send, or see, the first person\'s changes', () async {
    api.failWith = _offline;
    await newQueue().send(_food('a'));
    api.failWith = null;

    user = 'ravi';
    final theirs = newQueue();
    await theirs.load();
    expect(theirs.hasPending, isFalse);
    expect(await theirs.flush(), 0);
    expect(api.calls, isEmpty);
  });

  test('the water waiting for a day adds up, for showing it right away', () async {
    final queue = newQueue();
    api.failWith = _offline;
    await queue.send(_water('a', 250));
    await queue.send(_water('b', 250));
    await queue.send(_water('c', -250));
    await queue.send(_water('d', 250, date: '2026-11-08'));
    expect(queue.pendingWaterMl('2026-11-09'), 250);
    expect(queue.pendingWaterMl('2026-11-08'), 250);
    expect(queue.pendingWaterMl('2026-11-07'), 0);
    expect(queue.pendingFood('2026-11-09'), isEmpty);
    await queue.send(_food('f'));
    expect(queue.pendingFood('2026-11-09').single.id, 'f');
  });
}

/// Refuses the first request (a food that was deleted meanwhile) and passes the rest to [_inner].
class _RefuseFirst extends ApiClient {
  _RefuseFirst(this._inner) : super(SessionStore());

  final _Api _inner;
  var _first = true;

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    if (_first) {
      _first = false;
      throw const ApiException(404, 'not_found', 'That food no longer exists.');
    }
    return _inner.post(path, body: body);
  }
}
