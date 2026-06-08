//
//  Skeleton.swift
//  Loading scaffolds: while a screen fetches its data we show the *shape* of the
//  content to come — stone blocks on the marble panels, swept by a soft parchment
//  sheen. Each page composes the archetype skeleton that mirrors its real layout.
//
//  Aesthetic: same Greek-luxury surfaces as the live UI (see Theme.swift). The
//  shimmer is a light band gliding left→right, never neon. Honours Reduce Motion
//  by falling back to a gentle opacity pulse.
//

import SwiftUI

// MARK: - Shimmer engine

/// Sweeps a soft highlight across a known shape; clips the band to that shape so
/// the sheen rides only the stone block, not its bounding box.
private struct ShimmerBand<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        if reduceMotion {
            content.modifier(SkeletonPulse())
        } else {
            content
                .overlay {
                    GeometryReader { geo in
                        let w = max(geo.size.width, 1)
                        LinearGradient(colors: [.clear, Color.white.opacity(0.55), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: w * 0.6)
                            .offset(x: phase * w * 1.5)
                    }
                    .clipShape(shape)
                    .allowsHitTesting(false)
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
    }
}

/// Reduce-Motion fallback: a slow breathing fade instead of a moving band.
private struct SkeletonPulse: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 0.55 : 0.9)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

// MARK: - Atoms

/// A single stone bar. `width: nil` stretches to fill the row.
struct SkelBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var radius: CGFloat = 8

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(Palette.void2)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .modifier(ShimmerBand(shape: shape))
    }
}

/// A stone disc (avatars, nodes, status glyphs).
struct SkelDot: View {
    var size: CGFloat
    var body: some View {
        let shape = Circle()
        shape
            .fill(Palette.void2)
            .frame(width: size, height: size)
            .modifier(ShimmerBand(shape: shape))
    }
}

// MARK: - Reusable rows

/// Mirrors the "navigation link" tiles (icon square · two lines · arrow).
struct SkelLinkRow: View {
    var accent: Color = Palette.bronze
    var body: some View {
        HStack(spacing: 14) {
            SkelBlock(width: 48, height: 48, radius: 12)
            VStack(alignment: .leading, spacing: 7) {
                SkelBlock(width: 150, height: 14)
                SkelBlock(width: 110, height: 10)
            }
            Spacer()
            SkelDot(size: 16)
        }
        .padding(16).voltPanel(accent.opacity(0.2))
    }
}

/// Mirrors avatar list rows (chat, notifications): disc · two lines · trailing dot.
struct SkelAvatarRow: View {
    var accent: Color = Palette.cyan
    var body: some View {
        HStack(spacing: 14) {
            SkelDot(size: 46)
            VStack(alignment: .leading, spacing: 7) {
                SkelBlock(width: 150, height: 15)
                SkelBlock(width: 220, height: 11)
            }
            Spacer()
            SkelDot(size: 10)
        }
        .padding(14).voltPanel(accent.opacity(0.2))
    }
}

/// Mirrors summary cards (badge · title · subtitle · metric pills).
struct SkelSummaryCard: View {
    var accent: Color
    var pills: Int = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SkelBlock(width: 64, height: 18, radius: 6)
            SkelBlock(width: 190, height: 22)
            SkelBlock(width: 130, height: 11)
            HStack(spacing: 10) {
                ForEach(0..<pills, id: \.self) { _ in SkelBlock(height: 48, radius: 10) }
            }
        }
        .padding(18).voltPanel(accent.opacity(0.25))
    }
}

/// Mirrors date-stamped rows (agenda, history): date block · lines · status glyph.
struct SkelDateCard: View {
    var accent: Color
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SkelBlock(width: 54, height: 56, radius: 10)
            VStack(alignment: .leading, spacing: 8) {
                SkelBlock(width: 170, height: 16)
                SkelBlock(width: 120, height: 11)
                SkelBlock(width: 90, height: 11)
            }
            Spacer()
            SkelDot(size: 22)
        }
        .padding(16).voltPanel(accent.opacity(0.25))
    }
}

/// Mirrors a 3-up metric strip (quick stats, vitals).
struct SkelMetricsRow: View {
    var count: Int = 3
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    SkelBlock(width: 46, height: 26)
                    SkelBlock(width: 60, height: 9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14).padding(.horizontal, 12)
                .voltPanel()
            }
        }
    }
}

/// Mirrors a text panel (eyebrow · paragraph) — bios, anamnesis sections.
struct SkelSection: View {
    var accent: Color = Palette.bronze
    var lines: Int = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkelBlock(width: 120, height: 10)
            ForEach(0..<lines, id: \.self) { i in
                SkelBlock(width: i == lines - 1 ? 170 : nil, height: 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).voltPanel(accent.opacity(0.2))
    }
}

