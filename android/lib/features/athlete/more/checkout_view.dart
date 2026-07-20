import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/utils/stripe_web_flow.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/particle_burst.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/theme.dart';

/// Checkout — port of iOS `CheckoutView`: order summary → hosted Stripe
/// Checkout in a Custom Tab → the `athlynk://checkout-return` callback is
/// only a UX signal (fulfillment is server-side via webhook).
class CheckoutView extends ConsumerStatefulWidget {
  const CheckoutView({super.key, required this.plan});

  final SubscriptionPlanDto plan;

  @override
  ConsumerState<CheckoutView> createState() => _CheckoutViewState();
}

class _CheckoutViewState extends ConsumerState<CheckoutView> {
  bool _paying = false;
  String? _error;

  Future<void> _pay() async {
    if (_paying) return;
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      final url =
          await ref.read(apiClientProvider).checkoutStart(widget.plan.id);
      final flavor = ref.read(flavorProvider);
      final result =
          await StripeWebFlow.run(url, scheme: flavor.deepLinkScheme);
      if (!mounted) return;
      switch (result) {
        case StripeFlowResult.success:
          await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const CheckoutSuccessView()));
          if (mounted) Navigator.of(context).pop();
        case StripeFlowResult.cancelled:
          setState(() => _error = S.paymentCancelled);
        case StripeFlowResult.dismissed:
          break; // user closed the tab silently, like iOS canceledLogin
      }
    } catch (_) {
      if (mounted) setState(() => _error = S.paymentFailed);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        children: [
          const ScreenHeader(eyebrow: 'Riepilogo ordine', title: 'Checkout'),
          VoltPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.name, style: Typo.display(20)),
                if (plan.coach != null)
                  Text('di ${plan.coach!.fullName}',
                      style:
                          Typo.body(13, FontWeight.w400, Palette.textMid)),
                const Divider(height: 26),
                Row(
                  children: [
                    Expanded(
                      child: Text('Totale',
                          style: Typo.body(15, FontWeight.w600)),
                    ),
                    Text(
                        Formatters.price(plan.price,
                            currency: plan.currency),
                        style: Typo.poster(26)),
                  ],
                ),
              ],
            ),
          ),
          if (_error != null)
            Text(_error!,
                style: Typo.body(13.5, FontWeight.w600, Palette.crimson)),
          NeonButton(
            'Conferma e paga',
            loading: _paying,
            color: Palette.amber,
            onTap: _pay,
          ),
          Text(
            'Il pagamento avviene su Stripe, in modo sicuro. Tornerai qui a operazione conclusa.',
            textAlign: TextAlign.center,
            style: Typo.body(12, FontWeight.w400, Palette.textLow),
          ),
        ],
      ),
    );
  }
}

/// "PAGAMENTO RIUSCITO" — port of iOS `CheckoutSuccessView`.
class CheckoutSuccessView extends StatefulWidget {
  const CheckoutSuccessView({super.key});

  @override
  State<CheckoutSuccessView> createState() => _CheckoutSuccessViewState();
}

class _CheckoutSuccessViewState extends State<CheckoutSuccessView> {
  int _burst = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _burst = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void0,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            children: [
              const Spacer(),
              Stack(
                alignment: Alignment.center,
                children: [
                  ParticleBurst(trigger: _burst),
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Palette.lime.withValues(alpha: 0.12),
                      border: Border.all(
                          color: Palette.lime.withValues(alpha: 0.5)),
                    ),
                    child: const Icon(Icons.verified_rounded,
                        size: 42, color: Palette.lime),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              const Eyebrow('Pagamento riuscito'),
              const SizedBox(height: 8),
              Text('Benvenuto a bordo',
                  textAlign: TextAlign.center, style: Typo.poster(36)),
              const SizedBox(height: 10),
              Text(
                "L'abbonamento sarà attivo tra pochi istanti. Il tuo coach è stato avvisato.",
                textAlign: TextAlign.center,
                style: Typo.body(14.5, FontWeight.w400, Palette.textMid),
              ),
              const Spacer(),
              NeonButton('Fatto',
                  onTap: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }
}
