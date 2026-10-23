#!/usr/bin/env python3
"""Generate an ordinary Xcode project without Homebrew or third-party project generators."""
from pathlib import Path
import hashlib, json, plistlib

ROOT=Path(__file__).resolve().parents[1]
objects={}
def uid(value): return hashlib.sha256(value.encode()).hexdigest()[:24].upper()
def add(identity,isa,**values):
    key=uid(identity); objects[key]={'isa':isa,**values}; return key
def ref(path,kind): return add('file:'+path,'PBXFileReference',lastKnownFileType=kind,path=path,sourceTree='SOURCE_ROOT')
def build(file): return add('build:'+file,'PBXBuildFile',fileRef=file)
def configs(name,values):
    entries=[]
    for mode in ['Debug','Release']:
        settings=dict(values)
        settings.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if mode=='Debug' else '', 'DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym'})
        entries.append(add(name+mode,'XCBuildConfiguration',name=mode,buildSettings=settings))
    return add(name+'configs','XCConfigurationList',buildConfigurations=entries,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
sources=[];resources=[];groups=[]
for p in sorted((ROOT/'App').rglob('*')):
    if p.suffix in ['.swift','.cpp']:
        file=ref(str(p.relative_to(ROOT)),'sourcecode.swift' if p.suffix=='.swift' else 'sourcecode.cpp.cpp');sources.append(build(file));groups.append(file)
for p in [ROOT/'App/Resources/Assets.xcassets',ROOT/'App/Resources/AccountPresets.json',ROOT/'App/Resources/CardArtwork.json',ROOT/'App/Resources/PrivacyInfo.xcprivacy',ROOT/'App/Resources/OpenSourceLicenses.txt']:
    file=ref(str(p.relative_to(ROOT)),'folder.assetcatalog' if p.suffix=='.xcassets' else 'text.plist.xml' if p.suffix=='.xcprivacy' else 'text' if p.suffix=='.txt' else 'text.json');resources.append(build(file));groups.append(file)
app=add('product','PBXFileReference',explicitFileType='wrapper.application',path='PersonalAssistant.app',sourceTree='BUILT_PRODUCTS_DIR')
product_refs=[app]
app_id=uid('app-target')
app_config={
 'PRODUCT_NAME':'PersonalAssistant','PRODUCT_BUNDLE_IDENTIFIER':'cn.local.assistant.ios','INFOPLIST_FILE':'App/Info.plist','MARKETING_VERSION':'3.5.1','CURRENT_PROJECT_VERSION':'1',
 'SWIFT_VERSION':'5.0','SWIFT_OBJC_BRIDGING_HEADER':'App/Native/BridgingHeader.h','CLANG_CXX_LANGUAGE_STANDARD':'c++17',
 'CODE_SIGN_STYLE':'Automatic','TARGETED_DEVICE_FAMILY':'1','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos',
 'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES':'AppIconSky AppIconPeach','ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS':'YES',
 'HEADER_SEARCH_PATHS':['$(inherited)','$(PROJECT_DIR)/App/Native','$(PROJECT_DIR)/Vendor/llama.cpp/include','$(PROJECT_DIR)/Vendor/llama.cpp/ggml/include'],
 'OTHER_LDFLAGS[sdk=iphoneos*]':['$(inherited)','-Wl,-force_load,$(PROJECT_DIR)/NativeBuild/iphoneos/lib/libllama.a','-Wl,-force_load,$(PROJECT_DIR)/NativeBuild/iphoneos/lib/libggml.a','-Wl,-force_load,$(PROJECT_DIR)/NativeBuild/iphoneos/lib/libggml-base.a','-Wl,-force_load,$(PROJECT_DIR)/NativeBuild/iphoneos/lib/libggml-cpu.a','-Wl,-force_load,$(PROJECT_DIR)/NativeBuild/iphoneos/lib/libggml-metal.a','-Wl,-force_load,$(PROJECT_DIR)/NativeBuild/iphoneos/lib/libggml-blas.a','-framework','Accelerate','-framework','Metal','-framework','MetalKit','-framework','Foundation','-lc++'],
 'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks'],'ENABLE_TESTABILITY':'YES','GENERATE_INFOPLIST_FILE':'NO'
}
app_phases=[add('sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=sources,runOnlyForDeploymentPostprocessing=0),add('frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0),add('resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=resources,runOnlyForDeploymentPostprocessing=0)]
add('app-target','PBXNativeTarget',name='PersonalAssistant',productName='PersonalAssistant',productReference=app,productType='com.apple.product-type.application',buildConfigurationList=configs('app',app_config),buildPhases=app_phases,buildRules=[],dependencies=[])
test_ids=[]
for name,folder,ui in [('AssistantTests','Tests/iOSTests',False),('AssistantUITests','Tests/UITests',True)]:
    files=[]
    for p in sorted((ROOT/folder).rglob('*.swift')):
        file=ref(str(p.relative_to(ROOT)),'sourcecode.swift');groups.append(file);files.append(build(file))
    product=add('product:'+name,'PBXFileReference',explicitFileType='wrapper.cfbundle',path=name+'.xctest',sourceTree='BUILT_PRODUCTS_DIR');product_refs.append(product)
    proxy=add('proxy:'+name,'PBXContainerItemProxy',containerPortal=uid('project'),proxyType=1,remoteGlobalIDString=app_id,remoteInfo='PersonalAssistant')
    dependency=add('dependency:'+name,'PBXTargetDependency',target=app_id,targetProxy=proxy)
    settings={'PRODUCT_NAME':name,'PRODUCT_BUNDLE_IDENTIFIER':'cn.local.assistant.ios.'+name,'SWIFT_VERSION':'5.0','GENERATE_INFOPLIST_FILE':'YES','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','TARGETED_DEVICE_FAMILY':'1','CODE_SIGN_STYLE':'Automatic'}
    if ui: settings['TEST_TARGET_NAME']='PersonalAssistant'
    else: settings.update({'TEST_HOST':'$(BUILT_PRODUCTS_DIR)/PersonalAssistant.app/PersonalAssistant','BUNDLE_LOADER':'$(TEST_HOST)'})
    target=add('target:'+name,'PBXNativeTarget',name=name,productName=name,productReference=product,productType='com.apple.product-type.bundle.ui-testing' if ui else 'com.apple.product-type.bundle.unit-test',buildConfigurationList=configs(name,settings),buildPhases=[add(name+'sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=files,runOnlyForDeploymentPostprocessing=0),add(name+'frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)],buildRules=[],dependencies=[dependency]);test_ids.append(target)
products=add('products','PBXGroup',children=product_refs,name='Products',sourceTree='<group>')
group=add('main','PBXGroup',children=groups+[products],sourceTree='<group>')
project=add('project','PBXProject',attributes={'LastUpgradeCheck':'1600','BuildIndependentTargetsInParallel':'YES','TargetAttributes':{app_id:{'CreatedOnToolsVersion':'16.0'}}},buildConfigurationList=configs('project',{'CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','ENABLE_USER_SCRIPT_SANDBOXING':'YES'}),compatibilityVersion='Xcode 14.0',developmentRegion='zh-Hans',hasScannedForEncodings=0,knownRegions=['zh-Hans','en','Base'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[app_id]+test_ids)
def quote(s): return json.dumps(str(s),ensure_ascii=False)
def serialize(value):
    if isinstance(value,dict):return '{\n'+''.join(quote(k)+' = '+serialize(v)+';\n' for k,v in value.items())+'}'
    if isinstance(value,list):return '('+','.join(serialize(v) for v in value)+')'
    if isinstance(value,int):return str(value)
    return quote(value)
directory=ROOT/'PersonalAssistant.xcodeproj';directory.mkdir(exist_ok=True)
(directory/'project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n')
schemes=directory/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
def reference(target,name,product):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:PersonalAssistant.xcodeproj"/>'
app_ref=reference(app_id,'PersonalAssistant','PersonalAssistant.app')
tests=''.join('<TestableReference skipped="NO">'+reference(t,n,n+'.xctest')+'</TestableReference>' for t,n in zip(test_ids,['AssistantTests','AssistantUITests']))
(schemes/'PersonalAssistant.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>{tests}</Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Generated PersonalAssistant.xcodeproj with',len(sources),'app sources')
