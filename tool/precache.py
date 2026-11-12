#!/usr/bin/env python3
"""Schrijft build/web/precache_manifest.json: de lijst met bestanden die de
offline service worker (web/offline_sw.js) bij installatie bewaart."""
import json
import os
import sys

root = sys.argv[1] if len(sys.argv) > 1 else 'build/web'
skip_ext = ('.map',)
skip_names = {'flutter_service_worker.js', 'offline_sw.js', 'precache_manifest.json'}
entries = []
for dirpath, _, files in os.walk(root):
    for f in files:
        if f in skip_names or f.endswith(skip_ext):
            continue
        rel = os.path.relpath(os.path.join(dirpath, f), root).replace(os.sep, '/')
        entries.append({'url': rel})
entries.sort(key=lambda e: e['url'])
with open(os.path.join(root, 'precache_manifest.json'), 'w') as fh:
    json.dump({'version': 1, 'entries': entries}, fh, indent=1)
print(f'{len(entries)} bestanden in precache_manifest.json')
