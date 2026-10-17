#!/usr/bin/env python3
"""운영자용: users/<uid> 의 휴미더·재고·기록·위시를 앱 백업(JSON v2) 형식으로 덤프 (디버그 재현용).

메모·장소·페어링·사진은 뺀다 (재현에 불필요, 개인 메모라서).
env: TOKEN, PROJECT   usage: export_user.py <uid_prefix6> <out.json>
"""
import json
import os
import sys
import urllib.parse
import urllib.request

TOKEN = os.environ["TOKEN"]
PROJECT = os.environ["PROJECT"]
BASE = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"
UID6, OUT = sys.argv[1], sys.argv[2]


def get(url):
    r = urllib.request.Request(url, headers={"Authorization": f"Bearer {TOKEN}"})
    with urllib.request.urlopen(r, timeout=60) as resp:
        return json.loads(resp.read().decode() or "{}")


def collection(path, show_missing=False):
    docs, token = [], None
    while True:
        q = {"pageSize": 300}
        if show_missing:
            q["showMissing"] = "true"
            q["mask.fieldPaths"] = "_"
        if token:
            q["pageToken"] = token
        res = get(f"{BASE}/{path}?{urllib.parse.urlencode(q)}")
        docs += res.get("documents", [])
        token = res.get("nextPageToken")
        if not token:
            return docs


def unwrap(v):
    for k in ("stringValue", "booleanValue", "timestampValue"):
        if k in v:
            return v[k]
    if "integerValue" in v:
        return int(v["integerValue"])
    if "doubleValue" in v:
        return float(v["doubleValue"])
    if "nullValue" in v:
        return None
    if "arrayValue" in v:
        return [unwrap(x) for x in v["arrayValue"].get("values", [])]
    if "mapValue" in v:
        return {k: unwrap(x) for k, x in v["mapValue"].get("fields", {}).items()}
    return None


def rows(path):
    out = []
    for d in collection(path):
        m = {k: unwrap(v) for k, v in d.get("fields", {}).items()}
        if m.get("deleted") is True:
            continue
        m["_sid"] = d["name"].rsplit("/", 1)[-1]
        out.append(m)
    return out


uids = [d["name"].rsplit("/", 1)[-1] for d in collection("users", show_missing=True)]
uid = next((u for u in uids if u.startswith(UID6)), None)
if not uid:
    raise SystemExit(f"UID not found: {UID6}")

hums = sorted(rows(f"users/{uid}/humidors"), key=lambda h: h.get("sort_order") or 0)
hname = {h["_sid"]: h.get("name") or "내 휴미더" for h in hums}
stock = rows(f"users/{uid}/stock")
logs = rows(f"users/{uid}/logs")
wish = rows(f"users/{uid}/wishlist")
customs = rows(f"users/{uid}/custom_cigars")

backup = {
    "version": 2,
    "exported": "debug",
    "source": "MyHumidor",
    "humidors": [hname[h["_sid"]] for h in hums],
    "custom_cigars": [{k: v for k, v in c.items() if not k.startswith("_") and k not in ("updated", "synced")} for c in customs],
    "stock": [
        {
            "humidor": hname.get(s.get("humidor_sid"), "내 휴미더"),
            "cigar_id": s.get("cigar_id"), "cigar_name": s.get("cigar_name"), "vitola": s.get("vitola"),
            "qty": s.get("qty") or 0, "price_per_stick": s.get("price_per_stick"), "currency": s.get("currency") or "KRW",
            "added_date": s.get("added_date"),
        }
        for s in stock
    ],
    "wishlist": [
        {"cigar_id": w.get("cigar_id"), "cigar_name": w.get("cigar_name"), "vitola": w.get("vitola"), "memo": None, "priority": w.get("priority") or 1, "created": w.get("created")}
        for w in wish
    ],
    "logs": [
        {
            "cigar_id": l.get("cigar_id"), "cigar_name": l.get("cigar_name"), "vitola": l.get("vitola"), "date": l.get("date"),
            "score": l.get("score"), "tags": [t for t in str(l.get("tags") or "").split(",") if t],
            "note_start": None, "note_mid": None, "note_end": None, "summary": None, "place": None, "pairing": None,
            **({"stock_price": l["stock_price"]} if l.get("stock_price") is not None else {}),
            **({"stock_currency": l["stock_currency"]} if l.get("stock_currency") else {}),
            **({"stock_added": l["stock_added"]} if l.get("stock_added") else {}),
        }
        for l in logs
    ],
}
json.dump(backup, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(f"uid={uid} humidors={len(hums)} stock={len(stock)} logs={len(logs)} wish={len(wish)} customs={len(customs)}")
