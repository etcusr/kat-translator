import Foundation

/// Total device RAM, not model allocation. Rounded tiers allow for memory reserved by iOS.
public enum ModelMemoryAdvice {
    public static func recommended(_ model: TranslationModel, physicalMemory: UInt64) -> Bool {
        guard TranslationModel.selectable.contains(model) else { return false }
        if physicalMemory >= 10_500_000_000 { return model == .index9B }
        return model == .opusBig
    }
    public static func approximateRAM(_ model: TranslationModel) -> String {
        switch model {
        case .opusBig, .opusDirections: return L10n.text("Меньше расход памяти, чем у моделей 4B–9B")
        case .index2B: return L10n.text("Меньше памяти, чем у 9B")
        case .index9B, .qwen9B: return L10n.text("RAM устройства: от 12 ГБ (ориентир)")
        case .gemma4B, .mil4B: return L10n.text("RAM устройства: от 8 ГБ (ориентир)")
        case .mil12B: return L10n.text("RAM устройства: от 16 ГБ — оценка, не проверено")
        }
    }
}
