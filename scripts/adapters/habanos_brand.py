"""Official adapter (fallback): habanos.com brand pages → brand-level description + line strength.

habanos.com has no per-vitola tasting text we can reach (the catalogue is a JS app), but each brand has an
"Habanos Brands Academia" page in English with a history/character paragraph block and a Strength section
("Strength / Strenght:" followed by one value, or "Línea X: value" pairs).

For every DB entry that is Cuban and still has no note text we emit one row per entry:
  note_text  = the brand description (shared across the brand's lines, so collect.py gets tags_off=True:
               brand-level prose must NOT become per-line flavor tags)
  specs.strength = the line's strength when the page lists one (matched by line keyword) or the brand's single value
Source id: official:habanos (brand_level). URL kept.
"""
import json, re, time, html, unicodedata
from pathlib import Path
from .base import fetch

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "db" / "cigars.json"
BASE = "https://www.habanos.com/en/the-world-of-the-habano/the-habanos-brands-academia/"

# 브랜드 → 페이지 슬러그 (habanos.com)
SLUGS = {
    "bolivar": "bolivar", "cohiba": "cohiba", "cuaba": "cuaba", "diplomaticos": "diplomaticos", "el rey del mundo": "el-rey-del-mundo",
    "fonseca": "fonseca", "h. upmann": "h-upmann", "h upmann": "h-upmann", "hoyo de monterrey": "hoyo-de-monterrey", "jose l. piedra": "jose-l-piedra",
    "juan lopez": "juan-lopez", "la flor de cano": "la-flor-de-cano", "la gloria cubana": "la-gloria-cubana", "montecristo": "montecristo",
    "partagas": "partagas", "por larranaga": "por-larranaga", "punch": "punch", "quai d'orsay": "quai-dorsay", "quintero": "quintero",
    "rafael gonzalez": "rafael-gonzalez", "ramon allones": "ramon-allones", "romeo y julieta": "romeo-y-julieta", "saint luis rey": "saint-luis-rey",
    "san cristobal de la habana": "san-cristobal-de-la-habana", "sancho panza": "sancho-panza", "trinidad": "trinidad", "vegas robaina": "vegas-robaina",
    "vegueros": "vegueros",
}

STRENGTH_MAP = {
    "mild": "mild", "light": "mild", "suave": "mild", "ligero": "mild",
    "mild to medium": "mild to medium", "light to medium": "mild to medium", "suave a medio": "mild to medium",
    "medium": "medium", "medio": "medium",
    "medium to full": "medium to full", "medium to strong": "medium to full", "medio a fuerte": "medium to full",
    "full": "full", "strong": "full", "fuerte": "full",
}

# 라인 키워드 → 페이지의 "Línea X" 라벨 (브랜드별)
LINE_KEYS = {
    "cohiba": [("behike", "behike"), ("maduro 5", "maduro 5"), ("siglo", "1492"), ("medio siglo", "1492")],
    "montecristo": [("open", "open")],
    "partagas": [("serie", "serie")],
    "romeo y julieta": [("linea de oro", "oro"), ("churchills", "clasica")],
    "h. upmann": [("magnum", "magnum")],
}


def norm(s):
    s = unicodedata.normalize("NFKD", s)
    return "".join(c for c in s if not unicodedata.combining(c)).lower().strip()


def to_text(page):
    t = re.sub(r"<(script|style)[^>]*>.*?</\1>", " ", page, flags=re.S | re.I)
    t = html.unescape(re.sub(r"<[^>]+>", "\n", t))
    t = re.sub(r"[ \t]+", " ", t)
    return re.sub(r"\n\s*\n+", "\n", t)


