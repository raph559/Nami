import SwiftUI

/// Edits the viewer's AniList entry for an anime: status, progress and score.
struct ListEditorSheet: View {
    let media: Media
    /// The anime with its new entry, or with none once removed.
    let onSaved: (Media) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var status: ListStatus
    @State private var progress: Int
    /// Out of 10, by halves; 0 means not rated.
    @State private var score: Double
    @State private var saving = false
    @State private var error: String?
    @State private var confirmRemove = false

    init(media: Media, onSaved: @escaping (Media) -> Void) {
        self.media = media
        self.onSaved = onSaved
        let entry = media.mediaListEntry
        _status = State(initialValue: ListStatus(rawValue: entry?.status ?? "") ?? .PLANNING)
        _progress = State(initialValue: entry?.progress ?? 0)
        _score = State(initialValue: ((entry?.score ?? 0) / 5).rounded() / 2)
    }

    private var inList: Bool { media.mediaListEntry?.id != nil }

    /// Highest episode that can be set: the total, or what has aired so far.
    private var maxProgress: Int? { media.episodes ?? (media.nextAiringEpisode != nil ? media.availableEpisodes : nil) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        CoverImageView(url: media.coverImage?.large, corner: 4).frame(width: 48, height: 70)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(media.title.display).font(.headline).lineLimit(2)
                            Text(inList ? t("Dans ta liste", "In your list") : t("Pas encore dans ta liste", "Not in your list yet"))
                                .font(.caption).foregroundStyle(Nami.textSecondary)
                        }
                    }
                }
                Section(t("Statut", "Status")) {
                    Picker(t("Statut", "Status"), selection: Binding(get: { status }, set: setStatus)) {
                        ForEach(ListStatus.allCases) { s in
                            Label(s.label, systemImage: s.icon).tag(s)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    if !media.isMovie {
                        Stepper(value: Binding(get: { progress }, set: setProgress), in: 0...(maxProgress ?? 9999)) {
                            LabeledContent(t("Épisodes vus", "Episodes watched"),
                                           value: maxProgress.map { "\(progress) / \($0)" } ?? "\(progress)")
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent(t("Ta note", "Your score"),
                                       value: score == 0 ? t("Pas de note", "Not rated") : "\(Self.format(score)) / 10")
                        Slider(value: $score, in: 0...10, step: 0.5)
                            .accessibilityValue(score == 0 ? t("Pas de note", "Not rated") : "\(Self.format(score)) / 10")
                    }
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
                if inList {
                    Section {
                        Button(t("Retirer de ma liste", "Remove from my list"), role: .destructive) { confirmRemove = true }
                    }
                }
            }
            .disabled(saving)
            .navigationTitle(t("Ma liste", "My list"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Annuler", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button(inList ? t("Enregistrer", "Save") : t("Ajouter", "Add"), action: save).bold()
                    }
                }
            }
            .confirmationDialog(t("Retirer de ta liste ?", "Remove from your list?"), isPresented: $confirmRemove, titleVisibility: .visible) {
                Button(t("Retirer", "Remove"), role: .destructive, action: remove)
            } message: {
                Text(t("Ta progression et ta note pour \(media.title.display) seront effacées sur AniList.",
                       "Your progress and score for \(media.title.display) will be erased on AniList."))
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func setStatus(_ s: ListStatus) {
        status = s
        // Finishing an anime ticks off every episode.
        if s == .COMPLETED, let total = media.episodes { progress = total }
    }

    private func setProgress(_ p: Int) {
        progress = p
        // The last episode completes the anime, as the player does.
        if let total = media.episodes, p >= total, status == .CURRENT { status = .COMPLETED }
        if p > 0, status == .PLANNING { status = .CURRENT }
    }

    private func save() {
        saving = true
        error = nil
        Task {
            do {
                let entry = try await AniList.shared.saveEntry(media: media, status: status, progress: progress, score: score * 10)
                var updated = media
                updated.mediaListEntry = entry
                onSaved(updated)
                dismiss()
            } catch {
                saving = false
                self.error = t("L'enregistrement a échoué. Réessaie.", "Saving failed. Try again.")
            }
        }
    }

    private func remove() {
        guard let id = media.mediaListEntry?.id else { return }
        saving = true
        error = nil
        Task {
            do {
                try await AniList.shared.deleteEntry(id: id)
                var updated = media
                updated.mediaListEntry = nil
                onSaved(updated)
                dismiss()
            } catch {
                saving = false
                self.error = t("La suppression a échoué. Réessaie.", "Removing failed. Try again.")
            }
        }
    }

    static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: t(",", "."))
    }
}

/// The viewer's AniList profile and list, one status at a time.
struct LibraryView: View {
    @EnvironmentObject private var anilist: AniList
    @State private var lists: [ListStatus: [LibraryEntry]] = [:]
    @State private var status: ListStatus = .CURRENT
    @State private var loaded = false
    @State private var failed = false
    @State private var path: [MediaRoute] = []
    @State private var loginError: String?
    @Namespace private var ns

