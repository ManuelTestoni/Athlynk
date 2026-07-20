import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/theme.dart';
import '../../athlete/notifications/notifications_view.dart';
import '../agenda/coach_agenda_view.dart';
import '../analytics/coach_analytics_view.dart';
import '../clients/coach_clients_view.dart';
import '../messages/coach_messages_view.dart';
import '../profile/coach_profile_view.dart';
import '../resources/coach_resources_view.dart';
import '../subscriptions/coach_subscriptions_view.dart';

/// Coach "Altro" hub — port of iOS `CoachMoreView`: identity card + 8-tile
/// grid over the secondary destinations.
class CoachMoreView extends ConsumerWidget {
  const CoachMoreView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final user = session.user;

    void push(Widget screen) => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));

    final tiles = <({
      String title,
      String subtitle,
      IconData icon,
      Color accent,
      VoidCallback onTap
    })>[
      (
        title: 'Atleti',
        subtitle: 'Il tuo roster',
        icon: Icons.groups_rounded,
        accent: Palette.bronze,
        onTap: () => push(const CoachClientsView()),
      ),
      (
        title: 'Chat',
        subtitle: 'Parla con i tuoi atleti',
        icon: Icons.forum_rounded,
        accent: Palette.violet,
        onTap: () => push(const CoachMessagesView()),
      ),
      (
        title: 'Agenda',
        subtitle: 'Appuntamenti e visite',
        icon: Icons.calendar_month_rounded,
        accent: Palette.cyan,
        onTap: () => push(const CoachAgendaView()),
      ),
      (
        title: 'Abbonamenti',
        subtitle: 'Piani, incassi e Stripe',
        icon: Icons.workspace_premium_rounded,
        accent: Palette.amber,
        onTap: () => push(const CoachSubscriptionsView()),
      ),
      (
        title: 'Libreria risorse',
        subtitle: 'Schede, piani, modelli',
        icon: Icons.folder_copy_rounded,
        accent: Palette.lime,
        onTap: () => push(const CoachResourcesView()),
      ),
      (
        title: 'Analisi',
        subtitle: 'KPI e rischio abbandono',
        icon: Icons.query_stats_rounded,
        accent: Palette.bronze,
        onTap: () => push(const CoachAnalyticsView()),
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
        accent: Palette.phase,
        onTap: () => push(const CoachProfileView()),
      ),
    ];

    return ScreenScroll(
      spacing: Space.element,
      children: [
        const ScreenHeader(eyebrow: 'La tua cabina di regia', title: 'Altro'),
        VoltPanel(
          child: Row(
            children: [
              AvatarView(
                url: session.avatarUrl,
                name: user?.displayName ?? 'Coach',
                size: 52,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.displayName ?? 'Coach',
                        style: Typo.display(18)),
                    Text(user?.email ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Typo.body(
                            12.5, FontWeight.w400, Palette.textMid)),
                    const SizedBox(height: 4),
                    StatusBadge('Coach', color: Palette.bronze),
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
