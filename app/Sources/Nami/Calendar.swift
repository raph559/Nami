import SwiftUI

/// The seven days from `now`, each with its episodes in time order.
func weekDays(_ items: [AiringItem], now: Date = .now) -> [(day: Date, items: [AiringItem])] {
    let calendar = Calendar.current
    let first = calendar.startOfDay(for: now)
    return (0..<7).compactMap { i in
        guard let day = calendar.date(byAdding: .day, value: i, to: first) else { return nil }
        return (day, items.filter { calendar.isDate($0.airingAt, inSameDayAs: day) })
    }
}

/// The calendar as a tab of the app, with its own navigation.
struct CalendarTab: View {
    @ObservedObject private var store = HomeStore.shared
    @State private var path: [MediaRoute] = []
    @Namespace private var ns

    var body: some View {
        NavigationStack(path: $path) {
            CalendarView(listIDs: store.feed?.listIDs ?? [], ns: ns)
                .navigationDestination(for: MediaRoute.self) { r in
                    MediaDetailView(media: r.media).zoomDestination(r.source, in: ns)
                }
        }
    }
}

/// The week's episodes, one tab per day, with the anime of your list marked (same as Android and Windows).
struct CalendarView: View {
    let listIDs: Set<Int>
    let ns: Namespace.ID

    @EnvironmentObject private var anilist: AniList
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.fr.rawValue
    @State private var items: [AiringItem]?
    @State private var failed = false
    @State private var selected = 0
    @State private var onlyMine = false

    private var days: [(day: Date, items: [AiringItem])] {
        weekDays((items ?? []).filter { !onlyMine || listIDs.contains($0.media.id) })
    }

    var body: some View {
        let days = days
        VStack(alignment: .leading, spacing: 0) {
            tabs(days)
            if !listIDs.isEmpty {
                Toggle(t("Seulement ma liste", "Only my list"), isOn: $onlyMine)
                    .font(.subheadline)
                    .tint(Nami.textSecondary)
                    .padding(.horizontal).padding(.top, 8)
            }
            content(days.indices.contains(selected) ? days[selected].items : [])
        }
        .background(Nami.ground)
        .foregroundStyle(Nami.text)
        .navigationTitle(t("Calendrier", "Calendar"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await load() }
    }

    private func label(_ day: Date, _ index: Int) -> String {
        if index == 0 { return t("Aujourd'hui", "Today") }
        if index == 1 { return t("Demain", "Tomorrow") }
        return day.formatted(Date.FormatStyle(locale: Locale(identifier: appLanguage)).weekday(.abbreviated).day())
    }

    private func tabs(_ days: [(day: Date, items: [AiringItem])]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 22) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                    Button { selected = i } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(label(d.day, i)).font(.subheadline.weight(selected == i ? .bold : .medium))
                                    .foregroundStyle(selected == i ? Nami.text : Nami.textSecondary)
                                if items != nil {
                                    Text("\(d.items.count)").font(.caption).foregroundStyle(Nami.textMuted)
                                }
                            }
                            Capsule().fill(selected == i ? Nami.text : .clear).frame(height: 2)
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == i ? .isSelected : [])
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Nami.text.opacity(0.1)).frame(height: 1) }
    }

    @ViewBuilder
    private func content(_ shown: [AiringItem]) -> some View {
        if failed {
            VStack(spacing: 12) {
                Text(t("Calendrier indisponible", "Calendar unavailable")).font(.headline)
                Text(t("AniList n'a pas répondu.", "AniList didn't answer.")).font(.subheadline).foregroundStyle(Nami.textSecondary)
                Button(t("Réessayer", "Try again")) { Task { await load() } }.buttonStyle(.bordered).tint(Nami.text)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items == nil {
            VStack(spacing: 12) {
                ProgressView().tint(Nami.text)
                Text(t("Chargement du calendrier…", "Loading the calendar…")).font(.subheadline).foregroundStyle(Nami.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if shown.isEmpty {
            Text(onlyMine ? t("Rien de ta liste ce jour-là", "Nothing from your list that day")
                          : t("Aucun épisode ce jour-là", "No episodes that day"))
                .font(.subheadline).foregroundStyle(Nami.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { item in
                        let route = MediaRoute(media: item.media, source: "calendar-\(item.id)")
                        NavigationLink(value: route) { row(item).zoomSource(route.source, in: ns) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func row(_ item: AiringItem) -> some View {
        let time = item.airingAt.formatted(date: .omitted, time: .shortened)
        return HStack(spacing: 12) {
            CoverImageView(url: item.media.coverImage?.large, corner: 4).frame(width: 52, height: 74)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.aired ? t("\(time) · sorti", "\(time) · out") : time)
                    .font(.caption.bold()).foregroundStyle(Nami.textSecondary)
                Text(item.media.title.display).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(t("Épisode \(item.episode)", "Episode \(item.episode)")).font(.caption).foregroundStyle(Nami.textSecondary)
                if listIDs.contains(item.media.id) {
                    Text(t("Dans ta liste", "In your list")).font(.caption.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func load() async {
        failed = false
        do { items = try await anilist.airingWeek() } catch { failed = items == nil }
    }
}
