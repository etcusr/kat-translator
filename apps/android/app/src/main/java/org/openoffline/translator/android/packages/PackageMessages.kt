package org.openoffline.translator.android.packages

/** Translate known product messages; preserve technical errors from the platform verbatim. */
object PackageMessages {
    private val english = mapOf(
        "Нет подключения к интернету" to "No internet connection",
        "Разрешите мобильный интернет или подключитесь к обычному Wi-Fi" to "Allow mobile data or connect to unmetered Wi-Fi",
        "Хранилище приложения недоступно" to "App storage is unavailable",
        "Хранилище уже открыто другим загрузчиком" to "Storage is already open in another downloader",
        "Пакет не установлен" to "Package is not installed",
        "Пакет изменяется" to "Package is being changed",
        "Модель используется. Сначала остановите перевод или озвучку" to "Model is in use. Stop translation or speech first",
        "Не удалось удалить пакет" to "Could not remove the package",
        "Импорт файла" to "Importing file",
        "Не удалось открыть файл" to "Could not open the file",
        "Файл больше ожидаемого пакета" to "File exceeds the expected package size",
        "Размер файла не совпадает с каталогом" to "File size does not match the catalog",
        "Файл не соответствует SHA-256 пакета" to "File does not match the package SHA-256",
        "Компонент импортирован. Импортируйте остальные или продолжите загрузку" to "Component imported. Import the remaining files or resume downloading",
        "Не удалось установить пакет" to "Could not install the package",
        "Проверка пакета не пройдена" to "Package verification failed",
        "Неполный пакет" to "Incomplete package",
        "Разрешены только HTTPS-загрузки" to "Only HTTPS downloads are allowed",
        "Слишком много перенаправлений" to "Too many redirects",
        "Нет адреса перенаправления" to "Redirect location is missing",
        "Сервер вернул неверный диапазон" to "Server returned an invalid byte range",
        "Сервер вернул другой файл" to "Server returned a different file",
        "Размер ответа не совпадает с каталогом" to "Response size does not match the catalog",
        "Ответ больше ожидаемого файла" to "Response exceeds the expected file size",
        "Загрузка прервалась. Можно продолжить" to "Download interrupted. You can resume it",
        "Недопустимый путь файла" to "Invalid file path",
        "Файл скачан не полностью" to "File is incomplete",
        "Проверка SHA-256 не пройдена. Скачайте файл заново" to "SHA-256 verification failed. Download the file again",
        "Не удалось создать папку пакета" to "Could not create the package folder",
        "Архив оборван" to "Archive is truncated",
        "Архив неполон" to "Archive is incomplete",
        "Лишние данные в архиве" to "Unexpected data in archive",
        "Слишком много файлов в архиве" to "Too many archive entries",
        "Повреждён заголовок архива" to "Archive header is damaged",
        "Небезопасный путь в архиве" to "Unsafe archive path",
        "Неверный размер файла" to "Invalid file size",
        "Неверная папка архива" to "Invalid archive directory",
        "Ссылки и расширенные заголовки архива запрещены" to "Archive links and extended headers are not allowed",
        "Неизвестный файл в архиве" to "Unknown archive file",
        "Файл архива не совпадает с каталогом" to "Archive entry does not match the catalog",
        "Файл архива не прошёл SHA-256" to "Archive entry failed SHA-256 verification",
    )
    fun display(message: String?, language: String): String? {
        if (message == null || language == "ru") return message
        val strings = org.openoffline.translator.android.UiStrings
        english[message]?.let { return strings.text(message, it, language) }
        if (message.startsWith("Сервер вернул HTTP ")) return strings.text("Сервер вернул HTTP %@", null, language, message.removePrefix("Сервер вернул HTTP "))
        val space = Regex("Недостаточно свободного места\\. Нужно ещё (\\d+) МБ").matchEntire(message)
        if (space != null) return strings.text("Недостаточно свободного места. Нужно ещё %@ МБ", null, language, space.groupValues[1])
        return message
    }
    // Compatibility for existing callers and tests.
    fun display(message: String?, russian: Boolean): String? = display(message, if (russian) "ru" else "en")
}
