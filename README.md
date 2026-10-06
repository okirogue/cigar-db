# cigar-db

시가 카페 회원용 기록 앱의 중앙 시가 데이터베이스. 앱은 이 저장소의 `db/` JSON을 실행 시 받아 쓴다.

## 구성

| 경로 | 내용 |
| --- | --- |
| `db/tags.json` | 플레이버 태그 사전 37개 (한글 표기·설명·리뷰 매칭용 영문 동의어) |
| `db/cigars.json` | 시가별 노트 DB 2,666라인 (노트 1,240). 출처 구분(`official` / `review`), 검증 플래그 |
| `seed/noncuban_lines.csv` | 논쿠반 392브랜드 1,800라인 (cigarplace·cigarpage 카탈로그 기준, 2026-10-05) |
| `seed/cuban_lineup.csv` | 쿠반 현행 생산 27브랜드 228비톨라 (cubancigarwebsite 현행 목록 + 하바노스 강도) |
| `seed/excluded_lines.csv` | 번들·세컨드·기계식·샘플러 등 제외 248행 |
| `scripts/collect.py` | 어댑터 실행 → 태그 추출 → `db/cigars.json` 병합 |
| `seed/cuban_tags.csv` | 쿠반 핵심 114비톨라 수동 태깅 (리뷰 2곳 이상 합의, `~`는 저신뢰) |
| `scripts/adapters/` | 출처별 수집기. `official:*` 제조사 공식(davidoff, stg=cigarworld, wp_generic 12브랜드), `review:dojo`, `review:journal`, `review:manual` |
| `scripts/merge_ids.py` | 같은 라인 중복 ID 병합 |
| `scripts/seed_fill.py` | 시드 전 라인을 DB에 등록(노트 없는 건 스텁) |

## 노트 출처 원칙

1. 제조사 공식 노트가 1순위 (`notes.official`)
2. 리뷰 노트는 Cigar Dojo(점수 포함)·Cigar Journal·수동 태깅 (`notes.review`). Halfwheel·Cigar Aficionado·Perdomo는 robots/접근 정책상 수집하지 않음
3. 문장은 저장하되 앱에는 태그만 노출. 판매 사이트 링크는 저장하지 않음
4. `verified: true`는 사람이 확인한 항목

## 실행

Actions → collect-notes → adapter 이름 입력. 결과는 `db/cigars.json`에 자동 커밋.
