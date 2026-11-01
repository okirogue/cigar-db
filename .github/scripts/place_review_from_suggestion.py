#!/usr/bin/env python3
"""운영자용: 장소 제안(place_suggestions/<id>)의 별점·코멘트를 등록된 장소의 리뷰(place_reviews/<uid>_<placeId>)로 옮긴다.

제안자가 다시 쓰지 않아도 첫 리뷰가 되고, 앱에서 '내 평가 수정'으로 고칠 수 있다. 이미 리뷰가 있으면 건너뛴다.
env: TOKEN, PROJECT   usage: place_review_from_suggestion.py <suggestion_doc_id> <place_id> [--dry]
"""
import json, os, sys, time, urllib.request, urllib.error

TOKEN, PROJECT = os.environ["TOKEN"], os.environ["PROJECT"]
BASE = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"
SID, PID = sys.argv[1], sys.argv[2]
DRY = "--dry" in sys.argv


def req(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method, headers={"Authorization": f"Bearer {TOKEN}", **({"Content-Type": "application/json"} if data else {})})
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            t = resp.read().decode()
            return json.loads(t) if t else {}
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        print(f"HTTP {e.code}: {e.read().decode(errors='replace')}", file=sys.stderr)
        raise SystemExit(1)


def val(v):
    for k in ("stringValue", "booleanValue"):
        if k in v:
            return v[k]
    if "integerValue" in v:
        return int(v["integerValue"])
    if "doubleValue" in v:
        return float(v["doubleValue"])
    return None


def fv(x):
    if isinstance(x, bool):
        return {"booleanValue": x}
    if isinstance(x, int):
        return {"integerValue": str(x)}
    return {"stringValue": str(x)}


s = req("GET", f"{BASE}/place_suggestions/{SID}")
if not s:
    raise SystemExit(f"suggestion not found: {SID}")
f = {k: val(v) for k, v in s.get("fields", {}).items()}
uid, rating, comment = f.get("uid"), int(f.get("rating") or 0), (f.get("comment") or "").strip()
print(f"suggestion {SID}: name={f.get('name')!r} uid={uid[:6] if uid else None} rating={rating} comment={comment!r}")
if not uid or rating < 1:
    raise SystemExit("no uid or no rating → nothing to move")
doc = f"{BASE}/place_reviews/{uid}_{PID}"
if req("GET", doc):
    raise SystemExit("review already exists → skip")
body = {"fields": {"uid": fv(uid), "place_id": fv(PID), "rating": fv(rating), "comment": fv(comment[:200]),
                   "lang": fv(f.get("lang") or ""), "platform": fv(f.get("platform") or ""), "build": fv(int(f.get("build") or 0)),
                   "updated": {"timestampValue": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}}}
print(f"→ place_reviews/{uid[:6]}…_{PID} rating={rating} comment={comment[:60]!r} dry={DRY}")
if not DRY:
    req("PATCH", doc, body)
    print("written")
