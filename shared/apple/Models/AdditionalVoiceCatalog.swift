import Foundation
import OfflineCore

enum AdditionalVoiceCatalog {
    static let catalog: VoicePackageCatalog = {
        guard let url = Bundle.main.url(forResource: "additional-voices", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let definitions = try? JSONDecoder().decode([VoicePackageDefinition].self, from: data),
              let catalog = try? VoicePackageCatalog(definitions) else {
            preconditionFailure("Invalid bundled voice catalog")
        }
        return catalog
    }()
}
