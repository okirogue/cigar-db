#!/usr/bin/env python3
"""운영자 재고 일괄 입력 (수동): users/<uid>/stock 에 재고 문서를 만든다.

앱의 운영자 동기화가 다음 "지금 동기화" 때 그대로 받아간다 (사진 없음).

env: TOKEN (cloud-platform, Cloud Datastore 사용자), PROJECT
usage: add_stock.py <uid_prefix6> <humidor_name> <items.json> [--dry]

items.json: [{"cigar_id": "...", "cigar_name": "...", "vitola": "...", "qty": 10,
              "price_per_stick": 9470, "currency": "KRW", "added_date": "2026-10-14", "memo": "..."}]
"""
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

TOKEN = os.environ["TOKEN"]
PROJECT = os.environ["PROJECT"]
DB = f"projects/{PROJECT}/databases/(default)"
BASE = f"https://firestore.googleapis.com/v1/{DB}/documents"
UID6, HUMIDOR, ITEMS_PATH = sys.argv[1], sys.argv[2], sys.argv[3]
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
        print(f"[stock] {method} {url}\n  -> HTTP {e.code}: {e.read().decode(errors='replace')}", file=sys.stderr)
        raise SystemExit(1)


def collection(path, show_missing=False):
    docs, token = [], None
    while True:
        q = {"pageSize": 300}
        if show_missing:  # users/<uid> 는 하위 컬렉션만 있는 "빈 부모" 라 기본 목록엔 안 나옴
            q["showMissing"] = "true"
            q["mask.fieldPaths"] = "_"
        if token:
            q["pageToken"] = token
        res = req("GET", f"{BASE}/{path}?{urllib.parse.urlencode(q)}")
        docs += res.get("documents", [])
        token = res.get("nextPageToken")
        if not token:
            return docs


def doc_id(d):
    return d["name"].rsplit("/", 1)[-1]


def val(v):
    if "stringValue" in v:
        return v["stringValue"]
    if "integerValue" in v:
        return int(v["integerValue"])
    if "booleanValue" in v:
        return v["booleanValue"]
    return None


def fv(x):
    if x is None:
        return {"nullValue": None}
    if isinstance(x, bool):
        return {"booleanValue": x}
    if isinstance(x, int):
        return {"integerValue": str(x)}
    return {"stringValue": str(x)}


# 1) UID 찾기 (users/ 문서 id 로)
uids = [doc_id(d) for d in collection("users", show_missing=True)]
uid = next((u for u in uids if u.startswith(UID6)), None)
if not uid:
    print(f"UID not found: {UID6} (users: {[u[:6] for u in uids]})", file=sys.stderr)
    raise SystemExit(1)

# 2) 휴미더 찾기
hums = []
for d in collection(f"users/{uid}/humidors"):
    f = d.get("fields", {})
    if val(f.get("deleted", {})) is True:
        continue
    hums.append((doc_id(d), val(f.get("name", {})) or "", val(f.get("sort_order", {})) or 0))
hums.sort(key=lambda h: h[2])
print(f"uid={uid}\nhumidors:")
for sid, name, order in hums:
    print(f"  [{order}] {name}  ({sid})")
target = [h for h in hums if h[1] == HUMIDOR]
if len(target) != 1:
    print(f"humidor not found or ambiguous: {HUMIDOR!r}", file=sys.stderr)
    raise SystemExit(1)
hum_sid = target[0][0]
print(f"target humidor: {HUMIDOR} ({hum_sid})\ndry={DRY}")

# 3) 기존 재고 수 (참고)
existing = [d for d in collection(f"users/{uid}/stock") if val(d.get("fields", {}).get("deleted", {})) is not True]
print(f"existing stock docs: {len(existing)}")
if DRY:
    for d in existing:
        f = d.get("fields", {})
        print(f"  = {val(f.get('cigar_id', {}))} | {val(f.get('cigar_name', {}))} | {val(f.get('vitola', {})) or ''} | x{val(f.get('qty', {}))} | {val(f.get('added_date', {}))}")

# 4) 재고 문서 만들기
with open(ITEMS_PATH, encoding="utf-8") as fh:
    items = json.load(fh)
now = int(time.time() * 1000)
writes = []
total_qty = 0
for it in items:
    sid = secrets.token_hex(8)
    fields = {
        "humidor_sid": fv(hum_sid),
        "cigar_id": fv(it["cigar_id"]),
        "cigar_name": fv(it["cigar_name"]),
        "vitola": fv(it.get("vitola")),
        "qty": fv(int(it["qty"])),
        "price_per_stick": fv(int(it["price_per_stick"]) if it.get("price_per_stick") is not None else None),
        "currency": fv(it.get("currency", "KRW")),
        "added_date": fv(it["added_date"]),
        "memo": fv(it.get("memo")),
        "updated": fv(now),
        "deleted": fv(False),
    }
    total_qty += int(it["qty"])
    print(f"  + {it['cigar_name']} | {it.get('vitola') or ''} | x{it['qty']} | {it.get('price_per_stick')} {it.get('currency','KRW')} | {it['added_date']} | sid={sid}")
    writes.append({
        "update": {"name": f"{DB}/documents/users/{uid}/stock/{sid}", "fields": fields},
        "updateTransforms": [{"fieldPath": "synced", "setToServerValue": "REQUEST_TIME"}],
    })
print(f"planned: {len(writes)} docs, {total_qty} sticks")
if not DRY:
    req("POST", f"https://firestore.googleapis.com/v1/{DB}/documents:commit", {"writes": writes})
    print(f"written: {len(writes)} docs")
print("done")
