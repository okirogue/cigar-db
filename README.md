# cigar-db

시가 카페 회원용 기록 앱의 중앙 시가 데이터베이스. 앱은 이 저장소의 `db/` JSON을 실행 시 받아 쓴다.

## 구성

| 경로 | 내용 |
| --- | --- |
| `db/tags.json` | 플레이버 태그 사전 37개 (한글 표기·설명·리뷰 매칭용 영문 동의어) |
| `db/cigars.json` | 시가별 노트 DB. 출처 구분(`official` / `review`), 검증 플래그 |
| `seed/noncuban_lines.csv` | 논쿠반 392브랜드 1,800라인 (cigarplace·cigarpage 카탈로그 기준, 2026-10-05) |
| `seed/cuban_lineup.csv` | 쿠반 현행 생산 27브랜드 228비톨라 (cubancigarwebsite 현행 목록 + 하바노스 강도) |
| `seed/excluded_lines.csv` | 번들·세컨드·기계식·샘플러 등 제외 248행 |
| `scripts/collect.py` | 어댑터 실행 → 태그 추출 → `db/cigars.json` 병합 |
| `scripts/adapters/` | 출처별 수집기. `official:*`는 제조사 공식, 그 외는 리뷰 매체 |

## 노트 출처 원칙

1. 제조사 공식 노트가 1순위 (`notes.official`)
2. 없으면 리뷰 매체(Halfwheel, Cigar Aficionado, Cigar Dojo, Cigar Journal) 2곳 이상 일치 태그 (`notes.review`)
3. 문장은 저장하되 앱에는 태그만 노출. 판매 사이트 링크는 저장하지 않음
4. `verified: true`는 사람이 확인한 항목

## 실행

Actions → collect-notes → adapter 이름 입력. 결과는 `db/cigars.json`에 자동 커밋.
