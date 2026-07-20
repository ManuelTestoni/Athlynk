import 'dart:convert';
import 'dart:typed_data';

import 'package:athlynk/core/auth/session_controller.dart';
import 'package:athlynk/core/auth/token_storage.dart';
import 'package:athlynk/core/network/api_client.dart';
import 'package:athlynk/core/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory token vault so bootstrap/login/logout can be asserted without
/// touching the Android Keystore.
class _FakeTokenStorage implements TokenStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> clear() async => value = null;
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, int status) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });

const _meBody = {
  'user': {
    'id': 1,
    'email': 'atleta@athlynk.it',
    'role': 'CLIENT',
    'first_name': 'Luca',
    'last_name': 'Rossi',
    'display_name': 'Luca Rossi',
    'chiron_seen': true,
    'terms_accepted': true,
  },
  'profile': {
    'profile_image_url': 'https://cdn/a.webp',
    'brand_primary': '#1E3A5F',
    'brand_accent': '#5B89B6',
  },
};

ProviderContainer _container({
  required _FakeTokenStorage storage,
  required ResponseBody Function(RequestOptions) handler,
  required SharedPreferences prefs,
  AppFlavor flavor = AppFlavor.athlete,
}) {
  final dio = Dio(BaseOptions(
    responseType: ResponseType.bytes,
    validateStatus: (_) => true,
  ))..httpClientAdapter = _FakeAdapter(handler);

  return ProviderContainer(overrides: [
    flavorProvider.overrideWithValue(flavor),
    prefsProvider.overrideWithValue(prefs),
    tokenStorageProvider.overrideWithValue(storage),
    apiClientProvider
        .overrideWithValue(ApiClient(dio: dio, baseUrl: 'https://test.local')),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('no stored token → straight to the login phase', () async {
    final container = _container(
      storage: _FakeTokenStorage(),
      handler: (_) => _json(_meBody, 200),
      prefs: prefs,
    );
    addTearDown(container.dispose);

    await container.read(sessionControllerProvider.notifier).bootstrap();

    expect(container.read(sessionControllerProvider).phase, AppPhase.login);
  });

  test('valid token → app phase with user and avatar hydrated', () async {
    final storage = _FakeTokenStorage()..value = 'tok';
    final container = _container(
      storage: storage,
      handler: (_) => _json(_meBody, 200),
      prefs: prefs,
    );
    addTearDown(container.dispose);

    await container.read(sessionControllerProvider.notifier).bootstrap();
    final state = container.read(sessionControllerProvider);

    expect(state.phase, AppPhase.app);
    expect(state.user?.displayName, 'Luca Rossi');
    expect(state.avatarUrl, 'https://cdn/a.webp');
    expect(state.greetingName, 'Luca');
    expect(state.needsTermsConsent, isFalse);
    expect(state.showChiron, isFalse);
  });

  test('401 on bootstrap clears the token and drops to login', () async {
    final storage = _FakeTokenStorage()..value = 'stale';
    final container = _container(
      storage: storage,
      handler: (_) => _json({'error': 'unauthorized'}, 401),
      prefs: prefs,
    );
    addTearDown(container.dispose);

    await container.read(sessionControllerProvider.notifier).bootstrap();

    expect(container.read(sessionControllerProvider).phase, AppPhase.login);
    expect(storage.value, isNull);
    expect(container.read(apiClientProvider).token, isNull);
  });

  test('offline/5xx keeps the token and offers a retry instead', () async {
    final storage = _FakeTokenStorage()..value = 'good';
    final container = _container(
      storage: storage,
      handler: (_) => _json({'error': 'boom'}, 500),
      prefs: prefs,
    );
    addTearDown(container.dispose);

    await container.read(sessionControllerProvider.notifier).bootstrap();
    final state = container.read(sessionControllerProvider);

    expect(state.phase, AppPhase.splash); // stays on the splash
    expect(state.bootstrapRetryable, isTrue);
    expect(storage.value, 'good'); // token survives
  });

  test('login stores the token and sends the flavor role', () async {
    final storage = _FakeTokenStorage();
    final bodies = <String>[];
    final container = _container(
      storage: storage,
      flavor: AppFlavor.coach,
      prefs: prefs,
      handler: (options) {
        if (options.path.endsWith('/auth/login')) {
          bodies.add(options.data as String);
          return _json({'token': 'new-tok', 'user': _meBody['user']}, 200);
        }
        return _json(_meBody, 200);
      },
    );
    addTearDown(container.dispose);

    await container
        .read(sessionControllerProvider.notifier)
        .login(' coach@athlynk.it ', 'pw');

    expect(jsonDecode(bodies.single)['role'], 'COACH');
    expect(jsonDecode(bodies.single)['email'], 'coach@athlynk.it'); // trimmed
    expect(storage.value, 'new-tok');
    expect(container.read(sessionControllerProvider).phase, AppPhase.app);
  });

  test('bad credentials surface the Italian message, no phase change',
      () async {
    final container = _container(
      storage: _FakeTokenStorage(),
      handler: (_) => _json({'error': 'invalid'}, 401),
      prefs: prefs,
    );
    addTearDown(container.dispose);

    await container
        .read(sessionControllerProvider.notifier)
        .login('a@b.it', 'nope');
    final state = container.read(sessionControllerProvider);

    expect(state.loginError, 'Email o password errati.');
    expect(state.isAuthenticating, isFalse);
    expect(state.phase, AppPhase.splash);
  });

  test('terms gate opens the Chiron intro once accepted', () async {
    final storage = _FakeTokenStorage()..value = 'tok';
    final container = _container(
      storage: storage,
      prefs: prefs,
      handler: (options) {
        if (options.path.endsWith('/accept-terms')) return _json({'ok': 1}, 200);
        return _json({
          'user': {
            ..._meBody['user']! as Map<String, dynamic>,
            'terms_accepted': false,
            'chiron_seen': false,
          },
        }, 200);
      },
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    await controller.bootstrap();

    expect(container.read(sessionControllerProvider).needsTermsConsent, isTrue);
    // Chiron waits behind the legal gate.
    expect(container.read(sessionControllerProvider).showChiron, isFalse);

    final ok = await controller.acceptTerms();

    expect(ok, isTrue);
    expect(container.read(sessionControllerProvider).needsTermsConsent, isFalse);
    expect(container.read(sessionControllerProvider).showChiron, isTrue);
  });

  test('logout clears token, cache and state', () async {
    final storage = _FakeTokenStorage()..value = 'tok';
    final container = _container(
      storage: storage,
      handler: (_) => _json(_meBody, 200),
      prefs: prefs,
    );
    addTearDown(container.dispose);

    await container.read(sessionControllerProvider.notifier).bootstrap();
    container.read(memoryCacheProvider).set(CacheKeysForTest.any, 'x');

    await container.read(sessionControllerProvider.notifier).logout();
    final state = container.read(sessionControllerProvider);

    expect(state.phase, AppPhase.login);
    expect(state.user, isNull);
    expect(storage.value, isNull);
    expect(
        container.read(memoryCacheProvider).get<String>(CacheKeysForTest.any),
        isNull);
  });

  test('tab-bar and Chiron-FAB visibility flags flip', () async {
    final container = _container(
      storage: _FakeTokenStorage(),
      handler: (_) => _json(_meBody, 200),
      prefs: prefs,
    );
    addTearDown(container.dispose);
    final controller = container.read(sessionControllerProvider.notifier);

    controller.setTabBarHidden(true);
    controller.setChironHidden(true);
    expect(container.read(sessionControllerProvider).tabBarHidden, isTrue);
    expect(container.read(sessionControllerProvider).chironHidden, isTrue);

    controller.setTabBarHidden(false);
    controller.setChironHidden(false);
    expect(container.read(sessionControllerProvider).tabBarHidden, isFalse);
    expect(container.read(sessionControllerProvider).chironHidden, isFalse);
  });
}

/// Arbitrary cache key used to prove logout wipes the cache.
class CacheKeysForTest {
  static const any = 'test.any';
}
