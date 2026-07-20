import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/utils/haptics.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';

/// 1:1 chat thread — port of iOS `ChatDetailView`: newest page first,
/// "Carica precedenti" prepends older pages preserving scroll, 4-second
/// foreground poll (`?since=`), appointment request/accept/reject bubbles.
class ChatDetailView extends ConsumerStatefulWidget {
  const ChatDetailView({super.key, required this.conversation});

  final ConversationDto conversation;

  @override
  ConsumerState<ChatDetailView> createState() => _ChatDetailViewState();
}

class _ChatDetailViewState extends ConsumerState<ChatDetailView> {
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
    ref.read(sessionControllerProvider.notifier).setTabBarHidden(true);
    _loadInitial();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _pollNew());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.dispose();
    _composer.dispose();
    // Restore the tab bar on the way out (safe even from a sheet).
    ref.read(sessionControllerProvider.notifier).setTabBarHidden(false);
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      final res = await ref.read(apiClientProvider).messages(_convId);
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
    final lastId = _messages.last.id;
    try {
      final news =
          await ref.read(apiClientProvider).newMessages(_convId, lastId);
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
          .messages(_convId, before: _messages.first.id);
      if (!mounted) return;
      setState(() {
        _messages = [...res.messages, ..._messages];
        _hasMore = res.hasMore ?? false;
      });
      // Restore the previous visual position after prepending.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent - beforeOffset);
        }
      });
    } catch (_) {/* keep old page */} finally {
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
      await ref.read(apiClientProvider).sendMessage(_convId, text);
      _composer.clear();
      await _pollNew();
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context, success: false, message: 'Invio non riuscito');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _respondAppointment(MessageDto msg, String action,
      {String? counterDate, String? counterTime}) async {
    final apptId = msg.appointmentId;
    if (apptId == null) return;
    try {
      await ref.read(apiClientProvider).respondAppointment(
            _convId,
            apptId,
            action,
            counterDate: counterDate,
            counterTime: counterTime,
          );
      Haptics.success();
      await _pollNew();
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
    final coachName = widget.conversation.coach?.fullName ?? 'Coach';
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(
        title: Column(
          children: [
            Text(coachName, style: Typo.display(17)),
            Text('COACH',
                style: Typo.mono(8, FontWeight.w700, Palette.textLow)
                    .copyWith(letterSpacing: 2)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Richiedi appuntamento',
            icon: Icon(Icons.calendar_month_rounded,
                color: Palette.cyan),
            onPressed: _openAppointmentRequest,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: Palette.cyan))
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
                      final msg = _messages[i - (_hasMore ? 1 : 0)];
                      return _bubble(msg);
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
                  Palette.cyan,
                  Palette.cyan.withValues(alpha: 0.85),
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
            Text(
              msg.body,
              style: Typo.body(14.5, FontWeight.w400,
                  mine ? Palette.void0 : Palette.textHi),
            ),
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
                Icon(Icons.event_rounded,
                    size: 15, color: Palette.cyan),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    msg.appointmentTitle ?? 'Appuntamento',
                    style: Typo.body(14, FontWeight.w700),
                  ),
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
                    child: NeonButton(
                      'Conferma',
                      compact: true,
                      color: Palette.lime,
                      onTap: () => _confirmAppointment(msg),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NeonButton(
                      'Rifiuta',
                      compact: true,
                      filled: false,
                      color: Palette.crimson,
                      onTap: () => _rejectAppointment(msg),
                    ),
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

  // ── Appointment sheets ──

  void _openAppointmentRequest() {
    showAppSheet<void>(
      context,
      heightFactor: 0.8,
      builder: (_) => _AppointmentRequestSheet(onSubmit: (title, date, from,
          to, notes) async {
        Navigator.of(context).pop();
        try {
          await ref.read(apiClientProvider).requestAppointment(
                _convId,
                title: title,
                preferredDate: date,
                timeFrom: from,
                timeTo: to,
                notes: notes,
              );
          Haptics.success();
          await _pollNew();
        } catch (_) {
          if (mounted) {
            StatusFlash.show(context,
                success: false, message: 'Richiesta non inviata');
          }
        }
      }),
    );
  }

  void _confirmAppointment(MessageDto msg) async {
    await _respondAppointment(msg, 'accept');
  }

  void _rejectAppointment(MessageDto msg) {
    showAppSheet<void>(
      context,
      heightFactor: 0.62,
      builder: (_) => _AppointmentRejectSheet(
        onSubmit: (counterDate, counterTime) async {
          Navigator.of(context).pop();
          await _respondAppointment(msg, 'reject',
              counterDate: counterDate, counterTime: counterTime);
        },
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
                    hintText: 'Scrivi un messaggio…',
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
                  color: Palette.cyan,
                  shape: BoxShape.circle,
                  boxShadow: neonGlow(Palette.cyan),
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

/// "Richiedi appuntamento" form sheet.
class _AppointmentRequestSheet extends StatefulWidget {
  const _AppointmentRequestSheet({required this.onSubmit});

  final void Function(
          String title, String date, String from, String to, String? notes)
      onSubmit;

  @override
  State<_AppointmentRequestSheet> createState() =>
      _AppointmentRequestSheetState();
}

class _AppointmentRequestSheetState extends State<_AppointmentRequestSheet> {
  final _title = TextEditingController(text: 'Chiamata con il coach');
  final _notes = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _from = const TimeOfDay(hour: 17, minute: 0);
  TimeOfDay _to = const TimeOfDay(hour: 18, minute: 0);

  String _hm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(title: Text('Richiedi appuntamento', style: Typo.display(18))),
      body: ListView(
        padding: const EdgeInsets.all(Space.screenH),
        children: [
          const Eyebrow('Dettagli'),
          const SizedBox(height: 10),
          TextField(
            controller: _title,
            style: Typo.body(15, FontWeight.w600),
            decoration: const InputDecoration(labelText: 'Titolo'),
          ),
          const SizedBox(height: 14),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Data', style: Typo.body(14, FontWeight.w600)),
            trailing: Text(Formatters.mediumDate(_date),
                style: Typo.mono(13, FontWeight.w600, Palette.cyan)),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 180)),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Dalle', style: Typo.body(14, FontWeight.w600)),
            trailing: Text(_hm(_from),
                style: Typo.mono(13, FontWeight.w600, Palette.cyan)),
            onTap: () async {
              final picked =
                  await showTimePicker(context: context, initialTime: _from);
              if (picked != null) setState(() => _from = picked);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Alle', style: Typo.body(14, FontWeight.w600)),
            trailing: Text(_hm(_to),
                style: Typo.mono(13, FontWeight.w600, Palette.cyan)),
            onTap: () async {
              final picked =
                  await showTimePicker(context: context, initialTime: _to);
              if (picked != null) setState(() => _to = picked);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            maxLines: 3,
            style: Typo.body(14, FontWeight.w400),
            decoration:
                const InputDecoration(labelText: 'Note (facoltative)'),
          ),
          const SizedBox(height: 24),
          NeonButton('Invia richiesta', onTap: () {
            widget.onSubmit(
              _title.text.trim().isEmpty
                  ? 'Appuntamento'
                  : _title.text.trim(),
              '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
              _hm(_from),
              _hm(_to),
              _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            );
          }),
        ],
      ),
    );
  }
}

/// Reject sheet with optional counter-proposal (toggle → date+time).
class _AppointmentRejectSheet extends StatefulWidget {
  const _AppointmentRejectSheet({required this.onSubmit});

  final void Function(String? counterDate, String? counterTime) onSubmit;

  @override
  State<_AppointmentRejectSheet> createState() =>
      _AppointmentRejectSheetState();
}

class _AppointmentRejectSheetState extends State<_AppointmentRejectSheet> {
  bool _counter = false;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 17, minute: 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar:
          AppBar(title: Text('Rifiuta appuntamento', style: Typo.display(18))),
      body: ListView(
        padding: const EdgeInsets.all(Space.screenH),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Proponi un nuovo orario',
                style: Typo.body(14.5, FontWeight.w600)),
            value: _counter,
            onChanged: (v) => setState(() => _counter = v),
          ),
          if (_counter) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Data', style: Typo.body(14, FontWeight.w600)),
              trailing: Text(Formatters.mediumDate(_date),
                  style: Typo.mono(13, FontWeight.w600, Palette.cyan)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 180)),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Orario', style: Typo.body(14, FontWeight.w600)),
              trailing: Text(
                  '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                  style: Typo.mono(13, FontWeight.w600, Palette.cyan)),
              onTap: () async {
                final picked =
                    await showTimePicker(context: context, initialTime: _time);
                if (picked != null) setState(() => _time = picked);
              },
            ),
          ],
          const SizedBox(height: 24),
          NeonButton(
            'Rifiuta',
            color: Palette.crimson,
            onTap: () => widget.onSubmit(
              _counter
                  ? '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'
                  : null,
              _counter
                  ? '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}'
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
