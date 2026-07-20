import 'dart:convert';
import 'dart:typed_data';

import 'package:athlynk/app/athlynk_app.dart';
import 'package:athlynk/core/auth/token_storage.dart';
import 'package:athlynk/core/network/api_client.dart';
import 'package:athlynk/core/providers.dart';
import 'package:athlynk/design/theme.dart';
import 'package:athlynk/features/shared/login_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Future<void> _pump(
  WidgetTester tester, {
  required ResponseBody Function(RequestOptions) handler,
  required SharedPreferences prefs,
  _FakeTokenStorage? storage,
}) async {
  final dio = Dio(BaseOptions(
    responseType: ResponseType.bytes,
    validateStatus: (_) => true,
  ))..httpClientAdapter = _FakeAdapter(handler);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        flavorProvider.overrideWithValue(AppFlavor.athlete),
        prefsProvider.overrideWithValue(prefs),
        tokenStorageProvider.overrideWithValue(storage ?? _FakeTokenStorage()),
        apiClientProvider.overrideWithValue(
            ApiClient(dio: dio, baseUrl: 'https://test.local')),
      ],
      // Mirrors AthlynkApp's own MaterialApp configuration. The locale
      // settings are load-bearing, not decoration: with `it_IT` as the only
      // supported locale and no delegates, every TextField throws
      // "No MaterialLocalizations found". Pumping a bare `MaterialApp()` here
      // silently falls back to `en` and hides that.
      child: MaterialApp(
        theme: athlynkTheme(),
        locale: appLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: const LoginView(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('renders the Athlynk login form in Italian', (tester) async {
    await _pump(tester,
        prefs: prefs, handler: (_) => _json({'ok': 1}, 200));

    expect(find.text('ATHLYNK'), findsOneWidget);
    expect(find.text('Accedi al tuo percorso.'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Password dimenticata?'), findsOneWidget);
    // The connected backend URL is shown for debugging, like iOS.
    expect(find.textContaining('http'), findsOneWidget);
  });

  testWidgets('shows the generic credentials error on a 401', (tester) async {
    await _pump(tester,
        prefs: prefs,
        handler: (_) => _json({'error': 'invalid_credentials'}, 401));

    await tester.enterText(find.byType(TextField).first, 'a@b.it');
    await tester.enterText(find.byType(TextField).last, 'wrong');
    await tester.tap(find.text('Accedi'));
    await tester.pump(); // start the request
    await tester.pump(const Duration(seconds: 1)); // settle it

    expect(find.text('Email o password errati.'), findsOneWidget);
  });

  testWidgets('a successful login stores the token and leaves login',
      (tester) async {
    final storage = _FakeTokenStorage();
    await _pump(
      tester,
      prefs: prefs,
      storage: storage,
      handler: (options) {
        if (options.path.endsWith('/auth/login')) {
          return _json({
            'token': 'tok-widget',
            'user': {
              'id': 1,
              'email': 'a@b.it',
              'role': 'CLIENT',
              'first_name': 'Luca',
              'last_name': 'Rossi',
              'display_name': 'Luca Rossi',
              'chiron_seen': true,
              'terms_accepted': true,
            },
          }, 200);
        }
        return _json({
          'user': {
            'id': 1,
            'email': 'a@b.it',
            'role': 'CLIENT',
            'first_name': 'Luca',
            'last_name': 'Rossi',
            'display_name': 'Luca Rossi',
            'chiron_seen': true,
            'terms_accepted': true,
          },
        }, 200);
      },
    );

    await tester.enterText(find.byType(TextField).first, 'a@b.it');
    await tester.enterText(find.byType(TextField).last, 'right');
    await tester.tap(find.text('Accedi'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(storage.value, 'tok-widget');
    expect(find.text('Email o password errati.'), findsNothing);
  });

  testWidgets('password field starts obscured and toggles', (tester) async {
    await _pump(tester,
        prefs: prefs, handler: (_) => _json({'ok': 1}, 200));

    TextField passwordField() =>
        tester.widgetList<TextField>(find.byType(TextField)).last;

    expect(passwordField().obscureText, isTrue);
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();
    expect(passwordField().obscureText, isFalse);
  });
}
