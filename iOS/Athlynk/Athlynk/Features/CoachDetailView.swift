//
//  CoachDetailView.swift
//  Stitch "Profilo Coach": full profile of one of the athlete's coaches —
//  avatar, role, location, experience, bio, certifications and social links.
//  Backed by GET /api/v1/coaches/<id> (CoachProfile, IDOR-guarded server-side).
//

import SwiftUI

struct CoachDetailView: View {
    let coachId: Int

    @State private var coach: CoachDetailDTO?
    @State private var loading = true
    @State private var error: String?
    @State private var appear = false

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.violet, Palette.cyan, Palette.bronze, Palette.violet])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if loading {
                        CoachDetailSkeleton()
                    } else if let error {
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.danger)
                    } else if let coach {
                        hero(coach).revealUp(appear, index: 0)
                        if coach.yearsExperience != nil || coach.city != nil {
                            statsRow(coach).revealUp(appear, index: 1)
                        }
                        if let bio = bioText(coach) {
                            section("BIOGRAFIA", body: bio).revealUp(appear, index: 2)
                        }
                        if let cert = coach.certifications, !cert.isEmpty {
                            section("CERTIFICAZIONI", body: cert).revealUp(appear, index: 3)
                        }
                        socials(coach).revealUp(appear, index: 4)
                    } else {
                        EmptyPanel(icon: "person.crop.circle.badge.questionmark", text: "Coach non trovato.")
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 40)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
        .onChange(of: loading) { _, l in if !l { appear = true } }
    }

    private func hero(_ coach: CoachDetailDTO) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Palette.bronze)
                    .frame(width: 110, height: 110).neonGlow(Palette.bronze, radius: 14)
                if let u = coach.profileImageUrl, let url = URL(string: u) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            Text(initials(coach)).font(Typo.poster(40)).foregroundStyle(Palette.void0)
                        }
                    }
                    .frame(width: 110, height: 110).clipShape(Circle())
                } else {
                    Text(initials(coach)).font(Typo.poster(40)).foregroundStyle(Palette.void0)
                }
            }
            Text(coach.fullName).font(Typo.poster(32)).foregroundStyle(Palette.textHi)
                .multilineTextAlignment(.center)
            Text((coach.specialization ?? roleLabel(coach)).uppercased())
                .font(Typo.mono(10, .bold)).tracking(2).foregroundStyle(Palette.violet)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func statsRow(_ coach: CoachDetailDTO) -> some View {
        HStack(spacing: 12) {
            if let y = coach.yearsExperience {
                statCard("\(y)", "ANNI ESPERIENZA", Palette.bronze)
            }
            if let city = coach.city, !city.isEmpty {
                statCard(city, "CITTÀ", Palette.cyan)
            }
        }
    }

    private func statCard(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value).font(Typo.display(20)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .voltPanel(color.opacity(0.35))
    }

    private func section(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).voltEyebrow()
            Text(body).font(Typo.body(14)).foregroundStyle(Palette.textHi)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).voltPanel(Palette.violet.opacity(0.3))
    }

    @ViewBuilder
    private func socials(_ coach: CoachDetailDTO) -> some View {
        let links: [(String, String?)] = [
            ("Instagram", coach.socialInstagram),
            ("YouTube", coach.socialYoutube),
            ("Sito web", coach.socialWebsite),
        ].filter { ($0.1 ?? "").isEmpty == false }
        if !links.isEmpty {
            VStack(spacing: 10) {
                ForEach(links, id: \.0) { label, url in
                    if let url, let link = URL(string: url) {
                        Link(destination: link) {
                            HStack(spacing: 12) {
                                Image(systemName: "link").font(.system(size: 15, weight: .black))
                                    .foregroundStyle(Palette.cyan)
                                Text(label).font(Typo.display(16)).foregroundStyle(Palette.textHi)
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .black))
                                    .foregroundStyle(Palette.cyan)
                            }
                            .padding(14).voltPanel(Palette.cyan.opacity(0.3))
                        }
                    }
                }
            }
        }
    }

    private func bioText(_ coach: CoachDetailDTO) -> String? {
        let b = (coach.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let d = (coach.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let merged = [b, d].filter { !$0.isEmpty }.joined(separator: "\n\n")
        return merged.isEmpty ? nil : merged
    }

    private func roleLabel(_ coach: CoachDetailDTO) -> String {
        switch (coach.professionalType ?? "").uppercased() {
        case "ALLENATORE": return "Allenatore"
        case "NUTRIZIONISTA": return "Nutrizionista"
        default: return "Coach"
        }
    }

    private func initials(_ coach: CoachDetailDTO) -> String {
        let f = coach.firstName.first.map(String.init) ?? ""
        let l = coach.lastName.first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "C" : s
    }

    private func load() async {
        loading = true; error = nil
        do { coach = try await APIClient.shared.coach(id: coachId) }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
