#!/usr/bin/env python3
"""Publish only to a verified private repository, then start the internal checks/build."""
from pathlib import Path
import argparse,hashlib,json,subprocess,time

root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--repo',default='3824yyds/PersonalAssistant-Internal')
args=parser.parse_args()
assert args.repo=='3824yyds/PersonalAssistant-Internal', 'Unexpected research repository'

def output(*command):
    return subprocess.check_output(command,cwd=root,text=True).strip()
def run(*command):
    subprocess.run(command,cwd=root,check=True)

metadata=json.loads(output('gh','api','repos/'+args.repo))
assert metadata.get('private') is True, 'STOP: research source and weights must never be pushed to a public repository'
assert metadata['full_name']==args.repo
assert not output('git','status','--porcelain','--untracked-files=no'), 'Commit implementation changes before building'
run('python3','Scripts/verify_companion_model.py')
run('git','-c','credential.helper=','-c','credential.helper=!gh auth git-credential','push','https://github.com/'+args.repo+'.git','HEAD:main')
tag='companion-model-225'
release=subprocess.run(['gh','release','view',tag,'--repo',args.repo,'--json','assets'],cwd=root,text=True,stdout=subprocess.PIPE)
if release.returncode:
    run('gh','release','create',tag,'--repo',args.repo,'--target','main','--prerelease','--latest=false','--title','Frozen checkpoint-225 research model','--notes','Private internal research only. Q4_K_M, 986048064 bytes; SHA256 07fcb0fdd9a9e116f3ddb0926a5f9059fc8f9e3369f6455b80397cab562c4f4f. No additional training.')
    assets=[]
else:
    assets=json.loads(release.stdout)['assets']
asset=next((asset for asset in assets if asset['name']=='CompanionModel.gguf'),None)
if asset:
    assert asset['size']==986048064, 'Existing model asset has wrong size; do not replace it automatically'
else:
    run('gh','release','upload',tag,str(root/'App/Resources/CompanionModel.gguf'),'--repo',args.repo)
for attempt in range(6):
    started=subprocess.run(['gh','workflow','run','internal-companion.yml','--repo',args.repo,'--ref','main'],cwd=root)
    if started.returncode==0:break
    if attempt==5:raise SystemExit('Workflow did not become available')
    time.sleep(2)
print('Started private build: https://github.com/'+args.repo+'/actions/workflows/internal-companion.yml')
