/// Error surface of the API layer — port of iOS `APIError`.
///
/// User-facing copy is deliberately generic (never the raw server string,
/// which can leak internals); the raw detail lives in [debugDetail] for logs.
sealed class ApiException implements Exception {
  const ApiException();

  /// The message shown to the user (Italian, one of three generic strings).
  String get userMessage;

  /// Raw detail for logging only.
  String get debugDetail;

  @override
  String toString() => 'ApiException(${runtimeType.toString()}): $debugDetail';
}

/// Network unreachable / DNS / timeout — anything transport-level.
class ApiTransportException extends ApiException {
  const ApiTransportException(this.detail);
  final String detail;

  @override
  String get userMessage => 'Problema di connessione. Controlla la rete e riprova.';

  @override
  String get debugDetail => 'transport: $detail';
}

/// Non-2xx HTTP status.
class ApiHttpException extends ApiException {
  const ApiHttpException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String get userMessage => statusCode == 401
      ? 'Email o password errati.'
      : 'Si è verificato un errore. Riprova.';

  @override
  String get debugDetail => 'http $statusCode: $body';

  /// Server-side JSON `error` code when present (e.g. `access_blocked`,
  /// `subscription_expired`) — the 403 gating baked into every request.
  String? get errorCode {
    final m = RegExp('"error"\\s*:\\s*"([^"]+)"').firstMatch(body);
    return m?.group(1);
  }
}

/// Payload didn't decode into the expected shape.
class ApiDecodingException extends ApiException {
  const ApiDecodingException(this.detail);
  final String detail;

  @override
  String get userMessage => 'Si è verificato un errore. Riprova.';

  @override
  String get debugDetail => 'decoding: $detail';
}
