import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/utils/haptics.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';

/// Coach conversation list — port of iOS `CoachMessagesView`: threads with
/// unread badges + "nuova conversazione" picker (athletes without a thread).
class CoachMessagesView extends ConsumerStatefulWidget {
  const CoachMessagesView({super.key});

  @override
  ConsumerState<CoachMessagesView> createState() => _CoachMessagesViewState();
}

class _CoachMessagesViewState extends ConsumerState<CoachMessagesView> {
  List<CoachConversation>? _conversations;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(apiClientProvider).coachConversations();
      if (mounted) setState(() => _conversations = list);
    } catch (_) {
      if (mounted && _conversations == null) setState(() => _error = true);
    }
  }

  Future<void> _startNew() async {
    await showAppSheet<void>(
      context,
      heightFactor: 0.8,
      builder: (_) => _NewConversationSheet(onStarted: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _conversations;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Nuova conversazione',
            icon: const Icon(Icons.edit_square, color: Palette.textHi),
            onPressed: _startNew,
          ),
        ],
      ),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(eyebrow: 'I tuoi atleti', title: 'Messaggi'),
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
              message: 'Nessuna conversazione. Scrivine una con l\'icona in alto.',
            )
          else
            for (final conv in list)
              VoltPanel(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CoachThreadView(conversation: conv),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    AvatarView(
                      url: conv.client?.profileImageUrl,
                      name: conv.client?.displayName ?? 'Atleta',
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(conv.client?.displayName ?? 'Atleta',
                              style: Typo.body(15, FontWeight.w700)),
                          if ((conv.lastMessage ?? '').isNotEmpty)
                            Text(conv.lastMessage!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Typo.body(
                                    12.5, FontWeight.w400, Palette.textMid)),
                        ],
                      ),
                    ),
                    if (conv.unreadCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: const BoxDecoration(
                            color: Palette.crimson,
                            shape: BoxShape.circle),
                        child: Text('${conv.unreadCount}',
                            style: Typo.mono(
                                9, FontWeight.w700, Palette.void0)),
                      )
                    else if (Formatters.parseDate(conv.lastMessageAt) != null)
                      Text(
                        Formatters.relative(
                            Formatters.parseDate(conv.lastMessageAt)!
                                .toLocal()),
                        style:
                            Typo.mono(9, FontWeight.w600, Palette.textLow),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// Coach thread — same idiom as the athlete chat but on the coach endpoints
/// (5 s foreground poll, like iOS `CoachThreadView`).
class CoachThreadView extends ConsumerStatefulWidget {
  const CoachThreadView({super.key, required this.conversation});

  final CoachConversation conversation;

  @override
  ConsumerState<CoachThreadView> createState() => _CoachThreadViewState();
}

class _CoachThreadViewState extends ConsumerState<CoachThreadView> {
  final _scroll = ScrollController();
  final _composer = TextEditingController();
  List<MessageDto> _messages = [];
  bool _loading = true;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _sending = false;
  Timer? _poll;

  int get _convId => widget.conversation.id;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionControllerProvider.notifier);
    session.setTabBarHidden(true);
    session.setChironHidden(true);
    _loadInitial();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _pollNew());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.dispose();
    _composer.dispose();
    final session = ref.read(sessionControllerProvider.notifier);
    session.setTabBarHidden(false);
    session.setChironHidden(false);
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      final res = await ref.read(apiClientProvider).coachMessages(_convId);
      if (!mounted) return;
      setState(() {
        _messages = res.messages;
        _hasMore = res.hasMore ?? false;
        _loading = false;
      });
      _jumpToBottom();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pollNew() async {
    if (_messages.isEmpty) return _loadInitial();
    try {
      final news = await ref
          .read(apiClientProvider)
          .coachNewMessages(_convId, _messages.last.id);
      if (!mounted || news.isEmpty) return;
      setState(() => _messages = [..._messages, ...news]);
      _jumpToBottom(animated: true);
    } catch (_) {/* poll silently */}
  }

  Future<void> _loadOlder() async {
    if (_loadingMore || _messages.isEmpty) return;
    setState(() => _loadingMore = true);
    final beforeOffset =
        _scroll.hasClients ? _scroll.position.extentAfter : 0.0;
    try {
      final res = await ref
          .read(apiClientProvider)
          .coachMessages(_convId, before: _messages.first.id);
      if (!mounted) return;
      setState(() {
        _messages = [...res.messages, ..._messages];
        _hasMore = res.hasMore ?? false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent - beforeOffset);
        }
      });
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _jumpToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animated) {
        _scroll.animateTo(target,
            duration: Motion.snappyDuration, curve: Motion.snappy);
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(apiClientProvider).coachSendMessage(_convId, text);
      _composer.clear();
      await _pollNew();
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Invio non riuscito');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _respondAppointment(MessageDto msg, String action) async {
    final apptId = msg.appointmentId;
    if (apptId == null) return;
    try {
      await ref
          .read(apiClientProvider)
          .coachRespondAppointment(_convId, apptId, action);
      Haptics.success();
      await _loadInitial();
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Operazione non riuscita');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.conversation.client?.displayName ?? 'Atleta';
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(
        title: Column(
          children: [
            Text(name, style: Typo.display(17)),
            Text('ATLETA',
                style: Typo.mono(8, FontWeight.w700, Palette.textLow)
                    .copyWith(letterSpacing: 2)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? Center(
                    child:
                        CircularProgressIndicator(color: Palette.bronze))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    itemCount: _messages.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (_hasMore && i == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: LoadMoreButton(
                              onTap: _loadOlder, loading: _loadingMore),
                        );
                      }
                      return _bubble(_messages[i - (_hasMore ? 1 : 0)]);
                    },
                  ),
          ),
          _composerBar(),
        ],
      ),
    );
  }

  Widget _bubble(MessageDto msg) {
    if (msg.messageType == 'APPOINTMENT_REQUEST' ||
        msg.messageType == 'APPOINTMENT_RESPONSE') {
      return _appointmentBubble(msg);
    }
    final mine = msg.isMine;
    final time = Formatters.parseDate(msg.sentAt);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 290),
        decoration: BoxDecoration(
          gradient: mine
              ? LinearGradient(colors: [
                  Palette.bronze,
                  Palette.bronze.withValues(alpha: 0.85),
                ])
              : null,
          color: mine ? null : Palette.void2,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(msg.body,
                style: Typo.body(14.5, FontWeight.w400,
                    mine ? Palette.void0 : Palette.textHi)),
            if (time != null) ...[
              const SizedBox(height: 3),
              Text(
                Formatters.time(time.toLocal()),
                style: Typo.mono(
                    8.5,
                    FontWeight.w500,
                    mine
                        ? Palette.void0.withValues(alpha: 0.75)
                        : Palette.textLow),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _appointmentBubble(MessageDto msg) {
    final start = Formatters.parseDate(msg.appointmentStart);
    final status = msg.appointmentStatus?.toUpperCase();
    final expired = msg.appointmentExpired == true;
    final pending = status == 'PENDING' && !expired;
    final (badge, badgeColor) = switch ((status, expired)) {
      (_, true) => ('Scaduta', Palette.textLow),
      ('CONFIRMED', _) => ('Confermato', Palette.lime),
      ('REJECTED', _) => ('Rifiutato', Palette.crimson),
      _ => ('In attesa', Palette.amber),
    };
    return Align(
      alignment: msg.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: voltPanel(tint: Palette.cyan.withValues(alpha: 0.4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_rounded, size: 15, color: Palette.cyan),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(msg.appointmentTitle ?? 'Appuntamento',
                      style: Typo.body(14, FontWeight.w700)),
                ),
              ],
            ),
            if (start != null) ...[
              const SizedBox(height: 6),
              Text(
                '${Formatters.weekdayLongDate(start.toLocal())} · ${Formatters.time(start.toLocal())}',
                style: Typo.mono(11, FontWeight.w600, Palette.textMid),
              ),
            ],
            if (msg.body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(msg.body,
                  style: Typo.body(13, FontWeight.w400, Palette.textMid)),
            ],
            const SizedBox(height: 10),
            if (pending && !msg.isMine)
              Row(
                children: [
                  Expanded(
                    child: NeonButton('Conferma',
                        compact: true,
                        color: Palette.lime,
                        onTap: () => _respondAppointment(msg, 'accept')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NeonButton('Rifiuta',
                        compact: true,
                        filled: false,
                        color: Palette.crimson,
                        onTap: () => _respondAppointment(msg, 'reject')),
                  ),
                ],
              )
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(badge,
                    style: Typo.mono(10, FontWeight.w700, badgeColor)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _composerBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: const BoxDecoration(
          color: Palette.void0,
          border: Border(top: BorderSide(color: Palette.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Palette.void1,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Palette.line),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _composer,
                  minLines: 1,
                  maxLines: 5,
                  style: Typo.body(15, FontWeight.w400),
                  decoration: InputDecoration(
                    hintText: 'Scrivi al tuo atleta…',
                    hintStyle:
                        Typo.body(15, FontWeight.w400, Palette.textLow),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Pressable(
              onTap: _sending ? null : _send,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Palette.bronze,
                  shape: BoxShape.circle,
                  boxShadow: neonGlow(Palette.bronze),
                ),
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Palette.void0),
                      )
                    : const Icon(Icons.arrow_upward_rounded,
                        size: 20, color: Palette.void0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewConversationSheet extends ConsumerStatefulWidget {
  const _NewConversationSheet({required this.onStarted});

  final VoidCallback onStarted;

  @override
  ConsumerState<_NewConversationSheet> createState() =>
      _NewConversationSheetState();
}

class _NewConversationSheetState
    extends ConsumerState<_NewConversationSheet> {
  List<CoachMessageableClient>? _clients;
  int? _clientId;
  final _body = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(apiClientProvider)
        .coachMessageableClients()
        .then((c) => mounted ? setState(() => _clients = c) : null)
        .catchError((_) =>
            mounted ? setState(() => _clients = const []) : null);
  }

  Future<void> _start() async {
    if (_clientId == null || _body.text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(apiClientProvider)
          .coachStartConversation(_clientId!, _body.text.trim());
      if (!mounted) return;
      widget.onStarted();
      Navigator.of(context, rootNavigator: true).pop();
      StatusFlash.show(context, success: true, message: 'Messaggio inviato');
    } catch (_) {
      if (mounted) {
        setState(() => _sending = false);
        StatusFlash.show(context,
            success: false, message: 'Invio non riuscito');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = _clients;
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(
          title: Text('Nuova conversazione', style: Typo.display(18))),
      body: ListView(
        padding: const EdgeInsets.all(Space.screenH),
        children: [
          const Eyebrow('Atleta'),
          const SizedBox(height: 8),
          if (clients == null)
            const AvatarRowsSkeleton(count: 4)
          else if (clients.isEmpty)
            const EmptyPanel(
              icon: Icons.forum_outlined,
              message: 'Hai già una conversazione con tutti i tuoi atleti.',
            )
          else
            for (final c in clients)
              RadioListTile<int>(
                value: c.id,
                // ignore: deprecated_member_use
                groupValue: _clientId,
                // ignore: deprecated_member_use
                onChanged: (v) => setState(() => _clientId = v),
                activeColor: Palette.bronze,
                contentPadding: EdgeInsets.zero,
                secondary: AvatarView(
                    url: c.profileImageUrl,
                    name: c.displayName,
                    size: 38),
                title: Text(c.displayName,
                    style: Typo.body(14.5, FontWeight.w600)),
              ),
          const SizedBox(height: 14),
          TextField(
            controller: _body,
            maxLines: 4,
            minLines: 2,
            style: Typo.body(14.5, FontWeight.w400),
            decoration: const InputDecoration(labelText: 'Messaggio'),
          ),
          const SizedBox(height: 20),
          NeonButton('Invia',
              color: Palette.bronze, loading: _sending, onTap: _start),
        ],
      ),
    );
  }
}

/// Canned auto-replies — port of iOS `CoachAutoMessagesView`.
class CoachAutoMessagesView extends ConsumerStatefulWidget {
  const CoachAutoMessagesView({super.key});

  @override
  ConsumerState<CoachAutoMessagesView> createState() =>
      _CoachAutoMessagesViewState();
}

class _CoachAutoMessagesViewState
    extends ConsumerState<CoachAutoMessagesView> {
  List<CoachAutoMessage>? _templates;
  final Map<String, TextEditingController> _bodies = {};
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _bodies.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(apiClientProvider).coachAutoMessages();
      if (mounted) {
        setState(() {
          _templates = res.templates;
          for (final t in res.templates) {
            _bodies[t.key] = TextEditingController(text: t.body);
          }
        });
      }
    } catch (_) {
      if (mounted && _templates == null) setState(() => _error = true);
    }
  }

  Future<void> _save(CoachAutoMessage t, {bool? enabled}) async {
    try {
      await ref.read(apiClientProvider).coachUpdateAutoMessage(
            t.key,
            enabled: enabled ?? t.enabled,
            body: _bodies[t.key]?.text.trim() ?? t.body,
          );
      if (mounted) {
        StatusFlash.show(context, success: true, message: 'Salvato');
      }
      await _load();
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Salvataggio non riuscito');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = _templates;
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(
          title: Text('Messaggi automatici', style: Typo.display(18))),
      body: ListView(
        padding: const EdgeInsets.all(Space.screenH),
        children: [
          Text(
            'Vengono inviati automaticamente al verificarsi dell\'evento.',
            style: Typo.body(13.5, FontWeight.w400, Palette.textMid),
          ),
          const SizedBox(height: 16),
          if (templates == null && !_error)
            const FormSkeleton()
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else
            for (final t in templates!)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  decoration: voltPanel(),
                  padding: const EdgeInsets.all(Space.card),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                                t.label.isEmpty ? t.key : t.label,
                                style: Typo.body(14.5, FontWeight.w700)),
                          ),
                          Switch(
                            value: t.enabled,
                            onChanged: (v) => _save(t, enabled: v),
                          ),
                        ],
                      ),
                      TextField(
                        controller: _bodies[t.key],
                        maxLines: 3,
                        minLines: 2,
                        style: Typo.body(13.5, FontWeight.w400),
                        decoration: const InputDecoration(isDense: true),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => _save(t),
                          child: Text('Salva',
                              style: Typo.body(
                                  13, FontWeight.w700, Palette.bronze)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
