import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session.dart';

/// Everything the app knows about the backend lives in this file. Like the web app,
/// it talks to ONE address, the gateway, which decides which service handles what.
///
/// Set the address when building: flutter run --dart-define=API_URL=http://192.168.1.5:8080
/// A real phone needs that (your Mac's address on the Wi-Fi). Without it:
///  - the Android emulator reaches the Mac at 10.0.2.2
///  - Chrome and the iOS simulator reach it at localhost
String apiBaseUrl() {
  const fromBuild = String.fromEnvironment('API_URL');
  if (fromBuild.isNotEmpty) return fromBuild;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8080';
  return 'http://localhost:8080';
}

/// Every error from the backend has this shape, so the screens only handle one kind.
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message, [this.details]);

  final int status; // 0 when the server could not be reached at all
  final String code;
  final String message;
  final Map<String, String>? details;

  /// A message for the screen, including what is wrong with each field.
  String get display {
    final problems = details;
    if (problems == null || problems.isEmpty) return message;
    return problems.entries.map((e) => '${e.key} ${e.value}').join('\n');
  }

  @override
  String toString() => display;
}

/// A readable message for any error.
String messageOf(Object error) => error is ApiException ? error.display : 'Something went wrong. Please try again.';

class ApiClient {
  /// Only tests pass [adapter], to answer requests without a real server.
  ApiClient(this._sessions, {HttpClientAdapter? adapter}) {
    final options = BaseOptions(
      baseUrl: '${apiBaseUrl()}/api/v1',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    );
    _plain = Dio(options);
    _dio = Dio(options);
    if (adapter != null) {
      _plain.httpClientAdapter = adapter;
      _dio.httpClientAdapter = adapter;
    }
    _dio.interceptors.add(InterceptorsWrapper(onRequest: _addToken, onError: _refreshOn401));
  }

  final SessionStore _sessions;
  late final Dio _dio;
  late final Dio _plain; // for the refresh call itself, so it cannot loop

  // Several requests can fail with 401 at the same moment. Refresh tokens work only
  // once, so they must all share a single refresh instead of racing.
  Future<bool>? _refreshing;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get<dynamic>(path, queryParameters: query));

  Future<dynamic> post(String path, {Object? body}) => _send(() => _dio.post<dynamic>(path, data: body));

  Future<dynamic> put(String path, {Object? body}) => _send(() => _dio.put<dynamic>(path, data: body));

  Future<dynamic> patch(String path, {Object? body}) => _send(() => _dio.patch<dynamic>(path, data: body));

  Future<dynamic> delete(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.delete<dynamic>(path, queryParameters: query));

  Future<dynamic> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final response = await call();
      return response.data;
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  ApiException _toApiException(DioException e) {
    final response = e.response;
    if (response == null) {
      return const ApiException(0, 'network_error', 'Cannot reach the server. Is the backend running?');
    }
    final data = response.data;
    if (data is Map) {
      final details = data['details'];
      return ApiException(
        response.statusCode ?? 0,
        (data['code'] ?? 'error') as String,
        (data['message'] ?? 'Request failed') as String,
        details is Map ? details.map((k, v) => MapEntry('$k', '$v')) : null,
      );
    }
    return ApiException(response.statusCode ?? 0, 'error', 'Request failed');
  }

  void _addToken(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _sessions.session?.access;
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  /// An expired access token is normal: quietly get a new one and repeat the request once.
  ///
  /// Only the code "unauthorized" means that. Any other 401 is about what the person typed,
  /// such as a wrong password when signing in or deleting the account. A new token would
  /// not fix that, it would only send the same password a second time.
  Future<void> _refreshOn401(DioException error, ErrorInterceptorHandler handler) async {
    final request = error.requestOptions;
    final data = error.response?.data;
    final tokenExpired = error.response?.statusCode == 401 && data is Map && data['code'] == 'unauthorized';
    if (!tokenExpired || request.extra['retried'] == true) {
      handler.next(error);
      return;
    }

    _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
    if (!await _refreshing!) {
      handler.next(error);
      return;
    }

    request.extra['retried'] = true;
    try {
      handler.resolve(await _dio.fetch<dynamic>(request));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<bool> _refresh() async {
    final session = _sessions.session;
    if (session == null) return false;
    try {
      final response = await _plain.post<dynamic>('/auth/refresh', data: {'refresh_token': session.refresh});
      await _sessions.save(Session.fromAuthResponse(response.data as Map<String, dynamic>));
      return true;
    } on DioException catch (e) {
      // Only a definite "no" signs the person out. A network problem keeps the session.
      if (e.response?.statusCode == 401) await _sessions.save(null);
      return false;
    }
  }
}

/// Filled in by main() once the session has been read from secure storage.
final sessionStoreProvider = Provider<SessionStore>((ref) => throw UnimplementedError());

final apiProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(sessionStoreProvider)));
