"""Generate an isolated iPhone file-replay lab; never writes the shipping app project."""
import argparse, hashlib, plistlib, shutil, subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--work',type=Path,required=True);p.add_argument('--argmax',type=Path,required=True);p.add_argument('--team',required=True);a=p.parse_args()
repo=Path(__file__).resolve().parents[3];src=Path(__file__).resolve().parent;w=a.work.resolve();argmax=a.argmax.resolve()
assert '.build' in w.parts and '.build' in argmax.parts
assert subprocess.check_output(['git','-C',str(argmax),'rev-parse','HEAD'],text=True).strip() == '9f99b5cb6a907730543823ad271b82532782a899', 'Unexpected Argmax revision'
w.mkdir(exist_ok=True,parents=True);(w/'source').mkdir(exist_ok=True)
# All app support sources are frozen copies. Production files are not patched.
for source in [repo/'shared/apple/Translation/LlamaTranslationBackend.swift',repo/'shared/apple/Diagnostics/TranslationMemoryTrace.swift',repo/'shared/apple/Diagnostics/ResourceMonitor.swift',src/'Lab.swift',src/'ReplayAudio.swift']:
 shutil.copy2(source,w/'source'/source.name)
shutil.copy2(repo/'shared/native/TranslationRuntime/TranslationRuntime.h',w/'source/Bridge.h')
stream=argmax/'Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift'
original=subprocess.check_output(['git','-C',str(argmax),'show','HEAD:Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift'],text=True)
# Observability + a test-only permission bypass for supplied PCM. Recognition/confirmation stays upstream.
original=original.replace('    private var state: AudioStreamTranscriber.State', '    public var labPasses: [[String: Any]] = []\n    public func labSnapshot() -> State { state }\n    public func labStartFileReplay() async throws { try await startRecordingAndTranscribing() }\n    private var state: AudioStreamTranscriber.State',1)
original=original.replace('        let transcription = try await transcribeAudioSamples(Array(currentBuffer))','''        let labStart = ProcessInfo.processInfo.systemUptime
        let transcription = try await transcribeAudioSamples(Array(currentBuffer))
        labPasses.append(["samples": currentBuffer.count, "seconds": ProcessInfo.processInfo.systemUptime - labStart,
                          "text": transcription.text, "clipStart": state.lastConfirmedSegmentEndSeconds])''',1)
stream.write_text(original)
objects={}
def add(key,isa,**kw):
 k=hashlib.sha256(key.encode()).hexdigest()[:24].upper();objects[k]=dict(isa=isa,**kw);return k
refs=[];sourcebuild=[]
for f in sorted((w/'source').glob('*.swift')):
 r=add(f.name,'PBXFileReference',path=str(f),sourceTree='<absolute>',lastKnownFileType='sourcecode.swift');refs.append(r);sourcebuild.append(add(f.name+'-build','PBXBuildFile',fileRef=r))
packages=[];products=[];links=[]
for name,path in [('WhisperKit',argmax),('OfflineCore',repo/'shared/packages/OfflineCore')]:
 r=add(name+'-package','XCLocalSwiftPackageReference',relativePath=str(path));packages.append(r)
 pr=add(name+'-product','XCSwiftPackageProductDependency',package=r,productName=name);products.append(pr);links.append(add(name+'-link','PBXBuildFile',productRef=pr))
fw=add('mt','PBXFileReference',path=str(repo/'Dependencies/build/translation/TranslationRuntime.xcframework'),sourceTree='<absolute>',lastKnownFileType='wrapper.xcframework');refs.append(fw);links.append(add('mt-link','PBXBuildFile',fileRef=fw))
embed=add('embed','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=10,files=[add('mt-embed','PBXBuildFile',fileRef=fw,settings={'ATTRIBUTES':['CodeSignOnCopy','RemoveHeadersOnCopy']})],runOnlyForDeploymentPostprocessing=0)
product=add('app','PBXFileReference',explicitFileType='wrapper.application',path='WhisperKitLab.app',sourceTree='BUILT_PRODUCTS_DIR')
group=add('main','PBXGroup',children=refs+[product],sourceTree='<group>')
settings=dict(SDKROOT='iphoneos',IPHONEOS_DEPLOYMENT_TARGET='18.0',PRODUCT_NAME='WhisperKitLab',PRODUCT_MODULE_NAME='WhisperKitLab',PRODUCT_BUNDLE_IDENTIFIER='app.kattranslator.whisper-research',INFOPLIST_FILE='Info.plist',CODE_SIGN_ENTITLEMENTS='Lab.entitlements',CODE_SIGN_STYLE='Automatic',DEVELOPMENT_TEAM=a.team,TARGETED_DEVICE_FAMILY='1',SWIFT_VERSION='5.0',SWIFT_OPTIMIZATION_LEVEL='-O',SWIFT_OBJC_BRIDGING_HEADER=str(w/'source/Bridge.h'),CLANG_ENABLE_MODULES='YES',LD_RUNPATH_SEARCH_PATHS=['@executable_path/Frameworks'],OTHER_LDFLAGS=['-lc++','-framework','Metal','-framework','Accelerate'])
cfg=add('release','XCBuildConfiguration',name='Release',buildSettings=settings);cl=add('configs','XCConfigurationList',buildConfigurations=[cfg],defaultConfigurationName='Release')
sources=add('sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=sourcebuild,runOnlyForDeploymentPostprocessing=0)
link=add('link','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=links,runOnlyForDeploymentPostprocessing=0)
resources=add('resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
target=add('target','PBXNativeTarget',name='WhisperKitLab',productName='WhisperKitLab',productType='com.apple.product-type.application',productReference=product,buildConfigurationList=cl,buildPhases=[sources,resources,link,embed],dependencies=[],buildRules=[],packageProductDependencies=products)
pc=add('pc','XCBuildConfiguration',name='Release',buildSettings={});pcl=add('pcl','XCConfigurationList',buildConfigurations=[pc],defaultConfigurationName='Release')
project=add('project','PBXProject',buildConfigurationList=pcl,compatibilityVersion='Xcode 14.0',developmentRegion='en',mainGroup=group,projectDirPath='',projectRoot='',targets=[target],packageReferences=packages,attributes={'LastUpgradeCheck':'2700'})
proj=w/'WhisperKitLab.xcodeproj';proj.mkdir(exist_ok=True)
(proj/'project.pbxproj').write_bytes(plistlib.dumps(dict(archiveVersion='1',objectVersion='56',classes={},objects=objects,rootObject=project)))
(w/'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleDisplayName='Kat WhisperKit Lab',CFBundleExecutable='$(EXECUTABLE_NAME)',CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)',CFBundleName='WhisperKitLab',CFBundlePackageType='APPL',CFBundleShortVersionString='1.0',CFBundleVersion='1',LSRequiresIPhoneOS=True,UILaunchScreen={},UIRequiredDeviceCapabilities=['arm64'],UIApplicationSceneManifest={'UIApplicationSupportsMultipleScenes':False})))
(w/'Lab.entitlements').write_bytes(plistlib.dumps({'com.apple.developer.kernel.increased-memory-limit':True}))
print(proj)