/// Small uppercase-eyebrow placeholder used between sections.
struct SkelEyebrow: View {
    var width: CGFloat = 90
    var body: some View { SkelBlock(width: width, height: 10, radius: 4).padding(.top, 4) }
}

// MARK: - Page skeletons

/// Generic list of summary cards (Workouts).
struct ListCardsSkeleton: View {
    var accent: Color
    var count: Int = 2
    var pills: Int = 3
    @State private var appear = false
    var body: some View {
        Group {
            ForEach(0..<count, id: \.self) { i in
                SkelSummaryCard(accent: accent, pills: pills).revealUp(appear, index: i)
            }
        }
        .onAppear { appear = true }
    }
}

/// Avatar rows (Chat list, Notifications).
struct AvatarRowsSkeleton: View {
    var accent: Color = Palette.cyan
    var count: Int = 5
    @State private var appear = false
    var body: some View {
        Group {
            ForEach(0..<count, id: \.self) { i in
                SkelAvatarRow(accent: accent).revealUp(appear, index: i)
            }
        }
        .onAppear { appear = true }
    }
}

/// Date-stamped cards with a leading section label (Agenda, Workout history).
struct DateCardsSkeleton: View {
    var accent: Color
    var count: Int = 3
    @State private var appear = false
    var body: some View {
        Group {
            SkelEyebrow(width: 110).revealUp(appear, index: 0)
            ForEach(0..<count, id: \.self) { i in
                SkelDateCard(accent: accent).revealUp(appear, index: i + 1)
            }
        }
        .onAppear { appear = true }
    }
}

/// Vertical timeline (Checks, Journey).
struct TimelineSkeleton: View {
    var accent: Color = Palette.violet
    var count: Int = 3
    var railWidth: CGFloat = 14
    @State private var appear = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        SkelDot(size: 14)
                        if i != count - 1 {
                            Rectangle().fill(Palette.line).frame(width: 2).frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: railWidth, alignment: .top)

                    VStack(alignment: .leading, spacing: 10) {
                        SkelBlock(width: 90, height: 10)
                        SkelBlock(width: 170, height: 16)
                        SkelBlock(width: 120, height: 11)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .voltPanel(accent.opacity(0.25))
                    .padding(.bottom, i == count - 1 ? 0 : 16)
                    .revealUp(appear, index: i)
                }
            }
        }
        .onAppear { appear = true }
    }
}

/// Form: labelled fields + save button (Edit profile).
struct FormSkeleton: View {
    var accent: Color = Palette.amber
    var count: Int = 6
    @State private var appear = false
    var body: some View {
        Group {
            ForEach(0..<count, id: \.self) { i in
                VStack(alignment: .leading, spacing: 6) {
                    SkelBlock(width: 90, height: 9, radius: 4)
                    SkelBlock(height: 44, radius: 10)
                }
                .revealUp(appear, index: i)
            }
            SkelBlock(height: 52, radius: 26).revealUp(appear, index: count).padding(.top, 4)
        }
        .onAppear { appear = true }
    }
}

/// Dashboard hub: today's session + next meal + coach message.
struct DashboardSkeleton: View {
    @State private var appear = false
    var body: some View {
        Group {
            SkelEyebrow(width: 60).revealUp(appear, index: 0)
            SkelSummaryCard(accent: Palette.magenta, pills: 2).revealUp(appear, index: 1)
            SkelEyebrow(width: 130).revealUp(appear, index: 2)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SkelBlock(width: 140, height: 18)
                    Spacer()
                    SkelBlock(width: 60, height: 14)
                }
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in SkelBlock(height: 40, radius: 10) }
                }
            }
            .padding(18).voltPanel(Palette.lime.opacity(0.25))
            .revealUp(appear, index: 3)
            SkelEyebrow(width: 110).revealUp(appear, index: 4)
            SkelAvatarRow(accent: Palette.cyan).revealUp(appear, index: 5)
        }
        .onAppear { appear = true }
    }
}

/// Nutrition: active plan card + meal breakdown.
struct NutritionSkeleton: View {
    @State private var appear = false
    var body: some View {
        Group {
            SkelSummaryCard(accent: Palette.lime).revealUp(appear, index: 0)
            SkelEyebrow(width: 70).revealUp(appear, index: 1)
            ForEach(0..<2, id: \.self) { i in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SkelBlock(width: 130, height: 16)
                        Spacer()
                        SkelBlock(width: 60, height: 12)
                    }
                    ForEach(0..<3, id: \.self) { _ in
                        HStack {
                            SkelDot(size: 6)
                            SkelBlock(width: 150, height: 12)
                            Spacer()
                            SkelBlock(width: 40, height: 10)
                        }
                    }
                }
                .padding(16).voltPanel(Palette.accent(i).opacity(0.25))
                .revealUp(appear, index: i + 2)
            }
        }
        .onAppear { appear = true }
    }
}

