import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/api/coach_api.dart';
import '../../../core/providers.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/image_compressor.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/chiron_mascot.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/particle_burst.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/volt_background.dart';
import '../../../design/theme.dart';

/// First-login coach profile wizard guided by Chiron — port of iOS
/// `CoachChironIntroView`: tipo professionale, specializzazione, anni di
/// esperienza, certificazioni, bio, foto, recap. Salva via
/// `PATCH /api/v1/coach/profile` (+ upload foto), poi chiama [onFinish].
class CoachChironIntroView extends ConsumerStatefulWidget {
  const CoachChironIntroView({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  ConsumerState<CoachChironIntroView> createState() =>
      _CoachChironIntroViewState();
}

class _CoachChironIntroViewState extends ConsumerState<CoachChironIntroView> {
  int _step = 0;
  int _speak = 0;
  int _burst = 0;
  String? _professionalType;
  final _specialization = TextEditingController();
  double _years = 3;
  final Set<String> _certifications = {};
  final _bio = TextEditingController();
  String? _photoUrl;
  bool _uploading = false;
  bool _saving = false;

  static const _stepCount = 8;

  static const _types = [
    ('COACH', 'Coach'),
    ('ALLENATORE', 'Allenatore'),
    ('NUTRIZIONISTA', 'Nutrizionista'),
    ('ALTRO', 'Altro'),
  ];

  static const _certOptions = [
    'ISSA', 'NASM', 'CONI', 'FIPE', 'NSCA', 'ACSM',
    'Laurea Scienze Motorie', 'Laurea Dietistica', 'ISAK',
  ];

  String get _line {
    final name = ref.read(sessionControllerProvider).greetingName;
    return switch (_step) {
      0 => 'Χαῖρε, $name. Sono Chiron: prepariamo insieme il tuo profilo.',
      1 => 'Come ti presenti ai tuoi atleti?',
      2 => 'Qual è la tua specializzazione?',
      3 => 'Da quanti anni segui atleti?',
      4 => 'Quali certificazioni hai?',
      5 => 'Racconta in poche righe il tuo metodo.',
      6 => 'Una foto rende il profilo molto più credibile.',
      _ => 'Perfetto. Il tuo profilo è pronto: iniziamo.',
    };
  }

  Future<void> _pickPhoto() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final jpeg = await ImageCompressor.jpeg(bytes, maxDim: 1200);
      final url = await ref.read(apiClientProvider).uploadCoachPhoto(jpeg);
      ref.read(sessionControllerProvider.notifier).setAvatarUrl(url);
      if (mounted) setState(() => _photoUrl = url);
    } catch (_) {/* best-effort, like iOS */} finally {
      if (mounted) setState(() => _uploading = false);
    }
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
      await ref.read(apiClientProvider).coachUpdateProfile({
        if (_professionalType != null) 'professional_type': _professionalType,
        if (_specialization.text.trim().isNotEmpty)
          'specialization': _specialization.text.trim(),
        'years_experience': _years.round(),
        if (_certifications.isNotEmpty)
          'certifications': _certifications.join(', '),
        if (_bio.text.trim().isNotEmpty) 'bio': _bio.text.trim(),
      });
    } catch (_) {/* best-effort, like iOS */}
    setState(() => _burst++);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: (_step + 1) / _stepCount,
                            minHeight: 3,
                            backgroundColor: Palette.void2,
                            color: Palette.amber,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onFinish,
                        child: Text('Salta',
                            style: Typo.body(
                                13, FontWeight.w600, Palette.textLow)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      ParticleBurst(trigger: _burst),
                      ChironMascot(size: 88, speak: _speak),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AnimatedSwitcher(
                    duration: Motion.snappyDuration,
                    child: Container(
                      key: ValueKey(_step),
                      padding: const EdgeInsets.all(16),
                      decoration: voltPanel(
                          tint: Palette.amber.withValues(alpha: 0.4)),
                      child: Text(_line,
                          textAlign: TextAlign.center,
                          style: Typo.body(15, FontWeight.w500)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(child: _stepBody(session.avatarUrl)),
                  Row(
                    children: [
                      if (_step > 0 && _step < _stepCount - 1)
                        Expanded(
                          child: NeonButton('Indietro',
                              filled: false,
                              color: Palette.textMid,
                              onTap: () => setState(() => _step--)),
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

  Widget _stepBody(String? avatarUrl) {
    switch (_step) {
      case 0:
        return Center(
          child: Text(
            'Poche domande: il profilo che vedono i tuoi atleti e che racconta chi sei.',
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
              for (final (value, label) in _types)
                Pressable(
                  onTap: () => setState(() => _professionalType = value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 13),
                    decoration: BoxDecoration(
                      color: _professionalType == value
                          ? Palette.amber
                          : Palette.void1,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Palette.line),
                    ),
                    child: Text(
                      label,
                      style: Typo.body(
                          15,
                          FontWeight.w700,
                          _professionalType == value
                              ? Palette.void0
                              : Palette.textMid),
                    ),
                  ),
                ),
            ],
          ),
        );
      case 2:
        return Center(
          child: TextField(
            controller: _specialization,
            textAlign: TextAlign.center,
            style: Typo.display(20),
            decoration: InputDecoration(
              hintText: 'es. Ipertrofia e ricomposizione',
              hintStyle: Typo.body(15, FontWeight.w400, Palette.textLow),
            ),
          ),
        );
      case 3:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${_years.round()}', style: Typo.poster(56)),
              Text('ANNI DI ESPERIENZA',
                  style: Typo.mono(9, FontWeight.w700, Palette.textLow)
                      .copyWith(letterSpacing: 2)),
              Slider(
                value: _years,
                min: 0,
                max: 30,
                divisions: 30,
                activeColor: Palette.amber,
                onChanged: (v) {
                  Haptics.soft();
                  setState(() => _years = v);
                },
              ),
            ],
          ),
        );
      case 4:
        return SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final cert in _certOptions)
                Pressable(
                  onTap: () => setState(() {
                    if (!_certifications.remove(cert)) {
                      _certifications.add(cert);
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: _certifications.contains(cert)
                          ? Palette.amber
                          : Palette.void1,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Palette.line),
                    ),
                    child: Text(
                      cert,
                      style: Typo.body(
                          13,
                          FontWeight.w600,
                          _certifications.contains(cert)
                              ? Palette.void0
                              : Palette.textMid),
                    ),
                  ),
                ),
            ],
          ),
        );
      case 5:
        return TextField(
          controller: _bio,
          maxLines: 6,
          style: Typo.body(15, FontWeight.w400),
          decoration: InputDecoration(
            hintText: 'Il mio metodo parte da…',
            hintStyle: Typo.body(15, FontWeight.w400, Palette.textLow),
          ),
        );
      case 6:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AvatarView(
                url: _photoUrl ?? avatarUrl,
                name: ref.read(sessionControllerProvider).greetingName,
                size: 110,
              ),
              const SizedBox(height: 18),
              NeonButton(
                _photoUrl == null ? 'Scegli foto' : 'Cambia foto',
                compact: true,
                expand: false,
                filled: false,
                color: Palette.amber,
                loading: _uploading,
                onTap: _pickPhoto,
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
                _recapRow(
                    'Ruolo',
                    _types
                        .firstWhere(
                          (t) => t.$1 == _professionalType,
                          orElse: () => ('', '—'),
                        )
                        .$2),
                _recapRow(
                    'Specializzazione',
                    _specialization.text.trim().isEmpty
                        ? '—'
                        : _specialization.text.trim()),
                _recapRow('Esperienza', '${_years.round()} anni'),
                _recapRow(
                    'Certificazioni',
                    _certifications.isEmpty
                        ? '—'
                        : '${_certifications.length} selezionate'),
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
            width: 120,
            child: Text(label,
                style: Typo.body(13, FontWeight.w500, Palette.textMid)),
          ),
          Flexible(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Typo.body(14, FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
