#!/usr/bin/env python3
import hashlib,json,plistlib,struct,sys,zipfile
from pathlib import Path
p=Path(sys.argv[1])
with zipfile.ZipFile(p) as z:
    assert z.testzip() is None
    info=plistlib.loads(z.read('Payload/PersonalAssistant.app/Info.plist'))
    binary=z.read('Payload/PersonalAssistant.app/'+info['CFBundleExecutable'])
    assert binary[:4]==b'\xcf\xfa\xed\xfe','Expected a device Mach-O arm64 executable'
    assert struct.unpack_from('<I',binary,4)[0]==0x100000c,'Expected arm64 CPU'
    command_count=struct.unpack_from('<I',binary,16)[0];offset=32
    platform=None;encrypted=False
    for _ in range(command_count):
        cmd,size=struct.unpack_from('<II',binary,offset)
        if cmd==0x32:platform=struct.unpack_from('<I',binary,offset+8)[0]
        if cmd in (0x21,0x2c):encrypted=struct.unpack_from('<I',binary,offset+16)[0]!=0
        offset+=size
    assert platform==2,'Must be an iOS-device build, not a simulator bundle'
    assert not encrypted,'A re-signable build must not be App Store encrypted'
    assert all(marker not in binary for marker in [b'--ui-companion-fixture',b'--ui-companion-delivery-fixture',b'--ui-companion-group-slow-fixture']), 'Release build must not contain simulated companion replies'
    assert b'MIT' in z.read('Payload/PersonalAssistant.app/OpenSourceLicenses.txt'),'Bundled open-source license is required'
    assert info['CFBundleShortVersionString']=='3.5.1'
    assert info['CFBundleVersion']=='14'
    assert str(info.get('DTSDKName','')).startswith('iphoneos26'), 'An iOS 26 SDK build is required'
    assert 'Payload/PersonalAssistant.app/CompanionModel.gguf' not in z.namelist(), 'Retired companion weights must not be bundled'
    result={'version':'3.5.1','build':'14','sdk':info.get('DTSDKName'),'platform':'iOS device','architecture':'arm64','unsigned':True,'fairplay_encrypted':False,'minimum_ios':info.get('MinimumOSVersion'),'bundle_id':info['CFBundleIdentifier'],'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'device_installation_verified':False,'companion_engine':'deepseek-flash','companion_model_bundled':False,'live_conversation_evaluation_performed':False}
    p.with_suffix('.verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))
