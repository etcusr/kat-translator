"""Generate a disposable, separately signed iPhone probe; never edits Kat's project."""
import argparse
import hashlib
import plistlib
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("output", type=Path)
p.add_argument("--native-build", type=Path, required=True)
p.add_argument("--whisper-source", type=Path, required=True)
p.add_argument("--mlx-audio", type=Path)
p.add_argument("--team", required=True)
a = p.parse_args()
out = a.output.resolve()
out.mkdir(parents=True, exist_ok=True)
src = Path(__file__).resolve().parent
objects = {}


def add(identity, isa, **values):
    key = hashlib.sha256(identity.encode()).hexdigest()[:24].upper()
    objects[key] = dict(isa=isa, **values)
    return key


refs, sources = [], []
for filename in ["Phone.mm", "Bench.mm", "CoreMLBridge.mm"] + (["MLXRunner.swift"] if a.mlx_audio else []):
    ref = add(filename, "PBXFileReference", path=str(src / filename),
              sourceTree="<absolute>", lastKnownFileType="sourcecode.swift" if filename.endswith(".swift") else "sourcecode.cpp.objcpp")
    refs.append(ref)
    sources.append(add(filename + "-build", "PBXBuildFile", fileRef=ref))
product = add("app", "PBXFileReference", explicitFileType="wrapper.application",
              path="WhisperProbe.app", sourceTree="BUILT_PRODUCTS_DIR")
group = add("group", "PBXGroup", children=refs + [product], sourceTree="<group>")
libs = sorted(str(x.resolve()) for x in a.native_build.rglob("*.a") if x.name != "libparakeet.a")
flags = libs + [s for name in ["UIKit", "CoreGraphics", "Foundation", "Metal", "MetalKit", "Accelerate", "CoreML"]
                for s in ["-framework", name]]
settings = dict(
    SDKROOT="iphoneos", IPHONEOS_DEPLOYMENT_TARGET="18.0",
    PRODUCT_NAME="WhisperProbe", PRODUCT_MODULE_NAME="WhisperProbe",
    PRODUCT_BUNDLE_IDENTIFIER="app.kattranslator.whisper-research",
    INFOPLIST_FILE="Info.plist", CODE_SIGN_ENTITLEMENTS="Probe.entitlements",
    CODE_SIGN_STYLE="Automatic", DEVELOPMENT_TEAM=a.team, TARGETED_DEVICE_FAMILY="1",
    CLANG_ENABLE_OBJC_ARC="YES", CLANG_CXX_LANGUAGE_STANDARD="c++17",
    GCC_OPTIMIZATION_LEVEL="2", SWIFT_OPTIMIZATION_LEVEL="-O", SWIFT_VERSION="6.0",
    GCC_PREPROCESSOR_DEFINITIONS=["BENCH_IOS=1"] + (["BENCH_MLX=1"] if a.mlx_audio else []),
    HEADER_SEARCH_PATHS=[str(a.whisper_source.resolve() / name) for name in ["include", "ggml/include", "src/coreml"]],
    OTHER_LDFLAGS=flags, LD_RUNPATH_SEARCH_PATHS=["@executable_path/Frameworks"],
)
config = add("release", "XCBuildConfiguration", name="Release", buildSettings=settings)
config_list = add("config-list", "XCConfigurationList", buildConfigurations=[config], defaultConfigurationName="Release")
phase = add("sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=sources, runOnlyForDeploymentPostprocessing=0)
resources = add("resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
packages, products, frameworks = [], [], []
if a.mlx_audio:
    package = add("mlx-package", "XCLocalSwiftPackageReference", relativePath=str(a.mlx_audio.resolve()))
    packages.append(package)
    for name in ["MLXAudioSTT", "MLXAudioCore"]:
        prod = add(name, "XCSwiftPackageProductDependency", package=package, productName=name)
        products.append(prod)
        frameworks.append(add(name + "-link", "PBXBuildFile", productRef=prod))
link_phase = add("frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=frameworks, runOnlyForDeploymentPostprocessing=0)
target = add("target", "PBXNativeTarget", name="WhisperProbe", productName="WhisperProbe",
             productType="com.apple.product-type.application", productReference=product,
             buildConfigurationList=config_list, buildPhases=[phase, resources, link_phase],
             dependencies=[], buildRules=[], packageProductDependencies=products)
pc = add("project-config", "XCBuildConfiguration", name="Release", buildSettings={})
pcl = add("project-configs", "XCConfigurationList", buildConfigurations=[pc], defaultConfigurationName="Release")
project = add("project", "PBXProject", buildConfigurationList=pcl, compatibilityVersion="Xcode 14.0",
              developmentRegion="en", mainGroup=group, projectDirPath="", projectRoot="", targets=[target],
              packageReferences=packages, attributes={"LastUpgradeCheck": "2700"})
projdir = out / "WhisperProbe.xcodeproj"
projdir.mkdir(exist_ok=True)
(projdir / "project.pbxproj").write_bytes(plistlib.dumps(dict(archiveVersion="1", objectVersion="56", classes={}, objects=objects, rootObject=project)))
(out / "Info.plist").write_bytes(plistlib.dumps(dict(
    CFBundleDisplayName="Whisper Research", CFBundleExecutable="$(EXECUTABLE_NAME)",
    CFBundleIdentifier="$(PRODUCT_BUNDLE_IDENTIFIER)", CFBundleName="Whisper Research",
    CFBundlePackageType="APPL", CFBundleShortVersionString="1.0", CFBundleVersion="1",
    LSRequiresIPhoneOS=True, UILaunchScreen={}, UIRequiredDeviceCapabilities=["arm64"],
    UIApplicationSceneManifest={"UIApplicationSupportsMultipleScenes": False,
        "UISceneConfigurations": {"UIWindowSceneSessionRoleApplication": [{
            "UISceneConfigurationName": "Default Configuration", "UISceneDelegateClassName": "Delegate"}]}},
)))
(out / "Probe.entitlements").write_bytes(plistlib.dumps({"com.apple.developer.kernel.increased-memory-limit": True}))
print(projdir)
