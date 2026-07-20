import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/image_compressor.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/theme.dart';
import 'check_success_view.dart';

/// Multi-step check-in compiler — port of iOS `NewCheckView`. Question types:
/// metrica (numeric+unit, range-validated), si_no, radio, checkbox, aperta,
/// media (1–10 slider), allegato (photos ≤6, compressed), antropometria
/// (peso + circumferences + skinfolds grids). Validation scrolls to the
/// offending field with the exact iOS error strings.
class NewCheckView extends ConsumerStatefulWidget {
  const NewCheckView({super.key, required this.check});

  final CheckDto check;

  @override
  ConsumerState<NewCheckView> createState() => _NewCheckViewState();
}

class _NewCheckViewState extends ConsumerState<NewCheckView> {
  final _scroll = ScrollController();
  int _step = 0;
  bool _submitting = false;

  // Answers keyed by question id (String or List<String> or per-antro maps).
  final Map<String, TextEditingController> _text = {};
  final Map<String, String> _choice = {};
  final Map<String, Set<String>> _multi = {};
  final Map<String, double> _slider = {};
  final Map<String, List<Uint8List>> _photos = {};
  final Map<String, String> _errors = {};
  final Map<String, GlobalKey> _fieldKeys = {};

  List<CheckStep> get _steps => widget.check.steps.isEmpty
      ? const [CheckStep(id: '_all', label: 'Check')]
      : widget.check.steps;

  List<CheckQuestion> _questionsFor(CheckStep step) {
    if (step.id == '_all') return widget.check.questions;
    return widget.check.questions
        .where((q) => (q.stepId ?? _steps.first.id) == step.id)
        .toList();
  }

  TextEditingController _ctrl(String key) =>
      _text.putIfAbsent(key, () => TextEditingController());

  GlobalKey _keyFor(String id) => _fieldKeys.putIfAbsent(id, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    ref.read(sessionControllerProvider.notifier).setTabBarHidden(true);
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    _scroll.dispose();
    ref.read(sessionControllerProvider.notifier).setTabBarHidden(false);
    super.dispose();
  }

  // ── Validation (exact iOS copy) ──

  String? _problem(CheckQuestion q) {
    switch (q.type) {
      case 'metrica':
        final raw = _ctrl(q.id).text.trim();
        if (raw.isEmpty) return q.isRequired ? S.vRequired : null;
        final v = Formatters.parseDecimal(raw);
        if (v == null) return S.vNumberOnly;
        if (v <= 0) return S.vPositive;
        if (q.min != null && q.max != null && (v < q.min! || v > q.max!)) {
          return S.vRange(Formatters.decimal(q.min!),
              Formatters.decimal(q.max!), q.unit ?? '');
        }
        return null;
      case 'si_no':
      case 'radio':
        if (q.isRequired && (_choice[q.id] ?? '').isEmpty) return S.vRequired;
        return null;
      case 'checkbox':
        if (q.isRequired && (_multi[q.id] ?? {}).isEmpty) return S.vPickOne;
        return null;
      case 'aperta':
        if (q.isRequired && _ctrl(q.id).text.trim().isEmpty) {
          return S.vRequired;
        }
        return null;
      case 'allegato':
        if (q.isRequired && (_photos[q.id] ?? []).isEmpty) {
          return S.vPhotoRequired;
        }
        return null;
      case 'antropometria':
        if (q.weight) {
          final raw = _ctrl('${q.id}::weight').text.trim();
          if (q.isRequired && raw.isEmpty) return S.vRequired;
          if (raw.isNotEmpty) {
            final v = Formatters.parseDecimal(raw);
            if (v == null) return S.vNumberOnly;
            if (v <= 0) return S.vPositive;
          }
        }
        return null;
      default:
        return null;
    }
  }

