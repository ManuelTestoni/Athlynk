import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';

/// Notification feed — port of iOS `NotificheView`: unread highlight, icon by
/// type, tap marks read (optimistic), 20 per page. Shared by both apps (the
/// server keys on the authenticated user).
class NotificationsView extends ConsumerStatefulWidget {
  const NotificationsView({super.key});

  @override
  ConsumerState<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends ConsumerState<NotificationsView> {
  List<NotificationDto>? _items;
  bool _error = false;
  bool _hasMore = false;
  bool _loadingMore = false;
  StreamSubscription<String>? _remote;

  @override
  void initState() {
    super.initState();
    _load();
    _remote = ref
        .read(pushBridgeProvider)
        .onTypes(const {}).listen((_) => _load());
  }

  @override
  void dispose() {
    _remote?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(apiClientProvider).notifications();
      if (mounted) {
        setState(() {
          _items = res.notifications;
          _hasMore = res.hasMore ?? false;
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
          .notifications(offset: _items?.length ?? 0);
      if (mounted) {
        setState(() {
          _items = [...?_items, ...res.notifications];
          _hasMore = res.hasMore ?? false;
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  IconData _iconFor(String type) {
    final t = type.toUpperCase();
    if (t.contains('MESSAGE')) return Icons.forum_rounded;
    if (t.contains('CHECK')) return Icons.verified_rounded;
    if (t.contains('WORKOUT')) return Icons.fitness_center_rounded;
    if (t.contains('NUTRITION') || t.contains('MACRO')) {
      return Icons.restaurant_rounded;
    }
    if (t.contains('SUPPLEMENT')) return Icons.medication_rounded;
    if (t.contains('APPOINTMENT')) return Icons.calendar_month_rounded;
    return Icons.notifications_rounded;
  }

  Future<void> _markRead(NotificationDto n) async {
    if (n.isRead) return;
    setState(() {
      _items = [
        for (final item in _items!)
          if (item.id == n.id) item.copyWith(isRead: true) else item,
      ];
    });
    try {
      await ref.read(apiClientProvider).markNotificationRead(n.id);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(eyebrow: 'Centro notifiche', title: 'Notifiche'),
          if (items == null && !_error)
            const AvatarRowsSkeleton()
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (items!.isEmpty)
            const EmptyPanel(
              icon: Icons.notifications_none_rounded,
              message: 'Nessuna notifica.',
            )
          else ...[
            for (final n in items)
              VoltPanel(
                tint: n.isRead
                    ? Palette.line
                    : Palette.amber.withValues(alpha: 0.5),
                onTap: () => _markRead(n),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Palette.amber.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(_iconFor(n.type),
                              size: 18, color: Palette.amber),
                        ),
                        if (!n.isRead)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: const BoxDecoration(
                                  color: Palette.crimson,
                                  shape: BoxShape.circle),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.title,
                              style: Typo.body(14.5,
                                  n.isRead ? FontWeight.w500 : FontWeight.w700)),
                          if ((n.body ?? '').isNotEmpty)
                            Text(n.body!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Typo.body(12.5, FontWeight.w400,
                                    Palette.textMid)),
                          if (Formatters.parseDate(n.createdAt) != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                Formatters.relative(Formatters.parseDate(
                                        n.createdAt)!
                                    .toLocal()),
                                style: Typo.mono(9, FontWeight.w600,
                                    Palette.textLow),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (_hasMore)
              LoadMoreButton(onTap: _loadMore, loading: _loadingMore),
          ],
        ],
      ),
    );
  }
}
