"""취미생활 저널(hobby/index.html) + inventory.json → MyHumidor 가져오기 JSON.

실행: python3 scripts/journal_to_app.py <hobby_dir> <out.json>
"""
import html
import json
import re
import sys

HOBBY, OUT = sys.argv[1], sys.argv[2]
s = open(f"{HOBBY}/index.html", encoding="utf-8").read()
inv = json.load(open(f"{HOBBY}/inventory.json", encoding="utf-8"))
strip = lambda t: html.unescape(re.sub(r"<[^>]+>", "", t)).strip()

# 저널 노트 라벨 → 앱 태그 id
LABEL = {
    "가죽": "leather", "건초": "hay", "견과": "nuts", "꿀": "honey", "미네랄": "mineral", "바닐라": "vanilla",
    "백후추": "white_pepper", "시더": "cedar", "카라멜": "caramel", "캐러멜": "caramel", "커피": "coffee", "코코아": "cocoa",
    "크림": "cream", "플로럴": "floral", "후추": "pepper", "흙": "earth",
    "고소": "nuts", "고소함": "nuts", "고소 (기름진)": "nuts", "고소·견과": "nuts", "고소·묵직": "nuts",
    "단맛": "sweet", "단맛·꿀": "honey", "밀크초콜릿": "cocoa", "초콜릿": "dark_chocolate", "초콜릿·카라멜": "cocoa",
    "빵": "bread", "토스트": "bread", "토스트·빵": "bread", "토스트·태우는 향": "toast", "탄내": "toast", "로스티": "toast",
    "우유 크림": "cream", "크림 (질감)": "cream", "커피 (라이트 로스팅)": "coffee", "커피 (에스프레소)": "espresso",
    "나무 (마른)": "woody", "시더·나무": "cedar", "히코리": "woody", "감초": "spice", "쓴맛": None,
}
tags = json.load(open("app/assets/tags.json", encoding="utf-8"))
valid = {t["id"] for g in tags["groups"] for t in g["tags"]}
for k, v in LABEL.items():
    assert v is None or v in valid, (k, v)

# 세션 → DB id, 비톨라, 점수(명시 없으면 추정), 장소
META = {
    1: ("padron-natural", "Padrón 2000 Natural", "2000", 80, "역삼 시가브로"),
    2: ("rocky-patel-vintage-1990", "Rocky Patel Vintage 1990", "Junior", 74, "역삼 시가브로"),
    3: ("oliva-serie-g", "Oliva Serie G", "Toro", 78, "역삼 시가브로"),
    4: ("davidoff-signature", "Davidoff Signature", "No.2", 80, "레솔베르"),
    5: ("diamond-crown-maduro", "Diamond Crown Maduro", "Robusto No.5", 85, "차량"),
    6: ("plasencia-alma-del-cielo", "Plasencia Alma del Cielo", "Robusto", 78, "야외"),
    7: ("oliva-serie-g", "Oliva Serie G", "Special G", 62, "야외"),
    8: ("oliva-connecticut-reserve", "Oliva Connecticut Reserve", "Robusto", 70, "야외"),
    9: ("custom:davidoff-primeros-maduro-nicaragua", "Davidoff Primeros Maduro Nicaragua", "Petit Panatela", 80, "야외"),
    10: ("custom:arturo-fuente-chateau-fuente-royal-salute-maduro", "Arturo Fuente Chateau Fuente Royal Salute Maduro", "Double Corona", 74, "야외"),
    11: ("davidoff-yamasa", "Davidoff Yamasa", "Petit Churchill", 66, "차량"),
    12: ("montecristo-crafted-aj-fernandez", "Montecristo Crafted by AJ Fernandez", "Toro", 82, "야외"),
    13: ("avo-heritage", "AVO Heritage", "Robusto", 78, "야외"),
    14: ("romeo-y-julieta-romeo-no-1", "Romeo y Julieta Romeo No.1", "Tubos", 84, "발리 우붓"),
    15: ("montecristo-no-4", "Montecristo No.4", None, 73, "발리 우붓"),
    16: ("custom:taru-martani-robusto", "Taru Martani Robusto Special Edition", "Robusto", 60, "발리 우붓"),
    17: ("cohiba-siglo-ii", "Cohiba Siglo II", None, 83, "발리 우붓"),
    18: ("custom:sultan-vintage-robusto", "Sultan Vintage Robusto", "Robusto", 63, "발리 우붓"),
    19: ("custom:dos-hermanos-corona", "Dos Hermanos Corona", "Corona", 68, "발리 누사두아"),
    20: ("custom:dos-hermanos-maduro-robusto", "Dos Hermanos Maduro Robusto", "Robusto", 65, "발리 누사두아"),
    21: ("macanudo-inspirado-orange", "Macanudo Inspirado Orange", "Robusto", 75, "발리 누사두아"),
    22: ("cao-pilon", "CAO Pilón", "Robusto", 78, "발리 누사두아"),
    23: ("custom:don-agusto-tubos", "Don Agusto Tubos", "Tubos", 71, "발리 누사두아"),
    24: ("rocky-patel-emerald", "Rocky Patel Emerald", "Robusto", 81, "서울 야외"),
    25: ("davidoff-primeros-classic", "Davidoff Primeros Classic", "Petit Panatela", 78, "서울 야외"),
}
EXPLICIT = {13, 20, 21, 22, 23, 24, 25}  # 저널/재고에 점수가 적혀 있는 세션
FALLBACK_DATE = {1: "2026-09-02", 2: "2026-09-03"}


