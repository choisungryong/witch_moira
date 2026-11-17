# 기술 지시서 T3 — 현지화(언어팩)

2026-11-17, 기술 책임자(tech-lead) 작성. 총괄 디렉터가 배정한다. 각 지시서(T3-L0 ~ T3-L7)는 받는 에이전트에게 그대로 전달할 수 있게 썼다. 받는 쪽은 이 문서와 여기 적힌 파일만 보고 일할 수 있어야 한다.

사용자 결정(2026-11-17): 글로벌 출시, 배포의 기본은 스팀, 언어팩 적용, 목표 이용 등급은 15세 수준.

## 디렉터용 요약

1. 지금 화면 글은 모두 GDScript와 JSON 안의 한국어다. `tr()`·`TranslationServer` 0건, 번역 파일 0개. 코드의 한글 문자열 리터럴 721곳(서로 다른 것 505개), 데이터의 한글 문자열 132개(장비 80, 스킬 트리 34, 은총 9 외).
2. **코어가 글을 낸다.** 구역 이름, 수호자 이름, 목표 문장, 능력치 줄 이름·단위, 스킬 트리 설명 줄, 저장 오류 문장이 코어에서 한국어로 만들어진다. **골든 해시에 글이 들어간다**(직접 실행해 확인: `snapshot()` 안의 `enemies.#.title`, `items[].name/description`, `inventory[].name/description`). 지금 상태에서 언어나 이름을 코어에서 바꾸면 골든이 흔들린다.
3. **화면 글에 기대는 로직이 두 곳 있다**: `run_growth_quality37.gd:21`(진화 이름 문자열 비교), `chapter_one.gd:369`(오류 문장 비교). 화면 글을 바꾸면 동작이 바뀐다. 먼저 고친다.
4. 경계: **코어는 id·키·숫자 인자만 낸다. 화면이 번역한다.** 저장 파일에는 번역된 글을 넣지 않는다(스키마 4에서 장비의 `name`·`description`을 뺀다. 희귀 이름은 낱말 id 두 개로 저장).
5. 형식: Godot의 **PO(gettext) 파일, 키 기반**(`msgid`가 키). 복수형(`tr_n`)과 문맥을 PO로 받는다. 원문(한국어)은 화면 글은 `chapter1/i18n/ko.po`, 데이터 글은 JSON의 기존 `name` 등 필드(키는 id로 만든다).
6. 문장 틀은 이름 있는 자리 표시자(`{name}`)만 쓴다. 자리 표시자 바로 뒤에 한국어 조사를 붙이지 않는다. 이미 조사 오류가 있다(`chapter_hud.gd:1330` "성가대장를", `skill_tree.gd:594` "랭크 2으로").
7. 글꼴: 언어마다 첫 글꼴을 바꾸는 체인(한국어·일본어·중국어 간체·번체의 한자 모양이 다르므로). 후보는 Noto Sans/Serif CJK 계열 + Noto Sans(라틴·키릴), 한국어 본문은 Pretendard도 후보. 내려받기는 A3 승인 뒤.
8. 넘침 검사: Godot 내장 가짜 언어(pseudolocalization, 글 길이 늘림)로 `hud_dump.gd`를 돌리고, 덤프에서 잘림·화면 밖·겹침을 기계로 찾는다.
9. 순서 권고: **L0(틀·규칙, 새 파일만) → D4-U·D5-U·D6-A2는 처음부터 키로 → L1(코어 경계, 골든은 "글을 뺀 해시"로 대조) → L2(기존 화면 글 빼기)는 화면 묶음(D4-U·D5-U·D6-A2·A2 2-B 이후)이 끝난 뒤 `chapter_hud.gd`를 아무도 안 만지는 창에서.** 글꼴(L3)은 A3 승인 즉시 병렬.
10. 첫 언어 묶음 권고: 1차 한국어·영어, 2차 중국어 간체·일본어·중국어 번체(글꼴 작업을 한 번에), 3차 독일어·프랑스어·스페인어·러시아어·브라질 포르투갈어. 간체를 1차에 넣을지는 사용자 결정.

## 사용자 결정이 필요한 것

| # | 결정 | 선택지 | 권고 |
|---|---|---|---|
| L-U1 | 첫 언어 묶음 | (가) 한·영 → 간·일·번 → 유럽어 / (나) 한·영·간 → 일·번 → 유럽어 | (가). 다만 스팀 사용자 언어 비중에서 중국어 간체가 매우 크다(정확한 비율은 확인 필요). 출시 시점에 간체가 없으면 손해가 크므로 **출시 전에 2차까지 끝내는 것**을 조건으로 둔다. 데모(넥스트 페스트)를 1차 언어로만 낼지도 함께 정한다 |
| L-U2 | 글꼴 내려받기 승인(A3과 같은 건, 범위가 넓어짐) | 한국어만 / 한·중·일·라틴·키릴 전부 | 전부. 라이선스 원문 확인 → 내려받기 → 부분 집합 도구(fonttools, 공개 소프트웨어) 설치까지 한 번에 승인 |
| L-U3 | 번역 주체 | 사람 번역가 / 기계 초벌 + 사람 검수 / 기계만 | 1차의 영어는 기계 초벌 + 원어민 검수. 2차부터 전문 번역(외부 비용, 견적 뒤 승인). 서사 문장(어머니의 한 줄, 수집품)은 기계만으로 내지 않는다 |
| L-U4 | 이름이 정해진 고유명사(마녀 이름, 장 이름)를 언어마다 옮길지 그대로 둘지 | 음역 / 뜻 옮김 | narrative-lead 안을 받아 정한다. `WORDING-RULES.ko.md`(작성 중)에 언어별 칸을 둔다 |
| L-U5 | 옛 저장의 희귀 이름(낱말 id로 되찾지 못한 것) | 한국어 원문 그대로 모든 언어에 표시 / 다른 언어에서는 "희귀 + 기본 이름" 틀로 대체 | 대체. 한국어에서는 원문을 그대로 보인다(4.4절) |

디렉터가 정할 것은 6절.

---

## 1. 조사 결과 [모두 직접 확인]

### 1.1 한글 문자열의 양

GDScript 문자열 리터럴 중 한글이 든 것(주석 줄 제외, 임시 스크립트로 셈). "곳"은 등장 횟수, "종"은 파일 안에서 서로 다른 문자열 수, "틀"은 `%`나 `{`가 든 것.

| 파일 | 곳 | 종 | 틀 | 성격 |
|---|---|---|---|---|
| `chapter1/view/hud/chapter_hud.gd` | 293 | 234 | 61 | 화면. 가장 크다 |
| `chapter1/view/hud/skill_tree_panel.gd` | 90 | 82 | 46 | 화면 |
| `chapter1/app/chapter_one.gd` | 40 | 39 | 2 | 앱. 창 제목(57·364행), 알림, 저장 상태 줄 |
| `chapter1/core/chapter_profile.gd` | 40 | 33 | 1 | 코어(저장). 오류 문장이 화면에 그대로 나간다 |
| `chapter1/core/combat_core.gd` | 30 | 29 | 0 | 코어. 능력치 줄 이름·단위(332~365행), 시작 장비 이름(41~44행) |
| `chapter1/core/chapter_core.gd` | 24 | 24 | 1 | 코어. 구역 이름(38행), 의식 이름(41~42행), 수호자 이름(420행), 목표 문장(772~777행), 빌드 오류 |
| `chapter1/core/skill_tree.gd` | 22 | 22 | 21 | 코어. 설명 줄 `describe_block`(544~596행) |
| `chapter1/view/world/chapter_world.gd` | 5 | 4 | 0 | 3D 글(`Label3D`, 279~339행) |
| `chapter1/view/ui51/chapter_route51.gd` | 4 | 4 | 0 | 화면 |
| `chapter1/core/run_growth_quality37.gd` | 2 | 2 | 0 | 코어. **진화 이름 비교 로직** |
| `chapter1/core/loot.gd` | 1 | 1 | 0 | 코어. 이름 조립 `"의 "` |
| `chapter1/view/fx/chapter_effects.gd` | 1 | 1 | 0 | 글꼴 이름 |
| 옛 층 `chapter1/view/cloister_hud.gd`, `view/chapter_world.gd` | 83 | 76 | 20 | 옛 층(preload만). **번역하지 않는다**(T1 지시서 4에서 정리) |
| `chapter1/core/chapter_items.gd`(장비 v1), `combat_run.gd` | 40 | 39 | 2 | 옛 저장 검증·옛 검사용. 아래 4.5 |
| 검사 `chapter1/tests/*` | 48 | — | — | 한국어 이름을 기대값으로 쓰는 검사가 있다(`test_loot.gd` 22곳 등). L1·L2에서 함께 고친다 |
| **합계** | **721** | **505**(전체 고유) | 159 | 고유 문자열 글자 수 합 약 6,200자 |

