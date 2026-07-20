import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';
import 'chat_detail_view.dart';

/// Conversation list — port of iOS `ChatListView`.
class ChatListView extends ConsumerStatefulWidget {
  const ChatListView({super.key});

  @override
  ConsumerState<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends ConsumerState<ChatListView> {
  List<ConversationDto>? _conversations;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(apiClientProvider).conversations();
      if (mounted) setState(() => _conversations = list);
    } catch (_) {
      if (mounted && _conversations == null) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _conversations;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        onRefresh: _load,
        children: [
          const ScreenHeader(eyebrow: 'Messaggi', title: 'Chat'),
          if (list == null && !_error)
            const AvatarRowsSkeleton()
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (list!.isEmpty)
            const EmptyPanel(
              icon: Icons.forum_outlined,
              message: 'Nessuna conversazione.',
            )
          else
            for (final conv in list)
              VoltPanel(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChatDetailView(conversation: conv),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    AvatarView(
                      url: conv.coach?.profileImageUrl,
                      name: conv.coach?.fullName ?? 'Coach',
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(conv.coach?.fullName ?? 'Coach',
                              style: Typo.body(15, FontWeight.w700)),
                          if ((conv.lastMessage ?? '').isNotEmpty)
                            Text(conv.lastMessage!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Typo.body(
                                    13, FontWeight.w400, Palette.textMid)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        size: 18, color: Palette.textLow),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
