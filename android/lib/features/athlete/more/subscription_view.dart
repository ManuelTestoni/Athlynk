import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/utils/stripe_web_flow.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';
import 'pricing_view.dart';

/// "Il mio abbonamento" — port of iOS `SubscriptionView`: active
/// subscription(s), Stripe Billing Portal, link to plans on offer.
class SubscriptionView extends ConsumerStatefulWidget {
  const SubscriptionView({super.key});

  @override
  ConsumerState<SubscriptionView> createState() => _SubscriptionViewState();
}

class _SubscriptionViewState extends ConsumerState<SubscriptionView> {
  List<SubscriptionDto>? _subs;
  bool _error = false;
  bool _openingPortal = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final subs = await ref.read(apiClientProvider).subscription();
      if (mounted) setState(() => _subs = subs);
    } catch (_) {
      if (mounted && _subs == null) setState(() => _error = true);
    }
  }

  Future<void> _openPortal(SubscriptionDto sub) async {
    if (_openingPortal) return;
    setState(() => _openingPortal = true);
    try {
      final url = await ref
          .read(apiClientProvider)
          .subscriptionBillingPortal(sub.id);
      await StripeWebFlow.open(url);
      await _load();
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Impossibile aprire il portale');
      }
    } finally {
      if (mounted) setState(() => _openingPortal = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subs = _subs;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(eyebrow: 'Il tuo piano', title: 'Abbonamento'),
          if (subs == null && !_error)
            const ListCardsSkeleton(count: 2, height: 200)
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (subs!.isEmpty)
            const EmptyPanel(
              icon: Icons.workspace_premium_outlined,
              message:
                  'Nessun abbonamento attivo. Scopri i piani del tuo coach.',
            )
          else
            for (final sub in subs) _subCard(sub),
          NavListRow(
            title: 'Piani e prezzi',
            subtitle: 'I piani offerti dal tuo coach',
            icon: Icons.sell_rounded,
            accent: Palette.amber,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const PricingView())),
          ),
        ],
      ),
    );
  }

  Widget _subCard(SubscriptionDto sub) {
    final active = sub.status.toUpperCase() == 'ACTIVE';
    final start = Formatters.parseDate(sub.startDate);
    final end = Formatters.parseDate(sub.endDate);
    return VoltPanel(
      tint: Palette.amber.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(sub.plan.name, style: Typo.display(21))),
              StatusBadge(
                active ? 'Attivo' : sub.status,
                color: active ? Palette.lime : Palette.textLow,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            Formatters.price(sub.plan.price, currency: sub.plan.currency),
            style: Typo.poster(30),
          ),
          if ((sub.plan.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(sub.plan.description!,
                style: Typo.body(13.5, FontWeight.w400, Palette.textMid)),
          ],
          const SizedBox(height: 14),
          _row('Inizio', start == null ? '—' : Formatters.mediumDate(start)),
          _row('Scadenza', end == null ? '—' : Formatters.mediumDate(end)),
          _row('Pagamento', sub.paymentStatus ?? '—'),
          _row('Rinnovo automatico', sub.autoRenew ? 'Sì' : 'No'),
          if (sub.plan.includedServices.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Eyebrow('Servizi inclusi'),
            const SizedBox(height: 8),
            for (final s in sub.plan.includedServices)
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
          if (sub.manageable) ...[
            const SizedBox(height: 14),
            NeonButton(
              'Gestisci abbonamento',
              compact: true,
              filled: false,
              color: Palette.amber,
              loading: _openingPortal,
              onTap: () => _openPortal(sub),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: Typo.body(13.5, FontWeight.w500, Palette.textMid))),
          Text(value, style: Typo.body(13.5, FontWeight.w700)),
        ],
      ),
    );
  }
}
