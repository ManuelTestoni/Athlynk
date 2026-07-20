import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../design/components/floating_tab_bar.dart';
import '../../design/components/pressable.dart';
import '../../design/components/sheets.dart';
import '../../design/components/volt_background.dart';
import '../../design/theme.dart';
import 'agenda/coach_agenda_view.dart';
import 'checks/coach_check_detail_view.dart';
import 'checks/coach_checks_view.dart';
import 'chiron/chiron_router.dart';
import 'chiron/coach_chiron_view.dart';
import 'clients/coach_client_detail_view.dart';
import 'clients/coach_clients_view.dart';
import 'dashboard/coach_dashboard_view.dart';
import 'messages/coach_messages_view.dart';
import 'more/coach_more_view.dart';
import 'plans/coach_plans_view.dart';
import 'subscriptions/coach_subscriptions_view.dart';

/// Coach tab identity — port of iOS `CoachTab`.
enum CoachTab {
  home('Home', Icons.home_rounded),
  allenamento('Allenamento', Icons.fitness_center_rounded),
  nutrizione('Nutrizione', Icons.restaurant_rounded),
  check('Check', Icons.verified_rounded),
  altro('Altro', Icons.more_horiz_rounded);

  const CoachTab(this.title, this.icon);
  final String title;
  final IconData icon;

  Color get color => switch (this) {
        CoachTab.home => Palette.bronze,
        CoachTab.allenamento => Palette.cyan,
        CoachTab.nutrizione => Palette.lime,
        CoachTab.check => Palette.violet,
        CoachTab.altro => Palette.phase,
      };

  List<Color> get palette => switch (this) {
        CoachTab.home => [Palette.bronze, Palette.violet, Palette.cyan],
        CoachTab.allenamento => [Palette.cyan, Palette.violet, Palette.bronze],
        CoachTab.nutrizione => [Palette.lime, Palette.cyan, Palette.amber],
        CoachTab.check => [Palette.violet, Palette.cyan, Palette.bronze],
        CoachTab.altro => [Palette.phase, Palette.violet, Palette.cyan],
      };
}

final coachTabProvider = StateProvider<CoachTab>((ref) => CoachTab.home);

/// Coach 5-tab shell — port of iOS `CoachMainTabView`: same paged structure
/// as the athlete shell plus the floating Chiron AI FAB (bottom-trailing).
class CoachShell extends ConsumerStatefulWidget {
  const CoachShell({super.key});

  @override
  ConsumerState<CoachShell> createState() => _CoachShellState();
}

class _CoachShellState extends ConsumerState<CoachShell> {
  final _navKeys = {
    for (final tab in CoachTab.values) tab: GlobalKey<NavigatorState>(),
  };

  Widget _rootFor(CoachTab tab) => switch (tab) {
        CoachTab.home => const CoachDashboardView(),
        CoachTab.allenamento => const CoachPlansView(workout: true),
        CoachTab.nutrizione => const CoachPlansView(workout: false),
        CoachTab.check => const CoachChecksView(),
        CoachTab.altro => const CoachMoreView(),
      };

  /// Routes a Chiron action link into native navigation — port of iOS
  /// `applyDeepLink`: switch tab, then push the target screen on that tab's
  /// own stack.
  void _applyDeepLink(ChironDeepLink link) {
    final (tab, page) = switch (link) {
      ChironClientsLink() => (CoachTab.altro, const CoachClientsView()),
      ChironClientLink(:final clientId) => (
          CoachTab.altro,
          CoachClientDetailView(clientId: clientId)
        ),
      ChironCheckLink(:final checkId) => (
          CoachTab.check,
          CoachCheckDetailView(checkId: checkId)
        ),
      ChironCheckDashboardLink() => (CoachTab.check, null),
      ChironAgendaLink() => (CoachTab.altro, const CoachAgendaView()),
      ChironSubscriptionsLink() => (
          CoachTab.altro,
          const CoachSubscriptionsView()
        ),
      ChironMessagesLink() => (CoachTab.altro, const CoachMessagesView()),
    };

    ref.read(coachTabProvider.notifier).state = tab;
    final nav = _navKeys[tab]!.currentState;
    if (nav == null) return;
    nav.popUntil((r) => r.isFirst);
    if (page != null) {
      nav.push(MaterialPageRoute<void>(builder: (_) => page));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(coachTabProvider);
    final session = ref.watch(sessionControllerProvider);

    // Chiron chat emits a pending deep link; consume it once.
    ref.listen<ChironDeepLink?>(chironRouterProvider, (_, link) {
      if (link == null) return;
      ref.read(chironRouterProvider.notifier).state = null;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _applyDeepLink(link));
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = _navKeys[tab]!.currentState;
        if (nav != null && nav.canPop()) nav.pop();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 800),
              child: VoltBackground(
                key: ValueKey('coach-bg-${tab.name}'),
                palette: tab.palette,
              ),
            ),
            IndexedStack(
              index: tab.index,
              children: [
                for (final t in CoachTab.values)
                  // IndexedStack keeps every tab mounted with
                  // `maintainAnimation: true`, so without this the shimmers,
                  // reveals and mascots of the hidden tabs keep ticking —
                  // whole screens' worth of rebuild+layout every frame, for
                  // pixels nobody sees.
                  TickerMode(
                    enabled: t == tab,
                    child: Navigator(
                      key: _navKeys[t],
                      onGenerateRoute: (settings) => MaterialPageRoute(
                        settings: settings,
                        builder: (_) => _rootFor(t),
                      ),
                    ),
                  ),
              ],
            ),
            // Chiron AI FAB (hidden in chats / when the tab bar hides).
            if (!session.tabBarHidden && !session.chironHidden)
              Positioned(
                right: 18,
                bottom: MediaQuery.of(context).padding.bottom + 96,
                child: Pressable(
                  onTap: () => showAppSheet<void>(context,
                      builder: (_) => const CoachChironView()),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFC9971E), Color(0xFF8A6508)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Palette.amber.withValues(alpha: 0.4),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.auto_awesome_rounded,
                        size: 22, color: Palette.void0),
                  ),
                ),
              ),
            Positioned(
              left: 18,
              right: 18,
              bottom: MediaQuery.of(context).padding.bottom + 12,
              child: FloatingTabBar(
                hidden: session.tabBarHidden,
                tabs: [
                  for (final t in CoachTab.values)
                    FloatingTabSpec(
                        title: t.title, icon: t.icon, color: () => t.color),
                ],
                index: tab.index,
                onSelect: (i) => ref.read(coachTabProvider.notifier).state =
                    CoachTab.values[i],
                onReselect: (i) => _navKeys[CoachTab.values[i]]!
                    .currentState
                    ?.popUntil((r) => r.isFirst),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
