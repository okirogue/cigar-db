"""Extract flavor tags from English tasting-note text using db/tags.json.

Rules
- word-boundary, case-insensitive match on each synonym
- a hit within 5 words after a negation word is dropped
- a hit inside an excluded context phrase (e.g. "cedar sleeve") is dropped
Returns tag ids in order of first appearance.
"""
import json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TAGS = json.loads((ROOT / "db" / "tags.json").read_text(encoding="utf-8"))

_patterns = []
for g in TAGS["groups"]:
    for t in g["tags"]:
        syns = sorted(t["synonyms"], key=len, reverse=True)
        rx = re.compile(r"\b(" + "|".join(re.escape(s) for s in syns) + r")\b", re.I)
        _patterns.append((t["id"], rx))

_neg = re.compile(r"\b(" + "|".join(re.escape(n) for n in TAGS["negations"]) + r")\b", re.I)
_excl = [re.compile(re.escape(e), re.I) for e in TAGS.get("exclude_contexts", [])]


_vitola_no = re.compile(r"\bNo\.?\s*\d", re.I)   # "No. 2", "No.4" are vitola names, not negations


def _negated(text, start):
    before = text[max(0, start - 60):start]
    before = _vitola_no.sub("NUM ", before)
    m = list(_neg.finditer(before))
    if not m:
        return False
    tail = before[m[-1].end():]
    return len(tail.split()) <= 5


def _excluded(text, start, end):
    window = text[max(0, start - 20):end + 20]
    return any(rx.search(window) for rx in _excl)


def extract_tags(text: str):
    if not text:
        return []
    hits = []
    for tid, rx in _patterns:
        for m in rx.finditer(text):
            if _negated(text, m.start()) or _excluded(text, m.start(), m.end()):
                continue
            hits.append((m.start(), tid))
            break
    hits.sort()
    out, seen = [], set()
    for _, tid in hits:
        if tid not in seen:
            seen.add(tid); out.append(tid)
    return out


if __name__ == "__main__":
    import sys
    print(extract_tags(sys.stdin.read()))
