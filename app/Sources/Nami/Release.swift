import Foundation
import SwiftUI

/// What a torrent release name says, pulled out so the sources list can show
/// facts instead of raw file names. Same rules as the Android and Windows app.
struct ReleaseInfo: Identifiable {
    let result: TorrentResult
    var group: String?
    var resolution: String?
    var source: String?
    var codec: String?
    var dualAudio = false
    var multiAudio = false
    var dub = false
    var multiSubs = false
    var batch = false
    var prerelease = false

    var id: String { result.id }

    init(_ r: TorrentResult) {
        result = r
        let t = r.title
        func has(_ pattern: String) -> Bool { t.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        func first(_ pattern: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), m.numberOfRanges > 1,
                  let range = Range(m.range(at: 1), in: t) else { return nil }
            return String(t[range]).trimmingCharacters(in: .whitespaces)
        }
        group = first(#"^\s*\[([^\]]+)\]"#)
        resolution = first(#"\b(2160|1440|1080|720|480)p\b"#) ?? (has(#"\b(4K|UHD)\b"#) ? "2160" : nil)
        if has(#"\b(BD|Blu-?Ray|BDRip|BDMV)\b"#) { source = "Blu-ray" } else if has(#"\bWEB(-?DL|-?Rip)?\b"#) { source = "WEB" }
        if has(#"\b(HEVC|x265|H\.?265)\b"#) { codec = "HEVC" } else if has(#"\bAV1\b"#) { codec = "AV1" } else if has(#"\b(AVC|x264|H\.?264)\b"#) { codec = "H.264" }
        dualAudio = has(#"\bDual[- ]?Audio\b|\bDUAL\b"#)
        multiAudio = !dualAudio && has(#"\bMULTi\b|\bMulti[- ]?Audio\b"#)
        dub = !dualAudio && !multiAudio && has(#"\b(English )?Dub(bed)?\b"#)
        multiSubs = has(#"\bMulti[- ]?Subs?\b|\bMultiSub\b"#)
        prerelease = has(#"\bPre-?release\b"#)
        // A batch says so, or names a season without an episode (S02 but not S02E01).
        batch = has(#"\bBATCH\b|\bComplete\b"#) || (has(#"\bS\d{1,2}\b"#) && !has(#"\bS\d{1,2}E\d{1,4}\b"#))
    }

    /// The name shown first: the release group, else the extension.
    var title: String { group ?? result.source ?? result.title }

    var seeders: Int { result.seeders ?? 0 }

    var audioLabel: String {
        if dualAudio { return t("Double audio", "Dual audio") }
        if multiAudio { return "Multi-audio" }
        if dub { return t("Doublage", "Dub") }
        return t("VO", "Original audio")
    }

    /// Short facts, in reading order.
    var facts: [String] {
        var out: [String] = []
        if let resolution { out.append("\(resolution)p") }
        if let source { out.append(source) }
        if let codec { out.append(codec) }
        out.append(audioLabel)
        if multiSubs { out.append(t("Multi sous-titres", "Multi subs")) }
        if batch { out.append(t("Saison complète", "Full season")) }
        if prerelease { out.append(t("Pré-version", "Pre-release")) }
        return out
    }

    var health: SeedHealth { seeders >= 50 ? .good : seeders >= 5 ? .fair : .low }

    /// Ranking for the recommended source. Seeders matter most (they decide
    /// whether playback starts), then the user's quality, original audio,
    /// and a finished release over a pre-release. A full season always has more
    /// seeders than one episode, so it is held back: a single-episode release
    /// with a few dozen seeders wins over a season pack with a few hundred.
    func score(_ preferredResolution: String) -> Double {
        var s = log(Double(seeders) + 1) * 10
        if result.isBest { s += 25 }
        if resolution == preferredResolution { s += 20 } else if resolution != nil { s -= 5 }
        if dub { s -= 40 }
        if prerelease { s -= 30 }
        if batch { s -= 25 }
        if seeders == 0 { s -= 30 }
        return s
    }

    /// One plain sentence on why a source was picked.
    func reason(_ preferredResolution: String) -> String {
        var parts: [String] = []
        if resolution == preferredResolution { parts.append(t("ta qualité préférée", "your preferred quality")) }
        if !dub { parts.append(t("VO", "original audio")) }
        if result.isBest { parts.append(t("conseillée par \(result.source ?? "?")", "picked by \(result.source ?? "?")")) }
        parts.append("\(seeders) seeders")
        return parts.joined(separator: " · ")
    }

    static func rank(_ results: [TorrentResult], resolution: String) -> [ReleaseInfo] {
        results.map(ReleaseInfo.init).sorted { $0.score(resolution) > $1.score(resolution) }
    }
}

/// How well a torrent is shared, which decides how fast playback starts.
/// The word and the bar count carry the meaning; the color only repeats it.
enum SeedHealth {
    case good, fair, low

    var label: String {
        switch self {
        case .good: t("bien partagée", "well seeded")
        case .fair: t("partage moyen", "fairly seeded")
        case .low: t("lancement lent", "slow start")
        }
    }

    /// How much of the "cellularbars" symbol is filled.
    var bars: Double {
        switch self {
        case .good: 1
        case .fair: 0.6
        case .low: 0.3
        }
    }
}
