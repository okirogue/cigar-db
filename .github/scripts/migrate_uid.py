#!/usr/bin/env python3
"""운영자 UID 이전 (일회성): 옛 익명 UID 문서를 새 UID 로 옮긴다.

- log_stats/<old>_<logId> → log_stats/<new>_<logId> (uid 필드도 교체), 옛 문서 삭제
- installs/<old> → installs/<new> 에 합침 (days 합집합, first 이른 쪽, last 늦은 쪽), 옛 문서 삭제
- scan_quota/<old> 삭제

env: TOKEN (cloud-platform, Cloud Datastore 사용자), PROJECT
usage: migrate_uid.py <old_prefix6> <new_prefix6> [--dry]
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

TOKEN = os.environ["TOKEN"]
PROJECT = os.environ["PROJECT"]
BASE = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"
OLD6, NEW6 = sys.argv[1], sys.argv[2]
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
        print(f"[migrate] {method} {url}\n  -> HTTP {e.code}: {e.read().decode(errors='replace')}", file=sys.stderr)
        raise SystemExit(1)


def collection_raw(name):
    docs, token = [], None
    while True:
        q = {"pageSize": 300}
        if token:
            q["pageToken"] = token
        res = req("GET", f"{BASE}/{name}?{urllib.parse.urlencode(q)}")
        docs += res.get("documents", [])
        token = res.get("nextPageToken")
        if not token:
            return docs


def doc_id(d):
    return d["name"].rsplit("/", 1)[-1]


def sv(fields, k):
    v = fields.get(k, {})
    return v.get("stringValue")


# 전체 UID 찾기 (installs 문서 id 에서)
installs = collection_raw("installs")
ids = {doc_id(d)[:6]: doc_id(d) for d in installs}
old = ids.get(OLD6)
new = ids.get(NEW6)
if not old or not new:
    print(f"UID not found: old={old} new={new}", file=sys.stderr)
    raise SystemExit(1)
print(f"old={old}\nnew={new}\ndry={DRY}")

# 1) log_stats
moved = 0
for d in collection_raw("log_stats"):
    did = doc_id(d)
    if not did.startswith(old + "_"):
        continue
    log_id = did[len(old) + 1:]
    fields = d["fields"]
    fields["uid"] = {"stringValue": new}
    new_id = f"{new}_{log_id}"
    print(f"log_stats {did} -> {new_id}")
    if not DRY:
        req("PATCH", f"{BASE}/log_stats/{new_id}", {"fields": fields})
        req("DELETE", f"{BASE}/log_stats/{did}")
    moved += 1
print(f"log_stats moved: {moved}")

# 2) installs 합치기
o = next((d for d in installs if doc_id(d) == old), None)
n = next((d for d in installs if doc_id(d) == new), None)
if o:
    of, nf = o["fields"], (n["fields"] if n else {})
    def days(f):
        return [v.get("stringValue") for v in f.get("days", {}).get("arrayValue", {}).get("values", [])]
    merged_days = sorted(set(days(of)) | set(days(nf)))
    first = min(filter(None, [sv(of, "first"), sv(nf, "first")]))
    last = max(filter(None, [sv(of, "last"), sv(nf, "last")]))
    fields = dict(nf) if n else dict(of)
    fields["days"] = {"arrayValue": {"values": [{"stringValue": x} for x in merged_days]}}
    fields["first"] = {"stringValue": first}
    fields["last"] = {"stringValue": last}
    print(f"installs merge -> {new}: days={merged_days} first={first} last={last}")
    if not DRY:
        req("PATCH", f"{BASE}/installs/{new}", {"fields": fields})
        req("DELETE", f"{BASE}/installs/{old}")

# 3) scan_quota
print(f"scan_quota delete {old}")
if not DRY:
    req("DELETE", f"{BASE}/scan_quota/{old}")
print("done")
