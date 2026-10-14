#!/usr/bin/env python3
"""Generate the small Xcode project without a global XcodeGen dependency."""
from pathlib import Path
import hashlib, json, os, plistlib, subprocess, sys
root = Path(__file__).resolve().parent.parent
# The macOS generator executes this shared preamble too. Fail before project writes.
subprocess.run([sys.executable, str(root / 'scripts/update-animation-gallery.py'), '--check'], check=True)
subprocess.run([sys.executable, str(root / 'scripts/generate-model-catalog.py'), '--check'], check=True)
objects = {}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def obj(identifier, **fields):
    key = uid(identifier); objects[key] = fields; return key
def q(value):
    if isinstance(value, dict): return '{ ' + ' '.join(f'{k} = {q(v)};' for k,v in value.items()) + ' }'
    if isinstance(value, list): return '(' + ', '.join(q(v) for v in value) + ')'
    return json.dumps(str(value))
source_refs=[]; source_builds=[]; resource_builds=[]
def application_files():
    roots = ['shared/apple', 'shared/native/app', 'apps/ios', 'assets/catalogs', 'assets/bundled']
    for folder in roots:
        for file in (root/folder).rglob('*'):
            parts = file.relative_to(root/folder).parts
            if any(p in {'tests', 'widget', 'Config', 'Shared', 'build'} or p.endswith('.xcodeproj') for p in parts): continue
            yield file
for file in sorted(application_files()):
    if not file.is_file() or 'espeak-ng-data' in file.parts or any(part.endswith('.xcassets') for part in file.parts): continue
    rel = file.relative_to(root).as_posix()
    kind = {'.swift':'sourcecode.swift','.c':'sourcecode.c.c','.h':'sourcecode.c.h','.plist':'text.plist.xml','.xcstrings':'text.json.xcstrings','.xcprivacy':'text.xml'}.get(file.suffix,'text')
    ref=obj(rel, isa='PBXFileReference', lastKnownFileType=kind, path=rel, sourceTree='<group>')
    source_refs.append(ref)
    if file.suffix in ['.json', '.m4a', '.xcstrings', '.xcprivacy'] or rel in ['assets/bundled/ThirdPartyNotices.txt', 'assets/bundled/OCR/LICENSE.txt', 'assets/bundled/CatWizard/cat-wizard.mp4', 'assets/bundled/CatWizard/cat-wizard-poster.jpg'] or (file.parent.name == 'LoadingAnimations' and file.suffix in ['.mp4', '.jpg']): resource_builds.append(obj('resource:'+rel, isa='PBXBuildFile', fileRef=ref))
    if file.suffix in ['.swift','.c']: source_builds.append(obj('build:'+rel, isa='PBXBuildFile', fileRef=ref))
for catalog in sorted((root/'apps/ios/Resources').rglob('*.xcassets')):
    rel = catalog.relative_to(root).as_posix()
    ref = obj(rel, isa='PBXFileReference', lastKnownFileType='folder.assetcatalog', path=rel, sourceTree='<group>')
    source_refs.append(ref)
    resource_builds.append(obj('resource:'+rel, isa='PBXBuildFile', fileRef=ref))
espeak=obj('tts-espeak-data',isa='PBXFileReference',lastKnownFileType='folder',path='assets/bundled/espeak-ng-data',sourceTree='<group>')
source_refs.append(espeak)
resource_builds.append(obj('tts-espeak-resource',isa='PBXBuildFile',fileRef=espeak))
product=obj('product',isa='PBXFileReference',explicitFileType='wrapper.application',path='OfflineTranslator.app',sourceTree='BUILT_PRODUCTS_DIR')
framework=obj('whisper',isa='PBXFileReference',lastKnownFileType='wrapper.xcframework',path='Dependencies/build/whisper.xcframework',sourceTree='<group>')
fwbuild=obj('fwbuild',isa='PBXBuildFile',fileRef=framework)
extra_frameworks=[]; extra_builds=[]; embedded=[]
for name,path,dynamic in [('TranslationRuntime','translation/TranslationRuntime.xcframework',True),('SherpaOnnxC','speech/sherpa-onnx.xcframework',False),('onnxruntime','speech/onnxruntime.xcframework',False),('Python','wayu/Python.xcframework',True),('OmniVoiceRuntime','omnivoice/OmniVoiceRuntime.xcframework',True),('OpusRuntime','opus/OpusRuntime.xcframework',True)]:
    ref=obj(name,isa='PBXFileReference',lastKnownFileType='wrapper.xcframework',path='Dependencies/build/'+path,sourceTree='<group>')
    extra_frameworks.append(ref)
    extra_builds.append(obj('link:'+name,isa='PBXBuildFile',fileRef=ref))
    if dynamic: embedded.append(obj('embed:'+name,isa='PBXBuildFile',fileRef=ref,settings={'ATTRIBUTES':['CodeSignOnCopy','RemoveHeadersOnCopy']}))
