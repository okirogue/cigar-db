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
places = collection("place_suggestions")
previews = collection("place_reviews")

# 운영자 동기화 상태: users/<uid>/{humidors,stock,logs,custom} 문서 수 (내용은 안 읽음)
def _list_users():
    res = get(f"{BASE}/users?pageSize=50")
    return [d["name"].rsplit("/", 1)[-1] for d in res.get("documents", [])] if res else []
sync_rows = []
try:
    # 서브컬렉션만 있고 부모 문서가 없을 수 있어 listCollectionIds 대신 알려진 UID 후보(installs)로 탐색
    for uid in sorted({i["_id"].split("~")[0] for i in installs}):
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
for p_ in places:
    p_["uid"] = canon(p_.get("uid"))
for r_ in previews:
    r_["uid"] = canon(r_.get("uid"))
# installs: 로그인하며 흡수된 익명 문서는 뺀다 (b48+ 'absorbed'). 문서 id 'UID~플랫폼' 은 같은 사람의 기기별 문서.
_absorbed = {a for i in installs for a in (i.get("absorbed") or [])}
installs = [i for i in installs if i["_id"] not in _absorbed]
for i in installs:
    i["_uid"] = i["_id"].split("~")[0]
    i["_dev"] = i["_id"].split("~")[1] if "~" in i["_id"] else ""

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

# installs: 같은 UID 의 옛 'UID' 문서(익명 시절)와 새 'UID~플랫폼' 문서가 같이 있으면 한 기기로 합침 (같은 플랫폼 우선)
for bare in [i for i in installs if not i.get("_dev")]:
    sibs = [i for i in installs if i.get("_dev") and i["_uid"] == bare["_uid"]]
    if not sibs:
        continue
    n = next((i for i in sibs if i.get("platform") == bare.get("platform")), sibs[0])
    n["days"] = sorted(set(n.get("days") or []) | set(bare.get("days") or []))
    n["first"] = min(filter(None, [n.get("first"), bare.get("first")]))
    n["last"] = max(filter(None, [n.get("last"), bare.get("last")]))
    installs.remove(bare)

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
inst_cross = Counter((i.get("platform", "?"), i.get("lang", "?")) for i in installs)
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

# ---- 지난 집계 대비 변화 (사람이 세지 않게 스크립트가 직접) ----
# 이전 리포트 본문(PREV_BODY 파일) 끝의 <!-- snapshot {...} --> 를 읽어 id 집합으로 비교한다.
import re as _re
_prev = {}
_pb = os.environ.get("PREV_BODY")
if _pb and os.path.exists(_pb):
    _m = _re.search(r"<!-- snapshot (\{.*?\}) -->\s*$", open(_pb, encoding="utf-8").read(), flags=_re.S)
    if _m:
        try:
            _prev = json.loads(_m.group(1))
        except Exception:  # noqa
            _prev = {}
