#!/usr/bin/env python3
"""Original framing and score for a native screen-recorded product demonstration."""
from pathlib import Path
from functools import partial
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
import threading,wave
import numpy as np
from playwright.sync_api import sync_playwright

ROOT=Path(__file__).resolve().parents[1]
RATE=48000
DURATION=45

def plates():
    html='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><style>*{box-sizing:border-box}html,body{margin:0;width:1080px;height:1920px;overflow:hidden;background:radial-gradient(ellipse at 70% 70%,#d9e9ff 0%,transparent 60%),linear-gradient(150deg,#fcfdff,#f1f6fd);font-family:"Noto Sans CJK SC",sans-serif}.brand{position:absolute;left:50px;top:28px;display:flex;align-items:center;gap:16px;color:#172435;font-size:29px;font-weight:600;letter-spacing:1px}.brand img{width:48px;height:48px;border-radius:13px;box-shadow:0 3px 12px #8d7e3c24}.device{position:absolute;left:132px;top:101px;width:816px;height:1752px;border-radius:80px;background:linear-gradient(120deg,#515a68,#111820 40%,#444e5f);box-shadow:0 18px 50px #1f385328,0 0 0 1px #fff9}.screen{position:absolute;left:8px;top:8px;width:800px;height:1736px;border-radius:69px;background:#f7f8fa}.button{position:absolute;left:129px;top:365px;width:3px;height:65px;background:#929ba8;border-radius:3px 0 0 3px;box-shadow:0 88px #929ba8}.button.right{left:948px;top:420px;height:105px;box-shadow:none;border-radius:0 3px 3px 0}</style><div class="brand"><img src="../assets/app-icon.png">个人助理</div><div class="device"><div class="screen"></div></div><div class="button"></div><div class="button right"></div></html>'''
    (ROOT/'source/plate.html').write_text(html)
    class Quiet(SimpleHTTPRequestHandler):
        def log_message(self,*args):pass
    server=ThreadingHTTPServer(('127.0.0.1',0),partial(Quiet,directory=str(ROOT)))
    threading.Thread(target=server.serve_forever,daemon=True).start()
    with sync_playwright() as p:
        browser=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
        page=browser.new_page(viewport={'width':1080,'height':1920},device_scale_factor=1)
        page.goto(f'http://127.0.0.1:{server.server_port}/source/plate.html');page.evaluate('document.fonts.ready')
        page.wait_for_function('document.images[0].complete && document.images[0].naturalWidth>0')
        page.screenshot(path=str(ROOT/'assets/plate.png'))
        page.set_viewport_size({'width':800,'height':1736})
        page.set_content('<style>html,body{margin:0;background:black;width:800px;height:1736px}div{width:800px;height:1736px;background:white;border-radius:69px}</style><div></div>')
        page.screenshot(path=str(ROOT/'assets/screen-mask.png'))
        browser.close()
    server.shutdown();server.server_close()

def music():
    samples=int(DURATION*RATE)
    track=np.zeros((samples,2),dtype=np.float64)
    rng=np.random.default_rng(20261025)
    def add(sound,at,gain=1,pan=0):
        start=int(at*RATE)
        if start>=samples:return
        sound=sound[:min(len(sound),samples-start)]*gain
        track[start:start+len(sound),0]+=sound*np.sqrt((1-pan)/2)
        track[start:start+len(sound),1]+=sound*np.sqrt((1+pan)/2)
    def hz(note):return 440*2**((note-69)/12)
    def key(note,duration=1.8):
        t=np.arange(int(duration*RATE))/RATE;f=hz(note)
        envelope=(1-np.exp(-t/0.008))*np.exp(-t/0.43)*np.minimum(1,(duration-t)/.1)
        return (np.sin(2*np.pi*f*t)+.18*np.sin(2*np.pi*2*f*t)+.055*np.sin(2*np.pi*3*f*t))*envelope
    chords=[[62,66,69,73],[59,62,66,69],[55,59,62,66],[57,61,64,71]]
    beat=60/96
    for step in range(int(DURATION/beat)+1):
        at=step*beat;chord=chords[int(at/5)%4]
        note=chord[[0,2,1,3,2,1,0,2][step%8]]+12
        add(key(note),at,.039,(-.22 if step%2==0 else .22))
        if step%4==0:
            add(key(chord[0]-12,2.2),at,.046,-.03)
        if step%2==1:
            t=np.arange(int(.06*RATE))/RATE
            tick=np.diff(rng.normal(0,1,len(t)+1))*np.exp(-t/.012)
            add(tick,at,.0025,.25)
    for i,at in enumerate(np.arange(0,DURATION,5)):
        chord=chords[i%4];duration=min(5.7,DURATION-at)
        t=np.arange(int(duration*RATE))/RATE
        pad=sum(np.sin(2*np.pi*hz(n)*t+.17*j)*.012 for j,n in enumerate(chord))
        pad*=np.minimum(1,t/.55)*np.minimum(1,(duration-t)/.8)
        add(pad,at,1,-.1 if i%2 else .1)
    fade=np.minimum(1,np.arange(samples)/RATE/.7)*np.minimum(1,(samples-1-np.arange(samples))/RATE/1.5)
    track*=fade[:,None]
    peak=np.max(np.abs(track));track*=.24/max(peak,1e-9)
    pcm=(np.clip(track,-1,1)*32767).astype('<i2')
    with wave.open(str(ROOT/'assets/original-score.wav'),'wb') as w:
        w.setnchannels(2);w.setsampwidth(2);w.setframerate(RATE);w.writeframes(pcm.tobytes())
    print('Original score:',DURATION,'sec; peak',round(float(np.max(np.abs(track))),4),'RMS',round(float(np.sqrt(np.mean(track*track))),4))

if __name__=='__main__':plates();music()
