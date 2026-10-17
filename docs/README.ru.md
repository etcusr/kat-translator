# Указатель документации

[English](README.md) | **Русский**

Живая документация ведётся на двух языках: `NAME.md` — английская версия по умолчанию, `NAME.ru.md` — русская. Обе версии содержат одинаковые факты и обновляются вместе ([правило](GIT_WORKFLOW.ru.md#языки-документации)). Датированные отчёты, замеры и исследования — доказательства конкретного прогона; они остаются на исходном языке и не являются текущей спецификацией.

## С чего начать

| Документ | Назначение |
|---|---|
| [README](../README.ru.md) | Обзор проекта, выпуски, быстрые ссылки |
| [CURRENT_STATE](CURRENT_STATE.ru.md) | Текущие выпуски, подтверждённые результаты, ограничения и эксперименты |
| [ARCHITECTURE](ARCHITECTURE.ru.md) | Карта кода, общие и платформенные слои, команды сборки |
| [Очередь публикации](publication/OPEN_QUESTIONS.ru.md) | Что осталось до публикации в App Store / Google Play |
| [Описание проекта](../PROJECT_DESCRIPTION.ru.md) | Описание продукта и идентификаторы |

## Платформы

| Документ | Назначение |
|---|---|
| [Mac](macos/README.ru.md) | Сборки для Mac App Store и прямой загрузки, упаковка, заметки о тестах, история сборок |
| [Приложение Android](../apps/android/README.ru.md) · [Установка и сборка Android](android/INSTALL.ru.md) · [Архитектура Android](android/README.ru.md) | Выпуск Android, сборка и история переноса |
| [Карта каталогов](android/PLATFORM_LAYOUT.ru.md) | Структура каталогов для всех платформ |
| [Хранилище пакетов Android](android/PACKAGE-STORAGE.ru.md) · [Медиа-runtime Android](android/MEDIA.ru.md) | Технические справки |
| [OPUS Big](IMPLEMENTATION-opus-big.ru.md) | Движок OPUS и пакеты направлений |
| [Общее хранилище моделей](../model-store/README.ru.md) | Локальный кэш весов для разработки |

## Правила и лицензии

| Документ | Назначение |
|---|---|
| [Лицензия](LICENSING.ru.md) | GPL-3.0-or-later для кода Kat; условия сторонних компонентов; комплект исходников |
| [Состав репозитория](REPOSITORY_PRIVACY.ru.md) | Что можно и нельзя коммитить |
| [Работа с Git](GIT_WORKFLOW.ru.md) | Коммиты, выпуски, публичная история, языки документации |
| [Участие в разработке](../CONTRIBUTING.ru.md) | Как предлагать изменения и сообщать об ошибках |
| [Бренд](branding/README.ru.md) · [Анимации обработки](branding/loading-animations/README.ru.md) | Значок, тема, анимации |

## Датированные доказательства (на исходном языке)

- `publication/*-2026-10-*.md` — отчёты о магазинных сборках, конфиденциальности, лицензиях и runtime-приёмке. Основные: [сборки Mac App Store](publication/macos-appstore-build-2026-10-14.md), [runtime-приёмка 50/69](publication/runtime-acceptance-2026-10-14.md), [конфиденциальность загрузок моделей](publication/model-download-privacy-2026-10-14.md), [локализации](publication/2026-10-14/LOCALIZATIONS.md).
- `licensing/2026-10-*/` — проверки лицензий, уведомления и комплект исходников зависимостей.
- `benchmarks/`, `android/benchmarks/` — замеры и прогоны на устройствах.
- `research/`, `android/ASR-OPTIONS.md`, `android/OCR-OPTIONS.md` — исследования и записи решений.
- `maintenance/` — очистки, переносы, подпись и аудит исходников. Последняя: [очистка завершённых тестов и сборок, 17 октября](maintenance/cleanup-2026-10-17.md).
- Исторические журналы реализации: [IMPLEMENTATION](IMPLEMENTATION.md) (RU), [кэш проверки при запуске](IMPLEMENTATION-startup-verification-cache.md) (RU), [загрузки языков](IMPLEMENTATION-language-downloads.md) (EN), [протокол испытаний на устройстве](../DEVICE_TESTING.md) (RU), [паритет функций Android](android/FEATURE_PARITY.md) (EN), [паритет интерфейса Android](android/IOS_INTERFACE_PARITY.md) (EN), `macos/2026-10-10-shortcuts.md`, `macos/diagnostics/`, `branding/round-*`, `history/`.
