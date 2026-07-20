import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/confirm_dialog.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';

/// Resource library — port of iOS `CoachResourcesView`: collapsible sections
/// (schede, piani, modelli check, protocolli integratori) with counts.
class CoachResourcesView extends ConsumerStatefulWidget {
  const CoachResourcesView({super.key});

  @override
  ConsumerState<CoachResourcesView> createState() =>
      _CoachResourcesViewState();
}

class _CoachResourcesViewState extends ConsumerState<CoachResourcesView> {
  CoachResourcesResponse? _res;
  bool _error = false;
  final Set<String> _open = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(apiClientProvider).coachResources();
      if (mounted) setState(() => _res = res);
    } catch (_) {
      if (mounted && _res == null) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = _res;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(
              eyebrow: 'Tutto il tuo materiale', title: 'Libreria'),
          if (res == null && !_error)
            const ListCardsSkeleton(count: 4, height: 80)
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (res!.sections.isEmpty)
            const EmptyPanel(
              icon: Icons.folder_copy_outlined,
              message: 'Nessuna risorsa ancora creata.',
            )
          else
            for (final section in res.sections)
              VoltPanel(
                padding: EdgeInsets.zero,
                child: Pressable(
                  onTap: () => setState(() {
                    if (!_open.remove(section.key)) _open.add(section.key);
                  }),
                  child: Padding(
                    padding: const EdgeInsets.all(Space.card),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(section.title,
                                  style: Typo.display(17)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(
                                color:
                                    Palette.bronze.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text('${section.count}',
                                  style: Typo.mono(11, FontWeight.w700,
                                      Palette.bronze)),
                            ),
                            const SizedBox(width: 8),
                            AnimatedRotation(
                              turns: _open.contains(section.key) ? 0.5 : 0,
                              duration: Motion.snappyDuration,
                              child: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 20,
                                  color: Palette.textLow),
                            ),
                          ],
                        ),
                        AnimatedCrossFade(
                          firstChild: const SizedBox(width: double.infinity),
                          secondChild: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Column(
                              children: [
                                for (final item in section.items)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      children: [
                                        const Icon(
                                            Icons.chevron_right_rounded,
                                            size: 15,
                                            color: Palette.textLow),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(item.title,
                                              style: Typo.body(
                                                  13.5, FontWeight.w500)),
                                        ),
                                        if ((item.subtitle ?? '').isNotEmpty)
                                          Text(item.subtitle!,
                                              style: Typo.mono(
                                                  9.5,
                                                  FontWeight.w600,
                                                  Palette.textLow)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          crossFadeState: _open.contains(section.key)
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          duration: Motion.snappyDuration,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          NavListRow(
            title: 'Protocolli integratori',
            subtitle: 'Crea e assegna protocolli',
            icon: Icons.medication_rounded,
            accent: Palette.lime,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const CoachSupplementsView())),
          ),
        ],
      ),
    );
  }
}

/// Supplement-protocol CRUD + assignment — port of iOS
/// `CoachSupplementsView`/`Builder`/`AssignView`.
class CoachSupplementsView extends ConsumerStatefulWidget {
  const CoachSupplementsView({super.key});

  @override
  ConsumerState<CoachSupplementsView> createState() =>
      _CoachSupplementsViewState();
}

