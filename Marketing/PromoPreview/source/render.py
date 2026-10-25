#!/usr/bin/env python3
"""Render original product-video layouts with unaltered native simulator screenshots."""
from pathlib import Path
import base64, json, threading
from functools import partial
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from playwright.sync_api import sync_playwright

ROOT=Path(__file__).resolve().parents[1]
NAMES=['01-opening','02-notes','03-finance','04-voice','05-privacy','06-ending']
LABELS=['00—05 秒 · 开场','05—14 秒 · 随手记录','14—25 秒 · 管理收支','25—35 秒 · 语音交流','35—41 秒 · 私人空间','41—45 秒 · 品牌收尾']

def render():
    class QuietHandler(SimpleHTTPRequestHandler):
        def log_message(self,format,*args):pass
    server=ThreadingHTTPServer(('127.0.0.1',0),partial(QuietHandler,directory=str(ROOT)))
    threading.Thread(target=server.serve_forever,daemon=True).start()
    base=f'http://127.0.0.1:{server.server_port}'
    with sync_playwright() as p:
        browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox','--allow-file-access-from-files'])
        page=browser.new_page(viewport={'width':1080,'height':1920},device_scale_factor=1)
        for i,name in enumerate(NAMES,1):
            page.goto(base+f'/source/frames.html?frame={i}')
            page.evaluate('document.fonts.ready')
            page.wait_for_function('Array.from(document.images).every(i => i.complete && i.naturalWidth > 0)')
            page.screenshot(path=str(ROOT/'keyframes'/f'{name}.png'))
        browser.close()

    cards=''.join(f'<article><img src="keyframes/{n}.png"><div>{label}</div></article>' for n,label in zip(NAMES,LABELS))
    overview='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><style>
    *{box-sizing:border-box}body{margin:0;background:#e9eef5;font-family:"Noto Sans CJK SC",sans-serif;color:#2b3546;width:1788px;padding:52px 48px 40px}header{display:flex;align-items:baseline;justify-content:space-between;margin-bottom:34px}h1{font-size:36px;margin:0;letter-spacing:1px}header span{font-size:21px;color:#738198}.grid{display:grid;grid-template-columns:repeat(3,540px);gap:28px 32px}article{overflow:hidden;border-radius:18px;background:#f9fbff;box-shadow:0 8px 28px #43547012}article img{width:540px;height:960px;display:block}article div{height:61px;display:flex;align-items:center;padding:0 23px;font-size:21px;letter-spacing:1px;color:#65738a}footer{font-size:20px;margin-top:32px;color:#8592a6;display:flex;justify-content:space-between}</style>
    <header><h1>个人助理 · 宣传片视觉预览</h1><span>45 秒 / 竖屏 9:16 / 第一版</span></header><div class="grid">'''+cards+'''</div><footer><span>真实应用界面 · 虚构演示数据 · 关键画面预览</span><span>浅色留白 / 玻璃质感 / 蓝色点缀</span></footer></html>'''
    (ROOT/'overview.html').write_text(overview)
    with sync_playwright() as p:
        browser=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox','--allow-file-access-from-files'])
        page=browser.new_page(viewport={'width':1788,'height':2600},device_scale_factor=1)
        page.goto(base+'/overview.html');page.evaluate('document.fonts.ready')
        page.wait_for_function('Array.from(document.images).every(i => i.complete && i.naturalWidth > 0)')
        height=page.locator('body').bounding_box()['height']
        page.screenshot(path=str(ROOT/'宣传片-关键画面总览.png'),clip={'x':0,'y':0,'width':1788,'height':height})
        browser.close()
    embedded=[]
    for n in NAMES:
        embedded.append('data:image/png;base64,'+base64.b64encode((ROOT/'keyframes'/f'{n}.png').read_bytes()).decode())
    preview='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>个人助理 · 宣传片视觉预览</title><style>*{box-sizing:border-box}body{margin:0;background:#e9eef5;color:#27344a;font-family:system-ui,sans-serif}.top{max-width:1080px;margin:auto;padding:24px;display:flex;align-items:center;justify-content:space-between}h1{font-size:20px;margin:0}.muted{color:#758197;font-size:13px}.stage{height:calc(100dvh - 155px);min-height:300px;display:flex;justify-content:center;align-items:center}.stage img{height:100%;max-width:94vw;object-fit:contain;border-radius:15px;box-shadow:0 12px 60px #24395e22}.controls{display:flex;gap:22px;justify-content:center;align-items:center;margin:20px 0}button{border:0;background:white;border-radius:30px;padding:12px 22px;color:#31558d;font-size:16px;cursor:pointer}#label{font-size:14px;text-align:center;min-width:160px}.note{max-width:1000px;padding:0 24px 24px;margin:auto;text-align:center;line-height:1.6}</style><div class="top"><h1>个人助理 · 宣传片视觉预览</h1><span class="muted">第一版 / 45 秒分镜</span></div><div class="stage"><img id="frame"></div><div class="controls"><button onclick="move(-1)">← 上一张</button><span id="label"></span><button onclick="move(1)">下一张 →</button></div><div class="note muted">当前为关键画面预览，尚未制作完整转场与配乐。界面来自真实 iOS 模拟器，使用虚构演示数据；语音画面为界面演示。</div><script>const images='''+json.dumps(embedded)+''';const labels='''+json.dumps(LABELS,ensure_ascii=False)+''';let current=0;function draw(){document.querySelector('#frame').src=images[current];document.querySelector('#label').textContent=labels[current]+' · '+(current+1)+'/6'}function move(d){current=(current+d+6)%6;draw()}document.addEventListener('keydown',e=>{if(e.key==='ArrowRight')move(1);if(e.key==='ArrowLeft')move(-1)});draw()</script></html>'''
    (ROOT/'宣传片-逐张预览.html').write_text(preview)
    pdf_html='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>个人助理 · 宣传片关键画面预览</title><style>@page{size:1080px 1920px;margin:0}*{box-sizing:border-box}html,body{margin:0;padding:0}.slide{width:1080px;height:1920px;break-after:page}.slide:last-child{break-after:auto}.slide img{width:1080px;height:1920px;display:block}</style><body>'''+''.join(f'<div class="slide"><img src="{src}"></div>' for src in embedded)+'</body></html>'
    with sync_playwright() as p:
        browser=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
        page=browser.new_page(viewport={'width':1080,'height':1920})
        page.set_content(pdf_html,wait_until='load')
        page.wait_for_function('Array.from(document.images).every(i => i.complete && i.naturalWidth > 0)')
        page.pdf(path=str(ROOT/'宣传片-高清分镜预览.pdf'),prefer_css_page_size=True,print_background=True)
        browser.close()
    for n in NAMES:
        assert (ROOT/'keyframes'/f'{n}.png').stat().st_size>10000
    print(json.dumps({'keyframes':6,'resolution':[1080,1920],'overview':str(ROOT/'宣传片-关键画面总览.png'),'preview':str(ROOT/'宣传片-逐张预览.html')},ensure_ascii=False))
    server.shutdown();server.server_close()

if __name__=='__main__':render()
