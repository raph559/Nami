import SwiftUI

/// What is playing and how it is shown, for the whole app: the player lives
/// above the tabs so it can shrink to a mini-player and keep playing while
/// you browse.
@MainActor
final class PlayerCenter: ObservableObject {
    static let shared = PlayerCenter()

    struct Session: Identifiable {
        let id = UUID()
        var media: Media
        var episode: Int
        var result: TorrentResult
    }

    struct SourcesRequest: Identifiable {
        var media: Media
        var episode: Int
        /// Opened by the countdown: play the recommended source without asking.
        var autoPick = false
        var id: String { "\(media.id)-\(episode)" }
    }

    @Published var session: Session?
    @Published var minimized = false
    @Published var sources: SourcesRequest?
    /// Bumped when a session ends, so pages can refresh the AniList progress.
    @Published private(set) var finished = 0

    func openSources(_ media: Media, episode: Int, autoPick: Bool = false) {
        sources = SourcesRequest(media: media, episode: episode, autoPick: autoPick)
    }

    /// Called by the sources sheet: the sheet closes first, then the player opens.
    func picked(_ result: TorrentResult, for request: SourcesRequest) {
        sources = nil
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            play(request.media, episode: request.episode, result: result)
        }
    }

    func play(_ media: Media, episode: Int, result: TorrentResult) {
        minimized = false
        session = Session(media: media, episode: episode, result: result)
    }

    func close() {
        session = nil
        minimized = false
        finished += 1
    }

    /// A season pack that holds the next episode is played again; otherwise the
    /// sheet opens, and after a countdown it plays its recommendation.
    func next(_ exit: PlayerExit) {
        guard let s = session else { return }
        let episode = s.episode + 1
        if let reuse = exit.reuse {
            play(s.media, episode: episode, result: reuse)
        } else {
            close()
            openSources(s.media, episode: episode, autoPick: exit.auto)
        }
    }
}
