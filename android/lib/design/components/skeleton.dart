import 'package:flutter/material.dart';

import '../theme.dart';

/// Shimmer-loading system — port of iOS `Skeleton.swift`: a light band
/// sweeping left→right over stone-gray blocks; opacity pulse under reduced
/// motion. Each real screen composes its own skeleton from these primitives.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      // Slow opacity pulse fallback.
      return _PulseFallback(child: widget.child);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = (_c.value * 2 - 0.5) * bounds.width;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Palette.void2,
                Colors.white.withValues(alpha: 0.55),
                Palette.void2,
              ],
              stops: const [0.35, 0.5, 0.65],
              transform: _SlideGradientTransform(dx),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlideGradientTransform extends GradientTransform {
  const _SlideGradientTransform(this.dx);
  final double dx;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

class _PulseFallback extends StatefulWidget {
  const _PulseFallback({required this.child});
  final Widget child;

  @override
  State<_PulseFallback> createState() => _PulseFallbackState();
}

class _PulseFallbackState extends State<_PulseFallback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.55,
    upperBound: 0.9,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _c, child: widget.child);
}

// ── Primitives ──

class SkelBlock extends StatelessWidget {
  const SkelBlock({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Palette.void2,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class SkelDot extends StatelessWidget {
  const SkelDot({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration:
          const BoxDecoration(color: Palette.void2, shape: BoxShape.circle),
    );
  }
}

/// One card-shaped skeleton row.
class SkelCard extends StatelessWidget {
  const SkelCard({super.key, this.height = 96});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: voltPanel(),
      padding: const EdgeInsets.all(Space.card),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SkelBlock(width: 120, height: 12),
          SizedBox(height: 10),
          SkelBlock(width: 200, height: 16),
        ],
      ),
    );
  }
}

class SkelAvatarRow extends StatelessWidget {
  const SkelAvatarRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: voltPanel(),
      padding: const EdgeInsets.all(Space.card),
      child: const Row(children: [
        SkelDot(size: 44),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkelBlock(width: 140, height: 13),
              SizedBox(height: 8),
              SkelBlock(width: 90, height: 11),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Generic page skeletons (page-specific ones live with their screens) ──

class ListCardsSkeleton extends StatelessWidget {
  const ListCardsSkeleton({super.key, this.count = 3, this.height = 120});
  final int count;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < count; i++) ...[
            SkelCard(height: height),
            const SizedBox(height: Space.element),
          ],
        ],
      ),
    );
  }
}

class AvatarRowsSkeleton extends StatelessWidget {
  const AvatarRowsSkeleton({super.key, this.count = 5});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < count; i++) ...[
            const SkelAvatarRow(),
            const SizedBox(height: Space.element),
          ],
        ],
      ),
    );
  }
}

class TimelineSkeleton extends StatelessWidget {
  const TimelineSkeleton({super.key, this.count = 4});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.element),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: SkelDot(size: 14),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: SkelCard(height: 88)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class FormSkeleton extends StatelessWidget {
  const FormSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkelBlock(width: 110, height: 12),
          SizedBox(height: 12),
          SkelCard(height: 60),
          SizedBox(height: Space.element),
          SkelCard(height: 60),
          SizedBox(height: Space.element),
          SkelCard(height: 60),
          SizedBox(height: Space.section),
          SkelBlock(width: 110, height: 12),
          SizedBox(height: 12),
          SkelCard(height: 140),
        ],
      ),
    );
  }
}

class DateCardsSkeleton extends StatelessWidget {
  const DateCardsSkeleton({super.key, this.count = 5});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.element),
              child: Container(
                decoration: voltPanel(),
                padding: const EdgeInsets.all(Space.card),
                child: const Row(children: [
                  SkelBlock(width: 52, height: 52, radius: 12),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkelBlock(width: 150, height: 13),
                        SizedBox(height: 8),
                        SkelBlock(width: 100, height: 11),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
