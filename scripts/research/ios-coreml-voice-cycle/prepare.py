"""Patch a disposable git-archive snapshot, never the production checkout."""
import argparse
import json
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("snapshot", type=Path)
p.add_argument("--native-build", type=Path, required=True)
a = p.parse_args()
root = a.snapshot.resolve()
src = Path(__file__).resolve().parent
assert ".build" in root.parts and root.name == "source"
assert not (root / ".git").exists()

def replace(path, old, new):
    f = root / path
    s = f.read_text()
    assert s.count(old) == 1, (path, old, s.count(old))
    f.write_text(s.replace(old, new, 1))

catalog = root / "assets/catalogs/models.json"
data = json.loads(catalog.read_text())
for model in data["models"]:
    if model["symbol"] == "turbo":
        model.update(id="whisper-large-v3-turbo-q8-lab", title="Whisper Core ML + Q8 · LAB",
                     byteCount=874188075,
                     sha256="317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1",
                     remoteURL="https://example.invalid/research-local-only")
catalog.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
subprocess.run([sys.executable, str(root / "scripts/generate-model-catalog.py")], check=True)
shutil.copyfile(src / "ResearchTrace.swift", root / "apps/ios/Diagnostics/ResearchTrace.swift")
shutil.copyfile(src / "VoiceLabUITests.swift", root / "apps/ios/tests/ui/TranslatorUITests.swift")
bridge = (src.parent / "apple-whisper-acceleration/CoreMLBridge.mm").read_text()
assert bridge.count("if (!model) return nullptr;") == 1
# A failed Core ML load must fail this experiment, not silently benchmark Metal.
bridge = bridge.replace("if (!model) return nullptr;", "if (!model) { fprintf(stderr, \"VOICE_LAB_COREML_REQUIRED_FAILED\\n\"); abort(); }")
bridge_path = root / "apps/ios/Diagnostics/ResearchCoreML.mm"
bridge_path.write_text(bridge)

replace("apps/ios/OfflineTranslatorApp.swift",
        "@StateObject private var model = AppModel()",
        "@StateObject private var model: AppModel = { ResearchTrace.configure(); return AppModel() }()")
replace("apps/ios/OfflineTranslatorApp.swift",
        "Task { await model.memoryWarning() }",
        'ResearchTrace.record("memory.warning"); Task { await model.memoryWarning() }')
replace("shared/apple/ASR/WhisperBackend.swift",
        "self.context = whisper_init_from_file_with_params(modelURL.path, params)",
        '''let baseline = ProcessInfo.processInfo.environment["LAB_BASELINE"] == "1"
                let actualURL = baseline ? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Research/f16.bin") : modelURL
                ResearchTrace.record("asr.load.begin", ["baseline": baseline])
                self.context = whisper_init_from_file_with_params(actualURL.path, params)
                ResearchTrace.record("asr.load.end", ["success": self.context != nil])''')
replace("shared/apple/ASR/WhisperBackend.swift",
        "let start = ProcessInfo.processInfo.systemUptime",
        'ResearchTrace.record("asr.begin", ["audioSeconds": audio.durationSeconds]); let start = ProcessInfo.processInfo.systemUptime')
replace("shared/apple/ASR/WhisperBackend.swift",
        "continuation.resume(returning: result)",
        'ResearchTrace.record("asr.end", ["seconds": result.processingSeconds]); continuation.resume(returning: result)')
replace("shared/apple/ASR/WhisperBackend.swift",
        "func unload() async {", 'func unload() async { ResearchTrace.record("asr.unload")')
replace("shared/apple/Conversation/AppModel.swift",
        "captureStarted = true", 'captureStarted = true; ResearchTrace.record("capture.started")')
replace("shared/apple/Conversation/AppModel.swift",
        "let audio = try await recorder.stop()",
        'let audio = try await recorder.stop(); ResearchTrace.record("capture.stopped", ["seconds": audio.durationSeconds])')
replace("shared/apple/Conversation/AppModel.swift",
        "await synchronizeRecognition() }\n        } catch is CancellationError",
        'await synchronizeRecognition() }\n            ResearchTrace.finished(self)\n        } catch is CancellationError')
replace("shared/apple/Speech/SpeechPlayer.swift",
        "if !paused { node.play() }",
        'if !paused { ResearchTrace.record("playback.started", ["outputVolume": AVAudioSession.sharedInstance().outputVolume, "route": AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")]); node.play() }')
replace("shared/apple/Speech/SpeechPlayer.swift",
        "waiting?.resume()", 'ResearchTrace.record("playback.finished"); waiting?.resume()')

info = root / "apps/ios/Info.plist"
d = plistlib.loads(info.read_bytes())
d["CFBundleDisplayName"] = "Kat Voice Lab"
d["CFBundleURLTypes"] = []
info.write_bytes(plistlib.dumps(d))
generator = root / "scripts/generate-project.py"
s = generator.read_text().replace("'app.kattranslator'", "'app.kattranslator.voicelab'")
s = s.replace("'app.kattranslator.downloads'", "'app.kattranslator.voicelab.downloads'")
s = s.replace("'app.kattranslator.uitests'", "'app.kattranslator.voicelab.uitests'")
# Link only the experimental whisper archive, keep all other app runtimes unchanged.
s = s.replace("files=[fwbuild,packagebuild]+extra_builds", "files=[packagebuild]+extra_builds")
libs = sorted(str(x.resolve()) for x in a.native_build.rglob("*.a") if x.name != "libparakeet.a")
insert = """
targetsettings['OTHER_LDFLAGS'] += %r
targetsettings['OTHER_CPLUSPLUSFLAGS'] = ['$(inherited)', '-fobjc-arc']
ref=obj('lab-coreml',isa='PBXFileReference',lastKnownFileType='sourcecode.cpp.objcpp',path=%r,sourceTree='<absolute>')
objects[main]['children'].append(ref)
objects[sources]['files'].append(obj('lab-coreml-build',isa='PBXBuildFile',fileRef=ref))
targetsettings['HEADER_SEARCH_PATHS'].append('$(KAT_REPO_ROOT)/Dependencies/vendor/whisper.cpp/src/coreml')
""" % (libs, str(bridge_path))
s = s.replace("# WRITE_IOS_PROJECT", insert + "\n# WRITE_IOS_PROJECT")
generator.write_text(s)
subprocess.run([sys.executable, str(generator)], check=True)
print(root)
