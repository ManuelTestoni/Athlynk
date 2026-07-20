import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/api/coach_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/image_compressor.dart';
import '../../../core/utils/stripe_web_flow.dart';
import '../../../design/components/avatar.dart';
import '../../../design/components/brand_settings_view.dart';
import '../../../design/components/calendar_feed_view.dart';
import '../../../design/components/confirm_dialog.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/sheets.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';
import '../messages/coach_messages_view.dart';

/// Coach profile & settings — port of iOS `CoachProfileView`: bio, contatti,
/// social, notifiche email, abbonamento piattaforma Athlynk (billing portal),
/// messaggi automatici, aspetto, calendario, sicurezza, logout/delete.
class CoachProfileView extends ConsumerStatefulWidget {
  const CoachProfileView({super.key});

  @override
  ConsumerState<CoachProfileView> createState() => _CoachProfileViewState();
}

class _CoachProfileViewState extends ConsumerState<CoachProfileView> {
  CoachProfileDto? _profile;
  SettingsDto? _settings;
  bool _error = false;
  bool _openingPortal = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    try {
      final results = await Future.wait<Object?>([
        api.coachProfile(),
        api.settings().then<Object?>((v) => v).catchError((_) => null),
      ]);
      if (mounted) {
        setState(() {
          _profile = results[0] as CoachProfileDto;
          _settings = results[1] as SettingsDto?;
        });
      }
    } catch (_) {
      if (mounted && _profile == null) setState(() => _error = true);
    }
  }

  Future<void> _openBillingPortal() async {
    if (_openingPortal) return;
    setState(() => _openingPortal = true);
    try {
      final url = await ref.read(apiClientProvider).coachBillingPortal();
      await StripeWebFlow.open(url);
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Impossibile aprire il portale');
      }
    } finally {
      if (mounted) setState(() => _openingPortal = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = ref.read(sessionControllerProvider).user?.email;
    if (email == null) return;
    final ok = await ConfirmCenter.confirm(
      context,
      ConfirmOptions(
        title: 'Reimposta password',
        subtitle: 'Invieremo un link di reset a $email.',
        icon: Icons.lock_reset_rounded,
        confirmLabel: 'Invia link',
      ),
    );
    if (!ok) return;
    try {
      await ref.read(apiClientProvider).forgotPassword(email);
      if (mounted) {
        StatusFlash.show(context,
            success: true, message: 'Link inviato via email');
      }
    } on ApiException {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Invio non riuscito');
      }
    }
  }

  Future<void> _logout() async {
    final ok = await ConfirmCenter.confirm(
      context,
      const ConfirmOptions(
        title: 'Uscire dal profilo?',
        icon: Icons.logout_rounded,
        confirmLabel: 'Esci',
      ),
    );
    if (ok) await ref.read(sessionControllerProvider.notifier).logout();
  }

  Future<void> _deleteAccount() async {
    final ok = await ConfirmCenter.confirm(
      context,
      const ConfirmOptions(
        title: 'Eliminare il tuo account?',
        subtitle:
            'Atleti, piani e dati verranno cancellati per sempre. Azione irreversibile.',
        icon: Icons.delete_forever_rounded,
        variant: ConfirmVariant.danger,
        confirmLabel: 'Elimina definitivamente',
      ),
    );
    if (ok) {
      await ref.read(sessionControllerProvider.notifier).deleteAccount();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final p = _profile;
    final settings = _settings;
    final purchase = p?.platformPurchase;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        actions: [
          if (p != null)
            IconButton(
              tooltip: 'Modifica',
              icon: Icon(Icons.edit_outlined, color: Palette.bronze),
              onPressed: () async {
                await showAppSheet<void>(context,
                    builder: (_) => _EditCoachProfileSheet(profile: p));
                _load();
              },
            ),
        ],
      ),
      body: p == null
          ? Padding(
              padding: const EdgeInsets.all(Space.screenH),
              child: _error
                  ? EmptyPanel.network(onCta: () {
                      setState(() => _error = false);
                      _load();
                    })
                  : const FormSkeleton(),
            )
          : ScreenScroll(
              topPadding: 0,
              spacing: Space.element,
              onRefresh: _load,
              children: [
                Center(
                  child: Column(
                    children: [
                      AvatarView(
                        url: session.avatarUrl ?? p.profileImageUrl,
                        name: p.fullName,
                        size: 84,
                      ),
                      const SizedBox(height: 12),
                      Text(p.fullName, style: Typo.poster(30)),
                      const SizedBox(height: 4),
                      StatusBadge(p.roleLabel, color: Palette.bronze),
                    ],
                  ),
                ),
                if ((p.bio ?? '').isNotEmpty)
                  VoltPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('Bio'),
                        const SizedBox(height: 6),
                        Text(p.bio!,
                            style: Typo.body(14, FontWeight.w400)),
                      ],
                    ),
                  ),
                VoltPanel(
                  child: Column(
                    children: [
                      _row(Icons.alternate_email_rounded, 'Email',
                          p.email ?? session.user?.email ?? '—'),
                      const Divider(height: 20),
                      _row(Icons.phone_outlined, 'Telefono', p.phone ?? '—'),
                      const Divider(height: 20),
                      _row(Icons.place_outlined, 'Città', p.city ?? '—'),
                      const Divider(height: 20),
                      _row(Icons.workspace_premium_outlined,
                          'Specializzazione', p.specialization ?? '—'),
                      const Divider(height: 20),
                      _row(Icons.timeline_rounded, 'Esperienza',
                          p.yearsExperience == null
                              ? '—'
                              : '${p.yearsExperience} anni'),
                    ],
                  ),
                ),
                if ((p.certifications ?? '').isNotEmpty)
                  VoltPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('Certificazioni'),
                        const SizedBox(height: 6),
                        Text(p.certifications!,
                            style: Typo.body(13.5, FontWeight.w400,
                                Palette.textMid)),
                      ],
                    ),
                  ),
                if ([p.socialInstagram, p.socialYoutube, p.socialTiktok,
                        p.socialWebsite]
                    .any((s) => (s ?? '').isNotEmpty))
                  VoltPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('Social'),
                        const SizedBox(height: 8),
                        for (final (icon, url) in [
                          (Icons.camera_alt_outlined, p.socialInstagram),
                          (Icons.play_circle_outline, p.socialYoutube),
                          (Icons.music_note_outlined, p.socialTiktok),
                          (Icons.language_rounded, p.socialWebsite),
                        ])
                          if ((url ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: InkWell(
                                onTap: () => launchUrl(Uri.parse(url),
                                    mode: LaunchMode.externalApplication),
                                child: Row(
                                  children: [
                                    Icon(icon,
                                        size: 15, color: Palette.cyan),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(url!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Typo.body(13,
                                              FontWeight.w600, Palette.cyan)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                if (purchase != null)
                  VoltPanel(
                    tint: Palette.amber.withValues(alpha: 0.4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                  'Athlynk ${_planLabel(purchase.plan)}',
                                  style: Typo.display(18)),
                            ),
                            StatusBadge(
                              purchase.status.toUpperCase() == 'ACTIVE'
                                  ? 'Attivo'
                                  : purchase.status,
                              color:
                                  purchase.status.toUpperCase() == 'ACTIVE'
                                      ? Palette.lime
                                      : Palette.amber,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (purchase.billingInterval != null)
                              purchase.billingInterval!,
                            if (Formatters.parseDate(
                                    purchase.currentPeriodEnd) !=
                                null)
                              'rinnovo ${Formatters.mediumDate(Formatters.parseDate(purchase.currentPeriodEnd)!)}',
                          ].join(' · '),
                          style: Typo.mono(
                              10.5, FontWeight.w600, Palette.textMid),
                        ),
                        const SizedBox(height: 12),
                        NeonButton(
                          'Gestisci abbonamento',
                          compact: true,
                          filled: false,
                          color: Palette.amber,
                          loading: _openingPortal,
                          onTap: _openBillingPortal,
                        ),
                      ],
                    ),
                  ),
                if (settings != null && settings.notifications.isNotEmpty)
                  VoltPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('Notifiche email'),
                        const SizedBox(height: 4),
                        for (final toggle in settings.notifications)
                          SettingsToggleRow(
                            title: toggle.label,
                            subtitle:
                                toggle.desc.isEmpty ? null : toggle.desc,
                            value: toggle.enabled,
                            onChanged: (v) async {
                              try {
                                await ref
                                    .read(apiClientProvider)
                                    .updateSetting(toggle.key, v);
                              } catch (_) {}
                            },
                          ),
                      ],
                    ),
                  ),
                const Eyebrow('Account'),
                NavListRow(
                  title: 'Messaggi automatici',
                  subtitle: 'Risposte pronte per gli eventi chiave',
                  icon: Icons.mark_email_read_outlined,
                  accent: Palette.violet,
                  onTap: () => showAppSheet<void>(context,
                      builder: (_) => const CoachAutoMessagesView()),
                ),
                NavListRow(
                  title: 'Aspetto',
                  subtitle: 'Colori e brand dei tuoi atleti',
                  icon: Icons.palette_outlined,
                  accent: Palette.bronze,
                  onTap: () async {
                    await showAppSheet<void>(
                      context,
                      builder: (_) => BrandSettingsView(
                        initialName: p.brandName,
                        initialPrimary: p.brandPrimary,
                        initialAccent: p.brandAccent,
                      ),
                    );
                    _load();
                  },
                ),
                NavListRow(
                  title: 'Calendario',
                  subtitle: 'Sincronizza la tua agenda',
                  icon: Icons.event_repeat_rounded,
                  accent: Palette.cyan,
                  onTap: () => showAppSheet<void>(
                    context,
                    builder: (_) => CalendarFeedView(
                      load: ref.read(apiClientProvider).coachCalendarFeed,
                      rotate: ref
                          .read(apiClientProvider)
                          .coachRotateCalendarFeed,
                    ),
                  ),
                ),
                NavListRow(
                  title: 'Sicurezza',
                  subtitle: 'Reimposta la password',
                  icon: Icons.lock_outline_rounded,
                  accent: Palette.violet,
                  onTap: _resetPassword,
                ),
                const Eyebrow('Documenti'),
                const LegalLinks(),
                const SizedBox(height: 6),
                NeonButton('Esci',
                    filled: false, color: Palette.textMid, onTap: _logout),
                NeonButton('Elimina account',
                    filled: false,
                    color: Palette.crimson,
                    onTap: _deleteAccount),
              ],
            ),
    );
  }

  String _planLabel(String plan) => switch (plan.toLowerCase()) {
        'athena' => 'Athena',
        'apollo' => 'Apollo',
        'zeus' => 'Zeus',
        _ => plan,
      };

  Widget _row(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 17, color: Palette.textMid),
        const SizedBox(width: 10),
        Expanded(
            child: Text(label,
                style: Typo.body(14, FontWeight.w500, Palette.textMid))),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Typo.body(14, FontWeight.w700)),
        ),
      ],
    );
  }
}

