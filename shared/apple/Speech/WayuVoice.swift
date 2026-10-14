import OfflineCore
import Foundation

enum WayuVoice: String, CaseIterable, Identifiable {
    case fTeenBright = "f_teen_bright", fYoungBright = "f_young_bright", fYoungClear = "f_young_clear"
    case fYoungWarm = "f_young_warm", fMidClear = "f_mid_clear", fMidWarm = "f_mid_warm"
    case fElderlySoft = "f_elderly_soft", fElderlyLow = "f_elderly_low"
    case mTeenBright = "m_teen_bright", mYoungClear = "m_young_clear", mMidWarm = "m_mid_warm", mElderlyDeep = "m_elderly_deep"
    var id: String { rawValue }
    static let defaultVoice: WayuVoice = .mElderlyDeep
    static var selected: WayuVoice { WayuVoice(rawValue: UserDefaults.standard.string(forKey: "wayuVoice") ?? "") ?? defaultVoice }
    var title: String {
        switch self {
        case .fTeenBright: return L10n.text("Женский · высокий")
        case .fYoungBright: return L10n.text("Женский · яркий")
        case .fYoungClear: return L10n.text("Женский · молодой")
        case .fYoungWarm: return L10n.text("Женский · мягкий")
        case .fMidClear: return L10n.text("Женский · нейтральный")
        case .fMidWarm: return L10n.text("Женский · тёплый")
        case .fElderlySoft: return L10n.text("Женский · зрелый мягкий")
        case .fElderlyLow: return L10n.text("Женский · зрелый низкий")
        case .mTeenBright: return L10n.text("Мужской · высокий")
        case .mYoungClear: return L10n.text("Мужской · молодой")
        case .mMidWarm: return L10n.text("Мужской · тёплый")
        case .mElderlyDeep: return L10n.text("Мужской · глубокий")
        }
    }
}