데이터(`chapter1/data/*.json`, 한글이 든 문자열 값):

| 파일 | 개수 | 필드 |
|---|---|---|
| `loot.json` | 80 | `name` 47(기본 21, 접사 20, 전설 3, 고유 3), `rare_names.first`·`second` 각 10(**id 없음**), `description` 6, `slot_names` 7 |
| `skill_trees.json` | 34 | `name` 21, `lore` 13 |
| `growth_quality37.json`(그리고 `growth.json`, `growth_quality36.json`) | 각 9 | `name` 6, `evolution_name` 3 |
| `character_progression.json`, `combat_tuning.json` | 0 | — |

`project.godot`: 한글 없음. `config/name="Witch Moira"`. 창 제목은 코드(`chapter_one.gd` 57·364행)에서 한국어로 덮어쓴다.

### 1.2 글을 조립하는 곳

| 종류 | 위치 | 문제 |
|---|---|---|
| 조사를 문자열로 붙임 | `chapter_hud.gd:222` `pair[0]+"으로 시작"` → 1236행에서 `"연쇄 전류으로 시작"`을 `"연쇄 전류로 시작"`으로 **표시 글을 replace해서 고침** | 언어가 바뀌면 깨진다 |
| 조사 고정 | `chapter_hud.gd:1330` `"%s를 처치하세요"` | **지금도 틀린다**: 수호자 이름 "서리의 성가대장", "회랑의 파수왕"은 받침이 있어 "을"이어야 한다 |
| 조사 고정 | `skill_tree.gd:594` `"서리창 랭크 %d으로 시작"` | 2·4·5·9에서 "로"여야 한다 |
| 이름 조립 | `loot.gd:143` `prefix+"의 "+name_`, 144행 `" — "+suffix`, 150행 `legend.name+" "+name_`, 194행 희귀 `first+" "+second` | 어순이 한국어 고정. 영어는 "Wrathful Staff of Harvest"처럼 앞뒤 형태가 다르다 |
| 표시 글 바꿔치기 | `chapter_hud.gd` 433·434·641·644·646·870·1219·1236·1334행 `text.replace(...)` | 번역문에서는 찾을 글이 없어 조용히 실패한다 |
| 숫자 끼워 넣기 | `chapter_hud.gd` 61곳, `skill_tree_panel.gd` 46곳, `skill_tree.gd` 21곳 `%d`·`%.1f`·`%s` | 위치 기반 자리 표시자. 어순이 다른 언어에서 순서를 바꿀 수 없다 |
| 단위 | "초", "m", "회", "%", "m/초", "개", "발", "대상" — 코어(`combat_core.gd` 333~365행)와 화면에 섞여 있다 | 단위가 코어 결과에 들어 있다 |
| 천 단위 구분 | `chapter_hud.gd` `_commas()` | 언어마다 다르다(독일어는 마침표, 프랑스어는 공백) |

### 1.3 화면 글에 기대는 로직 [위험]

| 위치 | 내용 |
|---|---|
| `chapter1/core/run_growth_quality37.gd:21~24` | 은총 카탈로그의 번개 진화 이름이 `"두 갈래 폭풍"`인지 비교하고 `"세 갈래 폭풍"`으로 바꾼 뒤 후속 문서와 같은지 본다. JSON의 이 이름을 번역하거나 고치면 `configure`가 거부한다(판이 시작되지 않는다) |
| `chapter1/app/chapter_one.gd:369` | `profile.error!="전용 저장 경로가 없는 미리보기입니다"`로 분기한다. 오류 문장을 바꾸면 분기가 바뀐다 |

### 1.4 코어 이벤트와 골든 [직접 실행해 확인]

`res://_local/t3-probe/snapshot_text_probe.gd`(임시 검사, `_local`)를 헤드리스로 돌렸다. 시드 11, 냉기·번개, 내장 자동 조작으로 끝까지(냉기 victory 25,005틱, 번개 victory 20,697틱), 600틱마다 `snapshot()`과 마지막 이벤트 버퍼에서 한글이 든 문자열 경로를 모았다.

```
PROBE_PATH snapshot.enemies.#.title = 잿불의 문지기
PROBE_PATH snapshot.inventory[].name = 순례자의 장화
PROBE_PATH snapshot.inventory[].description = 화염 처치 폭발 · 피해 -10% · 발사체 +1
PROBE_PATH snapshot.items[].name = 수문장의 외투 — 수확
PROBE_PATH snapshot.items[].description = 화염 처치 폭발 · 피해 -10% · 발사체 +1
PROBE_PATH events[].item.name = 갈림길의 서약
PROBE_PATH events[].item.description = 번개 분기 +1 · 연쇄 +1 · 번개 피해 -12%
```

- `golden_core.gd:22`는 `JSON.stringify(run.snapshot()).sha256_text()`다. 그러므로 **장비 이름·설명과 수호자 이름이 골든 해시에 들어간다.** `loot.json`의 이름 하나, `chapter_core.gd:420`의 수호자 이름 하나만 바꿔도 골든 체크포인트가 달라진다(판의 진행은 같아도).
- 코드상으로는 이번 실행에 안 잡혔지만 같은 길로 들어갈 수 있는 것: `snapshot.chapter.pending_rewards[]`(장비), `snapshot.growth.offer.cards[].title`(은총 카드 이름, 체크포인트 순간에 제안이 열려 있으면).
- 이벤트(`events`)는 `snapshot()`에 들어가지 않는다(`combat_core.gd:1092~1097`). 하지만 이벤트도 글을 싣는다: `chapter_champion.name`(수호자), `gate_opened.name`(구역), `ritual_started/completed.name`(의식), 장비 이벤트의 `item.name`. 화면이 이것을 그대로 그린다.
- 결론: **코어에서 글을 빼는 일은 골든을 한 번 바꾼다.** 진행이 같다는 것을 보이려면 "글을 뺀 해시"가 필요하다(L0-b).

### 1.5 글꼴

- `SystemFont`로 Windows 글꼴 이름을 부른다: 본문 "Malgun Gothic", 제목 "Batang". `chapter_hud.gd` 51~52·141·1355~1356행, `skill_tree_panel.gd` 99~105행, `chapter_effects.gd:716`, 옛 층 `cloister_hud.gd` 46~47·136행. 게임 안 글꼴 파일(`.ttf`·`.otf`) 0개.
- 배포 불가(Microsoft 글꼴), 다른 OS·스팀 덱에서는 다른 글꼴로 바뀐다(`PLAN-GAP-AUDIT-20261117` 요약 10, A2 2.2절).
- `Label3D`(`chapter_world.gd` 279~283행 의식·관문 글, `chapter_effects.gd` 326·416행)는 글꼴을 지정하지 않는다. 컨트롤 테마가 아니라 프로젝트 기본 글꼴을 쓰므로, 테마만 바꾸면 3D 글은 빠진다.
- `combat_bar.gd` 106·148행은 `get_theme_default_font()`로 직접 그린다.

### 1.6 글자 폭 가정

- `view/hud`, `view/fx`, `app`, `hud_dump.gd`에서 `custom_minimum_size` 43곳, `AUTOWRAP_OFF` 21곳, `OVERRUN_TRIM_ELLIPSIS` 6곳, `clip_text` 1곳. 예: `chapter_hud.gd:728` 라벨 폭 115 고정, 731행 회피 표시 195 고정, 1493행 목표 300 고정.
- `draw_string`으로 폭을 정해 그리는 곳: `combat_bar.gd:107~108`, `skill_tree_panel.gd:423·436`.
- 글자 수 상한(`CHAPTER1-TEXT-PLAN` 0.2)은 한국어·맑은 고딕 기준이고 실제 폭으로 잰 적이 없다.

### 1.7 저장 파일에 들어가는 글

- 프로필 장비 키 `ITEM_KEYS`에 `name`·`description`이 있다(`chapter_profile.gd:24`). 저장 파일에 한국어 이름이 들어간다.
- D5 이후 읽을 때 `loot.dress()`가 지금 데이터로 이름·설명을 다시 짓는다(`loot.gd:310~324`). 다만 **희귀는 저장된 글을 그대로 쓴다**(323행). 희귀 이름은 `rare_names.first`·`second`에서 순번으로 뽑아 이어 붙인 글이고(194행), 순번도 id도 저장되지 않는다. 그래서 다른 언어로 다시 지을 수 없다.
- v1 장비(`grammar` 없음)는 `dress`하지 않는다(312행). v1의 이름도 한국어 글 그대로다.
- 프로필 오류(`profile.error`)는 한국어 문장이고 화면에 그대로 나간다(`chapter_one.gd` 355·357·358·369·480행).
- 그 밖의 저장 키(`TOP_KEYS`, `CHAR_KEYS`)에는 글이 없다.

---

## 2. 설계

### 2.1 번역 체계 선택