/// Supplement protocol cards (icon · title · dose/timing tags · note).
struct SupplementsSkeleton: View {
    var count: Int = 3
    @State private var appear = false
    var body: some View {
        Group {
            ForEach(0..<count, id: \.self) { i in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        SkelDot(size: 22)
                        VStack(alignment: .leading, spacing: 5) {
                            SkelBlock(width: 160, height: 17)
                            SkelBlock(width: 90, height: 9)
                        }
                        Spacer()
                    }
                    HStack(spacing: 10) {
                        SkelBlock(width: 90, height: 26, radius: 13)
                        SkelBlock(width: 110, height: 26, radius: 13)
                    }
                }
                .padding(16).voltPanel(Palette.accent(i).opacity(0.3))
                .revealUp(appear, index: i)
            }
        }
        .onAppear { appear = true }
    }
}

/// Settings: account card + notification toggle rows.
struct SettingsSkeleton: View {
    @State private var appear = false
    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                SkelBlock(width: 80, height: 10)
                HStack(spacing: 12) { SkelDot(size: 18); SkelBlock(width: 180, height: 14); Spacer() }
            }
            .padding(18).voltPanel(Palette.cyan.opacity(0.2))
            .revealUp(appear, index: 0)

            SkelEyebrow(width: 130).revealUp(appear, index: 1)

            ForEach(0..<4, id: \.self) { i in
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        SkelBlock(width: 150, height: 14)
                        SkelBlock(width: 210, height: 10)
                    }
                    Spacer()
                    SkelBlock(width: 46, height: 28, radius: 14)
                }
                .padding(16).voltPanel(Palette.cyan.opacity(0.2))
                .revealUp(appear, index: i + 2)
            }
        }
        .onAppear { appear = true }
    }
}

/// Coach profile: centred hero + stats + bio sections.
struct CoachDetailSkeleton: View {
    @State private var appear = false
    var body: some View {
        Group {
            VStack(spacing: 14) {
                SkelDot(size: 110)
                SkelBlock(width: 180, height: 26)
                SkelBlock(width: 120, height: 11)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .revealUp(appear, index: 0)

            HStack(spacing: 12) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(spacing: 6) { SkelBlock(width: 60, height: 20); SkelBlock(width: 80, height: 9) }
                        .frame(maxWidth: .infinity).padding(.vertical, 16).voltPanel(Palette.bronze.opacity(0.25))
                }
            }
            .revealUp(appear, index: 1)

            SkelSection(accent: Palette.violet, lines: 4).revealUp(appear, index: 2)
            SkelSection(accent: Palette.violet, lines: 2).revealUp(appear, index: 3)
        }
        .onAppear { appear = true }
    }
}

/// Macro diary: calorie ring + macro bars + logged entries.
struct MacroLogSkeleton: View {
    @State private var appear = false
    var body: some View {
        Group {
            VStack(spacing: 14) {
                HStack { SkelBlock(width: 100, height: 10); Spacer(); SkelBlock(width: 80, height: 10) }
                SkelDot(size: 188)
            }
            .padding(20).voltPanel(Palette.lime.opacity(0.25))
            .revealUp(appear, index: 0)

            VStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { SkelBlock(width: 100, height: 12); Spacer(); SkelBlock(width: 70, height: 10) }
                        SkelBlock(height: 9, radius: 5)
                    }
                }
            }
            .padding(18).voltPanel(Palette.cyan.opacity(0.25))
            .revealUp(appear, index: 1)

            SkelBlock(height: 52, radius: 26).revealUp(appear, index: 2)
            SkelEyebrow(width: 130).revealUp(appear, index: 3)
            ForEach(0..<2, id: \.self) { i in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        SkelBlock(width: 150, height: 13)
                        SkelBlock(width: 200, height: 9)
                    }
                    Spacer()
                    SkelBlock(width: 40, height: 14)
                }
                .padding(14).voltPanel(Palette.lime.opacity(0.2))
                .revealUp(appear, index: i + 4)
            }
        }
        .onAppear { appear = true }
    }
}

