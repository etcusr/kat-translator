# Android app

[English](README.md) | **Русский**

Текущая сборка: **0.4.6 / versionCode21**, Debug, ARM64/API31+. Проверенная платформа — Pixel9Pro/Mali-G715. [Общий текущий статус](../../docs/CURRENT_STATE.md).

Kotlin/Compose: Voice/Text/Camera, языки, история, настройки, модели, загрузки, аудио и общие анимации. Начальный выбор — «Авто»: установленный Index 9B → 2B на мощном устройстве, поддержанный OPUS → 2B → 9B на остальных. Доступны OPUS Big CTranslate2 CPU INT8 (EN-пакет и отдельные направления), Index 2B Q4_K_M Vulkan без MTP и Index 9B Q4_K_M Vulkan/MTP. Сохранённый выбор не сбрасывается.

ASR Auto: RU → GigaAMv3, остальные поддержанные Parakeet языки → ParakeetTDTv3; обязательный пакет предлагается скачать. Ручной выбор имеет приоритет. Голос/камера требуют явного исходного языка, текстовое Auto сохраняется. OCR: bundled ML Kit для поддержанных письменностей, русский PP-OCR.

Каталоги: `../../assets/catalogs`; модели/голоса: `../../model-store`. Веса не входят в APK. Native C ABI: `../../shared/native`. Mali Q6 и другие Android-only patches применяются к build-копии, без изменения общего vendor/Apple Metal.

[Установка и сборка](../../docs/android/INSTALL.md) · [Архитектура и история переноса](../../docs/android/README.md) · [Историческая проверка Q6](../../docs/android/benchmarks/2026-10-12-mali-q6-kernels/README.md) · [ASR routing](../../docs/android/benchmarks/2026-10-12-asr-routing/README.md).
