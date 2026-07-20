import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/push/push_bridge.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/charts.dart';
import '../../../design/components/dashboard_edit_sheet.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';
import '../chat/chat_detail_view.dart';
import '../chat/chat_list_view.dart';
import '../more/agenda_view.dart';
import '../more/journey_view.dart';
import '../more/subscription_view.dart';
import '../nutrition/supplements_view.dart';
import '../progress/progress_tracker_view.dart';
import '../shell.dart';
import 'dashboard_vm.dart';

/// Athlete home — port of iOS `DashboardView`: greeting hero + fixed KPI
/// grid + the server-driven customizable widget stack (canonical array
/// order, synced with the web grid).
class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key});

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _remote;
  bool _mealFlipped = false;
  bool _mealSquashed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => ref.read(dashboardVmProvider.notifier).load());
    _remote = ref.read(pushBridgeProvider).onTypes({
      RemoteChangeType.workoutAssigned,
      RemoteChangeType.nutritionAssigned,
      RemoteChangeType.checkReviewed,
      RemoteChangeType.coachFeedback,
      RemoteChangeType.message,
    }).listen((_) => ref.read(dashboardVmProvider.notifier).load(force: true));
  }

  @override
  void dispose() {
    _remote?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pick up layout edits made on the web while backgrounded.
    if (state == AppLifecycleState.resumed) {
      ref.read(dashboardVmProvider.notifier).refreshLayout();
    }
  }

  void _switchTab(AthleteTab tab) =>
      ref.read(athleteTabProvider.notifier).state = tab;

  void _openSheet(WidgetBuilder builder) =>
      showAppSheet<void>(context, builder: builder);

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(dashboardVmProvider);
    final session = ref.watch(sessionControllerProvider);

    return ScreenScroll(
      onRefresh: () =>
          ref.read(dashboardVmProvider.notifier).load(force: true),
      children: [
        // Greeting hero (fixed — never part of the customizable grid).
        RevealUp(
          index: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_greeting()}, ATLETA',
                      style: Typo.mono(11, FontWeight.w600, Palette.bronze)
                          .copyWith(letterSpacing: 3),
                    ),
                  ),
                  Pressable(
                    onTap: () => _openEdit(),
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
                    url: session.avatarUrl,
                    name: session.greetingName,
                    size: 40,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(session.greetingName.toUpperCase(),
                    style: Typo.poster(52)),
              ),
              const SizedBox(height: 8),
              Container(
                  height: 1, color: Palette.bronze.withValues(alpha: 0.5)),
            ],
          ),
        ),

        // Fixed KPI grid (2×2).
        RevealUp(index: 1, child: _statsGrid(vm)),

        if (vm.loading)
          const _DashboardSkeleton()
        else
          for (final (i, w) in vm.layoutWidgets.indexed)
            if (_widgetFor(w, vm) case final Widget widget)
              RevealUp(index: 2 + i, child: widget),
      ],
    );
  }

  void _openEdit() {
    final vm = ref.read(dashboardVmProvider);
    showAppSheet<void>(
      context,
      builder: (_) => DashboardEditSheet(
        widgets: vm.layoutWidgets,
        catalog: vm.catalog,
        onChanged: (w) =>
            ref.read(dashboardVmProvider.notifier).setWidgets(w),
        onReset: () => ref.read(dashboardVmProvider.notifier).resetLayout(),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'BUONGIORNO';
    if (h < 18) return 'BUON POMERIGGIO';
    return 'BUONASERA';
  }

  Widget _statsGrid(DashboardState vm) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      shrinkWrap: true,
      childAspectRatio: 1.35,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        StatTile(
          value: '${vm.sessionsThisWeek}',
          label: 'Sessioni Settimana',
          icon: Icons.fitness_center_rounded,
          accent: Palette.magenta,
          onTap: () => _switchTab(AthleteTab.train),
        ),
        StatTile(
          value: vm.kcalTargetDisplay,
          label: 'Target Giornaliero',
          icon: Icons.local_fire_department_rounded,
          accent: Palette.lime,
          onTap: () => _switchTab(AthleteTab.fuel),
        ),
        StatTile(
          value: vm.daysToRenewalDisplay,
          label: 'Abbonamento',
          icon: Icons.workspace_premium_rounded,
          accent: Palette.amber,
          onTap: () => _openSheet((_) => const SubscriptionView()),
        ),
        StatTile(
          value: vm.weightCurrentDisplay,
          label: 'Peso attuale',
          icon: Icons.monitor_weight_rounded,
          accent: Palette.cyan,
          onTap: () => _openSheet((_) => const ProgressTrackerView()),
        ),
      ],
    );
  }

  // ── Widget dispatch (customizable grid) ──

  Widget? _widgetFor(DashboardWidgetDto w, DashboardState vm) {
    switch (w.type) {
      case 'quick_actions':
        return _quickActions();
      case 'next_workout':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('Oggi'),
            const SizedBox(height: 10),
            _todayCard(vm),
          ],
        );
      case 'next_meal':
        final plan = vm.nextMealPlan;
        if (plan == null) return null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('Prossimo pasto'),
            const SizedBox(height: 10),
            _mealCard(vm, plan),
          ],
        );
      case 'coach_message':
        final conv = vm.lastConversation;
        final msg = conv?.lastMessage;
        if (conv == null || msg == null || msg.isEmpty) return null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('Dal tuo coach'),
            const SizedBox(height: 10),
            _coachCard(conv, msg),
          ],
        );
      case 'weight_trend':
        return _weightTrendWidget(vm);
      case 'training_loads':
        return _linkWidget(
          title: 'Carichi principali',
          subtitle: 'La progressione dei tuoi esercizi chiave',
          icon: Icons.fitness_center_rounded,
          accent: Palette.magenta,
          onTap: () => _openSheet((_) => const ProgressTrackerView()),
        );
      case 'weekly_volume':
        return _linkWidget(
          title: 'Volume settimanale',
          subtitle: 'Quanto ti sei allenato, settimana per settimana',
          icon: Icons.bar_chart_rounded,
          accent: Palette.cyan,
          onTap: () => _openSheet((_) => const ProgressTrackerView()),
        );
      case 'journey_timeline':
        return _linkWidget(
          title: 'Percorso',
          subtitle: 'Le tappe del tuo percorso con il coach',
          icon: Icons.map_rounded,
          accent: Palette.bronze,
          onTap: () => _openSheet((_) => const JourneyView()),
        );
      case 'checks_due':
        return _checksDueWidget(vm);
      case 'nav_shortcuts':
        return Row(
          children: [
            Expanded(
              child: QuickActionTile(
                icon: Icons.fitness_center_rounded,
                label: 'Allenamento',
                accent: Palette.magenta,
                onTap: () => _switchTab(AthleteTab.train),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: QuickActionTile(
                icon: Icons.restaurant_rounded,
                label: 'Nutrizione',
                accent: Palette.lime,
                onTap: () => _switchTab(AthleteTab.fuel),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: QuickActionTile(
                icon: Icons.photo_camera_rounded,
                label: 'Check',
                accent: Palette.cyan,
                onTap: () => _switchTab(AthleteTab.check),
              ),
            ),
          ],
        );
      default:
        return null;
    }
  }

  Widget _quickActions() {
    return Row(
      children: [
        Expanded(
          child: QuickActionTile(
            icon: Icons.medication_rounded,
            label: 'Integratori',
            accent: Palette.lime,
            onTap: () => _openSheet((_) => const SupplementsView()),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: QuickActionTile(
            icon: Icons.forum_rounded,
            label: 'Chat',
            accent: Palette.violet,
            onTap: () => _openSheet((_) => const ChatListView()),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: QuickActionTile(
            icon: Icons.calendar_month_rounded,
            label: 'Agenda',
            accent: Palette.cyan,
            onTap: () => _openSheet((_) => const AgendaView()),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: QuickActionTile(
            icon: Icons.map_rounded,
            label: 'Percorso',
            accent: Palette.bronze,
            onTap: () => _openSheet((_) => const JourneyView()),
          ),
        ),
      ],
    );
  }

  Widget _todayCard(DashboardState vm) {
    final day = vm.todayDay;
    return Pressable(
      onTap: () => _switchTab(AthleteTab.train),
      child: Container(
        decoration: voltPanel(tint: Palette.magenta.withValues(alpha: 0.4)),
        padding: const EdgeInsets.all(18),
        child: day == null
            ? Text(
                'Nessuna scheda attiva. Il tuo coach la sta preparando.',
                style: Typo.body(14, FontWeight.w400, Palette.textMid),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (day.dayName ?? 'Sessione').toUpperCase(),
                              style: Typo.mono(
                                      10, FontWeight.w700, Palette.magenta)
                                  .copyWith(letterSpacing: 2),
                            ),
                            const SizedBox(height: 4),
                            Text(day.focusArea ?? day.label,
                                style: Typo.display(24)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Palette.magenta,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('INIZIA',
                            style:
                                Typo.mono(10, FontWeight.w700, Palette.void0)
                                    .copyWith(letterSpacing: 1.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _pill(Icons.format_list_numbered_rounded,
                          '${day.exercises.length} esercizi'),
                      const SizedBox(width: 8),
                      _pill(
                          Icons.repeat_rounded,
                          '${day.exercises.fold<int>(0, (s, e) => s + (e.setCount ?? 0))} serie'),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  /// Meal card with the squash-flip micro-interaction (0.16 s squash to
  /// scaleX 0 → swap face → 0.22 s unsquash).
  Widget _mealCard(DashboardState vm, NutritionPlanDto plan) {
    final meal = vm.nextMeal;
    final targets = plan.overviewTargets;
    return Pressable(
      onTap: () => _switchTab(AthleteTab.fuel),
      child: Container(
        decoration: voltPanel(tint: Palette.lime.withValues(alpha: 0.4)),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: _mealSquashed ? 0.0 : 1.0),
                    duration: Duration(milliseconds: _mealSquashed ? 160 : 220),
                    curve: Curves.easeInOut,
                    builder: (context, v, child) =>
                        Transform.scale(scaleX: v, child: child),
                    child: _mealFlipped
                        ? _planFace(plan, targets)
                        : _mealFace(meal),
                  ),
                ),
                Pressable(
                  onTap: () async {
                    setState(() => _mealSquashed = true);
                    await Future<void>.delayed(
                        const Duration(milliseconds: 160));
                    if (!mounted) return;
                    setState(() {
                      _mealFlipped = !_mealFlipped;
                      _mealSquashed = false;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Palette.lime.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _mealFlipped ? 'Pasto' : 'Piano',
                      style: Typo.mono(10, FontWeight.w700, Palette.lime),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mealFace(MealDto? meal) {
    if (meal == null) {
      return Text('Nessun pasto pianificato per oggi.',
          style: Typo.body(13, FontWeight.w400, Palette.textMid));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(meal.name, style: Typo.display(20)),
        const SizedBox(height: 4),
        Text(
          '${meal.items.length} alimenti · ${meal.kcal.toInt()} kcal',
          style: Typo.mono(11, FontWeight.w600, Palette.textMid),
        ),
      ],
    );
  }

  Widget _planFace(NutritionPlanDto plan, OverviewTargets t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(plan.title, maxLines: 1,
            overflow: TextOverflow.ellipsis, style: Typo.display(18)),
        const SizedBox(height: 4),
        Text(
          '${t.kcal} kcal · P ${t.protein ?? "—"} · C ${t.carb ?? "—"} · F ${t.fat ?? "—"}',
          style: Typo.mono(11, FontWeight.w600, Palette.textMid),
        ),
      ],
    );
  }

  Widget _coachCard(ConversationDto conv, String message) {
    return Pressable(
      onTap: () => showAppSheet<void>(context,
          builder: (_) => ChatDetailView(conversation: conv)),
      child: Container(
        decoration: voltPanel(tint: Palette.violet.withValues(alpha: 0.35)),
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            AvatarView(
              url: conv.coach?.profileImageUrl,
              name: conv.coach?.fullName ?? 'Coach',
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(conv.coach?.fullName ?? 'Il tuo coach',
                      style: Typo.body(14, FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Typo.body(13, FontWeight.w400, Palette.textMid)),
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

  Widget _weightTrendWidget(DashboardState vm) {
    return Pressable(
      onTap: () => _openSheet((_) => const ProgressTrackerView()),
      child: Container(
        decoration: voltPanel(tint: Palette.cyan.withValues(alpha: 0.35)),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'ANDAMENTO PESO',
                    style: Typo.mono(9, FontWeight.w600, Palette.textMid)
                        .copyWith(letterSpacing: 2),
                  ),
                ),
                Text('${vm.weightCurrentDisplay} kg',
                    style: Typo.mono(13, FontWeight.w700, Palette.cyan)),
              ],
            ),
            const SizedBox(height: 12),
            if (vm.weights.length >= 2)
              SparklineView(values: vm.weights, height: 56)
            else
              Text(
                'Nessuna rilevazione ancora: compila un check per iniziare.',
                style: Typo.body(13, FontWeight.w400, Palette.textMid),
              ),
          ],
        ),
      ),
    );
  }

  Widget _checksDueWidget(DashboardState vm) {
    return Pressable(
      onTap: () => _switchTab(AthleteTab.check),
      child: Container(
        decoration: voltPanel(tint: Palette.amber.withValues(alpha: 0.35)),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'CHECK DA COMPILARE',
                    style: Typo.mono(9, FontWeight.w600, Palette.textMid)
                        .copyWith(letterSpacing: 2),
                  ),
                ),
                const Icon(Icons.checklist_rounded,
                    size: 16, color: Palette.amber),
              ],
            ),
            const SizedBox(height: 10),
            if (vm.checksDue.isEmpty)
              Text('Tutto in ordine: nessun check in attesa.',
                  style: Typo.body(13, FontWeight.w400, Palette.textMid))
            else
              for (final check in vm.checksDue.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(check.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Typo.body(14, FontWeight.w500)),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          size: 15, color: Palette.textLow),
                    ],
                  ),
                ),
          ],
        ),
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
                      style: Typo.body(12, FontWeight.w400, Palette.textMid)),
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

  Widget _pill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Palette.void2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Palette.textMid),
          const SizedBox(width: 5),
          Text(label, style: Typo.mono(10, FontWeight.w600, Palette.textMid)),
        ],
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: Column(
        children: [
          SkelCard(height: 120),
          SizedBox(height: Space.element),
          SkelCard(height: 90),
          SizedBox(height: Space.element),
          SkelCard(height: 90),
        ],
      ),
    );
  }
}
