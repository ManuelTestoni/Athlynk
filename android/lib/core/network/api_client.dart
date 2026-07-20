import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'api_exception.dart';

/// Thin HTTP core — port of iOS `APIClient.request(_:)`.
///
/// Behavior parity:
/// - 20 s request timeout;
/// - `Authorization: Bearer <token>` when a token is set;
/// - auto-retry ×2 with linear backoff (attempt × 400 ms) on 5xx or any
///   transport error that isn't a cancellation;
/// - raw server errors mapped to [ApiException] with generic user copy.
class ApiClient {
  ApiClient({Dio? dio, String? baseUrl})
      : baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 20),
              responseType: ResponseType.bytes,
              // Status handling is ours: never throw on status.
              validateStatus: (_) => true,
            ));

  final String baseUrl;
  final Dio _dio;

  /// Bearer token, mirrored from secure storage by the session controller.
  String? token;

  static const int _maxRetries = 2;

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// Performs a request and returns the raw response bytes.
  Future<Uint8List> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    final url = path.startsWith('http') ? path : '$baseUrl$path';
    Object? data;
    if (body != null) data = jsonEncode(body);

    for (var attempt = 0;; attempt++) {
      try {
        final res = await _dio.request<Uint8List>(
          url,
          data: data,
          queryParameters: query,
          options: Options(method: method, headers: _headers()),
        );
        final status = res.statusCode ?? 0;
        final bytes = res.data ?? Uint8List(0);
        if (status >= 200 && status < 300) return bytes;

        if (status >= 500 && attempt < _maxRetries) {
          await Future<void>.delayed(
              Duration(milliseconds: 400 * (attempt + 1)));
          continue;
        }
        throw ApiHttpException(status, _safeUtf8(bytes));
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) rethrow;
        if (attempt < _maxRetries) {
          await Future<void>.delayed(
              Duration(milliseconds: 400 * (attempt + 1)));
          continue;
        }
        throw ApiTransportException(e.message ?? e.type.name);
      }
    }
  }

  /// Request + JSON-decode into [T] via [fromJson] applied to the decoded map.
  Future<T> requestJson<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    final bytes =
        await request(path, method: method, body: body, query: query);
    return decodeObject(bytes, fromJson);
  }

  /// Request expecting any JSON value (map, list, …) — for ad-hoc payloads.
  Future<dynamic> requestAny(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    final bytes =
        await request(path, method: method, body: body, query: query);
    if (bytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (e) {
      throw ApiDecodingException(e.toString());
    }
  }

  /// Fire-and-forget style call where only success matters.
  Future<void> requestVoid(
    String path, {
    String method = 'POST',
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    await request(path, method: method, body: body, query: query);
  }

  /// Multipart upload (profile photos, check attachments, plan imports).
  /// [fields] are plain form fields; [files] is an entry list so the same
  /// field name can repeat (multiple photos per `allegato` question).
  Future<Uint8List> upload(
    String path, {
    Map<String, String> fields = const {},
    required List<MapEntry<String, MultipartFile>> files,
    String method = 'POST',
  }) async {
    final url = path.startsWith('http') ? path : '$baseUrl$path';
    final form = FormData();
    fields.forEach((k, v) => form.fields.add(MapEntry(k, v)));
    form.files.addAll(files);
    try {
      final res = await _dio.request<Uint8List>(
        url,
        data: form,
        options: Options(
          method: method,
          headers: _headers(json: false),
          // Uploads can be slow on mobile networks.
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final status = res.statusCode ?? 0;
      final bytes = res.data ?? Uint8List(0);
      if (status >= 200 && status < 300) return bytes;
      throw ApiHttpException(status, _safeUtf8(bytes));
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw ApiTransportException(e.message ?? e.type.name);
    }
  }

  /// Opens a Server-Sent-Events stream (Chiron chat) and yields the payload
  /// of each `data:` frame as a raw string.
  Stream<String> sse(
    String path, {
    Map<String, dynamic>? body,
    CancelToken? cancelToken,
  }) async* {
    final url = path.startsWith('http') ? path : '$baseUrl$path';
    final res = await _dio.request<ResponseBody>(
      url,
      data: body == null ? null : jsonEncode(body),
      cancelToken: cancelToken,
      options: Options(
        method: 'POST',
        headers: {..._headers(), 'Accept': 'text/event-stream'},
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(minutes: 5),
      ),
    );
    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw ApiHttpException(status, '');
    }
    var buffer = '';
    await for (final chunk in res.data!.stream) {
      buffer += utf8.decode(chunk, allowMalformed: true);
      while (true) {
        final nl = buffer.indexOf('\n');
        if (nl < 0) break;
        final line = buffer.substring(0, nl).trimRight();
        buffer = buffer.substring(nl + 1);
        if (line.startsWith('data:')) {
          yield line.substring(5).trim();
        }
      }
    }
  }

  static String _safeUtf8(Uint8List bytes) {
    try {
      final s = utf8.decode(bytes);
      return s.length > 500 ? s.substring(0, 500) : s;
    } catch (_) {
      return '<binary>';
    }
  }
}

/// Decodes [bytes] as a JSON object and maps it through [fromJson].
T decodeObject<T>(
    Uint8List bytes, T Function(Map<String, dynamic> json) fromJson) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    return fromJson(decoded as Map<String, dynamic>);
  } on ApiException {
    rethrow;
  } catch (e) {
    throw ApiDecodingException(e.toString());
  }
}
