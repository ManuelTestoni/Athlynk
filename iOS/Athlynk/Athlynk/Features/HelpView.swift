//
//  HelpView.swift
//  Stitch "Aiuto e Supporto": static FAQ + contact entry points. No API — the
//  content is bundled; "Scrivi al coach" routes the user to the messages tab.
//

import SwiftUI

struct HelpView: View {
    @State private var expanded: Set<Int> = []

    private let faqs: [(q: String, a: String)] = [
        ("Come inizio un allenamento?",
         "Vai nella sezione Train, apri la tua scheda e tocca un giorno per avviare la sessione."),
        ("Come compilo un check?",
         "Nella sezione Check trovi i check-in in attesa. Toccane uno e segui le indicazioni del coach."),
        ("Posso modificare il mio piano?",
         "I piani sono assegnati dal tuo coach. Per richieste di modifica, scrivigli dalla sezione Messaggi."),
        ("Come aggiorno i miei dati?",
         "Profilo → Modifica profilo: puoi aggiornare altezza, obiettivo, livello di attività e contatti."),
        ("Come gestisco le notifiche?",
         "Profilo → Impostazioni: attiva o disattiva le email per piani e check."),
    ]

    @State private var appear = false

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.cyan, Palette.violet, Palette.bronze, Palette.cyan])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header.revealUp(appear, index: 0)
                    Text("DOMANDE FREQUENTI").voltEyebrow().revealUp(appear, index: 1)
                    ForEach(Array(faqs.enumerated()), id: \.offset) { i, item in
                        faqCard(i, item.q, item.a).revealUp(appear, index: min(i, 6) + 2)
                    }
                    GreekDivider(color: Palette.cyan).padding(.top, 4)
                    Text("CONTATTI").voltEyebrow()
                    contactCard
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, AppLayout.tabBarClearance)
            }
        }
        .navigationTitle("Aiuto")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { appear = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUPPORTO").font(Typo.mono(10, .bold)).tracking(3).foregroundStyle(Palette.cyan)
            Text("Come possiamo aiutarti?").font(Typo.poster(32)).foregroundStyle(Palette.textHi)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Palette.cyan).frame(height: 1).opacity(0.5)
        }
    }

    private func faqCard(_ i: Int, _ q: String, _ a: String) -> some View {
        let open = expanded.contains(i)
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                if open { expanded.remove(i) } else { expanded.insert(i) }
            }
            Haptics.tap()
        } label: {
            VStack(alignment: .leading, spacing: open ? 10 : 0) {
                HStack(alignment: .top, spacing: 12) {
                    Text(q).font(Typo.display(16)).foregroundStyle(Palette.textHi)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: open ? "minus" : "plus")
                        .font(.system(size: 14, weight: .black)).foregroundStyle(Palette.cyan)
                }
                if open {
                    Text(a).font(Typo.body(14)).foregroundStyle(Palette.textMid)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16).voltPanel(Palette.cyan.opacity(0.3))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var contactCard: some View {
        VStack(spacing: 10) {
            contactRow("bubble.left.and.bubble.right.fill", "Scrivi al tuo coach",
                       "Dalla sezione Messaggi", Palette.cyan)
            Button {
                if let url = URL(string: "mailto:info@athlynk.app?subject=Supporto%20Athlynk") {
                    UIApplication.shared.open(url)
                }
            } label: {
                contactRow("envelope.fill", "info@athlynk.app",
                           "Risposta entro 24-48h", Palette.bronze)
            }
            .buttonStyle(.plain)
        }
    }

    private func contactRow(_ icon: String, _ title: String, _ subtitle: String, _ color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 18, weight: .black)).foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.display(16)).foregroundStyle(Palette.textHi)
                Text(subtitle).font(Typo.body(12)).foregroundStyle(Palette.textMid)
            }
            Spacer()
        }
        .padding(16).voltPanel(color.opacity(0.3))
    }
}
