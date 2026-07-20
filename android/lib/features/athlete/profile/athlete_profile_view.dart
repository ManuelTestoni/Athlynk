import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/image_compressor.dart';
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

/// Profile & settings hub — port of iOS `AthleteProfileView`: identity
/// header, contact details, email-notification toggles, legal links, account
/// actions (Aspetto / Calendario / reset password / logout / delete).
class AthleteProfileView extends ConsumerStatefulWidget {
  const AthleteProfileView({super.key});

  @override
  ConsumerState<AthleteProfileView> createState() =>
      _AthleteProfileViewState();
}

class _AthleteProfileViewState extends ConsumerState<AthleteProfileView> {
  ClientProfileDto? _profile;
  SettingsDto? _settings;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    try {
      final results = await Future.wait<Object?>([
        api.profile(),
        api.settings().then<Object?>((v) => v).catchError((_) => null),
      ]);
      if (mounted) {
        setState(() {
          _profile = results[0] as ClientProfileDto;
          _settings = results[1] as SettingsDto?;
        });
      }
    } catch (_) {
      if (mounted && _profile == null) setState(() => _error = true);
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
            'Tutti i tuoi dati verranno cancellati per sempre. Questa azione non si può annullare.',
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
    final profile = _profile;
    final settings = _settings;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        actions: [
          if (profile != null)
            IconButton(
              tooltip: 'Modifica',
              icon: Icon(Icons.edit_outlined, color: Palette.cyan),
              onPressed: () async {
                await showAppSheet<void>(context,
                    builder: (_) => _EditProfileSheet(profile: profile));
                _load();
              },
            ),
        ],
      ),
      body: profile == null
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
                        url: session.avatarUrl ?? profile.profileImageUrl,
                        name:
                            '${profile.firstName} ${profile.lastName}'.trim(),
                        size: 84,
                      ),
                      const SizedBox(height: 12),
                      Text('${profile.firstName} ${profile.lastName}'.trim(),
                          style: Typo.poster(30)),
                      const SizedBox(height: 4),
                      StatusBadge('Atleta', color: Palette.cyan),
                    ],
                  ),
                ),
                VoltPanel(
                  child: Column(
                    children: [
                      _row(Icons.alternate_email_rounded, 'Email',
                          session.user?.email ?? '—'),
                      const Divider(height: 20),
                      _row(Icons.phone_outlined, 'Telefono',
                          profile.phone ?? '—'),
                      const Divider(height: 20),
                      _row(Icons.monitor_weight_outlined, 'Peso',
                          profile.weightKg == null
                              ? '—'
                              : '${profile.weightKg} kg'),
                      const Divider(height: 20),
                      _row(Icons.sports_martial_arts_rounded, 'Sport',
                          profile.sport ?? '—'),
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
                  title: 'Aspetto',
                  subtitle: 'Colori e brand',
                  icon: Icons.palette_outlined,
                  accent: Palette.magenta,
                  onTap: () async {
                    await showAppSheet<void>(
                      context,
                      builder: (_) => BrandSettingsView(
                        initialName: profile.brandName,
                        initialPrimary: profile.brandPrimary,
                        initialAccent: profile.brandAccent,
                      ),
                    );
                    _load();
                  },
                ),
                NavListRow(
                  title: 'Calendario',
                  subtitle: 'Sincronizza i tuoi appuntamenti',
                  icon: Icons.event_repeat_rounded,
                  accent: Palette.cyan,
                  onTap: () => showAppSheet<void>(
                    context,
                    builder: (_) => CalendarFeedView(
                      load: ref.read(apiClientProvider).calendarFeed,
                      rotate:
                          ref.read(apiClientProvider).rotateCalendarFeed,
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

  Widget _row(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 17, color: Palette.textMid),
        const SizedBox(width: 10),
        Expanded(
            child: Text(label,
                style: Typo.body(14, FontWeight.w500, Palette.textMid))),
        Text(value, style: Typo.body(14, FontWeight.w700)),
      ],
    );
  }
}

/// Edit first/last name, phone, avatar — port of iOS `AthleteEditProfileView`.
class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile});

  final ClientProfileDto profile;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final _first = TextEditingController(text: widget.profile.firstName);
  late final _last = TextEditingController(text: widget.profile.lastName);
  late final _phone = TextEditingController(text: widget.profile.phone ?? '');
  bool _saving = false;
  bool _uploading = false;

  Future<void> _pickAvatar() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final jpeg = await ImageCompressor.jpeg(bytes);
      final url =
          await ref.read(apiClientProvider).uploadProfilePhoto(jpeg);
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
      await ref.read(apiClientProvider).updateProfile({
        'first_name': _first.text.trim(),
        'last_name': _last.text.trim(),
        'phone': _phone.text.trim(),
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
                          color: Palette.cyan, shape: BoxShape.circle),
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
          const SizedBox(height: 14),
          TextField(
              controller: _last,
              style: Typo.body(15, FontWeight.w600),
              decoration: const InputDecoration(labelText: 'Cognome')),
          const SizedBox(height: 14),
          TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              style: Typo.body(15, FontWeight.w600),
              decoration: const InputDecoration(labelText: 'Telefono')),
          const SizedBox(height: 26),
          NeonButton('Salva', loading: _saving, onTap: _save),
        ],
      ),
    );
  }
}
