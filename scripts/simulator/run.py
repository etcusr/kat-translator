#!/usr/bin/env python3
"""Build real Kat and run navigation tests in a dedicated, persistent iOS Simulator.

Never selects a physical device, erases a simulator, downloads models or modifies
the installed Mac/iPhone app. Xcode and an installed ARM64 iOS runtime are required.
"""
from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / ".build/KatSimulatorUITests"
DERIVED = ROOT / ".build/SimulatorDerivedData"
BUNDLE = "app.kattranslator"
DEVICE_NAME = "Kat iPhone 17 Pro"


def capture(*args: str) -> str:
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def run(log: Path, *args: str) -> None:
    print(f"{args[0]}: {log.relative_to(ROOT)}", flush=True)
    with log.open("w") as output:
        result = subprocess.run(args, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        print(log.read_text(errors="replace")[-6000:], file=sys.stderr)
        raise SystemExit(result.returncode)


def prepare_runner(model_check: bool = False) -> Path:
    """Generate an independent XCTest runner, with no app build target dependency."""
    project = WORK / "Control.xcodeproj"
    (project / "xcshareddata/xcschemes").mkdir(parents=True, exist_ok=True)
    objects: dict = {}

    def add(identity: str, isa: str, **fields: object) -> str:
        key = hashlib.sha1(identity.encode()).hexdigest()[:24].upper()
        objects[key] = dict(isa=isa, **fields)
        return key

    def value(item: object) -> str:
        if isinstance(item, dict):
            return "{ " + " ".join(f"{k} = {value(v)};" for k, v in item.items()) + " }"
        if isinstance(item, list):
            return "(" + ", ".join(value(v) for v in item) + ")"
        return json.dumps(str(item))

    refs, builds = [], []
    for source in [ROOT / "scripts/validation/apple-settings-ui.swift",
                   ROOT / ("scripts/simulator/ModelSmokeTests.swift" if model_check else "scripts/simulator/SimulatorNavigationTests.swift")]:
        ref = add(str(source), "PBXFileReference", lastKnownFileType="sourcecode.swift",
                  path=str(source), sourceTree="<absolute>")
        refs.append(ref)
        builds.append(add("build:" + str(source), "PBXBuildFile", fileRef=ref))
    product = add("product", "PBXFileReference", explicitFileType="wrapper.cfbundle",
                  path="SimulatorUITests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
    products = add("products", "PBXGroup", children=[product], name="Products", sourceTree="<group>")
    group = add("group", "PBXGroup", children=refs + [products], sourceTree="<group>")
    sources = add("sources", "PBXSourcesBuildPhase", buildActionMask=2147483647,
                  files=builds, runOnlyForDeploymentPostprocessing=0)
    common = dict(SDKROOT="iphonesimulator", IPHONEOS_DEPLOYMENT_TARGET="18.0",
                  SWIFT_VERSION="5.0", CLANG_ENABLE_MODULES="YES", CODE_SIGNING_ALLOWED="NO")
    config = add("project-config", "XCBuildConfiguration", name="Debug", buildSettings=common)
    configs = add("project-configs", "XCConfigurationList", buildConfigurations=[config],
                  defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")
    test_config = add("test-config", "XCBuildConfiguration", name="Debug", buildSettings=dict(
        PRODUCT_NAME="$(TARGET_NAME)", PRODUCT_BUNDLE_IDENTIFIER="app.kattranslator.simulatoruitests",
        GENERATE_INFOPLIST_FILE="YES", SUPPORTED_PLATFORMS="iphonesimulator",
        TARGETED_DEVICE_FAMILY="1", SWIFT_OPTIMIZATION_LEVEL="-Onone"))
    test_configs = add("test-configs", "XCConfigurationList", buildConfigurations=[test_config],
                       defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")
    target = add("test-target", "PBXNativeTarget", name="SimulatorUITests", productName="SimulatorUITests",
                 productType="com.apple.product-type.bundle.ui-testing", productReference=product,
                 buildConfigurationList=test_configs, buildPhases=[sources], dependencies=[], buildRules=[])
    root = add("project", "PBXProject", buildConfigurationList=configs, compatibilityVersion="Xcode 14.0",
               developmentRegion="en", knownRegions=["en"], mainGroup=group, productRefGroup=products,
               projectDirPath="", projectRoot="", targets=[target], attributes={"LastUpgradeCheck": "2700"})
    (project / "project.pbxproj").write_text("// !$*UTF8*$!\n" + value(dict(
        archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=root)) + "\n")
    reference = (f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" '
                 'BuildableName="SimulatorUITests.xctest" BlueprintName="SimulatorUITests" '
                 'ReferencedContainer="container:Control.xcodeproj"/>')
    (project / "xcshareddata/xcschemes/Control.xcscheme").write_text(
        '<?xml version="1.0"?><Scheme version="1.3">'
        '<BuildAction parallelizeBuildables="NO" buildImplicitDependencies="NO"><BuildActionEntries>'
        '<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" '
        f'buildForArchiving="NO" buildForAnalyzing="YES">{reference}</BuildActionEntry>'
        '</BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" '
        'selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" '
        'selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables>'
        f'<TestableReference skipped="NO">{reference}</TestableReference>'
        '</Testables></TestAction></Scheme>')
    return project


def simulator() -> str:
    runtimes = json.loads(capture("xcrun", "simctl", "list", "runtimes", "-j"))["runtimes"]
    model_id = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
    ios = [r for r in runtimes if r.get("isAvailable")
           and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
           and any(t["identifier"] == model_id for t in r.get("supportedDeviceTypes", []))]
    if not ios:
        raise SystemExit("Install an iPhone 17 Pro compatible runtime: xcodebuild -downloadPlatform iOS -buildVersion 27.0 -architectureVariant arm64")
    runtime = max(ios, key=lambda r: tuple(map(int, r["version"].split("."))))
    devices = json.loads(capture("xcrun", "simctl", "list", "devices", "-j"))["devices"].get(runtime["identifier"], [])
    existing = next((d for d in devices if d["name"] == DEVICE_NAME and d.get("isAvailable")
                     and d.get("deviceTypeIdentifier") == model_id), None)
    if existing:
        return existing["udid"]
    print(f"Creating iPhone 17 Pro with {runtime['name']}", flush=True)
    return capture("xcrun", "simctl", "create", DEVICE_NAME, model_id, runtime["identifier"])



def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-build", action="store_true", help="reuse the existing simulator app (may be stale)")
    parser.add_argument("--prepare-only", action="store_true", help="generate the UI-test project without booting a device")
    parser.add_argument("--headless", action="store_true", help="do not open Simulator.app")
    parser.add_argument("--model-check", action="store_true", help="check seeded models and one short translation instead of mode navigation")
    args = parser.parse_args()
    project = prepare_runner(args.model_check)
    if args.prepare_only:
        print(project)
        return
    logs = WORK / "runs" / datetime.now().strftime("%Y%m%d-%H%M%S")
    logs.mkdir(parents=True)
    device = simulator()
    if not args.skip_build:
        run(logs / "app-build.log", "xcodebuild", "-project", str(ROOT / "apps/ios/OfflineTranslator.xcodeproj"),
            "-scheme", "OfflineTranslator", "-configuration", "Debug", "-sdk", "iphonesimulator",
            "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(DERIVED),
            "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES", "CODE_SIGNING_ALLOWED=NO", "build")
    app = DERIVED / "Build/Products/Debug-iphonesimulator/OfflineTranslator.app"
    if not app.exists():
        raise SystemExit("Simulator app missing; run without --skip-build")
    states = json.loads(capture("xcrun", "simctl", "list", "devices", "-j"))["devices"]
    state = next(d for entries in states.values() for d in entries if d["udid"] == device)
    if state["state"] != "Booted":
        run(logs / "boot.log", "xcrun", "simctl", "boot", device)
    run(logs / "bootstatus.log", "xcrun", "simctl", "bootstatus", device, "-b")
    if not args.headless:
        developer = Path(capture("xcode-select", "-p"))
        candidates = [developer / "Applications/Simulator.app",
                      developer.parent / "Applications/Simulator.app",
                      developer.parent / "Applications/DeviceHub.app"]
        viewer = next((p for p in candidates if p.exists()), None)
        if viewer is None:
            raise SystemExit("Simulator/Device Hub viewer missing in the selected Xcode; use --headless")
        subprocess.run(["open", "-a", str(viewer), "--args", "-CurrentDeviceUDID", device], check=True)
    run(logs / "install.log", "xcrun", "simctl", "install", device, str(app))
    run(logs / "launch.log", "xcrun", "simctl", "launch", "--terminate-running-process", device, BUNDLE,
        "-languageSetupCompleted", "YES", "-automaticModelLoad", "NO", "-appInterfaceLanguage", "en", "-showTechnicalInfo", "NO")
    run(logs / "tests.log", "xcodebuild", "test", "-project", str(project), "-scheme", "Control",
        "-destination", f"platform=iOS Simulator,id={device}", "-derivedDataPath", str(WORK / "Derived"),
        "-resultBundlePath", str(logs / "Navigation.xcresult"), "-parallel-testing-enabled", "NO",
        "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES", "CODE_SIGNING_ALLOWED=NO",
        *(["-only-testing:SimulatorUITests/ModelSmokeTests"] if args.model_check else []))
    run(logs / "result-summary.log", "xcrun", "xcresulttool", "get", "test-results", "summary",
        "--path", str(logs / "Navigation.xcresult"))
    summary = json.loads((logs / "result-summary.log").read_text())
    if summary.get("passedTests", 0) < 2 or summary.get("failedTests", 0) or summary.get("skippedTests", 0):
        raise SystemExit("Expected both navigation tests to pass without skips; inspect the result bundle.")
    run(logs / "screenshots.log", "xcrun", "xcresulttool", "export", "attachments",
        "--path", str(logs / "Navigation.xcresult"), "--output-path", str(logs / "screenshots"))
    print(f"PASS: both selected UI tests. Results: {logs.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
