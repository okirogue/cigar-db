"""Shop-description adapter: cigarplace.biz line pages (all-brands/<brand>/<line>.html).

Each line page carries a `category-description` block: a retailer write-up of the blend
(factory, origin, wrapper/binder/filler, flavor words). Product listings load via JS, so only the
line-level description is used; no prices / shop URLs are stored.
URL list comes from seed/noncuban_lines.csv (source_url column, cigarplace rows) and is restricted
to lines whose id already exists in db/cigars.json, so this adapter only fills notes — it never
creates entries.
Source: shop:cigarplace
"""
import csv, html, json, re, time
from pathlib import Path
import urllib.error
from .base import fetch as _fetch


def fetch(url, tries=4):
    """cigarplace rate-limits (HTTP 429) after ~35 quick hits: back off and retry."""
    for i in range(tries):
        try:
            return _fetch(url)
        except urllib.error.HTTPError as e:
            if e.code != 429 or i == tries - 1:
                raise
            ra = e.headers.get("Retry-After")
            time.sleep(min(int(ra), 180) if ra and ra.isdigit() else 45 * (i + 1))

ROOT = Path(__file__).resolve().parents[2]
SEED = ROOT / "seed" / "noncuban_lines.csv"
DB = ROOT / "db" / "cigars.json"
DESC = re.compile(r'<div class="category-description[^"]*"[^>]*>(.*?)</div>\s*</div>', re.S)


def _slug(brand, name):
    from scripts.collect import slug
    return slug(brand, name)


def targets():
    db = json.loads(DB.read_text(encoding="utf-8"))
    out = []
    for r in csv.DictReader(SEED.open(encoding="utf-8")):
        u = r.get("source_url", "")
        if "cigarplace.biz" not in u:
            continue
        line = "" if r["line"].startswith("(") else r["line"]
        sid = _slug(r["brand"], line)
        if sid in db:
            e = db[sid]
            out.append((u, e["brand"], e["name"], sid))
    return out


def parse(page):
    m = DESC.search(page)
    if not m:
        md = re.search(r'<meta name="description" content="([^"]+)"', page)
        return html.unescape(md.group(1)).strip() if md else ""
    body = re.sub(r"<(script|style)[^>]*>.*?</\1>", " ", m.group(1), flags=re.S | re.I)
    paras = []
    for p in re.split(r"</p>", body):
        t = html.unescape(re.sub(r"<[^>]+>", " ", p))
        t = re.sub(r"\s+", " ", t).strip()
        cut = re.search(r"\(?\s*Shop all\b", t)
        if cut:
            t = t[:cut.start()].strip()
            if t:
                paras.append(t)
            break  # everything after "(Shop all …)" is store boilerplate
        if not t:
            continue
        if re.search(r"Cigar Place|cigarplace|free shipping|our online cigar shop|guarantees the freshness|Click here", t, re.I):
            break
        paras.append(t)
    return " ".join(paras).strip()




def run(limit=None, offset=0, delay=2.5):
    rows = []
    ts = targets()[offset:]
    if limit:
        ts = ts[:limit]
    for u, brand, name, sid in ts:
        try:
            page = fetch(u)
            text = parse(page)
            if len(text) < 60:
                rows.append({"brand": brand, "name": name, "error": "no description"})
            else:
                rows.append({"brand": brand, "name": name, "vitola": "", "note_text": text, "source": "shop:cigarplace"})
        except Exception as e:  # noqa
            rows.append({"brand": brand, "name": name, "error": str(e)})
        time.sleep(delay)
    return rows