class _CoachSupplementsViewState extends ConsumerState<CoachSupplementsView> {
  List<CoachSupplementSummary>? _protocols;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(apiClientProvider).coachSupplements();
      if (mounted) setState(() => _protocols = res.protocols);
    } catch (_) {
      if (mounted && _protocols == null) setState(() => _error = true);
    }
  }

  Future<void> _openBuilder({int? protocolId}) async {
    await showAppSheet<void>(
      context,
      builder: (_) =>
          CoachSupplementBuilderSheet(protocolId: protocolId, onSaved: _load),
    );
  }

  Future<void> _assign(CoachSupplementSummary p) async {
    await showAppSheet<void>(
      context,
      heightFactor: 0.8,
      builder: (_) => _AssignSupplementSheet(protocol: p, onDone: _load),
    );
  }

  Future<void> _delete(CoachSupplementSummary p) async {
    final ok = await ConfirmCenter.confirm(
      context,
      ConfirmOptions(
        title: 'Eliminare "${p.title}"?',
        icon: Icons.delete_outline_rounded,
        variant: ConfirmVariant.danger,
        confirmLabel: 'Elimina',
      ),
    );
    if (!ok) return;
    try {
      await ref.read(apiClientProvider).coachDeleteSupplement(p.id);
      await _load();
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Eliminazione non riuscita');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final protocols = _protocols;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Nuovo protocollo',
            icon: const Icon(Icons.add_rounded, color: Palette.textHi),
            onPressed: () => _openBuilder(),
          ),
        ],
      ),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(
              eyebrow: 'Integrazione', title: 'Protocolli'),
          if (protocols == null && !_error)
            const ListCardsSkeleton(count: 3, height: 100)
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (protocols!.isEmpty)
            const EmptyPanel(
              icon: Icons.medication_outlined,
              message: 'Nessun protocollo: creane uno con il +.',
            )
          else
            for (final p in protocols)
              VoltPanel(
                tint: Palette.lime.withValues(alpha: 0.35),
                onTap: () => _openBuilder(protocolId: p.id),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child:
                                Text(p.title, style: Typo.display(17))),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded,
                              size: 18, color: Palette.textMid),
                          color: Palette.void0,
                          onSelected: (a) =>
                              a == 'assign' ? _assign(p) : _delete(p),
                          itemBuilder: (_) => [
                            PopupMenuItem(
                                value: 'assign',
                                child: Text('Assegna',
                                    style:
                                        Typo.body(14, FontWeight.w500))),
                            PopupMenuItem(
                                value: 'delete',
                                child: Text('Elimina',
                                    style: Typo.body(14, FontWeight.w500,
                                        Palette.crimson))),
                          ],
                        ),
                      ],
                    ),
                    Text(
                      '${p.itemsCount} integratori · ${p.assignedCount} assegnazioni',
                      style:
                          Typo.mono(10, FontWeight.w600, Palette.textMid),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class CoachSupplementBuilderSheet extends ConsumerStatefulWidget {
  const CoachSupplementBuilderSheet({
    super.key,
    this.protocolId,
    required this.onSaved,
  });

  final int? protocolId;
  final VoidCallback onSaved;

  @override
  ConsumerState<CoachSupplementBuilderSheet> createState() =>
      _CoachSupplementBuilderSheetState();
}

class _CoachSupplementBuilderSheetState
    extends ConsumerState<CoachSupplementBuilderSheet> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.protocolId != null) _loadExisting();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    try {
      final d = await ref
          .read(apiClientProvider)
          .coachSupplementDetail(widget.protocolId!);
      if (mounted) {
        setState(() {
          _title.text = d.title;
          _notes.text = d.notes ?? '';
          _items = [
            for (final i in d.items)
              {
                'id': i.id,
                'name': i.name,
                'quantity': i.quantity,
                'unit': i.unit,
                'timing': i.timing,
                'notes': i.notes,
              },
          ];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _saving) {
      StatusFlash.show(context,
          success: false, message: 'Serve un titolo');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).coachSaveSupplement({
        if (widget.protocolId != null) 'id': widget.protocolId,
        'title': _title.text.trim(),
        'notes': _notes.text.trim(),
        'items': _items,
      });
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context, rootNavigator: true).pop();
      StatusFlash.show(context, success: true, message: 'Protocollo salvato');
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
              widget.protocolId == null
                  ? 'Nuovo protocollo'
                  : 'Modifica protocollo',
              style: Typo.display(18))),
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
                    controller: _notes,
                    maxLines: 2,
                    style: Typo.body(14, FontWeight.w400),
                    decoration:
                        const InputDecoration(labelText: 'Note generali')),
                const SizedBox(height: 18),
                const Eyebrow('Integratori'),
                const SizedBox(height: 10),
                for (final (i, item) in _items.indexed)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: voltPanel(),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue:
                                    item['name'] as String? ?? '',
                                style: Typo.body(14.5, FontWeight.w700),
                                decoration: const InputDecoration(
                                    hintText: 'Nome',
                                    isDense: true,
                                    border: InputBorder.none),
                                onChanged: (v) => item['name'] = v,
                              ),
                            ),
                            Pressable(
                              onTap: () =>
                                  setState(() => _items.removeAt(i)),
                              child: const Icon(Icons.close_rounded,
                                  size: 17, color: Palette.textLow),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue:
                                    item['quantity'] as String? ?? '',
                                textAlign: TextAlign.center,
                                style: Typo.mono(12.5, FontWeight.w700),
                                decoration: InputDecoration(
                                  labelText: 'Dose',
                                  isDense: true,
                                  labelStyle: Typo.mono(
                                      9, FontWeight.w600, Palette.textLow),
                                ),
                                onChanged: (v) => item['quantity'] = v,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextFormField(
                                initialValue: item['unit'] as String? ?? '',
                                textAlign: TextAlign.center,
                                style: Typo.mono(12.5, FontWeight.w700),
                                decoration: InputDecoration(
                                  labelText: 'Unità',
                                  isDense: true,
                                  labelStyle: Typo.mono(
                                      9, FontWeight.w600, Palette.textLow),
                                ),
                                onChanged: (v) => item['unit'] = v,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                initialValue:
                                    item['timing'] as String? ?? '',
                                textAlign: TextAlign.center,
                                style: Typo.mono(12.5, FontWeight.w700),
                                decoration: InputDecoration(
                                  labelText: 'Quando',
                                  isDense: true,
                                  labelStyle: Typo.mono(
                                      9, FontWeight.w600, Palette.textLow),
                                ),
                                onChanged: (v) => item['timing'] = v,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                NeonButton(
                  'Aggiungi integratore',
                  filled: false,
                  color: Palette.lime,
                  icon: Icons.add_rounded,
                  onTap: () => setState(() => _items.add({
                        'name': '',
                        'quantity': '',
                        'unit': '',
                        'timing': '',
                      })),
                ),
                const SizedBox(height: 20),
                NeonButton('Salva protocollo',
                    color: Palette.lime, loading: _saving, onTap: _save),
                const SizedBox(height: 30),
              ],
            ),
    );
  }
}

