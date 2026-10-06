"""Review adapter: Cigar Dojo (cigardojo.com).

Search via /wp-json/wp/v2/search, pick result titles that contain every word of the
brand+line query, fetch the review, require a % score, take the "Smoking Experience" section
as tasting text and the top spec block (Vitola/Wrapper/Binder/Filler/Strength/Body/Country/Price).
Source id: review:dojo. Review URL is stored (editorial, not retail).
"""
import re, json, time, html, unicodedata, csv
from pathlib import Path
from urllib.parse import quote
from .base import fetch, strip_html

ROOT = Path(__file__).resolve().parents[2]
SEARCH = "https://cigardojo.com/wp-json/wp/v2/search?per_page=10&search="
STOP = {"cigars", "cigar", "series", "serie", "the", "by", "de", "and", "&"}


def norm(s):
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.lower().replace("–", "-").replace("—", "-").replace("’", "'")
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def query_words(brand, line):
    words = [w for w in norm(f"{brand} {line}").split() if w not in STOP]
    return words


def title_matches(title_norm, brand, line):
    bw = [w for w in norm(brand).split() if w not in STOP]
    lw = [w for w in norm(line).split() if w not in STOP and w not in bw]
    tw = set(title_norm.split())
    if not all(w in tw or w in title_norm for w in bw):
        return False
    if not lw:
        return True
    hit = sum(1 for w in lw if w in tw or (len(w) > 3 and w in title_norm))
    return hit / len(lw) >= 0.7


def search(brand, line):
    words = query_words(brand, line)
    q = " ".join(words)
    try:
        data = json.loads(fetch(SEARCH + quote(q)))
    except Exception:
        return []
    hits = []
    for it in data:
        title = norm(html.unescape(it.get("title", "")))
        if title_matches(title, brand, line):
            hits.append({"title": html.unescape(it["title"]), "url": it["url"]})
    return hits[:3]


SPEC_KEYS = ["vitola", "wrapper", "binder", "filler", "strength", "body", "country", "price", "factory"]


def parse_review(page):
    text = strip_html(page)
    tail = text[-8000:]
    # the rating block: a verdict label followed by the overall percentage, e.g. "Old Guard 95%"
    cands = [int(x) for x in re.findall(r"(?:Overall|Rating|Score|Verdict)[^%]{0,80}?(\d{2})\s?%", tail, re.I)]
    if not cands:
        cands = [int(x) for x in re.findall(r"\b(\d{2})\s?%", tail)]
    cands = [c for c in cands if 60 <= c <= 99]
    if not cands:
        return None
    score = cands[-1]
    spec = {}
    for k in SPEC_KEYS:
        mm = re.search(rf"\b{k}\s*[:\-–—]\s*([^|]{{2,80}}?)(?=\s{{2,}}|\s+(?:{'|'.join(SPEC_KEYS)})\s*[:\-–—]|$)", text[:4000], re.I)
        if mm:
            spec[k] = mm.group(1).strip(" .")
    se = re.search(r"Smoking Experience(.*?)(Would I Smoke|Final Verdict|Conclusion|Overall|$)", text, re.I | re.S)
    note = se.group(1).strip() if se else ""
    if len(note) < 80:   # fallback: whole body minus header
        note = text[2000:9000]
    return {"score": score, "spec": spec, "note": note[:6000]}


def load_seed():
    rows = []
    with open(ROOT / "seed" / "noncuban_lines.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if "infused" in r["flags"] or r["line"] == "(브랜드 단일)":
                continue
            rows.append((r["brand"], r["line"]))
    with open(ROOT / "seed" / "cuban_lineup.csv", encoding="utf-8") as f:
        seen = set()
        for r in csv.DictReader(f):
            k = (r["brand"], r["vitola_name"])
            if k not in seen:
                seen.add(k); rows.append(k)
    return rows


def run(limit=None, delay=2.0, offset=0):
    out = []
    seed = load_seed()[offset: offset + limit if limit else None]
    for brand, line in seed:
        hits = search(brand, line)
        time.sleep(delay)
        for h in hits[:1]:
            try:
                page = fetch(h["url"])
            except Exception as e:  # noqa
                out.append({"brand": brand, "name": line, "error": str(e)}); continue
            rv = parse_review(page)
            time.sleep(delay)
            if not rv:
                continue
            out.append({"brand": brand, "name": line, "vitola": rv["spec"].get("vitola", ""),
                        "note_text": rv["note"], "specs": rv["spec"],
                        "score": rv["score"], "review_url": h["url"], "review_title": h["title"],
                        "source": "review:dojo"})
    return out
