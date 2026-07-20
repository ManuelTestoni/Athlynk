import 'dart:convert';
import 'dart:typed_data';

import 'package:athlynk/core/network/api_client.dart';
import 'package:athlynk/core/network/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal in-memory adapter so the retry/error-mapping contract can be
/// asserted without a live backend.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  /// (requestNumber, options) → response
  final ResponseBody Function(int attempt, RequestOptions options) handler;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    return handler(calls, options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, int status) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

ApiClient _clientWith(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(
    responseType: ResponseType.bytes,
    validateStatus: (_) => true,
  ))..httpClientAdapter = adapter;
  return ApiClient(dio: dio, baseUrl: 'https://test.local');
}

void main() {
  group('ApiClient', () {
    test('attaches the bearer token when one is set', () async {
      String? seenAuth;
      final adapter = _FakeAdapter((_, options) {
        seenAuth = options.headers['Authorization'] as String?;
        return _json({'ok': true}, 200);
      });
      final client = _clientWith(adapter)..token = 'tok-123';

      await client.requestAny('/api/v1/me');

      expect(seenAuth, 'Bearer tok-123');
    });

    test('retries twice on 5xx, then succeeds', () async {
      final adapter = _FakeAdapter((attempt, _) =>
          attempt < 3 ? _json({'error': 'boom'}, 503) : _json({'ok': 1}, 200));
      final client = _clientWith(adapter);

      final res = await client.requestAny('/api/v1/workouts');

      expect(adapter.calls, 3); // initial + 2 retries
      expect((res as Map)['ok'], 1);
    });

    test('gives up after 2 retries and maps to ApiHttpException', () async {
      final adapter = _FakeAdapter((_, _) => _json({'error': 'down'}, 500));
      final client = _clientWith(adapter);

      await expectLater(
        client.requestAny('/api/v1/workouts'),
        throwsA(isA<ApiHttpException>()
            .having((e) => e.statusCode, 'statusCode', 500)),
      );
      expect(adapter.calls, 3);
    });

    test('does not retry a 401 and maps the credentials message', () async {
      final adapter = _FakeAdapter((_, _) => _json({'error': 'bad'}, 401));
      final client = _clientWith(adapter);

      try {
        await client.requestAny('/api/v1/auth/login', method: 'POST');
        fail('should have thrown');
      } on ApiHttpException catch (e) {
        expect(e.statusCode, 401);
        expect(e.userMessage, 'Email o password errati.');
      }
      expect(adapter.calls, 1);
    });

    test('exposes the server error code for the 403 access gates', () async {
      final adapter =
          _FakeAdapter((_, _) => _json({'error': 'access_blocked'}, 403));
      final client = _clientWith(adapter);

      try {
        await client.requestAny('/api/v1/workouts');
        fail('should have thrown');
      } on ApiHttpException catch (e) {
        expect(e.errorCode, 'access_blocked');
        expect(e.userMessage, 'Si è verificato un errore. Riprova.');
      }
    });

    test('maps transport failures to the connection message', () async {
      final adapter = _FakeAdapter((_, options) => throw DioException(
          requestOptions: options, type: DioExceptionType.connectionError));
      final client = _clientWith(adapter);

      try {
        await client.requestAny('/api/v1/me');
        fail('should have thrown');
      } on ApiTransportException catch (e) {
        expect(e.userMessage,
            'Problema di connessione. Controlla la rete e riprova.');
      }
      expect(adapter.calls, 3); // transport errors retry too
    });

    test('parses SSE data frames', () async {
      final adapter = _FakeAdapter((_, _) => ResponseBody.fromString(
            'data: {"token":"Ciao"}\n\ndata: {"done":true}\n\n',
            200,
            headers: {
              Headers.contentTypeHeader: ['text/event-stream'],
            },
          ));
      final client = _clientWith(adapter);

      final frames =
          await client.sse('/api/v1/coach/chiron/chat/stream/').toList();

      expect(frames, ['{"token":"Ciao"}', '{"done":true}']);
    });
  });
}
