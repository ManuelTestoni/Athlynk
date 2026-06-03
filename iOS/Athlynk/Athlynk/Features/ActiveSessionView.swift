//
//  ActiveSessionView.swift
//  Stitch "Sessione Attiva": live training logger. Starts a WorkoutSession,
//  logs each set (reps · load · RPE) as you tick it off, then finishes the
//  session. Backed by POST /api/v1/sessions/{start,log-set,finish}.
//

import SwiftUI
import Combine

struct SetEntry {
    var reps = ""
    var load = ""
    var rpe = ""
    var done = false
}

@MainActor
final class ActiveSessionVM: ObservableObject {
    let assignmentId: Int
    let day: WorkoutDayDTO

    @Published var loading = true
    @Published var error: String?
    @Published var sessionId: Int?
    @Published var exercises: [SessionExerciseDTO] = []
    @Published var entries: [String: SetEntry] = [:]
    @Published var finishing = false
    @Published var finished = false

    init(assignmentId: Int, day: WorkoutDayDTO) {
        self.assignmentId = assignmentId
        self.day = day
    }

    func key(_ ex: Int, _ s: Int) -> String { "\(ex)-\(s)" }

    private func fmtLoad(_ v: Double?) -> String {
        guard let v else { return "" }
        return v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }

    var doneCount: Int { entries.values.filter { $0.done }.count }
    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }
    var progress: Double { totalSets == 0 ? 0 : Double(doneCount) / Double(totalSets) }

    func start() async {
        loading = true; error = nil
        do {
            let s = try await APIClient.shared.sessionStart(assignmentId: assignmentId, dayId: day.id)
            sessionId = s.sessionId
            exercises = s.exercises
            // Seed default reps/load per set, then overlay any already-logged sets.
            for ex in s.exercises {
                let defLoad = fmtLoad(ex.loadValue)
                for n in 1...max(ex.sets, 1) {
                    entries[key(ex.workoutExerciseId, n)] = SetEntry(reps: ex.reps, load: defLoad)
                }
            }
            for sl in s.setsLogged {
                entries[key(sl.workoutExerciseId, sl.setNumber)] = SetEntry(
                    reps: sl.repsDone.map { "\($0)" } ?? "",
                    load: fmtLoad(sl.loadUsed),
                    rpe: sl.rpe.map { "\($0)" } ?? "",
                    done: sl.completed
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    func toggle(_ ex: SessionExerciseDTO, set n: Int) async {
        guard let sid = sessionId else { return }
        let k = key(ex.workoutExerciseId, n)
        var e = entries[k] ?? SetEntry()
        e.done.toggle()
        entries[k] = e
        Haptics.thud()
        do {
            try await APIClient.shared.logSet(
                sessionId: sid, exerciseId: ex.workoutExerciseId, setNumber: n,
                reps: Int(e.reps), load: Double(e.load.replacingOccurrences(of: ",", with: ".")),
                loadUnit: ex.loadUnit ?? "KG", rpe: Int(e.rpe), completed: e.done)
        } catch {
            // Revert on failure.
            e.done.toggle(); entries[k] = e
        }
    }

    func finish(interrupted: Bool) async {
        guard let sid = sessionId else { return }
        finishing = true
        do {
            try await APIClient.shared.finishSession(sessionId: sid, notes: "", interrupted: interrupted)
            Haptics.success()
            finished = true
        } catch {
            self.error = error.localizedDescription
        }
        finishing = false
    }
}

struct ActiveSessionView: View {
    @StateObject private var vm: ActiveSessionVM
    @Environment(\.dismiss) private var dismiss
    @State private var burst = 0

    init(assignmentId: Int, day: WorkoutDayDTO) {
        _vm = StateObject(wrappedValue: ActiveSessionVM(assignmentId: assignmentId, day: day))
    }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.magenta, Palette.violet, Palette.cyan, Palette.magenta])
            if vm.loading {
                LoadingPanel(text: "Avvio sessione…")
            } else if let error = vm.error, vm.sessionId == nil {
                EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.magenta).padding(22)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        ForEach(vm.exercises) { ex in exerciseBlock(ex) }
                        finishButtons
                    }
                    .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 50)
                }
            }
            ParticleBurst(trigger: burst)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await vm.start() }
        .onChange(of: vm.finished) { _, done in if done { burst += 1 } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SESSIONE ATTIVA").font(Typo.mono(10, .bold)).tracking(3).foregroundStyle(Palette.magenta)
            HStack(alignment: .center) {
                VStack(alignment: .leading) {
                    Text(vm.day.label).font(Typo.poster(34)).foregroundStyle(Palette.textHi)
                    Text("\(vm.doneCount)/\(vm.totalSets) serie completate")
                        .font(Typo.mono(12, .bold)).foregroundStyle(Palette.magenta)
                }
                Spacer()
                RingGauge(progress: vm.progress, color: Palette.magenta, lineWidth: 9,
                          value: "\(Int(vm.progress * 100))")
                    .frame(width: 78, height: 78)
            }
            Rectangle().fill(Palette.magenta).frame(height: 1).opacity(0.5)
        }
    }

    private func exerciseBlock(_ ex: SessionExerciseDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.name).font(Typo.display(20)).foregroundStyle(Palette.textHi)
                    if let m = ex.targetMuscleGroup, !m.isEmpty {
                        Text(m.uppercased()).font(Typo.mono(9, .bold)).tracking(1).foregroundStyle(Palette.textLow)
                    }
                }
                Spacer()
                if let rec = ex.recoverySeconds {
                    Label("\(rec)s", systemImage: "timer")
                        .font(Typo.mono(11, .bold)).foregroundStyle(Palette.textMid)
                }
            }
            // Column headers
            HStack(spacing: 8) {
                Text("SET").frame(width: 34, alignment: .leading)
                Text("REPS").frame(maxWidth: .infinity)
                Text("CARICO").frame(maxWidth: .infinity)
                Text("RPE").frame(width: 52)
                Text("").frame(width: 34)
            }
            .font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(Palette.textLow)

            ForEach(1...max(ex.sets, 1), id: \.self) { n in setRow(ex, n) }
        }
        .padding(16).voltPanel(Palette.magenta.opacity(0.45))
    }

    private func setRow(_ ex: SessionExerciseDTO, _ n: Int) -> some View {
        let k = vm.key(ex.workoutExerciseId, n)
        let binding = Binding<SetEntry>(
            get: { vm.entries[k] ?? SetEntry() },
            set: { vm.entries[k] = $0 }
        )
        let done = binding.wrappedValue.done
        return HStack(spacing: 8) {
            Text("\(n)").font(Typo.mono(14, .black)).foregroundStyle(Palette.magenta)
                .frame(width: 34, alignment: .leading)
            field(binding.reps, keyboard: .numberPad)
            field(binding.load, keyboard: .decimalPad)
            field(binding.rpe, keyboard: .numberPad, width: 52)
            Button {
                Task { await vm.toggle(ex, set: n) }
            } label: {
                ZStack {
                    Circle().stroke(Palette.lime, lineWidth: 2).frame(width: 30, height: 30)
                    if done {
                        Circle().fill(Palette.lime).frame(width: 30, height: 30)
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .black))
                            .foregroundStyle(Palette.void0)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: 34)
        }
        .opacity(done ? 0.85 : 1)
    }

    private func field(_ text: Binding<String>, keyboard: UIKeyboardType, width: CGFloat? = nil) -> some View {
        TextField("", text: text)
            .font(Typo.mono(14, .semibold)).foregroundStyle(Palette.textHi).tint(Palette.magenta)
            .multilineTextAlignment(.center).keyboardType(keyboard)
            .padding(.vertical, 8)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.void2))
    }

    private var finishButtons: some View {
        VStack(spacing: 12) {
            if vm.finished {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 40, weight: .black))
                        .foregroundStyle(Palette.lime).neonGlow(Palette.lime, radius: 14)
                    Text("SESSIONE SALVATA").font(Typo.poster(26)).foregroundStyle(Palette.textHi)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24).voltPanel(Palette.lime.opacity(0.5))
                NeonButton(title: "Chiudi", icon: "xmark", color: Palette.magenta, filled: false) { dismiss() }
            } else {
                NeonButton(title: "Termina sessione", icon: "flag.checkered",
                           color: Palette.lime, loading: vm.finishing) {
                    Task { await vm.finish(interrupted: false) }
                }
                Button { Task { await vm.finish(interrupted: true); dismiss() } } label: {
                    Text("Interrompi").font(Typo.mono(12, .bold)).tracking(1).foregroundStyle(Palette.textLow)
                }
                .padding(.top, 2)
            }
        }
        .padding(.top, 8)
    }
}
