#!/usr/bin/env python3
"""이미 업로드된 버전코드를 다른 트랙(보통 production)으로 승격 (androidpublisher v3).

env: TOKEN, PKG, NOTE_KO, NOTE_EN (optional)
usage: play_promote.py <track> <versionCode> [--dry] [--rollout 0.2]
--dry 면 edits.validate 만 호출해 뭐가 막는지 보고 커밋하지 않음.
"""
import json, os, sys, urllib.error, urllib.request

TRACK, VC = sys.argv[1], sys.argv[2]
DRY = "--dry" in sys.argv
ROLL = float(sys.argv[sys.argv.index("--rollout") + 1]) if "--rollout" in sys.argv else None
TOKEN, PKG = os.environ["TOKEN"], os.environ["PKG"]
BASE = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PKG}"


def call(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            t = r.read().decode()
            return json.loads(t) if t else {}
    except urllib.error.HTTPError as e:
        print(f"[play] {method} {url}\n  -> HTTP {e.code}: {e.read().decode(errors='replace')}", file=sys.stderr)
        raise SystemExit(1)


eid = call("POST", f"{BASE}/edits")["id"]
print(f"[play] edit {eid} · {PKG} · {TRACK} ← versionCode {VC} · dry={DRY}")
cur = call("GET", f"{BASE}/edits/{eid}/tracks/{TRACK}")
print("[play] current track:", json.dumps(cur, ensure_ascii=False)[:600])
notes = []
for lang, key in (("ko-KR", "NOTE_KO"), ("en-US", "NOTE_EN")):
    if os.environ.get(key):
        notes.append({"language": lang, "text": os.environ[key][:500]})
rel = {"versionCodes": [str(VC)], "releaseNotes": notes}
if ROLL and ROLL < 1:
    rel.update(status="inProgress", userFraction=ROLL)
else:
    rel["status"] = "completed"
call("PUT", f"{BASE}/edits/{eid}/tracks/{TRACK}", {"track": TRACK, "releases": [rel]})
print(f"[play] track {TRACK} set → {VC} ({rel['status']})")
v = call("POST", f"{BASE}/edits/{eid}:validate")
print("[play] validate OK:", json.dumps(v, ensure_ascii=False)[:300])
if DRY:
    call("DELETE", f"{BASE}/edits/{eid}")
    print("[play] dry run — edit discarded")
else:
    res = call("POST", f"{BASE}/edits/{eid}:commit")
    print(f"[play] committed {res.get('id', eid)} ✔ — Google 검토 후 공개")
