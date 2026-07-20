import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';
import 'coach_client_detail_view.dart';

/// Roster — port of iOS `CoachClientsView`: search + status filter + rows
/// with active plan/check info, add-athlete flow.
class CoachClientsView extends ConsumerStatefulWidget {
  const CoachClientsView({super.key});

  @override
  ConsumerState<CoachClientsView> createState() => _CoachClientsViewState();
}

class _CoachClientsViewState extends ConsumerState<CoachClientsView> {
  final _query = TextEditingController();
  CoachClientsResponse? _res;
  bool _error = false;
  bool _loadingMore = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ref
          .read(apiClientProvider)
          .coachClients(q: _query.text.trim(), status: _status);
      if (mounted) setState(() => _res = res);
    } catch (_) {
      if (mounted && _res == null) setState(() => _error = true);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _res == null) return;
    setState(() => _loadingMore = true);
    try {
      final more = await ref.read(apiClientProvider).coachClients(
          q: _query.text.trim(),
          status: _status,
          offset: _res!.clients.length);
      if (mounted) {
        setState(() => _res = _res!.copyWith(
            clients: [..._res!.clients, ...more.clients],
            hasMore: more.hasMore));
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _openAdd() {
    showAppSheet<void>(
      context,
      builder: (_) => CoachAddClientSheet(onDone: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    final res = _res;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Aggiungi atleta',
            icon: Icon(Icons.person_add_alt_rounded, color: Palette.bronze),
            onPressed: _openAdd,
          ),
        ],
      ),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          ScreenHeader(
            eyebrow: res == null
                ? 'I tuoi atleti'
                : '${res.active} attivi · ${res.total} totali',
            title: 'Atleti',
          ),
          Container(
            decoration: voltPanel(radius: Radii.field),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(Icons.search_rounded,
                    size: 18, color: Palette.textLow),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _query,
                    style: Typo.body(15, FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: 'Cerca un atleta…',
                      hintStyle:
                          Typo.body(15, FontWeight.w400, Palette.textLow),
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => _load(),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              for (final (value, label) in const [
                ('', 'Tutti'),
                ('ACTIVE', 'Attivi'),
                ('INACTIVE', 'Inattivi'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Pressable(
                    onTap: () {
                      setState(() => _status = value);
                      _load();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _status == value
                            ? Palette.textHi
                            : Palette.void1,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Palette.line),
                      ),
                      child: Text(label,
                          style: Typo.body(
                              12.5,
                              FontWeight.w600,
                              _status == value
                                  ? Palette.void0
                                  : Palette.textMid)),
                    ),
                  ),
                ),
            ],
          ),
          if (res == null && !_error)
            const AvatarRowsSkeleton()
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (res!.clients.isEmpty)
            const EmptyPanel(
              icon: Icons.groups_outlined,
              message: 'Nessun atleta trovato. Aggiungine uno con il +.',
            )
          else ...[
            for (final c in res.clients) _clientRow(c),
            if (res.hasMore)
              LoadMoreButton(onTap: _loadMore, loading: _loadingMore),
          ],
        ],
      ),
    );
  }

  Widget _clientRow(CoachClientRow c) {
    final active = (c.status ?? '').toUpperCase() == 'ACTIVE';
    return VoltPanel(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CoachClientDetailView(clientId: c.id))),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          AvatarView(url: c.profileImageUrl, name: c.displayName, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.displayName, style: Typo.body(15, FontWeight.w700)),
                Text(
                  [
                    c.relationshipLabel,
                    if (c.activeWorkout != null) c.activeWorkout!,
                    if (c.lastCheckAt != null &&
                        Formatters.parseDate(c.lastCheckAt) != null)
                      'check ${Formatters.relative(Formatters.parseDate(c.lastCheckAt)!.toLocal())}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Typo.body(11.5, FontWeight.w400, Palette.textMid),
                ),
              ],
            ),
          ),
          StatusBadge(active ? 'Attivo' : (c.status ?? '—'),
              color: active ? Palette.lime : Palette.textLow),
        ],
      ),
    );
  }
}

