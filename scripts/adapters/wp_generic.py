"""Generic adapter for manufacturer sites (mostly WordPress) that expose one page per line.

Each brand is a config dict. The adapter:
1. collects line URLs from the sitemap(s) (or a fixed list),
2. fetches each page, strips HTML,
3. takes the tasting text = meta description (if it looks like a note) + body sentences
   containing note-ish words (notes/flavor/aroma/palate/finish/hints of/tones),
4. parses W/B/F, strength and vitolas when present.
"""
import re, time, html
from urllib.parse import urlparse
from .base import fetch, strip_html

NOTE_WORDS = r"(notes?|flavou?rs?|aromas?|palate|finish|hints? of|tones?|taste|undertones?|nuances?)"
STRENGTH = r"\b(mild to medium|medium to full|mild|medium|full)[- ]?(bodied|body|strength)?\b"
WBF = re.compile(r"\b(wrapper|binder|filler)\s*[:\-–—]\s*([A-Za-z0-9 ,'’./&()-]{2,60}?)(?=\s{2,}|\s*\|?\s*\b(wrapper|binder|filler|origin|strength|body|size|vitola|price)\b|$|\.)", re.I)
VITOLA = re.compile(r"([A-Z][A-Za-z0-9.'’ \-]{2,30}?)\s*(?:[\(:—–-]\s*)?(\d(?:\s?\d/\d|[¼-¾⅛-⅞]|\.\d)?)\s*[xX×]\s*(\d{2})\b")

BRANDS = {
    "rockypatel": dict(brand="Rocky Patel", sitemaps=["https://www.rockypatel.com/cigar-sitemap.xml"],
                       pattern=r"https://www\.rockypatel\.com/cigar/[^/]+/", delay=2),
    "oliva": dict(brand="Oliva", sitemaps=["https://olivacigar.com/products-sitemap.xml"],
                  pattern=r"https://olivacigar\.com/cigars/[^/]+/", delay=2),
    "drewestate": dict(brand="Drew Estate", sitemaps=["https://drewestate.com/products-sitemap.xml"],
                       pattern=r"https://drewestate\.com/products/[^/]+/[^/]+/", delay=10),
    "myfather": dict(brand="My Father", sitemaps=["https://myfathercigars.com/wp-sitemap-posts-cigar-1.xml"],
                     pattern=r"https://myfathercigars\.com/cigar/[^/]+/", delay=2),
    "casacarrillo": dict(brand="E.P. Carrillo", sitemaps=["https://casacarrillocigars.com/page-sitemap.xml"],
                         pattern=r"https://casacarrillocigars\.com/[^/]+/",
                         extra_urls=["https://casacarrillocigars.com/pledge/", "https://casacarrillocigars.com/encore/",
                                     "https://casacarrillocigars.com/la-historia/", "https://casacarrillocigars.com/deep-blue/",
                                     "https://casacarrillocigars.com/essence-sumatra/", "https://casacarrillocigars.com/inch-natural/",
                                     "https://casacarrillocigars.com/allegiance/"],
                         skip=r"pledge98|about|contact|shop|retailer|privacy|terms|news|events|home|cart|checkout|account|blog|crm|epc_view", delay=2),
    "alecbradley": dict(brand="Alec Bradley", sitemaps=["https://www.alecbradley.com/sitemap.xml"],
                        pattern=r"https://www\.alecbradley\.com/cigars/[^/]+", delay=2),
    "ajfernandez": dict(brand="AJ Fernandez", sitemaps=["https://ajfcigars.com/page-sitemap.xml"],
                        pattern=r"https://ajfcigars\.com/cigars/[^/]+/(?:[^/]+/)?", delay=2,
                        rest="https://ajfcigars.com/wp-json/wp/v2/pages?per_page=100&slug="),
}


def line_urls(cfg):
    urls = set(cfg.get("extra_urls", []))
    for sm in cfg["sitemaps"]:
        try:
            xml = fetch(sm)
        except Exception:
            continue
        for u in re.findall(r"<loc>([^<]+)</loc>", xml):
            if re.fullmatch(cfg["pattern"], u):
                urls.add(u)
    skip = re.compile(cfg.get("skip", r"$^"), re.I)
    return sorted(u for u in urls if not skip.search(u))


def name_from_url(url):
    parts = [p for p in urlparse(url).path.split("/") if p]
    name = parts[-1]
    if len(parts) > 2 and parts[-2] not in ("cigar", "cigars", "products"):
        name = parts[-2] + " " + name
    return re.sub(r"[-_]+", " ", name).strip()


def meta_desc(page):
    m = re.search(r'<meta\s+(?:name|property)="(?:description|og:description)"\s+content="([^"]+)"', page, re.I)
    return html.unescape(m.group(1)) if m else ""


def body_note_sentences(text):
    sents = re.split(r"(?<=[.!?])\s+", text)
    keep = [s for s in sents if re.search(NOTE_WORDS, s, re.I) and 30 < len(s) < 400
            and not re.search(r"cookie|privacy|newsletter|subscribe|copyright|age|21\+|retailer", s, re.I)]
    return " ".join(keep[:6])


def parse_specs(text):
    spec = {}
    for m in WBF.finditer(text):
        k = m.group(1).lower()
        if k not in spec:
            spec[k] = m.group(2).strip(" .")
    m = re.search(STRENGTH, text, re.I)
    if m:
        spec["strength"] = m.group(0).strip()
    vits = []
    for m in VITOLA.finditer(text):
        nm = m.group(1).strip(" -—–:")
        if re.search(r"wrapper|binder|filler|price|box|cigars|our|the", nm, re.I):
            continue
        vits.append(f"{nm} {m.group(2).replace(' ', '')}x{m.group(3)}")
    if vits:
        spec["vitolas"] = list(dict.fromkeys(vits))[:12]
    return spec


def fetch_page(cfg, url):
    page = fetch(url)
    text = strip_html(page)
    if cfg.get("rest") and len(text) < 1500:   # age gate: try WP REST
        slug = [p for p in urlparse(url).path.split("/") if p][-1]
        try:
            import json
            data = json.loads(fetch(cfg["rest"] + slug))
            if data:
                page = data[0]["content"]["rendered"]
                text = strip_html(page)
        except Exception:
            pass
    return page, text


def run(limit=None, delay=None, brand_key=None):
    cfg = BRANDS[brand_key]
    delay = delay or cfg.get("delay", 2)
    out = []
    urls = line_urls(cfg)
    if limit:
        urls = urls[:limit]
    for u in urls:
        try:
            page, text = fetch_page(cfg, u)
        except Exception as e:  # noqa
            out.append({"brand": cfg["brand"], "name": name_from_url(u), "error": str(e)})
            continue
        md = meta_desc(page)
        note = body_note_sentences(text)
        if re.search(NOTE_WORDS, md, re.I) and md not in note:
            note = md + " " + note
        out.append({"brand": cfg["brand"], "name": name_from_url(u), "vitola": "",
                    "note_text": note.strip(), "specs": parse_specs(text),
                    "source": f"official:{brand_key}"})
        time.sleep(delay)
    return out
