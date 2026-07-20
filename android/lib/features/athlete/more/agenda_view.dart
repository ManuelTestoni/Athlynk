import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';

/// Agenda — port of iOS `AgendaView`: appointments split PROSSIMI/PASSATI,
/// 10 per page.
class AgendaView extends ConsumerStatefulWidget {
  const AgendaView({super.key});

  @override
  ConsumerState<AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends ConsumerState<AgendaView> {
  List<AppointmentDto>? _items;
  bool _error = false;
  bool _hasMore = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(apiClientProvider).appointments();
      if (mounted) {
        setState(() {
          _items = res.appointments;
          _hasMore = res.hasMore;
        });
      }
    } catch (_) {
      if (mounted && _items == null) setState(() => _error = true);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final res = await ref
          .read(apiClientProvider)
          .appointments(offset: _items?.length ?? 0);
      if (mounted) {
        setState(() {
          _items = [...?_items, ...res.appointments];
          _hasMore = res.hasMore;
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final now = DateTime.now();
    final upcoming = <AppointmentDto>[];
    final past = <AppointmentDto>[];
    for (final a in items ?? const <AppointmentDto>[]) {
      final start = Formatters.parseDate(a.start);
      if (start != null && start.isBefore(now)) {
        past.add(a);
      } else {
        upcoming.add(a);
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(
              eyebrow: 'Appuntamenti', title: 'Agenda'),
          if (items == null && !_error)
            const DateCardsSkeleton()
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (items!.isEmpty)
            const EmptyPanel(
              icon: Icons.calendar_month_outlined,
              message: 'Nessun appuntamento in agenda.',
            )
          else ...[
            if (upcoming.isNotEmpty) ...[
              const Eyebrow('Prossimi'),
              for (final a in upcoming) _card(a),
            ],
            if (past.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Eyebrow('Passati'),
              for (final a in past) _card(a, past: true),
            ],
            if (_hasMore)
              LoadMoreButton(onTap: _loadMore, loading: _loadingMore),
          ],
        ],
      ),
    );
  }

  Widget _card(AppointmentDto a, {bool past = false}) {
    final start = Formatters.parseDate(a.start)?.toLocal();
    final end = Formatters.parseDate(a.end)?.toLocal();
    final statusColor = switch (a.status?.toUpperCase()) {
      'CONFIRMED' => Palette.lime,
      'PENDING' => Palette.amber,
      'CANCELLED' || 'REJECTED' => Palette.crimson,
      _ => Palette.textLow,
    };
    return Opacity(
      opacity: past ? 0.62 : 1,
      child: VoltPanel(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => AppointmentDetailView(appointment: a))),
        child: Row(
          children: [
            Container(
              width: 54,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Palette.cyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(start == null ? '—' : '${start.day}',
                      style: Typo.poster(22)),
                  if (start != null)
                    Text(
                      Formatters.monthYear(start).split(' ').first.toUpperCase(),
                      style: Typo.mono(8, FontWeight.w700, Palette.textMid),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title, style: Typo.body(15, FontWeight.w700)),
                  const SizedBox(height: 3),
                  if (start != null)
                    Text(
                      '${Formatters.time(start)}${end != null ? ' – ${Formatters.time(end)}' : ''}',
                      style:
                          Typo.mono(11, FontWeight.w600, Palette.textMid),
                    ),
                ],
              ),
            ),
            if (a.status != null)
              StatusBadge(a.status!, color: statusColor),
          ],
        ),
      ),
    );
  }
}

/// One appointment — port of iOS `AppointmentDetailView`.
class AppointmentDetailView extends StatelessWidget {
  const AppointmentDetailView({super.key, required this.appointment});

  final AppointmentDto appointment;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final start = Formatters.parseDate(a.start)?.toLocal();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        children: [
          ScreenHeader(
            eyebrow: a.type ?? 'Appuntamento',
            title: a.title,
            titleSize: 34,
            subtitle: start == null
                ? null
                : '${Formatters.weekdayLongDate(start)} · ${Formatters.time(start)}',
          ),
          VoltPanel(
            child: Column(
              children: [
                _row(Icons.timer_outlined, 'Durata',
                    a.durationMinutes == null ? '—' : '${a.durationMinutes} min'),
                const Divider(height: 20),
                _row(Icons.place_outlined, 'Luogo', a.location ?? 'Online'),
                if (a.coach != null) ...[
                  const Divider(height: 20),
                  _row(Icons.person_outline_rounded, 'Coach',
                      a.coach!.fullName),
                ],
              ],
            ),
          ),
          if (a.meetingUrl != null && a.meetingUrl!.isNotEmpty)
            VoltPanel(
              tint: Palette.cyan.withValues(alpha: 0.4),
              onTap: () => launchUrl(Uri.parse(a.meetingUrl!),
                  mode: LaunchMode.externalApplication),
              child: Row(
                children: [
                  Icon(Icons.videocam_rounded, color: Palette.cyan),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Partecipa alla call',
                        style: Typo.body(15, FontWeight.w700, Palette.cyan)),
                  ),
                  Icon(Icons.open_in_new_rounded,
                      size: 16, color: Palette.cyan),
                ],
              ),
            ),
          if ((a.description ?? '').isNotEmpty)
            VoltPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Note'),
                  const SizedBox(height: 8),
                  Text(a.description!,
                      style: Typo.body(14.5, FontWeight.w400)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 17, color: Palette.textMid),
        const SizedBox(width: 10),
        Expanded(
            child:
                Text(label, style: Typo.body(14, FontWeight.w500, Palette.textMid))),
        Text(value, style: Typo.body(14, FontWeight.w700)),
      ],
    );
  }
}
