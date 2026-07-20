import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/providers.dart';
import '../../../core/utils/haptics.dart';
import '../../../design/components/chiron_mascot.dart';
import '../../../design/components/confirm_dialog.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';
import 'chiron_router.dart';

/// Chiron AI chat — port of iOS `CoachChironView`/`CoachChironVM`:
/// paginated history, token-by-token SSE streaming, source chips, in-app
/// action links (deep-linked into native screens) and a pending-action
/// confirm banner. Gated server-side by the Chiron add-on.
class CoachChironView extends ConsumerStatefulWidget {
  const CoachChironView({super.key});

  @override
  ConsumerState<CoachChironView> createState() => _CoachChironViewState();
}

class _ChironTurn {
  _ChironTurn({
    required this.role,
    required this.content,
    this.sources = const [],
    this.actions = const [],
    this.streaming = false,
  });

  final String role; // user | assistant
  String content;
  List<Map<String, dynamic>> sources;
  List<Map<String, dynamic>> actions;
  bool streaming;
}

class _CoachChironViewState extends ConsumerState<CoachChironView> {
  final _scroll = ScrollController();
  final _composer = TextEditingController();
  final List<_ChironTurn> _turns = [];
  Map<String, dynamic>? _pendingAction;
  CancelToken? _cancel;
  bool _loading = true;
  bool _streaming = false;
  bool _accessDenied = false;
  int _speak = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _scroll.dispose();
    _composer.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final res = await ref.read(apiClientProvider).chironHistory();
      if (!mounted) return;
      setState(() {
        _turns
          ..clear()
          ..addAll(res.messages.map((m) => _ChironTurn(
                role: m.role,
                content: m.content,
                sources: m.sources ?? const [],
                actions: m.actions ?? const [],
              )));
        _loading = false;
      });
      _jumpToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // 403 → the coach's plan doesn't include the Chiron add-on.
        _accessDenied = e.toString().contains('403');
      });
    }
  }

  void _jumpToBottom({bool animated = true}) {
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
    if (text.isEmpty || _streaming) return;
    _composer.clear();
    Haptics.tap();
    setState(() {
      _turns.add(_ChironTurn(role: 'user', content: text));
      _turns.add(_ChironTurn(
          role: 'assistant', content: '', streaming: true));
      _streaming = true;
      _speak++;
    });
    _jumpToBottom();

    final reply = _turns.last;
    _cancel = CancelToken();
    try {
      final stream = ref
          .read(apiClientProvider)
          .chironChatStream(text, cancelToken: _cancel);
      await for (final frame in stream) {
        if (frame.isEmpty) continue;
        Map<String, dynamic> payload;
        try {
          payload = jsonDecode(frame) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        final token = payload['token'] as String?;
        if (token != null) {
          setState(() => reply.content += token);
          _jumpToBottom(animated: false);
        }
        if (payload['done'] == true) {
          setState(() {
            reply.content =
                (payload['response'] as String?) ?? reply.content;
            reply.sources = (payload['sources'] as List?)
                    ?.cast<Map<String, dynamic>>() ??
                const [];
            reply.actions = (payload['actions'] as List?)
                    ?.cast<Map<String, dynamic>>() ??
                const [];
            reply.streaming = false;
            _pendingAction = (payload['pending_action'] as Map?)
                ?.cast<String, dynamic>();
          });
        }
      }
    } catch (_) {
      setState(() {
        if (reply.content.isEmpty) {
          reply.content =
              'Non riesco a rispondere in questo momento. Riprova.';
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          reply.streaming = false;
          _streaming = false;
        });
        _jumpToBottom();
      }
    }
  }

  Future<void> _executePendingAction() async {
    final action = _pendingAction;
    if (action == null) return;
    try {
      await ref.read(apiClientProvider).chironExecuteAction(action);
      Haptics.success();
      if (mounted) {
        setState(() => _pendingAction = null);
        StatusFlash.show(context, success: true, message: 'Azione eseguita');
      }
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Azione non riuscita');
      }
    }
  }

  Future<void> _clear() async {
    final ok = await ConfirmCenter.confirm(
      context,
      const ConfirmOptions(
        title: 'Cancellare la conversazione?',
        subtitle: 'La memoria di Chiron per questa chat verrà azzerata.',
        icon: Icons.delete_sweep_outlined,
        variant: ConfirmVariant.danger,
        confirmLabel: 'Cancella',
      ),
    );
    if (!ok) return;
    try {
      await ref.read(apiClientProvider).chironClear();
      if (mounted) setState(() => _turns.clear());
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Operazione non riuscita');
      }
    }
  }

  /// Chiron emits relative web paths (Django `reverse()` output); route them
  /// into the native screens, like iOS `CoachDeepLink.parse`.
  void _openActionLink(String path) {
    final target = ChironDeepLink.parse(path);
    if (target == null) {
      StatusFlash.show(context,
          success: false, message: 'Sezione non disponibile');
      return;
    }
    ref.read(chironRouterProvider.notifier).state = target;
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_rounded,
                size: 16, color: Palette.goldText),
            const SizedBox(width: 8),
            Text('Chiron', style: Typo.display(18)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cancella chat',
            icon: const Icon(Icons.delete_sweep_outlined,
                color: Palette.textMid),
            onPressed: _clear,
          ),
        ],
      ),
      body: _accessDenied
          ? Padding(
              padding: const EdgeInsets.all(Space.screenH),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const ChironMascot(size: 110),
                  const SizedBox(height: 24),
                  Text('Chiron non è incluso nel tuo piano',
                      textAlign: TextAlign.center,
                      style: Typo.poster(26)),
                  const SizedBox(height: 10),
                  Text(
                    'Attiva il componente aggiuntivo Chiron dal tuo abbonamento Athlynk per avere l\'assistente sempre con te.',
                    textAlign: TextAlign.center,
                    style:
                        Typo.body(14, FontWeight.w400, Palette.textMid),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: _loading
                      ? Center(
                          child: CircularProgressIndicator(
                              color: Palette.bronze))
                      : _turns.isEmpty
                          ? _emptyState()
                          : ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(
                                  Space.screenH, 12, Space.screenH, 12),
                              itemCount: _turns.length,
                              itemBuilder: (context, i) =>
                                  _turnBubble(_turns[i]),
                            ),
                ),
                if (_pendingAction != null) _pendingBanner(),
                _composerBar(),
              ],
            ),
    );
  }

  Widget _emptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.screenH),
      child: Column(
        children: [
          const SizedBox(height: 12),
          ChironMascot(size: 104, speak: _speak),
          const SizedBox(height: 20),
          Text('Χαῖρε. Sono Chiron.',
              textAlign: TextAlign.center, style: Typo.poster(28)),
          const SizedBox(height: 8),
          Text(
            'Chiedimi dei tuoi atleti, dei check da rivedere o di come sta andando il tuo business.',
            textAlign: TextAlign.center,
            style: Typo.body(14, FontWeight.w400, Palette.textMid),
          ),
          const SizedBox(height: 20),
          for (final prompt in const [
            'Quali atleti sono a rischio abbandono?',
            'Chi ha check da rivedere?',
            'Come vanno i ricavi questo mese?',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Pressable(
                onTap: () {
                  _composer.text = prompt;
                  _send();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: voltPanel(
                      tint: Palette.amber.withValues(alpha: 0.35)),
                  child: Text(prompt,
                      style: Typo.body(13.5, FontWeight.w600)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _turnBubble(_ChironTurn turn) {
    final mine = turn.role == 'user';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: mine
            ? BoxDecoration(
                gradient: LinearGradient(colors: [
                  Palette.bronze,
                  Palette.bronze.withValues(alpha: 0.85),
                ]),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(4),
                ),
              )
            : voltPanel(tint: Palette.amber.withValues(alpha: 0.35)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (turn.content.isEmpty && turn.streaming)
              const _TypingDots()
            else
              Text(
                turn.content,
                style: Typo.body(14.5, FontWeight.w400,
                    mine ? Palette.void0 : Palette.textHi),
              ),
            if (turn.sources.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in turn.sources)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Palette.void2,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        (s['title'] as String?) ??
                            (s['label'] as String?) ??
                            'fonte',
                        style: Typo.mono(
                            9, FontWeight.w600, Palette.textMid),
                      ),
                    ),
                ],
              ),
            ],
            if (turn.actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final a in turn.actions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Pressable(
                    onTap: () {
                      final url = (a['url'] as String?) ??
                          (a['path'] as String?) ??
                          '';
                      if (url.isNotEmpty) _openActionLink(url);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_forward_rounded,
                            size: 13, color: Palette.cyan),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            (a['label'] as String?) ?? 'Apri',
                            style: Typo.body(
                                13, FontWeight.w700, Palette.cyan),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pendingBanner() {
    final action = _pendingAction!;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Space.screenH),
      padding: const EdgeInsets.all(14),
      decoration: voltPanel(tint: Palette.amber.withValues(alpha: 0.6)),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, size: 18, color: Palette.goldText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              (action['label'] as String?) ??
                  'Chiron propone un\'azione: confermi?',
              style: Typo.body(13, FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _pendingAction = null),
            child: Text('No',
                style: Typo.body(13, FontWeight.w600, Palette.textMid)),
          ),
          NeonButton('Conferma',
              compact: true,
              expand: false,
              color: Palette.amber,
              onTap: _executePendingAction),
        ],
      ),
    );
  }

  Widget _composerBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                    hintText: 'Chiedi a Chiron…',
                    hintStyle:
                        Typo.body(15, FontWeight.w400, Palette.textLow),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Pressable(
              onTap: _streaming ? null : _send,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFC9971E), Color(0xFF8A6508)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: neonGlow(Palette.amber),
                ),
                child: _streaming
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

/// Three-dot "typing" indicator while the first token is still in flight.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Opacity(
                  opacity: 0.35 +
                      0.65 *
                          ((((_c.value * 3) - i).clamp(0.0, 1.0)) *
                              (1 - ((_c.value * 3) - i - 1).clamp(0.0, 1.0))),
                  child: const CircleAvatar(
                      radius: 3.2, backgroundColor: Palette.goldText),
                ),
              ),
          ],
        );
      },
    );
  }
}
