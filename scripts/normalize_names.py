"""db/cigars.json 표기 정리.

- 소문자 슬러그에서 온 라인명을 Title Case 로 (de/la/y 같은 접속사·관사는 소문자, 로마숫자·약어는 대문자, "no 2" → "No. 2")
- 라인명 앞에 브랜드명이 중복된 것 제거 (단, "Punch Punch"·"Fonseca No.1" 처럼 원래 이름이 그런 쿠반은 유지)
- 같은 브랜드 안의 중복 라인 병합: 노트 많은 쪽을 남기고, 사라지는 id 는 legacy_ids 에 기록 (사용자 기록 호환)
- 수동 보정표(OVERRIDES) 우선

실행: python3 scripts/normalize_names.py  (→ db/cigars.json 갱신, 변경 내역 출력)
"""
import json
import pathlib
import re
import sys
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parent.parent
DB = ROOT / "db" / "cigars.json"

SMALL = {"de", "la", "las", "los", "del", "y", "e", "el", "of", "the", "and", "by", "a", "en", "con", "para", "du", "des", "di", "da"}
UPPER = {"ii", "iii", "iv", "vi", "vii", "viii", "ix", "xi", "xii", "xiii", "xiv", "xv", "xvi", "xvii", "xviii", "xix", "xx", "xxi", "xxv", "xxx", "itc", "ltd", "llc", "nyc", "gt", "xl", "xxl", "jj", "mf", "lcdh", "cao", "aj", "ep", "fsg", "esv", "jfr", "ct", "dbl", "dbs", "alr",
         "lb1", "c8", "m81", "s84", "usa", "uk", "ny", "la.", "xo", "xxx", "bx", "bxiii", "ss", "sw", "nw", "lfd", "rp", "ad", "rc", "ld", "tx", "mx", "bc", "lgc", "ryj"}
# 특정 브랜드 토큰이 라인명 안에 있을 때 대문자 유지
FIXED = {"cao": "CAO", "aj": "AJ", "jfr": "JFR", "ep": "E.P.", "erh": "E.R.H.", "lcdh": "LCDH", "esv": "ESV", "mf": "MF", "jj": "JJ",
         "h-2k-ct": "H-2K-CT", "r.e.": "R.E.", "re": "R.E.", "lfd": "LFD", "rp": "RP", "lgc": "LGC", "ryj": "RyJ"}