def ymd(txt):
    m = re.search(r"(\d{4})\.\s*(\d{1,2})\.\s*(\d{1,2})\.", txt)
    return f"{m.group(1)}-{int(m.group(2)):02d}-{int(m.group(3)):02d}" if m else None


def pick_phase(phases, keys):
    for h, p in phases:
        if any(k in h for k in keys):
            return f"{h}\n{p}"
    return None


logs = []
for m in re.finditer(r'<section id="d-c(\d+)" class="detail hidden">(.*?)</section>', s, re.S):
    no, body = int(m.group(1)), m.group(2)
    cid, name, vitola, score, place = META[no]
    meta = strip((re.search(r'class="d-meta">(.*?)</div>', body, re.S) or re.search(r"$", "")).group(1) if re.search(r'class="d-meta">', body) else "")
    tag_ids = []
    for cls, li in re.findall(r'<li( class="on")?><i></i>(.*?)</li>', body, re.S):
        if not cls:
            continue  # 체크 안 됨 / 긴가민가(half)는 제외
        lab = strip(re.sub(r"<small>.*?</small>", "", li, flags=re.S))
        t = LABEL.get(lab)
        if t and t not in tag_ids:
            tag_ids.append(t)
    # 세션 분할: 첫 경험 후기 + 추가 발견사항
    parts = re.split(r'(<div class="sec-h">.*?</div>)', body, flags=re.S)
    sections = []
    if len(parts) > 1:
        for i in range(1, len(parts), 2):
            head = strip(parts[i])
            sections.append((head, parts[i + 1]))
    else:
        sections.append(("첫 경험 후기", body))
    pairing = None
    for k in ["제로사이다", "제로콜라", "커피", "빈땅", "아이스 아메리카노", "위스키"]:
        if k in meta:
            pairing = k
            break
    for idx, (head, sec) in enumerate(sections):
        date = ymd(head) or ymd(meta) or FALLBACK_DATE.get(no)
        phases = [(strip(a), strip(b)) for a, b in re.findall(r'<div class="phase">(.*?)</div>\s*(?:<div class="quote">.*?</div>\s*)*<p>(.*?)</p>', sec, re.S)]
        if not phases and idx == 0:
            phases = [(strip(a), strip(b)) for a, b in re.findall(r'<div class="phase">(.*?)</div>\s*(?:<div class="quote">.*?</div>\s*)*<p>(.*?)</p>', body, re.S)]
        start = pick_phase(phases, ["초반", "착화", "첫인상", "시작"]) or (f"{phases[0][0]}\n{phases[0][1]}" if phases else None)
        mid = pick_phase(phases, ["중반", "1/10", "1/5", "1/3"]) or (f"{phases[len(phases)//2][0]}\n{phases[len(phases)//2][1]}" if len(phases) > 2 else None)
        end = pick_phase(phases, ["후반", "마무리", "총평", "절반", "종료"]) or (f"{phases[-1][0]}\n{phases[-1][1]}" if len(phases) > 1 else None)
        lesson = re.search(r'class="lesson">(.*?)</div>', sec, re.S)
        if lesson and end:
            end += "\n\n" + strip(lesson.group(1))
        note = "" if no in EXPLICIT else "[점수는 저널 총평 기준 자동 추정 — 수정해 주세요] "
        logs.append({
            "cigar_id": cid, "cigar_name": name, "vitola": vitola, "date": date, "score": score,
            "tags": tag_ids, "note_start": start, "note_mid": mid, "note_end": (note + end) if end else (note or None),
            "place": place, "pairing": pairing, "journal_no": no, "session": head,
        })