_snap = {
    "at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%MZ"),
    "logs": {l["_id"]: f"{short(l.get('uid'))}|{l.get('cigar_name') or ''}|{l.get('vitola') or ''}|{score10(l.get('score'))}" for l in logs},
    "installs": {i["_id"]: f"{i.get('platform') or ''}|{i.get('lang') or ''}|{i.get('build') or ''}" for i in installs},
    "sugg": sorted(x["_id"] for x in sugg),
    "feedback": sorted(x["_id"] for x in feedback),
    "places": sorted(x["_id"] for x in places),
    "reviews": {r["_id"]: f"{short(r.get('uid'))}|{r.get('place_id')}|{r.get('rating')}" for r in previews},
    "users": sorted(short(u) for u in uids if u),
}
_delta = []
if _prev:
    _pl, _pi = _prev.get("logs", {}), _prev.get("installs", {})
    _new_logs = [(k, v) for k, v in _snap["logs"].items() if k not in _pl]
    _chg_logs = [(k, v) for k, v in _snap["logs"].items() if k in _pl and _pl[k] != v]
    _del_logs = [k for k in _pl if k not in _snap["logs"]]
    _new_inst = [(k, v) for k, v in _snap["installs"].items() if k not in _pi]
    _new_users = [u for u in _snap["users"] if u not in set(_prev.get("users", []))]
    _new_sugg = [k for k in _snap["sugg"] if k not in set(_prev.get("sugg", []))]
    _new_fb = [k for k in _snap["feedback"] if k not in set(_prev.get("feedback", []))]
    _new_pl = [k for k in _snap["places"] if k not in set(_prev.get("places", []))]
    _pr = _prev.get("reviews", {})
    _new_rev = [(k, v) for k, v in _snap["reviews"].items() if k not in _pr or _pr[k] != v]
    _delta.append(f"### 지난 집계({_prev.get('at', '?')}) 이후 변화")
    _delta.append(f"- 기록 **{len(_pl)} → {len(_snap['logs'])}** (+{len(_new_logs)}" + (f", 수정 {len(_chg_logs)}" if _chg_logs else "") + (f", 삭제 {len(_del_logs)}" if _del_logs else "") + ")")
    for _k, _v in sorted(_new_logs, key=lambda kv: kv[1]):
        _u, _c, _vt, _sc = _v.split("|")
        _delta.append(f"  - 신규: {_u} · {_c}{(' ' + _vt) if _vt else ''} · {_sc}")
    for _k, _v in _chg_logs:
        _u, _c, _vt, _sc = _v.split("|")
        _delta.append(f"  - 수정: {_u} · {_c}{(' ' + _vt) if _vt else ''} · {_sc}")
    _delta.append(f"- 기기 **{len(_pi)} → {len(_snap['installs'])}** (+{len(_new_inst)})" + ("" if not _new_inst else ": " + ", ".join(f"{short(k)} ({v.replace('|', '·')})" for k, v in _new_inst)))
    _delta.append(f"- 공유 사용자 **{len(_prev.get('users', []))} → {len(_snap['users'])}**" + (f" (+{', '.join(_new_users)})" if _new_users else ""))
    _delta.append(f"- DB 제안 +{len(_new_sugg)} · 장소 제안 +{len(_new_pl)} · 장소 평가 +{len(_new_rev)} · 피드백 +{len(_new_fb)}")
    for _k, _v in _new_rev:
        _u, _pid, _r = _v.split("|")
        _delta.append(f"  - 장소 평가: {_u} · {_pid} · ★{_r}")
else:
    _delta.append("### 지난 집계 이후 변화")
    _delta.append("- (이전 스냅샷 없음 — 다음 집계부터 표시)")

# ---- 마크다운 ----
L = []
L.append(f"## MyHumidor 운영 통계 · {today.isoformat()}")
L.append("")
L.extend(_delta)
L.append("")
L.append("### 사용자")
L.append(f"- 기록 공유 중인 사람(익명 UID): **{len(uids)}명** — " + ", ".join(f"{k} {v}" for k, v in lang_users.most_common()))
L.append(f"- 공유된 기록: **{len(logs)}건**")
if installs:
    L.append(f"- 앱 실행 기록(installs): **{len(installs)}대** · 최근 7일 활성 {active7}대")
    L.append("  - 플랫폼: " + ", ".join(f"{k} {v}" for k, v in inst_platform.most_common()))
    L.append("  - 언어: " + ", ".join(f"{k} {v}" for k, v in inst_lang.most_common()))
    L.append("")
    L.append("  | 플랫폼 \\ 언어 | " + " | ".join(k for k, _ in inst_lang.most_common()) + " | 계 |")
    L.append("  |---|" + "--:|" * (len(inst_lang) + 1))
    for pf, n in inst_platform.most_common():
        L.append(f"  | {pf} | " + " | ".join(str(inst_cross[(pf, lg)]) for lg, _ in inst_lang.most_common()) + f" | {n} |")
    L.append("  | 계 | " + " | ".join(str(v) for _, v in inst_lang.most_common()) + f" | {len(installs)} |")
    L.append("")
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
# ---- 평점순 (2명 이상 피운 시가) + 노트 선호 ----
L.append("### 평점순 (2명 이상 기록한 시가)")
_multi = sorted([r for r in ranking if r["people"] >= 2], key=lambda r: (-r["avg"], -r["people"]))
if _multi:
    L.append("| # | 시가 | 평균 | 사람 | 기록 | 노트 |")
    L.append("|--:|---|--:|--:|--:|---|")
    for i, r in enumerate(_multi, 1):
        L.append(f"| {i} | {r['name']} | {r['avg']:.1f} | {r['people']} | {r['logs']} | {', '.join(r['top_tags'][:4])} |")
else:
    L.append("- 없음")
L.append("")
L.append("### 노트 선호 (공유 기록 전체, 운영자 제외)")
_op = next((u for u in uids if u and u.startswith("sZlitQ")), None)
_tag_all, _tag_hi, _tag_lo, _tag_users = Counter(), Counter(), Counter(), defaultdict(set)
for l in logs:
    if l.get("uid") == _op:
        continue
    sc = score10(l.get("score"))
    for t in (l.get("tags") or []):
        _tag_all[t] += 1
        _tag_users[t].add(l.get("uid"))
        if sc >= 8.5:
            _tag_hi[t] += 1
        elif sc < 7:
            _tag_lo[t] += 1