  bool _validateStep() {
    final questions = _questionsFor(_steps[_step]);
    _errors.clear();
    String? firstBad;
    for (final q in questions) {
      final problem = _problem(q);
      if (problem != null) {
        _errors[q.id] = problem;
        firstBad ??= q.id;
      }
    }
    setState(() {});
    if (firstBad != null) {
      Haptics.soft();
      final ctx = _keyFor(firstBad).currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: Motion.snappyDuration,
            alignment: 0.2,
            curve: Motion.snappy);
      }
      return false;
    }
    return true;
  }

  Future<void> _advance() async {
    if (!_validateStep()) return;
    if (_step < _steps.length - 1) {
      Haptics.tap();
      setState(() => _step++);
      _scroll.jumpTo(0);
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final answers = <String, dynamic>{};
    for (final q in widget.check.questions) {
      switch (q.type) {
        case 'metrica':
        case 'aperta':
          final v = _ctrl(q.id).text.trim();
          if (v.isNotEmpty) answers[q.id] = v.replaceAll(',', '.');
        case 'si_no':
        case 'radio':
          final v = _choice[q.id];
          if (v != null && v.isNotEmpty) answers[q.id] = v;
        case 'checkbox':
          final v = _multi[q.id];
          if (v != null && v.isNotEmpty) answers[q.id] = v.toList();
        case 'media':
          answers[q.id] = (_slider[q.id] ?? 5).round().toString();
        case 'antropometria':
          if (q.weight) {
            final w = _ctrl('${q.id}::weight').text.trim();
            if (w.isNotEmpty) answers['peso'] = w.replaceAll(',', '.');
          }
          for (final c in q.circumferences) {
            final v = _ctrl('${q.id}::c::${c.key}').text.trim();
            if (v.isNotEmpty) {
              answers['circumference_${c.key}'] = v.replaceAll(',', '.');
            }
          }
          for (final s in q.skinfolds) {
            final v = _ctrl('${q.id}::s::${s.key}').text.trim();
            if (v.isNotEmpty) {
              answers['skinfold_${s.key}'] = v.replaceAll(',', '.');
            }
          }
      }
    }
    try {
      await ref.read(apiClientProvider).submitCheck(
            widget.check.id,
            answers,
            attachments: _photos,
          );
      Haptics.success();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => CheckSuccessView(title: widget.check.title)));
    } catch (_) {
      if (mounted) {
        Haptics.error();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(S.errGeneric,
              style: Typo.body(14, FontWeight.w600, Palette.void0)),
          backgroundColor: Palette.crimson,
        ));
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _pickPhotos(CheckQuestion q) async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(limit: 6);
    if (picked.isEmpty) return;
    final existing = _photos[q.id] ?? [];
    for (final file in picked.take(6 - existing.length)) {
      final bytes = await file.readAsBytes();
      existing.add(await ImageCompressor.jpeg(bytes));
    }
    setState(() => _photos[q.id] = existing);
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final questions = _questionsFor(step);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Column(
          children: [
            Text(widget.check.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Typo.display(16)),
            Text('PASSO ${_step + 1} DI ${_steps.length}',
                style: Typo.mono(8, FontWeight.w700, Palette.textLow)
                    .copyWith(letterSpacing: 1.5)),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: Space.screenH),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (_step + 1) / _steps.length,
                minHeight: 4,
                backgroundColor: Palette.void2,
                color: Palette.violet,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(
                  Space.screenH, 18, Space.screenH, 30),
              children: [
                Eyebrow(step.label),
                const SizedBox(height: 12),
                for (final q in questions) ...[
                  KeyedSubtree(key: _keyFor(q.id), child: _questionCard(q)),
                  const SizedBox(height: Space.element),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.screenH, 6, Space.screenH, 12),
              child: Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: NeonButton(
                        S.back,
                        filled: false,
                        color: Palette.textMid,
                        onTap: () {
                          Haptics.tap();
                          setState(() => _step--);
                          _scroll.jumpTo(0);
                        },
                      ),
                    ),
                  if (_step > 0) const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: NeonButton(
                      _step == _steps.length - 1 ? 'Invia' : S.next,
                      color: Palette.violet,
                      loading: _submitting,
                      onTap: _advance,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _questionCard(CheckQuestion q) {
    final error = _errors[q.id];
    return Container(
      decoration: voltPanel(
          tint: error != null
              ? Palette.crimson.withValues(alpha: 0.6)
              : Palette.line),
      padding: const EdgeInsets.all(Space.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(q.label, style: Typo.body(15, FontWeight.w700)),
              ),
              if (q.isRequired)
                Text('*', style: Typo.body(15, FontWeight.w700, Palette.crimson)),
            ],
          ),
          const SizedBox(height: 10),
          switch (q.type) {
            'metrica' => _metricaField(q),
            'si_no' => _choiceChips(q, const ['Sì', 'No']),
            'radio' => _choiceChips(q, q.options),
            'checkbox' => _multiChips(q),
            'media' => _mediaSlider(q),
            'allegato' => _photoPicker(q),
            'antropometria' => _antropometria(q),
            _ => _apertaField(q),
          },
          if (error != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 14, color: Palette.crimson),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(error,
                      style:
                          Typo.body(12.5, FontWeight.w600, Palette.crimson)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricaField(CheckQuestion q) {
    return TextField(
      controller: _ctrl(q.id),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: Typo.mono(17, FontWeight.w700),
      decoration: InputDecoration(
        hintText: q.placeholder ?? '0,0',
        suffixText: q.unit,
        suffixStyle: Typo.mono(13, FontWeight.w600, Palette.textMid),
      ),
    );
  }

  Widget _apertaField(CheckQuestion q) {
    return TextField(
      controller: _ctrl(q.id),
      maxLines: 4,
      minLines: 2,
      style: Typo.body(14.5, FontWeight.w400),
      decoration: InputDecoration(
        hintText: q.placeholder ?? 'Scrivi qui…',
      ),
    );
  }

  Widget _choiceChips(CheckQuestion q, List<String> options) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final opt in options)
          Pressable(
            onTap: () => setState(() => _choice[q.id] = opt),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: _choice[q.id] == opt
                    ? Palette.violet
                    : Palette.void0,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Palette.line),
              ),
              child: Text(
                opt,
                style: Typo.body(13.5, FontWeight.w600,
                    _choice[q.id] == opt ? Palette.void0 : Palette.textMid),
              ),
            ),
          ),
      ],
    );
  }

  Widget _multiChips(CheckQuestion q) {
    final selected = _multi.putIfAbsent(q.id, () => {});
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final opt in q.options)
          Pressable(
            onTap: () => setState(() {
              if (!selected.remove(opt)) selected.add(opt);
            }),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: selected.contains(opt)
                    ? Palette.violet
                    : Palette.void0,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Palette.line),
              ),
              child: Text(
                opt,
                style: Typo.body(
                    13.5,
                    FontWeight.w600,
                    selected.contains(opt)
                        ? Palette.void0
                        : Palette.textMid),
              ),
            ),
          ),
      ],
    );
  }

  Widget _mediaSlider(CheckQuestion q) {
    final value = _slider[q.id] ?? 5;
    return Column(
      children: [
        Text('${value.round()}', style: Typo.poster(34)),
        Slider(
          value: value,
          min: q.min ?? 1,
          max: q.max ?? 10,
          divisions: ((q.max ?? 10) - (q.min ?? 1)).round(),
          activeColor: Palette.violet,
          onChanged: (v) {
            Haptics.soft();
            setState(() => _slider[q.id] = v);
          },
        ),
        Row(
          children: [
            Text(q.minLabel ?? '',
                style: Typo.body(11, FontWeight.w500, Palette.textLow)),
            const Spacer(),
            Text(q.maxLabel ?? '',
                style: Typo.body(11, FontWeight.w500, Palette.textLow)),
          ],
        ),
      ],
    );
  }

  Widget _photoPicker(CheckQuestion q) {
    final photos = _photos[q.id] ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, bytes) in photos.indexed)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(bytes,
                        width: 68, height: 88, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Pressable(
                      onTap: () =>
                          setState(() => _photos[q.id]!.removeAt(i)),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                            color: Palette.crimson, shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded,
                            size: 12, color: Palette.void0),
                      ),
                    ),
                  ),
                ],
              ),
            if (photos.length < 6)
              Pressable(
                onTap: () => _pickPhotos(q),
                child: Container(
                  width: 68,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Palette.void0,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Palette.line),
                  ),
                  child: const Icon(Icons.add_a_photo_outlined,
                      size: 20, color: Palette.textMid),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text('Fino a 6 foto.',
            style: Typo.body(11, FontWeight.w400, Palette.textLow)),
      ],
    );
  }

  Widget _antropometria(CheckQuestion q) {
    Widget numberField(String key, String label, String unit) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: Typo.body(13, FontWeight.w500, Palette.textMid)),
            ),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _ctrl(key),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.end,
                style: Typo.mono(14, FontWeight.w700),
                decoration: InputDecoration(
                  hintText: '—',
                  isDense: true,
                  suffixText: unit,
                  suffixStyle:
                      Typo.mono(11, FontWeight.w600, Palette.textLow),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (q.weight) numberField('${q.id}::weight', 'Peso corporeo', 'kg'),
        if (q.circumferences.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Eyebrow('Circonferenze'),
          const SizedBox(height: 8),
          for (final c in q.circumferences)
            numberField('${q.id}::c::${c.key}', c.label, 'cm'),
        ],
        if (q.skinfolds.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Eyebrow('Pliche'),
          const SizedBox(height: 8),
          for (final s in q.skinfolds)
            numberField('${q.id}::s::${s.key}', s.label, 'mm'),
        ],
      ],
    );
  }
}
