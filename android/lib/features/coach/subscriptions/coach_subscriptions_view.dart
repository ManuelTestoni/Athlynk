import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/utils/stripe_web_flow.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/confirm_dialog.dart';
import '../../../design/components/misc.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';

/// Coach revenue hub — port of iOS `CoachSubscriptionsView`: revenue KPIs,
/// plan CRUD, subscriber list, Stripe Connect onboarding banner while the
/// account isn't charges-enabled.
class CoachSubscriptionsView extends ConsumerStatefulWidget {
  const CoachSubscriptionsView({super.key});

  @override
  ConsumerState<CoachSubscriptionsView> createState() =>
      _CoachSubscriptionsViewState();
}

class _CoachSubscriptionsViewState
    extends ConsumerState<CoachSubscriptionsView> {
  CoachSubscriptionsDto? _data;
  CoachConnectStatusResponse? _connect;
  bool _error = false;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    try {
      final results = await Future.wait<Object?>([
        api.coachSubscriptions(),
        api
            .coachConnectStatus()
            .then<Object?>((v) => v)
            .catchError((_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _data = results[0] as CoachSubscriptionsDto;
        _connect = results[1] as CoachConnectStatusResponse?;
        _error = false;
      });
    } catch (_) {
      if (mounted && _data == null) setState(() => _error = true);
    }
  }

  /// Stripe Express onboarding: open the account link, then re-check status
  /// on return (`athlynkcoach://connect-return`).
  Future<void> _startConnect() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      final res = await ref.read(apiClientProvider).coachConnectStart();
      final flavor = ref.read(flavorProvider);
      await StripeWebFlow.run(
        res.accountLinkUrl,
        scheme: flavor.deepLinkScheme,
        successHost: 'connect-return',
        cancelHost: 'connect-refresh',
      );
      await _load();
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Onboarding Stripe non riuscito');
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _openPlanForm({CoachSubscriptionPlanRow? plan}) async {
    await showAppSheet<void>(
      context,
      heightFactor: 0.9,
      builder: (_) => CoachPlanFormSheet(plan: plan, onSaved: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final connectReady = _connect?.stripeConnectChargesEnabled ?? false;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Nuovo piano',
            icon: const Icon(Icons.add_rounded, color: Palette.textHi),
            onPressed: () => _openPlanForm(),
          ),
        ],
      ),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(eyebrow: 'I tuoi incassi', title: 'Abbonamenti'),
          if (_connect != null && !connectReady)
            VoltPanel(
              tint: Palette.amber.withValues(alpha: 0.55),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_rounded,
                          size: 18, color: Palette.goldText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Attiva i pagamenti online',
                            style: Typo.display(17)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    (_connect?.stripeConnectDetailsSubmitted ?? false)
                        ? 'Stripe sta verificando i tuoi dati. Torna qui tra poco.'
                        : 'Collega Stripe per far pagare i tuoi piani direttamente in app.',
                    style: Typo.body(13.5, FontWeight.w400, Palette.textMid),
                  ),
                  const SizedBox(height: 12),
                  NeonButton(
                    'Collega Stripe',
                    compact: true,
                    color: Palette.amber,
                    loading: _connecting,
                    onTap: _startConnect,
                  ),
                ],
              ),
            ),
          if (data == null && !_error)
            const ListCardsSkeleton(count: 3, height: 130)
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else ...[
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    value: data!.monthlyRevenue == null
                        ? '—'
                        : Formatters.price(data.monthlyRevenue!),
                    label: 'Ricavi mese',
                    icon: Icons.payments_rounded,
                    accent: Palette.lime,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    value: '${data.activeCount ?? data.subscriptions.length}',
                    label: 'Abbonati attivi',
                    icon: Icons.workspace_premium_rounded,
                    accent: Palette.amber,
                  ),
                ),
              ],
            ),
            const Eyebrow('I tuoi piani'),
            if (data.plans.isEmpty)
              const EmptyPanel(
                icon: Icons.sell_outlined,
                message: 'Nessun piano in vendita: creane uno con il +.',
              )
            else
              for (final plan in data.plans)
                VoltPanel(
                  onTap: () => _openPlanForm(plan: plan),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child:
                                  Text(plan.name, style: Typo.display(18))),
                          StatusBadge(plan.isActive ? 'Attivo' : 'Sospeso',
                              color: plan.isActive
                                  ? Palette.lime
                                  : Palette.textLow),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          Formatters.price(plan.price,
                              currency: plan.currency),
                          if (plan.billingInterval != null)
                            plan.billingInterval!,
                          if (plan.durationDays != null)
                            '${plan.durationDays} giorni',
                          '${plan.subscribersCount} abbonati',
                        ].join(' · '),
                        style:
                            Typo.mono(10.5, FontWeight.w600, Palette.textMid),
                      ),
                    ],
                  ),
                ),
            const Eyebrow('Abbonati'),
            if (data.subscriptions.isEmpty)
              const EmptyPanel(
                icon: Icons.groups_outlined,
                message: 'Ancora nessun abbonamento attivo.',
              )
            else
              for (final sub in data.subscriptions)
                VoltPanel(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      AvatarView(
                        url: sub.client?.profileImageUrl,
                        name: sub.client?.displayName ?? 'Atleta',
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(sub.client?.displayName ?? 'Atleta',
                                style: Typo.body(14.5, FontWeight.w700)),
                            Text(
                              [
                                if (sub.planName != null) sub.planName!,
                                if (Formatters.parseDate(sub.endDate) != null)
                                  'fino al ${Formatters.mediumDate(Formatters.parseDate(sub.endDate)!)}',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Typo.body(
                                  11.5, FontWeight.w400, Palette.textMid),
                            ),
                          ],
                        ),
                      ),
                      if (sub.price != null)
                        Text(Formatters.price(sub.price!),
                            style: Typo.mono(
                                12, FontWeight.w700, Palette.lime)),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

