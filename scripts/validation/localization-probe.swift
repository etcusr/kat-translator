import Foundation

// Compile with OfflineCore/L10n.swift; pass the built .app resource bundle.
@main struct LocalizationProbe {
    static func main() {
        let bundle = Bundle(path: CommandLine.arguments[1])!
        precondition(L10n.text("Готово", bundle: bundle, language: "en") == "Done")
        precondition(L10n.text("Готово", bundle: bundle, language: "ru") == "Готово")
        precondition(L10n.text("Перевожу часть \(2) из \(5)", bundle: bundle, language: "en") == "Translating part 2 of 5")
        precondition(L10n.text("Готово", bundle: bundle, language: "es") == "Hecho")
        precondition(L10n.text("Готово", bundle: bundle, language: "tr") == "Tamamlandı")
        precondition(L10n.text("Перевожу часть \(2) из \(5)", bundle: bundle, language: "es") == "Traduciendo parte 2 de 5")
        precondition(L10n.text("Перевожу часть \(2) из \(5)", bundle: bundle, language: "tr") == "Çevrilen bölüm: 2 / 5")
        for language in ["ru", "en", "es", "tr"] {
         for count in [1, 2, 5, 21, 22, 30, 365] {
          let value = L10n.retentionDays(count, bundle: bundle, language: language)
          print(language, count, value)
          let expected: String
          switch language {
          case "en": expected = "Delete after \(count) \(count == 1 ? "day" : "days")"
          case "es": expected = "Eliminar después de \(count) \(count == 1 ? "día" : "días")"
          case "tr": expected = "\(count) gün sonra sil"
          default:
            let suffix = count == 1 || count == 21 ? "день" : count == 2 || count == 22 ? "дня" : "дней"
            expected = "Удалять через \(count) \(suffix)"
          }
          precondition(value == expected)
         }
        }
        print("Compiled catalogs: RU/EN/ES/TR, interpolation and plural forms passed")
    }
}