| 항목 | 결정 | 이유 |
|---|---|---|
| 파일 형식 | **PO(gettext)**, 언어마다 한 파일: `chapter1/i18n/<locale>.po` | Godot 4가 `.po`를 그대로 번역 자원으로 읽는다. 복수형(`msgid_plural`/`tr_n`)과 문맥(`msgctxt`/`tr(key, ctx)`)을 쓸 수 있다. 번역 도구(Poedit, Weblate, Crowdin 등)가 받는 표준 형식이다. 언어별 파일이라 병합 충돌이 적다. CSV는 한 파일에 모든 언어가 들어가 충돌이 잦고, 복수형·문맥 지원은 확인하지 않았다 |
| 키 방식 | **키 기반**: `msgid`가 키(`hud.objective.seal_kills`), `msgstr`이 그 언어의 글 | 원문(한국어)을 고쳐도 코드는 그대로다. 원문은 `ko.po`의 `msgstr`이 진실 |
| 원문 위치 | 화면 글 → `chapter1/i18n/ko.po`(손으로 쓰는 원본). 데이터 글 → JSON의 기존 필드(`name`, `description`, `lore`, `evolution_name`)를 한국어 원문으로 두고, 키는 id에서 기계적으로 만든다 | 데이터 담당(content-balance, narrative-lead)과 관리 툴이 지금처럼 JSON에서 이름을 본다. 추출 도구가 JSON의 원문을 `ko.po`의 데이터 구역으로 옮겨 쓴다(생성 구역, 손으로 고치지 않음) |
| 등록 | `project.godot`의 `internationalization/locale/translations`에 `.po` 목록, `internationalization/locale/fallback="en"` | 빠진 키는 영어로, 영어도 없으면 키가 그대로 보인다(검사가 잡는다) |
| 호출 | 화면 코드는 **명시적으로** `Loc.t(key, args)`·`Loc.tn(key, n, args)`를 부른다. 컨트롤의 자동 번역(`auto_translate_mode`)은 HUD 뿌리에서 끈다 | 코드로 만드는 HUD라 자동 번역이 언제 일어나는지 추적하기 어렵다. 이미 번역된 장비 이름이 키와 우연히 같으면 두 번 번역된다. 명시 호출만 검사 도구로 셀 수 있다 |
| 언어 바꿈 | 메뉴에서만 바꾼다. 바꾸면 `TranslationServer.set_locale()` 뒤 HUD를 다시 짓는다(신호 `locale_changed`) | 판 도중 바꾸기를 지원하면 모든 라벨이 `NOTIFICATION_TRANSLATION_CHANGED`를 처리해야 한다. 비용 대비 얻는 것이 없다 |

### 2.2 키 이름 규칙

- 소문자, 낱말은 `_`, 층은 `.`. 첫 마디가 영역: `ui`, `hud`, `menu`, `stash`, `tree`, `result`, `notify`, `profile`, `world`, `item`, `skill`, `grace`, `enemy`, `zone`, `ritual`, `stat`, `unit`, `story`, `input`.
- 화면 글: `<영역>.<화면 또는 부품>.<뜻>`. 예: `menu.start_with`, `hud.dash.ready`, `hud.objective.seal_kills`, `result.title.victory`. 뜻으로 이름 짓고 글 모양으로 짓지 않는다(`hud.dash.ready`이지 `hud.space_evade_ready`가 아니다).
- 데이터 글: id에서 만든다. 고칠 수 없게 규칙으로 고정한다.

| 데이터 | 키 |
|---|---|
| 기본 장비 `bases[].id` | `item.base.<id>.name` |
| 접사 `affixes[].id` | `item.affix.<id>.prefix`, `item.affix.<id>.suffix`(언어마다 앞·뒤 형태가 다르므로 둘 다 둔다. 한국어는 같은 글) |
| 전설 `legendaries[].id` | `item.legendary.<id>.name`, `.desc` |
| 고유 `uniques[].id` | `item.unique.<id>.name`, `.desc` |
| 희귀 낱말(새 id, 4.4절) | `item.rare.first.<id>`, `item.rare.second.<id>` |
| 칸 `slot_names` | `item.slot.<slot>` |
| 등급 | `item.quality.<quality>` |
| 스킬(은총) `skills[].id` | `skill.<id>.name`, `skill.<id>.evolved_name` |
| 결정(패시브) `passives[].id` | `grace.passive.<id>.name` |
| 트리 노드 | `tree.<tree_id>.node.<node_id>.name`, `.lore`; 가지 `tree.<tree_id>.branch.<id>.name`; 단 `tree.<tree_id>.tier.<n>.name` |
| 구역·의식·수호자 | `zone.<n>.name`, `ritual.<id>.name`, `enemy.champion.<zone>.name` |
| 능력치 줄 | `stat.<row_id>.label`, 단위 `unit.<unit_id>` |

- `.`이 든 id(`chapter1.skill.frost`)는 그대로 쓴다: `skill.chapter1.skill.frost.name`. 키를 쪼개 쓰는 코드는 만들지 않는다.
- 문맥이 필요한 동음이의는 키를 나눈다(`msgctxt`는 쓰지 않아도 된다). 복수형만 `msgid_plural`을 쓴다.

### 2.3 경계: 코어는 키와 인자만 낸다

| 지금 | 바꾼 뒤 |
|---|---|
| 이벤트 `{"name": "…"}`(수호자·구역·의식) | `{"zone": n}`, `{"id": "vigil"}`처럼 id만. 화면이 `zone.<n>.name` 등으로 번역 |
| `enemies[id].title = "…"`(`chapter_core.gd:420`) | 지우거나 `title_key`(키 문자열)로. 키는 언어와 무관하므로 골든이 한 번 바뀐 뒤 고정된다 |
| `objective()`의 `title`, `text`(문장) | `{"zone", "kind": "move"|"seal_kills"|"champion", "done", "total", "hp", "hp_max", …}` 숫자와 종류만. 문장은 화면 |
| `stat_sheet()`의 `_row(id, label, …, unit, …)` | `label`·`unit`을 빼고 `id`와 `unit_id`만(`"s"`, `"m"`, `"pct"`, `"count"`, `"m_per_s"`). 화면이 `stat.<id>.label`, `unit.<unit_id>` |
| `stat_sheet().effects[{source: item.name, text: description}]` | `{source_uid 또는 item 참조, kind: "unique"|"legendary", id}` |
| `skill_tree.describe_block()`이 한국어 줄 배열 | `[{key: "tree.effect.pierce_add", args: {n: 1}}, …]` 구조를 돌려주고, 줄 만들기는 화면(`skill_tree_panel.gd`)으로 옮긴다. 함수 이름을 바꾸지 않으려면 `describe_block_keys()`를 새로 두고 옛것은 L2 끝에 지운다 |
| `profile.error = "…"` 문장 | `profile.error_code = "save_conflict"` + `profile.error_args = {…}`. 화면이 `profile.error.<code>`로 번역. 개발용 상세는 영어로 로그에만 |
| `chapter_core.errors`(빌드 검증) | 개발자용. 영어 문장으로 바꾸고 화면에 직접 보이지 않게 한다(보일 때는 `profile.error.build_rejected` 하나로) |
| `run_growth.effective_skill().name`, 은총 카드 `title` | 빼거나 키로. 화면이 `skill.<id>.name`/`evolved_name` |
| 장비 사전의 `name`·`description` | 2.4절 |

규칙: 코어가 새로 내는 이벤트·결과에 사람이 읽는 글을 넣지 않는다. 검사로 지킨다(L0-b의 "글 없는 스냅숏" 검사가 한글뿐 아니라 키가 아닌 글을 잡도록, 허용 필드 목록을 둔다).

### 2.4 장비 이름과 저장(스키마 4와 함께)

D6 8절의 스키마 4(`chapter-one-profile-v4.json`, v3은 읽기만 하고 첫 저장 때 옮김)에 다음을 더한다. 스키마를 한 번만 올리기 위해 **D6 S 단계와 같은 지시서로 묶는다**(디렉터 결정 T3-D1).

