import SwiftUI

struct RestTimerOverlay: View {
    @ObservedObject private var timer = RestTimerManager.shared

    private var progress: Double {
        timer.totalSeconds > 0 ? Double(timer.secondsLeft) / Double(timer.totalSeconds) : 0
    }

    private var timeString: String {
        let s = timer.secondsLeft
        return s >= 60 ? "\(s / 60):\(String(format: "%02d", s % 60))" : "\(s)s"
    }

    var body: some View {
        if timer.isRunning {
            VStack {
                Spacer()
                pill
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .move(edge: .bottom).combined(with: .opacity)
                    ))
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: timer.isRunning)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var pill: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.cyan)

                VStack(alignment: .leading, spacing: 1) {
                    Text("RECUPERO")
                        .font(Typo.mono(8, .bold)).tracking(2)
                        .foregroundStyle(Palette.textLow)
                    Text(timer.exerciseName)
                        .font(Typo.mono(11, .semibold))
                        .foregroundStyle(Palette.textMid)
                        .lineLimit(1)
                }

                Spacer()

                Text(timeString)
                    .font(Typo.mono(28, .bold))
                    .foregroundStyle(Palette.cyan)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeInOut(duration: 0.3), value: timer.secondsLeft)

                Button { timer.cancel() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.textLow)
                        .padding(8)
                        .background(Circle().fill(Palette.void2))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.void2).frame(height: 2)
                    Rectangle()
                        .fill(Palette.cyan)
                        .frame(width: geo.size.width * progress, height: 2)
                        .animation(.linear(duration: 1), value: progress)
                }
            }
            .frame(height: 2)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.void1)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Palette.line, lineWidth: 1)
                )
                .shadow(color: Color(hex: 0x14110D, alpha: 0.13), radius: 20, y: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
