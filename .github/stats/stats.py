#!/usr/bin/env python3
"""운영자용 통계 (Firestore REST, 읽기 전용, 표준 라이브러리만).

log_stats / installs / cigar_suggestions / scan_quota 를 읽어 마크다운 요약을 만든다.
개인정보 없음: 모두 익명 UID 기준 집계. 앱에는 노출하지 않는 운영자 전용.

env: TOKEN (OAuth access token, cloud-platform scope — Cloud Datastore 뷰어 권한), PROJECT
usage: stats.py out.md [out.json]
"""
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter, defaultdict

TOKEN = os.environ["TOKEN"]
PROJECT = os.environ["PROJECT"]
BASE = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"
OUT_MD = sys.argv[1]
OUT_JSON = sys.argv[2] if len(sys.argv) > 2 else None


def get(url):
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        print(f"[stats] GET {url}\n  -> HTTP {e.code}: {e.read().decode(errors='replace')}", file=sys.stderr)
        raise SystemExit(1)


def unwrap(v):
    """Firestore Value → python"""
    if "stringValue" in v:
        return v["stringValue"]
    if "integerValue" in v:
        return int(v["integerValue"])
    if "doubleValue" in v:
        return float(v["doubleValue"])
    if "booleanValue" in v:
        return v["booleanValue"]
    if "timestampValue" in v:
        return v["timestampValue"]
    if "nullValue" in v:
        return None
    if "arrayValue" in v:
        return [unwrap(x) for x in v["arrayValue"].get("values", [])]
    if "mapValue" in v:
        return {k: unwrap(x) for k, x in v["mapValue"].get("fields", {}).items()}
    return v


def collection(name):
    docs, token = [], None
    while True:
        q = {"pageSize": 300}
        if token:
            q["pageToken"] = token
        res = get(f"{BASE}/{name}?{urllib.parse.urlencode(q)}")
        for d in res.get("documents", []):
            row = {k: unwrap(v) for k, v in d.get("fields", {}).items()}
            row["_id"] = d["name"].rsplit("/", 1)[-1]
            row["_updated"] = d.get("updateTime", "")
            docs.append(row)
        token = res.get("nextPageToken")
        if not token:
            return docs


def short(uid):
    return (uid or "?")[:6]


def score10(s):
    s = float(s or 0)
    return round(s / 5) / 2 if s > 10 else s  # 옛 100점 문서 호환


today = dt.date.today()
logs = collection("log_stats")
installs = collection("installs")
sugg = collection("cigar_suggestions")
quota = collection("scan_quota")
feedback = collection("feedback")

# 운영자 동기화 상태: users/<uid>/{humidors,stock,logs,custom} 문서 수 (내용은 안 읽음)
def _list_users():
    res = get(f"{BASE}/users?pageSize=50")
    return [d["name"].rsplit("/", 1)[-1] for d in res.get("documents", [])] if res else []
sync_rows = []
try:
    # 서브컬렉션만 있고 부모 문서가 없을 수 있어 listCollectionIds 대신 알려진 UID 후보(installs)로 탐색
    for i in installs:
        uid = i["_id"]
        counts = {}
        for c in ("humidors", "stock", "logs", "custom"):
            docs = collection(f"users/{uid}/{c}")
            if docs:
                counts[c] = (len([d for d in docs if not d.get("deleted")]), max((d.get("_updated") or "") for d in docs)[:16])
        if counts:
            sync_rows.append((short(uid), counts))
except SystemExit:
    sync_rows = [("?", {"error": ("권한 없음", "")})]

# ---- 운영자 UID 통합 ----
# 2026-10-13 운영자 구글 로그인 때 익명 UID(eQbbDG…)가 새 UID(sZlitQ…)로 바뀜. 서버 문서를 옮기기 전까지 통계에서 한 사람으로 묶는다.
UID_ALIASES = {"eQbbDG": "sZlitQ"}  # 앞 6자리: 옛 → 새
_full = {}
for src in (logs, installs, sugg, feedback):
    for d in src:
        u = d.get("uid") or d.get("_id") or ""
        if len(u) > 6:
            _full.setdefault(u[:6], u)
