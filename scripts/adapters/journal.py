"""Review adapter: Cigar Journal (cigarjournal.com). Unscored editorial tastings.

REST search returns full post content, so one request per line. Keep posts whose title
contains all query words and that read like a tasting (title prefix "Tasting" or body has
note words). Source: review:journal.
"""
import re, json, time, html, csv
from pathlib import Path
from urllib.parse import quote
from .base import fetch, strip_html
from .dojo import norm, query_words, load_seed, title_matches

SEARCH = "https://www.cigarjournal.com/wp-json/wp/v2/posts?per_page=5&search="
SKIP_TITLE = re.compile(r"festival|award|top 25|trophy|interview|factory|visit|launch|release|news|event|edition \d{4}|cover", re.I)


def search(brand, line):
    words = query_words(brand, line)
    try:
        data = json.loads(fetch(SEARCH + quote(" ".join(words))))
    except Exception:
        return []
    hits = []
    for p in data:
        title = html.unescape(p["title"]["rendered"])
        nt = norm(title)
        words = query_words(brand, line)
        if not all(w in nt for w in words) or SKIP_TITLE.search(title):
            continue
        body = strip_html(p["content"]["rendered"])
        if not re.search(r"\b(notes?|aromas?|palate|flavou?r|spic|sweet|cream|wood|pepper|leather|earth)", body, re.I):
            continue
        hits.append({"title": title, "url": p["link"], "body": body})
    return hits[:1]


def run(limit=None, delay=2.0, offset=0):
    out = []
    seed = load_seed()[offset: offset + limit if limit else None]
    for brand, line in seed:
        for h in search(brand, line):
            body = h["body"]
            m = re.search(r"(first|initial) (third|puffs?|draws?)", body, re.I)
            note = body[m.start():m.start() + 5000] if m else body[:5000]
            out.append({"brand": brand, "name": line, "vitola": "", "note_text": note,
                        "review_url": h["url"], "review_title": h["title"], "source": "review:journal"})
        time.sleep(delay)
    return out
