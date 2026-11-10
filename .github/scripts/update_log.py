#!/usr/bin/env python3
"""운영자 기록 수정 (수동): users/<uid>/logs 문서의 일부 필드를 고친다 (시가 잘못 고른 기록 정정 등).

env: TOKEN (cloud-platform), PROJECT
usage: update_log.py <uid_prefix6> <edits.json> [--dry]

edits.json: [{"match": {"cigar_id": "plasencia-alma-fuerte-colorado", "date": "2026-11-10"}, "set": {"cigar_id": "plasencia-alma-fuerte", "vitola": "Robustus I"}}]
  match: 모든 키가 일치하는 기록 문서(삭제 안 된 것)만. 값 null 은 "비어 있음(null/'')" 매치.
  set:   바꿀 필드(문자열·숫자·불리언·문자열 배열·null). updated 는 자동으로 지금 시각 → 앱 운영자 동기화가 받아간다.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

TOKEN = os.environ["TOKEN"]
PROJECT = os.environ["PROJECT"]
BASE = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"
UID6, EDITS_PATH = sys.argv[1], sys.argv[2]
DRY = "--dry" in sys.argv


def req(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", f"Bearer {TOKEN}")
    if data:
        r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            t = resp.read().decode()
            return json.loads(t) if t else {}
    except urllib.error.HTTPError as e:
        print(f"[log] {method} {url}\n  -> HTTP {e.code}: {e.read().decode(errors='replace')}", file=sys.stderr)
        raise SystemExit(1)


def collection(path, show_missing=False):
    docs, token = [], None
    while True:
        q = {"pageSize": 300}
        if show_missing:
            q["showMissing"] = "true"
            q["mask.fieldPaths"] = "_"
        if token:
            q["pageToken"] = token
        res = req("GET", f"{BASE}/{path}?{urllib.parse.urlencode(q)}")
        docs += res.get("documents", [])
        token = res.get("nextPageToken")
        if not token:
            return docs


def val(v):
    for k in ("stringValue", "booleanValue"):
        if k in v:
            return v[k]
    if "integerValue" in v:
        return int(v["integerValue"])
    if "doubleValue" in v:
        return float(v["doubleValue"])
    if "arrayValue" in v:
        return [val(x) for x in v["arrayValue"].get("values", [])]
    return None


def fv(x):
    if x is None:
        return {"nullValue": None}
    if isinstance(x, bool):
        return {"booleanValue": x}
    if isinstance(x, int):
        return {"integerValue": str(x)}
    if isinstance(x, float):
        return {"doubleValue": x}
    if isinstance(x, list):
        return {"arrayValue": {"values": [fv(i) for i in x]}}
    return {"stringValue": str(x)}


uids = [d["name"].rsplit("/", 1)[-1] for d in collection("users", show_missing=True)]
uid = next((u for u in uids if u.startswith(UID6)), None)
if not uid:
    raise SystemExit(f"UID not found: {UID6}")

logs = []
for d in collection(f"users/{uid}/logs"):
    f = d.get("fields", {})
    if val(f.get("deleted", {})) is True:
        continue
    logs.append((d["name"], {k: val(v) for k, v in f.items()}))
print(f"uid={uid} log docs={len(logs)} dry={DRY}")

with open(EDITS_PATH, encoding="utf-8") as fh:
    edits = json.load(fh)
now = int(time.time() * 1000)
plan = []
for e in edits:
    m, s = e["match"], e["set"]
    hits = [(n, f) for n, f in logs if all((f.get(k) in (None, "")) if v is None else f.get(k) == v for k, v in m.items())]
    print(f"match {m} → {len(hits)} docs")
    for n, f in hits:
        print(f"  {f.get('date')} | {f.get('cigar_name')} | {f.get('vitola') or ''} | {f.get('score')}  SET {json.dumps(s, ensure_ascii=False)[:300]}")
        plan.append((n, s))

if DRY or not plan:
    print("nothing written" if not plan else "dry run: nothing written")
    raise SystemExit(0)

writes = []
for n, s in plan:
    fields = {k: fv(v) for k, v in s.items()}
    fields["updated"] = fv(now)
    writes.append({"update": {"name": n, "fields": fields}, "updateMask": {"fieldPaths": list(fields)}})
req("POST", f"{BASE}:commit", {"writes": writes})
print(f"updated {len(writes)} docs")
