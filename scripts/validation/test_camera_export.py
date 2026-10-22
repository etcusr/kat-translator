#!/usr/bin/env python3
"""Exercise iOS camera export decisions on Mac without UIKit or inference.

Production methods are extracted directly; only the iOS-only file-protection
flag is omitted on the Mac host. Raster operations are represented by block
identifiers, distinguishing a stale preview from the completed translation.
"""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def method(source, start):
    beginning = source.index(start)
    index = source.index('{', beginning) + 1
    depth = 1
    while depth:
        depth += (source[index] == '{') - (source[index] == '}')
        index += 1
    return source[beginning:index]


@unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler required')
class CameraExportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = (ROOT / 'apps/ios/Camera/CameraModel.swift').read_text()
        methods = '\n'.join(method(source, name) for name in (
            '    var canSave:', '    func renderedPicture()', '    func sharePicture()'))
        # iOS file protection is unavailable on the Mac host; export content/ordering is unchanged.
        methods = methods.replace(',.completeFileProtection', '')
        fixture = r'''
import Foundation
struct TranslatedImageBlock: Sendable { let text: String }
struct UIImage: Sendable { let blocks: [String]
    func jpegData(compressionQuality: Double) -> Data? { try? JSONEncoder().encode(blocks) }
}
struct CGImage: Sendable { let width: CGFloat = 100; let height: CGFloat = 100 }
enum CameraError: Error { case image }
enum CameraOverlay {
    static let photoQuality = 0.9
    static func render(size: CGSize, blocks: [TranslatedImageBlock]) -> UIImage { UIImage(blocks: blocks.map(\.text)) }
    static func composite(_ image: CGImage, overlay: UIImage) -> UIImage { overlay }
}
@MainActor final class Translation {
    var complete = true
    var translated = [TranslatedImageBlock(text: "first"), TranslatedImageBlock(text: "last")]
}
@MainActor final class CameraModelProbe {
    var frame: CGImage? = CGImage()
    var frozen: UIImage? = UIImage(blocks: [])
    var overlay: UIImage? = UIImage(blocks: ["first"])
    let translation = Translation()
    var recognizing = false
    var error: String?
''' + methods + r'''
}
@main struct Probe {
    @MainActor static func main() async throws {
        let model = CameraModelProbe()
        var results: [String: Any] = [:]
        results["stalePreviewExport"] = try await model.renderedPicture().blocks
        let sharedFile = try await model.sharePicture()
        defer { try? FileManager.default.removeItem(at: sharedFile) }
        results["sharedBlocks"] = try JSONDecoder().decode([String].self, from: Data(contentsOf: sharedFile))
        model.overlay = nil
        results["pendingFirstPreviewCanSave"] = model.canSave
        results["pendingFirstPreviewExport"] = (try? await model.renderedPicture().blocks) ?? []
        model.translation.complete = false
        results["incompleteCanSave"] = model.canSave
        results["incompleteRejected"] = (try? await model.renderedPicture()) == nil
        model.translation.complete = true
        model.recognizing = true
        results["recognizingCanSave"] = model.canSave
        model.recognizing = false
        model.error = "failed"
        results["failedCanSave"] = model.canSave
        print(String(data: try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''
        with tempfile.TemporaryDirectory(prefix='kat-camera-export-') as tmp:
            work = Path(tmp)
            (work / 'probe.swift').write_text(fixture)
            build = subprocess.run(['swiftc', '-module-cache-path', str(ROOT / '.build/validation-camera-export/ModuleCache'),
                                    '-parse-as-library', str(work / 'probe.swift'), '-o', str(work / 'probe')],
                                   capture_output=True, text=True, timeout=60)
            if build.returncode:
                raise AssertionError(build.stderr)
            run = subprocess.run([str(work / 'probe')], capture_output=True, text=True, timeout=10, check=True)
            cls.results = json.loads(run.stdout)

    def test_export_uses_final_blocks_while_preview_is_stale(self):
        self.assertEqual(self.results['stalePreviewExport'], ['first', 'last'])

    def test_sharing_uses_the_same_final_blocks(self):
        self.assertEqual(self.results['sharedBlocks'], ['first', 'last'])

    def test_export_does_not_wait_for_the_first_preview(self):
        self.assertTrue(self.results['pendingFirstPreviewCanSave'])
        self.assertEqual(self.results['pendingFirstPreviewExport'], ['first', 'last'])

    def test_incomplete_and_failed_work_cannot_be_exported(self):
        self.assertFalse(self.results['incompleteCanSave'])
        self.assertTrue(self.results['incompleteRejected'])
        self.assertFalse(self.results['recognizingCanSave'])
        self.assertFalse(self.results['failedCanSave'])


if __name__ == '__main__':
    unittest.main()
