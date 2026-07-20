import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/providers.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';

/// Chiron AI document import — port of iOS `CoachPlanCreateView`'s import
/// tab: upload PDF/Excel → async parse with rotating status phrases →
/// structured review → confirm as draft. Reuses the web importer endpoints.
class CoachPlanImportView extends ConsumerStatefulWidget {
  const CoachPlanImportView({super.key, required this.workout});

  final bool workout;

  @override
  ConsumerState<CoachPlanImportView> createState() =>
      _CoachPlanImportViewState();
}

enum _ImportPhase { pick, analyzing, review, done }

class _CoachPlanImportViewState extends ConsumerState<CoachPlanImportView> {
  _ImportPhase _phase = _ImportPhase.pick;
  Map<String, dynamic>? _parsed;
  String _statusLine = 'Chiron sta leggendo il documento…';
  Timer? _poll;
  Timer? _phrases;
  int _phraseIdx = 0;

  static const _statusPhrases = [
    'Chiron sta leggendo il documento…',
    'Riconosco giorni ed esercizi…',
    'Normalizzo serie e ripetizioni…',
    'Ancora un momento…',
  ];

  @override
  void dispose() {
    _poll?.cancel();
    _phrases?.cancel();
    super.dispose();
  }

  Future<void> _pickFile() async {
    // PDF/Excel arrive via the system file picker; image_picker covers media.
    // Without a dedicated file-picker dependency we accept any file through
    // the media picker's recent-files surface; PDF support lands with a
    // file_selector swap (single call site).
    final picked = await ImagePicker().pickMedia();
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final name = picked.name;
    final isExcel = name.endsWith('.xlsx') || name.endsWith('.xls');
    setState(() {
      _phase = _ImportPhase.analyzing;
      _phraseIdx = 0;
      _statusLine = _statusPhrases.first;
    });
    _phrases = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        setState(() {
          _phraseIdx = (_phraseIdx + 1) % _statusPhrases.length;
          _statusLine = _statusPhrases[_phraseIdx];
        });
      }
    });
    try {
      final res = await ref.read(apiClientProvider).importPlanFile(
            workout: widget.workout,
            excel: isExcel,
            bytes: bytes,
            filename: name,
          );
      final jobId = res['job_id'] as String?;
      if (jobId != null) {
        _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
          try {
            final status = await ref
                .read(apiClientProvider)
                .importPlanStatus(workout: widget.workout, jobId: jobId);
            if ((status['status'] as String?) == 'done') {
              _poll?.cancel();
              _phrases?.cancel();
              if (mounted) {
                setState(() {
                  _parsed = (status['result'] as Map?)
                          ?.cast<String, dynamic>() ??
                      status;
                  _phase = _ImportPhase.review;
                });
              }
            } else if ((status['status'] as String?) == 'error') {
              throw Exception('import failed');
            }
          } catch (_) {
            _poll?.cancel();
            _phrases?.cancel();
            if (mounted) {
              setState(() => _phase = _ImportPhase.pick);
              StatusFlash.show(context,
                  success: false, message: 'Analisi non riuscita');
            }
          }
        });
      } else {
        // Synchronous (Excel) result.
        _phrases?.cancel();
        setState(() {
          _parsed = (res['result'] as Map?)?.cast<String, dynamic>() ?? res;
          _phase = _ImportPhase.review;
        });
      }
    } catch (_) {
      _phrases?.cancel();
      if (mounted) {
        setState(() => _phase = _ImportPhase.pick);
        StatusFlash.show(context,
            success: false, message: 'Caricamento non riuscito');
      }
    }
  }

  Future<void> _confirm() async {
    final parsed = _parsed;
    if (parsed == null) return;
    try {
      await ref
          .read(apiClientProvider)
          .importPlanConfirm(workout: widget.workout, body: parsed);
      if (!mounted) return;
      setState(() => _phase = _ImportPhase.done);
      StatusFlash.show(context,
          success: true, message: 'Bozza creata dall\'import');
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Conferma non riuscita');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(
          title: Text('Import con Chiron', style: Typo.display(18))),
      body: Padding(
        padding: const EdgeInsets.all(Space.screenH),
        child: switch (_phase) {
          _ImportPhase.pick => Column(
              children: [
                const SizedBox(height: 20),
                const Icon(Icons.auto_awesome_rounded,
                    size: 44, color: Palette.amber),
                const SizedBox(height: 16),
                Text('Importa un piano esistente',
                    textAlign: TextAlign.center, style: Typo.poster(28)),
                const SizedBox(height: 10),
                Text(
                  widget.workout
                      ? 'Carica un PDF o un Excel con la scheda: Chiron la trasforma in una bozza modificabile.'
                      : 'Carica un PDF o un Excel con la dieta: Chiron la trasforma in una bozza modificabile.',
                  textAlign: TextAlign.center,
                  style: Typo.body(14, FontWeight.w400, Palette.textMid),
                ),
                const Spacer(),
                NeonButton('Scegli file',
                    color: Palette.amber,
                    icon: Icons.upload_file_rounded,
                    onTap: _pickFile),
                const SizedBox(height: 20),
              ],
            ),
          _ImportPhase.analyzing => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Palette.amber),
                  const SizedBox(height: 20),
                  AnimatedSwitcher(
                    duration: Motion.snappyDuration,
                    child: Text(
                      _statusLine,
                      key: ValueKey(_statusLine),
                      textAlign: TextAlign.center,
                      style: Typo.body(15, FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          _ => ListView(
              children: [
                const Eyebrow('Anteprima import'),
                const SizedBox(height: 10),
                VoltPanel(
                  child: Text(
                    _summaryText(),
                    style: Typo.body(14, FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 18),
                NeonButton('Crea bozza',
                    color: Palette.amber, onTap: _confirm),
                const SizedBox(height: 10),
                NeonButton('Annulla',
                    filled: false,
                    color: Palette.textMid,
                    onTap: () =>
                        setState(() => _phase = _ImportPhase.pick)),
              ],
            ),
        },
      ),
    );
  }

  String _summaryText() {
    final p = _parsed;
    if (p == null) return '—';
    final title = p['title'] ?? 'Piano importato';
    final days = (p['days'] as List?)?.length ?? 0;
    return '$title\n$days giorni riconosciuti. Conferma per creare la bozza, poi rifiniscila nel builder.';
  }
}