def canon(uid):
    if not uid:
        return uid
    tgt = UID_ALIASES.get(uid[:6])
    return _full.get(tgt, tgt) if tgt else uid
for l in logs:
    l["uid"] = canon(l.get("uid"))
for s_ in sugg:
    s_["uid"] = canon(s_.get("uid"))
for f_ in feedback:
    f_["uid"] = canon(f_.get("uid"))
# installs: 옛 문서를 새 문서에 합침 (실행일 합집합, first 는 이른 쪽, last 는 늦은 쪽)
_by_id = {i["_id"]: i for i in installs}
for old6, new6 in UID_ALIASES.items():
    o = next((i for i in installs if i["_id"].startswith(old6)), None)
    n = next((i for i in installs if i["_id"].startswith(new6)), None)
    if o and n:
        n["days"] = sorted(set(n.get("days") or []) | set(o.get("days") or []))
        n["first"] = min(filter(None, [n.get("first"), o.get("first")]))
        n["last"] = max(filter(None, [n.get("last"), o.get("last")]))
        installs.remove(o)
    elif o and not n:
        o["_id"] = new6 + o["_id"][6:]

# ---- 사용자 ----
uids = {l.get("uid") for l in logs}
lang_by_uid = defaultdict(Counter)
for l in logs:
    lang_by_uid[l.get("uid")][l.get("lang") or "ko?"] += 1
uid_lang = {u: c.most_common(1)[0][0] for u, c in lang_by_uid.items()}
lang_users = Counter(uid_lang.values())

inst_platform = Counter(i.get("platform", "?") for i in installs)
inst_version = Counter(f"{i.get('platform','?')} b{i.get('build','?')}" for i in installs)
inst_lang = Counter(i.get("lang", "?") for i in installs)
active7 = sum(1 for i in installs if (i.get("last") or "")[:10] >= (today - dt.timedelta(days=7)).isoformat())

# ---- 기록 ----
by_day = Counter()
for l in logs:
    u = (l.get("_updated") or "")[:10]
    if u:
        by_day[u] += 1
recent_days = [(today - dt.timedelta(days=i)).isoformat() for i in range(13, -1, -1)]

# ---- 시가별 ----
per_cigar = defaultdict(list)
for l in logs:
    per_cigar[(l.get("cigar_id"), l.get("cigar_name"))].append(l)
ranking = []
for (cid, name), ls in per_cigar.items():
    people = {x.get("uid") for x in ls}
    avg = sum(score10(x.get("score")) for x in ls) / len(ls)
    tags = Counter(t for x in ls for t in (x.get("tags") or []))
    ranking.append({"cigar_id": cid, "name": name, "logs": len(ls), "people": len(people), "avg": round(avg, 2),
                    "top_tags": [t for t, _ in tags.most_common(5)]})
ranking.sort(key=lambda r: (-r["people"], -r["logs"], -r["avg"]))

# ---- 최근 기록 ----
recent = sorted(logs, key=lambda l: l.get("_updated") or "", reverse=True)[:25]

# ---- 마크다운 ----
L = []
L.append(f"## MyHumidor 운영 통계 · {today.isoformat()}")
L.append("")
L.append("### 사용자")
L.append(f"- 기록 공유 중인 사람(익명 UID): **{len(uids)}명** — " + ", ".join(f"{k} {v}" for k, v in lang_users.most_common()))
L.append(f"- 공유된 기록: **{len(logs)}건**")
if installs:
    L.append(f"- 앱 실행 기록(installs): **{len(installs)}대** · 최근 7일 활성 {active7}대")
    L.append("  - 플랫폼: " + ", ".join(f"{k} {v}" for k, v in inst_platform.most_common()))
    L.append("  - 언어: " + ", ".join(f"{k} {v}" for k, v in inst_lang.most_common()))
    L.append("  - 버전: " + ", ".join(f"{k} ×{v}" for k, v in sorted(inst_version.items())))
