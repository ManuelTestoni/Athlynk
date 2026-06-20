//
//  ActiveSessionView.swift
//  Stitch "Sessione Attiva": live training logger. Starts a WorkoutSession,
//  logs each set (reps · load · RPE) as you tick it off, then finishes the
//  session. Backed by POST /api/v1/sessions/{start,log-set,finish}.
//

import SwiftUI
import Combine

// MARK: - Shake

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(.init(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}

// MARK: - SetEntry

struct SetEntry {
    var reps = ""
    var load = ""
    var rpe = ""
    var done = false
}

// MARK: - ViewModel

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
    @Published var setOverrides: [Int: Int] = [:]    // exerciseId → set count
    @Published var shakeTrigger: [String: Int] = [:] // set key → shake count
    @Published var invalidFields: Set<String> = []   // "reps-2-1", "load-2-1", "rpe-2-1"

    init(assignmentId: Int, day: WorkoutDayDTO) {
        self.assignmentId = assignmentId
        self.day = day
    }

    func key(_ ex: Int, _ s: Int) -> String { "\(ex)-\(s)" }

    func setsForExercise(_ ex: SessionExerciseDTO) -> Int {
        setOverrides[ex.workoutExerciseId] ?? ex.sets
    }

    func addSet(_ ex: SessionExerciseDTO) {
        let n = setsForExercise(ex)
        setOverrides[ex.workoutExerciseId] = n + 1
        entries[key(ex.workoutExerciseId, n + 1)] = SetEntry(reps: ex.reps, load: fmtLoad(ex.loadValue))
    }

    func removeSet(_ ex: SessionExerciseDTO) {
        let n = setsForExercise(ex)
        guard n > 1 else { return }
        entries.removeValue(forKey: key(ex.workoutExerciseId, n))
        setOverrides[ex.workoutExerciseId] = n - 1
    }

    private func fmtLoad(_ v: Double?) -> String {
        guard let v else { return "" }
        return v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }

    var doneCount: Int {
        exercises.reduce(0) { count, ex in
            count + (1...max(setsForExercise(ex), 1)).filter {
                entries[key(ex.workoutExerciseId, $0)]?.done == true
            }.count
        }
    }

    var totalSets: Int { exercises.reduce(0) { $0 + setsForExercise($1) } }
    var progress: Double { totalSets == 0 ? 0 : Double(doneCount) / Double(totalSets) }

    var incompleteExerciseCount: Int {
        exercises.filter { ex in
            let n = setsForExercise(ex)
            return !(1...max(n, 1)).contains { entries[key(ex.workoutExerciseId, $0)]?.done == true }
        }.count
    }

    func start() async {
        loading = true; error = nil
        do {
            let s = try await APIClient.shared.sessionStart(assignmentId: assignmentId, dayId: day.id)
            sessionId = s.sessionId
            exercises = s.exercises
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

        if !e.done {
            var invalid = Set<String>()
            if e.reps.trimmingCharacters(in: .whitespaces).isEmpty { invalid.insert("reps-\(k)") }
            if e.load.trimmingCharacters(in: .whitespaces).isEmpty { invalid.insert("load-\(k)") }
            if e.rpe.trimmingCharacters(in: .whitespaces).isEmpty  { invalid.insert("rpe-\(k)") }
            if !invalid.isEmpty {
                invalidFields = invalid
                shakeTrigger[k, default: 0] += 1
                Haptics.soft()
                return
            }
        }
        invalidFields = []
        e.done.toggle()
        entries[k] = e
        Haptics.thud()
        if e.done, let rec = ex.recoverySeconds, rec > 0 {
            RestTimerManager.shared.start(seconds: rec, exerciseName: ex.name)
        }
        do {
            try await APIClient.shared.logSet(
                sessionId: sid, exerciseId: ex.workoutExerciseId, setNumber: n,
                reps: Int(e.reps), load: Double(e.load.replacingOccurrences(of: ",", with: ".")),
                loadUnit: ex.loadUnit ?? "KG", rpe: Int(e.rpe), completed: e.done)
        } catch {
            e.done.toggle(); entries[k] = e
        }
    }

    func finish(interrupted: Bool) async {
        guard let sid = sessionId else { return }
        RestTimerManager.shared.cancel()
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

// MARK: - View

struct ActiveSessionView: View {
    @StateObject private var vm: ActiveSessionVM
    @Environment(\.dismiss) private var dismiss
    @State private var burst = 0
    @State private var keyboardShown = false
    @State private var showFinishConfirm = false

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
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    })
                }
                .scrollDismissesKeyboard(.interactively)
            }
            ParticleBurst(trigger: burst)
            RestTimerOverlay()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(keyboardShown ? .hidden : .visible, for: .navigationBar)
        .task { await vm.start() }
        .onChange(of: vm.finished) { _, done in if done { burst += 1 } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardShown = false
        }
        .alert("Sessione incompleta", isPresented: $showFinishConfirm) {
            Button("Termina comunque", role: .destructive) {
                Task { await vm.finish(interrupted: false) }
            }
            Button("Continua", role: .cancel) {}
        } message: {
            Text("Hai ancora \(vm.incompleteExerciseCount) \(vm.incompleteExerciseCount == 1 ? "esercizio" : "esercizi") da completare. I dati non compilati non verranno salvati.")
        }
    }

    // MARK: Header

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

    // MARK: Exercise block

    private func exerciseBlock(_ ex: SessionExerciseDTO) -> some View {
        let n = vm.setsForExercise(ex)
        return VStack(alignment: .leading, spacing: 12) {
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

            HStack(spacing: 8) {
                Text("SET").frame(width: 34, alignment: .leading)
                Text("REPS").frame(maxWidth: .infinity)
                Text("CARICO").frame(maxWidth: .infinity)
                Text("RPE").frame(width: 52)
                Text("").frame(width: 34)
            }
            .font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(Palette.textLow)

            ForEach(1...max(n, 1), id: \.self) { i in setRow(ex, i) }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { vm.addSet(ex) }
                } label: {
                    Label("Serie", systemImage: "plus")
                        .font(Typo.mono(11, .bold)).tracking(1)
                        .foregroundStyle(Palette.magenta)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().stroke(Palette.magenta, lineWidth: 1))
                }
                if n > 1 {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { vm.removeSet(ex) }
                    } label: {
                        Label("Rimuovi", systemImage: "minus")
                            .font(Typo.mono(11, .bold)).tracking(1)
                            .foregroundStyle(Palette.textLow)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().stroke(Palette.line, lineWidth: 1))
                    }
                }
                Spacer()
            }
            .buttonStyle(.plain)
        }
        .padding(16).voltPanel(Palette.magenta.opacity(0.45))
    }

    // MARK: Set row

    private func setRow(_ ex: SessionExerciseDTO, _ n: Int) -> some View {
        let k = vm.key(ex.workoutExerciseId, n)
        let binding = Binding<SetEntry>(
            get: { vm.entries[k] ?? SetEntry() },
            set: { vm.entries[k] = $0 }
        )
        let done = binding.wrappedValue.done
        let shakeVal = vm.shakeTrigger[k] ?? 0
        return HStack(spacing: 8) {
            Text("\(n)").font(Typo.mono(14, .black)).foregroundStyle(Palette.magenta)
                .frame(width: 34, alignment: .leading)
            field(binding.reps, fieldKey: "reps-\(k)", keyboard: .numberPad)
            field(binding.load, fieldKey: "load-\(k)", keyboard: .decimalPad)
            field(binding.rpe,  fieldKey: "rpe-\(k)",  keyboard: .numberPad, width: 52)
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
        .modifier(ShakeEffect(animatableData: CGFloat(shakeVal)))
        .animation(.default, value: shakeVal)
    }

    // MARK: Field

    private func field(_ text: Binding<String>, fieldKey: String, keyboard: UIKeyboardType, width: CGFloat? = nil) -> some View {
        let isInvalid = vm.invalidFields.contains(fieldKey)
        return TextField("", text: text)
            .font(Typo.mono(14, .semibold)).foregroundStyle(Palette.textHi).tint(Palette.magenta)
            .multilineTextAlignment(.center).keyboardType(keyboard)
            .padding(.vertical, 8)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isInvalid ? Palette.magenta.opacity(0.12) : Palette.void2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isInvalid ? Palette.magenta : Color.clear, lineWidth: 1.5)
                    )
            )
            .onChange(of: text.wrappedValue) { _, _ in
                vm.invalidFields.remove(fieldKey)
            }
    }

    // MARK: Finish buttons

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
                    if vm.incompleteExerciseCount > 0 {
                        showFinishConfirm = true
                    } else {
                        Task { await vm.finish(interrupted: false) }
                    }
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
