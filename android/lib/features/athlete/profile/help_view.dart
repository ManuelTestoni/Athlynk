import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/theme.dart';

/// Static FAQ + contact — port of iOS `HelpView` (5 hardcoded Q&A + mailto).
class HelpView extends StatefulWidget {
  const HelpView({super.key});

  @override
  State<HelpView> createState() => _HelpViewState();
}

class _HelpViewState extends State<HelpView> {
  int? _open;

  static const _faq = [
    (
      'Come vedo la mia scheda di allenamento?',
      'Apri la tab Allenamento: trovi le schede attive con giorni ed esercizi. Tocca un giorno per i dettagli e avvia la sessione quando ti alleni.'
    ),
    (
      'Come registro quello che mangio?',
      'Se il tuo piano è a macro, apri Nutrizione → Diario di oggi e aggiungi gli alimenti. Se il piano è ad alimenti, trovi i pasti già pronti dal coach.'
    ),
    (
      'Cosa sono i check?',
      'Sono i questionari periodici del tuo coach: peso, misure, foto e domande. Compilarli con costanza aiuta il coach a seguirti al meglio.'
    ),
    (
      'Come contatto il mio coach?',
      'Dalla chat, in Altro → Messaggi. Puoi anche richiedere un appuntamento direttamente dalla conversazione.'
    ),
    (
      'Come gestisco il mio abbonamento?',
      'In Altro → Abbonamento trovi il tuo piano, la scadenza e il portale per gestire pagamento e rinnovo.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        children: [
          const ScreenHeader(eyebrow: 'Guida e supporto', title: 'Aiuto'),
          const Eyebrow('Domande frequenti'),
          for (final (i, qa) in _faq.indexed)
            VoltPanel(
              padding: EdgeInsets.zero,
              child: Pressable(
                onTap: () => setState(() => _open = _open == i ? null : i),
                child: Padding(
                  padding: const EdgeInsets.all(Space.card),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(qa.$1,
                                style: Typo.body(14.5, FontWeight.w700)),
                          ),
                          AnimatedRotation(
                            turns: _open == i ? 0.5 : 0,
                            duration: Motion.snappyDuration,
                            child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: Palette.textLow),
                          ),
                        ],
                      ),
                      AnimatedCrossFade(
                        firstChild: const SizedBox(width: double.infinity),
                        secondChild: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(qa.$2,
                              style: Typo.body(
                                  13.5, FontWeight.w400, Palette.textMid)),
                        ),
                        crossFadeState: _open == i
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        duration: Motion.snappyDuration,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const Eyebrow('Contatti'),
          VoltPanel(
            tint: Palette.violet.withValues(alpha: 0.35),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Serve altro?', style: Typo.display(17)),
                const SizedBox(height: 6),
                Text(
                  'Per domande sul tuo percorso scrivi al tuo coach in chat. Per problemi con l\'app contattaci via email.',
                  style: Typo.body(13.5, FontWeight.w400, Palette.textMid),
                ),
                const SizedBox(height: 12),
                Pressable(
                  onTap: () => launchUrl(
                      Uri.parse('mailto:info@athlynk.app'),
                      mode: LaunchMode.externalApplication),
                  child: Row(
                    children: [
                      Icon(Icons.mail_outline_rounded,
                          size: 16, color: Palette.cyan),
                      const SizedBox(width: 8),
                      Text('info@athlynk.app',
                          style: Typo.body(
                              14, FontWeight.w700, Palette.cyan)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
