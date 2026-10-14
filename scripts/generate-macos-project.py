#!/usr/bin/env python3
"""Generate a separate native macOS project without changing the iOS project."""
from pathlib import Path
import plistlib, shutil, sys, subprocess, os, runpy
root=Path(__file__).resolve().parent.parent
profile_name=os.environ.get('KAT_MAC_PROFILE','modern')
mac_profile=runpy.run_path(str(root/'scripts/mac-build-profile.py'))['profile'](profile_name)
mac_info='$(KAT_REPO_ROOT)/apps/macos/Info.plist'
if profile_name != 'modern':
    generated=root/'.build/macos15-config/Info.plist'
    generated.parent.mkdir(parents=True,exist_ok=True)
    data=plistlib.loads((root/'apps/macos/Info.plist').read_bytes())
    data['LSMinimumSystemVersion']=mac_profile['minimum']
    data['KatBuildProfile']=profile_name
    generated.write_bytes(plistlib.dumps(data,sort_keys=False))
    mac_info='$(KAT_REPO_ROOT)/.build/macos15-config/Info.plist' 
ns={'__file__':str(root/'scripts/generate-project.py')}
source=(root/'scripts/generate-project.py').read_text().split('# WRITE_IOS_PROJECT')[0]
exec(compile(source,ns['__file__'],'exec'),ns)
objects=ns['objects']; obj=ns['obj']; q=ns['q']; uid=ns['uid']
# Retain common code/resources, replace UIKit/capture/diagnostic-only surfaces.
skip={'apps/ios/OfflineTranslatorApp.swift','apps/ios/Camera/CameraCapture.swift','apps/ios/Camera/CameraView.swift','apps/ios/Camera/CameraModel.swift','apps/ios/Camera/CameraOverlay.swift','apps/ios/Conversation/CatWizardView.swift','apps/ios/Models/DownloadLiveActivity.swift','apps/ios/Diagnostics/RecordingPreviewProbe.swift','apps/ios/widget/DownloadActivityAttributes.swift'}
def path_for_build(key): return objects.get(objects[key].get('fileRef'),{}).get('path','')
objects[ns['sources']]['files']=[k for k in objects[ns['sources']]['files'] if path_for_build(k) not in skip]
objects[ns['resources']]['files']=[k for k in objects[ns['resources']]['files'] if not path_for_build(k).endswith('.xcassets') and path_for_build(k) not in {'apps/ios/Resources/InfoPlist.xcstrings', 'apps/ios/Resources/PrivacyInfo.xcprivacy'}]
for p in sorted((root/'apps/macos').rglob('*')):
 if 'tests' in p.relative_to(root/'apps/macos').parts or any(v.endswith('.xcodeproj') for v in p.parts): continue
 if p.suffix not in ['.swift','.icns','.strings']: continue
 rel=str(p.relative_to(root));ref=obj('mac:'+rel,isa='PBXFileReference',lastKnownFileType='sourcecode.swift' if p.suffix=='.swift' else 'file',path=rel,sourceTree='<group>')
 objects[ns['main']]['children'].append(ref)
 phase=ns['sources'] if p.suffix=='.swift' else ns['resources']
 objects[phase]['files'].append(obj('macbuild:'+rel,isa='PBXBuildFile',fileRef=ref))
frameworks=[]
for name,path in [('Whisper','macos/libwhisper.a'),('Translation','macos/libTranslationRuntime.dylib'),('Sherpa','speech-macos/sherpa-onnx.xcframework'),('Onnx','macos/libonnxruntime.dylib'),('Python','macos/libpython3.11.dylib'),('Omni','omnivoice/OmniVoiceRuntime.xcframework'),('Opus','opus/OpusRuntime.xcframework')]:
 if name=='Python' and profile_name=='macos15':path='macos15/StandalonePython/python/lib/libpython3.11.dylib'
 ref=obj('macfw:'+name,isa='PBXFileReference',lastKnownFileType='wrapper.xcframework' if path.endswith('.xcframework') else 'archive.ar' if path.endswith('.a') else 'compiled.mach-o.dylib',path='Dependencies/build/'+path,sourceTree='<group>')
 objects[ns['main']]['children'].append(ref);frameworks.append(obj('maclink:'+name,isa='PBXBuildFile',fileRef=ref))
