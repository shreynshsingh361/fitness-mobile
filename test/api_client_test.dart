import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fitness_mobile/core/api.dart';
import 'package:fitness_mobile/core/session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

ResponseBody answer(int status, Map<String, dynamic> body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

// A function, because a response body can only be read once.
ResponseBody expired() => answer(401, {'code': 'unauthorized', 'message': 'missing, invalid or expired access token'});

/// Answers requests the way a test says to and remembers what it was asked.
class FakeServer implements HttpClientAdapter {
  FakeServer(this.respond);

  final ResponseBody Function(RequestOptions request) respond;
  final requests = <RequestOptions>[];

  List<String> get paths => requests.map((r) => r.path).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late SessionStore sessions;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    sessions = SessionStore();
    await sessions.save(
      const Session(
        access: 'old',
        refresh: 'r1',
        user: User(id: 'u1', name: 'Asha', email: 'asha@example.test'),
      ),
    );
  });

  /// A server where only the new token works and a refresh always succeeds.
  ResponseBody healthyServer(RequestOptions request) {
    if (request.path == '/auth/refresh') {
      return answer(200, {
        'user': {'id': 'u1', 'name': 'Asha', 'email': 'asha@example.test'},
        'access_token': 'new',
        'refresh_token': 'r2',
      });
    }
    return request.headers['Authorization'] == 'Bearer new' ? answer(200, {'ok': true}) : expired();
  }

  test('an expired token is replaced quietly and the request repeated', () async {
    final server = FakeServer(healthyServer);
    final api = ApiClient(sessions, adapter: server);

    final result = await api.get('/things');

    expect(result, {'ok': true});
    expect(server.paths, ['/things', '/auth/refresh', '/things']);
    expect(sessions.session?.access, 'new');
    expect(sessions.session?.refresh, 'r2');
  });

  test('requests failing together share one refresh, because a refresh token works only once', () async {
    final server = FakeServer(healthyServer);
    final api = ApiClient(sessions, adapter: server);

    final results = await Future.wait([api.get('/a'), api.get('/b'), api.get('/c')]);

    expect(results, everyElement({'ok': true}));
    expect(server.paths.where((p) => p == '/auth/refresh'), hasLength(1));
  });

  test('a wrong password is not mistaken for an expired token', () async {
    final server = FakeServer((_) => answer(401, {'code': 'invalid_password', 'message': 'the password is incorrect'}));
    final api = ApiClient(sessions, adapter: server);

    await expectLater(
      api.post('/account/delete', body: {'password': 'x'}),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'invalid_password')),
    );

    expect(server.paths, ['/account/delete'], reason: 'the password must be sent only once');
    expect(sessions.session?.access, 'old', reason: 'the token was fine, so it must not change');
  });

  test('a wrong login does not try a refresh either', () async {
    final server = FakeServer(
      (_) => answer(401, {'code': 'invalid_credentials', 'message': 'email or password is incorrect'}),
    );
    final api = ApiClient(sessions, adapter: server);

    await expectLater(api.post('/auth/login'), throwsA(isA<ApiException>()));

    expect(server.paths, ['/auth/login']);
  });

  test('a request that still fails with the new token is not repeated forever', () async {
    final server = FakeServer((request) => request.path == '/auth/refresh' ? healthyServer(request) : expired());
    final api = ApiClient(sessions, adapter: server);

    await expectLater(api.get('/things'), throwsA(isA<ApiException>()));

    expect(server.paths, ['/things', '/auth/refresh', '/things']);
  });

  test('a refused refresh signs the person out', () async {
    final server = FakeServer(
      (request) => request.path == '/auth/refresh'
          ? answer(401, {'code': 'invalid_refresh_token', 'message': 'refresh token is invalid'})
          : expired(),
    );
    final api = ApiClient(sessions, adapter: server);

    await expectLater(api.get('/things'), throwsA(isA<ApiException>()));

    expect(sessions.signedIn, isFalse);
  });

  test('a network problem during the refresh keeps the login', () async {
    final server = FakeServer((request) {
      if (request.path == '/auth/refresh') {
        throw DioException(requestOptions: request, type: DioExceptionType.connectionError);
      }
      return expired();
    });
    final api = ApiClient(sessions, adapter: server);

    await expectLater(api.get('/things'), throwsA(isA<ApiException>()));

    expect(sessions.signedIn, isTrue);
  });

  test('an unreachable server gives a clear message', () async {
    final server = FakeServer(
      (request) => throw DioException(requestOptions: request, type: DioExceptionType.connectionError),
    );
    final api = ApiClient(sessions, adapter: server);

    await expectLater(
      api.get('/things'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 0).having((e) => e.code, 'code', 'network_error')),
    );
  });

  test('field problems from the server are shown together', () async {
    final server = FakeServer(
      (_) => answer(422, {
        'code': 'validation_failed',
        'message': 'invalid input',
        'details': {'steps': 'must be at most 100000'},
      }),
    );
    final api = ApiClient(sessions, adapter: server);

    await expectLater(
      api.post('/steps/sync'),
      throwsA(isA<ApiException>().having((e) => e.display, 'display', 'steps must be at most 100000')),
    );
  });
}
