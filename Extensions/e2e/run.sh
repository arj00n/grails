#!/bin/bash
# End-to-end test: real Chrome + the unpacked extension + the real Grails app.
# Needs: Node 22+, Google Chrome, a built Debug Grails.app. Everything lives under /private/tmp/grails-e2e.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W=/private/tmp/grails-e2e
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/Grails-*/Build/Products/Debug/Grails.app | head -1)
pkill -x Grails || true; pkill -f grails-chrome-profile || true; sleep 1
rm -rf $W/Lib.grails $W/i.sqlite* /private/tmp/grails-chrome-profile; mkdir -p $W/web
python3 - <<'PY'
import struct,zlib
def png(w,h,c):
    raw=b''.join(b'\x00'+bytes(c+[255])*w for _ in range(h))
    def ch(t,d): x=struct.pack('>I',len(d))+t+d; return x+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+ch(b'IDAT',zlib.compress(raw))+ch(b'IEND',b'')
open('/private/tmp/grails-e2e/web/hero.png','wb').write(png(320,200,[40,120,200]))
open('/private/tmp/grails-e2e/web/hero2.png','wb').write(png(300,180,[220,90,40]))
open('/private/tmp/grails-e2e/web/index.html','w').write('<html><head><title>Web test page</title></head><body><img id="pic" src="hero.png" alt="Hero photo" width="320"></body></html>')
PY
cp "$HERE"/*.mjs $W/
(cd $W/web && python3 -m http.server 8765 --bind 127.0.0.1 >/dev/null 2>&1 &)
GRAILS_NO_MENUBAR=1 GRAILS_API_TOKEN=e2e-token GRAILS_SEED=3 GRAILS_SEED_PLAIN=1 GRAILS_LIBRARY=$W/Lib.grails GRAILS_INDEX_PATH=$W/i.sqlite "$APP/Contents/MacOS/Grails" >/dev/null 2>&1 &
(cd $W && nohup node launch-chrome.mjs >launch.log 2>&1 &)
sleep 7
(cd $W && node ext-e2e.mjs && node altclick.mjs)
python3 - <<'PY'
import glob,json
for f in sorted(glob.glob('/private/tmp/grails-e2e/Lib.grails/items/*/item.json')):
    j=json.load(open(f))
    if j['addedBy']!='fixture': print('saved:',j['kind'],'|',j['name'],'|',(j.get('source') or {}).get('url') or (j.get('source') or {}).get('pageUrl'))
PY
pkill -f grails-chrome-profile || true; pkill -f launch-chrome.mjs || true; pkill -f "http.server 8765" || true; pkill -x Grails || true