objects[ns['frameworks']]['files']=[ns['packagebuild'],uid('recognition-build')]+frameworks
bundle=obj('macbundle',isa='PBXShellScriptBuildPhase',buildActionMask='2147483647',files=[],inputPaths=[],outputPaths=[],name='Bundle standalone Mac runtimes',shellPath='/bin/bash',shellScript='python3 "$KAT_REPO_ROOT/scripts/bundle-macos-runtimes.py" "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"',alwaysOutOfDate='1',runOnlyForDeploymentPostprocessing='0')
objects[ns['target']]['buildPhases']=[ns['sources'],ns['frameworks'],ns['resources'],bundle,ns['identity_phase']]
objects[ns['target']]['dependencies']=[];objects[ns['target']]['name']='KatTranslatorMac';objects[ns['target']]['productName']='Kat translator'
objects[ns['product']]['path']='Kat translator.app'
objects[ns['project']]['targets']=[ns['target']]
objects[ns['products']]['children']=[ns['product']]
python_include=subprocess.check_output(['/opt/homebrew/opt/python@3.11/bin/python3.11','-c','import sysconfig; print(sysconfig.get_path("include"))'],text=True).strip()
if profile_name=='macos15':python_include='$(KAT_REPO_ROOT)/Dependencies/build/macos15/StandalonePython/python/include/python3.11'
for name in ['Debug','Release']:
 settings=objects[uid('project'+name)]['buildSettings'];settings.pop('IPHONEOS_DEPLOYMENT_TARGET',None);settings.update(SDKROOT='macosx',MACOSX_DEPLOYMENT_TARGET=mac_profile['deployment'],ARCHS='arm64')
 objects[uid('target'+name)].pop('baseConfigurationReference',None)
 objects[uid('target'+name)]['buildSettings']={
 'PRODUCT_NAME':'Kat translator','PRODUCT_BUNDLE_IDENTIFIER':'org.openoffline.translator.mac','INFOPLIST_FILE':mac_info,'KAT_MAC_PROFILE':profile_name,'GENERATE_INFOPLIST_FILE':'NO','CODE_SIGN_IDENTITY':'-','CODE_SIGN_STYLE':'Manual','ENABLE_HARDENED_RUNTIME':'NO','CODE_SIGN_ENTITLEMENTS':'$(KAT_REPO_ROOT)/apps/macos/KatMac.entitlements','SUPPORTED_PLATFORMS':'macosx','ENABLE_APP_SANDBOX':'NO','SWIFT_OBJC_BRIDGING_HEADER':'$(KAT_REPO_ROOT)/shared/apple/ASR/BridgingHeader.h','ENABLE_USER_SCRIPT_SANDBOXING':'NO',
 'HEADER_SEARCH_PATHS':['$(inherited)','$(KAT_REPO_ROOT)/Dependencies/build/headers','$(KAT_REPO_ROOT)/shared/native/TranslationRuntime','$(KAT_REPO_ROOT)/Dependencies/build/macos/headers','$(KAT_REPO_ROOT)/Dependencies/build/macos/headers',python_include],
 'LIBRARY_SEARCH_PATHS':['$(inherited)','$(KAT_REPO_ROOT)/Dependencies/build/macos'],
 'GCC_PREPROCESSOR_DEFINITIONS':['$(inherited)','OT_MACOS=1'],
 'OTHER_LDFLAGS':['$(inherited)','-lc++','-framework','Accelerate','-framework','Metal','-framework','Foundation','-framework','CoreML'],
 'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../Frameworks']}
# Hosted runtime tests and native UI tests exercise the actual packaged application.
for name in ['Debug','Release']:
 objects[uid('target'+name)]['buildSettings']['ENABLE_TESTABILITY']='YES'
