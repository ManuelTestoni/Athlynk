//
//  StatusOverlay.swift
//  A reusable success / failure flash, fired after a meaningful mutation
//  (saving a check feedback, an appointment, a plan, …). Reuses the same
//  animated seal + neon confetti language as the athlete CheckSuccessView, so
//  the two apps feel consistent. Drive it through the `.statusOverlay` modifier.
//

import SwiftUI

enum StatusKind: Equatable {
    case success(String)
    case failure(String)

    var isSuccess: Bool { if case .success = self { return true } else { return false } }
    var text: String { switch self { case .success(let t), .failure(let t): return t } }
    var accent: Color { isSuccess ? Palette.lime : Palette.crimson }
    var icon: String { isSuccess ? "checkmark" : "xmark" }
}

/// Lightweight controller you keep in a view as @StateObject and bump.
@MainActor
final class StatusFlash: ObservableObject {
    @Published var current: StatusKind?
    @Published var burst = 0

    func success(_ text: String = "Salvato") { fire(.success(text)) }
    func failure(_ text: String = "Operazione non riuscita") { fire(.failure(text)) }

    private func fire(_ kind: StatusKind) {
        current = kind
        if kind.isSuccess { Haptics.success() } else { Haptics.error() }
        burst += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            withAnimation(.easeOut(duration: 0.3)) { self?.current = nil }
        }
    }
}

private struct StatusOverlayModifier: ViewModifier {
    @ObservedObject var flash: StatusFlash
    @State private var sealIn = false

    func body(content: Content) -> some View {
        content.overlay {
            if let kind = flash.current {
                ZStack {
                    Color.black.opacity(0.32).ignoresSafeArea()
                        .transition(.opacity)
                    VStack(spacing: 18) {
                        seal(kind)
                        Text(kind.text)
                            .font(Typo.body(16, .semibold))
                            .foregroundStyle(Palette.textHi)
                            .multilineTextAlignment(.center)
                    }
                    .padding(30)
                    .frame(maxWidth: 260)
                    .background {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Palette.void1.opacity(0.96))
                            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(kind.accent.opacity(0.4), lineWidth: 1))
                    }
                    .shadow(color: .black.opacity(0.3), radius: 30, y: 14)

                    ParticleBurst(trigger: flash.burst,
                                  colors: kind.isSuccess
                                    ? [Palette.lime, Palette.bronze, Palette.aegean]
                                    : [Palette.crimson, Palette.amber])
                }
                .onAppear {
                    sealIn = false
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { sealIn = true }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: flash.current)
    }

    private func seal(_ kind: StatusKind) -> some View {
        ZStack {
            Circle().fill(kind.accent.opacity(0.14)).frame(width: 96, height: 96)
                .scaleEffect(sealIn ? 1 : 0.6)
            Circle().fill(kind.accent).frame(width: 70, height: 70)
                .neonGlow(kind.accent, radius: 16)
                .scaleEffect(sealIn ? 1 : 0.3)
            Image(systemName: kind.icon)
                .font(.system(size: 32, weight: .black))
                .foregroundStyle(Palette.void0)
                .scaleEffect(sealIn ? 1 : 0.2)
                .opacity(sealIn ? 1 : 0)
        }
    }
}

extension View {
    /// Flash a success/failure seal over this view. Pair with a `StatusFlash`.
    func statusOverlay(_ flash: StatusFlash) -> some View {
        modifier(StatusOverlayModifier(flash: flash))
    }
}
