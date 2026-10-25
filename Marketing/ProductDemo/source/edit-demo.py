#!/usr/bin/env python3
"""Edit a continuous native Simulator recording into an actual 45-second product demo.

All app pixels come from recordVideo. This script removes idle waits and annotates
real input events; it never substitutes screenshots or fabricates app transitions.
"""
from pathlib import Path
import concurrent.futures,hashlib,json,math,subprocess,wave
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
FPS=30
RAW=ROOT/'raw/product-demo-raw.mp4'
SCENES=[
 ('notes',9.0,'01 / 写下想法','新建笔记，写好后点 ✓ 保存。'),
 ('ledger',8.5,'02 / 随手记账','记下 28 元咖啡支出，保存即入账。'),
 ('statistics',4.0,'03 / 看清收支','从流水切到统计，再看看收支日历。'),
 ('wallet',4.0,'04 / 管理账户','展开卡包，查看账户与余额。'),
 ('models',7.0,'05 / 选择模型','点击展开，左右滑动切换 Flash / Pro。'),
 ('chat',3.0,'06 / 聊聊日常','本机问候示例：发出消息，收到简短回应。'),
 ('voice',5.5,'07 / 语音模式','进入语音模式，静音与退出一键完成。'),
 ('privacy',4.0,'08 / 私人资料','一键锁定资料库，保护私人记录。')]

def command(args,log=None):
    result=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    if log:Path(log).write_text(result.stdout)
    if result.returncode:raise RuntimeError(result.stdout[-5000:])
    return result.stdout

def probe(path):
    return json.loads(command(['ffprobe','-v','error','-show_format','-show_streams','-of','json',str(path)]))

def load_events():
    for path in (ROOT/'raw').rglob('*'):
        if path.is_file() and path.suffix.lower() in ['.json','.txt']:
            try:obj=json.loads(path.read_text())
            except (UnicodeError,json.JSONDecodeError):continue
            if isinstance(obj,list) and obj and isinstance(obj[0],dict) and 'epoch' in obj[0] and 'name' in obj[0]:return obj
    raise RuntimeError('Actual XCTest operation timestamps were not exported')

def merge(windows):
    result=[]
    for a,b in sorted(windows):
        if b-a<.08:continue
        if result and a-result[-1][1]<.28:result[-1][1]=max(result[-1][1],b)
        else:result.append([a,b])
    return result

def plan_edit(events,meta,raw_info):
    duration=float(raw_info['format']['duration'])
    observed=meta['stopped_epoch']-meta['started_epoch']
    correction=duration-observed
    if abs(correction)>3:raise RuntimeError(f'Capture clock drift {correction:.2f}s needs inspection')
    def t(event):return event['epoch']-meta['started_epoch']+correction
    by_name={e['name']:e for e in events}
    end_event=by_name['finished']
    total_frames=0;output_start=0;scenes=[];pieces=[];taps=[]
    for index,(name,target,heading,caption) in enumerate(SCENES):
        start=t(by_name['scene.'+name])
        end=t(by_name['scene.'+SCENES[index+1][0]]) if index+1<len(SCENES) else t(end_event)
        actions=[];windows=[[start+.08,min(end,start+.65)]]
        for e in events:
            if not (start<=t(e)<end) or e.get('kind') not in ['tap','type','swipe']:continue
            finish=by_name.get(e['name'].removesuffix('.begin')+'.end')
            if not finish:continue
            a,b=t(e),t(finish)
            if e['kind']=='tap':a=max(a,b-1.55)
            tail=.23
            if name=='statistics':tail=1.15
            if name=='wallet' and e['name']=='wallet.card.begin':tail=1.2
            if name=='models' and e['kind']=='swipe':tail=.65
            if name=='voice':tail=.65
            windows.append([a-.08,b+tail]);actions.append((e,t(e),b))
        holds={'notes':('notes.saved',1.0),'ledger':('ledger.saved',1.0),'chat':('chat.replied',1.0),'privacy':('privacy.locked',1.65)}
        if name in holds:
            marker,length=holds[name];point=t(by_name[marker]);windows.append([point-.3,point+length])
        if name=='privacy':
            point=t(by_name['privacy.lockVisible']);windows.append([point-.15,point+.35])
        windows=merge([[max(start,a),min(end-.02,b)] for a,b in windows])
        source_seconds=sum(b-a for a,b in windows)
        frame_budget=round(target*FPS)
        assigned=0;scene_pieces=[]
        for i,(a,b) in enumerate(windows):
            frames=max(1,round((b-a)/source_seconds*frame_budget)) if i<len(windows)-1 else frame_budget-assigned
            assert frames>0
            assigned+=frames
            output_seconds=frames/FPS
            piece={'id':len(pieces),'scene':name,'source_start':a,'source_end':b,'frames':frames,'output_start':output_start,'output_duration':output_seconds,'speed':(b-a)/output_seconds}
            pieces.append(piece);scene_pieces.append(piece)
            for e,event_start,event_end in actions:
                touch=event_start+min(.6,(event_end-event_start)*.45)
                if a<=touch<b and e['kind'] in ['tap','swipe']:
                    item={'time':output_start+(touch-a)/piece['speed'],'kind':e['kind'],'x':140+800*e['x'],'y':109+1736*e['y'],'name':e['name']}
                    if e['kind']=='swipe':item.update(toX=140+800*e['toX'],toY=109+1736*e['toY'])
                    taps.append(item)
            output_start+=output_seconds
        scene_start=sum(s['duration'] for s in scenes)
        scenes.append({'name':name,'heading':heading,'caption':caption,'start':scene_start,'duration':target,'source_seconds':source_seconds,'source_start':start,'source_end':end})
        total_frames+=assigned
    assert total_frames==1350
    return {'format':{'width':1080,'height':1920,'fps':FPS,'duration':45},'capture_clock_correction':correction,'scenes':scenes,'pieces':pieces,'taps':taps,'source_type':'continuous native Simulator screen recording','voice':'UI demonstration only; no recorded speech or fabricated reply'}

