import 'dart:convert';
import 'dart:typed_data';

import 'package:athlynk/app/athlynk_app.dart';
import 'package:athlynk/core/auth/session_controller.dart';
import 'package:athlynk/core/auth/token_storage.dart';
import 'package:athlynk/core/network/api_client.dart';
import 'package:athlynk/core/providers.dart';
import 'package:athlynk/design/theme.dart';
import 'package:athlynk/features/athlete/chiron_tutorial_view.dart';
import 'package:athlynk/features/athlete/shell.dart';
import 'package:athlynk/features/shared/onboarding_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end flow of the athlete app against a stubbed backend:
/// splash → login → 5-tab shell → dashboard widgets → tab switching.
/// Run on a device/emulator with:
///   flutter test integration_test/athlete_flow_test.dart --flavor athlete

class _FakeTokenStorage implements TokenStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async => value = token;
  @override
  Future<void> clear() async => value = null;
}

class _StubAdapter implements HttpClientAdapter {
  final List<String> seenPaths = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final path = options.uri.path;
    seenPaths.add(path);
    return _route(path);
  }

  ResponseBody _route(String path) {
    Map<String, dynamic> body;
    if (path.endsWith('/auth/login')) {
      body = {'token': 'integration-token', 'user': _user};
    } else if (path.endsWith('/api/v1/me')) {
      body = {
        'user': _user,
        'profile': {
          'profile_image_url': null,
          'brand_primary': '#1E3A5F',
          'brand_accent': '#5B89B6',
        },
      };
    } else if (path.endsWith('/dashboard/summary')) {
      body = {
        'weight_current': 78.4,
        'weight_delta': -0.6,
        'sessions_this_week': 3,
        'kcal_target': 2450.0,
        'days_to_renewal': 12,
      };
    } else if (path.endsWith('/dashboard/layout')) {
      body = {
        'layout': {
          'version': 1,
          'widgets': [
            {'id': 'w1', 'type': 'next_workout', 'x': 0, 'y': 0, 'size': 'full'},
            {'id': 'w2', 'type': 'nav_shortcuts', 'x': 0, 'y': 1, 'size': 'full'},
          ],
        },
        'catalog': [
          {
            'type': 'next_workout',
            'title': 'Prossimo allenamento',
            'desc': '',
            'sf_symbol': 'dumbbell.fill',
            'mobile_size': 'full',
          },
        ],
      };
    } else if (path.endsWith('/api/v1/workouts')) {
      body = {
        'plans': [
          {
            'assignment_id': 1,
            'plan_id': 1,
            'title': 'Push Pull Legs',
            'goal': 'Ipertrofia',
            'frequency_per_week': 4,
            'duration_weeks': 8,
            'start_date': '2026-07-01',
            'days': [
              {
                'id': 10,
                'day_order': 1,
                'day_name': 'Giorno A',
                'focus_area': 'Spinta',
                'exercises': [
                  {
                    'id': 100,
                    'name': 'Panca piana',
                    'equipment': ['Bilanciere'],
                    'order_index': 0,
                    'set_count': 4,
                    'rep_range': '8-10',
                    'load_value': 80.0,
                    'load_unit': 'KG',
                    'recovery_seconds': 120,
                  },
                ],
              },
            ],
          },
        ],
      };
    } else if (path.endsWith('/api/v1/nutrition')) {
      body = {'plans': []};
    } else if (path.endsWith('/api/v1/conversations')) {
      body = {'conversations': []};
    } else if (path.endsWith('/api/v1/checks')) {
      body = {'pending': []};
    } else {
      body = {'ok': true};
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}

  static const _user = {
    'id': 1,
    'email': 'atleta@athlynk.it',
    'role': 'CLIENT',
    'first_name': 'Luca',
    'last_name': 'Rossi',
    'display_name': 'Luca Rossi',
    'chiron_seen': true,
    'terms_accepted': true,
  };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login → dashboard → tab switch', (tester) async {
    SharedPreferences.setMockInitialValues({PrefsKeys.onboarded: true});
    final prefs = await SharedPreferences.getInstance();
    final storage = _FakeTokenStorage();
    final adapter = _StubAdapter();
    final dio = Dio(BaseOptions(
      responseType: ResponseType.bytes,
      validateStatus: (_) => true,
    ))..httpClientAdapter = adapter;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        flavorProvider.overrideWithValue(AppFlavor.athlete),
        prefsProvider.overrideWithValue(prefs),
        tokenStorageProvider.overrideWithValue(storage),
        apiClientProvider.overrideWithValue(
            ApiClient(dio: dio, baseUrl: 'https://test.local')),
      ],
      child: AthlynkApp(
        config: FlavorConfig(
          flavor: AppFlavor.athlete,
          appTitle: 'Athlynk',
          splashSubtitle: null,
          splashTagline: 'FORZA · METODO · GLORIA',
          splashPalette: const [Palette.defaultPrimary, Palette.violet],
          onboardedPrefsKey: PrefsKeys.onboarded,
          shellBuilder: (_) => const AthleteShell(),
          chironBuilder: (_, onFinish) =>
              ChironTutorialView(onFinish: onFinish),
          onboardingBuilder: (_, onDone) => OnboardingView(
            onDone: onDone,
            slides: const [
              OnboardingSlide(
                  icon: Icons.info_outline,
                  title: 'Benvenuto',
                  body: 'Intro'),
            ],
          ),
        ),
      ),
    ));

    // Splash boots, finds no token, lands on login.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Accedi al tuo percorso.'), findsOneWidget);

    // Log in.
    await tester.enterText(find.byType(TextField).first, 'atleta@athlynk.it');
    await tester.enterText(find.byType(TextField).last, 'password');
    await tester.tap(find.text('Accedi'));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(storage.value, 'integration-token');

    // Dashboard: greeting hero + KPI tiles fed by /dashboard/summary.
    expect(find.text('LUCA'), findsOneWidget);
    expect(find.textContaining('SESSIONI SETTIMANA'), findsOneWidget);
    expect(find.text('3'), findsWidgets); // sessions_this_week
    expect(find.text('2450'), findsWidgets); // kcal target

    // The layout came from the server: today's session widget is rendered.
    expect(find.text('OGGI'), findsOneWidget);
    expect(find.text('Spinta'), findsOneWidget);

    // Switch to the Allenamento tab from the floating tab bar.
    await tester.tap(find.text('ALLENAMENTO'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Push Pull Legs'), findsOneWidget);
    expect(find.text('Storico allenamenti'), findsOneWidget);

    // Sanity: the app really hit the documented endpoints.
    expect(adapter.seenPaths, contains('/api/v1/auth/login'));
    expect(adapter.seenPaths, contains('/api/v1/me'));
    expect(adapter.seenPaths, contains('/api/v1/dashboard/summary'));
    expect(adapter.seenPaths, contains('/api/v1/workouts'));
  });
}
