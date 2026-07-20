import 'package:athlynk/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Payloads shaped exactly like the Django serializers (`config/api.py`,
/// `config/api_coach.py`) so a wire-format drift fails here, not in the UI.
void main() {
  group('auth', () {
    test('AuthUser gates: nil termsAccepted is treated as accepted', () {
      final user = AuthUser.fromJson({
        'id': 7,
        'email': 'atleta@athlynk.it',
        'role': 'CLIENT',
        'first_name': 'Luca',
        'last_name': 'Rossi',
        'display_name': 'Luca Rossi',
      });

      expect(user.isClient, isTrue);
      expect(user.needsTermsConsent, isFalse); // nil ⇒ never trapped
      expect(user.needsChironIntro, isTrue); // chiron_seen absent
    });

    test('AuthUser blocks only on an explicit false', () {
      final user = AuthUser.fromJson({
        'id': 7,
        'email': 'a@b.it',
        'role': 'COACH',
        'first_name': 'Ada',
        'last_name': 'Neri',
        'display_name': 'Ada Neri',
        'terms_accepted': false,
        'chiron_seen': true,
      });

      expect(user.isClient, isFalse);
      expect(user.needsTermsConsent, isTrue);
      expect(user.needsChironIntro, isFalse); // coaches never get the intro
    });
  });

  group('workouts', () {
    const exerciseJson = {
      'id': 12,
      'name': 'Panca piana',
      'equipment': ['Bilanciere'],
      'order_index': 0,
      'set_count': 4,
      'rep_range': '8-10',
      'load_value': 80.0,
      'load_unit': 'KG',
      'recovery_seconds': 120,
      'rir': 2,
      'demo_gif': 'https://cdn/x.webp',
      'cover_image': 'https://cdn/x.jpg',
      'instruction_steps': ['Sdraiati', 'Spingi'],
    };

    test('ExerciseDto maps snake_case media keys and derives labels', () {
      final ex = ExerciseDto.fromJson(exerciseJson);

      expect(ex.demoGif, 'https://cdn/x.webp');
      expect(ex.coverImage, 'https://cdn/x.jpg');
      expect(ex.setsReps, '4×8-10');
      expect(ex.loadLabel, '80 kg');
      expect(ex.instructionSteps, hasLength(2));
    });

    test('loadLabel honours PERCENT_1RM and BODYWEIGHT units', () {
      final pct = ExerciseDto.fromJson(
          {...exerciseJson, 'load_unit': 'PERCENT_1RM', 'load_value': 75.0});
      final bw = ExerciseDto.fromJson(
          {...exerciseJson, 'load_unit': 'BODYWEIGHT', 'load_value': 0.0});

      expect(pct.loadLabel, '75% 1RM');
      expect(bw.loadLabel, 'BW');
    });

    test('WorkoutPlanDto id mirrors assignment_id', () {
      final plan = WorkoutPlanDto.fromJson({
        'assignment_id': 55,
        'plan_id': 9,
        'title': 'Push Pull Legs',
        'days': [
          {'id': 1, 'day_order': 1, 'day_name': 'A', 'exercises': []}
        ],
      });

      expect(plan.id, 55);
      expect(plan.days.single.label, 'A');
    });
  });

  group('nutrition', () {
    test('athlete meal items use the plural `carbs` key', () {
      final item = MealItemDto.fromJson({
        'id': 3,
        'name': 'Riso',
        'quantity_g': 120.0,
        'kcal': 420.0,
        'protein': 8.0,
        'carbs': 92.0,
        'fat': 1.0,
      });

      expect(item.carbs, 92.0);
    });

    test('MACRO plans average per-day targets when plan-level is missing', () {
      final plan = NutritionPlanDto.fromJson({
        'assignment_id': 2,
        'plan_id': 4,
        'title': 'Ricomposizione',
        'plan_mode': 'MACRO',
        'plan_kind': 'WEEKLY',
        'days': [
          {
            'id': 1,
            'day_of_week': 'MONDAY',
            'target_kcal': 2000,
            'target_protein_g': 150,
            'meals': [],
          },
          {
            'id': 2,
            'day_of_week': 'TUESDAY',
            'target_kcal': 2400,
            'target_protein_g': 170,
            'meals': [],
          },
        ],
      });

      final t = plan.overviewTargets;
      expect(plan.isMacro, isTrue);
      expect(plan.isWeekly, isTrue);
      expect(t.kcal, 2200); // (2000 + 2400) / 2
      expect(t.protein, 160);
      expect(t.carb, isNull);
    });

    test('FOOD plans fall back to the first day meal sum', () {
      final plan = NutritionPlanDto.fromJson({
        'assignment_id': 2,
        'plan_id': 4,
        'title': 'Definizione',
        'plan_mode': 'FOOD',
        'plan_kind': 'DAILY',
        'days': [
          {
            'id': 1,
            'day_of_week': 'MONDAY',
            'meals': [
              {
                'id': 1,
                'name': 'Colazione',
                'items': [
                  {
                    'id': 1,
                    'quantity_g': 100.0,
                    'kcal': 300.0,
                    'protein': 10.0,
                    'carbs': 40.0,
                    'fat': 5.0,
                  },
                ],
              },
            ],
          },
        ],
      });

      expect(plan.overviewTargets.kcal, 300);
      expect(plan.days.single.meals.single.kcal, 300.0);
    });

    test('SupplementItemDto joins quantity and unit, tolerating blanks', () {
      expect(
        SupplementItemDto.fromJson(
            {'id': 1, 'name': 'Creatina', 'quantity': '5', 'unit': 'g'}).dose,
        '5 g',
      );
      expect(
        SupplementItemDto.fromJson({'id': 2, 'name': 'Omega 3'}).dose,
        '',
      );
    });
  });

  group('session', () {
    test('exercise keys line up between prescription and logged sets', () {
      final planned = SessionExerciseDto.fromJson({
        'workout_exercise_id': 42,
        'name': 'Squat',
        'sets': 4,
        'reps': '6',
      });
      final logged = LoggedSetDto.fromJson({
        'workout_exercise_id': 42,
        'set_number': 1,
        'reps_done': 6,
        'completed': true,
      });

      expect(planned.key, 'we-42');
      expect(logged.exerciseKey, planned.key);
    });

    test('added exercises key off the catalog id', () {
      final added = SessionExerciseDto.addedExercise(
          catalogId: 900, name: 'Curl');
      final loggedForAdded = LoggedSetDto.fromJson({
        'exercise_id': 900,
        'set_number': 1,
        'completed': false,
      });

      expect(added.key, 'add-900');
      expect(added.added, isTrue);
      expect(added.loadUnit, 'KG');
      expect(loggedForAdded.exerciseKey, added.key);
    });

    test('substitution surfaces the performed movement', () {
      final ex = SessionLoggedExerciseDto.fromJson({
        'workout_exercise_id': 5,
        'exercise_name': 'Panca piana',
        'sets': [
          {
            'set_number': 1,
            'completed': true,
            'exercise_substituted': true,
            'actual_exercise': {'id': 88, 'name': 'Panca manubri'},
          },
        ],
      });

      expect(ex.wasSubstituted, isTrue);
      expect(ex.performedName, 'Panca manubri');
    });
  });

  group('checks', () {
    test('CheckQuestion maps the reserved `required` key', () {
      final q = CheckQuestion.fromJson({
        'id': 'q1',
        'type': 'metrica',
        'label': 'Peso',
        'required': true,
        'unit': 'kg',
        'min': 30.0,
        'max': 250.0,
      });

      expect(q.isRequired, isTrue);
      expect(q.unit, 'kg');
      expect(q.min, 30.0);
    });

    test('CheckValue keeps numbers numeric and renders them as sent', () {
      expect(CheckValue.fromRaw(80).display, '80');
      expect(CheckValue.fromRaw(80.5).display, '80.5');
      expect(CheckValue.fromRaw('Bene').display, 'Bene');
      expect(CheckValue.fromRaw(null).display, isNull);
      expect(CheckValue.fromRaw('').display, isNull);
    });

    test('check detail decodes sections with a fabbisogni tool block', () {
      final detail = CheckDetailDto.fromJson({
        'id': 3,
        'title': 'Check mensile',
        'submitted_at': '2026-07-01T10:00:00Z',
        'coach_feedback': 'Ottimo lavoro',
        'sections': [
          {
            'id': 's1',
            'label': 'Antropometria',
            'questions': [
              {
                'id': 'peso',
                'type': 'metrica',
                'label': 'Peso',
                'unit': 'kg',
                'value': 81.4,
                'previous': 82.0,
                'delta': -0.6,
              },
              {
                'id': 'fb',
                'type': 'strumento_fabbisogni',
                'label': 'Calcolo Fabbisogni',
                'fb': {
                  'mb': 1780,
                  'det_finale': 2600,
                  'det_adjust': 0,
                  'macros': [
                    {'label': 'Proteine', 'g': 170, 'kcal': 680},
                  ],
                },
              },
            ],
          },
        ],
      });

      final questions = detail.sections.single.questions;
      expect(questions.first.value?.display, '81.4');
      expect(questions.first.delta, -0.6);
      expect(questions.last.fb?.detFinale, 2600);
      expect(questions.last.fb?.macros.single.g, 170);
      expect(detail.coachFeedback, 'Ottimo lavoro');
    });
  });

  group('dashboard', () {
    test('layout + catalog decode and keep widget order', () {
      final res = DashboardLayoutResponse.fromJson({
        'layout': {
          'version': 1,
          'widgets': [
            {'id': 'w1', 'type': 'next_workout', 'x': 0, 'y': 0, 'size': 'full'},
            {
              'id': 'w2',
              'type': 'pinned_athletes',
              'x': 0,
              'y': 1,
              'size': 'full',
              'config': {'client_ids': [3, 9]},
            },
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
      });

      expect(res.layout.widgets.map((w) => w.type),
          ['next_workout', 'pinned_athletes']);
      expect(res.layout.widgets.last.config?.clientIds, [3, 9]);
      expect(res.catalog.single.sfSymbol, 'dumbbell.fill');
    });
  });

  group('coach', () {
    test('CoachProfileDto derives role label and reads the platform plan', () {
      final p = CoachProfileDto.fromJson({
        'id': 1,
        'first_name': 'Ada',
        'last_name': 'Neri',
        'professional_type': 'NUTRIZIONISTA',
        'stripe_connect_charges_enabled': true,
        'brand_primary': '#1E3A5F',
        'brand_accent': '#5B89B6',
        'platform_purchase': {
          'plan': 'apollo',
          'status': 'ACTIVE',
          'billing_interval': 'mensile',
        },
      });

      expect(p.fullName, 'Ada Neri');
      expect(p.roleLabel, 'Nutrizionista');
      expect(p.stripeConnectChargesEnabled, isTrue);
      expect(p.platformPurchase?.plan, 'apollo');
    });

    test('CoachClientRow localises the relationship type', () {
      CoachClientRow row(String? type) => CoachClientRow.fromJson({
            'id': 1,
            'display_name': 'Marco',
            'first_name': 'Marco',
            'last_name': 'Bianchi',
            'relationship_type': ?type,
          });

      expect(row('FULL').relationshipLabel, 'Full Coaching');
      expect(row('WORKOUT').relationshipLabel, 'Allenamento');
      expect(row('NUTRITION').relationshipLabel, 'Nutrizione');
      expect(row(null).relationshipLabel, 'Cliente');
    });

    test('CoachFolder pins the default Template folder', () {
      expect(
        CoachFolder.fromJson({'id': 1, 'title': 'Template'})
            .isDefaultTemplates,
        isTrue,
      );
      expect(
        CoachFolder.fromJson({'id': 2, 'title': 'Massa'}).isDefaultTemplates,
        isFalse,
      );
    });
  });

  group('billing', () {
    test('included_services tolerates a non-string array', () {
      final plan = SubscriptionPlanDto.fromJson({
        'id': 1,
        'name': 'Full Coaching',
        'price': 99.9,
        'currency': 'EUR',
        'included_services': ['Scheda', 42, null, 'Dieta'],
        'is_online_purchasable': true,
      });

      expect(plan.includedServices, ['Scheda', 'Dieta']);
      expect(plan.isOnlinePurchasable, isTrue);
    });
  });
}