/// Add-athlete flow — port of iOS `CoachAddClientView`: new account or
/// attach-existing, optional pre-paid plan.
class CoachAddClientSheet extends ConsumerStatefulWidget {
  const CoachAddClientSheet({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<CoachAddClientSheet> createState() =>
      _CoachAddClientSheetState();
}

class _CoachAddClientSheetState extends ConsumerState<CoachAddClientSheet> {
  bool _existing = false;
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  String? _gender;
  bool _alreadyPaid = false;
  int? _planId;
  List<CoachSubscriptionPlanRow> _plans = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref
        .read(apiClientProvider)
        .coachSubscriptionPlans()
        .then((p) => mounted ? setState(() => _plans = p) : null)
        .catchError((_) => null);
  }

  Future<void> _save() async {
    if (_email.text.trim().isEmpty ||
        (!_existing && (_first.text.trim().isEmpty))) {
      setState(() => _error = 'Compila i campi obbligatori.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).coachCreateClient({
        'mode': _existing ? 'existing' : 'new',
        'email': _email.text.trim(),
        if (!_existing) 'first_name': _first.text.trim(),
        if (!_existing) 'last_name': _last.text.trim(),
        if (!_existing && _phone.text.trim().isNotEmpty)
          'phone': _phone.text.trim(),
        if (!_existing && _gender != null) 'gender': _gender,
        'already_paid': _alreadyPaid,
        if (_alreadyPaid && _planId != null) 'subscription_plan_id': _planId,
      });
      if (!mounted) return;
      widget.onDone();
      Navigator.of(context, rootNavigator: true).pop();
      StatusFlash.show(context,
          success: true,
          message: _existing ? 'Atleta collegato' : 'Invito inviato');
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Operazione non riuscita. Controlla l\'email.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar:
          AppBar(title: Text('Nuovo atleta', style: Typo.display(18))),
      body: ListView(
        padding: const EdgeInsets.all(Space.screenH),
        children: [
          Row(
            children: [
              for (final (value, label) in const [
                (false, 'Nuovo account'),
                (true, 'Già registrato'),
              ])
                Expanded(
                  child: Pressable(
                    onTap: () => setState(() => _existing = value),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _existing == value
                            ? Palette.bronze
                            : Palette.void1,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Palette.line),
                      ),
                      child: Text(label,
                          style: Typo.body(
                              13,
                              FontWeight.w700,
                              _existing == value
                                  ? Palette.void0
                                  : Palette.textMid)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              style: Typo.body(15, FontWeight.w600),
              decoration: const InputDecoration(labelText: 'Email *')),
          if (!_existing) ...[
            const SizedBox(height: 12),
            TextField(
                controller: _first,
                style: Typo.body(15, FontWeight.w600),
                decoration: const InputDecoration(labelText: 'Nome *')),
            const SizedBox(height: 12),
            TextField(
                controller: _last,
                style: Typo.body(15, FontWeight.w600),
                decoration: const InputDecoration(labelText: 'Cognome')),
            const SizedBox(height: 12),
            TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                style: Typo.body(15, FontWeight.w600),
                decoration: const InputDecoration(labelText: 'Telefono')),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (final (v, l) in const [
                  ('M', 'Uomo'),
                  ('F', 'Donna'),
                  ('O', 'Altro')
                ])
                  ChoiceChip(
                    label: Text(l, style: Typo.body(13, FontWeight.w600)),
                    selected: _gender == v,
                    selectedColor: Palette.bronze.withValues(alpha: 0.2),
                    onSelected: (_) => setState(() => _gender = v),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Ha già pagato',
                style: Typo.body(14.5, FontWeight.w600)),
            subtitle: Text('Attiva subito un abbonamento manuale',
                style: Typo.body(12, FontWeight.w400, Palette.textLow)),
            value: _alreadyPaid,
            onChanged: (v) => setState(() => _alreadyPaid = v),
          ),
          if (_alreadyPaid && _plans.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _plans)
                  ChoiceChip(
                    label: Text('${p.name} · ${Formatters.price(p.price)}',
                        style: Typo.body(12.5, FontWeight.w600)),
                    selected: _planId == p.id,
                    selectedColor: Palette.bronze.withValues(alpha: 0.2),
                    onSelected: (_) => setState(() => _planId = p.id),
                  ),
              ],
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  style: Typo.body(13, FontWeight.w600, Palette.crimson)),
            ),
          const SizedBox(height: 22),
          NeonButtonLike(saving: _saving, onTap: _save),
        ],
      ),
    );
  }
}

/// Small local CTA to avoid importing NeonButton with a non-const color.
class NeonButtonLike extends StatelessWidget {
  const NeonButtonLike({super.key, required this.saving, required this.onTap});

  final bool saving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: saving ? null : onTap,
      dim: true,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: Palette.bronze,
          borderRadius: BorderRadius.circular(27),
          boxShadow: neonGlow(Palette.bronze),
        ),
        child: Center(
          child: saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Palette.void0),
                )
              : Text('Crea atleta',
                  style: Typo.body(16, FontWeight.w700, Palette.void0)),
        ),
      ),
    );
  }
}