def ass_time(seconds):
    centis=round(max(0,seconds)*100);hours,remain=divmod(centis,360000);minutes,remain=divmod(remain,6000);sec,cs=divmod(remain,100)
    return f'{hours}:{minutes:02}:{sec:02}.{cs:02}'

def write_labels(plan):
    lines=['[Script Info]','ScriptType: v4.00+','PlayResX: 1080','PlayResY: 1920','WrapStyle: 2','ScaledBorderAndShadow: yes','','[V4+ Styles]','Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding',
    'Style: Header,Noto Sans CJK SC,28,&H00AD6D46,&H00AD6D46,&H00FFFFFF,&H00000000,0,0,0,0,100,100,1,0,1,0,0,6,50,50,0,1',
    'Style: Caption,Noto Sans CJK SC,28,&H007B6554,&H007B6554,&H00FFFFFF,&H00000000,0,0,0,0,100,100,0,0,1,0,0,5,30,30,0,1',
    'Style: Note,Noto Sans CJK SC,17,&H009E8D80,&H009E8D80,&H00FFFFFF,&H00000000,0,0,0,0,100,100,0,0,1,0,0,5,0,0,0,1',
    'Style: Touch,Noto Sans CJK SC,72,&H20D88A42,&H20D88A42,&H40FFFFFF,&H00000000,0,0,0,0,100,100,0,0,1,1.2,0,5,0,0,0,1',
    '','[Events]','Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text']
    def add(start,end,style,text,layer=1):lines.append(f'Dialogue: {layer},{ass_time(start)},{ass_time(end)},{style},,0,0,0,,{text}')
    for scene in plan['scenes']:
        a,b=scene['start'],scene['start']+scene['duration']
        add(a,b,'Header',r'{\an6\pos(1030,52)\fad(100,100)}'+scene['heading'])
        end=b-1.35 if scene['name']=='privacy' else b
        add(a,end,'Caption',r'{\an5\pos(540,1883)\fad(100,100)}'+scene['caption'])
        if scene['name']=='voice':add(a,b,'Note',r'{\an5\pos(540,89)}语音界面操作演示')
    add(43.65,45,'Caption',r'{\an5\pos(540,1883)\fad(120,200)}个人助理｜让日常，更从容一点。')
    for tap in plan['taps']:
        at=tap['time'];x,y=round(tap['x']),round(tap['y'])
        placement=f'\\pos({x},{y})'
        if tap['kind']=='swipe':placement=f'\\move({x},{y},{round(tap["toX"])},{round(tap["toY"])},20,520)'
        text='{\\an5'+placement+r'\fscx75\fscy75\t(0,160,\fscx100\fscy100)\fad(35,160)}○'
        add(at,min(45,at+.62),'Touch',text,3)
    (ROOT/'labels.ass').write_text('\n'.join(lines)+'\n')

def render_piece(piece):
    out=ROOT/'pieces'/f'{piece["id"]:03}.mp4'
    cache=out.with_suffix('.json');identity={'piece':piece,'raw_size':RAW.stat().st_size}
    if out.exists() and cache.exists() and json.loads(cache.read_text())==identity:return piece['id']
    vf=f'setpts=(PTS-STARTPTS)/{piece["speed"]:.9f},fps={FPS},scale=800:1736:flags=lanczos,setsar=1,tpad=stop_mode=clone:stop_duration=0.15,format=yuv420p'
    args=['ffmpeg','-hide_banner','-loglevel','error','-y','-threads','1','-filter_threads','1','-ss',f'{piece["source_start"]:.6f}','-t',f'{piece["source_end"]-piece["source_start"]:.6f}','-i',str(RAW),'-vf',vf,'-frames:v',str(piece['frames']),'-an','-c:v','libx264','-preset','veryfast','-crf','16','-threads','1','-video_track_timescale','15360',str(out)]
    command(args,ROOT/'pieces'/f'{piece["id"]:03}.log')
    cache.write_text(json.dumps(identity,ensure_ascii=False,indent=2)+'\n')
    return piece['id']

