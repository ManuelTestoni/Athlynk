import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/chat.dart';
import '../theme.dart';
import 'confirm_dialog.dart';
import 'neon_button.dart';
import 'panel.dart';
import 'scaffold.dart';
import 'skeleton.dart';
import 'status_overlay.dart';

/// Google/Apple Calendar subscription — port of iOS `CalendarFeedView`:
/// feed URL, add-to-Google link, copy, rotate. Shared by both roles via
/// injected loaders.
class CalendarFeedView extends StatefulWidget {
  const CalendarFeedView({
    super.key,
    required this.load,
    required this.rotate,
  });

  final Future<CalendarFeedDto> Function() load;
  final Future<CalendarFeedDto> Function() rotate;

  @override
  State<CalendarFeedView> createState() => _CalendarFeedViewState();
}

class _CalendarFeedViewState extends State<CalendarFeedView> {
  CalendarFeedDto? _feed;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await widget.load();
      if (mounted) setState(() => _feed = f);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _rotate() async {
    final ok = await ConfirmCenter.confirm(
      context,
      const ConfirmOptions(
        title: 'Rigenerare il link?',
        subtitle:
            'Il vecchio link smetterà di funzionare su tutti i calendari collegati.',
        icon: Icons.autorenew_rounded,
        variant: ConfirmVariant.danger,
        confirmLabel: 'Rigenera',
      ),
    );
    if (!ok) return;
    try {
      final f = await widget.rotate();
      if (mounted) {
        setState(() => _feed = f);
        StatusFlash.show(context, success: true, message: 'Link rigenerato');
      }
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Operazione non riuscita');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(title: Text('Calendario', style: Typo.display(18))),
      body: ListView(
        padding: const EdgeInsets.all(Space.screenH),
        children: [
          Text(
            'Iscriviti al feed per vedere i tuoi appuntamenti in Google Calendar o Apple Calendar. Il calendario si aggiorna da solo.',
            style: Typo.body(14, FontWeight.w400, Palette.textMid),
          ),
          const SizedBox(height: 18),
          if (feed == null && !_error)
            const Shimmer(child: SkelCard(height: 180))
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else ...[
            NavListRow(
              title: 'Aggiungi a Google Calendar',
              icon: Icons.event_available_rounded,
              accent: Palette.cyan,
              onTap: () => launchUrl(Uri.parse(feed!.googleSubscribeUrl),
                  mode: LaunchMode.externalApplication),
            ),
            const SizedBox(height: 10),
            NavListRow(
              title: 'Aggiungi ad Apple Calendar',
              subtitle: 'Apre il link webcal',
              icon: Icons.event_rounded,
              accent: Palette.violet,
              onTap: () => launchUrl(Uri.parse(feed!.webcalUrl),
                  mode: LaunchMode.externalApplication),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: voltPanel(),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Link del feed'),
                  const SizedBox(height: 8),
                  Text(feed!.feedUrl,
                      style: Typo.mono(10.5, FontWeight.w500, Palette.textMid)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: NeonButton(
                          'Copia link',
                          compact: true,
                          filled: false,
                          color: Palette.cyan,
                          onTap: () async {
                            await Clipboard.setData(
                                ClipboardData(text: feed.feedUrl));
                            if (context.mounted) {
                              StatusFlash.show(context,
                                  success: true, message: 'Link copiato');
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: NeonButton(
                          'Rigenera',
                          compact: true,
                          filled: false,
                          color: Palette.crimson,
                          onTap: _rotate,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