class _AssignSupplementSheet extends ConsumerStatefulWidget {
  const _AssignSupplementSheet({required this.protocol, required this.onDone});

  final CoachSupplementSummary protocol;
  final VoidCallback onDone;

  @override
  ConsumerState<_AssignSupplementSheet> createState() =>
      _AssignSupplementSheetState();
}

class _AssignSupplementSheetState
    extends ConsumerState<_AssignSupplementSheet> {
  List<CoachAssignableClient>? _clients;
  final Set<int> _selected = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(apiClientProvider)
        .coachSupplementAssignableClients(
            excludeProtocolId: widget.protocol.id)
        .then((c) => mounted ? setState(() => _clients = c) : null)
        .catchError(
            (_) => mounted ? setState(() => _clients = const []) : null);
  }

  Future<void> _assign() async {
    if (_selected.isEmpty || _saving) return;
    // Overwrite-active confirmation (parity with iOS).
    final overwriting = (_clients ?? [])
        .where((c) => _selected.contains(c.id))
        .any((c) => c.activeProtocol != null || c.activeAssignment != null);
    if (overwriting) {
      final ok = await ConfirmCenter.confirm(
        context,
        const ConfirmOptions(
          title: 'Sostituire il protocollo attivo?',
          subtitle:
              'Alcuni atleti hanno già un protocollo: verrà sostituito.',
          icon: Icons.swap_horiz_rounded,
          variant: ConfirmVariant.danger,
          confirmLabel: 'Sostituisci',
        ),
      );
      if (!ok) return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(apiClientProvider)
          .coachAssignSupplement(widget.protocol.id, _selected.toList());
      if (!mounted) return;
      widget.onDone();
      Navigator.of(context, rootNavigator: true).pop();
      StatusFlash.show(context,
          success: true, message: 'Protocollo assegnato');
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
          title: Text('Assegna protocollo', style: Typo.display(18))),
      body: ListView(
        padding: const EdgeInsets.all(Space.screenH),
        children: [
          if (clients == null)
            const AvatarRowsSkeleton(count: 5)
          else if (clients.isEmpty)
            const EmptyPanel(
                icon: Icons.groups_outlined,
                message: 'Nessun atleta disponibile.')
          else
            for (final c in clients)
              CheckboxListTile(
                value: _selected.contains(c.id),
                activeColor: Palette.lime,
                contentPadding: EdgeInsets.zero,
                secondary: AvatarView(
                    url: c.profileImageUrl, name: c.displayName, size: 38),
                title: Text(c.displayName,
                    style: Typo.body(14.5, FontWeight.w600)),
                subtitle: (c.activeProtocol ?? c.activeAssignment) == null
                    ? null
                    : Text('Ha già un protocollo attivo',
                        style: Typo.body(
                            11, FontWeight.w400, Palette.amber)),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(c.id);
                  } else {
                    _selected.remove(c.id);
                  }
                }),
              ),
          const SizedBox(height: 18),
          NeonButton('Assegna a ${_selected.length} atleti',
              color: Palette.lime, loading: _saving, onTap: _assign),
        ],
      ),
    );
  }
}