    private let columns = [GridItem(.adaptive(minimum: 105), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let viewer = anilist.viewer {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ProfileHeader(viewer: viewer)
                            statusChips
                            content
                        }
                        .padding(.bottom)
                    }
                    .ignoresSafeArea(edges: .top)
                    .refreshable { await load() }
                } else {
                    loggedOut
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MediaRoute.self) { r in
                MediaDetailView(media: r.media).zoomDestination(r.source, in: ns)
            }
            .task(id: "\(anilist.viewer?.id ?? 0)-\(anilist.listRevision)") { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        let entries = lists[status] ?? []
        if !loaded {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(0..<9, id: \.self) { _ in LoadingShape(height: 160) }
            }
            .padding(.horizontal)
        } else if failed {
            message(t("Ta liste n'a pas pu être chargée", "Your list couldn't be loaded"),
                    t("Impossible de joindre AniList. Vérifie ta connexion, puis réessaie.",
                      "Can't reach AniList. Check your connection, then try again."))
        } else if entries.isEmpty {
            message(t("Rien ici pour l'instant", "Nothing here yet"),
                    t("Sur la page d'un anime, « Ma liste » le range dans ta liste AniList.",
                      "On an anime's page, \"My list\" files it in your AniList list."))
        } else {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(entries) { e in
                    let route = MediaRoute(media: e.media, source: "library-\(e.media.id)")
                    NavigationLink(value: route) {
                        MediaGridCell(media: e.media, badge: badge(e), progress: fraction(e)).zoomSource(route.source, in: ns)
                    }
                    .buttonStyle(.plain)
                    .mediaPreview(e.media) { path.append(route) }
                }
            }
            .padding(.horizontal)
        }
    }

    private var statusChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ListStatus.allCases) { s in
                    let count = lists[s]?.count
                    Button { status = s } label: {
                        Text(count.map { "\(s.label)  \($0)" } ?? s.label).font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(status == s ? Nami.text : .white.opacity(0.08), in: Capsule())
                            .foregroundStyle(status == s ? Nami.ground : Nami.text)
                    }
                    .accessibilityAddTraits(status == s ? .isSelected : [])
                }
            }
            .padding(.horizontal)
        }
    }

    private func message(_ title: String, _ body: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(body).font(.subheadline).foregroundStyle(Nami.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private var loggedOut: some View {
        VStack(spacing: 14) {
            Image(systemName: "bookmark").font(.largeTitle).foregroundStyle(Nami.textSecondary)
            Text(t("Ta liste AniList", "Your AniList list")).font(.title3.bold())
            Text(t("Connecte ton compte pour suivre tes animes, les noter et retrouver ce que tu as prévu de voir.",
                   "Log in to track your anime, rate them and find what you planned to watch."))
                .font(.subheadline).foregroundStyle(Nami.textSecondary).multilineTextAlignment(.center)
            Button {
                Task {
                    do { try await anilist.login() } catch { loginError = error.localizedDescription }
                }
            } label: {
                Label(t("Se connecter à AniList", "Log in to AniList"), systemImage: "person.crop.circle")
                    .font(.headline).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Nami.text)
            .foregroundStyle(Nami.ground)
            if let loginError {
                Text(loginError).font(.footnote).foregroundStyle(Nami.textSecondary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        guard anilist.viewer != nil else { lists = [:]; return }
        do {
            lists = try await anilist.library()
            failed = false
        } catch {
            failed = lists.isEmpty
        }
        loaded = true
    }

    /// Episodes watched out of the total, and the score when there is one.
    private func badge(_ e: LibraryEntry) -> String {
        var parts: [String] = []
        let progress = e.entry.progress ?? 0
        if !e.media.isMovie {
            parts.append(e.media.episodes.map { "\(progress) / \($0)" } ?? t("\(progress) ép.", "\(progress) ep."))
        }
        let score = (e.entry.score ?? 0) / 10
        if score > 0 { parts.append("★ \(ListEditorSheet.format(score))") }
        return parts.joined(separator: " · ")
    }

    private func fraction(_ e: LibraryEntry) -> Double? {
        let total = e.media.episodes ?? e.media.availableEpisodes
        guard !e.media.isMovie, total > 0, e.entry.status != ListStatus.COMPLETED.rawValue else { return nil }
        return Double(e.entry.progress ?? 0) / Double(total)
    }
}

private struct ProfileHeader: View {
    let viewer: Viewer

    private var stats: String {
        let a = viewer.statistics?.anime
        let days = Double(a?.minutesWatched ?? 0) / 60 / 24
        let dayText = ListEditorSheet.format((days * 10).rounded() / 10)
        return [
            t("\(a?.count ?? 0) animes", "\(a?.count ?? 0) anime"),
            t("\(a?.episodesWatched ?? 0) épisodes vus", "\(a?.episodesWatched ?? 0) episodes watched"),
            t("\(dayText) jours", "\(dayText) days"),
        ].joined(separator: " · ")
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverImageView(url: viewer.bannerImage, corner: 0)
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                .overlay(LinearGradient(colors: [Nami.ground.opacity(0.3), Nami.ground], startPoint: .top, endPoint: .bottom))
                .clipped()
            HStack(alignment: .bottom, spacing: 16) {
                CoverImageView(url: viewer.avatar?.large, corner: 36).frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewer.name).font(.title.bold()).accessibilityAddTraits(.isHeader)
                    Text(stats).font(.subheadline).foregroundStyle(Nami.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
        }
    }
}
