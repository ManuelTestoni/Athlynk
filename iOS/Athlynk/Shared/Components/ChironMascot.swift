//
//  ChironMascot.swift
//  Shared animated centaur mascot. Uses ChironCentaur asset when present,
//  falls back to a styled SF Symbol placeholder.
//

import SwiftUI

struct ChironMascot: View {
    var speak: Int
    var reduceMotion: Bool
    var size: CGFloat = 150

    @State private var aura = false
    @State private var ring = 0.0
    @State private var bob = false
    @State private var pop: CGFloat = 1

    private let seal = LinearGradient(
        colors: [Color(hex: 0xA78554), Color(hex: 0x8A6A3A), Color(hex: 0x5E4824)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    private var artwork: Image? {
        #if canImport(UIKit)
        UIImage(named: "ChironCentaur").map(Image.init(uiImage:))
        #else
        nil
        #endif
    }

    var body: some View {
        let art = artwork
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [Palette.bronze.opacity(art == nil ? 0.32 : 0.22), .clear],
                                     center: .center, startRadius: 6, endRadius: size))
                .frame(width: size * 1.9, height: size * 1.9)
                .scaleEffect(aura ? 1.12 : 0.96)
                .opacity(aura ? 0.9 : 0.55)

            if art == nil {
                Circle()
                    .stroke(Palette.bronze.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [2, 8]))
                    .frame(width: size * 1.55, height: size * 1.55)
                    .rotationEffect(.degrees(ring))
            }

            if let artwork = art {
                artwork
                    .resizable().scaledToFit()
                    .frame(width: size * 1.18, height: size * 1.18)
                    .shadow(color: Color(hex: 0x5E4824, alpha: 0.45), radius: 20, y: 14)
                    .offset(y: bob ? -6 : 5)
                    .scaleEffect(pop)
            } else {
                ZStack {
                    Circle().fill(seal).frame(width: size, height: size)
                        .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1).padding(3))
                        .shadow(color: Color(hex: 0x5E4824, alpha: 0.5), radius: 20, y: 12)
                    Image(systemName: "figure.archery")
                        .font(.system(size: size * 0.5, weight: .black))
                        .foregroundStyle(Palette.void0)
                }
                .offset(y: bob ? -6 : 5)
                .scaleEffect(pop)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Chiron, la mascotte di Athlynk")
        .onAppear(perform: idle)
        .onChange(of: speak) {
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { pop = 1.12 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { pop = 1 }
            }
        }
    }

    private func idle() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { aura = true }
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { bob = true }
        withAnimation(.linear(duration: 26).repeatForever(autoreverses: false)) { ring = 360 }
    }
}
