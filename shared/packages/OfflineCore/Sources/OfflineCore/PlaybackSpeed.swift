import Foundation

public enum PlaybackSpeed: Double, CaseIterable, Sendable {
    case normal = 1
    case oneAndQuarter = 1.25
    case oneAndHalf = 1.5
    case double = 2

    public var label: String {
        "×" + rawValue.formatted(.number.locale(L10n.locale))
    }
    public var next: Self {
        switch self {
        case .normal: return .oneAndQuarter
        case .oneAndQuarter: return .oneAndHalf
        case .oneAndHalf: return .double
        case .double: return .normal
        }
    }
}
