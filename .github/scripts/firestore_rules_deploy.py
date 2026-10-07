#!/usr/bin/env python3
"""Firestore 보안 규칙 배포 (Firebase Rules REST API, 표준 라이브러리만).

현재 게시된 규칙과 파일 내용이 같으면 아무것도 안 함. 다르면 새 ruleset 만들고
`cloud.firestore` release 를 거기로 옮긴다 (= 콘솔의 '게시').

env: TOKEN (OAuth access token, cloud-platform scope), PROJECT (GCP project id)
usage: firestore_rules_deploy.py path/to/firestore.rules
"""
import json
import os
import sys
import urllib.error
import urllib.request

RULES = sys.argv[1]
TOKEN = os.environ["TOKEN"]
PROJECT = os.environ["PROJECT"]
BASE = f"https://firebaserules.googleapis.com/v1/projects/{PROJECT}"
RELEASE = "cloud.firestore"


def call(method, url, body=None, ok404=False):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            txt = r.read().decode()
            return json.loads(txt) if txt else {}
    except urllib.error.HTTPError as e:
        if e.code == 404 and ok404:
            return None
        print(f"[rules] {method} {url}\n  -> HTTP {e.code}: {e.read().decode(errors='replace')}", file=sys.stderr)
        raise SystemExit(1)


src = open(RULES, encoding="utf-8").read()

# 현재 게시본과 비교
rel = call("GET", f"{BASE}/releases/{RELEASE}", ok404=True)
if rel:
    cur = call("GET", f"https://firebaserules.googleapis.com/v1/{rel['rulesetName']}")
    files = cur.get("source", {}).get("files", [])
    if files and files[0].get("content", "").strip() == src.strip():
        print(f"[rules] unchanged ({rel['rulesetName'].rsplit('/', 1)[-1]}) — skip")
        raise SystemExit(0)

# 문법 검사 (test 케이스 없이 컴파일만)
test = call("POST", f"{BASE}:test", {"source": {"files": [{"name": "firestore.rules", "content": src}]}})
issues = test.get("issues", [])
errors = [i for i in issues if i.get("severity") == "ERROR"]
for i in issues:
    print(f"[rules] {i.get('severity')}: {i.get('description')} @ {i.get('sourcePosition', {})}")
if errors:
    raise SystemExit(1)

rs = call("POST", f"{BASE}/rulesets", {"source": {"files": [{"name": "firestore.rules", "content": src}]}})
print(f"[rules] created ruleset {rs['name'].rsplit('/', 1)[-1]}")

body = {"name": f"projects/{PROJECT}/releases/{RELEASE}", "rulesetName": rs["name"]}
if rel:
    call("PATCH", f"{BASE}/releases/{RELEASE}", {"release": body, "updateMask": "rulesetName"})
else:
    call("POST", f"{BASE}/releases", body)
print(f"[rules] released {RELEASE} ✔")