/// Anamnesis: monumental header + vitals + text sections.
struct AnamnesisSkeleton: View {
    @State private var appear = false
    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                SkelBlock(width: 110, height: 10)
                SkelBlock(width: 200, height: 32)
                SkelBlock(width: 150, height: 11)
                Rectangle().fill(Palette.line).frame(height: 1)
            }
            .revealUp(appear, index: 0)

            SkelMetricsRow(count: 3).revealUp(appear, index: 1)
            SkelSection(accent: Palette.bronze, lines: 3).revealUp(appear, index: 2)
            SkelSection(accent: Palette.bronze, lines: 2).revealUp(appear, index: 3)
            SkelSection(accent: Palette.bronze, lines: 3).revealUp(appear, index: 4)
        }
        .onAppear { appear = true }
    }
}

/// Progress: chart carousel card + check history.
struct ProgressSkeleton: View {
    @State private var appear = false
    var body: some View {
        Group {
            VStack(spacing: 14) {
                HStack(spacing: 11) {
                    SkelDot(size: 34)
                    VStack(alignment: .leading, spacing: 6) {
                        SkelBlock(width: 110, height: 10)
                        SkelBlock(width: 150, height: 20)
                    }
                    Spacer()
                }
                SkelBlock(height: 200, radius: 12)
                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { _ in SkelBlock(width: 16, height: 7, radius: 4) }
                }
            }
            .padding(18).voltPanel(Palette.cyan.opacity(0.25))
            .revealUp(appear, index: 0)

            SkelEyebrow(width: 120).revealUp(appear, index: 1)
            ForEach(0..<2, id: \.self) { i in
                VStack(alignment: .leading, spacing: 12) {
                    HStack { SkelBlock(width: 130, height: 11); Spacer(); SkelBlock(width: 60, height: 12) }
                    SkelBlock(height: 12)
                    SkelBlock(width: 220, height: 12)
                }
                .padding(16).voltPanel(Palette.violet.opacity(0.2))
                .revealUp(appear, index: i + 2)
            }
        }
        .onAppear { appear = true }
    }
}

/// Subscription: plan card + included services.
struct SubscriptionSkeleton: View {
    @State private var appear = false
    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        SkelBlock(width: 64, height: 18, radius: 6)
                        SkelBlock(width: 180, height: 26)
                        SkelBlock(width: 100, height: 10)
                    }
                    Spacer()
                    SkelDot(size: 26)
                }
                SkelBlock(width: 120, height: 30)
                Rectangle().fill(Palette.line).frame(height: 1)
                ForEach(0..<4, id: \.self) { _ in
                    HStack { SkelBlock(width: 110, height: 11); Spacer(); SkelBlock(width: 90, height: 12) }
                }
            }
            .padding(18).voltPanel(Palette.amber.opacity(0.3))
            .revealUp(appear, index: 0)

            VStack(alignment: .leading, spacing: 12) {
                SkelBlock(width: 130, height: 10)
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 10) { SkelDot(size: 14); SkelBlock(width: 200, height: 12); Spacer() }
                }
            }
            .padding(18).voltPanel(Palette.lime.opacity(0.25))
            .revealUp(appear, index: 1)
        }
        .onAppear { appear = true }
    }
}

/// Pricing: plan cards with price, service list and CTA.
struct PricingSkeleton: View {
    var count: Int = 2
    @State private var appear = false
    var body: some View {
        Group {
            ForEach(0..<count, id: \.self) { i in
                VStack(alignment: .leading, spacing: 14) {
                    SkelBlock(width: 80, height: 18, radius: 6)
                    SkelBlock(width: 170, height: 24)
                    SkelBlock(width: 120, height: 34)
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 10) { SkelDot(size: 13); SkelBlock(width: 190, height: 11); Spacer() }
                    }
                    SkelBlock(height: 50, radius: 25).padding(.top, 2)
                }
                .padding(18).voltPanel(Palette.bronze.opacity(i == 0 ? 0.4 : 0.25))
                .revealUp(appear, index: i)
            }
        }
        .onAppear { appear = true }
    }
}

/// Active training session: header + exercise blocks with set rows.
struct ActiveSessionSkeleton: View {
    @State private var appear = false
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    SkelBlock(width: 90, height: 10)
                    SkelBlock(width: 200, height: 28)
                    SkelBlock(height: 8, radius: 4)
                }
                .revealUp(appear, index: 0)

                ForEach(0..<2, id: \.self) { e in
                    VStack(alignment: .leading, spacing: 12) {
                        SkelBlock(width: 170, height: 18)
                        ForEach(0..<3, id: \.self) { _ in
                            HStack(spacing: 10) {
                                SkelBlock(width: 30, height: 30, radius: 8)
                                SkelBlock(height: 30, radius: 8)
                                SkelBlock(width: 40, height: 30, radius: 8)
                            }
                        }
                    }
                    .padding(16).voltPanel(Palette.magenta.opacity(0.25))
                    .revealUp(appear, index: e + 1)
                }
            }
            .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 50)
        }
        .onAppear { appear = true }
    }
}
