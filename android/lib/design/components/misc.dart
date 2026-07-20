import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

/// Animated numeric counter (iOS `RollingNumber` / `.contentTransition`).
class RollingNumber extends StatelessWidget {
  const RollingNumber(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.snappyDuration,
      switchInCurve: Motion.snappy,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.35), end: Offset.zero)
              .animate(anim),
          child: child,
        ),
      ),
      child: Text(text, key: ValueKey(text), style: style ?? Typo.poster(38)),
    );
  }
}

/// "Carica ancora" pagination trigger (iOS `LoadMoreButton`).
class LoadMoreButton extends StatelessWidget {
  const LoadMoreButton({super.key, required this.onTap, this.loading = false});

  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Pressable(
        onTap: loading ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
          decoration: BoxDecoration(
            color: Palette.void1,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Palette.line),
          ),
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Palette.textMid),
                )
              : Text('Carica ancora',
                  style: Typo.mono(11, FontWeight.w700, Palette.textMid)
                      .copyWith(letterSpacing: 1)),
        ),
      ),
    );
  }
}

/// 44pt rounded exercise cover thumbnail with dumbbell placeholder
/// (iOS `ExerciseThumb`).
class ExerciseThumb extends StatelessWidget {
  const ExerciseThumb({super.key, this.url, this.size = 44});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final u = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        color: Palette.void2,
        child: (u == null || u.isEmpty)
            ? const Icon(Icons.fitness_center_rounded,
                size: 18, color: Palette.textLow)
            : CachedNetworkImage(
                imageUrl: u,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const Icon(
                    Icons.fitness_center_rounded,
                    size: 18,
                    color: Palette.textLow),
              ),
      ),
    );
  }
}

/// Big hero media block: animated WebP demo gif → static cover → placeholder
/// (iOS `ExerciseMediaHero`). Flutter decodes animated WebP natively, so no
/// WebView hack is needed here.
class ExerciseMediaHero extends StatelessWidget {
  const ExerciseMediaHero({
    super.key,
    this.demoGif,
    this.coverImage,
    this.height = 210,
  });

  final String? demoGif;
  final String? coverImage;
  final double height;

  @override
  Widget build(BuildContext context) {
    final media = (demoGif?.isNotEmpty ?? false)
        ? demoGif!
        : ((coverImage?.isNotEmpty ?? false) ? coverImage! : null);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.hero),
      child: Container(
        height: height,
        width: double.infinity,
        color: Colors.white,
        child: media == null
            ? const Center(
                child: Icon(Icons.fitness_center_rounded,
                    size: 40, color: Palette.textLow))
            : CachedNetworkImage(
                imageUrl: media,
                fit: BoxFit.contain,
                placeholder: (_, _) => const Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Palette.textLow),
                  ),
                ),
                errorWidget: (_, _, _) => const Center(
                    child: Icon(Icons.fitness_center_rounded,
                        size: 40, color: Palette.textLow)),
              ),
      ),
    );
  }
}

/// Serif headline with a gold-shadow settle-in reveal (iOS `GlitchText` —
/// the RGB-split effect was removed long ago; the name is legacy).
class GlitchText extends StatefulWidget {
  const GlitchText(this.text, {super.key, this.size = 56});

  final String text;
  final double size;

  @override
  State<GlitchText> createState() => _GlitchTextState();
}

class _GlitchTextState extends State<GlitchText> {
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _settled = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Motion.glowDecay,
      curve: Curves.easeOut,
      child: AnimatedDefaultTextStyle(
        duration: Motion.glowIn,
        style: Typo.poster(widget.size).copyWith(
          letterSpacing: 2,
          shadows: [
            Shadow(
              color: Palette.gold.withValues(alpha: _settled ? 0.0 : 0.85),
              blurRadius: _settled ? 2 : 22,
            ),
          ],
        ),
        child: Text(widget.text),
      ),
    );
  }
}

/// Big KPI stat tile — iOS `CoachStatTile` (shared by BOTH dashboards
/// despite the name): icon, optional flag badge, poster value, mono label.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.flag,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final String? flag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        decoration: voltPanel(tint: accent.withValues(alpha: 0.3)),
        padding: const EdgeInsets.all(Space.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: accent),
                const Spacer(),
                if (flag != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child:
                        Text(flag!, style: Typo.mono(8, FontWeight.w700, accent)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: RollingNumber(value, style: Typo.poster(34)),
            ),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Typo.mono(9, FontWeight.w600, Palette.textLow)
                  .copyWith(letterSpacing: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small quick-nav tile (iOS `CoachQuickAction`).
class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.accent,
    this.plusBadge = false,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final bool plusBadge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        decoration: voltPanel(),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 20, color: accent),
                if (plusBadge)
                  Positioned(
                    right: -7,
                    top: -5,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Palette.void1, width: 1.5),
                      ),
                      child: const Icon(Icons.add_rounded,
                          size: 9, color: Palette.void0),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label.toUpperCase(),
              style: Typo.mono(8.5, FontWeight.w700, Palette.textMid)
                  .copyWith(letterSpacing: 0.8),
            ),
          ],
        ),
      ),
    );
  }
}
