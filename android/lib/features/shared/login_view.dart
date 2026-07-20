import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../design/components/misc.dart';
import '../../design/components/neon_button.dart';
import '../../design/components/panel.dart';
import '../../design/components/volt_background.dart';
import '../../design/components/volt_field.dart';
import '../../design/theme.dart';
import 'forgot_password_view.dart';

/// Email/password login — port of iOS `LoginView`/`CoachLoginView` (the role
/// is hardcoded per flavor by the session controller). Shows the connected
/// backend URL in the footer for debugging, like iOS.
class LoginView extends ConsumerStatefulWidget {
  const LoginView({super.key});

  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await ref
        .read(sessionControllerProvider.notifier)
        .login(_email.text, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final flavor = ref.watch(flavorProvider);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const VoltBackground(palette: [
            Palette.defaultPrimary,
            Palette.violet,
            Palette.defaultAccent,
          ]),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: Space.screenH),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 30),
                      const Center(
                        child: Icon(Icons.account_balance_rounded,
                            size: 34, color: Palette.amber),
                      ),
                      const SizedBox(height: 12),
                      const Center(child: GlitchText('ATHLYNK', size: 44)),
                      if (flavor == AppFlavor.coach)
                        Center(
                          child: Text(
                            'COACH',
                            style: Typo.mono(
                                    12, FontWeight.w700, Palette.textMid)
                                .copyWith(letterSpacing: 6),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Accedi al tuo percorso.',
                          style:
                              Typo.body(15, FontWeight.w400, Palette.textMid),
                        ),
                      ),
                      const SizedBox(height: 34),
                      const Eyebrow('Accesso'),
                      const SizedBox(height: 10),
                      VoltField(
                        hint: S.email,
                        icon: Icons.alternate_email_rounded,
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                      ),
                      const SizedBox(height: Space.element),
                      VoltField(
                        hint: S.password,
                        icon: Icons.lock_outline_rounded,
                        controller: _password,
                        secure: true,
                        textInputAction: TextInputAction.go,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _submit(),
                      ),
                      if (session.loginError != null) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                size: 15, color: Palette.crimson),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                session.loginError!,
                                style: Typo.body(
                                    13, FontWeight.w600, Palette.crimson),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 22),
                      NeonButton(
                        S.login,
                        loading: session.isAuthenticating,
                        onTap: _submit,
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).push(MaterialPageRoute<void>(
                              fullscreenDialog: true,
                              builder: (_) => const ForgotPasswordView(),
                            ));
                          },
                          child: Text(
                            S.forgotPassword,
                            style:
                                Typo.body(14, FontWeight.w600, Palette.cyan),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      Center(
                        child: Text(
                          AppConfig.apiBaseUrl,
                          style: Typo.mono(
                              9, FontWeight.w500, Palette.textLow),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
