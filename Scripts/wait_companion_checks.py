#!/usr/bin/env python3
"""Release only the exact commit whose companion checks succeeded."""
import json,os,subprocess,sys,time

run_id=int(sys.argv[1])
repo=os.environ['GITHUB_REPOSITORY']
revision=os.environ['GITHUB_SHA']
for _ in range(120):
    run=json.loads(subprocess.check_output(['gh','api',f'repos/{repo}/actions/runs/{run_id}'],text=True))
    assert run['head_sha']==revision, 'UI check must match packaged source commit'
    assert run['workflow_id']==395701280, 'Unexpected verification workflow'
    if run['status']=='completed':
        assert run['conclusion']=='success', 'Companion checks failed; refusing to publish the package'
        print('Verified companion checks for exact source commit '+revision);break
    print('Waiting for companion checks: '+run['status'],flush=True)
    time.sleep(10)
else:
    raise SystemExit('Companion verification did not finish in time')
