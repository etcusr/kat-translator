import ActivityKit
import Foundation

struct DownloadActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var detail: String
        var bytes: String
        var fraction: Double
        var symbol: String
        var finished: Bool
    }
    var staleMessage: String
    // Optional for activities created by an older installed version.
    var catCoat: Int? = nil
}
