import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../design/components/neon_button.dart';
import '../../design/components/scaffold.dart';
import '../../design/components/volt_background.dart';
import '../../design/theme.dart';

/// Blocking legal gate — port of iOS `TermsConsentView` (`fullScreenCover`
/// with `interactiveDismissDisabled`): shown until `POST /accept-terms`
/// succeeds. Back gesture is swallowed.
class TermsConsentView extends ConsumerStatefulWidget {
  const TermsConsentView({super.key});

  @override
  ConsumerState<TermsConsentView> createState() => _TermsConsentViewState();
}

class _TermsConsentViewState extends ConsumerState<TermsConsentView> {
  bool _accepting = false;
  bool _failed = false;

  Future<void> _accept() async {
    setState(() {
      _accepting = true;
      _failed = false;
    });
    final ok =
        await ref.read(sessionControllerProvider.notifier).acceptTerms();
    if (!mounted) return;
    setState(() {
      _accepting = false;
      _failed = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const VoltBackground(
                palette: [Palette.violet, Palette.defaultPrimary]),
            SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: Space.screenH),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    const Icon(Icons.verified_user_outlined,
                        size: 40, color: Palette.amber),
                    const SizedBox(height: 18),
                    Text('Termini e Privacy',
                        textAlign: TextAlign.center, style: Typo.poster(36)),
                    const SizedBox(height: 12),
                    Text(
                      'Per continuare devi accettare i Termini di Servizio e la Privacy Policy di Athlynk.',
                      textAlign: TextAlign.center,
                      style: Typo.body(15, FontWeight.w400, Palette.textMid),
                    ),
                    const SizedBox(height: 26),
                    const Expanded(
                      child: SingleChildScrollView(child: LegalLinks()),
                    ),
                    if (_failed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          'Si è verificato un errore. Riprova.',
                          textAlign: TextAlign.center,
                          style:
                              Typo.body(13, FontWeight.w600, Palette.crimson),
                        ),
                      ),
                    NeonButton(
                      'Accetto e continuo',
                      loading: _accepting,
                      onTap: _accept,
                    ),
                    const SizedBox(height: 26),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