embed=obj('embed',isa='PBXCopyFilesBuildPhase',buildActionMask='2147483647',dstPath='',dstSubfolderSpec='10',files=embedded,name='Embed Frameworks',runOnlyForDeploymentPostprocessing='0')
vad=obj('vad',isa='PBXFileReference',lastKnownFileType='file',path='Dependencies/build/speech/silero_vad.onnx',sourceTree='<group>')
source_refs.append(vad)
resource_builds.append(obj('vad-resource',isa='PBXBuildFile',fileRef=vad))
package=obj('corepackage',isa='XCLocalSwiftPackageReference',relativePath='../../shared/packages/OfflineCore')
packageproduct=obj('coreproduct',isa='XCSwiftPackageProductDependency',package=package,productName='OfflineCore')
packagebuild=obj('corebuild',isa='PBXBuildFile',productRef=packageproduct)
sources=obj('sources',isa='PBXSourcesBuildPhase',buildActionMask='2147483647',files=source_builds,runOnlyForDeploymentPostprocessing='0')
frameworks=obj('frameworks',isa='PBXFrameworksBuildPhase',buildActionMask='2147483647',files=[fwbuild,packagebuild]+extra_builds,runOnlyForDeploymentPostprocessing='0')
resources=obj('resources',isa='PBXResourcesBuildPhase',buildActionMask='2147483647',files=resource_builds,runOnlyForDeploymentPostprocessing='0')
products=obj('products',isa='PBXGroup',children=[product],name='Products',sourceTree='<group>')
config=obj('signingconfig',isa='PBXFileReference',lastKnownFileType='text.xcconfig',path='apps/ios/Config/Signing.xcconfig',sourceTree='<group>')
project_description=obj('project-description',isa='PBXFileReference',lastKnownFileType='net.daringfireball.markdown',path='PROJECT_DESCRIPTION.md',sourceTree='<group>')
brand_description=obj('brand-description',isa='PBXFileReference',lastKnownFileType='net.daringfireball.markdown',path='docs/branding/README.md',sourceTree='<group>')
project_info=obj('project-info',isa='PBXGroup',children=[project_description,brand_description],name='Kat translator — Project Info',sourceTree='<group>')
main=obj('main',isa='PBXGroup',children=[project_info]+source_refs+[framework,config,products]+extra_frameworks,path='../..',sourceTree='<group>')
common={'KAT_REPO_ROOT':'$(PROJECT_DIR)/../..','IPHONEOS_DEPLOYMENT_TARGET':'18.0','SDKROOT':'iphoneos','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','GCC_C_LANGUAGE_STANDARD':'gnu11','CLANG_CXX_LANGUAGE_STANDARD':'c++17','ENABLE_USER_SCRIPT_SANDBOXING':'YES','SWIFT_STRICT_CONCURRENCY':'targeted'}
targetsettings={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'app.kattranslator','INFOPLIST_FILE':'$(KAT_REPO_ROOT)/apps/ios/Info.plist','GENERATE_INFOPLIST_FILE':'NO','CODE_SIGN_STYLE':'Automatic','CODE_SIGN_ENTITLEMENTS':'$(KAT_REPO_ROOT)/apps/ios/OfflineTranslator.entitlements','TARGETED_DEVICE_FAMILY':'1','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','SWIFT_OBJC_BRIDGING_HEADER':'$(KAT_REPO_ROOT)/shared/apple/ASR/BridgingHeader.h','HEADER_SEARCH_PATHS':['$(inherited)','$(KAT_REPO_ROOT)/Dependencies/build/headers','$(KAT_REPO_ROOT)/shared/native/TranslationRuntime','$(KAT_REPO_ROOT)/Dependencies/build/speech/sherpa-onnx.xcframework/ios-arm64/SherpaOnnxC.framework/Headers'],'OTHER_LDFLAGS':['$(inherited)','-lc++','-framework','Accelerate','-framework','Metal','-framework','Foundation','-framework','CoreML'],'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks']}
projectconfigs=[]; targetconfigs=[]
targetsettings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
for name in ['Debug','Release']:
    settings=common|{'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if name=='Debug' else 'dwarf-with-dsym'}
    projectconfigs.append(obj('project'+name,isa='XCBuildConfiguration',buildSettings=settings,name=name))
    targetconfigs.append(obj('target'+name,isa='XCBuildConfiguration',baseConfigurationReference=config,buildSettings=targetsettings,name=name))
pcl=obj('pcl',isa='XCConfigurationList',buildConfigurations=projectconfigs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
tcl=obj('tcl',isa='XCConfigurationList',buildConfigurations=targetconfigs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
python_bundle=obj('python-bundle',isa='PBXShellScriptBuildPhase',buildActionMask='2147483647',files=[],inputPaths=[],outputPaths=[],name='Bundle offline Thai frontend',shellPath='/bin/bash',shellScript='bash "$KAT_REPO_ROOT/scripts/bundle-wayu-python.sh"',alwaysOutOfDate='1',runOnlyForDeploymentPostprocessing='0')
privacy_phase=obj('framework-privacy',isa='PBXShellScriptBuildPhase',buildActionMask='2147483647',files=[],inputPaths=[],outputPaths=[],name='Install framework privacy manifests',shellPath='/bin/bash',shellScript='python3 "$KAT_REPO_ROOT/scripts/install-ios-privacy-manifests.py" --app "$TARGET_BUILD_DIR/$WRAPPER_NAME"',alwaysOutOfDate='1',runOnlyForDeploymentPostprocessing='0')
identity_phase=obj('build-identity',isa='PBXShellScriptBuildPhase',buildActionMask='2147483647',files=[],inputPaths=[],outputPaths=['$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/BuildIdentity.plist'],name='Stamp build identity',shellPath='/bin/bash',shellScript='python3 "$KAT_REPO_ROOT/scripts/build-identity.py" --root "$KAT_REPO_ROOT" --platform "$PLATFORM_NAME" --output "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/BuildIdentity.plist"',alwaysOutOfDate='1',runOnlyForDeploymentPostprocessing='0')
targetsettings['ENABLE_USER_SCRIPT_SANDBOXING']='NO'
target=obj('target',isa='PBXNativeTarget',buildConfigurationList=tcl,buildPhases=[sources,frameworks,resources,python_bundle,embed,privacy_phase],buildRules=[],dependencies=[],name='OfflineTranslator',packageProductDependencies=[packageproduct],productName='OfflineTranslator',productReference=product,productType='com.apple.product-type.application')
project=obj('project',isa='PBXProject',attributes={'LastUpgradeCheck':'2700'},buildConfigurationList=pcl,compatibilityVersion='Xcode 14.0',developmentRegion='ru',hasScannedForEncodings='0',knownRegions=['ru','en','es','tr','Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',packageReferences=[package],targets=[target])
recognition_package=obj('recognition-package',isa='XCLocalSwiftPackageReference',relativePath='../../shared/packages/SpeechRecognitionRuntime')
recognition_product=obj('recognition-product',isa='XCSwiftPackageProductDependency',package=recognition_package,productName='SpeechRecognitionRuntime')
objects[project]['packageReferences'].append(recognition_package)
objects[target]['packageProductDependencies'].append(recognition_product)
objects[frameworks]['files'].append(obj('recognition-build',isa='PBXBuildFile',productRef=recognition_product))
# Lock Screen / Dynamic Island UI is isolated from inference frameworks.
shared_ref=obj('download-attributes',isa='PBXFileReference',lastKnownFileType='sourcecode.swift',path='apps/ios/widget/DownloadActivityAttributes.swift',sourceTree='<group>')
widget_ref=obj('download-widget',isa='PBXFileReference',lastKnownFileType='sourcecode.swift',path='apps/ios/widget/DownloadActivityWidget.swift',sourceTree='<group>')
widget_product=obj('download-widget-product',isa='PBXFileReference',explicitFileType='wrapper.app-extension',path='DownloadActivityExtension.appex',sourceTree='BUILT_PRODUCTS_DIR')
objects[main]['children'] += [shared_ref,widget_ref]
objects[products]['children'].append(widget_product)
objects[sources]['files'].append(obj('download-attributes-app-build',isa='PBXBuildFile',fileRef=shared_ref))
widget_sources=obj('download-widget-sources',isa='PBXSourcesBuildPhase',buildActionMask='2147483647',files=[obj('download-attributes-widget-build',isa='PBXBuildFile',fileRef=shared_ref),obj('download-widget-build',isa='PBXBuildFile',fileRef=widget_ref)],runOnlyForDeploymentPostprocessing='0')
# Share only the tiny vector drawing/motion with the widget, not the inference package.
cat_ref=obj('cat-drawing',isa='PBXFileReference',lastKnownFileType='sourcecode.swift',path='shared/apple/Shared/CatProgressDrawing.swift',sourceTree='<group>')
cat_motion_ref=obj('cat-widget-motion',isa='PBXFileReference',lastKnownFileType='sourcecode.swift',path='shared/packages/OfflineCore/Sources/OfflineCore/CatProgressMotion.swift',sourceTree='<group>')
objects[main]['children'] += [cat_ref,cat_motion_ref]
objects[sources]['files'].append(obj('cat-drawing-app-build',isa='PBXBuildFile',fileRef=cat_ref))
objects[widget_sources]['files'] += [obj('cat-drawing-widget-build',isa='PBXBuildFile',fileRef=cat_ref),obj('cat-motion-widget-build',isa='PBXBuildFile',fileRef=cat_motion_ref)]
widget_configs=[]
for name in ['Debug','Release']:
    widget_configs.append(obj('widget-config'+name,isa='XCBuildConfiguration',baseConfigurationReference=config,name=name,buildSettings={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'app.kattranslator.downloads','INFOPLIST_FILE':'$(KAT_REPO_ROOT)/apps/ios/widget/Info.plist','GENERATE_INFOPLIST_FILE':'YES','MARKETING_VERSION':plistlib.loads((root/'apps/ios/Info.plist').read_bytes())['CFBundleShortVersionString'],'CURRENT_PROJECT_VERSION':plistlib.loads((root/'apps/ios/Info.plist').read_bytes())['CFBundleVersion'],'CODE_SIGN_STYLE':'Automatic','TARGETED_DEVICE_FAMILY':'1','SKIP_INSTALL':'YES','APPLICATION_EXTENSION_API_ONLY':'YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'$(inherited) CAT_WIDGET','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks','@executable_path/../../Frameworks']}))
widget_config_list=obj('widget-config-list',isa='XCConfigurationList',buildConfigurations=widget_configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
widget_target=obj('widget-target',isa='PBXNativeTarget',buildConfigurationList=widget_config_list,buildPhases=[widget_sources],buildRules=[],dependencies=[],name='DownloadActivityExtension',productName='DownloadActivityExtension',productReference=widget_product,productType='com.apple.product-type.app-extension')
objects[project]['targets'].append(widget_target)
objects[target]['dependencies'].append(obj('widget-dependency',isa='PBXTargetDependency',target=widget_target))
widget_embed=obj('widget-embed',isa='PBXCopyFilesBuildPhase',buildActionMask='2147483647',dstPath='',dstSubfolderSpec='13',files=[obj('widget-embed-build',isa='PBXBuildFile',fileRef=widget_product,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})],name='Embed App Extensions',runOnlyForDeploymentPostprocessing='0')
objects[target]['buildPhases'].append(widget_embed)
objects[target]['buildPhases'].append(identity_phase)
# Download integration fixtures are explicitly excluded from normal builds.
if os.environ.get("OT_DOWNLOAD_VALIDATION_BUILD") == "1":
    targetsettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "$(inherited) DOWNLOAD_VALIDATION"
# Apple ASR uses only fixed local fixtures and is absent from shipping builds.
if os.environ.get('OT_APPLE_ASR_BUILD') == '1':
    targetsettings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) APPLE_SPEECH_PROBE'
    targetsettings['INFOPLIST_FILE'] = '$(KAT_REPO_ROOT)/.build/apple-asr/Info.plist'
# Additional experimental engines stay excluded from normal builds.
if os.environ.get('OT_ASR_BENCHMARK_BUILD') == '1':
    targetsettings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) ASR_COMPARISON_PROBE'
    probe_package=obj('asr-probe-package',isa='XCLocalSwiftPackageReference',relativePath='../../.build/asr-comparison/ProbeSupport')
    probe_product=obj('asr-probe-product',isa='XCSwiftPackageProductDependency',package=probe_package,productName='ASRProbeSupport')
    objects[project]['packageReferences'].append(probe_package)
    objects[target]['packageProductDependencies'].append(probe_product)
    objects[frameworks]['files'].append(obj('asr-probe-build',isa='PBXBuildFile',productRef=probe_product))
# On-device UI regressions use the production app and preserve its data.
ui_ref=obj('ui-source',isa='PBXFileReference',lastKnownFileType='sourcecode.swift',path='apps/ios/tests/ui/TranslatorUITests.swift',sourceTree='<group>')
ui_product=obj('ui-product',isa='PBXFileReference',explicitFileType='wrapper.cfbundle',path='TranslatorUITests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
objects[main]['children'].append(ui_ref); objects[products]['children'].append(ui_product)
ui_sources=obj('ui-sources',isa='PBXSourcesBuildPhase',buildActionMask='2147483647',files=[obj('ui-build',isa='PBXBuildFile',fileRef=ui_ref)],runOnlyForDeploymentPostprocessing='0')
opus_ui_ref=obj('opus-ui-source',isa='PBXFileReference',lastKnownFileType='sourcecode.swift',path='shared/apple/tests/OpusUITests.swift',sourceTree='<group>')
objects[main]['children'].append(opus_ui_ref)
objects[ui_sources]['files'].append(obj('opus-ui-build',isa='PBXBuildFile',fileRef=opus_ui_ref))
ui_configs=[]
for name in ['Debug','Release']:
    ui_configs.append(obj('ui-config'+name,isa='XCBuildConfiguration',baseConfigurationReference=config,name=name,buildSettings={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'app.kattranslator.uitests','GENERATE_INFOPLIST_FILE':'YES','CODE_SIGN_STYLE':'Automatic','TARGETED_DEVICE_FAMILY':'1','TEST_TARGET_NAME':'OfflineTranslator','SWIFT_VERSION':'5.0'}))
ui_config_list=obj('ui-config-list',isa='XCConfigurationList',buildConfigurations=ui_configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
ui_dependency=obj('ui-dependency',isa='PBXTargetDependency',target=target)
ui_target=obj('ui-target',isa='PBXNativeTarget',buildConfigurationList=ui_config_list,buildPhases=[ui_sources],buildRules=[],dependencies=[ui_dependency],name='TranslatorUITests',productName='TranslatorUITests',productReference=ui_product,productType='com.apple.product-type.bundle.ui-testing')
objects[project]['targets'].append(ui_target)
# Hosted benchmarks are absent from ordinary projects and release builds.
article_testable = ''
if os.environ.get('KAT_MTP_TEST_BUILD') == '1' or os.environ.get('KAT_ARTICLE_BENCHMARK_BUILD') == '1' or os.environ.get('KAT_VOICE_ORIGINAL_TEST_BUILD') == '1' or os.environ.get('KAT_VOICE_AUTO_TEST_BUILD') == '1':
    targetsettings['ENABLE_TESTABILITY'] = 'YES'
    benchmark_refs=[]
    hosted_files = [('tests/benchmarks/VoiceOriginalIntegrationTests.swift','sourcecode.swift')] if os.environ.get('KAT_VOICE_ORIGINAL_TEST_BUILD') == '1' else [('tests/benchmarks/ArticleDeviceBenchmarkTests.swift','sourcecode.swift'),('tests/fixtures/article-device-benchmark.json','text.json')]
    if os.environ.get('KAT_MTP_TEST_BUILD') == '1':
        hosted_files = [('tests/benchmarks/IndexMTPIntegrationTests.swift','sourcecode.swift'),('tests/fixtures/index-mtp-cases.json','text.json')]
    if os.environ.get('KAT_VOICE_AUTO_TEST_BUILD') == '1':
        hosted_files = [('tests/benchmarks/VoiceAutoRoutingIntegrationTests.swift','sourcecode.swift')]
    for rel,kind in hosted_files:
        ref_b=obj(rel,isa='PBXFileReference',lastKnownFileType=kind,path=rel,sourceTree='<group>')
        objects[main]['children'].append(ref_b)
        benchmark_refs.append(obj('build:'+rel,isa='PBXBuildFile',fileRef=ref_b))
    bproduct=obj('article-product',isa='PBXFileReference',explicitFileType='wrapper.cfbundle',path='ArticleRuntimeTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
    objects[products]['children'].append(bproduct)
    bsource=obj('article-sources',isa='PBXSourcesBuildPhase',buildActionMask='2147483647',files=benchmark_refs[:1],runOnlyForDeploymentPostprocessing='0')
    bresources=obj('article-resources',isa='PBXResourcesBuildPhase',buildActionMask='2147483647',files=benchmark_refs[1:],runOnlyForDeploymentPostprocessing='0')
    bsettings={'PRODUCT_NAME':'ArticleRuntimeTests','PRODUCT_BUNDLE_IDENTIFIER':'app.kattranslator.articletests','GENERATE_INFOPLIST_FILE':'YES','CODE_SIGN_STYLE':'Automatic','TARGETED_DEVICE_FAMILY':'1','SWIFT_VERSION':'5.0','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/OfflineTranslator.app/OfflineTranslator','BUNDLE_LOADER':'$(TEST_HOST)','HEADER_SEARCH_PATHS':targetsettings['HEADER_SEARCH_PATHS'],'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks','@loader_path/Frameworks']}
    bconfigs=[obj('article-config'+n,isa='XCBuildConfiguration',baseConfigurationReference=config,name=n,buildSettings=bsettings) for n in ['Debug','Release']]
    bcl=obj('article-configs',isa='XCConfigurationList',buildConfigurations=bconfigs,defaultConfigurationName='Release',defaultConfigurationIsVisible='0')
    btarget=obj('article-target',isa='PBXNativeTarget',buildConfigurationList=bcl,buildPhases=[bsource,bresources],buildRules=[],dependencies=[obj('article-dependency',isa='PBXTargetDependency',target=target)],name='ArticleRuntimeTests',productName='ArticleRuntimeTests',productReference=bproduct,productType='com.apple.product-type.bundle.unit-test')
    objects[project]['targets'].append(btarget)
    article_testable=f'<TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{btarget}" BuildableName="ArticleRuntimeTests.xctest" BlueprintName="ArticleRuntimeTests" ReferencedContainer="container:OfflineTranslator.xcodeproj"/></TestableReference>'
test_arguments = ''
if os.environ.get('KAT_VOICE_AUTO_TEST_BUILD') == '1':
    test_arguments = '<CommandLineArguments><CommandLineArgument argument="-automaticModelLoad" isEnabled="YES"/><CommandLineArgument argument="NO" isEnabled="YES"/></CommandLineArguments>'
# WRITE_IOS_PROJECT
out=root/'apps/ios/OfflineTranslator.xcodeproj'; out.mkdir(exist_ok=True)
text='// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'
text+='\n'.join(f'{key} = {q(value)};' for key,value in objects.items())
text+='\n}; rootObject = '+project+'; }\n'
(out/'project.pbxproj').write_text(text)
scheme=out/'xcshareddata/xcschemes'; scheme.mkdir(parents=True,exist_ok=True)
ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="OfflineTranslator.app" BlueprintName="OfflineTranslator" ReferencedContainer="container:OfflineTranslator.xcodeproj"/>'
(scheme/'OfflineTranslator.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Release" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB">{test_arguments}<Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="TranslatorUITests.xctest" BlueprintName="TranslatorUITests" ReferencedContainer="container:OfflineTranslator.xcodeproj"/></TestableReference>{article_testable}</Testables></TestAction>
<LaunchAction buildConfiguration="Release" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(out)
