"""Exercise production AppModel lifecycle methods with controlled capture/session completion."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def method(source, name):
    start = source.index("    " + name)
    brace = source.index("{", start)
    depth, end = 1, brace + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def ios_only(source):
    enabled, stack, lines = True, [], []
    for line in source.splitlines():
        stripped = line.strip()
        if stripped.startswith("#if os("):
            stack.append(enabled)
            enabled = enabled and stripped == "#if os(iOS)"
        elif stripped == "#else":
            enabled = stack[-1] and not enabled
        elif stripped == "#endif":
            enabled = stack.pop()
        elif enabled:
            lines.append(line)
    return "\n".join(lines)


class RecordingLifecycleTests(unittest.TestCase):
    def test_stop_and_foreground_races(self):
        source = (ROOT / "shared/apple/Conversation/AppModel.swift").read_text()
        start = source.index("    private struct DeferredRecording")
        stop = source.index("    func importAudioFile", start)
        methods = source[start:stop]
        for name in ["func background()", "func cancel()"]:
            methods += "\n" + method(source, name)
        for name in ["private func observeDeferredRecording()", "private func scheduleDeferredRecording()"]:
            if name in source and name not in methods:
                methods += "\n" + method(source, name)
        observer = "observeDeferredRecording()" if "private func observeDeferredRecording()" in source else ""
        fixture = (ROOT / "scripts/validation/fixtures/recording_lifecycle.swift").read_text()
        fixture = fixture.replace("// PRODUCTION_METHODS", ios_only(methods)).replace("// OBSERVE", observer)
        with tempfile.TemporaryDirectory(prefix="kat-recording-lifecycle-") as folder:
            swift, binary = Path(folder) / "probe.swift", Path(folder) / "probe"
            swift.write_text(fixture)
            build = subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", folder + "/modules", str(swift), "-o", str(binary)], capture_output=True, text=True)
            self.assertEqual(build.returncode, 0, build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("PASS: recording lifecycle", run.stdout)
