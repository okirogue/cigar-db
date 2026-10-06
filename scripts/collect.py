"""Run one adapter, tag its notes, and merge into db/cigars.json.

usage: python scripts/collect.py davidoff [--limit N]

Each DB entry:
{
  "id": "davidoff-signature-no-2",
  "brand": "Davidoff",
  "name": "signature no 2",
  "notes": {"official": ["floral","earth",...], "review": [...]},
  "note_sources": [{"source":"official:davidoff","tags":[...],"text":"..."}],
  "verified": false,
  "updated": "2026-10-06"
}
"""
import argparse, importlib, json, re, sys, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.tagger import extract_tags  # noqa: E402

DB = ROOT / "db" / "cigars.json"


import unicodedata
STOP = {"cigars", "cigar", "the", "by"}


def slug(brand, name):
    s = unicodedata.normalize("NFKD", f"{brand} {name}")
    s = "".join(c for c in s if not unicodedata.combining(c)).lower()
    words = [w for w in re.sub(r"[^a-z0-9]+", " ", s).split() if w not in STOP]
    # drop a repeated brand word inside the line part (e.g. "oliva oliva serie v")
    out = []
    for w in words:
        if not out or w != out[-1]:
            out.append(w)
    return "-".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("adapter")
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--offset", type=int, default=0)
    a = ap.parse_args()

    from scripts.adapters import wp_generic
    if a.adapter in wp_generic.BRANDS:
        rows = wp_generic.run(limit=a.limit, brand_key=a.adapter)
    else:
        mod = importlib.import_module(f"scripts.adapters.{a.adapter}")
        import inspect
        kw = {"limit": a.limit}
        if "offset" in inspect.signature(mod.run).parameters:
            kw["offset"] = a.offset
        rows = mod.run(**kw)

    db = json.loads(DB.read_text(encoding="utf-8")) if DB.exists() else {}
    today = datetime.date.today().isoformat()
    added = updated = errors = 0
    for r in rows:
        if r.get("error"):
            errors += 1
            print("ERR", r["name"], r["error"]); continue
        tags = extract_tags(r["note_text"])
        sid = slug(r["brand"], r["name"])
        e = db.setdefault(sid, {"id": sid, "brand": r["brand"], "name": r["name"],
                                "notes": {"official": [], "review": []},
                                "note_sources": [], "verified": False})
        kind = "official" if r["source"].startswith("official") else "review"
        key = (r["source"], r.get("vitola", ""))
        e["note_sources"] = [s for s in e["note_sources"] if (s["source"], s.get("vitola", "")) != key]
        if r["note_text"]:
            src = {"source": r["source"], "vitola": r.get("vitola", ""), "tags": tags, "text": r["note_text"]}
            if r.get("score") is not None:
                src["score"] = r["score"]; src["url"] = r.get("review_url"); src["title"] = r.get("review_title")
            e["note_sources"].append(src)
        if r.get("score") is not None:
            e.setdefault("ratings", {})[r["source"].split(":")[1]] = {"score": r["score"], "url": r.get("review_url")}
        vit = e.setdefault("vitolas", [])
        if r.get("vitola") and r["vitola"] not in vit:
            vit.append(r["vitola"])
        merged = []
        for s in e["note_sources"]:
            if (s["source"].startswith("official")) == (kind == "official"):
                for t in s["tags"]:
                    if t not in merged:
                        merged.append(t)
        e["notes"][kind] = merged
        for k, v in (r.get("specs") or {}).items():
            e.setdefault("specs", {}).setdefault(k, v)
        e["updated"] = today
        added += 1

    texts = [r.get("note_text", "") for r in rows if r.get("note_text")]
    if len(texts) >= 5:
        from collections import Counter
        top, n = Counter(texts).most_common(1)[0]
        if n / len(texts) > 0.5:
            print(f"WARNING {a.adapter}: {n}/{len(texts)} rows share the same note text -> likely boilerplate")
    DB.write_text(json.dumps(db, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{a.adapter}: {len(rows)} rows, {added} rows merged, {errors} errors, db={len(db)}")


if __name__ == "__main__":
    main()