| 항목 | 스키마 4 |
|---|---|
| 장비 `name`, `description` | **저장하지 않는다.** 읽을 때·굴릴 때 화면이 id(`base_id`, `affixes[].id`, `legendary_id`, `quality`, `rare_words`)로 짓는다 |
| 희귀 이름 | 새 필드 `rare_words: ["<first_id>", "<second_id>"]`. `loot.json`의 `rare_names.first`·`second`를 문자열 배열에서 `{"id": "...", "name": "..."}` 배열로 바꾼다(id는 영어 소문자, 한 번 정하면 고치지 않는다) |
| 옛 희귀(v3에서 옮길 때) | 저장된 글을 공백으로 나눠 두 낱말이 지금 `ko` 원문 목록에 각각 있으면 그 id로 `rare_words`를 채운다. 못 찾으면(이름이 바뀐 낱말, 세 낱말) `legacy_name`에 원문을 보관한다. 화면은 한국어일 때 `legacy_name`을 그대로, 다른 언어일 때 `item.name.rare_unnamed` 틀("{quality} {base}")로 보인다(L-U5) |
| v1 장비(`grammar` 없음) | 저장 형식을 바꾸지 않는다. 화면이 `chapter_items.gd`의 id(`chapter1.full.<id>`, 접사 id)로 키를 만들어 이름을 짓는다. 키: `item.v1.base.<id>.name`, `item.v1.affix.<id>.name`, `item.v1.unique.<id>.name`, `.desc` |
| 메모리의 장비 사전(판 안) | `name`·`description` 키를 없애고 `rare_words`를 둔다. **골든 체크포인트 해시가 바뀐다**(L0-b로 진행 동일을 보인다). 굴림의 난수 소비는 그대로다(희귀 낱말은 지금도 순번 두 개를 뽑는다. 뽑은 순번을 id로 바꿔 담을 뿐) |
| 검증 | `validate`는 `name`·`description`이 없어야 통과(스키마 4 장비). 스키마 3 장비는 지금 규칙(D5) 그대로 읽어 옮긴다 |

원칙: **저장 파일에는 번역된 글, 화면에 보이는 글을 넣지 않는다.** 예외는 옛 저장에서 되찾지 못한 `legacy_name` 하나다.

### 2.5 문장 틀

- 자리 표시자는 **이름 있는 것만**: `{name}`, `{n}`, `{done}`, `{total}`. Godot의 `String.format(dict)`를 쓴다(`"{name}"` 형식). `%d`·`%s`를 번역 글 안에 쓰지 않는다.
- 숫자는 화면이 먼저 글로 만든 뒤 넣는다: `Loc.num(1234)`(언어별 천 단위 구분), `Loc.dec(1.5, 1)`(소수점 기호), `Loc.pct(12.5)`. 단위는 틀 안에 쓴다(`"{n}초"`, `"{n} s"`). 단위를 틀 밖에서 붙이지 않는다.
- **한국어 조사**: 1순위는 자리 표시자 뒤에 조사가 오지 않게 문장을 짓는다("처치 대상: {name}", "{name} 처치"). 2순위로 꼭 필요하면 한국어 번역 글 안에서만 `{name|을}` 표기를 허용하고 `Loc`이 받침을 보고 고른다(을/를, 이/가, 은/는, 와/과, 으로/로 — "로"는 ㄹ 받침도 "로"). 숫자·라틴 문자로 끝나는 이름은 읽는 소리로 판단하는 표를 둔다(0·1·3·6·7·8은 받침 있음, L·M·N 등). 다른 언어에서 `|` 표기는 오류로 검사한다.
- **영어 복수·관사**: 수량이 붙는 글은 모두 `tr_n`. 자리 표시자 앞에 관사(a/an/the)를 쓰지 않는다("Defeat {name}"). 수호자 이름 자체에 관사가 필요하면 이름 쪽 글에 넣는다("The Ember Warden").
- **어순**: 장비 이름 조립을 틀로 옮긴다.

| 키 | ko | en(예) |
|---|---|---|
| `item.name.magic.prefix` | `{prefix}의 {base}` | `{prefix} {base}` |
| `item.name.magic.suffix` | `{base} — {suffix}` | `{base} {suffix}` |
| `item.name.magic.both` | `{prefix}의 {base} — {suffix}` | `{prefix} {base} {suffix}` |
| `item.name.legendary` | `{legend} {base}` | `{legend} {base}` |
| `item.name.rare` | `{first} {second}` | `{first} {second}` |

  접사는 `prefix`형과 `suffix`형 두 글을 둔다(en `Wrathful` / `of Wrath`). 문법적 성(性)이 있는 언어(독일어·프랑스어·러시아어·스페인어)는 형용사 일치가 문제다. 3차 언어 때 기본 장비 키에 `#. gender: f` 주석을 달고 접사 키를 `item.affix.<id>.prefix.f`처럼 성별로 나누는 확장을 둔다(지금은 틀만 열어 둔다). 쉬운 길로 "{base} {suffix}"만 쓰는 언어별 틀도 허용한다.
- 줄바꿈은 번역 글 안에 둔다(`\n`). 화면이 문장을 이어 붙여 한 줄을 만들지 않는다(`"진화 · " + "랭크 %d"` 같은 것은 키 하나로).
- `text.replace()`로 표시 글을 바꾸는 9곳은 모두 키 선택으로 바꾼다(어떤 조건일 때 어느 키를 쓸지).

### 2.6 글꼴

**후보**(라이선스는 내 기억이다. 확인 필요. 내려받기는 사용자 승인 L-U2 뒤)

| 용도 | 후보 | 덮는 글자 | 라이선스(기억) |
|---|---|---|---|
| 본문(한) | Pretendard / Noto Sans KR | 한글, 라틴 | 둘 다 SIL OFL 1.1 |
| 본문(일·간·번) | Noto Sans JP / SC / TC (= Source Han Sans 계열) | 한자 지역 모양, 가나 | SIL OFL 1.1 |
| 본문(라틴·키릴·그리스) | Noto Sans | 라틴 확장, 키릴, 그리스 | SIL OFL 1.1 |
| 제목(한) | Noto Serif KR / 함렛 / 고운바탕(A2 2.2절 후보) | 한글 | SIL OFL 1.1 |
| 제목(일·간·번) | Noto Serif JP / SC / TC | | SIL OFL 1.1 |
| 제목(라틴·키릴) | Noto Serif | | SIL OFL 1.1 |
| 숫자(고정폭) | 본문 글꼴의 `tnum` 기능 또는 별도 고정폭 숫자 글꼴 | | — |

**체인(언어별 첫 글꼴을 바꾼다)**

- 한·중·일은 같은 한자 코드에 지역마다 다른 모양을 쓴다. 하나의 체인으로 모든 언어를 덮으면 일본어 화면에 한국식 한자가 나온다. 그래서 `Loc`이 언어가 바뀔 때 테마의 기본 글꼴을 언어별 체인으로 갈아 끼운다.
  - ko: Pretendard(또는 Noto Sans KR) → Noto Sans → Noto Sans JP → Noto Sans SC
  - ja: Noto Sans JP → Noto Sans → Noto Sans KR
  - zh_CN: Noto Sans SC → Noto Sans → Noto Sans KR / zh_TW: Noto Sans TC → …
  - 라틴·키릴 언어: Noto Sans → Noto Sans KR(한국어 고유명사가 남을 때 대비)
- Godot의 `Font.fallbacks`로 체인을 만든다. 시스템 글꼴 대체(`allow_system_fallback`)는 끈다(다른 컴퓨터에서 결과가 달라지지 않게). 끈 뒤 빠진 글자는 검사(L3-c)가 잡는다.
- 3D 글(`Label3D`)과 `draw_string`도 같은 체인을 쓰도록 `Loc.font(role)` 하나에서 받는다. 프로젝트 기본 글꼴(`gui/theme/custom_font`)도 본문 체인으로 둔다.
- 한 글꼴 묶음 안에서 A2 2.2절의 위계(H1~보조, 14 미만 금지)를 그대로 쓴다. 크기는 언어마다 같은 숫자를 쓰되, 중·일 글꼴이 같은 크기에서 작아 보이면 `Loc`의 언어별 배율(0.95~1.05)로 맞춘다.

**용량**: CJK 글꼴은 굵기 하나에 수 MB~십수 MB다(정확한 값은 확인 필요). 2굵기 × 4지역 × 본문·제목이면 100MB를 넘을 수 있다. 줄이는 길:
- 게임에는 문자 입력(이름 짓기)이 없다. **실제로 쓰는 글자만 남기는 부분 집합**을 빌드 때 만든다(`tools/dev/font_subset.py`, fonttools의 `pyftsubset`). 대상 글자 = 출시 언어 `.po`의 모든 글자 + ASCII + 숫자·기호 + 한국어는 KS X 1001 2,350자(번역 수정 여유).
- 부분 집합 글꼴은 OFL의 "예약 글꼴 이름(Reserved Font Name)" 조항 때문에 이름을 바꿔야 할 수 있다. 글꼴마다 원문을 열어 RFN이 있는지 본다(확인 필요).

**라이선스 확인 절차**(ui-hud, 내려받은 뒤)
1. 각 글꼴 묶음의 `OFL.txt`(또는 `LICENSE`) 원문과 판 번호, 내려받은 주소, 날짜, sha256을 `chapter1/art/fonts/FONTS.ko.md`에 적는다.
2. RFN 유무를 적고, 부분 집합을 만들 때 이름 변경이 필요한지 판단해 적는다.
3. 게임 안 크레딧 화면과 배포 폴더에 OFL 원문을 넣는다(T4의 고지 항목과 같이).
4. 판단이 서지 않는 조항이 있으면 사용자에게 올린다. 추측으로 넣지 않는다.

