import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/athlete_api.dart';
import '../../core/l10n/strings.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../design/components/neon_button.dart';
import '../../design/components/panel.dart';
import '../../design/components/volt_background.dart';
import '../../design/components/volt_field.dart';
import '../../design/theme.dart';

/// Password-reset request — port of iOS `ForgotPasswordView`. The reset link
/// completes in the browser (web page), not in-app.
class ForgotPasswordView extends ConsumerStatefulWidget {
  const ForgotPasswordView({super.key});

  @override
  ConsumerState<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends ConsumerState<ForgotPasswordView> {
  final _email = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).forgotPassword(_email.text.trim());
      setState(() => _sent = true);
    } on ApiException catch (e) {
      setState(() => _error = e.userMessage);
    } finally {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const VoltBackground(
              palette: [Palette.violet, Palette.defaultAccent]),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: Space.screenH),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 30),
                  const Eyebrow('Recupero accesso'),
                  const SizedBox(height: 8),
                  Text('Password dimenticata', style: Typo.poster(38)),
                  const SizedBox(height: 10),
                  Text(
                    "Inserisci la tua email: ti invieremo un link per reimpostare la password.",
                    style: Typo.body(14.5, FontWeight.w400, Palette.textMid),
                  ),
                  const SizedBox(height: 26),
                  if (_sent)
                    VoltPanel(
                      tint: Palette.lime.withValues(alpha: 0.4),
                      child: Row(
                        children: [
                          const Icon(Icons.mark_email_read_outlined,
                              color: Palette.lime),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              S.forgotPasswordSent,
                              style: Typo.body(14, FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    VoltField(
                      hint: S.email,
                      icon: Icons.alternate_email_rounded,
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style:
                              Typo.body(13, FontWeight.w600, Palette.crimson)),
                    ],
                    const SizedBox(height: 20),
                    NeonButton('Invia link', loading: _sending, onTap: _submit),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