/// Subscription-plan CRUD — port of iOS `CoachPlanFormView`.
class CoachPlanFormSheet extends ConsumerStatefulWidget {
  const CoachPlanFormSheet({super.key, this.plan, required this.onSaved});

  final CoachSubscriptionPlanRow? plan;
  final VoidCallback onSaved;

  @override
  ConsumerState<CoachPlanFormSheet> createState() =>
      _CoachPlanFormSheetState();
}

class _CoachPlanFormSheetState extends ConsumerState<CoachPlanFormSheet> {
  late final _name = TextEditingController(text: widget.plan?.name ?? '');
  late final _price =
      TextEditingController(text: widget.plan?.price.toString() ?? '');
  late final _description =
      TextEditingController(text: widget.plan?.description ?? '');
  late String _kind = widget.plan?.kind ?? 'subscription';
  late String _interval = widget.plan?.billingInterval ?? 'mensile';
  late int _durationDays = widget.plan?.durationDays ?? 30;
  late bool _isActive = widget.plan?.isActive ?? true;
  bool _saving = false;

  bool get _isSubscription => _kind == 'subscription';

  Future<void> _save() async {
    final price = Formatters.parseDecimal(_price.text);
    if (_name.text.trim().isEmpty || price == null || _saving) {
      StatusFlash.show(context,
          success: false, message: 'Nome e prezzo obbligatori');
      return;
    }
    setState(() => _saving = true);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'price': price,
      'currency': 'EUR',
      'kind': _kind,
      'description': _description.text.trim(),
      'is_active': _isActive,
      if (_isSubscription) 'billing_interval': _interval,
      if (!_isSubscription) 'duration_days': _durationDays,
    };
    try {
      final api = ref.read(apiClientProvider);
      if (widget.plan == null) {
        await api.coachCreateSubscriptionPlan(body);
      } else {
        await api.coachUpdateSubscriptionPlan(widget.plan!.id, body);
      }
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context, rootNavigator: true).pop();
      StatusFlash.show(context, success: true, message: 'Piano salvato');
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        StatusFlash.show(context,
            success: false, message: 'Salvataggio non riuscito');
      }
    }
  }

  Future<void> _delete() async {
    final plan = widget.plan;
    if (plan == null) return;
    final ok = await ConfirmCenter.confirm(
      context,
      ConfirmOptions(
        title: 'Eliminare "${plan.name}"?',
        subtitle: 'Gli abbonamenti già attivi restano validi.',
        icon: Icons.delete_outline_rounded,
        variant: ConfirmVariant.danger,
        confirmLabel: 'Elimina',
      ),
    );
    if (!ok) return;
    try {
      await ref
          .read(apiClientProvider)
          .coachDeleteSubscriptionPlan(plan.id);
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Eliminazione non riuscita');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(
        title: Text(widget.plan == null ? 'Nuovo piano' : 'Modifica piano',
            style: Typo.display(18)),
        actions: [
          if (widget.plan != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Palette.crimson),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.screenH),
        children: [
          TextField(
              controller: _name,
              style: Typo.body(16, FontWeight.w700),
              decoration: const InputDecoration(labelText: 'Nome piano *')),
          const SizedBox(height: 14),
          TextField(
            controller: _price,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: Typo.mono(18, FontWeight.w700),
            decoration: const InputDecoration(
                labelText: 'Prezzo *', suffixText: '€'),
          ),
          const SizedBox(height: 18),
          const Eyebrow('Tipo'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final (v, l) in const [
                ('subscription', 'Abbonamento'),
                ('one_time', 'Una tantum'),
              ])
                ChoiceChip(
                  label: Text(l, style: Typo.body(13, FontWeight.w600)),
                  selected: _kind == v,
                  selectedColor: Palette.amber.withValues(alpha: 0.2),
                  onSelected: (_) => setState(() => _kind = v),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (_isSubscription) ...[
            const Eyebrow('Fatturazione'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (v, l) in const [
                  ('mensile', 'Mensile'),
                  ('annuale', 'Annuale'),
                ])
                  ChoiceChip(
                    label: Text(l, style: Typo.body(13, FontWeight.w600)),
                    selected: _interval == v,
                    selectedColor: Palette.amber.withValues(alpha: 0.2),
                    onSelected: (_) => setState(() => _interval = v),
                  ),
              ],
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: Text('Durata: $_durationDays giorni',
                      style: Typo.body(14, FontWeight.w600)),
                ),
                Expanded(
                  child: Slider(
                    value: _durationDays.toDouble(),
                    min: 7,
                    max: 365,
                    divisions: 51,
                    activeColor: Palette.amber,
                    onChanged: (v) =>
                        setState(() => _durationDays = v.round()),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _description,
            maxLines: 3,
            style: Typo.body(14, FontWeight.w400),
            decoration:
                const InputDecoration(labelText: 'Descrizione / servizi'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Piano attivo',
                style: Typo.body(14.5, FontWeight.w600)),
            subtitle: Text('Visibile ai tuoi atleti in app',
                style: Typo.body(12, FontWeight.w400, Palette.textLow)),
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
          ),
          const SizedBox(height: 20),
          NeonButton('Salva',
              color: Palette.amber, loading: _saving, onTap: _save),
        ],
      ),
    );
  }
}