test_targets=[]
for name,folder,kind in [('MacRuntimeTests','runtime','unit-test'),('MacUITests','ui','ui-testing')]:
 refs=[]
 test_files = sorted((root/'apps/macos/tests'/folder).glob('*.swift'))
 if name == 'MacUITests': test_files.append(root/'shared/apple/tests/OpusUITests.swift')
 if name == 'MacRuntimeTests': test_files.append(root/'tests/benchmarks/VoiceOriginalIntegrationTests.swift')
 if name == 'MacRuntimeTests' and os.environ.get('KAT_ARTICLE_BENCHMARK_BUILD') == '1':
  test_files.append(root/'tests/benchmarks/ArticleDeviceBenchmarkTests.swift')
 if name == 'MacRuntimeTests' and os.environ.get('KAT_AUDIO_IMPORT_TEST_BUILD') == '1':
  test_files.append(root/'tests/benchmarks/AudioImportIntegrationTests.swift')
 for file in test_files:
  rel=str(file.relative_to(root));ref=obj(rel,isa='PBXFileReference',lastKnownFileType='sourcecode.swift',path=rel,sourceTree='<group>')
  objects[ns['main']]['children'].append(ref);refs.append(obj('build:'+rel,isa='PBXBuildFile',fileRef=ref))
 product=obj(name+'product',isa='PBXFileReference',explicitFileType='wrapper.cfbundle',path=name+'.xctest',sourceTree='BUILT_PRODUCTS_DIR')
 objects[ns['products']]['children'].append(product)
 sources=obj(name+'sources',isa='PBXSourcesBuildPhase',buildActionMask='2147483647',files=refs,runOnlyForDeploymentPostprocessing='0')
 settings={'PRODUCT_NAME':name,'PRODUCT_BUNDLE_IDENTIFIER':'org.openoffline.translator.mac.'+name,'GENERATE_INFOPLIST_FILE':'YES','CODE_SIGN_IDENTITY':'-','CODE_SIGN_STYLE':'Manual','SWIFT_VERSION':'5.0','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@loader_path/../Frameworks','@executable_path/../Frameworks']}
 if kind=='unit-test':
  settings['HEADER_SEARCH_PATHS']=objects[uid('targetRelease')]['buildSettings']['HEADER_SEARCH_PATHS']
  settings['GCC_PREPROCESSOR_DEFINITIONS']=['$(inherited)','OT_MACOS=1']
  settings.update(TEST_HOST='$(BUILT_PRODUCTS_DIR)/Kat translator.app/Contents/MacOS/Kat translator',BUNDLE_LOADER='$(TEST_HOST)')
 else: settings['TEST_TARGET_NAME']='KatTranslatorMac'
 configs=[obj(name+n,isa='XCBuildConfiguration',name=n,buildSettings=settings) for n in ['Debug','Release']]
 cl=obj(name+'configs',isa='XCConfigurationList',buildConfigurations=configs,defaultConfigurationName='Release',defaultConfigurationIsVisible='0')
 phases=[sources]
 for flag,fixture in [('KAT_ARTICLE_BENCHMARK_BUILD','article-device-benchmark.json'),('KAT_AUDIO_IMPORT_TEST_BUILD','audio-import.m4a')]:
  if name != 'MacRuntimeTests' or os.environ.get(flag) != '1': continue
  rel='tests/fixtures/'+fixture
  ref=obj(rel,isa='PBXFileReference',lastKnownFileType='file',path=rel,sourceTree='<group>')
  objects[ns['main']]['children'].append(ref)
  phases.append(obj(name+'resources'+fixture,isa='PBXResourcesBuildPhase',buildActionMask='2147483647',files=[obj('build:'+rel,isa='PBXBuildFile',fileRef=ref)],runOnlyForDeploymentPostprocessing='0'))
 target=obj(name+'target',isa='PBXNativeTarget',buildConfigurationList=cl,buildPhases=phases,buildRules=[],dependencies=[obj(name+'dependency',isa='PBXTargetDependency',target=ns['target'])],name=name,productName=name,productReference=product,productType='com.apple.product-type.bundle.'+kind)
 objects[ns['project']]['targets'].append(target);test_targets.append((name,target))
out=root/'apps/macos/KatTranslatorMac.xcodeproj';out.mkdir(exist_ok=True)
(out/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(f'{key} = {q(value)};' for key,value in objects.items())+'\n}; rootObject = '+ns['project']+'; }\n')
scheme=out/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ns["target"]}" BuildableName="Kat translator.app" BlueprintName="KatTranslatorMac" ReferencedContainer="container:KatTranslatorMac.xcodeproj"/>'
(scheme/'KatTranslatorMac.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Release" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print(out)

schemefile=scheme/'KatTranslatorMac.xcscheme'
testables=''.join(f'<TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{tid}" BuildableName="{name}.xctest" BlueprintName="{name}" ReferencedContainer="container:KatTranslatorMac.xcodeproj"/></TestableReference>' for name,tid in test_targets)
testaction=f'<TestAction buildConfiguration="Release" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables>{testables}</Testables></TestAction>'
schemefile.write_text(schemefile.read_text().replace('<LaunchAction',testaction+'<LaunchAction'))