### 2.7 배치

규칙(새 화면과 L2에 모두 적용)
- 글이 든 컨트롤에 **고정 폭을 주지 않는다**. 최소 폭은 되지만 그 안에 글을 맞추는 가정은 하지 않는다. 컨테이너가 늘어날 수 있게 둔다.
- 한 줄로 둬야 하는 글(단추, 칸 머리)은 `OVERRUN_TRIM_ELLIPSIS` + 툴팁에 전체 글. 설명은 자동 줄바꿈(`AUTOWRAP_WORD_SMART`).
- 독일어·러시아어는 영어보다 30~40% 길다는 경험칙으로 **한국어 대비 가로 2배까지** 견디게 짓는다(한국어는 영어보다 짧다). 키마다 상한이 필요한 곳은 `.po` 주석 `#. max: 18`에 적고 검사가 번역 글 길이를 본다(폭이 아니라 글자 수라 거친 1차 관문).
- 숫자 칸은 고정폭 숫자를 써서 값이 바뀔 때 흔들리지 않게 한다.
- 단축키 표기(`[E]`, `Space`, `Q`)는 글 안에 박지 않는다. `{key_interact}` 자리 표시자로 두고 `Loc`이 입력 장치에 맞는 표기를 넣는다(패드 아이콘은 T4).

**넘침 자동 검사**
- Godot 내장 가짜 언어(pseudolocalization: 글 늘이기, 악센트 붙이기, 앞뒤 괄호 표시)를 켜고 `hud_dump.gd`를 돈다. 프로젝트 설정 이름은 `internationalization/pseudolocalization/*`, 실행 중에는 `TranslationServer.pseudolocalization_enabled`(이름은 구현자가 4.5.1 문서로 확인).
- `hud_dump.gd`에 `--locale=<code>`와 `--pseudo`(늘이는 비율 `--pseudo-expand=1.4`)를 더한다. 덤프의 각 텍스트 컨트롤에 `text_w`(글꼴로 잰 한 줄 폭, 자동 줄바꿈이면 줄 수), `clipped`(잘림 또는 말줄임 발생), `offscreen`(화면 밖), `overlap`(같은 부모의 다른 텍스트 컨트롤과 겹침)을 적는다.
- 판정 도구 `tools/dev/check_overflow.py <dump.json>`: `clipped`이면서 툴팁이 없는 것, `offscreen`, `overlap`을 목록으로 내고 하나라도 있으면 실패. 허용 목록(의도한 말줄임)은 키로 적는다.
- 가짜 언어는 "번역이 안 된 글"도 드러낸다: 가짜 언어 캡처에서 괄호 표시가 없는 글은 `Loc`을 거치지 않은 글이다. 검사가 덤프에서 이것을 센다(L2 진행률 지표).

### 2.8 언어 선택과 저장, 스팀 따라가기

- 설정은 **프로필과 다른 파일** `user://settings.cfg`(Godot `ConfigFile`)에 둔다. 키 `locale`. 프로필 스키마와 무관하게 하고, 프로필이 거부되어도 언어는 유지된다. 설정 화면(G5/PLAN-GAP 8)이 생기면 같은 파일을 쓴다.
- 첫 실행 순서: (1) `settings.cfg`의 `locale` → (2) 스팀이 있으면 스팀 게임 언어(GodotSteam `getCurrentGameLanguage()`, 값은 `"koreana"`, `"english"`, `"schinese"`, `"tchinese"`, `"japanese"` 같은 스팀 이름. 대응표를 `Loc`에 둔다) → (3) `OS.get_locale_language()` → (4) `en`. 지원하지 않는 언어면 `en`.
- 플레이어가 메뉴에서 고르면 그것을 저장하고 이후로는 스팀 설정보다 앞선다. 메뉴의 언어 목록에는 언어 이름을 **그 언어 자체로** 쓴다(한국어, English, 日本語, 简体中文, 繁體中文).
- 언어 목록은 출시 언어 묶음(`chapter1/i18n/locales.json`: `{"shipping": ["ko","en"], "in_progress": ["ja","zh_CN","zh_TW"]}`)에서 만든다. `in_progress`는 개발 빌드에서만 보인다.

### 2.9 번역 작업 흐름

| 단계 | 누가 | 무엇 |
|---|---|---|
| 원문 | 화면 글: ui-hud가 코드에 키를 쓰며 `ko.po`에 원문을 더한다. 서사 글: narrative-lead가 `docs/story/`에 쓰고 content-balance가 `ko.po`(또는 데이터 JSON)에 옮긴다. 데이터 이름: JSON 필드 | 원문 주인 = 그 글을 처음 쓴 담당. 고칠 때도 같은 담당 |
| 용어집 | narrative-lead | `docs/story/WORDING-RULES.ko.md`(작성 중)에 언어별 칸: 고유명사(마녀, 장, 적, 장비 낱말), 금지 낱말, 말투. 기계가 읽을 사본 `chapter1/i18n/glossary.csv`(키 없이 낱말 대응표) |
| 추출 | manager-tools의 `tools/dev/i18n_extract.py` | 코드의 `Loc.t("…")` 호출, JSON의 데이터 글을 모아 `ko.po` 데이터 구역을 다시 쓰고 `template.pot`를 만든다. 각 항목에 `#.` 주석으로 원문 한국어, 자리 표시자 뜻, 글자 상한, 화면 위치(캡처 경로) |
| 넘기기 | 디렉터 | 번역가에게 `template.pot` + 그 언어의 `.po`(이미 된 것 포함) + 용어집 + 화면 캡처 묶음. 원문이 바뀐 항목은 추출 도구가 `#, fuzzy` 표시(원문 해시를 `#. src:` 주석에 둔다) |
| 받기 | manager-tools 도구 | 받은 `.po`를 검사(아래)로 돌린 뒤 넣는다 |
| 관리 툴 | manager-tools | 「번역」 화면: 언어별 진행률, 빠진 키, fuzzy, 상한 넘김, 자리 표시자 불일치. 캡처(L4의 가짜 언어·언어별) 나란히 보기 |

**`run_all.py`에 넣을 검사 `i18n`(Python, 빠름, `--quick`에 포함)**
1. 코드가 부르는 모든 키가 `ko.po`에 있다(없으면 실패).
2. `locales.json`의 `shipping` 언어 `.po`에 `ko.po`의 모든 키가 있고 빈 `msgstr`·`fuzzy`가 없다(실패). `in_progress`는 경고만.
3. 각 번역 글의 자리 표시자 집합이 원문과 같다(`{name}` 빠짐·추가는 실패).
4. 한국어 외 언어에 조사 표기 `{x|을}`가 없다.
5. `#. max:` 상한 넘김(실패).
6. 화면 코드(`chapter1/view/hud/`, `view/fx/`, `view/world/`, `view/actors/`, `app/`)에 한글 리터럴이 늘지 않는다: L2 전에는 지금 개수를 기준선 파일(`tools/dev/i18n_baseline.json`)로 두고 **늘면 실패**, 줄면 기준선을 낮춘다. L2가 끝나면 0. 코어(`chapter1/core/`)도 L1 뒤 0(옛 저장용 `chapter_items.gd`와 옛 검사용 `combat_run.gd`는 허용 목록).

### 2.10 첫 언어 묶음 권고(L-U1)

| 차수 | 언어 | 근거 |
|---|---|---|
| 1차 | 한국어, 영어 | 한국어는 원문. 영어는 스팀 전체에서 가장 큰 언어이고, 번역 흐름·글꼴 체인·넘침 검사를 처음 세우는 데 라틴 글자가 가장 싸다. 데모·넥스트 페스트 최소 조건 |
| 2차 | 중국어 간체, 일본어, 중국어 번체 | 스팀 사용자 중 중국어 간체 비중이 매우 크다(정확한 값은 스팀 하드웨어 설문으로 확인 필요). 이 장르(군중 생존, 핵 앤 슬래시)의 아시아 수요. **세 언어가 같은 글꼴 문제(지역 한자 모양, 용량, 부분 집합)를 공유하므로 한 번에 하는 것이 싸다** |
| 3차 | 독일어, 프랑스어, 스페인어(스페인·중남미 중 택), 러시아어, 브라질 포르투갈어 | 긴 글(독·러)과 문법적 성(형용사 일치)으로 장비 이름 틀 확장이 필요하다(2.5절). 키릴 글꼴은 Noto Sans가 덮는다 |
| 하지 않음 | 아랍어·히브리어(오른쪽에서 왼쪽) | 화면 전체 좌우 반전이 필요하다. 수요를 보고 따로 정한다 |

---

## 3. 지시서

