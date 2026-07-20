import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';

/// Assign a check template — port of iOS `CoachAssignCheckView`:
/// multi-select athletes + recurrence (una tantum / settimanale / mensile).
class CoachAssignCheckView extends ConsumerStatefulWidget {
  const CoachAssignCheckView({super.key, required this.template});

  final CoachCheckTemplate template;

  @override
  ConsumerState<CoachAssignCheckView> createState() =>
      _CoachAssignCheckViewState();
}

class _CoachAssignCheckViewState extends ConsumerState<CoachAssignCheckView> {
  List<CoachClientRow>? _clients;
  final Set<int> _selected = {};
  String _recurrence = 'once';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(apiClientProvider)
        .coachClients(status: 'ACTIVE', limit: 100)
        .then((r) => mounted ? setState(() => _clients = r.clients) : null)
        .catchError((_) =>
            mounted ? setState(() => _clients = const []) : null);
  }

  Future<void> _assign() async {
    if (_selected.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(apiClientProvider)
          .coachAssignCheckTemplate(widget.template.id, {
        'client_ids': _selected.toList(),
        'recurrence_type': _recurrence,
      });
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      StatusFlash.show(context, success: true, message: 'Check assegnato');
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        StatusFlash.show(context,
            success: false, message: 'Assegnazione non riuscita');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = _clients;
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(
          title: Text('Assegna "${widget.template.title}"',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Typo.display(16))),
      body: ListView(
        padding: const EdgeInsets.all(Space.screenH),
        children: [
          const Eyebrow('Ricorrenza'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final (v, l) in const [
                ('once', 'Una tantum'),
                ('weekly', 'Settimanale'),
                ('monthly', 'Mensile'),
              ])
                ChoiceChip(
                  label: Text(l, style: Typo.body(13, FontWeight.w600)),
                  selected: _recurrence == v,
                  selectedColor: Palette.violet.withValues(alpha: 0.2),
                  onSelected: (_) => setState(() => _recurrence = v),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const Eyebrow('Atleti'),
          const SizedBox(height: 8),
          if (clients == null)
            const AvatarRowsSkeleton(count: 5)
          else if (clients.isEmpty)
            const EmptyPanel(
                icon: Icons.groups_outlined,
                message: 'Nessun atleta attivo.')
          else
            for (final c in clients)
              CheckboxListTile(
                value: _selected.contains(c.id),
                activeColor: Palette.violet,
                contentPadding: EdgeInsets.zero,
                secondary: AvatarView(
                    url: c.profileImageUrl, name: c.displayName, size: 38),
                title: Text(c.displayName,
                    style: Typo.body(14.5, FontWeight.w600)),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(c.id);
                  } else {
                    _selected.remove(c.id);
                  }
                }),
              ),
          const SizedBox(height: 18),
          NeonButton(
            'Assegna a ${_selected.length} atleti',
            color: Palette.violet,
            loading: _saving,
            onTap: _assign,
          ),
        ],
      ),
    );
  }
}
