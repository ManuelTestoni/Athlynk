import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../design/components/floating_tab_bar.dart';
import '../../design/components/volt_background.dart';
import '../../design/theme.dart';
import 'checks/checks_view.dart';
import 'dashboard/dashboard_view.dart';
import 'more/more_view.dart';
import 'nutrition/nutrition_view.dart';
import 'workouts/workouts_view.dart';

/// Athlete tab identity — port of iOS `AppTab`.
enum AthleteTab {
  home('Home', Icons.home_rounded),
  train('Allenamento', Icons.fitness_center_rounded),
  fuel('Nutrizione', Icons.local_fire_department_rounded),
  check('Check', Icons.verified_rounded),
  altro('Altro', Icons.more_horiz_rounded);

  const AthleteTab(this.title, this.icon);
  final String title;
  final IconData icon;

  Color get color => switch (this) {
        AthleteTab.home => Palette.cyan,
        AthleteTab.train => Palette.magenta,
        AthleteTab.fuel => Palette.lime,
        AthleteTab.check => Palette.violet,
        AthleteTab.altro => Palette.amber,
      };

  List<Color> get palette => switch (this) {
        AthleteTab.home => [Palette.cyan, Palette.violet, Palette.magenta],
        AthleteTab.train => [Palette.magenta, Palette.violet, Palette.cyan],
        AthleteTab.fuel => [Palette.lime, Palette.cyan, Palette.amber],
        AthleteTab.check => [Palette.violet, Palette.cyan, Palette.magenta],
        AthleteTab.altro => [Palette.amber, Palette.violet, Palette.cyan],
      };
}

/// Selected athlete tab — screens switch tabs through this (KPI tiles,
/// widget shortcuts), mirroring iOS `MainTabView`'s `$tab` binding.
final athleteTabProvider =
    StateProvider<AthleteTab>((ref) => AthleteTab.home);

/// 5-tab shell — port of iOS `MainTabView`: always-mounted pages behind a
/// floating glass tab bar, per-tab navigation stacks (pop-to-root on
/// re-tap), animated backdrop tinted by the active tab.
class AthleteShell extends ConsumerStatefulWidget {
  const AthleteShell({super.key});

  @override
  ConsumerState<AthleteShell> createState() => _AthleteShellState();
}

class _AthleteShellState extends ConsumerState<AthleteShell> {
  final _navKeys = {
    for (final tab in AthleteTab.values) tab: GlobalKey<NavigatorState>(),
  };

  Widget _rootFor(AthleteTab tab) => switch (tab) {
        AthleteTab.home => const DashboardView(),
        AthleteTab.train => const WorkoutsView(),
        AthleteTab.fuel => const NutritionView(),
        AthleteTab.check => const ChecksView(),
        AthleteTab.altro => const AthleteMoreView(),
      };

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(athleteTabProvider);
    final tabBarHidden =
        ref.watch(sessionControllerProvider.select((s) => s.tabBarHidden));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = _navKeys[tab]!.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 800),
              child: VoltBackground(
                key: ValueKey('bg-${tab.name}'),
                palette: tab.palette,
              ),
            ),
            IndexedStack(
              index: tab.index,
              children: [
                for (final t in AthleteTab.values)
                  // IndexedStack keeps every tab mounted with
                  // `maintainAnimation: true`, so without this the shimmers,
                  // reveals and mascots of the four hidden tabs keep ticking
                  // — four screens' worth of rebuild+layout every frame, for
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
            Positioned(
              left: 18,
              right: 18,
              bottom: MediaQuery.of(context).padding.bottom + 12,
              child: FloatingTabBar(
                hidden: tabBarHidden,
                tabs: [
                  for (final t in AthleteTab.values)
                    FloatingTabSpec(
                      title: t.title,
                      icon: t.icon,
                      color: () => t.color,
                    ),
                ],
                index: tab.index,
                onSelect: (i) => ref.read(athleteTabProvider.notifier).state =
                    AthleteTab.values[i],
                onReselect: (i) {
                  // Pop-to-root, like iOS resetting the tab's NavigationPath.
                  _navKeys[AthleteTab.values[i]]!
                      .currentState
                      ?.popUntil((r) => r.isFirst);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
