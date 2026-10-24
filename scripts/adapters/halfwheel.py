"""Review adapter: halfwheel (halfwheel.com) via the WordPress REST API.

For every DB entry that still has no note text, search posts in the Reviews category
(`categories=5`) for "<brand> <line>", keep the first hit whose title contains the brand and
most of the line words, and take from `content.rendered`:
  - specs block: Country of Origin / Wrapper / Binder / Filler / Length / Ring Gauge
  - tasting text: the paragraphs between the specs block ("Number of Cigars Smoked For Review")
    and "Final Notes" (this is the first/second/final-third narrative)
Source id: review:halfwheel. Review URL + title stored (editorial, not retail). No score (it is
rendered outside the post body).
"""
import json, re, time, html, urllib.error
from pathlib import Path
from urllib.parse import quote
from .base import fetch as _fetch
from .dojo import norm, title_matches, STOP

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "db" / "cigars.json"
API = "https://halfwheel.com/wp-json/wp/v2/posts?categories=5&per_page=6&_fields=id,title,link,content,date&search="
SPEC_KEYS = {"Country of Origin": "country", "Wrapper": "wrapper", "Binder": "binder", "Filler": "filler", "Length": "length", "Ring Gauge": "ring"}


def fetch(url, tries=4):
    for i in range(tries):
        try:
            return _fetch(url)
        except urllib.error.HTTPError as e:
            if e.code not in (429, 503) or i == tries - 1:
                raise
            ra = e.headers.get("Retry-After")
            time.sleep(min(int(ra), 180) if ra and ra.isdigit() else 30 * (i + 1))


def targets():
    db = json.loads(DB.read_text(encoding="utf-8"))
    out = []
    for sid, e in db.items():
        if any(s.get("text") for s in e.get("note_sources", [])):
            continue
        if any(s.get("source") == "review:halfwheel" for s in e.get("note_sources", [])):
            continue  # searched before, nothing usable
        out.append((e["brand"], e["name"], sid))
    return out


def to_text(rendered):
    t = re.sub(r"<(script|style)[^>]*>.*?</\1>", " ", rendered, flags=re.S | re.I)
    t = re.sub(r"<li[^>]*>", "\n- ", t)
    t = re.sub(r"</?(p|div|h\d|ul|ol|br|tr)[^>]*>", "\n", t)
    t = html.unescape(re.sub(r"<[^>]+>", " ", t))
    t = re.sub(r"[ \t]+", " ", t)
    return re.sub(r"\n\s*\n+", "\n", t).strip()


def parse(post):
    t = to_text(post["content"]["rendered"])
    specs = {}
    for k, key in SPEC_KEYS.items():
        m = re.search(r"\n(?:- )?%s:\s*\n?\s*([^\n]{1,80})" % re.escape(k), t)
        if m:
            specs[key] = m.group(1).strip()
    body = t
    m = re.search(r"Number of Cigars Smoked For Review:\s*\n?\s*\d+\s*\n", t)
    if m:
        body = t[m.end():]
    else:
        m = re.search(r"\nRelease Date:[^\n]*\n(?:[^\n]*\n){0,3}", t)
        if m:
            body = t[m.end():]
    j = body.find("Final Notes")
    if j > 0:
        body = body[:j]
    paras = [p.strip() for p in body.split("\n") if len(p.strip()) > 80 and not p.strip().startswith("- ")]
    # drop the appearance/pre-light paragraph when there are at least 3 (first / second / final third)
    if len(paras) >= 4:
        paras = paras[1:]
    text = " ".join(paras)[:2200]
    # strength / body sentence: "the strength ... medium" etc. — keep as-is for the tagger; map to spec when explicit
    m = re.search(r"strength[^.]{0,80}?\b(mild|medium-plus|medium-full|medium|full)\b", text, re.I)
    if m:
        specs["strength_felt"] = m.group(1).lower().replace("-plus", "").replace("medium-full", "medium to full")
    return text, specs


def run(limit=None, offset=0, delay=1.5):
    out = []
    ts = targets()[offset:]
    if limit:
        ts = ts[:limit]
    for brand, name, sid in ts:
        q = " ".join(w for w in norm(f"{brand} {name}").split() if w not in STOP)
        try:
            res = json.loads(fetch(API + quote(q)))
        except Exception as e:  # noqa
            out.append({"brand": brand, "name": name, "error": str(e)})
            time.sleep(delay)
            continue
        hit = None
        for p in res:
            title = html.unescape(p["title"]["rendered"])
            if title_matches(norm(title), brand, name):
                hit = p
                break
        if not hit:
            out.append({"brand": brand, "name": name, "error": "no match"})
            time.sleep(delay)
            continue
        text, specs = parse(hit)
        if len(text) < 200:
            out.append({"brand": brand, "name": name, "error": "no tasting text"})
        else:
            out.append({"brand": brand, "name": name, "vitola": "", "note_text": text, "specs": specs,
                        "source": "review:halfwheel", "review_url": hit["link"], "review_title": html.unescape(hit["title"]["rendered"])})
        time.sleep(delay)
    return out
