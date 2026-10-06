"""Register every seed line that has no DB entry yet as a stub (no notes), so the app can
search/select it and users' checks can accumulate. Also attach seed metadata
(flags, Cuban specs) to existing entries. Idempotent."""
import csv, json, sys, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.collect import slug  # noqa
from scripts.merge_ids import canon  # noqa

DB = ROOT / "db" / "cigars.json"


def main():
    db = json.loads(DB.read_text(encoding="utf-8"))
    by_canon = {canon(e["brand"], e["name"]): k for k, e in db.items()}
    today = datetime.date.today().isoformat()
    added = linked = 0

    def get_or_make(brand, name, extra):
        nonlocal added, linked
        key = canon(brand, name)
        if key in by_canon:
            e = db[by_canon[key]]; linked += 1
        else:
            sid = slug(brand, name)
            if sid in db:
                e = db[sid]; linked += 1
            else:
                e = db[sid] = {"id": sid, "brand": brand, "name": name,
                               "notes": {"official": [], "review": []}, "note_sources": [],
                               "verified": False, "updated": today}
                by_canon[key] = sid; added += 1
        for k, v in extra.items():
            if v not in (None, ""):
                e.setdefault("seed", {})[k] = v
        return e

    with open(ROOT / "seed" / "noncuban_lines.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["line"] == "(브랜드 단일)":
                continue
            get_or_make(r["brand"], r["line"], {"flags": r["flags"], "shops": r["sources"], "cuban": False})

    with open(ROOT / "seed" / "cuban_lineup.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            e = get_or_make(r["brand"], r["vitola_name"], {"cuban": True, "coh_stocked": r["coh_stocked"] == "yes"})
            sp = e.setdefault("specs", {})
            sp.setdefault("length_in", r["length_in"]); sp.setdefault("ring_gauge", r["ring_gauge"])
            if r["strength"]:
                sp.setdefault("strength", r["strength"])
            if r["factory_vitola"]:
                sp.setdefault("factory_vitola", r["factory_vitola"])
            e["seed"]["tubos"] = r["tubos_available"]

    DB.write_text(json.dumps(db, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"stubs added {added}, linked to existing {linked}, total {len(db)}")


if __name__ == "__main__":
    main()
