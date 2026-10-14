import SwiftUI
import OfflineCore

struct PrivacyView: View {
    var body: some View {
        Form {
            Section {
                Text(L10n.text("Разработчик Kat translator не собирает пользовательские данные через приложение. Тексты, записи голоса, изображения и переводы обрабатываются на устройстве и автоматически разработчику не передаются."))
            } header: {
                SettingsSectionHeader(L10n.text("Обработка на устройстве"))
            }
            Section {
                Text(L10n.text("Интернет используется для скачивания моделей и голосов. Серверы загрузки получают обычные технические данные соединения, например IP-адрес и имя запрошенного файла. Содержимое ваших переводов туда не отправляется. После загрузки нужных пакетов перевод работает без интернета."))
            } header: {
                SettingsSectionHeader(L10n.text("Когда нужен интернет"))
            }
            Section {
                Text(L10n.text("История текста, озвучки и изображений хранится локально, если её сохранение включено. В настройках можно отключить сохранение, изменить срок хранения или очистить историю. При включённом сохранении аудио история может содержать исходные записи речи."))
                Text(L10n.text("Диагностический отчёт создаётся по вашей команде и содержит показатели работы и версии моделей, без текста и аудио. Отправка отчётов, переводов и озвучки происходит только через выбранное вами действие «Поделиться»."))
            } header: {
                SettingsSectionHeader(L10n.text("История и отчёты"))
            }
            Section {
                Text(L10n.text("Результат создают ИИ-модели: возможны ошибки, пропуски, добавления и искажение смысла, чисел или имён. Качество зависит от языка, модели, шума и исходного текста. Мы не гарантируем точность или пригодность перевода для конкретной цели. Проверяйте важную информацию по оригиналу, особенно когда ошибка может повлиять на здоровье, безопасность или обязательства."))
            } header: {
                SettingsSectionHeader(L10n.text("Точность перевода"))
            }
            Section {
                Link(L10n.text("Полная политика конфиденциальности"), destination: URL(string: "https://etcusr.github.io/kat-translator/privacy/")!)
                Link("katlabs.dev@gmail.com", destination: URL(string: "mailto:katlabs.dev@gmail.com")!)
            }
            Section {
                Text(L10n.text("Приложение использует открытые компоненты, включая whisper.cpp, llama.cpp, sherpa-onnx и ONNX Runtime. У программных компонентов, моделей и голосов разные лицензии; некоторые веса имеют ограничения, в том числе на коммерческое использование. Открытость исходного кода не означает одинаковые условия для всех моделей и не гарантирует точность результата."))
                Link("whisper.cpp", destination: URL(string: "https://github.com/ggml-org/whisper.cpp")!)
                Link("llama.cpp", destination: URL(string: "https://github.com/ggml-org/llama.cpp")!)
                Link("sherpa-onnx", destination: URL(string: "https://github.com/k2-fsa/sherpa-onnx")!)
                Link("ONNX Runtime", destination: URL(string: "https://github.com/microsoft/onnxruntime")!)
                Text(L10n.text("Сведения об источниках и условиях моделей доступны в разделах моделей и голосов."))
            } header: {
                SettingsSectionHeader(L10n.text("Открытые компоненты и модели"))
            }
        }.katSectionSpacing()
            .navigationTitle(L10n.text("Конфиденциальность и точность"))
            .accessibilityIdentifier("settings.privacy.content")
    }
}
