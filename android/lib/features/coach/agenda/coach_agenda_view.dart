import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';

/// Coach agenda — port of iOS `CoachAgendaView`: appointments grouped by day
/// + booking form.
class CoachAgendaView extends ConsumerStatefulWidget {
  const CoachAgendaView({super.key});

  @override
  ConsumerState<CoachAgendaView> createState() => _CoachAgendaViewState();
}

class _CoachAgendaViewState extends ConsumerState<CoachAgendaView> {
  CoachAgendaResponse? _res;
  bool _error = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(apiClientProvider).coachAgenda();
      if (mounted) setState(() => _res = res);
    } catch (_) {
      if (mounted && _res == null) setState(() => _error = true);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _res == null) return;
    setState(() => _loadingMore = true);
    try {
      final more = await ref
          .read(apiClientProvider)
          .coachAgenda(offset: _res!.appointments.length);
      if (mounted) {
        setState(() => _res = _res!.copyWith(
              appointments: [..._res!.appointments, ...more.appointments],
              hasMore: more.hasMore,
            ));
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = _res;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Nuovo appuntamento',
            icon: const Icon(Icons.add_rounded, color: Palette.textHi),
            onPressed: () => showAppSheet<void>(context,
                    builder: (_) => const CoachNewAppointmentSheet())
                .then((_) => _load()),
          ),
        ],
      ),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(eyebrow: 'I tuoi impegni', title: 'Agenda'),
          if (res == null && !_error)
            const DateCardsSkeleton()
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (res!.appointments.isEmpty)
            const EmptyPanel(
              icon: Icons.calendar_month_outlined,
              message: 'Agenda vuota: prenota il primo appuntamento con +.',
            )
          else ...[
            for (final (i, a) in res.appointments.indexed) ...[
              if (i == 0 || !_sameDay(res.appointments[i - 1], a))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Eyebrow(_dayLabel(a)),
                ),
              _card(a),
            ],
            if (res.hasMore)
              LoadMoreButton(onTap: _loadMore, loading: _loadingMore),
          ],
        ],
      ),
    );
  }

  bool _sameDay(CoachAgendaItem a, CoachAgendaItem b) {
    final da = Formatters.parseDate(a.start);
    final db = Formatters.parseDate(b.start);
    if (da == null || db == null) return true;
    return da.year == db.year && da.month == db.month && da.day == db.day;
  }

  String _dayLabel(CoachAgendaItem a) {
    final d = Formatters.parseDate(a.start);
    return d == null ? 'Appuntamenti' : Formatters.weekdayLongDate(d.toLocal());
  }

  Widget _card(CoachAgendaItem a) {
    final start = Formatters.parseDate(a.start)?.toLocal();
    return VoltPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Text(start == null ? '—' : Formatters.time(start),
              style: Typo.mono(14, FontWeight.w700, Palette.cyan)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.title, style: Typo.body(14.5, FontWeight.w700)),
                Text(
                  [
                    if (a.client != null) a.client!.displayName,
                    if (a.durationMinutes != null)
                      '${a.durationMinutes} min',
                    if ((a.location ?? '').isNotEmpty) a.location!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Typo.body(12, FontWeight.w400, Palette.textMid),
                ),
              ],
            ),
          ),
          if (a.client != null)
            AvatarView(
                url: a.client!.profileImageUrl,
                name: a.client!.displayName,
                size: 34),
        ],
      ),
    );
  }
}

/// Booking form — port of iOS `CoachNewAppointmentView`.
class CoachNewAppointmentSheet extends ConsumerStatefulWidget {
  const CoachNewAppointmentSheet({super.key});

  @override
  ConsumerState<CoachNewAppointmentSheet> createState() =>
      _CoachNewAppointmentSheetState();
}

class _CoachNewAppointmentSheetState
    extends ConsumerState<CoachNewAppointmentSheet> {
  final _title = TextEditingController();
  final _link = TextEditingController();
  final _notes = TextEditingController();
  List<CoachClientRow> _clients = [];
  int? _clientId;
  String _type = 'consulenza';
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 17, minute: 0);
  int _duration = 30;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(apiClientProvider)
        .coachClients(status: 'ACTIVE', limit: 100)
        .then((r) => mounted ? setState(() => _clients = r.clients) : null)
        .catchError((_) => null);
  }

  Future<void> _save() async {
    if (_clientId == null || _title.text.trim().isEmpty || _saving) {
      StatusFlash.show(context,
          success: false, message: 'Atleta e titolo obbligatori');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).coachCreateAppointment({
        'client_id': _clientId,
        'title': _title.text.trim(),
        'type': _type,
        'date':
            '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
        'time':
            '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
        'duration_minutes': _duration,
        if (_link.text.trim().isNotEmpty) 'meeting_url': _link.text.trim(),
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      StatusFlash.show(context, success: true, message: 'Appuntamento creato');
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        StatusFlash.show(context,
            success: false, message: 'Creazione non riuscita');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(
          title: Text('Nuovo appuntamento', style: Typo.display(18))),
      body: ListView(
        padding: const EdgeInsets.all(Space.screenH),
        children: [
          DropdownButtonFormField<int>(
            initialValue: _clientId,
            decoration: const InputDecoration(labelText: 'Atleta *'),
            items: [
              for (final c in _clients)
                DropdownMenuItem(
                    value: c.id,
                    child: Text(c.displayName,
                        style: Typo.body(14.5, FontWeight.w600))),
            ],
            onChanged: (v) => setState(() => _clientId = v),
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _title,
              style: Typo.body(15, FontWeight.w600),
              decoration: const InputDecoration(labelText: 'Titolo *')),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final (v, l) in const [
                ('visita', 'Visita'),
                ('prima_visita', 'Prima visita'),
                ('check', 'Check'),
                ('consulenza', 'Consulenza'),
              ])
                ChoiceChip(
                  label: Text(l, style: Typo.body(12.5, FontWeight.w600)),
                  selected: _type == v,
                  selectedColor: Palette.cyan.withValues(alpha: 0.2),
                  onSelected: (_) => setState(() => _type = v),
                ),
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Data', style: Typo.body(14, FontWeight.w600)),
            trailing: Text(Formatters.mediumDate(_date),
                style: Typo.mono(13, FontWeight.w600, Palette.cyan)),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Ora', style: Typo.body(14, FontWeight.w600)),
            trailing: Text(
                '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                style: Typo.mono(13, FontWeight.w600, Palette.cyan)),
            onTap: () async {
              final picked =
                  await showTimePicker(context: context, initialTime: _time);
              if (picked != null) setState(() => _time = picked);
            },
          ),
          Row(
            children: [
              Expanded(
                  child: Text('Durata: $_duration min',
                      style: Typo.body(14, FontWeight.w600))),
              Expanded(
                child: Slider(
                  value: _duration.toDouble(),
                  min: 15,
                  max: 120,
                  divisions: 7,
                  activeColor: Palette.cyan,
                  onChanged: (v) => setState(() => _duration = v.round()),
                ),
              ),
            ],
          ),
          TextField(
              controller: _link,
              style: Typo.body(14, FontWeight.w500),
              decoration: const InputDecoration(
                  labelText: 'Link call (se online)')),
          const SizedBox(height: 12),
          TextField(
              controller: _notes,
              maxLines: 2,
              style: Typo.body(14, FontWeight.w400),
              decoration: const InputDecoration(labelText: 'Note')),
          const SizedBox(height: 22),
          NeonButton('Prenota',
              color: Palette.cyan, loading: _saving, onTap: _save),
        ],
      ),
    );
  }
}