# 수동 보정: id → 새 이름 (검증된 공식 표기)
OVERRIDES = {
    # My Father (myfathercigars.com 2026-10 확인)
    "my-father-my-father": "My Father",
    "my-father-my-father-blue": "Blue",
    "my-father-my-father-la-lealtad": "La Lealtad",
    "my-father-judge": "The Judge",
    "my-father-el-centurion-h-2k-ct": "El Centurion H-2K-CT",
    "my-father-el-centurion": "El Centurion",
    "my-father-don-pepin-garcia-e-r-h": "Don Pepin Garcia E.R.H.",
    "my-father-don-pepin-garcia-serie-jj": "Don Pepin Garcia Serie JJ",
    "my-father-don-pepin-garcia-original": "Don Pepin Garcia Original",
    "my-father-don-pepin-garcia-cuban-classic": "Don Pepin Garcia Cuban Classic",
    "my-father-don-pepin-garcia-blue-label": "Don Pepin Garcia Blue Label",
    "my-father-don-pepin-vintage-edition": "Don Pepin Vintage Edition",
    "my-father-vegas-cubanas": "Don Pepin Garcia Vegas Cubanas",
    "my-father-jaime-garcia-r-e-connecticut": "Jaime Garcia R.E. Connecticut",
    "my-father-jaime-garcia-reserva-especial": "Jaime Garcia Reserva Especial",
    "my-father-tabacos-baez-serie-sf": "Tabacos Baez Serie SF",
    "my-father-la-duena": "La Dueña",
    "my-father-la-antiguedad": "La Antiguedad",
    "my-father-fonseca": "Fonseca",
    "my-father-fonseca-mexico-edition": "Fonseca Mexico Edition",
    "my-father-flor-de-las-antillas": "Flor de las Antillas",
    "my-father-flor-de-las-antillas-maduro": "Flor de las Antillas Maduro",
    "my-father-connecticut": "Connecticut",
    "my-father-la-gran-oferta": "La Gran Oferta",
    "my-father-la-opulencia": "La Opulencia",
    "my-father-la-promesa": "La Promesa",
    "my-father-le-bijou-1922": "Le Bijou 1922",
    "my-father-limited-edition": "Limited Edition",
    # 브랜드명 중복 슬러그 (비쿠반)
    "aganorsa-leaf-aganorsa-leaf-arsenio": "Arsenio",
    "aganorsa-leaf-aganorsa-leaf-signature-corojo": "Signature Corojo",
    "aganorsa-leaf-aganorsa-leaf-supreme-leaf": "Supreme Leaf",
    "espinosa-crema": "Crema",
    "espinosa-habano": "Habano",
    "acid-20": "20",
    "acid-frenchies": "Frenchies",
    "baccarat-natural": "Natural",
    "cao-60": "60",
    "cusano-connecticut": "Connecticut",
    "cusano-maduro": "Maduro",
    "excalibur-black": "Black",
    "lars-tetens-lars-tetens-phat": "Phat Cigars",
    "padron-series": "Series",
    "silencio-serie-m-reserva-roja": "Serie M Reserva Roja",
    "zino-red-davidoff": "Red by Davidoff",
    "drew-estate-liga-privada-liga-privada-liga-10": "Liga Privada Liga 10",  # 공식: Liga Privada 10 Year Aniversario, 통칭 "Liga 10"
    "aj-fernandez-dias-de-gloria-brazil": "Dias de Gloria Brazil",
    # 브랜드 자체가 라인인 것 (이름 = 브랜드명 유지; 앱에서 중복 표시 안 함)
    "brioso": "Brioso", "buffalo-trace-buffalo-trace": "Buffalo Trace", "chillin-moose-chillin-moose": "Chillin' Moose", "diesel": "Diesel",
    "don-diego-don-diego": "Don Diego", "el-baton-el-baton": "El Baton", "el-rico-habano-el-rico-habano": "El Rico Habano", "excalibur": "Excalibur",
    "henry-clay-henry-clay": "Henry Clay", "los-statos-deluxe-los-statos-deluxe": "Los Statos Deluxe", "made-man-made-man": "Made Man", "griffins": "The Griffins",
}

# 병합: 사라지는 id → 남는 id
MERGES = {
    "my-father-my-father-mf-judge": "my-father-judge",          # 공식 "MF The Judge" = The Judge
    "my-father-blue-honduras": "my-father-my-father-blue",       # 공식 "My Father – Blue" (온두라스)
    "my-father-don-pepin-garcia-vegas-cubanas": "my-father-vegas-cubanas",
}
DELETE = {"my-father-samplers-and-humidified-bags", "aj-fernandez-dias-de-gloria-dias-de-gloria1"}  # 시가 아님 / 슬러그 깨진 빈 항목


def title_token(tok, first):
    low = tok.lower()
    if low in FIXED:
        return FIXED[low]
    if re.fullmatch(r"no\.?", low):
        return "No."
    if low in UPPER:
        return tok.upper()
    if not first and low in SMALL:
        return low
    if re.fullmatch(r"\d+(st|nd|rd|th)", low):
        return low
    # 숫자+문자 조합(20th, c8, m81)은 그대로/대문자
    if re.search(r"\d", low) and re.search(r"[a-z]", low) and len(low) <= 4:
        return low.upper()
    if "-" in low:
        return "-".join(title_token(p, True) for p in low.split("-"))
    if "'" in low:
        a, b = low.split("'", 1)
        return a[:1].upper() + a[1:] + "'" + b
    return low[:1].upper() + low[1:]


def collapse_repeat(name):
    """'herrera esteli herrera esteli brazilian' → 'herrera esteli brazilian' (슬러그에 서브브랜드가 두 번 들어간 것)"""
    toks = name.split()
    for n in (3, 2, 1):
        if len(toks) >= 2 * n and [t.lower() for t in toks[:n]] == [t.lower() for t in toks[n:2 * n]]:
            return " ".join(toks[n:])
    return name