공통 규칙(모든 지시서)
- 코드를 고치는 에이전트는 별도 작업 폴더에서 일한다(DIRECTOR-PLAN 2.8의 2026-11-17 규칙).
- `.gitattributes`가 `* -text`다. 줄바꿈을 바꾸는 도구로 기존 파일을 고치지 않는다. `.po`는 UTF-8, LF로 새로 만든다.
- 표현은 코어 이벤트와 읽기 전용 상태만 쓴다. `Loc`은 표현 쪽 모듈이며 코어가 부르지 않는다.
- 옛 층(`chapter1/view/` 바로 아래 `cloister_*.gd`, `chapter_world_quality*.gd`, `view/chapter_world.gd`)은 번역하지 않고 새 기능을 넣지 않는다.
- 검사는 `_local/` 아래 격리 경로만 쓴다. 사용자 폴더(`%APPDATA%\WitchMoira`)를 읽거나 쓰지 않는다. `settings.cfg`를 쓰는 검사도 격리 경로로 바꿔 쓴다(`Loc.configure(settings_path)`).
- 실행하지 않은 검사, 보지 않은 화면을 통과로 적지 않는다.

### T3-L0a — 번역 틀과 규칙(refactor-architect)

| 항목 | 내용 |
|---|---|
| 목적 | 새 화면이 처음부터 키로 쓸 수 있게 최소한의 틀을 만든다. 기존 화면 글은 건드리지 않는다 |
| 시작 조건 | 없음. 새 파일 위주라 다른 작업과 겹치지 않는다. `project.godot`은 이 작업만 고친다 |
| 만들 파일 | `chapter1/view/loc.gd`(class 없이 `preload`로 쓰는 정적 함수 모음 또는 자동 로드 하나 — 자동 로드를 쓰면 `project.godot`에 등록): `t(key, args={})`, `tn(key, n, args={})`, `num(i)`, `dec(f, digits)`, `pct(f)`, `josa` 처리(ko에서만, 2.5절), `set_locale(code)`, `locale()`, `font(role)`(L3 전에는 지금의 SystemFont를 그대로 돌려준다), 신호 `locale_changed`. `chapter1/i18n/ko.po`(헤더 + 예시 키 몇 개), `chapter1/i18n/en.po`(같은 키, 비워 둠 가능), `chapter1/i18n/locales.json`, `chapter1/i18n/README.ko.md`(키 규칙 2.2, 틀 규칙 2.5, 새 화면 규칙) |
| 고칠 파일 | `project.godot`(`internationalization/locale/translations`, `fallback`, 자동 로드를 쓰면 등록) |
| 건드리지 않을 파일 | `chapter_hud.gd`, `skill_tree_panel.gd`, `chapter_one.gd`, 코어 전부 |
| 검사 | 새 `chapter1/tests/test_loc.gd`(마커 `CHAPTER1_LOC_RESULT`): 키 번역, 빠진 키는 키 그대로, `{name}` 치환, `tn` 복수(en 1/2), 조사 처리 표(받침 있음/없음/ㄹ/숫자 0~9/라틴 끝), 다른 언어의 `|` 표기 거부, 천 단위 구분(ko·en·de 흉내), `set_locale`가 신호를 낸다 |
| 통과 기준 | `godot --headless --path . --script res://chapter1/tests/test_loc.gd` 통과. `python tools/dev/run_all.py` 전체 통과(골든 4건 불일치 0 — 코어를 건드리지 않으므로 불변이어야 한다). 게임을 `--chapter1-start --chapter1-quit-after=5`로 띄워 로그에 스크립트 오류 0 |

### T3-L0b — 글 없는 골든 해시와 문자열 검사 기준선(qa-perf)

| 항목 | 내용 |
|---|---|
| 목적 | 코어에서 글을 빼는 L1이 "진행은 그대로"임을 보일 수단을 먼저 만든다. 화면 글이 늘지 않게 기준선을 세운다 |
| 시작 조건 | 없음. `golden_core.gd`를 고치는 다른 작업이 없을 때 |
| 고칠 파일 | `chapter1/tests/golden_core.gd`: 인수 `--textless`를 더한다. 이때 해시 전에 스냅숏에서 문자열 필드 `name`, `title`, `description`, `rare_words`, `legacy_name`, `title_key`를 재귀로 지우고 해시한다. 결과는 기존 골든 파일이 아니라 `chapter1/tests/golden/core_runtime_textless.json`(새 파일)에 `--update`로 쓰고 비교한다. 기존 동작(인수 없을 때)은 바이트 하나 바꾸지 않는다 |
| 새 파일 | `tools/dev/i18n_scan.py`(한글 리터럴 수를 파일별로 세어 `tools/dev/i18n_baseline.json`과 비교. 늘면 실패), `tools/dev/i18n_baseline.json`(지금 값, 1.1절 표의 제품 파일들) |
| 고칠 파일 | `tools/dev/run_all.py`: 검사 `golden-textless`(느림 묶음), `i18n-scan`(빠른 묶음, Python) |
| 통과 기준 | (1) `golden_core.gd -- --textless --update`로 기준을 만들고, 바로 다시 `-- --textless`로 비교해 불일치 0. (2) **확인 실험**(작업 폴더 사본에서만, 커밋 금지): `chapter_core.gd:420`의 수호자 이름 하나를 바꾸면 기존 골든은 불일치, `--textless`는 일치함을 보이고 출력을 보고서에 붙인다. 되돌린다. (3) `run_all.py` 전체 통과 |

### T3-L1 — 코어가 글을 내지 않게(gameplay-systems)

| 항목 | 내용 |
|---|---|
| 목적 | 2.3절 표대로 코어의 결과·이벤트·오류에서 사람이 읽는 글을 빼고 id·키·숫자만 낸다. 1.3절의 "글에 기대는 로직" 두 곳을 없앤다 |
| 시작 조건 | L0a, L0b 끝. **디렉터가 코어 동결의 예외로 허락**(T3-D2). D6 A1(수치 시트, `combat_core.gd` `stat_sheet`)과 동시에 하지 않는다 — 같은 함수다. 권고: D6 A1을 먼저 끝내고 A1의 새 결과도 이 규칙으로 짓게 A1 지시서에 "label·unit 대신 id·unit_id"를 넣는다(T3-D3) |
| 고칠 파일 | `chapter1/core/chapter_core.gd`(ZONE_NAMES·RITUALS의 name·수호자 title·`objective()`·이벤트 name·빌드 오류), `chapter1/core/combat_core.gd`(`_row`의 label·unit, `effects`, STARTER 장비 이름), `chapter1/core/skill_tree.gd`(`describe_block_keys` 새로, 옛 `describe_block`은 L2까지 둠), `chapter1/core/run_growth.gd`(`effective_skill().name`, 카드 `title`), `chapter1/core/run_growth_quality37.gd`(이름 비교를 id·구조 비교로: 진화 이름은 비교하지 않고 "이름 외 같음"만 본다), `chapter1/core/chapter_profile.gd`(`error` → `error_code`·`error_args`, 옛 `error`는 개발용 영어 문장으로 남김), `chapter1/app/chapter_one.gd`(369행 비교를 `error_code`로, `profile.error`를 보이던 곳을 `Loc.t("profile.error."+code)`로 — **이 파일은 D4-A·D5-A와 동시에 하지 않는다**), 관련 검사(`test_chapter_run.gd`, `test_chapter_profile.gd`, `test_growth.gd`, `test_skill_tree.gd`의 한국어 기대값을 id 기대값으로) |
| 화면 쪽 | 코어 결과가 바뀌면 지금 화면이 그 글을 읽던 곳이 깨진다. **이 지시서 안에서 화면이 키를 번역하도록 최소 수정**(`chapter_hud.gd`·`skill_tree_panel.gd`·`chapter_world.gd`에서 해당 필드를 읽는 줄만, `Loc.t`로). `ko.po`에 그 키와 지금 한국어 원문을 넣어 화면 글이 바이트 단위로 같게 한다. ui-hud가 같은 파일을 만지는 중이면 시작하지 않는다 |
| 하지 않을 것 | 장비 사전의 `name`·`description` 빼기(L1은 스키마 3 그대로. 장비는 T3-S에서), 데이터 JSON 구조 변경, 수치 변경 |
| 골든 | 기존 골든은 **바뀐다**(수호자 title, 은총 카드 title이 빠짐). `--textless` 골든은 **불변이어야 한다**. 불변 확인 뒤에만 기존 골든을 `--update`하고, 보고서에 "글 필드 제거로 인한 의도한 변경, textless 4건 일치, 각 사례의 tick·kills·hp_raw·level 동일"을 적는다 |
| 통과 기준 | (1) `golden_core.gd -- --textless` 불일치 0. (2) 기존 골든 갱신 전후 `GOLDEN_CASE`의 mode·tick·kills 동일(출력 붙임). (3) 1.4절의 탐침과 같은 방식으로 `snapshot()`과 이벤트에 한글 0(보고서에 출력). (4) `run_all.py` 전체 통과. (5) `hud_dump.gd`로 냉기 시드 11 한 판을 L1 전후 덤프해 텍스트 컨트롤의 `text`가 같다(차이 0, 차이가 있으면 목록과 이유) |

