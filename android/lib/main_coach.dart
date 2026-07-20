import 'package:flutter/material.dart';

import 'app/athlynk_app.dart';
import 'app/bootstrap.dart';
import 'core/auth/session_controller.dart';
import 'core/providers.dart';
import 'design/theme.dart';
import 'features/coach/onboarding/coach_chiron_intro_view.dart';
import 'features/coach/shell.dart';
import 'features/shared/onboarding_view.dart';

/// Athlynk Coach — coach app entry point (flavor `coach`).
void main() {
  runAthlynk(FlavorConfig(
    flavor: AppFlavor.coach,
    appTitle: 'Athlynk Coach',
    splashSubtitle: 'COACH',
    splashTagline: 'GUIDA · METODO · RISULTATO',
    splashPalette: const [
      Palette.defaultPrimary,
      Palette.violet,
      Palette.amber,
    ],
    onboardedPrefsKey: PrefsKeys.coachOnboarded,
    shellBuilder: (_) => const CoachShell(),
    chironBuilder: (_, onFinish) => CoachChironIntroView(onFinish: onFinish),
    onboardingBuilder: (_, onDone) => OnboardingView(
      onDone: onDone,
      slides: const [
        OnboardingSlide(
          icon: Icons.auto_awesome_rounded,
          title: 'Benvenuto, Coach',
          body:
              'Athlynk è la tua cabina di regia: atleti, schede, diete, check e incassi in un solo posto.',
          mascot: true,
        ),
        OnboardingSlide(
          icon: Icons.groups_rounded,
          title: 'I tuoi atleti',
          body:
              'Roster completo, progressi, aderenza e storico sessioni: sai sempre come sta andando ognuno.',
        ),
        OnboardingSlide(
          icon: Icons.fitness_center_rounded,
          title: 'Schede e piani',
          body:
              'Costruisci schede e diete dal telefono, o importa quelle che hai già con l\'AI.',
        ),
        OnboardingSlide(
          icon: Icons.verified_rounded,
          title: 'Check-in',
          body:
              'Crea i tuoi modelli di check, assegnali con la ricorrenza che vuoi e rispondi con un feedback.',
        ),
        OnboardingSlide(
          icon: Icons.workspace_premium_rounded,
          title: 'Incassi',
          body:
              'Vendi i tuoi piani in app con Stripe e tieni sotto controllo ricavi e rinnovi.',
        ),
        OnboardingSlide(
          icon: Icons.login_rounded,
          title: 'Tutto pronto',
          body: 'Accedi con le credenziali del tuo account Athlynk.',
        ),
      ],
    ),
  ));
}