def titlecase(name):
    toks = name.split()
    out = [title_token(t, i == 0) for i, t in enumerate(toks)]
    s = " ".join(out)
    s = re.sub(r"\bNo\. ?(\d)", r"No. \1", s)
    return s


def strip_brand(brand, name):
    b = brand.lower()
    n = name.lower()
    if n.startswith(b + " ") and len(n) > len(b) + 1:
        return name[len(brand) + 1:]
    return name


def main():
    db = json.load(open(DB, encoding="utf-8"))
    changes = []

    # 1) 병합
    for old, new in MERGES.items():
        if old not in db or new not in db:
            continue
        a, b = db[old], db[new]
        for k in ("official", "review"):
            b["notes"][k] = list(dict.fromkeys(b["notes"].get(k, []) + a["notes"].get(k, [])))
        b["note_sources"] = b.get("note_sources", []) + a.get("note_sources", [])
        b["vitolas"] = list(dict.fromkeys((b.get("vitolas") or []) + (a.get("vitolas") or [])))
        if not b.get("specs") and a.get("specs"):
            b["specs"] = a["specs"]
        b.setdefault("aliases", [])
        if a["name"] not in b["aliases"] and a["name"].lower() != b["name"].lower():
            b["aliases"].append(a["name"])
        b.setdefault("legacy_ids", []).append(old)
        del db[old]
        changes.append(f"MERGE {old} → {new}")
    for old in DELETE:
        if old in db:
            del db[old]
            changes.append(f"DELETE {old}")

    # 2) 이름 정리
    for cid, c in db.items():
        old = c["name"]
        if cid in OVERRIDES:
            new = OVERRIDES[cid]
        else:
            new = old
            cuban = bool((c.get("seed") or {}).get("cuban"))
            if not cuban:
                new = strip_brand(c["brand"], new)
            if new[:1].islower():
                new = titlecase(collapse_repeat(new))
        new = re.sub(r"\s+", " ", new).strip()
        if new != old:
            c.setdefault("aliases", [])
            if old.lower() != new.lower() and old not in c["aliases"]:
                c["aliases"].append(old)  # 검색 호환
            c["name"] = new
            changes.append(f"RENAME {cid}: {old!r} → {new!r}")

    # 3) 정리 후 같은 브랜드·같은 이름이 남으면 병합 (노트 많은 쪽, 같으면 id 짧은 쪽을 남김)
    def merge(old, new):
        a, b = db[old], db[new]
        for k in ("official", "review"):
            b["notes"][k] = list(dict.fromkeys(b["notes"].get(k, []) + a["notes"].get(k, [])))
        b["note_sources"] = b.get("note_sources", []) + a.get("note_sources", [])
        b["vitolas"] = list(dict.fromkeys((b.get("vitolas") or []) + (a.get("vitolas") or [])))
        if not b.get("specs") and a.get("specs"):
            b["specs"] = a["specs"]
        if not b.get("seed") and a.get("seed"):
            b["seed"] = a["seed"]
        b.setdefault("aliases", [])
        for al in a.get("aliases", []):
            if al not in b["aliases"] and al.lower() != b["name"].lower():
                b["aliases"].append(al)
        b.setdefault("legacy_ids", [])
        b["legacy_ids"] += [old] + a.get("legacy_ids", [])
        del db[old]
        changes.append(f"MERGE {old} → {new}")

    seen = defaultdict(list)
    for cid, c in db.items():
        seen[(c["brand"].lower(), c["name"].lower())].append(cid)
    for k, ids in seen.items():
        if len(ids) < 2:
            continue
        def score(cid):
            c = db[cid]
            return (len(c["notes"].get("official", [])) + len(c["notes"].get("review", [])), -len(cid))
        ids.sort(key=score, reverse=True)
        for old in ids[1:]:
            merge(old, ids[0])

    json.dump(db, open(DB, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("\n".join(changes))
    print(f"-- {len(changes)} changes, {len(db)} cigars", file=sys.stderr)


if __name__ == "__main__":
    main()