### T3-S — 스키마 4의 장비 글 빼기(gameplay-systems, D6 S와 같은 지시서)

| 항목 | 내용 |
|---|---|
| 목적 | 2.4절. 저장과 판 안 장비 사전에서 `name`·`description`을 빼고 희귀를 `rare_words`로 |
| 시작 조건 | L1 끝. D6 S(스키마 4) 지시서에 **이 항목을 더해 한 번에** 한다(스키마를 두 번 올리지 않는다). D3 1.1의 서사 기록도 같은 스키마(디렉터 결정 D-1) |
| 고칠 파일 | `chapter1/core/loot.gd`(`roll_item`이 `rare_words`를 담음, `_compose`는 수치만, `dress`는 스키마 3 장비를 옮길 때만), `chapter1/core/chapter_profile.gd`(v3→v4 옮김, 2.4절 희귀 되찾기), `chapter1/data/loot.json`(`rare_names`를 id 객체 배열로 — content-balance와 함께, id는 narrative-lead 확인), `chapter1/core/chapter_core.gd`(`_bare_item` 키 목록), 검사 |
| 화면 | 장비 이름 짓기를 화면으로: 새 `chapter1/view/item_names.gd`(`name(item)`, `description(item)`, 2.5절 틀). 지금 `item.name`을 그리는 곳을 이것으로 바꾸는 일은 이 지시서 안에서 최소로(L1과 같은 방식, 한국어 화면 글 바이트 동일) |
| 골든 | 기존 골든 바뀜, textless 불변. L1과 같은 보고 |
| 통과 기준 | D6 S 통과 기준 + 옛 v3 고정 묶음(`fixtures/loot_compat_items.json`)을 v4로 옮긴 뒤 화면 이름(ko)이 옮기기 전 `dress` 결과와 같다. 희귀 되찾기 성공·실패(이름 바뀐 낱말, 세 낱말) 사례. 원본 v3 바이트 불변 |

### T3-L2 — 기존 화면 글을 키로 옮기기(ui-hud)

| 항목 | 내용 |
|---|---|
| 목적 | 화면 코드의 한글 리터럴을 0으로. `text.replace` 9곳을 없앤다. 조사 오류를 고친다 |
| 시작 조건 | **D4-U, D5-U, D6-A2(착용 창), A2 지시서 2-B·3-B·4·5, T1 지시서 4 R4가 모두 끝난 뒤**, 그리고 `chapter_hud.gd`·`skill_tree_panel.gd`·`chapter_one.gd`를 고치는 다른 지시서가 없을 때. L1 끝. 가능하면 L3(글꼴)도 끝난 뒤(넘침 판정이 글꼴에 달림) |
| 고칠 파일 | 파일 하나씩 차례로, 파일마다 검수: (1) `chapter1/view/world/chapter_world.gd`, `view/ui51/chapter_route51.gd`, `view/fx/chapter_effects.gd`(작은 것부터), (2) `chapter1/view/hud/skill_tree_panel.gd`, (3) `chapter1/view/hud/chapter_hud.gd`, (4) `chapter1/app/chapter_one.gd`(창 제목, 알림). `ko.po`에 원문 |
| 규칙 | 2.2·2.5·2.7절. 고정 폭(`custom_minimum_size.x`를 글 폭 때문에 준 곳)을 풀 때 1080p·720p 한국어 화면이 달라지면 캡처를 붙여 이유를 적는다. 조사 오류(1.2절)는 문장을 바꿔 고친다 |
| 하지 않을 것 | 배치·색·크기의 디자인 변경. 옛 층 파일 |
| 통과 기준 | (1) `i18n_scan.py` 화면 파일 한글 0(허용 목록 제외). (2) `hud_dump.gd` 기존 시점 전부에서 L2 전후 한국어 덤프의 `text` 차이가 "조사 고침"과 "의도한 문장 변경" 목록 밖에 0. (3) 가짜 언어 덤프(L4)에서 `Loc`을 거치지 않은 글 0. (4) `run_all.py` 전체 통과, 골든 불변(표현만 고침) |

### T3-L3 — 글꼴(ui-hud, 내려받기는 L-U2 승인 뒤)

| 항목 | 내용 |
|---|---|
| 목적 | 시스템 글꼴을 게임에 넣은 공개 글꼴로 바꾸고 언어별 체인을 만든다 |
| 시작 조건 | 사용자 승인 L-U2(=A3). `chapter_hud.gd`의 글꼴 줄을 고치므로 다른 ui-hud 작업과 차례로 |
| 단계 | (a) 2.6절 라이선스 확인 절차 → `chapter1/art/fonts/` + `FONTS.ko.md`. (b) `Loc.font(role)`가 언어별 체인을 돌려주게 하고, `chapter_hud.gd`·`skill_tree_panel.gd`·`chapter_effects.gd`의 `SystemFont` 5곳과 `Label3D`·`draw_string`·프로젝트 기본 글꼴을 이것으로. (c) 글자 덮음 검사 `tools/dev/check_glyphs.py`(qa-perf가 만들어도 됨): 출시 언어 `.po`와 데이터 JSON의 모든 글자가 그 언어 체인의 어느 글꼴에 있는지 fonttools로 확인, 빠진 글자 목록 |
| 통과 기준 | `SystemFont` 0건(옛 층 제외). `check_glyphs.py` 빠진 글자 0. 1080p·720p 한국어 캡처(메뉴, 판, 은총, 결과, 보관함, 트리)를 사람 검수(art-lead)용으로 `_local/shots/t3-font/`에. 글꼴 파일 합 용량을 보고(부분 집합 전·후) |

### T3-L4 — 가짜 언어와 넘침 검사(qa-perf)

| 항목 | 내용 |
|---|---|
| 목적 | 2.7절의 자동 넘침 검사 |
| 시작 조건 | L0a. 전체 효과는 L2 뒤에 나지만 도구는 먼저 만들 수 있다 |
| 고칠 파일 | `chapter1/tests/hud_dump.gd`(선택 인수 `--locale=`, `--pseudo`, `--pseudo-expand=`; `_describe`에 `text_w`, `lines`, `clipped`, `offscreen`, `overlap`. 기존 출력 키는 바꾸지 않고 더하기만), 새 `tools/dev/check_overflow.py`, `tools/dev/overflow_allow.json` |
| 통과 기준 | 같은 시드·시점으로 `--pseudo --pseudo-expand=1.4` 덤프와 캡처(1080p, 720p)를 만들고 `check_overflow.py` 결과를 보고. 첫 실행은 실패 목록이 나오는 것이 정상이다 — 목록을 L2·새 화면 담당에게 넘길 형태(파일:줄 추정, 키 또는 글)로 낸다. 일부러 고정 폭 라벨에 긴 글을 넣은 작은 장면(`chapter1/tests/fixtures/overflow_probe.tscn`)에서 검출되는 것을 보인다 |

### T3-L5 — 언어 선택과 설정 파일(ui-hud 화면, gameplay-systems 설정 저장)

| 항목 | 내용 |
|---|---|
| 목적 | 2.8절 |
| 시작 조건 | L0a. 설정 화면 명세(G5, design-lead)가 있으면 그 안에, 없으면 메뉴에 언어 단추 하나. 1차 언어(en)의 번역이 일부라도 들어온 뒤 |
| 파일 | `chapter1/view/loc.gd`(설정 읽기·쓰기, 스팀 언어 이름 대응표), 메뉴 화면(`chapter_hud.gd`의 메뉴 부분 — 다른 ui-hud 작업과 차례로), `chapter1/tests/test_loc.gd`(격리 경로의 설정 파일로 첫 실행 순서·저장·지원 안 하는 언어 `en` 처리) |
| 통과 기준 | 검사 통과. 메뉴에서 en↔ko 바꿔 HUD가 다시 지어지는 캡처 두 장. 스팀 없이(GodotSteam 없음) 실행해도 오류 0 |

### T3-L6 — 번역 관리 도구와 `run_all` 검사(manager-tools)

| 항목 | 내용 |
|---|---|
| 목적 | 2.9절의 추출·검사·관리 툴 화면 |
| 시작 조건 | L0a(키 규칙과 `ko.po` 형식이 정해진 뒤) |
| 만들 파일 | `tools/dev/i18n_extract.py`, `tools/dev/i18n_check.py`(2.9의 검사 1~5), `tools/manager/`의 「번역」 화면과 백엔드, `tools/manager/test_*.py`에 검사 |
| 고칠 파일 | `tools/dev/run_all.py`(검사 `i18n`). L0b가 같은 파일을 고치므로 L0b 뒤에 |
| 통과 기준 | `python tools/dev/i18n_check.py` 지금 상태 통과. 일부러 깨뜨린 사본(`_local/` 아래: 빠진 키, 자리 표시자 다름, en의 조사 표기, 상한 넘김)에서 각각 실패. `run_all.py --quick`에 들어감. 관리 툴 검사 통과 |

