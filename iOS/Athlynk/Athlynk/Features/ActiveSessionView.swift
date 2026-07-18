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
    @Published var setOverrides: [String: Int] = [:] // exercise key → set count
    @Published var shakeTrigger: [String: Int] = [:] // set key → shake count
    @Published var invalidFields: Set<String> = []   // "reps-we-2-1", …

    // Session-only plan deviations (the assigned plan is never modified)
    @Published var substitutions: [String: SubstituteExerciseDTO] = [:] // ex key → substitute
    @Published var removedIds: Set<String> = []

    init(assignmentId: Int, day: WorkoutDayDTO) {
        self.assignmentId = assignmentId
        self.day = day
    }

    func key(_ ex: SessionExerciseDTO, _ s: Int) -> String { "\(ex.id)-\(s)" }

    func setsForExercise(_ ex: SessionExerciseDTO) -> Int {
        setOverrides[ex.id] ?? ex.sets
    }

    func addSet(_ ex: SessionExerciseDTO) {
        let n = setsForExercise(ex)
        setOverrides[ex.id] = n + 1
        entries[key(ex, n + 1)] = SetEntry(reps: ex.reps, load: fmtLoad(ex.loadValue))
    }

    func removeSet(_ ex: SessionExerciseDTO) {
        let n = setsForExercise(ex)
        guard n > 1 else { return }
        entries.removeValue(forKey: key(ex, n))
        setOverrides[ex.id] = n - 1
    }

    private func fmtLoad(_ v: Double?) -> String {
        guard let v else { return "" }
        return v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }

    /// Exercises still in play for this session (removed ones don't count).
    var activeExercises: [SessionExerciseDTO] {
        exercises.filter { !removedIds.contains($0.id) }
    }

    func isRemoved(_ ex: SessionExerciseDTO) -> Bool { removedIds.contains(ex.id) }
    func displayName(_ ex: SessionExerciseDTO) -> String { substitutions[ex.id]?.name ?? ex.name }

    var doneCount: Int {
        activeExercises.reduce(0) { count, ex in
            count + (1...max(setsForExercise(ex), 1)).filter {
                entries[key(ex, $0)]?.done == true
            }.count
        }
    }

    var totalSets: Int { activeExercises.reduce(0) { $0 + setsForExercise($1) } }
    var progress: Double { totalSets == 0 ? 0 : Double(doneCount) / Double(totalSets) }

    var incompleteExerciseCount: Int {
        activeExercises.filter { ex in
            let n = setsForExercise(ex)
            return !(1...max(n, 1)).contains { entries[key(ex, $0)]?.done == true }
        }.count
    }

    func start() async {
        loading = true; error = nil
        do {
            let s = try await APIClient.shared.sessionStart(assignmentId: assignmentId, dayId: day.id)
            sessionId = s.sessionId
            exercises = s.exercises
            for ex in s.exercises {
                if ex.removed { removedIds.insert(ex.id) }
                if let sub = ex.substitutedWith { substitutions[ex.id] = sub }
                let defLoad = fmtLoad(ex.loadValue)
                for n in 1...max(ex.sets, 1) {
                    entries[key(ex, n)] = SetEntry(reps: ex.reps, load: defLoad)
                }
            }
            for sl in s.setsLogged {
                entries["\(sl.exerciseKey)-\(sl.setNumber)"] = SetEntry(
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

    // MARK: Session-only add / remove / substitute

    private func pushOverrides() async {
        guard let sid = sessionId else { return }
        var removed: [Int] = []
        var substituted: [Int: Int] = [:]
        var added: [Int] = []
        for ex in exercises {
            if let weId = ex.workoutExerciseId {
                if removedIds.contains(ex.id) { removed.append(weId) }
                if let sub = substitutions[ex.id] { substituted[weId] = sub.id }
            } else if ex.added, let exId = ex.exerciseId {
                added.append(exId)
            }
        }
        try? await APIClient.shared.setSessionOverrides(
            sessionId: sid, removed: removed, substituted: substituted, added: added)
    }

    func addExercise(_ item: ExerciseSearchItemDTO) {
        let ex = SessionExerciseDTO(addedExerciseId: item.id, name: item.name,
                                    targetMuscleGroup: item.primaryMuscle,
                                    coverImageUrl: item.coverImageUrl, demoGifUrl: item.demoGifUrl)
        guard !exercises.contains(where: { $0.id == ex.id }) else { return }
        exercises.append(ex)
        for n in 1...max(ex.sets, 1) {
            entries[key(ex, n)] = SetEntry(reps: ex.reps, load: "")
        }
        Haptics.thud()
        Task { await pushOverrides() }
    }

    func substitute(_ ex: SessionExerciseDTO, with item: ExerciseSearchItemDTO) {
        substitutions[ex.id] = SubstituteExerciseDTO(id: item.id, name: item.name)
        Haptics.thud()
        Task { await pushOverrides() }
    }

    func undoSubstitute(_ ex: SessionExerciseDTO) {
        substitutions.removeValue(forKey: ex.id)
        Task { await pushOverrides() }
    }

    func removeExercise(_ ex: SessionExerciseDTO) {
        if ex.added {
            exercises.removeAll { $0.id == ex.id }
        } else {
            removedIds.insert(ex.id)
        }
        Haptics.thud()
        Task { await pushOverrides() }
    }

    func restoreExercise(_ ex: SessionExerciseDTO) {
        removedIds.remove(ex.id)
        Task { await pushOverrides() }
    }

    func toggle(_ ex: SessionExerciseDTO, set n: Int) async {
        guard let sid = sessionId else { return }
        let k = key(ex, n)
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
            RestTimerManager.shared.start(seconds: rec, exerciseName: displayName(ex))
        }
        let sub = substitutions[ex.id]
        do {
            try await APIClient.shared.logSet(
                sessionId: sid,
                workoutExerciseId: ex.workoutExerciseId,
                addedExerciseId: ex.added ? ex.exerciseId : nil,
                setNumber: n,
                reps: Int(e.reps), load: Double(e.load.replacingOccurrences(of: ",", with: ".")),
                loadUnit: ex.loadUnit ?? "KG", rpe: Int(e.rpe), completed: e.done,
                isExtraSet: ex.added || n > ex.sets,
                substituted: !ex.added && sub != nil,
                actualExerciseId: ex.added ? ex.exerciseId : sub?.id)
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
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var burst = 0
    @State private var appear = false
    @State private var keyboardShown = false
    @State private var showFinishConfirm = false
    @State private var showAddPicker = false
    @State private var substituteTarget: SessionExerciseDTO?
    @State private var detailTarget: SessionExerciseDTO?
    @EnvironmentObject private var confirmCenter: ConfirmCenter

    init(assignmentId: Int, day: WorkoutDayDTO) {
        _vm = StateObject(wrappedValue: ActiveSessionVM(assignmentId: assignmentId, day: day))
    }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.magenta, Palette.violet, Palette.cyan, Palette.magenta])
            if vm.loading {
                ActiveSessionSkeleton()
            } else if let error = vm.error, vm.sessionId == nil {
                EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.danger).padding(22)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        header.revealUp(appear, index: 0)
                        ForEach(Array(vm.exercises.enumerated()), id: \.element.id) { i, ex in
                            Group {
                                if vm.isRemoved(ex) {
                                    removedBlock(ex)
                                } else {
                                    exerciseBlock(ex)
                                }
                            }
                            .revealUp(appear, index: i + 1)
                        }
                        addExerciseButton.revealUp(appear, index: vm.exercises.count + 1)
                        finishButtons.revealUp(appear, index: vm.exercises.count + 2)
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
        .onChange(of: vm.loading) { _, l in if !l { withAnimation { appear = true } } }
        .onAppear { app.tabBarHidden = true }
        .onDisappear { app.tabBarHidden = false }
        .onChange(of: vm.finished) { _, done in if done { burst += 1 } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardShown = false
        }
        .sheet(isPresented: $showAddPicker) {
            SessionExercisePickerSheet(title: "Aggiungi esercizio", accent: Palette.primary) { item in
                vm.addExercise(item)
            }
        }
        .sheet(item: $substituteTarget) { ex in
            SubstitutePickerSheet(forExercise: ex,
                                  catalogExerciseId: ex.exerciseCatalogId ?? ex.exerciseId,
                                  accent: Palette.control) { item in
                vm.substitute(ex, with: item)
            }
        }
        .sheet(item: $detailTarget) { ex in
            ExerciseCatalogDetailSheet(exerciseId: ex.exerciseCatalogId ?? ex.exerciseId ?? 0,
                                       fallbackName: ex.name, accent: Palette.magenta)
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
        let sub = vm.substitutions[ex.id]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Button {
                    Haptics.tap()
                    detailTarget = ex
                } label: {
                    ExerciseThumb(url: ex.coverImageUrl, size: 40)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.displayName(ex)).font(Typo.display(20)).foregroundStyle(Palette.textHi)
                    if sub != nil {
                        Text(ex.name)
                            .font(Typo.body(12)).strikethrough()
                            .foregroundStyle(Palette.textLow)
                    }
                    HStack(spacing: 6) {
                        if let m = ex.targetMuscleGroup, !m.isEmpty {
                            Text(m.uppercased()).font(Typo.mono(9, .bold)).tracking(1).foregroundStyle(Palette.textLow)
                        }
                        if ex.added {
                            Text("AGGIUNTO").font(Typo.mono(8, .bold)).tracking(1)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Palette.primary))
                                .foregroundStyle(Palette.void0)
                        }
                        if sub != nil {
                            Text("SOSTITUITO").font(Typo.mono(8, .bold)).tracking(1)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Palette.control))
                                .foregroundStyle(Palette.void0)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Menu {
                        if !ex.added {
                            if sub == nil {
                                Button {
                                    substituteTarget = ex
                                } label: {
                                    Label("Sostituisci esercizio", systemImage: "arrow.left.arrow.right")
                                }
                            } else {
                                Button {
                                    vm.undoSubstitute(ex)
                                } label: {
                                    Label("Ripristina \(ex.name)", systemImage: "arrow.uturn.backward")
                                }
                            }
                        }
                        Button(role: .destructive) {
                            Task {
                                if await confirmCenter.confirm(.init(
                                    title: "Eliminare esercizio?",
                                    subtitle: "\(ex.name) verrà rimosso solo da questa sessione. La scheda assegnata dal coach non cambia.",
                                    icon: "trash")) {
                                    vm.removeExercise(ex)
                                }
                            }
                        } label: {
                            Label("Elimina da questa sessione", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Palette.textMid)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    if let rec = ex.recoverySeconds {
                        Label("\(rec)s", systemImage: "timer")
                            .font(Typo.mono(11, .bold)).foregroundStyle(Palette.textMid)
                    }
                    // TUT (tempo) — only when the coach set it for this exercise.
                    if let t = ex.tempo?.trimmingCharacters(in: .whitespaces), !t.isEmpty {
                        Label(t, systemImage: "metronome")
                            .font(Typo.mono(11, .bold)).foregroundStyle(Palette.textMid)
                    }
                    // Target RPE/RIR the coach prescribed — distinct from the RPE
                    // the athlete types per set below (that's the *actual* value).
                    if let rpe = ex.rpe {
                        Label("RPE \(rpe)", systemImage: "flame")
                            .font(Typo.mono(11, .bold)).foregroundStyle(Palette.textMid)
                    }
                    if let rir = ex.rir {
                        Label("RIR \(rir)", systemImage: "gauge.medium")
                            .font(Typo.mono(11, .bold)).foregroundStyle(Palette.textMid)
                    }
                }
            }

            // Coach note — shown only when set for this exercise.
            if let note = ex.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.magenta)
                    Text(note).font(Typo.body(13)).foregroundStyle(Palette.textMid)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.magenta.opacity(0.08)))
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

    // MARK: Removed exercise (slim, restorable)

    private func removedBlock(_ ex: SessionExerciseDTO) -> some View {
        HStack(spacing: 10) {
            Text(ex.name)
                .font(Typo.body(15, .semibold)).strikethrough()
                .foregroundStyle(Palette.textLow)
            Text("RIMOSSO").font(Typo.mono(8, .bold)).tracking(1)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().stroke(Palette.line, lineWidth: 1))
                .foregroundStyle(Palette.textLow)
            Spacer()
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    vm.restoreExercise(ex)
                }
            } label: {
                Label("Ripristina", systemImage: "arrow.uturn.backward")
                    .font(Typo.mono(11, .bold)).tracking(1)
                    .foregroundStyle(Palette.control)
            }
            .buttonStyle(.plain)
        }
        .padding(14).voltPanel(Palette.line)
        .opacity(0.75)
    }

    // MARK: Add exercise (session-only)

    private var addExerciseButton: some View {
        Button {
            Haptics.tap()
            showAddPicker = true
        } label: {
            Label("Aggiungi esercizio", systemImage: "plus")
                .font(Typo.mono(12, .bold)).tracking(1)
                .foregroundStyle(Palette.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Palette.primary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5]))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Set row

    private func setRow(_ ex: SessionExerciseDTO, _ n: Int) -> some View {
        let k = vm.key(ex, n)
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