def soundtrack(plan):
    with wave.open(str(ROOT/'assets/original-score.wav'),'rb') as w:
        rate=w.getframerate();audio=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(np.float64).reshape(-1,2)/32768
    for tap in plan['taps']:
        if tap['kind']!='tap':continue
        start=int(tap['time']*rate);duration=.07;t=np.arange(int(duration*rate))/rate
        click=(np.sin(2*np.pi*1046.5*t)+.3*np.sin(2*np.pi*1568*t))*(1-np.exp(-t/.001))*np.exp(-t/.012)*.014
        count=min(len(click),len(audio)-start)
        if count>0:audio[start:start+count]+=(click[:count,None]/np.sqrt(2))
    with wave.open(str(ROOT/'assets/demo-soundtrack.wav'),'wb') as w:
        w.setnchannels(2);w.setsampwidth(2);w.setframerate(rate);w.writeframes((np.clip(audio,-1,1)*32767).astype('<i2').tobytes())

def main():
    (ROOT/'pieces').mkdir(exist_ok=True)
    events=load_events();meta=json.loads((ROOT/'raw/recording-metadata.json').read_text());raw_info=probe(RAW)
    plan=plan_edit(events,meta,raw_info);(ROOT/'edit-plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n')
    (ROOT/'events.json').write_text(json.dumps(events,ensure_ascii=False,indent=2)+'\n')
    write_labels(plan);soundtrack(plan)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        for done in pool.map(render_piece,plan['pieces']):print('Rendered native clip',done,flush=True)
    concat='\n'.join("file '"+str(ROOT/'pieces'/f'{p["id"]:03}.mp4')+"'" for p in plan['pieces'])+'\n'
    (ROOT/'pieces/list.txt').write_text(concat)
    command(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','concat','-safe','0','-i',str(ROOT/'pieces/list.txt'),'-c','copy','-movflags','+faststart',str(ROOT/'operations.mp4')])
    print('Compositing native recording, framing, labels and original music',flush=True)
    filters=f'[0:v]setpts=PTS-STARTPTS,format=rgb24[app];[2:v]format=gray[mask];[app][mask]alphamerge[rounded];[1:v]format=rgb24[base];[base][rounded]overlay=140:109:shortest=1:format=auto,ass={ROOT}/labels.ass,format=yuv420p,fade=t=in:st=0:d=0.2:color=0xf1f6fd,fade=t=out:st=44.6:d=0.4:color=0xf1f6fd[v]'
    output=ROOT/'个人助理-产品操作演示-45秒.mp4'
    command(['ffmpeg','-hide_banner','-loglevel','warning','-y','-threads','2','-filter_complex_threads','1','-i',str(ROOT/'operations.mp4'),'-loop','1','-framerate','30','-i',str(ROOT/'assets/plate.png'),'-loop','1','-framerate','30','-i',str(ROOT/'assets/screen-mask.png'),'-i',str(ROOT/'assets/demo-soundtrack.wav'),'-filter_complex',filters,'-map','[v]','-map','3:a','-t','45','-r','30','-c:v','libx264','-preset','fast','-crf','18','-threads','2','-c:a','aac','-b:a','160k','-ar','48000','-movflags','+faststart','-metadata','title=个人助理｜产品操作演示','-metadata','comment=Native app screen recording with fictional demonstration data; idle waits edited. Voice segment demonstrates UI controls only. Original background music.',str(output)],ROOT/'render.log')
    info=probe(output);(ROOT/'video-probe.json').write_text(json.dumps(info,ensure_ascii=False,indent=2)+'\n')
    video=next(s for s in info['streams'] if s['codec_type']=='video');audio=next(s for s in info['streams'] if s['codec_type']=='audio')
    assert video['width']==1080 and video['height']==1920 and video['codec_name']=='h264'
    assert abs(float(info['format']['duration'])-45)<.1 and video['r_frame_rate']=='30/1'
    assert int(video['nb_frames'])==1350,'The complete operation sequence must contain 45 seconds of video'
    assert audio['codec_name']=='aac'
    print(json.dumps({'output':str(output),'bytes':output.stat().st_size,'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'duration':info['format']['duration'],'pieces':len(plan['pieces'])},ensure_ascii=False),flush=True)

if __name__=='__main__':main()
