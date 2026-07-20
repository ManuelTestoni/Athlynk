/// Build-time configuration, injected via `--dart-define-from-file=env/*.json`
/// (mirrors the iOS xcconfig keys). Defaults match `AppConfig.swift`: the
/// production host, analytics off.
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://app.athlynk.it',
  );

  static const String environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'production',
  );

  /// Empty ⇒ analytics is a total no-op (parity with iOS today).
  static const String posthogApiKey =
      String.fromEnvironment('POSTHOG_API_KEY', defaultValue: '');

  static const String posthogHost = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://eu.i.posthog.com',
  );

  static const String appVersion = '1.0.0';

  /// Resolves a possibly-relative `/media/...` path against the API host.
  /// (The backend already absolutizes mobile payloads via `_abs_media`; this
  /// is belt-and-braces for any stray relative URL.)
  static String absoluteMediaUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '$apiBaseUrl$url';
    return url;
  }
}
