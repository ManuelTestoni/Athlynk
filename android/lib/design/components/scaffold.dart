import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'panel.dart';
import 'pressable.dart';

/// Standard screen scroll container (iOS `ScreenScroll`): horizontal padding,
/// top inset, bottom clearance for the floating tab bar, 22pt section gaps.
class ScreenScroll extends StatelessWidget {
  const ScreenScroll({
    super.key,
    required this.children,
    this.onRefresh,
    this.controller,
    this.topPadding = AppLayout.screenTop,
    this.bottomPadding = AppLayout.tabBarClearance,
    this.spacing = Space.section,
  });

  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final ScrollController? controller;
  final double topPadding;
  final double bottomPadding;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    Widget scroll = ListView.separated(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
      padding: EdgeInsets.fromLTRB(
          Space.screenH, topPadding, Space.screenH, bottomPadding),
      itemCount: children.length,
      separatorBuilder: (_, _) => SizedBox(height: spacing),
      itemBuilder: (_, i) => children[i],
    );
    if (onRefresh != null) {
      scroll = RefreshIndicator(
        onRefresh: onRefresh!,
        color: Palette.cyan,
        backgroundColor: Palette.void1,
        child: scroll,
      );
    }
    return scroll;
  }
}

/// "Monumental Stack" screen header: mono eyebrow + poster title + optional
/// subtitle + optional trailing widget (avatar/action), hairline rule below.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.trailing,
    this.titleSize = 46,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow(eyebrow),
                  const SizedBox(height: 6),
                  Text(title, style: Typo.poster(titleSize)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(subtitle!,
                        style: Typo.body(15, FontWeight.w400, Palette.textMid)),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 18),
        const Divider(height: 1),
      ],
    );
  }
}

/// Empty/error panel with icon, message and optional CTA (iOS `EmptyPanel`).
class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.message,
    this.tint = Palette.textLow,
    this.ctaLabel,
    this.onCta,
  });

  /// Network-error convenience (wifi icon + retry).
  const EmptyPanel.network({super.key, this.ctaLabel = 'Riprova', this.onCta})
      : icon = Icons.wifi_off_rounded,
        message = 'Problema di connessione. Controlla la rete e riprova.',
        tint = Palette.textLow;

  final IconData icon;
  final String message;
  final Color tint;
  final String? ctaLabel;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    return VoltPanel(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 22),
      child: Column(
        children: [
          Icon(icon, size: 34, color: tint),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Typo.body(14, FontWeight.w500, Palette.textMid),
          ),
          if (ctaLabel != null && onCta != null) ...[
            const SizedBox(height: 16),
            Pressable(
              onTap: onCta,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                decoration: BoxDecoration(
                  color: Palette.cyan.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                  border:
                      Border.all(color: Palette.cyan.withValues(alpha: 0.5)),
                ),
                child: Text(ctaLabel!,
                    style: Typo.body(14, FontWeight.w700, Palette.cyan)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Section opener: eyebrow + serif title, optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.trailing,
  });

  final String title;
  final String? eyebrow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                Eyebrow(eyebrow!),
                const SizedBox(height: 4),
              ],
              Text(title, style: Typo.display(20)),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Fade-to-transparent hairline (iOS `SectionDivider`).
class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          Palette.line,
          Palette.line.withValues(alpha: 0),
        ]),
      ),
    );
  }
}

/// ⓘ tooltip (iOS `InfoTip`): tap → popover-style panel.
class InfoTip extends StatelessWidget {
  const InfoTip(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () {
        showDialog<void>(
          context: context,
          barrierColor: Palette.textHi.withValues(alpha: 0.25),
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: VoltPanel(
              radius: Radii.hero,
              child: Text(text,
                  style: Typo.body(14, FontWeight.w500, Palette.textMid)),
            ),
          ),
        );
      },
      child: const Icon(Icons.info_outline_rounded,
          size: 16, color: Palette.textLow),
    );
  }
}

/// Chevron nav row (iOS `NavListRow`).
class NavListRow extends StatelessWidget {
  const NavListRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.accent,
    this.onTap,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? accent;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accent = this.accent ?? Palette.cyan;
    return VoltPanel(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Typo.body(15, FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: Typo.body(12, FontWeight.w400, Palette.textLow)),
              ],
            ),
          ),
          trailing ??
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: Palette.textLow),
        ],
      ),
    );
  }
}

/// 2-column hub tile (both "Altro" hubs).
class HubTile extends StatelessWidget {
  const HubTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    this.onTap,
    this.index = 0,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final int index;

  @override
  Widget build(BuildContext context) {
    return RevealUp(
      index: index,
      child: VoltPanel(
        onTap: onTap,
        tint: accent.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: accent),
            ),
            const SizedBox(height: 14),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Typo.display(16)),
            const SizedBox(height: 3),
            Text(subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Typo.body(11.5, FontWeight.w400, Palette.textLow)),
          ],
        ),
      ),
    );
  }
}

/// Small status pill (iOS `StatusBadge`).
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.color = Palette.lime});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label.toUpperCase(),
          style: Typo.mono(9, FontWeight.w700, color).copyWith(letterSpacing: 1)),
    );
  }
}

/// Hosted legal documents (5 links, same URLs as iOS `LegalLinks`).
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  static const _links = [
    ('Privacy Policy', 'https://app.athlynk.it/privacy/'),
    ('Termini di Servizio', 'https://app.athlynk.it/termini-di-servizio/'),
    ("Termini d'Uso", 'https://app.athlynk.it/termini-duso/'),
    ('Cookie Policy', 'https://app.athlynk.it/cookie/'),
    ('Trasparenza AI', 'https://app.athlynk.it/ai-trasparenza/'),
  ];

  @override
  Widget build(BuildContext context) {
    return VoltPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (final (i, link) in _links.indexed) ...[
            if (i > 0) const Divider(height: 1),
            Pressable(
              onTap: () => launchUrl(Uri.parse(link.$2),
                  mode: LaunchMode.externalApplication),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child:
                          Text(link.$1, style: Typo.body(14, FontWeight.w500)),
                    ),
                    const Icon(Icons.open_in_new_rounded,
                        size: 15, color: Palette.textLow),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Notification-preference toggle row with the optimistic local mirror the
/// iOS `SettingsToggleRow` uses (the switch flips instantly, backend catches
/// up async and the row never visually lags).
class SettingsToggleRow extends StatefulWidget {
  const SettingsToggleRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final Future<void> Function(bool) onChanged;

  @override
  State<SettingsToggleRow> createState() => _SettingsToggleRowState();
}

class _SettingsToggleRowState extends State<SettingsToggleRow> {
  late bool _local = widget.value;

  @override
  void didUpdateWidget(SettingsToggleRow old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _local = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: Typo.body(14.5, FontWeight.w600)),
                if (widget.subtitle != null)
                  Text(widget.subtitle!,
                      style: Typo.body(12, FontWeight.w400, Palette.textLow)),
              ],
            ),
          ),
          Switch(
            value: _local,
            onChanged: (v) {
              setState(() => _local = v);
              widget.onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}