if _tag_all:
    L.append("| 노트 | 언급 | 사람 | 8.5점↑ 기록에서 | 7점 미만에서 |")
    L.append("|---|--:|--:|--:|--:|")
    for t, n in _tag_all.most_common(20):
        L.append(f"| {t} | {n} | {len(_tag_users[t])} | {_tag_hi[t]} | {_tag_lo[t]} |")
else:
    L.append("- 없음")
L.append("")
L.append("### 최근 기록 25건")
L.append("| 갱신 | 사용자 | 언어 | 시가 | 비톨라 | 점수 | 태그 |")
L.append("|---|---|---|---|---|--:|---|")
for l in recent:
    L.append(f"| {(l.get('_updated') or '')[:16].replace('T', ' ')}Z | {short(l.get('uid'))} | {l.get('lang') or '-'} | {l.get('cigar_name')} | "
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
        su = short(i.get("_uid", i["_id"])) + (f"~{i['_dev']}" if i.get("_dev") else "")
        days = set(i.get("days") or [])
        share = i.get("share")
        share_s = "" if share is None else ("on" if share else "**off**")
        cal = " ".join("●" if d in days else "·" for d in cal_days)
        L.append(f"| {su} | {i.get('platform','')} | {i.get('lang','')} | {i.get('build','')} | {i.get('first','')} | {i.get('last','')} | {share_s} | {'✓' if short(i.get('_uid', i['_id'])) in log_uids else ''} | {len(days) or ''} | {cal} |")
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
L.append(f"### 장소 제안 ({len(places)}건)")
if places:
    L.append("| 날짜 | 사용자 | 언어 | 상호명 | 유형 | 흡연 | 시가판매 | 별점 | 위치 | 코멘트 | 문서 id |")
    L.append("|---|---|---|---|---|---|---|--:|---|---|---|")
    for p_ in sorted(places, key=lambda x: x.get("_updated") or "", reverse=True):
        loc = f"[{p_['lat']:.5f},{p_['lng']:.5f}](https://www.google.com/maps/search/?api=1&query={p_['lat']:.6f},{p_['lng']:.6f})" if p_.get("lat") is not None and p_.get("lng") is not None else ""
        txt = (p_.get("comment") or "").replace("|", "¦").replace("\n", " ")
        L.append(f"| {(p_.get('_updated') or '')[:10]} | {short(p_.get('uid'))} | {p_.get('lang') or ''} | {(p_.get('name') or '')[:60]} | {', '.join(p_.get('kinds') or [])} | "
                 f"{', '.join(p_.get('smoking') or [])} | {p_.get('sells') or ''} | {p_.get('rating') or ''} | {loc} | {txt[:120]} | `{p_['_id']}` |")
else:
    L.append("- 없음")
L.append("")
L.append(f"### 장소 평가 ({len(previews)}건)")
if previews:
    _byp = defaultdict(list)
    for r_ in previews:
        _byp[r_.get("place_id") or "?"].append(r_)
    L.append("| 장소 | 평가 | 평균 | 최근 코멘트 (사용자 · 별점 · 날짜) |")
    L.append("|---|--:|--:|---|")
    for pid, rs in sorted(_byp.items(), key=lambda kv: -len(kv[1])):
        rated = [r for r in rs if r.get("rating")]
        avg = f"{sum(r['rating'] for r in rated) / len(rated):.1f}" if rated else ""
        recent = sorted(rs, key=lambda r: r.get("_updated") or "", reverse=True)[:3]
        cm = "<br>".join(f"{short(r.get('uid'))} ★{r.get('rating')} {(r.get('_updated') or '')[:10]}: {(r.get('comment') or '').replace('|', '¦')[:80]}" for r in recent)
        L.append(f"| {pid} | {len(rs)} | {avg} | {cm} |")
else:
    L.append("- 없음")
L.append("")
L.append("_자동 생성 (stats.yml). 익명 UID 앞 6자리만 표시._")
L.append("")
L.append("<!-- snapshot " + json.dumps(_snap, ensure_ascii=False, separators=(",", ":")) + " -->")

md = "\n".join(L)
open(OUT_MD, "w", encoding="utf-8").write(md)
if OUT_JSON:
    json.dump({"date": today.isoformat(), "users": len(uids), "logs": len(logs), "lang_users": lang_users,
               "installs": installs, "ranking": ranking, "suggestions": sugg,
               "logs_raw": logs}, open(OUT_JSON, "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
print(md)
