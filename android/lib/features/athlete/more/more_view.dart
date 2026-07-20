import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/theme.dart';
import '../chat/chat_list_view.dart';
import '../more/agenda_view.dart';
import '../more/journey_view.dart';
import '../more/subscription_view.dart';
import '../notifications/notifications_view.dart';
import '../profile/athlete_profile_view.dart';
import '../profile/help_view.dart';
import '../progress/progress_tracker_view.dart';

/// Altro tab root — port of iOS `AthleteMoreView`: identity card + 2-column
/// hub grid over the 8 secondary destinations.
class AthleteMoreView extends ConsumerWidget {
  const AthleteMoreView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final user = session.user;

    void push(Widget screen) => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));

    final tiles = <({String title, String subtitle, IconData icon, Color accent, VoidCallback onTap})>[
      (
        title: 'Il mio andamento',
        subtitle: 'Peso, circonferenze e pliche',
        icon: Icons.query_stats_rounded,
        accent: Palette.cyan,
        onTap: () => push(const ProgressTrackerView()),
      ),
      (
        title: 'Il mio percorso',
        subtitle: 'Piani, diete e check',
        icon: Icons.map_rounded,
        accent: Palette.bronze,
        onTap: () => push(const JourneyView()),
      ),
      (
        title: 'Messaggi',
        subtitle: 'Parla con il tuo coach',
        icon: Icons.forum_rounded,
        accent: Palette.violet,
        onTap: () => push(const ChatListView()),
      ),
      (
        title: 'Agenda',
        subtitle: 'Appuntamenti e sessioni',
        icon: Icons.calendar_month_rounded,
        accent: Palette.cyan,
        onTap: () => push(const AgendaView()),
      ),
      (
        title: 'Abbonamento',
        subtitle: 'Il tuo piano',
        icon: Icons.workspace_premium_rounded,
        accent: Palette.magenta,
        onTap: () => push(const SubscriptionView()),
      ),
      (
        title: 'Notifiche',
        subtitle: 'Centro notifiche',
        icon: Icons.notifications_rounded,
        accent: Palette.amber,
        onTap: () => push(const NotificationsView()),
      ),
      (
        title: 'Profilo & Impostazioni',
        subtitle: 'I tuoi dati e preferenze',
        icon: Icons.person_rounded,
        accent: Palette.amber,
        onTap: () => push(const AthleteProfileView()),
      ),
      (
        title: 'Aiuto',
        subtitle: 'Guida e supporto',
        icon: Icons.help_outline_rounded,
        accent: Palette.violet,
        onTap: () => push(const HelpView()),
      ),
    ];

    return ScreenScroll(
      spacing: Space.element,
      children: [
        const ScreenHeader(eyebrow: 'Il tuo spazio', title: 'Altro'),
        VoltPanel(
          child: Row(
            children: [
              AvatarView(
                url: session.avatarUrl,
                name: user?.displayName ?? 'Atleta',
                size: 52,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.displayName ?? 'Atleta',
                        style: Typo.display(18)),
                    Text(user?.email ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Typo.body(
                            12.5, FontWeight.w400, Palette.textMid)),
                    const SizedBox(height: 4),
                    StatusBadge('Atleta', color: Palette.cyan),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Eyebrow('Gestione'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.18,
          children: [
            for (final (i, t) in tiles.indexed)
              HubTile(
                title: t.title,
                subtitle: t.subtitle,
                icon: t.icon,
                accent: t.accent,
                index: i,
                onTap: t.onTap,
              ),
          ],
        ),
      ],
    );
  }
}
