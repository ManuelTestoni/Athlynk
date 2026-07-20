import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';
import 'checkout_view.dart';

/// "Piani e prezzi" — port of iOS `PricingView`: the coach's plans on offer;
/// featured badge on the first, "Scegli" only when online-purchasable.
class PricingView extends ConsumerStatefulWidget {
  const PricingView({super.key});

  @override
  ConsumerState<PricingView> createState() => _PricingViewState();
}

class _PricingViewState extends ConsumerState<PricingView> {
  List<SubscriptionPlanDto>? _plans;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final plans = await ref.read(apiClientProvider).plans();
      if (mounted) setState(() => _plans = plans);
    } catch (_) {
      if (mounted && _plans == null) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = _plans;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(eyebrow: 'Offerta del coach', title: 'Piani e prezzi'),
          if (plans == null && !_error)
            const ListCardsSkeleton(count: 3, height: 190)
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (plans!.isEmpty)
            const EmptyPanel(
              icon: Icons.sell_outlined,
              message: 'Il tuo coach non ha ancora piani in vendita.',
            )
          else
            for (final (i, plan) in plans.indexed) _planCard(plan, featured: i == 0),
        ],
      ),
    );
  }

  Widget _planCard(SubscriptionPlanDto plan, {required bool featured}) {
    final interval = switch (plan.billingInterval?.toLowerCase()) {
      'mensile' || 'month' || 'monthly' => '/mese',
      'annuale' || 'year' || 'yearly' => '/anno',
      _ => plan.durationDays != null ? ' · ${plan.durationDays} giorni' : '',
    };
    return VoltPanel(
      tint: featured
          ? Palette.amber.withValues(alpha: 0.5)
          : Palette.line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(plan.name, style: Typo.display(20))),
              if (featured) const StatusBadge('Consigliato', color: Palette.amber),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Formatters.price(plan.price, currency: plan.currency),
                  style: Typo.poster(30)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(interval,
                    style: Typo.mono(11, FontWeight.w600, Palette.textMid)),
              ),
            ],
          ),
          if ((plan.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(plan.description!,
                style: Typo.body(13.5, FontWeight.w400, Palette.textMid)),
          ],
          if (plan.includedServices.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final s in plan.includedServices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.check_rounded,
                        size: 14, color: Palette.lime),
                    const SizedBox(width: 8),
                    Expanded(
                        child:
                            Text(s, style: Typo.body(13.5, FontWeight.w500))),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 14),
          if (plan.isOnlinePurchasable)
            NeonButton(
              'Scegli',
              compact: true,
              color: featured ? Palette.amber : Palette.magenta,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => CheckoutView(plan: plan))),
            )
          else
            Text('Contatta il coach per attivarlo.',
                style: Typo.body(13, FontWeight.w600, Palette.textMid)),
        ],
      ),
    );
  }
}
