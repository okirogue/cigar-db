"""Official-note adapter: altadisusa.com (Altadis U.S.A. brand hub).

Covers the US (non-Cuban) Montecristo, Romeo y Julieta, H. Upmann, Trinidad, Saint Luis Rey,
Henry Clay, Aging Room, VegaFina, Gispert, Don Diego, Casa de Garcia, Omar Ortez, Onyx, Te-Amo…
Each line page: description paragraph(s) with flavor words, "Available in Sizes" list (ring x length),
and a spec block: origin / wrapper / binder / filler / strength (1-5).
Source: official:altadis
"""
import re, time, html
from urllib.parse import urlparse
from .base import fetch, strip_html

SITEMAP = "https://www.altadisusa.com/sitemap.xml"
LINE = re.compile(r"https://www\.altadisusa\.com/cigars/([^/]+)/([^/]+)/$")
BRAND_NAMES = {
    "montecristo": "Montecristo", "romeo-y-julieta": "Romeo y Julieta", "h-upmann": "H. Upmann",
    "trinidad-santiago": "Trinidad", "saint-luis-rey": "Saint Luis Rey", "henry-clay": "Henry Clay",
    "aging-room": "Aging Room", "vegafina": "VegaFina", "gispert": "Gispert", "don-diego": "Don Diego",
    "casa-de-garcia": "Casa de Garcia", "omar-ortez": "Omar Ortez", "onyx": "Onyx", "te-amo": "Te-Amo",
    "las-cabrillas": "Las Cabrillas", "primo-del-rey": "Primo del Rey",
}
STRENGTH_WORDS = {1: "mild", 2: "mild to medium", 3: "medium", 4: "medium to full", 5: "full"}
SIZE = re.compile(r"\|([^|]{2,40}?):\|(\d{2})\s*x\s*(\d(?:\s?\d/\d)?)")


def product_urls():
    xml = fetch(SITEMAP)
    urls = sorted(set(u for u in re.findall(r"<loc>([^<]+)</loc>", xml) if LINE.fullmatch(u)))
    return urls


def parse(page, url):
    m = LINE.fullmatch(url)
    bslug, lslug = m.group(1), m.group(2)
    brand = BRAND_NAMES.get(bslug, bslug.replace("-", " ").title())
    name = lslug
    if name.startswith(bslug + "-"):
        name = name[len(bslug) + 1:]
    name = name.replace("-", " ")
    t = re.sub(r"<(script|style|noscript)[^>]*>.*?</\1>", " ", page, flags=re.S | re.I)
    t = re.sub(r"<[^>]+>", "|", t)
    t = html.unescape(re.sub(r"\s+", " ", t))
    t = re.sub(r"(\|\s*)+", "|", t)

    specs = {}
    for key in ("origin", "wrapper", "binder", "filler"):
        mm = re.search(r"\|%s\|([^|]{2,80})\|" % key, t, re.I)
        if mm:
            specs["country" if key == "origin" else key] = mm.group(1).strip()
    mm = re.search(r"\|strength\|(\d)\|", t, re.I)
    if mm:
        specs["strength"] = STRENGTH_WORDS.get(int(mm.group(1)), "medium")
    sizes = []
    seg = t
    i = t.find("Available in Sizes")
    if i >= 0:
        seg = t[i:i + 1500]
    for s in SIZE.finditer(seg):
        nm, ring, length = s.group(1).strip(), s.group(2), s.group(3).strip()
        sizes.append(f"{nm} {length}x{ring}")
    if sizes:
        specs["vitolas"] = list(dict.fromkeys(sizes))[:12]

    # description: segments between the title and "Available in Sizes" + the paragraph after the spec block
    desc = []
    md = re.search(r'<meta\s+(?:name|property)="(?:description|og:description)"\s+content="([^"]+)"', page, re.I)
    if md:
        desc.append(html.unescape(md.group(1)))
    parts = [p.strip() for p in t.split("|") if len(p.strip()) > 60]
    for p in parts:
        if re.search(r"privacy|cookie|newsletter|warning|all rights reserved|skip to content", p, re.I):
            continue
        if p not in desc:
            desc.append(p)
    note = " ".join(desc[:4])
    return {"brand": brand, "name": name, "vitola": "", "note_text": note, "specs": specs, "source": "official:altadis"}


def run(limit=None, delay=2.0):
    out = []
    urls = product_urls()
    if limit:
        urls = urls[:limit]
    for u in urls:
        try:
            page = fetch(u)
            out.append(parse(page, u))
        except Exception as e:  # noqa
            m = LINE.fullmatch(u)
            out.append({"brand": BRAND_NAMES.get(m.group(1), m.group(1)) if m else "Altadis", "name": urlparse(u).path.rstrip("/").rsplit("/", 1)[-1].replace("-", " "), "error": str(e)})
        time.sleep(delay)
    return out
