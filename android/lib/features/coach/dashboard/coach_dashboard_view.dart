import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/api/coach_api.dart';
import '../../../core/cache/memory_cache.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/dashboard_edit_sheet.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';
import '../agenda/coach_agenda_view.dart';
import '../analytics/coach_analytics_view.dart';
import '../clients/coach_clients_view.dart';
import '../messages/coach_messages_view.dart';
import '../subscriptions/coach_subscriptions_view.dart';

/// Coach home — port of iOS `CoachDashboardView`: fixed business KPI row +
/// server-driven widget stack (array order canonical, synced with web),
/// debounced 600 ms autosave, pinned-athletes widget.
class CoachDashboardView extends ConsumerStatefulWidget {
  const CoachDashboardView({super.key});

  @override
  ConsumerState<CoachDashboardView> createState() =>
      _CoachDashboardViewState();
}

class _CoachDashboardViewState extends ConsumerState<CoachDashboardView> {
  CoachDashboardDto? _dash;
  List<DashboardWidgetDto> _widgets = [];
  List<WidgetCatalogItemDto> _catalog = [];
  List<PinnedAthleteDto> _pinned = [];
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final api = ref.read(apiClientProvider);
    final cache = ref.read(memoryCacheProvider);
    if (!force) {
      final d = cache.get<CoachDashboardDto>(CacheKeys.coachDashboard);
      final l = cache.get<DashboardLayoutDto>(CacheKeys.coachDashboardLayout);
      final c = cache
          .get<List<WidgetCatalogItemDto>>(CacheKeys.coachDashboardCatalog);
      if (d != null && l != null && c != null) {
        setState(() {
          _dash = d;
          _widgets = l.widgets;
          _catalog = c;
        });
        _loadPinned();
        return;
      }
    }
    try {
      final results = await Future.wait<Object?>([
        api.coachDashboard(),
        api.dashboardLayout().then<Object?>((v) => v).catchError((_) => null),
      ]);
      if (!mounted) return;
      final d = results[0] as CoachDashboardDto;
      final l = results[1] as DashboardLayoutResponse?;
      cache.set(CacheKeys.coachDashboard, d);
      if (l != null) {
        cache.set(CacheKeys.coachDashboardLayout, l.layout);
        cache.set(CacheKeys.coachDashboardCatalog, l.catalog);
      }
      setState(() {
        _dash = d;
        _widgets = l?.layout.widgets ?? _widgets;
        _catalog = l?.catalog ?? _catalog;
        _error = false;
      });
      _loadPinned();
    } catch (_) {
      if (mounted && _dash == null) setState(() => _error = true);
    }
  }

  Future<void> _loadPinned() async {
    final ids = <int>[];
    for (final w in _widgets) {
      if (w.type == 'pinned_athletes') {
        ids.addAll(w.config?.clientIds ?? const []);
      }
    }
    if (ids.isEmpty) return;
    try {
      final rows = await ref.read(apiClientProvider).pinnedAthletes(ids);
      if (mounted) setState(() => _pinned = rows);
    } catch (_) {}
  }

  void _saveWidgets(List<DashboardWidgetDto> widgets) {
    setState(() {
      _widgets = [for (final (i, w) in widgets.indexed) w.copyWith(y: i)];
    });
    // Debounce handled server-tolerantly: single save on edit-sheet change.
    ref
        .read(apiClientProvider)
        .updateDashboardLayout(DashboardLayoutDto(version: 1, widgets: _widgets))
        .then((resp) {
      ref
          .read(memoryCacheProvider)
          .set(CacheKeys.coachDashboardLayout, resp.layout);
      _loadPinned();
    }).catchError((_) {});
  }

  void _openEdit() {
    showAppSheet<void>(
      context,
      builder: (_) => DashboardEditSheet(
        widgets: _widgets,
        catalog: _catalog,
        onChanged: _saveWidgets,
        onReset: () async {
          final resp =
              await ref.read(apiClientProvider).resetDashboardLayout();
          if (mounted) setState(() => _widgets = resp.layout.widgets);
        },
        onConfigure: (w) => _openPinnedPicker(w),
      ),
    );
  }

  Future<void> _openPinnedPicker(DashboardWidgetDto widget) async {
    final api = ref.read(apiClientProvider);
    final clients = await api.coachClients(status: 'ACTIVE', limit: 100);
    if (!mounted) return;
    final selected = Set<int>.of(widget.config?.clientIds ?? const []);
    await showAppSheet<void>(
      context,
      heightFactor: 0.8,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Scaffold(
          backgroundColor: Palette.void0,
          appBar: AppBar(
              title:
                  Text('Atleti in evidenza', style: Typo.display(18))),
          body: ListView(
            padding: const EdgeInsets.all(Space.screenH),
            children: [
              Text('Scegli fino a 6 atleti.',
                  style: Typo.body(13, FontWeight.w400, Palette.textMid)),
              const SizedBox(height: 12),
              for (final c in clients.clients)
                CheckboxListTile(
                  value: selected.contains(c.id),
                  title: Text(c.displayName,
                      style: Typo.body(14.5, FontWeight.w600)),
                  activeColor: Palette.bronze,
                  onChanged: (v) => setSheetState(() {
                    if (v == true) {
                      if (selected.length < 6) selected.add(c.id);
                    } else {
                      selected.remove(c.id);
                    }
                  }),
                ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () {
                  final updated = [
                    for (final w in _widgets)
                      if (w.id == widget.id)
                        w.copyWith(
                            config: DashboardWidgetConfigDto(
                                clientIds: selected.toList()))
                      else
                        w,
                  ];
                  _saveWidgets(updated);
                  Navigator.of(context, rootNavigator: true).pop();
                },
                child: const Text('Conferma'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSheet(WidgetBuilder builder) =>
      showAppSheet<void>(context, builder: builder);

  @override
  Widget build(BuildContext context) {
    final dash = _dash;
    return ScreenScroll(
      onRefresh: () => _load(force: true),
      children: [
        RevealUp(
          index: 0,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow('La tua palestra digitale',
                        color: Palette.bronze),
                    const SizedBox(height: 6),
                    FittedBox(
                      child: Text(
                        (dash?.coach.firstName ?? 'Coach').toUpperCase(),
                        style: Typo.poster(46),
                      ),
                    ),
                  ],
                ),
              ),
              Pressable(
                onTap: _openEdit,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                      color: Palette.void1, shape: BoxShape.circle),
                  child: const Icon(Icons.tune_rounded,
                      size: 16, color: Palette.textMid),
                ),
              ),
              const SizedBox(width: 10),
              AvatarView(
                url: dash?.coach.profileImageUrl,
                name: dash?.coach.fullName ?? 'Coach',
                size: 40,
              ),
            ],
          ),
        ),
        if (dash == null && !_error)
          const ListCardsSkeleton(count: 3, height: 110)
        else if (_error)
          EmptyPanel.network(onCta: () {
            setState(() => _error = false);
            _load(force: true);
          })
        else ...[
          RevealUp(index: 1, child: _statsGrid(dash!)),
          for (final (i, w) in _widgets.indexed)
            if (_widgetFor(w, dash) case final Widget child)
              RevealUp(index: 2 + i, child: child),
        ],
      ],
    );
  }

  Widget _statsGrid(CoachDashboardDto dash) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      shrinkWrap: true,
      childAspectRatio: 1.35,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        StatTile(
          value: '${dash.stats.activeClients}',
          label: 'Atleti attivi',
          icon: Icons.groups_rounded,
          accent: Palette.bronze,
          onTap: () => _openSheet((_) => const CoachClientsView()),
        ),
        StatTile(
          value: '${dash.stats.pendingChecks}',
          label: 'Check in attesa',
          icon: Icons.verified_rounded,
          accent: Palette.violet,
          onTap: () => _openSheet((_) => const CoachAnalyticsView()),
        ),
        StatTile(
          value: '${dash.stats.appointmentsToday}',
          label: 'Appuntamenti oggi',
          icon: Icons.calendar_month_rounded,
          accent: Palette.cyan,
          onTap: () => _openSheet((_) => const CoachAgendaView()),
        ),
        StatTile(
          value: '${dash.stats.unreadMessages}',
          label: 'Messaggi non letti',
          icon: Icons.forum_rounded,
          accent: Palette.lime,
          onTap: () => _openSheet((_) => const CoachMessagesView()),
        ),
      ],
    );
  }

  Widget? _widgetFor(DashboardWidgetDto w, CoachDashboardDto dash) {
    switch (w.type) {
      case 'quick_actions':
        return Row(
          children: [
            Expanded(
              child: QuickActionTile(
                icon: Icons.groups_rounded,
                label: 'Atleti',
                accent: Palette.bronze,
                onTap: () => _openSheet((_) => const CoachClientsView()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: QuickActionTile(
                icon: Icons.forum_rounded,
                label: 'Chat',
                accent: Palette.violet,
                onTap: () => _openSheet((_) => const CoachMessagesView()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: QuickActionTile(
                icon: Icons.calendar_month_rounded,
                label: 'Agenda',
                accent: Palette.cyan,
                onTap: () => _openSheet((_) => const CoachAgendaView()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: QuickActionTile(
                icon: Icons.workspace_premium_rounded,
                label: 'Incassi',
                accent: Palette.amber,
                onTap: () =>
                    _openSheet((_) => const CoachSubscriptionsView()),
              ),
            ),
          ],
        );
      case 'agenda_today':
        return _agendaWidget(dash);
      case 'activity_feed':
        return _activityWidget(dash);
      case 'pinned_athletes':
        return _pinnedWidget();
      case 'business_kpis':
      case 'churn_risk':
      case 'revenue_chart':
      case 'checks_volume_chart':
        return _linkWidget(
          title: switch (w.type) {
            'business_kpis' => 'KPI business',
            'churn_risk' => 'Rischio abbandono',
            'revenue_chart' => 'Ricavi',
            _ => 'Volume check',
          },
          subtitle: 'Apri le analisi complete',
          icon: Icons.query_stats_rounded,
          accent: Palette.bronze,
          onTap: () => _openSheet((_) => const CoachAnalyticsView()),
        );
      case 'unread_messages':
        return _linkWidget(
          title: 'Messaggi',
          subtitle: '${dash.stats.unreadMessages} non letti',
          icon: Icons.forum_rounded,
          accent: Palette.lime,
          onTap: () => _openSheet((_) => const CoachMessagesView()),
        );
      case 'pending_checks':
        return _linkWidget(
          title: 'Check da revisionare',
          subtitle: '${dash.stats.pendingChecks} in attesa',
          icon: Icons.verified_rounded,
          accent: Palette.violet,
          onTap: () => _openSheet((_) => const CoachClientsView()),
        );
      case 'insight':
        return _insightWidget(dash);
      default:
        return null;
    }
  }

  Widget _agendaWidget(CoachDashboardDto dash) {
    return Container(
      decoration: voltPanel(tint: Palette.cyan.withValues(alpha: 0.35)),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Agenda di oggi'),
          const SizedBox(height: 10),
          if (dash.agenda.isEmpty)
            Text('Nessun appuntamento oggi.',
                style: Typo.body(13, FontWeight.w400, Palette.textMid))
          else
            for (final a in dash.agenda.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text(
                      Formatters.parseDate(a.start) == null
                          ? '—'
                          : Formatters.time(
                              Formatters.parseDate(a.start)!.toLocal()),
                      style:
                          Typo.mono(12, FontWeight.w700, Palette.cyan),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${a.title}${a.client == null ? '' : ' · ${a.client!.displayName}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Typo.body(13.5, FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _activityWidget(CoachDashboardDto dash) {
    return Container(
      decoration: voltPanel(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Attività recente'),
          const SizedBox(height: 10),
          if (dash.activity.isEmpty)
            Text('Ancora nessuna attività.',
                style: Typo.body(13, FontWeight.w400, Palette.textMid))
          else
            for (final a in dash.activity.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Icon(Icons.circle,
                          size: 7, color: Palette.bronze),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(a.title,
                          style: Typo.body(13.5, FontWeight.w500)),
                    ),
                    if (Formatters.parseDate(a.createdAt) != null)
                      Text(
                        Formatters.relative(
                            Formatters.parseDate(a.createdAt)!.toLocal()),
                        style: Typo.mono(
                            9, FontWeight.w600, Palette.textLow),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _pinnedWidget() {
    return Container(
      decoration: voltPanel(tint: Palette.bronze.withValues(alpha: 0.35)),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Atleti in evidenza'),
          const SizedBox(height: 10),
          if (_pinned.isEmpty)
            Text('Scegli gli atleti da tenere d\'occhio (matita in alto).',
                style: Typo.body(13, FontWeight.w400, Palette.textMid))
          else
            for (final p in _pinned)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    AvatarView(
                        url: p.profileImageUrl,
                        name: p.displayName,
                        size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(p.displayName,
                          style: Typo.body(14, FontWeight.w600)),
                    ),
                    if (p.hasPendingCheck)
                      const StatusBadge('Check', color: Palette.amber),
                    if (p.weightDelta != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${p.weightDelta! >= 0 ? '+' : ''}${Formatters.decimal(p.weightDelta!)} kg',
                        style: Typo.mono(
                            10, FontWeight.w700, Palette.textMid),
                      ),
                    ],
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _insightWidget(CoachDashboardDto dash) {
    if (dash.insight.text.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: voltPanel(tint: Palette.amber.withValues(alpha: 0.4)),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_rounded,
              size: 16, color: Palette.goldText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(dash.insight.text,
                style: Typo.body(13.5, FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _linkWidget({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Pressable(
      onTap: onTap,
      child: Container(
        decoration: voltPanel(tint: accent.withValues(alpha: 0.3)),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Typo.display(17)),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Typo.body(12, FontWeight.w400, Palette.textMid)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: Palette.textLow),
          ],
        ),
      ),
    );
  }
}
