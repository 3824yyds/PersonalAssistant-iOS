#!/usr/bin/env python3
"""Check the individually painted pack, and optionally its compiled iOS asset catalog."""
import hashlib,json,re,struct,subprocess,sys
from pathlib import Path

root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'Docs/COMPANION_STICKERS.json').read_text())
expected={'happy','hug','confused','speechless','smug','goodnight','meme_laugh','meme_melon','meme_cracked','meme_justthis','male_happy','male_hug','male_confused','male_speechless','male_smug','male_goodnight'}
assert {p['id'] for p in manifest['stickers']}==expected
catalog=(root/'App/Core/CompanionStickers.swift').read_text()
assert set(re.findall(r'\.init\(id:"([a-z_]+)"',catalog))==expected
for entry in manifest['stickers']:
    folder=root/'App/Resources/Assets.xcassets'/('CompanionSticker_'+entry['id']+'.imageset')
    contents=json.loads((folder/'Contents.json').read_text())
    file=folder/contents['images'][0]['filename']
    data=file.read_bytes()
    assert data[:8]==b'\x89PNG\r\n\x1a\n'
    width,height,depth,color=struct.unpack('>IIBB',data[16:26])
    assert width>=512 and height>=512 and depth==8 and color==6, 'RGBA PNG required'
    assert hashlib.sha256(data).hexdigest()==entry['sha256']
if len(sys.argv)>1:
    records=json.loads(subprocess.check_output(['xcrun','assetutil','--info',sys.argv[1]]))
    names={p.get('Name') for p in records}
    assert {'CompanionSticker_'+key for key in expected}|{'CompanionMaleAvatar'}<=names, 'A sticker is missing from Assets.car'
print('Verified all sixteen individually generated RGBA stickers'+(' and compiled assets' if len(sys.argv)>1 else ''))
