import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/providers.dart';
import '../../../core/utils/haptics.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';

/// Block-based check-template composer — port of iOS `CoachCheckBuilderView`:
/// steps + the 7 block types (antropometria, metrica, media, sì/no, radio,
/// checkbox, aperta, allegato), add/reorder/edit/delete, save via the same
/// create/update endpoints the web builder uses.
class CoachCheckBuilderView extends ConsumerStatefulWidget {
  const CoachCheckBuilderView({super.key, this.templateId});

  final int? templateId;

  @override
  ConsumerState<CoachCheckBuilderView> createState() =>
      _CoachCheckBuilderViewState();
}

const _blockTypes = [
  ('antropometria', 'Antropometria', Icons.straighten_rounded),
  ('metrica', 'Metrica', Icons.numbers_rounded),
  ('media', 'Scala 1-10', Icons.tune_rounded),
  ('si_no', 'Sì / No', Icons.rule_rounded),
  ('radio', 'Scelta singola', Icons.radio_button_checked_rounded),
  ('checkbox', 'Scelta multipla', Icons.check_box_rounded),
  ('aperta', 'Risposta aperta', Icons.notes_rounded),
  ('allegato', 'Foto', Icons.photo_camera_rounded),
];

class _CoachCheckBuilderViewState
    extends ConsumerState<CoachCheckBuilderView> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  List<Map<String, dynamic>> _questions = [];
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.templateId != null) _loadExisting();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    try {
      final d = await ref
          .read(apiClientProvider)
          .coachCheckTemplateDetail(widget.templateId!);
      if (mounted) {
        setState(() {
          _title.text = d.title;
          _description.text = d.description;
          _questions = List.of(d.questions);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addBlock(String type) {
    Haptics.thud();
    setState(() {
      _questions = [
        ..._questions,
        {
          'id': 'q${DateTime.now().millisecondsSinceEpoch}',
          'type': type,
          'label': '',
          'required': false,
          if (type == 'radio' || type == 'checkbox') 'options': <String>[],
          if (type == 'metrica') 'unit': '',
          if (type == 'antropometria') 'weight': true,
        },
      ];
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _questions.isEmpty || _saving) {
      StatusFlash.show(context,
          success: false, message: 'Titolo e almeno un blocco richiesti');
      return;
    }
    setState(() => _saving = true);
    final body = {
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'questions': _questions,
      'steps': const <Map<String, dynamic>>[],
    };
    try {
      final api = ref.read(apiClientProvider);
      if (widget.templateId == null) {
        await api.coachCreateCheckTemplate(body);
      } else {
        await api.coachUpdateCheckTemplate(widget.templateId!, body);
      }
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      StatusFlash.show(context, success: true, message: 'Modello salvato');
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        StatusFlash.show(context,
            success: false, message: 'Salvataggio non riuscito');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(
        title: Text(
            widget.templateId == null ? 'Nuovo modello' : 'Modifica modello',
            style: Typo.display(18)),
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(Space.screenH), child: FormSkeleton())
          : ListView(
              padding: const EdgeInsets.all(Space.screenH),
              children: [
                TextField(
                    controller: _title,
                    style: Typo.body(16, FontWeight.w700),
                    decoration:
                        const InputDecoration(labelText: 'Titolo *')),
                const SizedBox(height: 12),
                TextField(
                    controller: _description,
                    maxLines: 2,
                    style: Typo.body(14, FontWeight.w400),
                    decoration:
                        const InputDecoration(labelText: 'Descrizione')),
                const SizedBox(height: 20),
                const Eyebrow('Blocchi'),
                const SizedBox(height: 10),
                if (_questions.isEmpty)
                  const EmptyPanel(
                    icon: Icons.dashboard_customize_outlined,
                    message: 'Aggiungi il primo blocco qui sotto.',
                  )
                else
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    onReorderItem: (oldIndex, newIndex) {
                      setState(() {
                        final item = _questions.removeAt(oldIndex);
                        _questions.insert(newIndex, item);
                      });
                    },
                    children: [
                      for (final (i, q) in _questions.indexed)
                        Padding(
                          key: ValueKey(q['id']),
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _blockCard(i, q),
                        ),
                    ],
                  ),
                const SizedBox(height: 6),
                const Eyebrow('Aggiungi blocco'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (type, label, icon) in _blockTypes)
                      Pressable(
                        onTap: () => _addBlock(type),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Palette.void1,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Palette.line),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 14, color: Palette.violet),
                              const SizedBox(width: 6),
                              Text(label,
                                  style: Typo.body(12.5, FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                NeonButton('Salva modello',
                    color: Palette.violet, loading: _saving, onTap: _save),
                const SizedBox(height: 30),
              ],
            ),
    );
  }

  Widget _blockCard(int index, Map<String, dynamic> q) {
    final type = q['type'] as String? ?? 'aperta';
    final spec = _blockTypes.firstWhere((b) => b.$1 == type,
        orElse: () => _blockTypes.last);
    final options = (q['options'] as List?)?.cast<String>() ?? const [];
    return Container(
      decoration: voltPanel(tint: Palette.violet.withValues(alpha: 0.3)),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_indicator_rounded,
                    size: 18, color: Palette.textLow),
              ),
              const SizedBox(width: 8),
              Icon(spec.$3, size: 15, color: Palette.violet),
              const SizedBox(width: 6),
              Expanded(
                child: Text(spec.$2,
                    style: Typo.mono(10, FontWeight.w700, Palette.violet)
                        .copyWith(letterSpacing: 1)),
              ),
              Text('Obbligatorio',
                  style:
                      Typo.body(11, FontWeight.w500, Palette.textLow)),
              Switch(
                value: (q['required'] as bool?) ?? false,
                onChanged: (v) => setState(() => q['required'] = v),
              ),
              Pressable(
                onTap: () => setState(() => _questions.removeAt(index)),
                child: const Icon(Icons.remove_circle_outline_rounded,
                    size: 18, color: Palette.crimson),
              ),
            ],
          ),
          TextFormField(
            initialValue: q['label'] as String? ?? '',
            style: Typo.body(14.5, FontWeight.w600),
            decoration: const InputDecoration(
                labelText: 'Domanda', isDense: true),
            onChanged: (v) => q['label'] = v,
          ),
          if (type == 'metrica')
            TextFormField(
              initialValue: q['unit'] as String? ?? '',
              style: Typo.body(13.5, FontWeight.w500),
              decoration: const InputDecoration(
                  labelText: 'Unità (es. kg, cm)', isDense: true),
              onChanged: (v) => q['unit'] = v,
            ),
          if (type == 'radio' || type == 'checkbox') ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (oi, opt) in options.indexed)
                  InputChip(
                    label:
                        Text(opt, style: Typo.body(12, FontWeight.w600)),
                    onDeleted: () => setState(() {
                      final next = List<String>.of(options)..removeAt(oi);
                      q['options'] = next;
                    }),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 14),
                  label: Text('Opzione',
                      style: Typo.body(12, FontWeight.w600)),
                  onPressed: () async {
                    final controller = TextEditingController();
                    final value = await showDialog<String>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: Palette.void0,
                        title: Text('Nuova opzione',
                            style: Typo.display(17)),
                        content: TextField(
                            controller: controller, autofocus: true),
                        actions: [
                          TextButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(),
                              child: const Text('Annulla')),
                          TextButton(
                              onPressed: () => Navigator.of(context)
                                  .pop(controller.text.trim()),
                              child: const Text('Aggiungi')),
                        ],
                      ),
                    );
                    if (value != null && value.isNotEmpty) {
                      setState(() =>
                          q['options'] = [...options, value]);
                    }
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
