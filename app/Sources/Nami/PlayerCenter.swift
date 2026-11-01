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
        var result: TorrentResult?
        var localFile: URL?
    }

    struct SourcesRequest: Identifiable {
        var media: Media
        var episode: Int
        /// Opened by the countdown: play the recommended source without asking.
        var autoPick = false
        /// The source picked is downloaded rather than played.
        var forDownload = false
        var id: String { "\(media.id)-\(episode)" }
    }

    @Published var session: Session?
    @Published var minimized = false
    @Published var sources: SourcesRequest?
    /// The sources are open to pick a release to download.
    private var downloadRequest: SourcesRequest?
    /// Bumped when a session ends, so pages can refresh the AniList progress.
    @Published private(set) var finished = 0

    /// A downloaded episode plays straight from the device.
    func openSources(_ media: Media, episode: Int, autoPick: Bool = false, forDownload: Bool = false) {
        if let file = Downloads.shared.localURL(media.id, episode), !forDownload {
            play(media, episode: episode, result: nil, localFile: file)
            return
        }
        let request = SourcesRequest(media: media, episode: episode, autoPick: autoPick, forDownload: forDownload)
        if forDownload { downloadRequest = request }
        sources = request
    }

    /// Closing the sources without picking comes back to the download question.
    func sourcesClosed() {
        guard let request = downloadRequest else { return }
        downloadRequest = nil
        Downloads.shared.askStart(request.media, episode: request.episode)
    }

    /// Called by the sources sheet: the sheet closes first, then the player opens.
    func picked(_ result: TorrentResult, for request: SourcesRequest) {
        sources = nil
        if request.forDownload {
            downloadRequest = nil
            Downloads.shared.start(request.media, episode: request.episode, link: result.link)
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            play(request.media, episode: request.episode, result: result)
        }
    }

    func play(_ media: Media, episode: Int, result: TorrentResult?, localFile: URL? = nil) {
        minimized = false
        session = Session(media: media, episode: episode, result: result, localFile: localFile)
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
