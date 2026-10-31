"""db/cigars.json + db/tags.json → app/assets/ 축약본.

앱에는 노트 원문(text)은 넣지 않고 태그/스펙/평점만 넣는다.
실행: python3 scripts/build_app_assets.py
"""
import datetime
import hashlib
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "app" / "assets"
OUT.mkdir(parents=True, exist_ok=True)

SPEC_KEYS = ["strength", "wrapper", "binder", "filler", "length_in", "ring_gauge", "factory_vitola", "strength_felt"]

cigars = json.load(open(ROOT / "db" / "cigars.json", encoding="utf-8"))
tags = json.load(open(ROOT / "db" / "tags.json", encoding="utf-8"))

out = []
for cid, c in cigars.items():
    seed = c.get("seed") or {}
    specs = c.get("specs") or {}
    notes = c.get("notes") or {}
    official = list(dict.fromkeys(notes.get("official", [])))
    review = list(dict.fromkeys(notes.get("review", [])))
    # 리뷰 출처 수(합의 표시용): 소스별로 태그가 몇 군데서 나왔는지
    tag_votes = {}
    for ns in c.get("note_sources", []):
        src = ns.get("source", "")
        for t in ns.get("tags", []):
            tag_votes.setdefault(t, set()).add(src)
    rating = None
    r = (c.get("ratings") or {}).get("dojo")
    if r and r.get("score"):
        rating = {"dojo": r["score"]}
    item = {
        "id": cid,
        "brand": c["brand"],
        "name": c["name"],
        "cuban": bool(seed.get("cuban")),
        "vitolas": c.get("vitolas") or [],
        "official": official,
        "review": review,
        "votes": {t: len(s) for t, s in tag_votes.items() if len(s) > 1},
    }
    sp = {k: specs[k] for k in SPEC_KEYS if specs.get(k)}
    if sp:
        item["specs"] = sp
    if rating:
        item["rating"] = rating
    if c.get("aliases"):
        item["aliases"] = c["aliases"]
    if c.get("legacy_ids"):
        item["legacy"] = c["legacy_ids"]  # 병합된 옛 id → 사용자 기록 호환
    if seed.get("tubos"):
        item["tubos"] = True
    out.append(item)

out.sort(key=lambda x: (x["brand"].lower(), x["name"].lower()))
json.dump(out, open(OUT / "cigars.json", "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))

tag_out = {
    "groups": [
        {
            "id": g["id"],
            "ko": g["ko"],
            "tags": [{"id": t["id"], "ko": t["ko"], "hint": t.get("hint", ""), "en": t.get("en", t["ko"]), "hint_en": t.get("hint_en", "")} for t in g["tags"]],
            "en": g.get("en", g["ko"]),
        }
        for g in tags["groups"]
    ]
}
json.dump(tag_out, open(OUT / "tags.json", "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))

# 원격 갱신용 메타 (앱이 docs/db/meta.json 의 rev 와 비교). rev = 생성 시각(UTC ISO)
raw = (OUT / "cigars.json").read_bytes()
sha = hashlib.sha256(raw).hexdigest()[:16]
try:
    prev = json.load(open(OUT / "db_meta.json"))
except Exception:  # noqa
    prev = {}
# 내용이 같으면 rev 유지 (앱이 쓸데없이 다시 받지 않게)
rev = prev["rev"] if prev.get("sha") == sha else datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
meta = {"rev": rev, "sha": sha, "count": len(out)}
json.dump(meta, open(OUT / "db_meta.json", "w"), separators=(",", ":"))

# 장소 목록 (db/places.json → assets/places.json 그대로) + 메타
praw = (ROOT / "db" / "places.json").read_bytes() if (ROOT / "db" / "places.json").exists() else b"[]"
places = json.loads(praw)
(OUT / "places.json").write_bytes(json.dumps(places, ensure_ascii=False, separators=(",", ":")).encode())
psha = hashlib.sha256((OUT / "places.json").read_bytes()).hexdigest()[:16]
try:
    pprev = json.load(open(OUT / "places_meta.json"))
except Exception:  # noqa
    pprev = {}
prev_rev = pprev["rev"] if pprev.get("sha") == psha else datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump({"rev": prev_rev, "sha": psha, "count": len(places)}, open(OUT / "places_meta.json", "w"), separators=(",", ":"))
print(f"places {len(places)} → {OUT/'places.json'}")

n_notes = sum(1 for x in out if x["official"] or x["review"])
print(f"cigars {len(out)} (with notes {n_notes}) → {OUT/'cigars.json'} {(OUT/'cigars.json').stat().st_size//1024} KB")
print(f"tags {sum(len(g['tags']) for g in tag_out['groups'])} → {OUT/'tags.json'}")
