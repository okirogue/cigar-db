"""Official-note adapter: Davidoff (us.davidoffgeneva.com, the brand's own US store).

The site exposes one page per vitola at /product/davidoff-<line>-<vitola>/.
We read the sitemap, keep /product/davidoff-* pages, fetch each, and take the
tasting-note paragraph. The store URL is NOT stored in the DB (retail link);
source is recorded as "official:davidoff".
"""
import re, time, html
from urllib.parse import urlparse
from .base import fetch, strip_html

BRAND = "Davidoff"
SITEMAP = "https://us.davidoffgeneva.com/sitemap.xml"
SKIP = re.compile(r"limited-edition|sampler|gift|assortment|humidor|cutter|lighter|ashtray|accessor|pipe|flask|glass|bucket|pouch|set\b|selection|collection|band\b|promo|chefs-edition|year-of-the|exclusive|boutique|small-batch|oro-blanco|royal-release|davpipe|cigarillo|demi-tasse|real-especial|ritual|collectors|cleaner|mixture|tobacco", re.I)


def product_urls():
    xml = fetch(SITEMAP)
    urls = re.findall(r"<loc>(https://us\.davidoffgeneva\.com/product/davidoff-[^<]+)</loc>", xml)
    return [u for u in urls if not SKIP.search(u)]


def parse_name(url):
    slug = urlparse(url).path.strip("/").split("/")[-1]
    slug = re.sub(r"^davidoff-", "", slug)
    slug = re.sub(r"^primeros-by-davidoff-", "primeros-", slug)
    words = slug.replace("-", " ")
    return words


def note_text(page_html):
    # 1) meta description carries the tasting sentence on this store
    m = re.search(r'<meta\s+name="description"\s+content="([^"]+)"', page_html, re.I)
    if m and len(m.group(1)) > 40:
        return m.group(1)
    text = strip_html(page_html)
    m = re.search(r"([^.]{0,200}\b(notes?|aromas?|flavou?rs?|palate|aftertaste|taste)\b[^.]{0,300}\.)", text, re.I)
    return m.group(1).strip() if m else ""


def run(limit=None, delay=1.5):
    out = []
    urls = product_urls()
    if limit:
        urls = urls[:limit]
    for u in urls:
        try:
            page = fetch(u)
        except Exception as e:  # noqa
            out.append({"brand": BRAND, "name": parse_name(u), "error": str(e)})
            continue
        out.append({
            "brand": BRAND,
            "name": parse_name(u),
            "note_text": html.unescape(note_text(page)),
            "source": "official:davidoff",
        })
        time.sleep(delay)
    return out
