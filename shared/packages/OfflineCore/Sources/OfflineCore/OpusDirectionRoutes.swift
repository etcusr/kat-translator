import Foundation

/// OPUS-MT Big direction packages from assets/catalogs/opus-direction-packages.json (shared with
/// Android). Each package holds one model directory; routes map app language ids to it, with
/// the target-language marker multi-target models require. Catalog order is routing priority.
public struct OpusDirectionRoute: Sendable, Equatable {
    public let packageID: String
    public let direction: String
    public let sources: Set<String>
    public let targets: Set<String>
    public let markers: [String: String]
    public let parts: [VoicePackagePart]
    public var bytes: Int64 { parts.reduce(0) { $0 + $1.byteCount } }
    public var hosted: Bool { !parts.contains { $0.remoteURL.absoluteString.contains("HOSTING-PENDING") } }
    public func covers(_ source: String, _ target: String) -> Bool { source != target && sources.contains(source) && targets.contains(target) }
    public func marker(_ target: String) -> String { markers[target] ?? "" }
}

public enum OpusDirectionRoutes {
    private struct Entry: Decodable {
        let id: String; let direction: String; let sources: [String]; let targets: [String]
        let markers: [String: String]; let parts: [VoicePackagePart]
    }
    public static func decode(_ data: Data) throws -> [OpusDirectionRoute] {
        try JSONDecoder().decode([Entry].self, from: data).map {
            OpusDirectionRoute(packageID: $0.id, direction: $0.direction, sources: Set($0.sources), targets: Set($0.targets), markers: $0.markers, parts: $0.parts)
        }
    }
    /// Empty when the bundle has no catalog (unit tests of other components).
    public static let all: [OpusDirectionRoute] = {
        guard let url = Bundle.main.url(forResource: "opus-direction-packages", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? decode(data)) ?? []
    }()
    public static var languages: Set<String> { Set(all.flatMap { $0.sources.union($0.targets) }) }
    public static func route(_ source: String, _ target: String, in routes: [OpusDirectionRoute] = all, available: (OpusDirectionRoute) -> Bool = { _ in true }) -> OpusDirectionRoute? {
        routes.first { $0.covers(source, target) && available($0) }
    }
}

/// Automatic translation: a powerful device prefers Index 9B; otherwise OPUS for the pair
/// (English package, then a direction package), then Index 2B, then Index 9B.
public enum AutoTranslation {
    public static let preferenceKey = "translationAuto"
    public static func resolve(source: SpeechLanguage, target: SpeechLanguage, strongDevice: Bool,
                               installed: (TranslationModel) -> Bool, directionInstalled: (String, String) -> Bool) -> TranslationModel? {
        let opusPair = installed(.opusBig) && TranslationModel.opusBig.supports(source: source, target: target)
        let direction = directionInstalled(source.rawValue, target.rawValue)
        let order: [TranslationModel] = strongDevice ? [.index9B, .index2B] : [.opusBig, .opusDirections, .index2B, .index9B]
        return order.first {
            switch $0 {
            case .opusBig: return opusPair
            case .opusDirections: return direction
            default: return installed($0) && $0.supports(source: source, target: target)
            }
        }
    }
}
