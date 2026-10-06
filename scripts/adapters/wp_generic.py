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
                         skip=r"pledge98|about|contact|shop|retailer|privacy|terms|news|events|home|cart|checkout|account|blog|crm|epc_view|locator|campaign|giveaway|not-found|anniversary|\d{4,}|sample|thank|landing|press|careers|faq|policy|family|story|team", delay=2),
    "alecbradley": dict(brand="Alec Bradley", sitemaps=["https://www.alecbradley.com/sitemap.xml"],
                        pattern=r"https://www\.alecbradley\.com/cigars/[^/]+", delay=2),
    "plasencia": dict(brand="Plasencia", sitemaps=["https://www.plasenciacigars.com/sitemap.xml"],
                      pattern=r"https://www\.plasenciacigars\.com/collections/[^/]+/?", delay=2),
    "joya": dict(brand="Joya de Nicaragua", sitemaps=["https://joyacigars.com/cigars-sitemap.xml"],
                 pattern=r"https://joyacigars\.com/cigars/[^/]+/", skip=r"/es/", delay=2),
    "kristoff": dict(brand="Kristoff", sitemaps=["https://kristoff.com/product-sitemap.xml"],
                     pattern=r"https://kristoff\.com/product/[^/]+/", skip=r"sampler|gift|hat|shirt|cutter|lighter|ashtray|humidor|pack", delay=2),
    "aganorsa": dict(brand="Aganorsa Leaf", sitemaps=["https://aganorsaleaf.com/wp-sitemap-posts-page-1.xml"],
                     pattern=r"https://aganorsaleaf\.com/cigars/[^/]+/", delay=2),
    "espinosa": dict(brand="Espinosa", sitemaps=[], pattern=r"https://espinosacigars\.com/core-lines/[^/]+/",
                     index_url="https://espinosacigars.com/", delay=2),
    "ajfernandez": dict(brand="AJ Fernandez", sitemaps=["https://ajfcigars.com/page-sitemap.xml"],
                        pattern=r"https://ajfcigars\.com/cigars/[^/]+/(?:[^/]+/)?", delay=2,
                        meta_only=True),
}


def line_urls(cfg):
    urls = set(cfg.get("extra_urls", []))
    if cfg.get("index_url"):
        try:
            page = fetch(cfg["index_url"])
            urls |= set(u.rstrip('"\'') for u in re.findall(r'href="(' + cfg["pattern"] + r')"', page))
        except Exception:
            pass
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


def body_note_sentences(text, name=""):
    """Note sentences from the main content only: stop at footer/related-product markers,
    and prefer the region after the first mention of the line name."""
    cut = re.search(r"(related products|you may also like|other cigars|our cigars|explore|footer|all rights reserved|©)", text, re.I)
    if cut and cut.start() > 300:
        text = text[:cut.start()]
    if name:
        key = name.split()[0]
        i = text.lower().find(key.lower())
        if i > 0:
            text = text[i:]
    sents = re.split(r"(?<=[.!?])\s+", text)
    keep = [s for s in sents if re.search(NOTE_WORDS, s, re.I) and 30 < len(s) < 400
            and not re.search(r"cookie|privacy|newsletter|subscribe|copyright|age|21\+|retailer|sign up|shop now", s, re.I)]
    return " ".join(keep[:4])


def parse_specs(text):
    spec = {}
    for m in WBF.finditer(text):
        k = m.group(1).lower()
        if k not in spec:
            spec[k] = m.group(2).strip(" .")
    m = re.search(r"(strength|body|bodied)\s*[:\-–—]?\s*" + STRENGTH, text, re.I) or \
        re.search(STRENGTH + r"\s*(bodied|body|strength)", text, re.I)
    if m:
        spec["strength"] = re.search(STRENGTH, m.group(0), re.I).group(0).strip()
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
    if cfg.get("meta_only"):   # age-gated body: specs/notes only from meta description
        text = meta_desc(page)
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
        note = body_note_sentences(text, name_from_url(u))
        if re.search(NOTE_WORDS, md, re.I) and md not in note:
            note = md + " " + note
        out.append({"brand": cfg["brand"], "name": name_from_url(u), "vitola": "",
                    "note_text": note.strip(), "specs": parse_specs(text),
                    "source": f"official:{brand_key}"})
        time.sleep(delay)
    return out
