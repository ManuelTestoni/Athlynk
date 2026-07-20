import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/utils/haptics.dart';
import '../theme.dart';

/// Spec for one tab of the floating glass bar.
class FloatingTabSpec {
  const FloatingTabSpec({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color Function() color; // late-bound: brand colors can change
}

/// Floating capsule tab bar — port of iOS `NeonTabBar`/`CoachTabBar`:
/// glass blur + tint, morphing active-tab color blob, bounce on select,
/// re-tap active tab = pop-to-root callback. Slides off-screen when hidden.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({
    super.key,
    required this.tabs,
    required this.index,
    required this.onSelect,
    required this.onReselect,
    this.hidden = false,
  });

  final List<FloatingTabSpec> tabs;
  final int index;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onReselect;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: hidden ? const Offset(0, 1.8) : Offset.zero,
      duration: Motion.luxeDuration,
      curve: Motion.luxe,
      child: AnimatedOpacity(
        opacity: hidden ? 0 : 1,
        duration: Motion.luxeDuration,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Palette.void1.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x260B1D3A),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final slot = constraints.maxWidth / tabs.length;
                  return SizedBox(
                    height: 57,
                    child: Stack(
                      children: [
                        // Morphing active blob (matchedGeometry equivalent).
                        AnimatedPositioned(
                          duration: Motion.luxeDuration,
                          curve: Motion.luxe,
                          left: slot * index + 4,
                          top: 0,
                          bottom: 0,
                          width: slot - 8,
                          child: AnimatedContainer(
                            duration: Motion.luxeDuration,
                            decoration: BoxDecoration(
                              color: tabs[index].color(),
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: neonGlow(tabs[index].color()),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (final (i, tab) in tabs.indexed)
                              Expanded(child: _TabButton(
                                spec: tab,
                                active: i == index,
                                onTap: () {
                                  if (i == index) {
                                    Haptics.tap();
                                    onReselect(i);
                                  } else {
                                    Haptics.tap();
                                    onSelect(i);
                                  }
                                },
                              )),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.spec,
    required this.active,
    required this.onTap,
  });

  final FloatingTabSpec spec;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Palette.void0 : Palette.textMid;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 1, end: active ? 1 : 0),
            duration: Motion.snappyDuration,
            curve: Motion.snappy,
            builder: (context, v, child) => Transform.scale(
              scale: 1 + 0.12 * v * (active ? 1 : 0),
              child: child,
            ),
            child: Icon(spec.icon, size: 20, color: fg),
          ),
          const SizedBox(height: 3),
          Text(
            spec.title.toUpperCase(),
            style: Typo.mono(9, FontWeight.w700, fg).copyWith(letterSpacing: 1),
          ),
        ],
      ),
    );
  }
}
