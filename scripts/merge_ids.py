"""Merge DB entries that refer to the same line under different ids.

Strategy: for every entry, compute a canonical key from (brand, name) with brand words,
stop words and vitola suffixes removed; entries sharing a key are merged (sources appended,
tags unioned, specs/ratings/vitolas combined). The surviving id is the shortest one.
"""
import json, re, sys, unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "db" / "cigars.json"
STOP = {"cigars", "cigar", "the", "by", "series", "serie", "edition", "line"}
VITOLA_WORDS = {"robusto", "toro", "churchill", "corona", "gordo", "torpedo", "belicoso", "lancero",
                "petit", "short", "double", "gran", "grande", "perfecto", "piramides", "pyramid",
                "figurado", "lonsdale", "panetela", "box", "pressed", "tubo", "tubos"}


def canon(brand, name):
    s = unicodedata.normalize("NFKD", f"{brand} {name}")
    s = "".join(c for c in s if not unicodedata.combining(c)).lower()
    words = [w for w in re.sub(r"[^a-z0-9]+", " ", s).split() if w not in STOP]
    bwords = set(re.sub(r"[^a-z0-9]+", " ", brand.lower()).split()) - STOP
    rest = [w for w in words if w not in bwords and w not in VITOLA_WORDS]
    return " ".join(sorted(bwords)) + "|" + " ".join(rest)


def merge(a, b):
    a["note_sources"] += [s for s in b["note_sources"] if s not in a["note_sources"]]
    for k in ("official", "review"):
        for t in b["notes"].get(k, []):
            if t not in a["notes"][k]:
                a["notes"][k].append(t)
    a.setdefault("vitolas", [])
    for v in b.get("vitolas", []):
        if v and v not in a["vitolas"]:
            a["vitolas"].append(v)
    for k, v in b.get("specs", {}).items():
        a.setdefault("specs", {}).setdefault(k, v)
    for k, v in b.get("ratings", {}).items():
        a.setdefault("ratings", {}).setdefault(k, v)
    a["aliases"] = sorted(set(a.get("aliases", []) + [b["name"]] + b.get("aliases", [])) - {a["name"]})
    a["verified"] = a.get("verified") or b.get("verified", False)
    return a


def main():
    db = json.loads(DB.read_text(encoding="utf-8"))
    groups = {}
    for sid, e in db.items():
        groups.setdefault(canon(e["brand"], e["name"]), []).append(sid)
    # second pass: within a brand, a key whose line words are a superset of another key's
    # non-empty line words (e.g. "serie v melanio" vs "serie v") are NOT merged, but
    # identical word sets in different order are
    out, merged = {}, 0
    for key, ids in groups.items():
        ids.sort(key=lambda i: (len(db[i]["name"]), i))
        base = db[ids[0]]
        for other in ids[1:]:
            base = merge(base, db[other]); merged += 1
        out[base["id"]] = base
    DB.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(db)} -> {len(out)} entries ({merged} merged)")


if __name__ == "__main__":
    main()
