import SwiftUI

/// The seven days from `start`, each with its episodes in time order.
func weekDays(_ items: [AiringItem], from start: Date) -> [(day: Date, items: [AiringItem])] {
    let calendar = Calendar.current
    return (0..<7).compactMap { i in
        guard let day = calendar.date(byAdding: .day, value: i, to: start) else { return nil }
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

/// Seven days of episodes, today first, Apple Calendar style: a strip of days you swipe by seven
/// days, over the chosen day with its times on the left (the Android calendar has the same layout).
struct CalendarView: View {
    let listIDs: Set<Int>
    let ns: Namespace.ID

    @EnvironmentObject private var anilist: AniList
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.fr.rawValue
    @State private var start = Calendar.current.startOfDay(for: .now)
    @State private var selected = 0
    @State private var items: [AiringItem]?
    @State private var failed = false
    @State private var onlyMine = false
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.28) }

    /// What is new comes from the side you are going to.
    private var slide: AnyTransition {
        .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    private var days: [(day: Date, items: [AiringItem])] {
        weekDays((items ?? []).filter { !onlyMine || listIDs.contains($0.media.id) }, from: start)
    }

    var body: some View {
        let days = days
        let chosen = days.indices.contains(selected) ? days[selected] : nil
        VStack(alignment: .leading, spacing: 0) {
            strip(days).id(start).transition(slide)
            if !listIDs.isEmpty {
                Toggle(t("Seulement ma liste", "Only my list"), isOn: $onlyMine.animation(motion))
                    .font(.subheadline)
                    .tint(Nami.textSecondary)
                    .padding(.horizontal).padding(.top, 8)
            }
            content(chosen).id("\(start)-\(selected)").transition(slide)
        }
        .clipped()
        .background(Nami.ground)
        .foregroundStyle(Nami.text)
        .navigationTitle(chosen.map { month($0.day) } ?? t("Calendrier", "Calendar"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if let chosen, !Calendar.current.isDateInToday(chosen.day) {
                Button(t("Aujourd'hui", "Today")) { goToday() }.tint(Nami.text)
            }
        }
        .task(id: start) { await load() }
    }

    private func month(_ day: Date) -> String {
        day.formatted(Date.FormatStyle(locale: Locale(identifier: appLanguage)).month(.wide).year()).capitalized
    }

    private func goToday() {
        let today = Calendar.current.startOfDay(for: .now)
        forward = today > start
        withAnimation(motion) {
            start = today
            selected = 0
        }
    }

    private func shift(_ weeks: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: 7 * weeks, to: start) else { return }
        forward = weeks > 0
        withAnimation(motion) { start = next }
    }

    private func strip(_ days: [(day: Date, items: [AiringItem])]) -> some View {
        let letters = t("L M M J V S D", "M T W T F S S").split(separator: " ").map(String.init)
        return HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                let today = Calendar.current.isDateInToday(d.day)
                let marked = listIDs.isEmpty ? !d.items.isEmpty : d.items.contains { listIDs.contains($0.media.id) }
                Button {
                    forward = i > selected
                    withAnimation(motion) { selected = i }
                } label: {
                    VStack(spacing: 4) {
                        Text(letters[(Calendar.current.component(.weekday, from: d.day) + 5) % 7])
                            .font(.caption2).foregroundStyle(Nami.textSecondary)
                        Text(d.day.formatted(.dateTime.day()))
                            .font(.subheadline.weight(selected == i || today ? .bold : .medium))
                            .foregroundStyle(selected == i ? Nami.ground : Nami.text)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(selected == i ? Nami.text : .clear))
                            .overlay(Circle().strokeBorder(today && selected != i ? Nami.text : .clear, lineWidth: 1.5))
                        Circle().fill(marked ? Nami.textSecondary : .clear).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(d.day.formatted(Date.FormatStyle(locale: Locale(identifier: appLanguage)).weekday(.wide).day()))
                .accessibilityAddTraits(selected == i ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            guard abs(v.translation.width) > abs(v.translation.height) else { return }
            shift(v.translation.width < 0 ? 1 : -1)
        })
    }

    @ViewBuilder
    private func content(_ chosen: (day: Date, items: [AiringItem])?) -> some View {
        let shown = chosen?.items ?? []
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
            let today = chosen.map { Calendar.current.isDateInToday($0.day) } ?? false
            let aired = today ? shown.filter(\.aired).count : -1
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, item in
                        if i == aired { nowLine }
                        let route = MediaRoute(media: item.media, source: "calendar-\(item.id)")
                        NavigationLink(value: route) { row(item).zoomSource(route.source, in: ns) }
                            .buttonStyle(.plain)
                    }
                    if aired == shown.count { nowLine }
                }
                .padding(.vertical, 8)
            }
        }
    }

    /// The current time, between what is out and what is to come.
    private var nowLine: some View {
        Rectangle().fill(Nami.text).frame(height: 2)
            .padding(.horizontal).padding(.vertical, 4)
            .accessibilityLabel(t("Maintenant", "Now"))
    }

    private func row(_ item: AiringItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(item.airingAt.formatted(date: .omitted, time: .shortened))
                .font(.caption.bold()).foregroundStyle(Nami.textSecondary)
                .frame(minWidth: 44, alignment: .leading)
            CoverImageView(url: item.media.coverImage?.large, corner: 4).frame(width: 44, height: 62)
            VStack(alignment: .leading, spacing: 1) {
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
        let wanted = start
        failed = false
        items = nil
        do {
            let found = try await anilist.airingWeek(from: wanted)
            if wanted == start { withAnimation(motion) { items = found } }
        } catch {
            if wanted == start { failed = true }
        }
    }
}
