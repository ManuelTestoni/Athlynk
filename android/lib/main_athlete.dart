import 'package:flutter/material.dart';

import 'app/athlynk_app.dart';
import 'app/bootstrap.dart';
import 'core/auth/session_controller.dart';
import 'core/providers.dart';
import 'design/theme.dart';
import 'features/athlete/chiron_tutorial_view.dart';
import 'features/athlete/shell.dart';
import 'features/shared/onboarding_view.dart';

/// Athlynk — athlete app entry point (flavor `athlete`).
void main() {
  runAthlynk(FlavorConfig(
    flavor: AppFlavor.athlete,
    appTitle: 'Athlynk',
    splashSubtitle: null,
    splashTagline: 'FORZA · METODO · GLORIA',
    splashPalette: const [
      Palette.defaultPrimary,
      Palette.violet,
      Palette.defaultAccent,
    ],
    onboardedPrefsKey: PrefsKeys.onboarded,
    shellBuilder: (_) => const AthleteShell(),
    chironBuilder: (_, onFinish) => ChironTutorialView(onFinish: onFinish),
    onboardingBuilder: (_, onDone) => OnboardingView(
      onDone: onDone,
      slides: const [
        OnboardingSlide(
          icon: Icons.account_balance_rounded,
          title: 'Benvenuto in Athlynk',
          body:
              'Il tuo percorso con il coach, tutto in un unico posto: schede, dieta, check e progressi.',
        ),
        OnboardingSlide(
          icon: Icons.fitness_center_rounded,
          title: 'Allenamenti',
          body:
              'Le schede del tuo coach sempre con te. Registra ogni serie durante la sessione, con timer di recupero.',
        ),
        OnboardingSlide(
          icon: Icons.restaurant_rounded,
          title: 'Nutrizione',
          body:
              'Piani alimentari e diario dei macro: sai sempre cosa mangiare e come stai andando.',
        ),
        OnboardingSlide(
          icon: Icons.query_stats_rounded,
          title: 'Progressi',
          body:
              'Peso, misure, foto e carichi: i tuoi miglioramenti diventano visibili, settimana dopo settimana.',
        ),
        OnboardingSlide(
          icon: Icons.auto_awesome_rounded,
          title: 'Chiron',
          body:
              'Il centauro che guida gli eroi: Chiron ti accompagna nei primi passi dentro Athlynk.',
          mascot: true,
        ),
        OnboardingSlide(
          icon: Icons.verified_rounded,
          title: 'Tutto pronto',
          body: 'Accedi con le credenziali che ti ha dato il tuo coach.',
        ),
      ],
    ),
  ));
}
