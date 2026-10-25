#!/usr/bin/env python3
"""Record an actual Simulator session while XCTest performs the product walkthrough."""
import json,os,signal,subprocess,threading,time
from pathlib import Path

out=Path('build');out.mkdir(exist_ok=True)
device=os.environ['SIMULATOR_ID']
ready=threading.Event();meta={'launch_epoch':time.time(),'device':device,'capture':'native simctl H.264 screen recording'}
recorder=subprocess.Popen(['xcrun','simctl','io',device,'recordVideo','--codec=h264','--force',str(out/'product-demo-raw.mp4')],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1)
def read_recording_log():
    with (out/'screen-recording.log').open('w') as log:
        for line in recorder.stdout:
            log.write(line);log.flush()
            if 'Recording started' in line and not ready.is_set():
                meta['started_epoch']=time.time();ready.set()
thread=threading.Thread(target=read_recording_log,daemon=True);thread.start()
ready.wait(15)
if 'started_epoch' not in meta:
    if recorder.poll() is not None:raise RuntimeError('Simulator recording did not start')
    meta['started_epoch']=meta['launch_epoch'];meta['clock_fallback']=True
command=['xcodebuild','-project','PersonalAssistant.xcodeproj','-scheme','PersonalAssistant','-configuration','Debug','-derivedDataPath','build/DemoDerived','-destination','platform=iOS Simulator,id='+device,'-resultBundlePath','build/ProductDemo.xcresult','-only-testing:AssistantUITests/PromoDemoTests','-parallel-testing-enabled','NO','-test-timeouts-enabled','YES','-default-test-execution-time-allowance','300','-maximum-test-execution-time-allowance','360','CODE_SIGNING_ALLOWED=NO','ONLY_ACTIVE_ARCH=YES','test-without-building']
try:
    with (out/'product-demo.log').open('w') as log:
        result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=480)
finally:
    meta['stopped_epoch']=time.time()
    recorder.send_signal(signal.SIGINT)
    try:recorder.wait(timeout=90)
    except subprocess.TimeoutExpired:recorder.terminate();recorder.wait(timeout=15)
    thread.join(timeout=5)
    meta['recording_returncode']=recorder.returncode
    (out/'recording-metadata.json').write_text(json.dumps(meta,indent=2)+'\n')
if result.returncode:
    print((out/'product-demo.log').read_text()[-14000:]);raise SystemExit(result.returncode)
assert (out/'product-demo-raw.mp4').stat().st_size>100000,'No actual screen recording produced'
print('Actual walkthrough recording complete.')