else:
    L.append("- 앱 실행 기록(installs): 아직 없음 (②번 업데이트 배포 후 쌓임)")
L.append(f"- 스캔 카운터 문서: {len(quota)}개")
L.append("")
L.append("### 최근 14일 기록 수 (서버 갱신일 기준)")
L.append("| " + " | ".join(d[5:] for d in recent_days) + " |")
L.append("|" + "---|" * len(recent_days))
L.append("| " + " | ".join(str(by_day.get(d, 0)) for d in recent_days) + " |")
# 일별 실행 기기 수 (installs.days, b43+)
act_day = Counter(d for i in installs for d in (i.get("days") or []))
if act_day:
    L.append("")
    L.append("실행 기기 수 (그날 앱을 연 기기, b43+):")
    L.append("| " + " | ".join(d[5:] for d in recent_days) + " |")
    L.append("|" + "---|" * len(recent_days))
    L.append("| " + " | ".join(str(act_day.get(d, 0)) for d in recent_days) + " |")
L.append("")
L.append("### 시가별 (운영자 전용 랭킹 — 앱 노출 안 함)")
L.append("| # | 시가 | 사람 | 기록 | 평균 | 많이 느낀 노트 |")
L.append("|--:|---|--:|--:|--:|---|")
for i, r in enumerate(ranking[:40], 1):
    L.append(f"| {i} | {r['name']} | {r['people']} | {r['logs']} | {r['avg']:.1f} | {', '.join(r['top_tags'])} |")
if len(ranking) > 40:
    L.append(f"| … | 외 {len(ranking) - 40}종 | | | | |")
L.append("")
L.append("### 최근 기록 25건")
L.append("| 갱신 | 사용자 | 언어 | 시가 | 비톨라 | 점수 | 태그 |")
L.append("|---|---|---|---|---|--:|---|")
for l in recent:
    L.append(f"| {(l.get('_updated') or '')[:10]} | {short(l.get('uid'))} | {l.get('lang') or '-'} | {l.get('cigar_name')} | "
             f"{l.get('vitola') or ''} | {score10(l.get('score')):.1f} | {', '.join(l.get('tags') or [])[:60]} |")
L.append("")
L.append("### 실행 기록 (installs, UID별)")
if installs:
    log_uids = {short(u) for u in uids}
    # 실행일 달력: 최근 14일, 들어온 날은 ●  (days 필드는 b43+ 에서만 쌓임 — 그 전 기기는 first/last 만)
    cal_days = recent_days
    L.append("| UID | 플랫폼 | 언어 | 빌드 | 첫 실행 | 마지막 | 공유 | 기록 | 실행일수 | " + " ".join(d[8:] for d in cal_days) + " |")
    L.append("|---|---|---|--:|---|---|:-:|:-:|--:|" + "---|")
    for i in sorted(installs, key=lambda x: x.get("last") or "", reverse=True):
        su = short(i["_id"])
        days = set(i.get("days") or [])
        share = i.get("share")
        share_s = "" if share is None else ("on" if share else "**off**")
        cal = " ".join("●" if d in days else "·" for d in cal_days)
        L.append(f"| {su} | {i.get('platform','')} | {i.get('lang','')} | {i.get('build','')} | {i.get('first','')} | {i.get('last','')} | {share_s} | {'✓' if su in log_uids else ''} | {len(days) or ''} | {cal} |")
    L.append("")
    L.append("_공유: 익명 집계 켜짐 여부(b43+). 실행일수·달력: 실행한 날짜 기준(b43+), ● = 그날 한 번 이상 실행._")
else:
    L.append("- 없음")
L.append("")
L.append("### 사용자별")
L.append("| 사용자 | 언어 | 기록 | 평균 | 마지막 갱신 |")
L.append("|---|---|--:|--:|---|")
per_uid = defaultdict(list)
for l in logs:
    per_uid[l.get("uid")].append(l)
