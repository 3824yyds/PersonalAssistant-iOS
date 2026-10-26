#!/usr/bin/env python3
"""Fetch public model transport volumes and verify before atomically installing."""
from pathlib import Path
import hashlib,json,re,time,urllib.request

MODEL_REVISION='4fa8c13439839c8a5b158626486f6ce1d2942f39'
EXPECTED_BYTES=986048064
EXPECTED_SHA='07fcb0fdd9a9e116f3ddb0926a5f9059fc8f9e3369f6455b80397cab562c4f4f'

def sha256(path):
    digest=hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda:source.read(4*1024*1024),b''):digest.update(block)
    return digest.hexdigest()

def main():
    root=Path(__file__).resolve().parents[1]
    destination=root/'App/Resources/CompanionModel.gguf'
    if destination.is_file() and destination.stat().st_size==EXPECTED_BYTES and sha256(destination)==EXPECTED_SHA:
        print('Frozen companion model already verified');return
    assert re.fullmatch(r'[0-9a-f]{40}',MODEL_REVISION), 'Pin the complete model-assets commit before building'
    base='https://raw.githubusercontent.com/3824yyds/PersonalAssistant-iOS/'+MODEL_REVISION+'/'
    with urllib.request.urlopen(base+'MODEL_PARTS.json',timeout=120) as response:
        manifest=json.load(response)
    assert manifest['model_bytes']==EXPECTED_BYTES and manifest['model_sha256']==EXPECTED_SHA
    parts=manifest['parts']
    assert len(parts)==12 and sum(part['bytes'] for part in parts)==EXPECTED_BYTES
    for index,part in enumerate(parts,1):
        assert part['name']==f'checkpoint225.gguf.part{index:02d}'
        assert 0<part['bytes']<=80*1024*1024 and re.fullmatch(r'[0-9a-f]{64}',part['sha256'])
    staging=destination.with_suffix('.download')
    try:
        with staging.open('w+b') as output:
            for index,part in enumerate(parts,1):
                start=output.tell()
                for attempt in range(3):
                    digest=hashlib.sha256();received=0
                    try:
                        request=urllib.request.Request(base+part['name'],headers={'User-Agent':'PersonalAssistant-build10'})
                        with urllib.request.urlopen(request,timeout=120) as response:
                            while block:=response.read(4*1024*1024):
                                received+=len(block)
                                if received>part['bytes']:raise ValueError('Oversized model volume')
                                digest.update(block);output.write(block)
                        if received!=part['bytes'] or digest.hexdigest()!=part['sha256']:
                            raise ValueError('Model volume size or SHA mismatch')
                        print(f'Verified model volume {index}/12',flush=True);break
                    except Exception:
                        output.seek(start);output.truncate()
                        if attempt==2:raise
                        time.sleep(2*(attempt+1))
        assert staging.stat().st_size==EXPECTED_BYTES and sha256(staging)==EXPECTED_SHA
        staging.replace(destination)
        print('Assembled and verified frozen checkpoint-225 model')
    finally:
        staging.unlink(missing_ok=True)

if __name__=='__main__':main()
