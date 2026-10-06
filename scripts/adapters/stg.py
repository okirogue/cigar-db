"""Official-note adapter: cigarworld.com (Scandinavian Tobacco Group's brand hub).

Covers CAO, Macanudo, Punch, Cohiba (US), La Gloria Cubana, Partagas (US), Hoyo (US),
Excalibur, Montecristo (US, STG-distributed), H. Upmann (US), Diesel, Room101, etc.
Each product page has a "Tasting Notes" keyword list, Body 1-5, and W/B/F headings.
Source: official:stg
"""
import re, time, html
from urllib.parse import urlparse
from .base import fetch, strip_html

SITEMAP = "https://www.cigarworld.com/sitemap.xml/sitemap/Cw-Cigars-Objects-Product/1"
BRAND_NAMES = {
    "cao": "CAO", "macanudo": "Macanudo", "punch": "Punch", "cohiba": "Cohiba", "la-gloria-cubana": "La Gloria Cubana",
    "partagas": "Partagas", "hoyo-de-monterrey": "Hoyo de Monterrey", "excalibur": "Excalibur", "montecristo": "Montecristo",
    "h-upmann": "H. Upmann", "diesel": "Diesel", "room101": "Room101", "el-rey-del-mundo": "El Rey del Mundo",
    "alec-bradley": "Alec Bradley", "joya-de-nicaragua": "Joya de Nicaragua", "bolivar": "Bolivar", "sancho-panza": "Sancho Panza",
    "don-tomas": "Don Tomas", "toraño": "Torano", "torano": "Torano", "chateau-real": "Chateau Real", "trinidad": "Trinidad",
    "helix": "Helix", "cuban-rounds": "Cuban Rounds", "quorum": "Quorum", "macanudo-m": "Macanudo",
}
CUBAN_HOMONYMS = {"cohiba", "partagas", "hoyo-de-monterrey", "montecristo", "h-upmann", "punch", "bolivar",
                  "la-gloria-cubana", "el-rey-del-mundo", "sancho-panza", "trinidad", "romeo-y-julieta"}
SKIP = re.compile(r"sampler|gift|limited|anniversary-\d{2,}th|-le-|\bltd\b|edicion|box-of|humidor", re.I)
BODY_WORDS = {1: "mild", 2: "mild to medium", 3: "medium", 4: "medium to full", 5: "full"}


def product_urls():
    xml = fetch(SITEMAP)
    urls = re.findall(r"<loc>(https://www\.cigarworld\.com/cigars/[^/]+/[^/<]+/)</loc>", xml)
    return sorted(set(u for u in urls if not SKIP.search(u)))


def section(text, heading):
    m = re.search(rf"\b{heading}\b\s*(.*?)(?=\b(Tasting Notes|Body|Wrapper|Binder|Filler|Strength|Sizes|Vitolas|Pairings?|Where to Buy|Find a Retailer|Reviews?)\b|$)", text, re.I | re.S)
    return m.group(1).strip(" :-") if m else ""


def parse(page, url):
    parts = [p for p in urlparse(url).path.split("/") if p]
    bslug, pslug = parts[1], parts[2]
    brand = BRAND_NAMES.get(bslug, bslug.replace("-", " ").title())
    if bslug in CUBAN_HOMONYMS:   # US (non-Cuban) versions of Cuban marcas: keep separate from Habanos entries
        brand = brand + " (US)"
    name = pslug.replace("-", " ")
    text = strip_html(page)
    notes = section(text, "Tasting Notes")
    notes = re.sub(r"\{\{.*?\}\}", "", notes)[:200]
    spec = {}
    for k in ("Wrapper", "Binder", "Filler"):
        v = section(text, k)
        if v and len(v) < 80:
            spec[k.lower()] = v
    mb = re.search(r"setBodyKeyword\((\d)\)", page)
    if mb:
        spec["strength"] = BODY_WORDS.get(int(mb.group(1)), "")
    md = re.search(r'<meta\s+name="description"\s+content="([^"]+)"', page, re.I)
    desc = html.unescape(md.group(1)) if md else ""
    return brand, name, notes, desc, spec


def run(limit=None, delay=2.0):
    out = []
    urls = product_urls()
    if limit:
        urls = urls[:limit]
    for u in urls:
        try:
            page = fetch(u)
        except Exception as e:  # noqa
            out.append({"brand": "", "name": u, "error": str(e)}); continue
        brand, name, notes, desc, spec = parse(page, u)
        out.append({"brand": brand, "name": name, "vitola": "",
                    "note_text": (notes + ". " + desc).strip(". "), "specs": spec, "source": "official:stg"})
        time.sleep(delay)
    return out
