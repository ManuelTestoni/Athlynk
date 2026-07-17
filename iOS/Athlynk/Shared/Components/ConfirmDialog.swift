//
//  ConfirmDialog.swift
//  Custom confirm/alert overlay, replacing system .alert/.confirmationDialog for
//  consistent styling across both apps (mirrors the web app's alConfirm/alAlert).
//  Presentation pattern mirrors StatusOverlay (ObservableObject + root .overlay),
//  but exposes an async API so call sites read like:
//    if await confirmCenter.confirm(.init(title: "Eliminare il giorno?")) { remove() }
//

import SwiftUI
import Combine

enum ConfirmVariant {
    case danger, neutral
    var accent: Color { self == .danger ? Palette.danger : Palette.control }
}

struct ConfirmOptions {
    var title: String
    var subtitle: String? = nil
    var icon: String = "trash"
    var variant: ConfirmVariant = .danger
    var confirmLabel: String = "Elimina"
    var cancelLabel: String = "Annulla"
}

@MainActor
final class ConfirmCenter: ObservableObject {
    fileprivate struct Pending: Identifiable {
        let id = UUID()
        let options: ConfirmOptions
        let isAlert: Bool
        let resume: (Bool) -> Void
    }

    @Published fileprivate var pending: Pending?

    /// Binary choice. Returns true if the user confirmed.
    func confirm(_ options: ConfirmOptions) async -> Bool {
        await withCheckedContinuation { continuation in
            pending = Pending(options: options, isAlert: false) { result in
                continuation.resume(returning: result)
            }
        }
    }

    /// Single-button informational dialog. Fire-and-forget, no result to await.
    func alert(_ options: ConfirmOptions) {
        pending = Pending(options: options, isAlert: true) { _ in }
    }

    fileprivate func resolve(_ result: Bool) {
        guard let current = pending else { return }
        pending = nil
        current.resume(result)
    }
}

private struct ConfirmDialogHost: ViewModifier {
    @ObservedObject var center: ConfirmCenter
    @State private var sealIn = false

    func body(content: Content) -> some View {
        content.overlay {
            if let pending = center.pending {
                let opts = pending.options
                ZStack {
                    Color.black.opacity(0.32).ignoresSafeArea()
                        .transition(.opacity)

                    VStack(spacing: 16) {
                        icon(opts)
                        VStack(spacing: 6) {
                            Text(opts.title)
                                .font(Typo.body(17, .semibold))
                                .foregroundStyle(Palette.textHi)
                                .multilineTextAlignment(.center)
                            if let subtitle = opts.subtitle {
                                Text(subtitle)
                                    .font(Typo.body(13))
                                    .foregroundStyle(Palette.textMid)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        buttons(pending)
                    }
                    .padding(24)
                    .frame(maxWidth: 300)
                    .background {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Palette.void1)
                            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(opts.variant.accent.opacity(0.35), lineWidth: 1))
                    }
                    .shadow(color: .black.opacity(0.22), radius: 30, y: 14)
                    .scaleEffect(sealIn ? 1 : 0.9)
                    .opacity(sealIn ? 1 : 0)
                }
                .onAppear {
                    sealIn = false
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { sealIn = true }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: center.pending?.id)
    }

    private func icon(_ opts: ConfirmOptions) -> some View {
        ZStack {
            Circle().fill(opts.variant.accent.opacity(0.14)).frame(width: 64, height: 64)
            Image(systemName: opts.icon)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(opts.variant.accent)
        }
    }

    @ViewBuilder
    private func buttons(_ pending: ConfirmCenter.Pending) -> some View {
        let opts = pending.options
        if pending.isAlert {
            NeonButton(title: opts.confirmLabel, color: opts.variant.accent) {
                center.resolve(true)
            }
        } else {
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    center.resolve(false)
                } label: {
                    Text(opts.cancelLabel)
                        .font(Typo.body(15, .semibold))
                        .foregroundStyle(Palette.textMid)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(Palette.void2))
                }
                .buttonStyle(PressableButtonStyle())

                Button {
                    Haptics.tap()
                    center.resolve(true)
                } label: {
                    Text(opts.confirmLabel)
                        .font(Typo.body(15, .semibold))
                        .foregroundStyle(Palette.void0)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(opts.variant.accent))
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }
}

extension View {
    func confirmDialogHost(_ center: ConfirmCenter) -> some View {
        modifier(ConfirmDialogHost(center: center))
    }
}