def parse(page):
    """→ (description, {line_label_norm: strength}, default_strength)"""
    t = to_text(page)
    i = t.find("Habanos Brands")
    j = t.find("Authenticity Check", i)
    seg = t[i:j] if i >= 0 and j > i else t
    lines = [ln.strip() for ln in seg.split("\n") if ln.strip()]
    # 설명: "<Brand> Brand" 다음부터 Strength 전까지의 긴 문장들 (이미지 캡션 같은 짧은 줄 제외)
    try:
        k = next(n for n, ln in enumerate(lines) if ln.lower().endswith(" brand"))
    except StopIteration:
        k = 0
    s_idx = next((n for n, ln in enumerate(lines) if re.fullmatch(r"streng?h?th?:?|strength:?|strenght:?", ln.lower().replace(" ", ""))), len(lines))
    desc = " ".join(ln for ln in lines[k + 1:s_idx] if len(ln) > 60)
    desc = re.sub(r"\s+", " ", desc).strip()
    # 강도
    strengths, default = {}, None
    tail = lines[s_idx + 1:] if s_idx < len(lines) else []
    n = 0
    while n < len(tail):
        ln = tail[n]
        m = re.match(r"(?:l[ií]nea\s+)?(.+?):\s*(.*)$", ln, flags=re.I)
        if m:
            label, val = norm(m.group(1)), m.group(2).strip()
            if not val and n + 1 < len(tail):
                n += 1
                val = tail[n].strip()
            v = STRENGTH_MAP.get(norm(val))
            if v:
                strengths[label.replace("linea ", "")] = v
        else:
            v = STRENGTH_MAP.get(norm(ln))
            if v and default is None:
                default = v
            elif not v:
                break
        n += 1
    return desc, strengths, default


def targets():
    db = json.loads(DB.read_text(encoding="utf-8"))
    out = {}
    for sid, e in db.items():
        if not (e.get("seed") or {}).get("cuban"):
            continue
        if any(s.get("text") for s in e.get("note_sources", [])):
            continue
        if any(s.get("source") == "official:habanos" for s in e.get("note_sources", [])):
            continue
        out.setdefault(norm(e["brand"]), []).append((e["brand"], e["name"], sid, (e.get("specs") or {}).get("strength")))
    return out


def line_strength(brand_norm, name, strengths, default):
    nm = norm(name)
    for kw, label in LINE_KEYS.get(brand_norm, []):
        if kw in nm:
            for lab, v in strengths.items():
                if label in lab:
                    return v
    # 라인별 표가 있는데 매치가 없으면 '클래식/기본' 라인으로
    for lab, v in strengths.items():
        if any(x in lab for x in ("clasica", "classic", "linea clasica")):
            return v
    if default:
        return default
    if len(strengths) == 1:
        return next(iter(strengths.values()))
    return None


def run(limit=None, offset=0, delay=2.0):
    out = []
    tg = targets()
    brands = sorted(tg)[offset:]
    if limit:
        brands = brands[:limit]
    for b in brands:
        slug = SLUGS.get(b) or SLUGS.get(b.replace(".", "")) or b.replace(" ", "-").replace(".", "").replace("'", "")
        url = f"{BASE}{slug}-brand/"
        try:
            desc, strengths, default = parse(fetch(url))
        except Exception as e:  # noqa
            for brand, name, sid, _ in tg[b]:
                out.append({"brand": brand, "name": name, "error": f"{url}: {e}"})
            time.sleep(delay)
            continue
        if len(desc) < 120:
            for brand, name, sid, _ in tg[b]:
                out.append({"brand": brand, "name": name, "error": f"{url}: no description"})
            time.sleep(delay)
            continue
        for brand, name, sid, cur in tg[b]:
            st = line_strength(b, name, strengths, default)
            specs = {"strength": st} if st and not cur else {}
            out.append({"brand": brand, "name": name, "vitola": "", "note_text": desc[:1800], "specs": specs, "source": "official:habanos",
                        "review_url": url, "review_title": f"Habanos S.A. — {brand} brand", "tags_off": True, "brand_level": True})
        time.sleep(delay)
    return out
