#!/usr/bin/env python3
"""Select a stable Xcode with an iOS 26+ SDK, so glass is native rather than a visual imitation."""
import glob,os,re,subprocess
choices=[]
for app in glob.glob('/Applications/Xcode*.app'):
    if re.search(r'beta|candidate|_RC',app,re.I):continue
    developer=app+'/Contents/Developer'
    env=dict(os.environ,DEVELOPER_DIR=developer)
    try:
        version=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-version'],env=env,text=True,stderr=subprocess.DEVNULL).strip()
        parts=tuple(map(int,version.split('.')))
        if parts[0]>=26:choices.append((parts,developer,version))
    except (subprocess.CalledProcessError,ValueError):pass
assert choices,'A stable Xcode with an iOS 26+ SDK is required'
_,developer,version=max(choices)
with open(os.environ['GITHUB_ENV'],'a') as f:f.write('DEVELOPER_DIR='+developer+'\n')
print('Selected',developer,'with iOS SDK',version)
