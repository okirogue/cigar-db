#!/usr/bin/env python3
"""Google Play 내부 테스트 트랙에 .aab 업로드 (androidpublisher v3, 표준 라이브러리만 사용).

env: TOKEN (OAuth access token), PKG (package name), NOTE (release note, optional)
usage: play_upload.py path/to/app.aab [track ...]  (예: internal alpha)
"""
import json
import os
import sys
import urllib.error
import urllib.request

AAB = sys.argv[1]
TRACKS = sys.argv[2:] or ["internal"]
TOKEN = os.environ["TOKEN"]
PKG = os.environ["PKG"]
NOTE = os.environ.get("NOTE", "")

BASE = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PKG}"
UPLOAD = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PKG}"


def call(method, url, body=None, ctype="application/json", timeout=600):
    data = body if isinstance(body, (bytes, bytearray)) else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    if data is not None:
        req.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            txt = r.read().decode()
            return json.loads(txt) if txt else {}
    except urllib.error.HTTPError as e:
        msg = e.read().decode(errors="replace")
        print(f"[play] {method} {url}\n  -> HTTP {e.code}: {msg}", file=sys.stderr)
        raise SystemExit(1)


print(f"[play] package={PKG} tracks={TRACKS} file={AAB} ({os.path.getsize(AAB)//1024} KB)")

edit = call("POST", f"{BASE}/edits")
eid = edit["id"]
print(f"[play] edit {eid}")

with open(AAB, "rb") as f:
    aab = f.read()
bundle = call("POST", f"{UPLOAD}/edits/{eid}/bundles?uploadType=media", aab, "application/octet-stream")
vc = bundle["versionCode"]
print(f"[play] uploaded bundle versionCode={vc}")

for TRACK in TRACKS:
    track_body = {
        "track": TRACK,
        "releases": [{
            "versionCodes": [str(vc)],
            "status": "completed",
            "releaseNotes": [{"language": "ko-KR", "text": NOTE[:500]}] if NOTE else [],
        }],
    }
    call("PUT", f"{BASE}/edits/{eid}/tracks/{TRACK}", track_body)
    print(f"[play] track {TRACK} -> {vc} (completed)")

res = call("POST", f"{BASE}/edits/{eid}:commit")
print(f"[play] committed edit {res.get('id', eid)} ✔")
