import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/components/pressable.dart';
import '../../../design/theme.dart';
import 'rest_timer.dart';

/// Floating rest-timer pill — port of iOS `RestTimerOverlay`: bottom-anchored
/// "RECUPERO" label + exercise name + monospaced countdown + thin progress
/// bar, dismissible with ×.
class RestTimerOverlay extends ConsumerWidget {
  const RestTimerOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(restTimerProvider);
    final visible = timer.isRunning;

    final label = timer.secondsLeft >= 60
        ? '${timer.secondsLeft ~/ 60}:${(timer.secondsLeft % 60).toString().padLeft(2, '0')}'
        : '${timer.secondsLeft}s';

    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 1.4),
      duration: Motion.luxeDuration,
      curve: Motion.luxe,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: Motion.luxeDuration,
        child: Container(
          margin: EdgeInsets.only(
            left: 26,
            right: 26,
            bottom: MediaQuery.of(context).padding.bottom + 14,
          ),
          padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
          decoration: BoxDecoration(
            color: Palette.textHi,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330B1D3A),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_outlined,
                      size: 16, color: Palette.gold),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('RECUPERO',
                            style: Typo.mono(
                                    8, FontWeight.w700, Palette.gold)
                                .copyWith(letterSpacing: 2)),
                        Text(
                          timer.exerciseName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Typo.body(
                              12, FontWeight.w600, Palette.void0),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(label,
                      style:
                          Typo.mono(22, FontWeight.w700, Palette.void0)),
                  const SizedBox(width: 6),
                  Pressable(
                    onTap: () =>
                        ref.read(restTimerProvider.notifier).cancel(),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Palette.void0.withValues(alpha: 0.12),
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 15, color: Palette.void0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: timer.progress,
                  minHeight: 3,
                  backgroundColor: Palette.void0.withValues(alpha: 0.15),
                  color: Palette.gold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
