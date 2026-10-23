import XCTest
import SwiftUI
import AppKit
import OfflineCore
@testable import Kat_translator

/// Opt-in native view previews, not desktop screenshots or model benchmarks.
final class PublicationPreviewTests: XCTestCase {
    @MainActor func testLanguageMenuPreviews() async throws {
        guard let directory = ProcessInfo.processInfo.environment["KAT_LANGUAGE_PREVIEW_DIR"] else {
            throw XCTSkip("Opt-in language menu preview export")
        }
        let defaults = UserDefaults.standard
        let saved = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(saved, forName: UserDefaults.argumentDomain) }
        for language in ["en", "ru", "es", "tr"] {
            defaults.setVolatileDomain(saved.merging([
                "appInterfaceLanguage": language, "automaticModelLoad": false,
                "languageSetupCompleted": true, "favoriteTranslationLanguages": ""
            ]) { _, new in new }, forName: UserDefaults.argumentDomain)
            let model = AppModel()
            let view = LanguageSearchSheet(selection: .constant(LanguageSelection()), side: .target,
                mode: .text, model: .index9B, app: model, packages: .shared)
                .environment(\.locale, Locale(identifier: language))
                .tint(KatTheme.accent).preferredColorScheme(.dark)
                .frame(width: 560, height: 640)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderBack(nil)
            try await Task.sleep(for: .milliseconds(600))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let output = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: output.appendingPathComponent(language + ".png"))
            XCTAssertEqual(bitmap.pixelsWide, 560)
            window.close()
        }
    }

    @MainActor func testLocalizedSettingsPreviews() async throws {
        guard let directory = ProcessInfo.processInfo.environment["KAT_PUBLICATION_PREVIEW_DIR"] else {
            throw XCTSkip("Opt-in publication preview export")
        }
        let defaults = UserDefaults.standard
        let saved = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(saved, forName: UserDefaults.argumentDomain) }
        for language in ["en", "ru", "es", "tr"] {
            defaults.setVolatileDomain(saved.merging([
                "appInterfaceLanguage": language, "automaticModelLoad": false,
                "languageSetupCompleted": true, "showTechnicalInfo": false,
                "historyRecordText": false, "historyRecordAudio": false
            ]) { _, new in new }, forName: UserDefaults.argumentDomain)
            let model = AppModel()
            let views: [(String, AnyView)] = [
                ("01-settings", AnyView(SettingsView(model: model))),
                ("02-models-and-voices", AnyView(SettingsView(model: model, initialPage: .models))),
                ("03-voices", AnyView(SettingsView(model: model, initialPage: .voices))),
                ("04-quick-setup", AnyView(LanguageSetupView(model: model)))
            ]
            for (name, view) in views {
                let host = NSHostingView(rootView: view
                    .environment(\.locale, Locale(identifier: language))
                    .tint(KatTheme.accent).preferredColorScheme(.dark)
                    .frame(width: 1000, height: 800))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                // Render only this application's view; never capture another window or screen.
                window.orderBack(nil)
                try await Task.sleep(for: .milliseconds(600))
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let output = URL(fileURLWithPath: directory).appendingPathComponent(language)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: output.appendingPathComponent(name + ".png"))
                XCTAssertGreaterThan(bitmap.pixelsWide, 0)
                window.close()
            }
        }
    }
}