### T3-L7 — 1차 영어 번역 넣기(디렉터 → 번역 주체, 검수 narrative-lead·content-balance)

시작 조건: L2 끝, 용어집, L-U3. 통과 기준: `i18n_check.py`에서 en이 `shipping`으로 통과, 가짜 언어와 en 넘침 검사 실패 0, en 캡처 전 화면 사람 검수.

---

## 4. 순서와 다른 지시서와의 관계

```
L0a(refactor-architect) ─┬─ L0b(qa-perf) ── L6(manager-tools)
                         ├─ L4 도구(qa-perf)
                         └─ L5 틀(뒤로 미뤄도 됨)
  [규칙] D4-U · D5-U · D6-A2(착용 창) · 새 화면 전부: 처음부터 Loc.t + ko.po
L1(gameplay-systems) ← L0a·L0b, 디렉터의 코어 동결 예외, D6 A1 뒤
T3-S = D6 S에 포함 ← L1
L3 글꼴(ui-hud) ← 사용자 L-U2. 다른 ui-hud 작업과 차례로
L2(ui-hud) ← D4-U·D5-U·D6-A2·A2 2-B 등 화면 묶음 끝 + L1 (+ 가능하면 L3)
L7 영어 ← L2, L6, 용어집
```

**화면 파일 순서에 대한 분명한 권고**
- `chapter_hud.gd`를 큰 폭으로 고치는 L2를 지금 하면 D4-U·D5-U·D6-A2·A2의 모든 작업과 충돌한다. 그렇다고 그 작업들이 끝날 때까지 기다리며 한국어 리터럴을 계속 더하면 L2가 커진다.
- 그래서 **L0a를 지금 바로 한다(새 파일뿐이라 누구와도 충돌하지 않는다).** L0a가 끝난 날부터 D4-U·D5-U·D6-A2와 모든 새 화면 지시서에 다음 한 줄을 넣는다: "새로 쓰는 화면 글은 `Loc.t(key)`로 쓰고 원문을 `chapter1/i18n/ko.po`에 더한다. 자리 표시자는 `{이름}`, 자리 표시자 뒤에 조사 금지, 글 폭 고정 금지(T3 2.5·2.7절). 기존 글을 옮기는 일은 하지 않는다(L2의 몫)." 새 착용 창은 별도 파일(`equipment_window.gd`)이라 처음부터 깨끗하게 짓기 쉽다.
- L0b의 기준선 검사가 "화면 파일의 한글 리터럴이 늘면 실패"이므로, 이 규칙은 검사로 지켜진다.
- L2는 그 화면 묶음이 끝난 뒤 한 번에, 파일 하나씩 한다. 이때 `chapter_hud.gd`를 만지는 다른 작업은 배정하지 않는다(약 2~3일 창, 어림).
- T2(성능)와는 파일이 거의 겹치지 않는다(`actors`, `fx` 쪽). 다만 T2-0b·T2-V 측정 창 동안에는 같은 컴퓨터에서 Godot 캡처를 돌리지 않는다(L1·L2·L3·L4의 캡처 단계).

| 파일 | T3 단계 | 겹치는 것 | 규칙 |
|---|---|---|---|
| `project.godot` | L0a | T4-B(내보내기 설정, 창·아이콘) | L0a 먼저, T4-B는 그 뒤 |
| `chapter1/tests/golden_core.gd` | L0b | 없음 | — |
| `tools/dev/run_all.py` | L0b → L6 | T4-Q(빌드 검사) | 차례로 |
| `core/combat_core.gd` `stat_sheet` | L1 | D6 A1 | A1 먼저, A1이 id·unit_id 규칙으로 |
| `core/chapter_core.gd` | L1, S | D2 K2~K3, D6 E·F, D4-K | 동시 금지 |
| `core/chapter_profile.gd`, `loot.gd`, `loot.json` | L1(오류 코드), S | D6 S·C, D5 2단계 | S는 D6 S와 같은 지시서 |
| `app/chapter_one.gd` | L1(최소), L2 | D4-A, D5-A, T1 R1·R4 | 동시 금지 |
| `view/hud/chapter_hud.gd`, `skill_tree_panel.gd` | L1(최소), L3, L5, L2 | D4-U, D5-U, D6-A2, A2, T1 R4 | 동시 금지. L2는 마지막 |
| `chapter1/tests/hud_dump.gd` | L4 | D4·D5·D6의 선택 인수 추가 | 더하기만, 차례로 |

## 5. 위험

| 위험 | 대응 |
|---|---|
| L1의 최소 화면 수정이 한국어 화면 글을 바꿈 | L1 통과 기준 (5): 전후 덤프 `text` 비교 |
| 코어에서 글을 빼다가 진행을 바꿈 | textless 골든(L0b)이 불변이어야만 기존 골든 갱신 |
| 키 기반이라 번역가가 맥락을 모름 | `.po` 주석에 원문·자리 표시자 뜻·캡처 경로·상한 |
| 글꼴 용량 | 부분 집합(빌드 때). 출시 언어만 넣기 |
| 부분 집합이 OFL RFN 조항에 걸림 | 글꼴마다 원문 확인, 판단 안 서면 사용자에게 |
| 장비 이름의 문법적 성(3차 언어) | 2.5절의 확장 자리만 열어 두고 3차 때 설계 |
| 옛 희귀 이름 되찾기 실패 | `legacy_name` 보관, L-U5 |
| 화면이 이미 번역된 글을 다시 번역(자동 번역) | HUD 뿌리에서 자동 번역 끔, 명시 호출만 |

## 6. 디렉터가 정할 것

| # | 결정 | 권고 |
|---|---|---|
| T3-D1 | 장비 글 빼기(T3-S)를 D6 S(스키마 4)와 한 지시서로 | 한 지시서. 스키마를 한 번만 올린다 |
| T3-D2 | L1을 코어 동결의 예외로 허락 | 허락. 진행 불변을 textless 골든으로 보이는 조건 |
| T3-D3 | D6 A1 지시서에 "능력치 줄은 label·unit 대신 id·unit_id" 한 줄 추가 | 추가. A1이 L1보다 먼저 가므로 두 번 고치지 않게 |
| T3-D4 | L0a 직후부터 모든 새 화면 지시서에 키 규칙 한 줄을 넣기 | 넣는다(4절 문구 그대로) |
| T3-D5 | 데이터 글의 원문을 JSON에 둘지(권고) / `ko.po`로 옮길지 | JSON. 데이터 담당과 관리 툴의 흐름을 바꾸지 않는다 |
| T3-D6 | `Loc`을 자동 로드로 둘지 / `preload` 정적 모듈로 둘지 | 자동 로드(언어 바뀜 신호와 설정 파일을 한 곳에서). 검사 스크립트(`extends SceneTree`)에서는 자동 로드가 없으므로 `preload` 정적 함수도 함께 둔다 — 구현자가 정하고 이유를 적는다 |

## 7. 확인하지 못한 것

- Godot 4.5.1의 PO 복수형·문맥, 가짜 언어 설정 이름, `auto_translate_mode`, `Font.allow_system_fallback`, `.otc`(글꼴 모음) 읽기를 4.5.1 문서나 실행으로 확인하지 않았다(기억에 의존). L0a·L3·L4 구현자가 확인한다.
- 글꼴 라이선스 원문과 RFN, 용량을 보지 않았다(내려받지 않음).
- 스팀 사용자 언어 비중의 실제 숫자(웹 조사 안 함).
- `growth.json`, `growth_quality36.json`, `growth_quality37.json` 가운데 실행에서 실제로 읽는 것이 어느 것인지 끝까지 따라가지 않았다(`run_growth_quality37.gd`가 q37을 읽는 것만 확인). L1 구현자가 확인한다.
- 옛 층 `cloister_hud.gd`의 글이 실행 중 화면에 나오는지 확인하지 않았다(preload만 된다고 알려져 있다. T1 지시서 4).
- 은총 카드 제안(`growth.offer`)이 골든 체크포인트 순간에 열려 있는 경우는 이번 탐침에서 잡히지 않았다. 코드로만 판단했다.

## 8. 직접 실행한 것

- 임시 스크립트(세션 작업 폴더의 `count_ko.py`, 저장소 밖): 1.1절의 개수.
- `Godot_v4.5.1-stable_win64_console.exe --headless --path . --script res://_local/t3-probe/snapshot_text_probe.gd`: 1.4절 출력(냉기 victory 25,005틱, 번개 victory 20,697틱, 한글 경로 7개). 제품 코드는 고치지 않았다. 탐침 스크립트는 `_local/`에 있다.
- Grep: 조사 조립, `text.replace`, 고정 폭, 글꼴, 저장 키, 오류 비교 줄(본문의 파일:줄).
