import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/athlete_api.dart';
import '../../core/l10n/formatters.dart';
import '../../core/providers.dart';
import '../../core/utils/haptics.dart';
import '../../design/components/chiron_mascot.dart';
import '../../design/components/neon_button.dart';
import '../../design/components/panel.dart';
import '../../design/components/particle_burst.dart';
import '../../design/components/pressable.dart';
import '../../design/components/volt_background.dart';
import '../../design/theme.dart';

/// First-login profile intake wizard guided by Chiron — port of iOS
/// `ChironTutorialView`: intro, gender, birth date, weight, sport, recap.
/// Saves via `PATCH /api/v1/profile`, then calls [onFinish].
class ChironTutorialView extends ConsumerStatefulWidget {
  const ChironTutorialView({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  ConsumerState<ChironTutorialView> createState() =>
      _ChironTutorialViewState();
}

class _ChironTutorialViewState extends ConsumerState<ChironTutorialView> {
  int _step = 0;
  int _speak = 0;
  int _burst = 0;
  String? _gender;
  DateTime? _birthDate;
  double _weight = 70;
  final _sport = TextEditingController();
  bool _saving = false;

  static const _sports = [
    'Bodybuilding',
    'Powerlifting',
    'CrossFit',
    'Calcio',
    'Corsa',
    'Ciclismo',
    'Nuoto',
    'Altro',
  ];

  static const _stepCount = 6;

  String get _greetingLine {
    final name = ref.read(sessionControllerProvider).greetingName;
    return switch (_step) {
      0 => 'Χαῖρε, $name. Sono Chiron: ti guiderò nei primi passi.',
      1 => 'Parlami di te: come ti identifichi?',
      2 => 'Quando sei nato?',
      3 => 'Qual è il tuo peso attuale?',
      4 => 'Qual è il tuo sport principale?',
      _ => 'Perfetto. Il tuo coach ha tutto ciò che serve per iniziare.',
    };
  }

  Future<void> _advance() async {
    if (_step < _stepCount - 1) {
      Haptics.tap();
      setState(() {
        _step++;
        _speak++;
      });
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).updateProfile({
        if (_gender != null) 'gender': _gender,
        if (_birthDate != null)
          'birth_date':
              '${_birthDate!.year.toString().padLeft(4, '0')}-${_birthDate!.month.toString().padLeft(2, '0')}-${_birthDate!.day.toString().padLeft(2, '0')}',
        'weight_kg': double.parse(_weight.toStringAsFixed(1)),
        if (_sport.text.trim().isNotEmpty) 'sport': _sport.text.trim(),
      });
    } catch (_) {/* best-effort, like iOS */}
    setState(() => _burst++);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const VoltBackground(
              palette: [Palette.amber, Palette.violet, Palette.defaultAccent]),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      ParticleBurst(trigger: _burst),
                      ChironMascot(size: 96, speak: _speak),
                    ],
                  ),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration: Motion.snappyDuration,
                    child: Container(
                      key: ValueKey(_step),
                      padding: const EdgeInsets.all(16),
                      decoration: voltPanel(
                          tint: Palette.amber.withValues(alpha: 0.4)),
                      child: Text(
                        _greetingLine,
                        textAlign: TextAlign.center,
                        style: Typo.body(15, FontWeight.w500),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Expanded(child: _stepBody()),
                  Row(
                    children: [
                      if (_step > 0 && _step < _stepCount - 1)
                        Expanded(
                          child: NeonButton(
                            'Indietro',
                            filled: false,
                            color: Palette.textMid,
                            onTap: () => setState(() => _step--),
                          ),
                        ),
                      if (_step > 0 && _step < _stepCount - 1)
                        const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: NeonButton(
                          _step == _stepCount - 1 ? 'Inizia' : 'Avanti',
                          color: Palette.amber,
                          loading: _saving,
                          onTap: _advance,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return Center(
          child: Text(
            'Poche domande per personalizzare il tuo percorso.',
            textAlign: TextAlign.center,
            style: Typo.body(14, FontWeight.w400, Palette.textMid),
          ),
        );
      case 1:
        return Center(
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              for (final (value, label) in const [
                ('M', 'Uomo'),
                ('F', 'Donna'),
                ('O', 'Altro'),
              ])
                Pressable(
                  onTap: () => setState(() => _gender = value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 13),
                    decoration: BoxDecoration(
                      color:
                          _gender == value ? Palette.amber : Palette.void1,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Palette.line),
                    ),
                    child: Text(
                      label,
                      style: Typo.body(15, FontWeight.w700,
                          _gender == value ? Palette.void0 : Palette.textMid),
                    ),
                  ),
                ),
            ],
          ),
        );
      case 2:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _birthDate == null
                    ? 'Seleziona la data'
                    : Formatters.longDate(_birthDate!),
                style: Typo.display(22),
              ),
              const SizedBox(height: 16),
              NeonButton(
                'Scegli data',
                compact: true,
                expand: false,
                filled: false,
                color: Palette.amber,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _birthDate ?? DateTime(2000, 1, 1),
                    firstDate: DateTime(1930),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _birthDate = picked);
                },
              ),
            ],
          ),
        );
      case 3:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${Formatters.decimal(_weight)} kg',
                  style: Typo.poster(48)),
              Slider(
                value: _weight,
                min: 35,
                max: 160,
                divisions: 250,
                activeColor: Palette.amber,
                onChanged: (v) {
                  Haptics.soft();
                  setState(() => _weight = v);
                },
              ),
            ],
          ),
        );
      case 4:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final sport in _sports)
                    Pressable(
                      onTap: () =>
                          setState(() => _sport.text = sport),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          color: _sport.text == sport
                              ? Palette.amber
                              : Palette.void1,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Palette.line),
                        ),
                        child: Text(
                          sport,
                          style: Typo.body(
                              13.5,
                              FontWeight.w600,
                              _sport.text == sport
                                  ? Palette.void0
                                  : Palette.textMid),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      default:
        return Center(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: voltPanel(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Eyebrow('Riepilogo'),
                const SizedBox(height: 10),
                _recapRow('Genere', switch (_gender) {
                  'M' => 'Uomo',
                  'F' => 'Donna',
                  'O' => 'Altro',
                  _ => '—',
                }),
                _recapRow(
                    'Nascita',
                    _birthDate == null
                        ? '—'
                        : Formatters.mediumDate(_birthDate!)),
                _recapRow('Peso', '${Formatters.decimal(_weight)} kg'),
                _recapRow('Sport',
                    _sport.text.trim().isEmpty ? '—' : _sport.text.trim()),
              ],
            ),
          ),
        );
    }
  }

  Widget _recapRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: Typo.body(13, FontWeight.w500, Palette.textMid)),
          ),
          Text(value, style: Typo.body(14, FontWeight.w700)),
        ],
      ),
    );
  }
}
