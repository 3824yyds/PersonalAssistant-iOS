#!/usr/bin/env python3
"""Fail closed if an internal build omits or substitutes the frozen model."""
from pathlib import Path
import hashlib

model=Path(__file__).resolve().parents[1]/'App/Resources/CompanionModel.gguf'
assert model.is_file(), 'Internal device build requires the private checkpoint-225 GGUF'
assert model.stat().st_size==986048064, 'Incomplete checkpoint-225 GGUF'
digest=hashlib.sha256()
with model.open('rb') as source:
    assert source.read(4)==b'GGUF', 'Not a GGUF model'
    source.seek(0)
    for block in iter(lambda:source.read(4*1024*1024),b''):
        digest.update(block)
assert digest.hexdigest()=='07fcb0fdd9a9e116f3ddb0926a5f9059fc8f9e3369f6455b80397cab562c4f4f', 'Checkpoint hash mismatch'
print('Verified frozen checkpoint-225: 986048064 bytes, SHA256 '+digest.hexdigest())