class _EditCoachProfileSheet extends ConsumerStatefulWidget {
  const _EditCoachProfileSheet({required this.profile});

  final CoachProfileDto profile;

  @override
  ConsumerState<_EditCoachProfileSheet> createState() =>
      _EditCoachProfileSheetState();
}

class _EditCoachProfileSheetState
    extends ConsumerState<_EditCoachProfileSheet> {
  late final _first = TextEditingController(text: widget.profile.firstName);
  late final _last = TextEditingController(text: widget.profile.lastName);
  late final _phone =
      TextEditingController(text: widget.profile.phone ?? '');
  late final _city = TextEditingController(text: widget.profile.city ?? '');
  late final _bio = TextEditingController(text: widget.profile.bio ?? '');
  late final _spec =
      TextEditingController(text: widget.profile.specialization ?? '');
  late final _certs =
      TextEditingController(text: widget.profile.certifications ?? '');
  late final _instagram =
      TextEditingController(text: widget.profile.socialInstagram ?? '');
  late final _website =
      TextEditingController(text: widget.profile.socialWebsite ?? '');
  bool _saving = false;
  bool _uploading = false;

  Future<void> _pickAvatar() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final jpeg = await ImageCompressor.jpeg(bytes, maxDim: 1200);
      final url = await ref.read(apiClientProvider).uploadCoachPhoto(jpeg);
      ref.read(sessionControllerProvider.notifier).setAvatarUrl(url);
      if (mounted) {
        StatusFlash.show(context, success: true, message: 'Foto aggiornata');
      }
    } on ApiException {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Caricamento non riuscito');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).coachUpdateProfile({
        'first_name': _first.text.trim(),
        'last_name': _last.text.trim(),
        'phone': _phone.text.trim(),
        'city': _city.text.trim(),
        'bio': _bio.text.trim(),
        'specialization': _spec.text.trim(),
        'certifications': _certs.text.trim(),
        'social_instagram': _instagram.text.trim(),
        'social_website': _website.text.trim(),
      });
      if (mounted) Navigator.of(context).pop();
    } on ApiException {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Salvataggio non riuscito');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar:
          AppBar(title: Text('Modifica profilo', style: Typo.display(18))),
      body: ListView(
        padding: const EdgeInsets.all(Space.screenH),
        children: [
          Center(
            child: Stack(
              children: [
                AvatarView(
                  url: session.avatarUrl ?? widget.profile.profileImageUrl,
                  name: '${_first.text} ${_last.text}'.trim(),
                  size: 90,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: _uploading ? null : _pickAvatar,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                          color: Palette.bronze, shape: BoxShape.circle),
                      child: _uploading
                          ? const Padding(
                              padding: EdgeInsets.all(7),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Palette.void0),
                            )
                          : const Icon(Icons.photo_camera_rounded,
                              size: 15, color: Palette.void0),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextField(
              controller: _first,
              style: Typo.body(15, FontWeight.w600),
              decoration: const InputDecoration(labelText: 'Nome')),
          const SizedBox(height: 12),
          TextField(
              controller: _last,
              style: Typo.body(15, FontWeight.w600),
              decoration: const InputDecoration(labelText: 'Cognome')),
          const SizedBox(height: 12),
          TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              style: Typo.body(15, FontWeight.w600),
              decoration: const InputDecoration(labelText: 'Telefono')),
          const SizedBox(height: 12),
          TextField(
              controller: _city,
              style: Typo.body(15, FontWeight.w600),
              decoration: const InputDecoration(labelText: 'Città')),
          const SizedBox(height: 12),
          TextField(
              controller: _spec,
              style: Typo.body(15, FontWeight.w600),
              decoration:
                  const InputDecoration(labelText: 'Specializzazione')),
          const SizedBox(height: 12),
          TextField(
              controller: _bio,
              maxLines: 4,
              style: Typo.body(14, FontWeight.w400),
              decoration: const InputDecoration(labelText: 'Bio')),
          const SizedBox(height: 12),
          TextField(
              controller: _certs,
              maxLines: 3,
              style: Typo.body(14, FontWeight.w400),
              decoration:
                  const InputDecoration(labelText: 'Certificazioni')),
          const SizedBox(height: 12),
          TextField(
              controller: _instagram,
              style: Typo.body(14, FontWeight.w500),
              decoration: const InputDecoration(labelText: 'Instagram')),
          const SizedBox(height: 12),
          TextField(
              controller: _website,
              style: Typo.body(14, FontWeight.w500),
              decoration: const InputDecoration(labelText: 'Sito web')),
          const SizedBox(height: 26),
          NeonButton('Salva',
              color: Palette.bronze, loading: _saving, onTap: _save),
        ],
      ),
    );
  }
}
