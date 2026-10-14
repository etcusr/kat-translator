import Foundation

enum AppBuildInformation {
    /// Generated once during the build; never hashes the app or models at launch.
    static let identifier: String? = {
        guard let url = Bundle.main.url(forResource: "BuildIdentity", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return value["identifier"] as? String
    }()
}