logs.sort(key=lambda l: (l["date"] or "", l["journal_no"]))

# 재고: inventory.json → 아도리니 노바라 L
INV = {
    "monte-aj-toro": ("montecristo-crafted-aj-fernandez", "Montecristo Crafted by AJ Fernandez", "Toro", 8400),
    "avo-heritage": ("avo-heritage", "AVO Heritage", "Robusto", 7800),
    "oliva-v-figurado": ("oliva-serie-v", "Oliva Serie V", "Special Figurado", 19300),
    "primeros-classic": ("davidoff-primeros-classic", "Davidoff Primeros Classic", "Petit Panatela (틴)", 7000),
    "rp-emerald": ("rocky-patel-emerald", "Rocky Patel Emerald", "Robusto", 12900),
    "dc-robusto5-maduro": ("diamond-crown-maduro", "Diamond Crown Maduro", "Robusto No.5", 16200),
    "romeo-no1-tubos": ("romeo-y-julieta-romeo-no-1", "Romeo y Julieta Romeo No.1", "Tubos", 41000),
    "punch-coronations": ("punch-coronations", "Punch Coronations", "Tubos", 37800),
    "macanudo-orange": ("macanudo-inspirado-orange", "Macanudo Inspirado Orange", "Robusto", 16500),
    "cao-pilon": ("cao-pilon", "CAO Pilón", "Robusto", 19000),
    "dos-hermanos-maduro": ("custom:dos-hermanos-maduro-robusto", "Dos Hermanos Maduro Robusto", "Robusto", 15200),
    "chateau-fuente-rsm": ("custom:arturo-fuente-chateau-fuente-royal-salute-maduro", "Arturo Fuente Chateau Fuente Royal Salute Maduro", "Double Corona", 8500),
}
stock = []
for it in inv["items"]:
    if it["qty"] <= 0:
        continue
    cid, name, vit, price = INV[it["id"]]
    stock.append({"humidor": "아도리니 노바라 L", "cigar_id": cid, "cigar_name": name, "vitola": vit, "qty": it["qty"], "price_per_stick": price, "added_date": it["date"]})

out = {"version": 1, "exported": "2026-10-07", "source": "취미생활 저널", "humidors": ["아도리니 노바라 L"], "stock": stock, "logs": logs}
json.dump(out, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(f"logs {len(logs)} · stock {len(stock)} rows / {sum(x['qty'] for x in stock)} sticks → {OUT}")
for l in logs:
    print(l["date"], f"No.{l['journal_no']:>2}", l["cigar_name"][:34].ljust(34), l["score"], ",".join(l["tags"]), "|", l["session"][:20])
