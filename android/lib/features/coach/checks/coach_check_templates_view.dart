import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/confirm_dialog.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';
import 'coach_assign_check_view.dart';
import 'coach_check_builder_view.dart';

/// Template library — port of iOS `CoachCheckTemplatesSection`/detail:
/// presets + customs, per-template actions (assign / edit / duplicate /
/// delete / restore).
class CoachCheckTemplatesView extends ConsumerStatefulWidget {
  const CoachCheckTemplatesView({super.key});

  @override
  ConsumerState<CoachCheckTemplatesView> createState() =>
      _CoachCheckTemplatesViewState();
}

class _CoachCheckTemplatesViewState
    extends ConsumerState<CoachCheckTemplatesView> {
  CoachCheckTemplatesResponse? _res;
  bool _error = false;
  bool _showPresets = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(apiClientProvider).coachCheckTemplates();
      if (mounted) setState(() => _res = res);
    } catch (_) {
      if (mounted && _res == null) setState(() => _error = true);
    }
  }

  Future<void> _action(CoachCheckTemplate t, String action) async {
    final api = ref.read(apiClientProvider);
    try {
      switch (action) {
        case 'assign':
          await showAppSheet<void>(context,
              builder: (_) => CoachAssignCheckView(template: t));
        case 'edit':
          await showAppSheet<void>(context,
              builder: (_) => CoachCheckBuilderView(templateId: t.id));
        case 'duplicate':
          await api.coachDuplicateCheckTemplate(t.id);
        case 'restore':
          final ok = await ConfirmCenter.confirm(
            context,
            const ConfirmOptions(
              title: 'Ripristinare il preset originale?',
              subtitle: 'Le tue modifiche andranno perse.',
              icon: Icons.restore_rounded,
              variant: ConfirmVariant.danger,
              confirmLabel: 'Ripristina',
            ),
          );
          if (ok) await api.coachRestoreCheckTemplate(t.id);
        case 'delete':
          final ok = await ConfirmCenter.confirm(
            context,
            ConfirmOptions(
              title: 'Eliminare "${t.title}"?',
              icon: Icons.delete_outline_rounded,
              variant: ConfirmVariant.danger,
              confirmLabel: 'Elimina',
            ),
          );
          if (ok) await api.coachDeleteCheckTemplate(t.id);
      }
      await _load();
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Operazione non riuscita');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = _res;
    final list = res == null
        ? const <CoachCheckTemplate>[]
        : (_showPresets ? res.presets : res.customs);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(eyebrow: 'Libreria', title: 'Modelli check'),
          Row(
            children: [
              for (final (value, label) in const [
                (true, 'Preset'),
                (false, 'Personalizzati'),
              ])
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _showPresets = value),
                    child: AnimatedContainer(
                      duration: Motion.snappyDuration,
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _showPresets == value
                            ? Palette.violet
                            : Palette.void1,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Palette.line),
                      ),
                      child: Text(label,
                          style: Typo.body(
                              13,
                              FontWeight.w700,
                              _showPresets == value
                                  ? Palette.void0
                                  : Palette.textMid)),
                    ),
                  ),
                ),
            ],
          ),
          if (res == null && !_error)
            const ListCardsSkeleton(count: 3, height: 110)
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (list.isEmpty)
            EmptyPanel(
              icon: Icons.dashboard_customize_outlined,
              message: _showPresets
                  ? 'Nessun preset disponibile.'
                  : 'Ancora nessun modello personalizzato: creane uno dal Check tab.',
            )
          else
            for (final t in list)
              VoltPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child:
                                Text(t.title, style: Typo.display(17))),
                        if (t.isPreset)
                          StatusBadge('Preset', color: Palette.cyan),
                        if (t.isModifiedPreset)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: StatusBadge('Modificato',
                                color: Palette.amber),
                          ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded,
                              size: 18, color: Palette.textMid),
                          color: Palette.void0,
                          onSelected: (a) => _action(t, a),
                          itemBuilder: (_) => [
                            _item('assign', 'Assegna'),
                            _item('edit', 'Modifica'),
                            _item('duplicate', 'Duplica'),
                            if (t.isModifiedPreset)
                              _item('restore', 'Ripristina preset'),
                            if (!t.isPreset) _item('delete', 'Elimina'),
                          ],
                        ),
                      ],
                    ),
                    if (t.description.isNotEmpty)
                      Text(t.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Typo.body(
                              12.5, FontWeight.w400, Palette.textMid)),
                    const SizedBox(height: 8),
                    Text(
                      '${t.questionsCount} domande · ${t.stepsCount} passi',
                      style:
                          Typo.mono(10, FontWeight.w600, Palette.textLow),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _item(String value, String label) => PopupMenuItem(
        value: value,
        child: Text(label,
            style: Typo.body(14, FontWeight.w500,
                value == 'delete' ? Palette.crimson : Palette.textHi)),
      );
}