for u, ls in sorted(per_uid.items(), key=lambda kv: -len(kv[1])):
    last = max((x.get("_updated") or "") for x in ls)[:10]
    avg = sum(score10(x.get("score")) for x in ls) / len(ls)
    L.append(f"| {short(u)} | {uid_lang.get(u)} | {len(ls)} | {avg:.1f} | {last} |")
L.append("")
L.append("<details><summary><b>사용자별 전체 기록</b> (펼치기)</summary>")
L.append("")
for u, ls in sorted(per_uid.items(), key=lambda kv: -len(kv[1])):
    L.append(f"**{short(u)}** ({uid_lang.get(u)}) · {len(ls)}건")
    L.append("")
    L.append("| 날짜 | 시가 | 비톨라 | 점수 | 태그 |")
    L.append("|---|---|---|--:|---|")
    for l in sorted(ls, key=lambda x: (x.get("date") or "", x.get("_updated") or ""), reverse=True):
        L.append(f"| {l.get('date') or ''} | {l.get('cigar_name')} | {l.get('vitola') or ''} | {score10(l.get('score')):.1f} | {', '.join(l.get('tags') or [])[:60]} |")
    L.append("")
L.append("</details>")
L.append("")
L.append("### 운영자 동기화 (users/)")
if sync_rows:
    L.append("| UID | 휴미더 | 재고 | 기록 | 직접추가 | 마지막 갱신(UTC) |")
    L.append("|---|--:|--:|--:|--:|---|")
    for su, c in sync_rows:
        last = max((v[1] for v in c.values()), default="")
        L.append(f"| {su} | {c.get('humidors',(0,))[0]} | {c.get('stock',(0,))[0]} | {c.get('logs',(0,))[0]} | {c.get('custom',(0,))[0]} | {last} |")
else:
    L.append("- 없음 (아직 동기화된 데이터 없음)")
L.append("")
L.append(f"### 제작자에게 제안·피드백 ({len(feedback)}건)")
if feedback:
    L.append("| 날짜 | 사용자 | 플랫폼 | 빌드 | 연락처 | 내용 |")
    L.append("|---|---|---|--:|---|---|")
    for f in sorted(feedback, key=lambda f: f.get("_updated") or "", reverse=True):
        txt = (f.get("text") or "").replace("|", "¦").replace("\n", " ")
        L.append(f"| {(f.get('_updated') or '')[:10]} | {short(f.get('uid'))} | {f.get('platform') or ''} | {f.get('build') or ''} | {(f.get('contact') or '')[:40]} | {txt[:300]} |")
else:
    L.append("- 없음")
L.append("")
L.append(f"### DB 제안 ({len(sugg)}건)")
if sugg:
    L.append("| 날짜 | 사용자 | 브랜드 | 라인 | 비톨라 | 원산지 | 강도 | 래퍼 | 메모 |")
    L.append("|---|---|---|---|---|---|---|---|---|")
    for s in sorted(sugg, key=lambda s: s.get("_updated") or "", reverse=True):
        L.append(f"| {(s.get('_updated') or '')[:10]} | {short(s.get('uid'))} | {s.get('brand')} | {s.get('line')} | {s.get('vitola') or ''} | "
                 f"{s.get('country') or ''} | {s.get('strength') or ''} | {s.get('wrapper') or ''} | {(s.get('note') or '')[:80]} |")
else:
    L.append("- 없음")
L.append("")
L.append("_자동 생성 (stats.yml). 익명 UID 앞 6자리만 표시._")

md = "\n".join(L)
open(OUT_MD, "w", encoding="utf-8").write(md)
if OUT_JSON:
    json.dump({"date": today.isoformat(), "users": len(uids), "logs": len(logs), "lang_users": lang_users,
               "installs": installs, "ranking": ranking, "suggestions": sugg,
               "logs_raw": logs}, open(OUT_JSON, "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
print(md)
