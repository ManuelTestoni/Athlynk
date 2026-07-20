import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/session_controller.dart';
import '../core/providers.dart';
import '../design/theme.dart';
import '../features/shared/login_view.dart';
import '../features/shared/review_request_view.dart';
import '../features/shared/splash_view.dart';
import '../features/shared/terms_consent_view.dart';

/// Everything that differs between the two apps (mirrors the iOS
/// target split: Athlynk vs AthlynkCoach).
class FlavorConfig {
  const FlavorConfig({
    required this.flavor,
    required this.appTitle,
    required this.splashSubtitle,
    required this.splashTagline,
    required this.splashPalette,
    required this.onboardedPrefsKey,
    required this.shellBuilder,
    required this.chironBuilder,
    required this.onboardingBuilder,
  });

  final AppFlavor flavor;
  final String appTitle;
  final String? splashSubtitle;
  final String? splashTagline;
  final List<Color> splashPalette;
  final String onboardedPrefsKey;

  /// Root 5-tab shell.
  final WidgetBuilder shellBuilder;

  /// First-login Chiron flow (athlete: profile intake wizard; coach:
  /// profile setup wizard). Must call the provided callback when done.
  final Widget Function(BuildContext, VoidCallback onFinish) chironBuilder;

  /// First-launch marketing intro (6 slides). Must call `onDone`.
  final Widget Function(BuildContext, VoidCallback onDone) onboardingBuilder;
}

/// The app is Italian-only (mirrors the iOS `Locale(identifier: "it_IT")`).
const appLocale = Locale('it', 'IT');
const appSupportedLocales = [appLocale];

/// Because [appSupportedLocales] excludes `en`, the `Default*Localizations`
/// that `MaterialApp` falls back to by default resolve to nothing and every
/// `TextField` throws "No MaterialLocalizations found". These delegates are
/// what actually ship the `it` strings — do not drop them.
const appLocalizationsDelegates = <LocalizationsDelegate<Object>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class AthlynkApp extends ConsumerWidget {
  const AthlynkApp({super.key, required this.config});

  final FlavorConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Brand-color changes bump themeVersion → rebuild the whole tree with the
    // new palette (iOS `.id(app.themeVersion)` remount trick).
    final themeVersion =
        ref.watch(sessionControllerProvider.select((s) => s.themeVersion));

    return MaterialApp(
      title: config.appTitle,
      debugShowCheckedModeBanner: false,
      theme: athlynkTheme(),
      themeMode: ThemeMode.light,
      locale: appLocale,
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      home: KeyedSubtree(
        key: ValueKey('theme-$themeVersion'),
        child: _PhaseRoot(config: config),
      ),
    );
  }
}

/// Root phase router — port of iOS `ContentView`: cross-faded
/// splash / login / app, with the three blocking full-screen covers
/// (terms → chiron → review) layered on top.
class _PhaseRoot extends ConsumerStatefulWidget {
  const _PhaseRoot({required this.config});

  final FlavorConfig config;

  @override
  ConsumerState<_PhaseRoot> createState() => _PhaseRootState();
}

class _PhaseRootState extends ConsumerState<_PhaseRoot> {
  bool _showOnboarding = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final prefs = ref.watch(prefsProvider);
    final onboarded =
        prefs.getBool(widget.config.onboardedPrefsKey) ?? false;

    final Widget page;
    switch (session.phase) {
      case AppPhase.splash:
        page = SplashView(
          key: const ValueKey('splash'),
          title: 'ATHLYNK',
          subtitle: widget.config.splashSubtitle,
          tagline: widget.config.splashTagline,
          palette: widget.config.splashPalette,
        );
      case AppPhase.login:
        if (!onboarded || _showOnboarding) {
          page = KeyedSubtree(
            key: const ValueKey('onboarding'),
            child: widget.config.onboardingBuilder(context, () async {
              await prefs.setBool(widget.config.onboardedPrefsKey, true);
              setState(() => _showOnboarding = false);
            }),
          );
        } else {
          page = const LoginView(key: ValueKey('login'));
        }
      case AppPhase.app:
        page = KeyedSubtree(
          key: const ValueKey('app'),
          child: Builder(builder: widget.config.shellBuilder),
        );
    }

    return Stack(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 700),
          switchInCurve: Motion.luxe,
          switchOutCurve: Curves.easeOut,
          child: page,
        ),
        // Blocking covers, in priority order (only one is ever true at once).
        if (session.phase == AppPhase.app && session.needsTermsConsent)
          const Positioned.fill(child: TermsConsentView()),
        if (session.phase == AppPhase.app &&
            !session.needsTermsConsent &&
            session.showChiron)
          Positioned.fill(
            child: widget.config.chironBuilder(context, () {
              ref.read(sessionControllerProvider.notifier).finishChiron();
            }),
          ),
        if (session.phase == AppPhase.app && session.showReview)
          const Positioned.fill(child: ReviewRequestView()),
      ],
    );
  }
}
