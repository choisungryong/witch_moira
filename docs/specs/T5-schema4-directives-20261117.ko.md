# 기술 지시서 T5 — 저장 스키마 4

2026-11-17, 기술 책임자(tech-lead) 작성. 총괄 디렉터가 배정한다. 14절의 지시서는 받는 에이전트에게 그대로 넘길 수 있게 썼다. 받는 쪽은 이 문서와 여기 적힌 파일만 보고 일할 수 있어야 한다.

근거: `CLAUDE.md`, `chapter1/core/chapter_profile.gd`, `chapter1/core/loot.gd`, `chapter1/core/chapter_core.gd`, `chapter1/app/chapter_one.gd`, `chapter1/tests/test_chapter_profile.gd`, `docs/specs/D5-save-safety-spec.ko.md`, `docs/reviews/TECH-REVIEW-D5-20261117.ko.md`, `docs/specs/G1-permanent-growth-spec.ko.md` 6절, `docs/specs/T3-localization-directives-20261117.ko.md` 2.4·2.8절과 T3-S, `docs/specs/D6-loot-farming-spec.ko.md` 8·10절, `docs/specs/D3-story-systems-requirements.ko.md`, `docs/story/ACT-STRUCTURE.ko.md`·`CHAPTER1-TEXT-PLAN.ko.md` 6절·`FORESHADOW-MAP.ko.md` N20·N22·N23, `docs/specs/A4-ui-redesign-direction.ko.md` 4.2절, `docs/specs/T4-steam-release-directives-20261117.ko.md` 3.5절, `docs/reviews/DECISIONS-PENDING-20261117.ko.md` 2.8·2.13절.

표기: [확인]은 코드를 읽었거나 직접 실행한 것, [추정]은 읽은 것에서 미루어 본 것, [미확인]은 확인하지 못한 것.

---

## 디렉터용 요약

1. 스키마 4는 새 파일 `user://chapter-one-profile-v4.json`이다. v3·v2·v1 파일과 그 기록본, v3 가리키는 파일은 **읽기만 하고 한 바이트도 쓰지 않는다.** 첫 정상 저장이 v4 파일을 만든다(v2→v3 때와 같은 길).
2. 장비에서 `name`·`description`을 뺀다. 희귀 이름은 낱말 id 두 개(`rare_words`)로 저장하고, 옛 이름에서 되찾지 못하면 원문을 `legacy_name`에 보관한다. **저장 파일에는 화면 글이 들어가지 않는다**(예외: `legacy_name`, 옛 v1 장비, 격리 보관한 원본).
3. 최상위 `equipped`를 없애고 마녀마다 `loadout`을 둔다(L4). 판이 끝나 저장할 때 그 판에서 바꿔 낀 장비를 그 마녀의 `loadout`에 넣는다(L5). 옮길 때 기존 한 묶음은 **세 마녀 모두에게 복사**하기를 권한다. 그러면 옮긴 뒤 첫 판의 출발 장비가 지금과 같다.
4. 마녀마다 `wardrobe: {owned, worn}`(의상), `story: {found, seen, duel_cleared, final_cleared}`(수집품·본 사건·결전), `depth_cleared`(균열 깊이). 최상위에 `codex`, `gambles`, `shared_story`(공통 장면을 어느 마녀로든 봤는가, 진 엔딩), `quarantine`(읽지 못한 것을 버리지 않고 보관), `origin`(어디서 옮겨 왔는가). 막 진행은 저장하지 않고 첫 처치 영수증에서 계산한다.
5. 검증을 세 갈래로 나눈다. **거부**는 파일 구조가 깨졌을 때만(JSON, 크기, 스키마 번호, 키 집합, id 중복). 장비 하나가 지금 데이터와 안 맞으면 파일 전체를 거부하지 않고 그 장비만 `quarantine`에 원본 그대로 옮겨 둔다(데이터가 돌아오면 되살린다). 모르는 의상·수집품·사건 id는 그 자리에 **보존**하고 화면만 무시한다. 쓸 때는 지금처럼 엄격하다.
6. 기록본은 하위 폴더 `revisions/`에 쓰고, 보존 규칙(최근 20개 + 최근 7일 하루 하나 + 옮긴 직후 하나)으로 지운다. 지우는 코드는 함수 하나, 정규식에 맞는 이름만, 저장 한 번에 10개까지. 따로 된 지시서(S3)로 검수한다.
7. 흔들림·음량·음소거·해상도·언어 같은 설정은 프로필이 아니라 `user://settings.cfg`(이미 언어가 거기 있다)로 간다. 프로필이 거부돼도 설정은 남고, 클라우드에 올리지 않는다.
8. 골든: 프로필과 앱만 바뀌는 단계(S1, S3)는 골든·글 없는 골든·드랍 시뮬레이션이 **그대로여야 한다.** 판 안 장비 사전에서 글을 빼는 단계(S2 = T3-S의 코어 부분)만 기존 골든이 바뀌고 글 없는 골든은 그대로여야 한다. 골든·전투 측정·드랍 도구는 프로필을 읽지 않으므로 L5가 그 출발 조건을 바꾸지 않는다. 이것을 정적 검사로 묶어 둔다.
9. 구현 단위: S0 옛 저장 고정 묶음(qa-perf, **지금 바로**, 코드 변경 전에 반드시) · M0 관리 툴의 희귀 낱말 형식(manager-tools, 지금 바로) · S1 프로필 v4 + 앱 연결(gameplay-systems, T3-L1 뒤) · S2 판 안 장비 글 빼기(gameplay-systems, S1 뒤) · S3 기록본 보존(gameplay-systems, S1 뒤, 결정 T5-D3 뒤) · Q1 독립 검사(qa-perf, S1 뒤).
10. 정할 것: 사용자 5건, 디렉터 9건(17절). 가장 급한 것은 T5-U1(공용 묶음을 누구에게), T5-U2(한 장비를 여러 마녀가 낄 수 있나), T5-D1(장비 검증 실패를 거부 대신 격리).

---

## 1. 지금의 저장 [확인]

| 항목 | 지금 | 위치 |
|---|---|---|
| 파일 | 본 `user://chapter-one-profile-v3.json`, 읽기만 `-v2`·`-v1`, 가리키는 파일 `chapter-one-profile-active.json`, 거부 뒤 새 저장 `chapter-one-profile-v3-r<시각>[-n].json` | `chapter_profile.gd:14-18` |
| 기록본 | 저장마다 본 파일 옆에 `<바탕>.revision-<rev6>-<pid>-<usec>.json`, 임시 `<바탕>.next-….json`. **지우지 않는다** | `:413-427` |
| 키 검사 | 최상위·마녀·장비 키를 **정확히** 맞춘다(`keys_match`). 새 키 하나면 옛 실행본이 파일 전체를 거부한다 | `:278`, `:295`, `:340`, `:352` |
| 장비 글 | `name`·`description`을 저장한다. 읽을 때 `loot.dress()`가 지금 데이터로 다시 짓되 희귀 이름은 저장된 글 그대로 | `:316`, `loot.gd:310-324` |
| 희귀 이름 | `rare_names.first`·`second`(각 10개, 문자열)에서 하나씩 뽑아 공백으로 잇는다. 낱말에 공백이 없고 두 목록이 겹치지 않는다(직접 셈) | `loot.gd:194`, `loot.json:73` |
| 장비 한 개 실패 | 프로필 전체 거부(`incompatible`) | `:312-314` |
| 착용 | 최상위 `equipped` 하나를 세 마녀가 함께 쓴다. `record_run`은 `equipped`를 바꾸지 않는다 → 판에서 바꿔 낀 장비는 이어지지 않는다 | `:431-454`, `:498-507` |
| 출발 장비 | 요구 레벨이 그 마녀의 영구 레벨보다 높은 것은 선택은 남기고 출발에서 뺀다(`blocked_gear`). 코어는 받은 장비를 레벨과 무관하게 낀다 | `:498-519`, `chapter_core.gd:649-665` |
| 판 안 착용 | 요구 레벨을 `max(판 레벨, 영구 레벨)`로 본다. 그래서 판에서 낀 장비가 영구 레벨보다 높을 수 있다 | `chapter_core.gd:644-647` |
| 마녀 항목 | 키 다섯(`xp, tree_revision, ranks, first_rewards, respecs`). 그 마녀로 처음 판을 마칠 때 생긴다. 세 개 이하 | `:23`, `:341` |
| 첫 처치 포인트 | 모르는 보상 id는 포인트 계산에서 무시된다 | `character_progression.gd:118-126` |
| 옛 v1 장비 | `chapter_items.gd`의 `validate`가 이름·설명까지 비교한다(데이터가 고정이라 안전) | `chapter_items.gd:82-124` |
| 설정 | 언어만 `user://settings.cfg`(`Loc`). 음소거(M 키)·음량은 저장하지 않는다 | `view/loc.gd:12,103-130`, `app/chapter_one.gd:86,163-165` |
| 검사 격리 | `run_all.py`·`tools/dev/godot.py`가 `APPDATA`를 `_local/appdata/<용도>/`로 바꾼다. 직접 실행: `OS.get_user_data_dir()` = `C:/Project/witch-moira/_local/appdata/godot/WitchMoira` | `tools/dev/isolated_env.py`, 19절 |
| 회귀 | `run_all.py --only profile,loot,app-guard`: profile 115, loot 36, app-guard 5 검사 실패 0(오늘 직접 실행) | 19절 |

---

## 2. 원칙

1. **옛 파일은 읽기만 한다.** v4 실행본은 v3 시대의 파일(본, r-파일, 기록본, 가리키는 파일)과 v2·v1을 열어 읽기만 하고, 쓰기·이름 바꾸기·지우기를 하지 않는다. 지우는 코드(S3)는 v4 기록본만 대상으로 한다.
2. **사실만 저장하고 계산할 수 있는 것은 저장하지 않는다.** 레벨·포인트(지금처럼), 막 진행(첫 처치 영수증에서), 5막 입장(마녀별 `duel_cleared`에서), 이름(id에서).
3. **저장 파일에 화면 글을 넣지 않는다.** id·숫자·참거짓만. 예외 셋: 되찾지 못한 옛 희귀 이름 `legacy_name`, 옛 v1 장비(형식 동결), `quarantine`의 원본.
4. **읽기는 너그럽게, 쓰기는 엄격하게.** 읽을 때 고칠 수 있는 것은 고쳐 메모리에만 두고(파일은 다음 정상 저장 때 바뀐다), 버려야 할 것은 버리지 않고 `quarantine`에 둔다. 쓸 때(`_persist`)는 모든 규칙을 엄격하게 본다. **읽은 결과는 항상 엄격한 쓰기 검사를 통과해야 한다**(검사로 지킨다).
5. **새로 더하는 것은 엄격, 이미 있는 것은 보존.** 의상·수집품·사건 id를 새로 더하는 함수는 데이터에 있는 id만 받는다. 이미 저장된 id는 데이터에서 사라져도 지우지 않는다.
6. **스키마 4 안에서는 키를 더하지 않는다.** 키가 바뀌면 스키마 5다. 그래서 필요한 자리를 이번에 한 번에 연다(아직 쓰지 않는 자리도 기본값으로).

---

## 3. 파일 이름과 위치

| 파일 | 이름 | 누가 쓰나 | 비고 |
|---|---|---|---|
| 본 | `user://chapter-one-profile-v4.json` | `_persist` | |
| 거부 뒤 새 저장 | `user://chapter-one-profile-v4-r<YYYYMMDD-HHMMSS>[-n].json` | `start_fresh_after_reject` | 이름 규칙 `^chapter-one-profile-v4-r[0-9-]+\.json\z`. 이미 있는 이름은 건너뛴다(D5와 같음) |
| 가리키는 파일 | `user://chapter-one-profile-v4-active.json` | `_write_pointer` | **v3의 `chapter-one-profile-active.json`과 따로 둔다.** v4 실행본은 v3 가리키는 파일을 읽기만 한다(옮겨 올 원본을 찾을 때). v4 가리키는 파일은 v4 이름 규칙만 따라간다 |
| 기록본 | `user://revisions/<본 바탕>.revision-<rev6>-<YYYYMMDD>-<pid>-<usec>.json` | `_persist` | **하위 폴더**(결정 T5-D4). 이름에 날짜를 넣어 보존 규칙이 파일 시각에 기대지 않게 한다 |
| 임시 | `user://chapter-one-profile-v4.json.next-<stamp>.tmp` | `_persist` | 본 파일과 같은 폴더(바꿔 끼우기). 끝이 `.tmp`라 `*.json` 패턴에 걸리지 않는다 |
| 설정 | `user://settings.cfg` | 설정 모듈(11절) | 프로필과 무관 |

- 자동 클라우드(T4 3.5)를 쓰면 대상 패턴은 `chapter-one-profile-v4*.json`(본, r-파일, 가리키는 파일)이 된다. 기록본은 하위 폴더, 임시는 `.tmp`라 겹치지 않는다. 스팀 자동 클라우드 패턴의 정확한 문법(하위 폴더 포함 여부)은 [미확인]이다. T4-C가 확인한다.
- QA 모드: 모든 경로는 `res://_local/` 아래여야 한다(지금 규칙 그대로, `chapter_profile.gd:83-88`). 기록본 폴더도 본 파일 경로에서 만들므로 같은 아래에 생긴다.

---

## 4. 스키마 4 필드

"쓰는 곳"은 프로필의 공개 함수, "읽는 곳"은 그 값을 쓰는 쪽이다. 화면(view)은 프로필이 앱을 거쳐 넘긴 사본만 읽는다.

### 4.1 최상위(키 집합은 정확히 이것)

| 키 | 형 | 기본값 | 쓰는 곳 | 읽는 곳 | 검증 |
|---|---|---|---|---|---|
| `schema_version` | int | 4 | `_persist` | `configure` | 정확히 4. 아니면 거부 |
| `revision` | int | 0 | `_persist`(+1) | 기록본 이름, 이어 하기 | 0~10억 |
| `next_id` | int | 1 | `record_run`, 도박(D6-C) | 새 장비 번호 | 1~10억, `items`·`quarantine`의 모든 `storage_id`보다 크다. 아니면 거부 |
| `items` | 배열 | `[]` | `record_run`, `salvage`, 도박 | 보관함, 출발 장비, 착용 창 | 4.2절. 325개 이하(지금 `MAX_ITEMS`) |
| `completed_runs` | int | 0 | `record_run` | 첫 처치 판정 대체(마녀 없을 때), 통계 | 0~10억 |
| `best_ticks` | int | 0 | `record_run` | 결과 화면 | 0~10억 |
| `essence` | int | 0 | `salvage`, `respec`, 도박 | 화면 | 0~10억 |
| `receipts` | 문자열 배열 | `[]` | `record_run` | 중복 지급 방지 | 64개 이하, 각 1~120자(지금 그대로) |
| `characters` | 사전 | `{}` | 4.4절 함수들 | 4.4절 | 키는 데이터의 마녀 id. 모르는 id는 `quarantine`(6절) |
| `codex` | 사전 `{uniques, legendaries, set_pieces}` | 모두 `[]` | `record_run`, 도박(처음 얻은 고유·전설·세트) | 도감 화면(D6) | 각 64개 이하, 각 원소는 id 형식(4.7) |
| `gambles` | int | 0 | 도박(D6-C) | 통계, 시뮬레이션 대조 | 0~10억 |
| `shared_story` | 사전 `{seen, true_ending}` | `{"seen":[],"true_ending":false}` | `mark_shared_seen`, 결전 뒤(나중) | 공통 장면 넘기기(N22), 진 엔딩(D3 8절) | `seen` 64개 이하 id 형식, `true_ending` bool |
| `quarantine` | 배열 | `[]` | 읽기 고침(6절)과 그 뒤 `_persist` | 되살리기, 지원 문의 | 4.6절. 325개 이하 |
| `origin` | 사전 `{from_schema, from_file, from_revision, at_unix}` | `{0,"",0,만든 시각}` | 첫 v4 저장 때 한 번 | 지원 문의, 이어 하기 안내 | `from_schema` 0~4, `from_file` 0~120자 파일 이름만(경로 금지), 나머지 int |

없어지는 키: `equipped`(마녀별 `loadout`으로).

### 4.2 장비 기록 `items[]`

| 키 | 형 | 기본값 | 검증 |
|---|---|---|---|
| `storage_id` | int | — | 1~10억, `items`·`quarantine` 전체에서 중복 없음(중복이면 거부) |
| `item` | 사전 | — | 4.3절. 실패하면 이 기록을 `quarantine`으로(6절) |
| `locked` | bool, 참일 때만 둔다 | 없음 | 해체 잠금(D6 7.7). 값이 `true`가 아니면 지우고 읽는다 |
| `new` | bool, 참일 때만 | 없음 | "새 장비" 배지(D6 I8). 같은 규칙 |

### 4.3 장비 `item`

**문법 2 장비**(키 `grammar`가 있는 것). 키 집합은 정확히 아래(대괄호는 조건부).

| 키 | 형 | 검증 |
|---|---|---|
| `grammar`, `base_id`, `slot`, `stats`, `quality`, `item_level`, `affixes`, `required_level` | 지금과 같음 | 지금 `loot.validate`의 정체 검사 그대로(D5 N1) |
| `[legendary_id]` | 문자열 | 지금과 같음 |
| `[rare_words]` | `["<첫 낱말 id>", "<둘째 낱말 id>"]` | 등급이 희귀일 때만, `legacy_name`과 둘 중 하나만. 형식만 본다(각 id 형식, 길이 2). **데이터에 없는 낱말 id여도 장비는 통과한다**(이름은 겉모습이다. 화면이 대체 이름을 쓴다) |
| `[legacy_name]` | 문자열 | 희귀일 때만. 옮길 때 되찾지 못한 옛 이름. `loot._check_text`의 이름 규칙(1~160자, 한 줄, 제어·방향 문자 금지) |
| `[veiled]` | `true` | 흐린 장비(D6-B). 참일 때만 둔다. D6-B 전에는 쓰는 곳이 없다 |

- `name`, `description`이 있으면: **고쳐 읽기**(지우고 읽는다, 보고 항목 `stripped_text`). 쓸 때는 있으면 거부.
- 등급 `set`과 세트 조각(`chapter1.full.set.<piece>`)은 데이터가 생기면(D6-D) 같은 경로로 통과한다. 스키마 키는 그대로다.

**옛 v1 장비**(`grammar` 없음): 형식을 바꾸지 않는다. 키도 지금(`ITEM_KEYS` 8개, 이름·설명 포함) 그대로이고 `chapter_items.gd`로 검증한다. 화면은 T3 2.4절의 `item.v1.*` 키로 이름을 짓는다.

### 4.4 마녀 항목 `characters.<id>`(키 집합은 정확히 이것)

| 키 | 형 | 기본값 | 쓰는 곳 | 읽는 곳 | 검증 |
|---|---|---|---|---|---|
| `xp`, `tree_revision`, `ranks`, `first_rewards`, `respecs` | 지금과 같음 | 지금과 같음 | 지금과 같음 | 지금과 같음 | 지금과 같음. 다만 `ranks` 위반과 `first_rewards`의 모르는 id는 6절의 고쳐 읽기·보존 |
| `loadout` | 사전 `{칸: storage_id}` | `{}` | `select_item`, `unselect`, `salvage`(모든 마녀에서 뺌), `record_run`(L5) | 출발 장비, 착용 창, 메뉴 | 칸은 8칸 이름. 값은 `items` 또는 `quarantine`에 있는 `storage_id`. 칸과 장비 종류가 맞음(`ring2`는 반지). 한 마녀 안에서 같은 장비가 두 칸에 없음. 마녀 사이 공유는 T5-U2 |
| `depth_cleared` | 사전 `{던전 id: 0~3}` | `{}` | 균열 깊이(D6-E) 승리 저장 | 깊이 고르기 | 키 `^d[0-9]{1,2}$`, 16개 이하. 사전으로 두는 이유는 T5-D9 |
| `wardrobe` | 사전 `{owned, worn}` | `{"owned":[],"worn":""}` | `grant_outfit`, `wear_outfit` | 캐릭터 선택 의상 칸(A4 U4), 메뉴·착용 창 초상, 3D 표현 | `owned` 64개 이하 id 형식, 중복 없음. `worn`은 `""`(기본 복장) 또는 id 형식 |
| `story` | 사전 `{found, seen, duel_cleared, final_cleared}` | `{"found":[],"seen":[],"duel_cleared":false,"final_cleared":false}` | `record_run`(수집품, 판 요약의 `collectibles_found`), `mark_story_seen`(사건 화면을 본 뒤), 결전(나중) | 수집품 화면, 사건 화면 한 번만, 결전 뒤 기억 위 겹침(N23), 5막 입장(D3 8절) | `found`·`seen` 각 128개 이하 id 형식, 중복 없음. 나머지 bool |

- 마녀 항목은 v4에서 **세 마녀 모두** 둘 수 있다(옮길 때 `loadout`을 주려면 필요). 기본값만 든 항목도 받는다.
- 지금 쓰지 않는 자리(`depth_cleared`, `story.duel_cleared`, `final_cleared`, `codex`, `gambles`, `veiled`, `locked`)는 기본값으로 쓰고 읽기만 한다. 채우는 일은 각 기능의 지시서(D6-B·C·D·E, D3 수집품)가 한다.

### 4.5 의상 데이터(새 파일 `chapter1/data/outfits.json`)

```json
{"schema_version": 1,
 "outfits": [
   {"id": "chapter1.outfit.frost.swim_1", "character_id": "chapter1.character.frost", "default_owned": true, "art": {}},
   {"id": "chapter1.outfit.frost.swim_2", "character_id": "chapter1.character.frost", "default_owned": true, "art": {}}
 ]}
```
- 마녀마다 기본 복장은 데이터에 두지 않는다(`worn == ""`). 첫 컬렉션은 마녀마다 두 벌, 여섯 줄. id는 한 번 정하면 바꾸지 않는다(T5-D5). `art`(초상·3D 경로)는 A4 U4·character-artist가 채운다. 이름 글은 `ko.po`의 `outfit.<id>.name` 키(T3 2.2 규칙)로, 데이터에 한국어를 두지 않는다.
- 가진 의상 = 데이터의 `default_owned: true`인 것 ∪ `wardrobe.owned`. 그래서 처음부터 주는 의상은 저장에 쓰지 않는다.
- 의상은 능력치가 없다. 코어와 골든에 들어가지 않는다(표현만).

### 4.6 격리 보관 `quarantine[]`

| 키 | 형 | 검증 |
|---|---|---|
| `kind` | `"item"` 또는 `"character"` | 그 밖이면 거부 |
| `storage_id` | int(`item`일 때만) | `items`와 겹치지 않음 |
| `id` | 문자열(`character`일 때만) | 0~120자 |
| `reason` | 문자열 | 1~120자, 영어 짧은 사유(예: `"unknown base"`, `"stats mismatch"`). 장비 이름을 넣지 않는다 |
| `since_revision` | int | 옮긴 리비전 |
| `raw` | 아무 JSON | 원본 그대로. 직렬화해 8,000자 이하 |

- 파일 전체 상한(200만 자)은 그대로다. `quarantine`이 325개를 넘으면 거부한다(그 정도면 데이터가 크게 바뀐 것이고, 조용히 넘기면 안 된다).
- 읽을 때마다 `item` 항목을 지금 데이터로 다시 검사해, 통과하면 같은 `storage_id`로 `items`에 되살린다(보고 항목 `restored_items`). 그 `storage_id`를 가리키던 `loadout`은 다시 살아난다.

### 4.7 id 형식(보존 대상 목록 공통)

`^[a-z0-9][a-z0-9_.:-]{0,79}$`. 지금 데이터의 id(`champion:0`, `chapter1.character.frost`, `witch.frost.needle`)가 모두 맞는다 [확인: 데이터 파일과 코드에서 본 id 기준].

### 4.8 희귀 낱말 데이터(`loot.json`)

```json
"rare_names": {"first": [{"id": "f01", "name": "…"}, …], "second": [{"id": "s01", "name": "…"}, …]}
```
- 순서와 `name` 글자는 지금과 같다. 그래서 굴림의 난수 소비와 이름 글자가 그대로다(골든 불변).
- 낱말 이름을 바꿔도 id는 그대로 둔다. 그러면 이미 가진 희귀가 새 낱말로 다시 입혀진다(N46 "나" 안). 낱말을 없애려면 드랍에서 빼는 표시를 따로 두고 줄은 지우지 않는다(T5-D5).

---

## 5. 읽는 순서와 옮겨 오기

### 5.1 `configure()`의 순서

1. v4 가리키는 파일이 v4 이름 규칙에 맞고 같은 폴더에 있으면 그 r-파일, 아니면 v4 본 파일. **있으면 v4로 읽는다.** 거부되면 6.1의 거부 흐름(D5와 같음). 이후 단계로 내려가지 않는다(v4가 있으면 v3는 보지 않는다).
2. v4가 없으면 **v3 원본**을 찾는다: v3 가리키는 파일이 v3 이름 규칙(`^chapter-one-profile-v3-r[0-9-]+\.json\z`)에 맞고 그 파일이 있으면 그 r-파일, 아니면 `chapter-one-profile-v3.json`. 있으면 5.2로 옮긴다(메모리만).
3. v3가 없으면 v2(지금 `import_v2_text`), 그다음 v1(`import_v1_text`). 읽은 결과(메모리의 v3 모양)를 5.2로 옮긴다.
4. 아무것도 없으면 빈 v4.

어느 경우든 **읽기만으로는 아무 파일도 쓰지 않는다.** `imported_from = 3|2|1`을 두고, 첫 정상 저장이 v4 본 파일을 만든다. 그때 `origin`을 채운다.

### 5.2 v3 → v4 (한 번, 메모리에서)

| v3 | v4 |
|---|---|
| `schema_version` 3 | 4 |
| `revision` n | 첫 v4 저장이 n+1(지금 `_persist` 규칙) |
| `next_id`, `completed_runs`, `best_ticks`, `essence`, `receipts` | 그대로 |
| 문법 2 장비의 `name`, `description` | 버린다. 희귀는 5.3 |
| v1 장비 | 그대로(이름 포함) |
| `equipped` | 결정 T5-U1(권고: 세 마녀의 `loadout`에 **똑같이 복사**). 이를 위해 세 마녀 항목을 모두 만든다 |
| `characters.<id>` 다섯 키 | 그대로 + `loadout`, `depth_cleared`(그 마녀의 `first_rewards`에 `"boss"`가 있으면 `{"d1":1}`, 없으면 `{}`), `wardrobe` 기본, `story` 기본 |
| — | `codex`: 보관함에 있는 고유·전설의 id(D6 8.2). `gambles` 0. `shared_story` 기본. `quarantine`: 5.4 |
| — | `origin`: `{3, 원본 파일 이름, v3 revision, 저장 시각}` |

- `depth_cleared`의 근거: 우두머리 첫 처치 영수증 `boss`가 그 마녀가 깊이 1을 이긴 적이 있다는 유일한 마녀별 기록이다 [확인: `chapter_one.gd:406`이 이 영수증으로 첫 처치를 판정]. v2·v1에서 온 경우 영수증이 옮겨지지 않아(G1 6.2) 0이 된다. 받아들일 만하다(깊이 2는 아직 없다).
- `completed_runs`로 정하는 D6 8.2의 안보다 이쪽이 마녀별로 맞다.

### 5.3 옛 희귀 이름 되찾기

1. v3에 **저장된** 이름(읽을 때 `dress`가 다시 짓지 않으므로 파일 글 그대로)을 공백으로 나눈다.
2. 정확히 두 낱말이고, 첫 낱말이 `first` 목록의 `name`, 둘째가 `second` 목록의 `name`이면 `rare_words = [그 id 둘]`.
3. 아니면(낱말이 바뀌었거나, 세 낱말, 한 낱말) `legacy_name`에 원문을 둔다. 원문이 `_check_text`를 통과하지 못하면(제어 문자 등) 장비를 `quarantine`으로.
- 지금 데이터로 굴린 희귀는 언제나 2번에 걸린다(낱말에 공백 없음, 두 목록이 겹치지 않음 [확인]).
- 화면은 `legacy_name`을 한국어일 때 그대로, 다른 언어일 때 대체 틀로 보인다(T3 L-U5).

### 5.4 옮길 때의 너그러움

옮기는 쪽은 v3 원본에 **v4의 읽기 규칙**(6절)을 적용한다. 그래서 지금 v3 실행본이 거부할 파일(장비 하나가 데이터와 안 맞음, 투자 위반)도 구조만 맞으면 옮겨 올 수 있다. 구조가 깨진 v3(JSON, 크기, 키 집합)는 `reject_kind = "legacy"`로 거부하고, 이어 하기 후보로 **v3 기록본 가운데 가장 최근의 읽히는 것**을 찾는다(지금 `latest_readable_revision`과 같은 방식, 최근 64개까지, 읽기만).

### 5.5 v4가 거부됐을 때의 이어 하기 후보

1. v4 기록본 가운데 가장 최근의 읽히는 것(지금 규칙과 같음).
2. 없으면(결정 T5-D6) v3 원본을 다시 옮겨 온 상태. 안내 화면에 "옛 저장(v3, n번째)에서 다시 옮겨 옵니다"라고 알릴 수 있게 `resume_info()`에 `{"kind":"v3_source", "file", "revision"}`를 담는다.
3. 그것도 없으면 빈 저장.

---

## 6. 검증 — 거부, 고쳐 읽기, 보존

### 6.1 표

| 경우 | 처리 | 보고 키(`read_report`) |
|---|---|---|
| 파일 200만 자 초과, JSON 깨짐, 최상위가 사전이 아님 | **거부** `damaged` | — |
| `schema_version`이 4가 아님, 최상위 키 집합이 다름, 마녀 항목 키 집합이 다름, 형이 다름(배열 자리에 사전 등) | **거부** `incompatible` | — |
| `storage_id` 중복(`items`·`quarantine` 합쳐), `next_id` 이하가 아님 | **거부** `incompatible` | — |
| `quarantine` 325개 초과, 원본 하나가 8,000자 초과, `kind` 모름 | **거부** `incompatible` | — |
| 장비 하나가 정체 검사 실패(모르는 기본·접사·전설·고유 id, 수치 불일치, 요구 레벨 공식 불일치) | **격리**(T5-D1): 기록을 `quarantine`으로, 파일은 받아들임 | `quarantined_items` |
| 장비에 `name`·`description`이 있음(v4) | 고쳐 읽기: 지움 | `stripped_text` |
| `rare_words`의 낱말 id가 데이터에 없음 | 그대로 둠. 화면이 대체 이름 | `unnamed_rare` |
| `locked`·`new`가 `true`가 아닌 값 | 고쳐 읽기: 지움 | `dropped_flags` |
| `loadout`이 `quarantine`의 장비를 가리킴 | 보존(출발 장비에서만 뺌) | `inactive_loadout` |
| `loadout`이 어디에도 없는 `storage_id`, 칸·종류 불일치, 같은 장비 두 칸 | 고쳐 읽기: 그 칸을 비움 | `dropped_loadout` |
| `tree_revision`이 데이터와 다름 | 고쳐 읽기: 투자 반환, 알림(지금 그대로) | `refunded_trees` |
| 투자 위반(포인트 초과, 선행 깨짐, 레벨 부족) | 고쳐 읽기(T5-D2): 투자 반환, 알림 | `refunded_trees` |
| `first_rewards`·`wardrobe.owned`·`story.found`·`story.seen`·`codex`·`shared_story.seen`의 모르는 id | **보존**(그대로 두고 화면·계산에서 무시. 포인트 계산은 이미 무시한다) | `unknown_ids` |
| `wardrobe.worn`이 모르는 id이거나 가지지 않은 것 | 보존. 화면은 기본 복장 | `unknown_ids` |
| 모르는 마녀 id의 항목 | 격리(`kind: "character"`) | `quarantined_characters` |
| 같은 id가 목록에 두 번 | 고쳐 읽기: 하나만 | `deduped` |

- 읽은 뒤 `read_report`가 비어 있지 않으면 로그 한 줄 `CHAPTER1_PROFILE_READ_FIXES {"file":<이름만>, <키>:<개수>…}`를 찍는다. 장비 이름·사용자 경로를 찍지 않는다. 화면 안내(한 번 보이고 닫으면 끝)는 ui-hud의 일이다(키 `profile.read_fix.*`).
- 읽기는 파일을 쓰지 않는다. 고친 내용은 다음 정상 저장 때 파일에 쓰인다. 격리한 원본은 그 저장에서도 `quarantine`에 그대로 남는다.

### 6.2 쓰기 규칙(`_persist`의 엄격 검사)

6.1에서 "거부"와 "고쳐 읽기"인 것은 쓸 때 모두 거부다. "보존"인 것(모르는 id)은 형식만 맞으면 쓴다. 새로 더하는 함수는 따로 엄격하다:

| 함수 | 엄격한 점 |
|---|---|
| `record_run`의 새 장비 | `loot.validate` 통과, 희귀는 `rare_words`가 데이터의 id 둘. `name`·`description`은 프로필이 떼고 쓴다 |
| `record_run`의 `progress.collectibles_found` | 데이터(`collectibles.json`, D3 단계에서 생김)에 있는 id만. 파일이 없으면 비어 있어야 한다 |
| `grant_outfit`, `wear_outfit` | `outfits.json`에 있고 그 마녀의 것. `wear_outfit`은 가진 것이거나 `""` |
| `mark_story_seen`, `mark_shared_seen` | 데이터(`story_beats.json`, 나중)에 있는 id. 이미 있으면 쓰지 않고 참을 돌려준다(기록본이 늘지 않게) |
| `select_item(storage_id, character_id)` | 마녀 id 필수, 지금의 요구 레벨 거부 그대로 |

**불변식**: 어떤 파일이든 읽어서 받아들인 결과를 그대로 엄격 쓰기 검사에 넣으면 통과한다. 모든 고정 묶음에서 검사한다(14절 S1 V-15).

### 6.3 거부 흐름

D5의 흐름(안내, 저장 없이 플레이, 새 저장으로 시작, 기록본에서 이어 하기)을 v4 파일 이름으로 그대로 쓴다. 바뀌는 것은 3절의 이름과 5.5절의 이어 하기 후보 하나뿐이다. `reject_kind`는 지금 셋(`damaged`, `incompatible`, `legacy`) 그대로다.

---

## 7. 이름·번역을 바꿔도 저장이 흔들리지 않는다는 것을 검사로 지키기

"이름"은 장비 이름(기본·접사·전설·고유·세트·희귀 낱말), 의상·수집품·사건 이름, 장 이름, 마녀 표시 이름을 모두 뜻한다고 읽었다.

| 검사 | 방법 | 실패 조건 |
|---|---|---|
| 글 없는 파일 | v4 고정 묶음과 검사 중 저장한 모든 파일에서, `legacy_name`·옛 v1 장비·`quarantine[].raw`를 뺀 나머지 문자열 값에 한글(U+AC00–D7A3, U+3131–318E)이 없고, 사전 키에 `name`·`description`·`title`·`text`가 없다 | 하나라도 있으면 |
| 이름 바꾼 데이터로 읽기 | 검사가 `loot.json`을 `_local/` 아래로 복사해 모든 `name`·`description`·희귀 낱말 `name`을 다른 글(예: 앞에 `X-`)로 바꾸고, 프로필의 데이터 경로를 그 사본으로 돌린 뒤(시험 훅 `Profile.use_data_for_test({...})`) 같은 v4 파일을 읽는다 | 거부, `read_report`가 비어 있지 않음, 받아들인 상태가 원래 데이터로 읽은 것과 다름 |
| 낱말 바꿈 | 위 사본에서 희귀 낱말 하나의 `name`만 바꿈 | 그 낱말을 쓴 희귀의 `rare_words`가 그대로이고 화면 이름(`item_names.gd`, S2 뒤)이 새 낱말 |
| 번역 바꿈 | 언어를 `en`으로 바꾼 뒤 저장을 읽고 저장 | 파일 바이트가 언어와 무관(같은 상태를 ko·en에서 저장한 두 파일이 `revision`·시각 필드 말고 같음) |
| 옛 묶음 | S0의 고정 묶음(v3 파일들)을 옮긴 v4의 화면 이름(ko)이 옮기기 전 v3 실행본이 보이던 이름과 같음(S0의 기대값 파일과 비교) | 다름 |
| v4 호환 묶음 | S1 끝에 만든 `fixtures/profile_v4_compat.json`을 이후 모든 실행본이 `read_report` 0으로 읽음 | 고치기가 하나라도 나오면(데이터 변경이 저장을 건드렸다는 뜻) |

마지막 줄은 D5의 `loot_compat_items.json`과 같은 규칙이다. **묶음 파일을 다시 만들어 검사를 통과시키는 것은 금지한다.** 바꿔야 하면 디렉터 승인이 먼저다.

---

## 8. 마녀별 착용(L4)과 이어 가기(L5)

### 8.1 판 밖

- `loadout(character_id) -> Dictionary`: 그 마녀의 `{칸: storage_id}` 사본.
- `select_item(storage_id, character_id)`, `unselect(slot, character_id)`: 그 마녀의 묶음만 바꾼다. 마녀 id가 비면 거부(지금은 비면 공용에 넣는다 — 그 길을 없앤다).
- `salvage(storage_id)`: 모든 마녀의 묶음에서 뺀다.
- `starting_kit(character_id) -> {gear: Array, kept_slots: Array}`: `gear`는 지금 `starting_gear`와 같은 모양(코어 `import_starting_gear`가 받는 것). `kept_slots`는 묶음에 있으나 출발에서 빠진 칸(요구 레벨 미달, 격리된 장비). 지금의 `starting_gear`·`blocked_gear`는 이것을 감싸는 함수로 남긴다(화면이 쓰는 중).

### 8.2 판이 끝날 때(L5)

`record_run(receipt, inventory, pending, victory, ticks, progress := {}, carry := {})`

- `carry = {"character_id", "equipped": {칸: uid}, "kept_slots": [칸…]}`. 비면 묶음을 바꾸지 않는다.
- 새로 저장되는 장비는 지금처럼 차례로 새 `storage_id`를 받는다. 이때 `uid → storage_id` 대응을 만든다. 출발 장비는 이미 `storage_id`를 가지고 있다 [확인: `import_starting_gear`가 사본에 `storage_id`를 남긴다, `chapter_core.gd:653,658`]. 판에서 떨어진 장비는 `_publish_item`이 `uid`를 붙인다 [확인: `chapter_core.gd:575-576`].
- 새 묶음 = `equipped`의 각 칸을 대응한 `storage_id`로 + `kept_slots`의 칸은 이전 묶음 값 그대로. 그 밖의 칸은 빈다(판에서 벗은 칸).
- 검증: `character_id`가 알려진 마녀이고 `progress.character_id`가 있으면 같아야 한다. `equipped`의 uid는 `inventory`에 있어야 한다(`pending`은 끼지 않은 것). 칸·종류가 맞아야 한다. 실패하면 **저장 전체를 거부**한다(보상이 반만 저장되지 않게. 지금 `record_run`의 원자성 그대로).
- 같은 영수증이면 아무것도 하지 않는다(지금 그대로). 그래서 다시 시도해도 묶음이 두 번 바뀌지 않는다.
- 다른 마녀의 묶음은 바꾸지 않는다.
- 요구 레벨이 영구 레벨보다 높은 장비도 묶음에 들어간다(판 안 착용은 판 레벨을 쓰므로 생긴다, 1절). 다음 출발 때 지금처럼 `kept_slots`로 남고 화면이 "Lv n 필요"를 보인다.

### 8.3 앱(`chapter_one.gd`)

- 출발 때 `starting_kit`를 받아 넣고 `_run_kept_slots`를 기억한다. 출발 장비를 넣지 못했으면(지금 `gear_failed`, `:410-416`) `_run_carry_ok = false`: **이 판은 묶음을 바꾸지 않는다**(D5 N7 "저장된 선택은 바꾸지 않는다"를 지킨다).
- 저장 때(`_save_terminal`, `:549-563`) `_run_carry_ok`이면 `carry = {run_character_id, run.equipped 사본, _run_kept_slots}`. 이긴 판·진 판·포기한 판 모두 같다(T5-U5).
- 메뉴 보관함의 "다음 도전에 장착"은 메뉴에서 고른 마녀에게 넣는다. 지금 화면의 고른 마녀는 `chapter_hud.gd`의 `_menu_witch`(`:1575`)다 [확인]. 앱이 `hud.profile_state`를 만들 때 `equipped` 키에 그 마녀의 `loadout`을 넣어 주면 지금 보관함 화면(`:1407`)은 고치지 않고 돈다. 공개 읽기 함수(`menu_character_id()`)가 없으면 ui-hud가 다음 작업에서 더한다. S1이 `chapter_hud.gd`를 고치지 않는다(지금 다른 작업이 고치는 중이다, git 상태 `M chapter1/view/hud/chapter_hud.gd`).

---

## 9. 의상

- 프로필 함수: `wardrobe_view(character_id) -> {owned: [...], worn: "..."}`(데이터의 기본 소유 포함, 모르는 id는 뺀 화면용), `wear_outfit(character_id, outfit_id) -> bool`(`""`이면 기본 복장), `grant_outfit(character_id, outfit_id) -> bool`(나중의 얻는 길. 첫 컬렉션이 처음부터 주는 것이면 쓰지 않는다).
- 화면(A4 U4 의상 칸)은 `wardrobe_view`만 읽고 `wear_outfit`을 앱을 거쳐 부른다. 초상·3D 선택은 표현의 일이다(코어와 무관).
- 의상은 계정 공용이 아니라 마녀별(T5-U3 권고). 사용자 말("마녀마다 여러 벌")과 그림이 마녀별이라는 점이 근거다.

---

## 10. 서사 기록

| 요구(근거) | 저장 | 계산 |
|---|---|---|
| 수집품, 마녀별(D3 2절, 적용안 6절) | `characters.<id>.story.found` | 공통 조각도 그 마녀가 찾은 것으로 그 마녀 목록에 둔다. 수집품 화면은 합집합을 보일 수 있다 |
| 되돌아보기 조각(N20) | 같은 `found` | 출처 조건만 데이터에서 늘어난다 |
| 본 사건, 한 번만(D3 3절) | `story.seen` | — |
| 공통 장면을 다른 마녀로 이미 봄(N22) | `shared_story.seen` | — |
| 결전 완료(D3 7·8절) | `story.duel_cleared` | 5막 입장 = 세 마녀 가운데 하나라도 참. **따로 저장하지 않는다** |
| 악마신 처치 | `story.final_cleared` | — |
| 진 엔딩을 봄 | `shared_story.true_ending` | — |
| 막 진행(ACT-STRUCTURE 2절, N25) | 저장하지 않음 | 우두머리 첫 처치 영수증(`first_rewards`)에서. 제1장은 던전 하나라 영수증 `boss` 하나다 |
| 그 마녀의 첫 판(D3 3절) | 저장하지 않음 | `xp == 0`(D3 권고 그대로) |
| 결전 뒤 기억에 수집품 겹침(N23) | 같은 `found` | — |

스키마 4가 여는 것은 자리와 기록 함수뿐이다. 수집품을 주는 코어 규칙, 데이터 파일(`collectibles.json`, `story_beats.json`), 화면은 D3 구현 지시서의 일이다.

---

## 11. 설정 파일과의 경계

| 프로필(`chapter-one-profile-v4.json`) | 설정(`user://settings.cfg`) |
|---|---|
| 진행과 소유: 장비, 착용 묶음, 의상 소유와 입은 것, 경험치·트리, 재, 서사 기록, 도감, 깊이 | 기계·사람의 취향: 언어(`[general] locale`, 이미 있음), 창 모드·해상도·수직 동기화(`[display]`), 전체·음악·효과 음량과 음소거(`[audio]`), 화면 흔들림 세기·움직임 줄이기·번쩍임 줄이기(`[view]`), 마지막에 고른 마녀(`[general] last_character`), 키 배치(나중, `[input]`) |
| 저장마다 기록본이 생긴다. 클라우드 대상 | 기록본 없음. 클라우드에 넣지 않는다(T4 3.5) |
| 거부되면 안내와 네 갈래 | 읽지 못하면 기본값으로 시작하고 막지 않는다. 다음 쓰기 때 새로 쓴다 |

규칙
- 입은 의상은 진행으로 본다(프로필). 바꾸는 일이 드물어 기록본이 많이 늘지 않는다 [추정].
- 마지막에 고른 마녀처럼 자주 바뀌고 잃어도 해가 없는 값은 설정으로 둔다. 프로필에 두면 메뉴에서 오갈 때마다 기록본이 생긴다.
- 설정 파일을 쓰는 코드는 한 모듈이어야 한다. 지금은 `Loc`이 직접 읽고 쓴다(`loc.gd:103-130`). 설정 화면(A4 U8, T3-L5)을 만들 때 한 모듈(`chapter1/app/game_settings.gd` 안)로 모으고 `Loc`은 그것을 부른다. 이 일은 T5의 범위가 아니다. 스키마 4는 이 키들을 **넣지 않는다**는 것만 정한다.
- 검사는 설정 파일도 격리 경로를 쓴다(`Loc.configure(path)`, 지금 규칙).

---

## 12. 기록본 보존과 지우는 코드(S3, 결정 T5-D3 = T4 S-D3)

### 12.1 규칙(권고)

v4 본 파일(또는 쓰고 있는 r-파일)의 기록본 가운데 다음은 **남긴다**:
1. 리비전 번호로 최근 20개.
2. 이름의 날짜(`YYYYMMDD`)로 최근 7일, 날마다 리비전이 가장 큰 것 하나.
3. 그 파일의 가장 작은 리비전 하나(옮긴 직후 또는 새 저장 직후의 상태).
4. v4 가리키는 파일의 `from_revision`이 가리키는 기록본.

나머지는 지운다. 한 번의 저장 뒤 지우는 수는 **10개까지**(밀린 것은 다음 저장 때 이어서). 판당 저장이 2~5번이라 [추정: 결과 저장 1 + 착용·해체·트리] 며칠이면 따라잡는다.

### 12.2 안전 조건

| 조건 | 내용 |
|---|---|
| 함수 하나 | 지우는 호출(`DirAccess.remove_absolute`)은 `chapter_profile.gd`의 `_prune_journals()` 한 곳에만. `chapter1/` 전체에서 그 밖의 `remove`·`remove_absolute` 0건(지금 0건 [확인: TECH-REVIEW-D5 1절]) |
| 계획과 실행을 나눔 | `plan_journal_prune() -> Array[String]`(순수, 지울 이름 목록)과 `_prune_journals()`(그 목록만 지움). 검사가 계획을 먼저 본다 |
| 대상 | `revisions/` 폴더 바로 아래의 파일 가운데 이름이 `^<본 바탕>\.revision-([0-9]{6})-([0-9]{8})-[0-9]+-[0-9]+\.json\z`에 정확히 맞는 것만. 폴더, 링크(`DirAccess.is_link`), 다른 바탕 이름, v3 기록본(본 파일 옆), 본·r-파일·가리키는 파일·임시 파일은 대상이 될 수 없다 |
| 언제 | `_persist`가 바꿔 끼우기와 내용 확인까지 성공한 **뒤에만**. 지우기가 실패해도 저장은 성공으로 두고 로그만 찍는다 |
| 하지 않는 때 | 프로필이 거부 상태이거나 `available`이 거짓일 때. 이번 실행에서 읽을 때 `read_report`가 비어 있지 않았을 때(데이터가 바뀐 직후에는 옛 기록본을 남겨 둔다. 깨끗하게 읽힌 다음 실행부터 지운다). QA 모드가 아닌데 경로가 `user://` 아래가 아닐 때 |
| v3 시대 파일 | 지우지 않는다. v3 기록본을 정리할지는 T4-C에서 따로 정한다 |
| 로그 | `CHAPTER1_PROFILE_PRUNE {"kept":n,"removed":n,"left":n}`(이름 목록 없음) |

### 12.3 검사(격리)

- 날짜 주입 훅 `journal_date_override`(검사 전용, 숫자만)로 열흘에 걸친 기록본 40개를 실제 저장으로 만든다.
- 그 폴더에 함정 파일을 둔다: 비슷한 이름(`….json.bak`, 대문자 `REVISION`, 리비전 다섯 자리, 다른 바탕 이름), 같은 이름의 폴더, 본 파일 옆의 v3 기록본, 임시 파일.
- 기대: 지운 집합 = `plan_journal_prune()`의 결과 = 12.1 규칙으로 손으로 셈한 집합. 남은 파일은 모두 바이트가 그대로(sha256). 함정 파일은 모두 그대로. 본 파일·가리키는 파일 그대로.
- 한 번에 10개 상한: 30개가 밀린 상태에서 저장 한 번 뒤 정확히 10개만 줄었는지.
- 거부 상태·`read_report`가 있는 상태에서 저장(또는 저장 시도) 뒤 아무것도 지워지지 않았는지.
- 소스 검사: `chapter1/` 아래 `.gd` 파일을 읽어 `remove_absolute`·`.remove(` 등장이 `_prune_journals` 안의 한 곳뿐인지.

---

## 13. 골든·측정과의 관계

| 단계 | 코어 진행 | 골든 4건 | 글 없는 골든 4건 | 드랍 시뮬레이션 |
|---|---|---|---|---|
| S0, M0 | 안 바뀜(파일 추가뿐) | 돌리지 않아도 됨 | — | — |
| S1 | 안 바뀜. `loot.gd`는 희귀 낱말 읽는 법(문자열 → `.name`)과 `_check`의 모양 검사만 바뀐다. 난수 소비·이름 글자 같음 | **그대로여야 함** | 그대로여야 함 | 3,000판 결과 키·값 같아야 함 |
| S2(T3-S 코어) | 진행은 안 바뀜. 판 안 장비 사전에서 `name`·`description`이 빠지고 희귀에 `rare_words`가 생긴다 | **바뀜**(의도). 글 없는 골든이 그대로인 것을 먼저 보이고 갱신 | **그대로여야 함**(`rare_words`는 L0b가 지우는 필드 목록에 있다, T3 L0b) | 같아야 함 |
| S3 | 안 바뀜 | 그대로 | 그대로 | — |

**L5와 자동 조작 조건**
- 골든(`golden_core.gd`), 전투 측정(`measure_combat.gd`), 드랍 시뮬레이션(`sim_loot.gd`), 한 판 드랍 보고(`report_run_loot.gd`)는 프로필을 읽지 않고 장비 없이 출발한다(골든의 넷째 사례만 고정 빌드 파일) [확인: 네 파일에 `chapter_profile`·`starting_gear` 참조 없음]. 그래서 L5는 이들의 출발 조건을 바꾸지 않는다. **이 성질을 Q1의 정적 검사로 묶는다**: 이 네 파일이 `chapter_profile.gd`를 불러오거나 `import_starting_gear`를 부르면 실패.
- 창 실행의 측정·캡처는 지금처럼 `--chapter1-profile-off`(장비 없이 출발)로만 한다. 같은 실행 안에서 판을 이어 하면 L5 때문에 둘째 판의 출발 장비가 달라지기 때문이다.
- `hud_dump.gd --profile-fixture=…`은 실행마다 그 태그의 파일을 지우고 새로 만든다 [확인: `hud_dump.gd:108-116`]. 전후 비교는 같은 고정 묶음으로 새로 만든 프로필에서만 한다. 한 프로필로 판을 둘 이상 돌려 비교하지 않는다.
- `sim_progression.gd`는 디스크 프로필 없이 자기 착용 정책으로 장비를 이어 간다(`carry`, `:220-259`) [확인]. L5와 같은 의미로 맞출지는 content-balance가 정한다(T5 범위 밖). S1은 이 도구가 계속 도는 것만 보장한다.

---

## 14. 지시서

공통 규칙(모든 지시서)
- 코드를 고치는 에이전트는 별도 작업 폴더에서 일한다. 커밋하지 않는다.
- `.gitattributes`가 `* -text`다. 줄바꿈을 바꾸는 도구로 기존 파일을 고치지 않는다. 새 파일은 UTF-8, LF.
- 검사는 `_local/` 아래 격리 경로만 쓴다. Godot는 `python tools/dev/godot.py …` 또는 `run_all.py`로만 띄운다(둘 다 `APPDATA`를 `_local/appdata/`로 돌린다). **사용자 폴더(`%APPDATA%\WitchMoira`)를 읽거나 쓰지 않는다. 열어 보지도 않는다.**
- `assert()` 안에 부작용을 넣지 않는다.
- 표현(view)은 코어 이벤트와 읽기 전용 상태만 쓴다.
- 새 화면 글은 `Loc.t(key)`, 원문은 `chapter1/i18n/ko.po`(T3 4절 규칙). 프로필 오류는 T3-L1이 정한 `error_code` 방식을 따른다.
- 실행하지 않은 검사를 통과로 적지 않는다. 보고서에 실제 명령과 출력의 결과 줄을 붙인다.

### S0 — 옛 저장 고정 묶음(qa-perf, 지금 바로)

| 항목 | 내용 |
|---|---|
| 목적 | 스키마 4 코드가 들어가기 **전의** 실행본으로 v3·v2·v1 저장 파일과 "그 파일로 출발하면 무엇을 끼는가"를 만들어 고정한다. S1이 옮긴 결과를 이것과 대조한다. 코드가 바뀐 뒤에는 만들 수 없으므로 S1보다 먼저 끝나야 한다 |
| 시작 조건 | 없음. `chapter_profile.gd`를 고치는 작업이 시작되기 전 |
| 만들 파일 | `chapter1/tests/make_profile_legacy_fixtures.gd`(한 번 돌리는 생성기, `res://_local/` 아래에서 실제 `chapter_profile.gd`로 저장을 만들어 결과를 고정 폴더로 복사), `chapter1/tests/fixtures/profile_legacy/` 아래: `v3_full.json`(문법 2 장비 등급×칸을 고루 30개 이상, 희귀 5개 이상, 전설·고유 포함, v1 장비 2개, 8칸 착용, 세 마녀 항목: 서리는 투자 있음·첫 처치 셋, 화염은 경험치만, 번개 없음), `v3_rare_oldword.json`(희귀 이름 하나를 목록에 없는 낱말로 손으로 바꾼 것), `v3_rare_threeword.json`(세 낱말 희귀), `v3_with_journals/`(본 파일 + 기록본 4개 + v3 가리키는 파일 + r-파일 하나, 본 파일은 수치를 바꿔 거부되게), `v2_sample.json`, `v1_sample.json`, `expected_v3.json`(각 파일에 대해 지금 실행본이 내놓는 값: `configure` 결과, `state`, `characters`, 세 마녀 각각의 `starting_gear(마녀)`와 `blocked_gear(마녀)`, 각 장비의 화면 이름(`dress` 뒤의 `name`)), `README.ko.md`(만든 날, 커밋, 명령, "다시 만들지 않는다") |
| 건드리지 않을 파일 | `chapter1/core/` 전부, `test_chapter_profile.gd`, 데이터 |
| 통과 기준 | (1) 생성기를 `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/make_profile_legacy_fixtures.gd` 로 돌려 종료 0. (2) 만든 v3 파일들을 지금 `chapter_profile.gd`로 다시 읽으면 `v3_full`·`v3_rare_*`는 받아들이고 `v3_with_journals` 본 파일은 `incompatible`로 거부(출력 붙임). (3) `run_all.py --quick` 통과. (4) 묶음 파일 목록과 sha256을 보고서에 |

### M0 — 관리 툴이 희귀 낱말의 새 형식을 읽게(manager-tools, 지금 바로)

| 항목 | 내용 |
|---|---|
| 목적 | S1이 `loot.json`의 `rare_names`를 문자열 배열에서 `{"id","name"}` 배열로 바꾼다. 관리 툴(`tools/manager/catalog.py:522`)이 지금 형식만 읽어 그때 깨진다. **두 형식을 다 읽게** 먼저 고쳐 둔다 |
| 고칠 파일 | `tools/manager/catalog.py`(그 부분만), `tools/manager/`의 해당 검사 |
| 건드리지 않을 파일 | `chapter1/` 전부 |
| 통과 기준 | 두 형식의 작은 사본(`_local/` 아래)으로 화면 데이터가 같은 낱말 목록을 낸다(새 형식은 id도 함께). `run_all.py --only manager` 통과 |

### S1 — 프로필 스키마 4와 앱 연결(gameplay-systems)

| 항목 | 내용 |
|---|---|
| 목적 | 이 문서 3~11절. 장비 글을 **파일에서** 빼되(판 안 장비 사전은 S2), L4·L5, 의상, 서사 자리, 격리 보관, 너그러운 읽기, v3/v2/v1 옮기기, 하위 폴더 기록본 |
| 시작 조건 | S0 끝, M0 끝, **T3-L1 끝**(같은 `chapter_profile.gd`·`chapter_one.gd`를 고친다. L1이 정한 `error_code` 방식을 따른다), 결정 T5-U1·U2·D1·D2·D4·D5·D6. `chapter_one.gd`를 고치는 다른 작업(D4-A·D5-A 남은 것, T1 R1·R4)이 없을 때 |
| 두 단계(한 작업 폴더, 검수는 끝에 한 번) | **S1a 프로필**: 아래 core·data·tests. **S1b 앱**: `chapter_one.gd` 연결(8.3절). S1a의 검사가 다 통과한 뒤 S1b |
| 고칠 파일 | `chapter1/core/chapter_profile.gd`(4~10절 전부. v3 읽기 함수 `normalize`·`normalize_v3`·`import_v2_text`·`import_v1_text`·`upgrade_v1`·`migrated_characters`는 옮기기용으로 남긴다), `chapter1/core/loot.gd`(`rare_names` 새 형식 읽기, `_check`에 모양·id 중복 검사, 새 함수 `rare_word_ids(name) -> Array`(5.3), `rare_name_for(words) -> String`(S2 전까지 메모리 이름을 짓는 데 씀). `roll_item`의 난수 소비와 결과는 바꾸지 않는다), `chapter1/data/loot.json`(`rare_names`만: 같은 순서·같은 글, id `f01`~`f10`·`s01`~`s10` — T5-D5 결정대로), 새 `chapter1/data/outfits.json`(4.5절, 여섯 줄, `default_owned`는 T5-U4 결정대로), `chapter1/app/chapter_one.gd`(S1b: 8.3절, `hud.profile_state.equipped`에 고른 마녀의 묶음, 보관함 장착에 마녀 id), `chapter1/tests/test_chapter_profile.gd`(v4로 옮김, 아래), 새 `chapter1/tests/test_profile_v4.gd`(마커 `CHAPTER1_PROFILE_V4_RESULT`), `chapter1/tests/test_loot.gd`(`rare_names` 읽는 138~149행), `chapter1/tests/hud_dump.gd`(**`--profile-fixture=rejected`의 파일 만드는 부분만**: v4에서는 수치를 바꾼 장비가 거부가 아니라 격리되므로, 구조가 깨진 v4(예: `storage_id` 중복) + 읽히는 기록본으로 바꾼다. 시점 이름과 출력 키는 그대로), `chapter1/tests/sim_progression.gd`(프로필 모양이 바뀌어 깨질 때만 최소로), `tools/dev/run_all.py`(검사 `profile-v4` 한 줄) |
| 메모리 모양 | 앱과 화면이 읽는 `state`에서 `equipped`가 빠진다. 앱이 화면용 사본을 만들 때 고른 마녀의 묶음을 `equipped`로 넣는다(8.3). S2 전까지 메모리의 문법 2 장비에는 `name`·`description`을 **다시 지어 넣는다**(`loot.dress` + 희귀는 `rare_name_for` 또는 `legacy_name`). 파일에는 쓰지 않는다. 그래서 코어와 화면은 S1에서 바뀌지 않는다 |
| 건드리지 않을 파일 | `chapter1/core/chapter_core.gd`, `combat_core.gd`, `chapter_items.gd`, `combat_run.gd`, `chapter1/view/` 전부(특히 `chapter_hud.gd`, 다른 작업이 고치는 중), `golden_core.gd`, 골든 기준 파일, `loot.json`의 `rare_names` 밖, `fixtures/loot_compat_items.json`, S0의 묶음 |
| `test_chapter_profile.gd` 옮기기 | 지금 115개 검사 각각을 "그대로 / v4로 옮김 / 바뀐 규칙으로 대체(이유)"로 나눈 표를 보고서에 붙인다. **말없이 빠진 검사가 없어야 한다.** 바뀌는 대표: D5 P-3(수치 위조 → 거부)은 T5-D1에 따라 "격리, 파일 받아들임, 파일 바이트 그대로"로, G1 5~7(투자 위반 → 거부)은 T5-D2에 따라 "반환·알림"으로. 맨 앞에 두 줄을 더한다: `--fixture-dir`가 `res://_local/`로 시작하지 않으면 `quit(1)`(D5 검수 L8), `OS.get_user_data_dir()`에 `/_local/appdata/`가 없으면 `quit(1)` |
| `test_profile_v4.gd`의 검사 | V-1 v3(S0 `v3_full`) → v4: 읽기만으로 파일이 생기지 않음, 첫 저장 뒤 v4 생김, v3 폴더의 모든 파일(본, 기록본, 가리키는 파일, r-파일) sha256 그대로. V-2 v4가 생긴 뒤 v3를 바꿔도 v4를 읽음. V-3 v2만·v1만 → v4, 경험치 옮김 규칙 그대로, 원본 그대로. V-4 **옮긴 뒤 세 마녀의 `starting_kit(마녀).gear`가 S0 `expected_v3.json`의 `starting_gear(마녀)`와 같다**(이름·설명 키를 뺀 비교), `kept_slots`가 `blocked_gear`의 칸과 같다. V-5 7절의 글 없는 파일 검사. V-6 희귀 되찾기: `v3_full`의 희귀는 모두 `rare_words`, `v3_rare_oldword`·`v3_rare_threeword`는 `legacy_name`이고 메모리 이름이 옮기기 전 화면 이름과 같다. V-7 7절의 이름 바꾼 데이터로 읽기(시험 훅 `Profile.use_data_for_test`, 끝나면 되돌림). V-8 격리: 모르는 기본 id·모르는 접사·수치 위조 장비를 넣은 v4 → 받아들임, 그 장비만 `quarantine`, 그것을 가리키는 묶음 칸은 남되 출발에서 빠짐, `read_report` 개수, 읽기로 파일 바이트 불변, 다음 저장에서 `raw`가 JSON으로 같음, 데이터를 되돌리면 같은 `storage_id`로 되살아남. V-9 거부: 6.1표의 거부 줄마다 하나씩, `reject_kind`가 맞고 폴더 sha256 그대로, 이어 하기 후보(v4 기록본 → T5-D6이면 v3 원본 → 빈 저장). V-10 투자: 리비전 불일치·포인트 초과·선행 깨짐 → 반환·알림, 다음 저장에 빈 `ranks`. V-11 L5: 판에서 새로 낀 장비가 새 `storage_id`로 묶음에 들어감, 출발 장비 유지, 판에서 벗은 칸은 빔, `kept_slots`는 유지, `carry` 없으면 묶음 그대로, 같은 영수증 두 번이면 장비·묶음 두 번 바뀌지 않음, 다른 마녀 묶음 그대로, 잘못된 `carry`(모르는 uid, 칸 불일치, 마녀 불일치)면 저장 전체 거부·파일 그대로. V-12 L4: 서리에게 장착해도 화염 묶음 그대로, 마녀 id 없는 `select_item` 거부, `salvage`가 모든 묶음에서 뺌, T5-U2 결정대로 공유 허용/거부. V-13 의상: 기본·가진 의상 입기, 모르는·남의·안 가진 의상 거부(파일 그대로), 저장된 모르는 id가 읽기·저장을 거쳐 남음, 모르는 `worn`은 화면에서 기본. V-14 서사: `mark_story_seen` 두 번째는 쓰지 않음(기록본 수 그대로), 모르는 id 보존, `collectibles_found`에 모르는 id면 `record_run` 거부. V-15 모든 고정 묶음·검사 파일에서 "읽은 결과 → 엄격 쓰기 검사" 통과. V-16 가리키는 파일: v4 가리키는 파일에 v3 이름을 넣으면 무시, v3 가리키는 파일은 바이트 그대로. V-17 S1 끝에 `fixtures/profile_v4_compat.json`을 **한 번** 만들어 넣고, 이 파일을 `read_report` 0으로 읽는 검사 |
| 앱 검사(S1b) | `test_profile_app_guard.gd`와 같은 방식(트리 밖에서 앱 객체를 만들고 프로필을 손으로 격리 경로에 설정)으로 새 `chapter1/tests/test_profile_app_loadout.gd`(마커 `CHAPTER1_APP_LOADOUT_RESULT`): 출발 장비를 넣지 못한 판은 묶음을 바꾸지 않음, 넣은 판은 저장 뒤 묶음이 판의 착용과 같음, 메뉴 마녀를 바꾸면 보관함 장착이 그 마녀에게 감. `run_all.py`에 한 줄 |
| 골든 | 13절 S1 줄. `golden`·`golden-textless`·`loot-sim`이 그대로여야 한다. 바뀌면 멈추고 보고한다(`--update` 금지) |
| 통과 기준 | (1) `python tools/dev/run_all.py` **전체** 통과(골든 4 + 글 없는 골든 4 불일치 0, 드랍 시뮬레이션, 새 검사 셋 포함). (2) 위 검사 V-1~V-17과 앱 검사의 결과 줄. (3) 115개 검사 대응표. (4) `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --profile-fixture=rejected …`로 D5-U 시점이 그대로 찍힘(시점 이름 목록과 `HUD_DUMP_REJECT` 줄). (5) `sim_progression.gd`를 가장 짧은 인수로 한 번 돌려 오류 0. (6) 소스 검사 결과: `chapter1/` 아래 `remove_absolute` 0건(S3 전), `user://`가 나오는 곳 목록과 각 이유 |

### S2 — 판 안 장비 사전에서 글 빼기(gameplay-systems, T3-S의 코어 부분)

| 항목 | 내용 |
|---|---|
| 목적 | T3 2.4절의 나머지: 굴림 결과에 `name`·`description`을 넣지 않고 희귀는 `rare_words`. 화면은 `item_names.gd`로 이름을 짓는다. S1의 "메모리에 다시 지어 넣기"를 없앤다 |
| 시작 조건 | S1 검수 통과. `chapter_hud.gd`를 고치는 다른 작업이 없을 때(화면 최소 수정이 들어간다) |
| 고칠 파일 | T3-S 표 그대로: `chapter1/core/loot.gd`(`roll_item`·`make_unique`가 글 없이, `_compose`는 수치만, `dress`는 옛 v3 장비를 옮길 때만), `chapter1/core/chapter_core.gd`(`_bare_item` 키 목록 `:680`), `chapter1/core/chapter_profile.gd`(메모리 다시 짓기 제거), 새 `chapter1/view/item_names.gd`(`name(item)`, `description(item)`: 희귀는 `rare_words` → `item.rare.first.<id>`·`second.<id>` 키, 모르는 낱말이나 `legacy_name`은 T3 L-U5 규칙), 지금 `item.name`·`item.description`을 그리는 곳(`chapter_hud.gd` 등)을 `item_names`로 — 최소, 한국어 화면 글 바이트 동일, `ko.po`에 낱말·장비 키 |
| 건드리지 않을 파일 | 데이터 수치, `chapter_items.gd`, 프로필 파일 형식(S1에서 끝남) |
| 골든 | 기존 골든 바뀜(의도). **글 없는 골든 4건이 먼저 그대로**인 것을 보이고, 그 뒤에만 기존 골든 `--update`. 보고에 각 사례의 mode·tick·kills·level 전후 동일 |
| 통과 기준 | T3-S 통과 기준 + (1) `run_all.py` 전체 통과. (2) `hud_dump.gd` 냉기 시드 11 한 판의 전후 덤프에서 텍스트 컨트롤 `text` 차이 0. (3) S0 묶음을 옮긴 화면 이름(ko)이 `expected_v3.json`의 이름과 같음 |

### S3 — 기록본 보존(gameplay-systems)

| 항목 | 내용 |
|---|---|
| 목적 | 12절 |
| 시작 조건 | S1 검수 통과, 디렉터 결정 T5-D3(= T4 S-D3) |
| 고칠 파일 | `chapter1/core/chapter_profile.gd`(`plan_journal_prune`, `_prune_journals`, `journal_date_override`), `chapter1/tests/test_profile_v4.gd`(12.3절 검사 묶음 `P-*`) |
| 건드리지 않을 파일 | 그 밖 전부 |
| 골든 | 그대로여야 함 |
| 통과 기준 | 12.3절 검사 전부, `run_all.py` 전체 통과, 소스 검사(`remove_absolute` 1건, 위치) |

### Q1 — 독립 검사(qa-perf)

| 항목 | 내용 |
|---|---|
| 목적 | 구현자가 짠 검사와 따로, 저장 안전과 "자동 조작 조건 불변"을 다른 눈으로 본다 |
| 시작 조건 | S1 검수 통과(S3 뒤에 한 번 더) |
| 만들 파일 | `chapter1/tests/test_profile_v4_guard.gd`(마커 `CHAPTER1_PROFILE_V4_GUARD_RESULT`)만. 다른 검사 파일을 고치지 않는다 |
| 할 일 | (1) 정적 검사: `golden_core.gd`·`measure_combat.gd`·`sim_loot.gd`·`report_run_loot.gd`가 `chapter_profile.gd`를 불러오거나 `import_starting_gear`를 부르지 않는다. (2) 망가뜨리기: S0·V4 묶음에 무작위 변형(키 빼기·더하기, 형 바꾸기, 숫자 부호, 문자열 자르기, 배열 섞기)을 시드 고정 500개 만들어 읽게 하고, 결과가 "거부(폴더 sha256 그대로)" 또는 "받아들임(그리고 엄격 쓰기 검사 통과)" 둘 중 하나인지. 엔진 오류(스크립트 오류 로그) 0. (3) 큰 파일(200만 자 근처), 깊은 중첩 `raw`. (4) 두 실행 흉내: 같은 경로를 두 객체가 열고 한쪽이 저장한 뒤 다른 쪽 저장이 거부되는지(지금 "다른 실행" 규칙) |
| 통과 기준 | 검사 통과와 결과 줄. 실패를 찾으면 고치지 말고 재현 입력(`_local/` 아래 파일)과 함께 보고 |

---

## 15. 순서와 다른 지시서와의 관계

```
지금 바로(서로 파일이 안 겹침):  S0(qa-perf)   M0(manager-tools)
T3-L1(gameplay-systems) ──▶ S1a ─▶ S1b(gameplay-systems) ──▶ [검수] ─┬─▶ S2(gameplay-systems, T3-S 코어)
                                                                    ├─▶ S3(gameplay-systems, 결정 T5-D3 뒤)
                                                                    └─▶ Q1(qa-perf)
S1 검수 뒤에 열리는 것: D6-A2 착용 창(마녀별 묶음 전제), A4 U4 의상 칸(wardrobe_view), D6-B·C·D·E(필드 자리 있음),
                       D3 수집품·사건(story 자리 있음), T4-C 클라우드(파일 이름 고정됨)
```

| 다른 지시서 | 관계 |
|---|---|
| T3-L1 | S1보다 먼저. 같은 `chapter_profile.gd`(오류 코드)·`chapter_one.gd`. 동시에 하지 않는다 |
| T3-S | S1(파일 형식) + S2(판 안 사전)로 나눠 이 문서가 맡는다. T3-S 표의 통과 기준은 S2에 들어 있다 |
| D6 S | 이 문서가 대신한다. D6 8.1의 필드를 모두 담았다(`depth_cleared`는 사전으로, T5-D9) |
| D6-A2 착용 창 | S1 뒤. 착용 창은 `loadout(마녀)`·`select_item(id, 마녀)`·`starting_kit`를 쓴다. 판 안 목록은 지금처럼 `run.inventory` |
| A4 U4 캐릭터 선택·의상 | 화면은 S1 전에도 지을 수 있다(A4 4.2: 저장 전에는 기본 복장 하나). 의상 칸 연결은 S1 뒤. 고른 마녀를 앱에 알리는 공개 함수(`menu_character_id()`)를 U4가 만든다 |
| D5 | 규칙(원본 불변, 거부 흐름, 고정 장비 묶음)을 그대로 잇는다. 바뀌는 것은 T5-D1(장비 실패를 격리로), T5-D2(투자 위반을 반환으로) 두 가지 |
| T4-C 클라우드 | S1 뒤(파일 이름), S3 뒤(기록본 보존). 자동 클라우드 패턴 문법 확인은 T4-C |
| D3 구현 | S1 뒤. 수집품 데이터·코어 지급·사건 화면 |
| T2-V(성능 최종 측정) | S0·M0·S1·S3·Q1은 판 밖·프로필 일이라 T2-V 전에 해도 된다(DIRECTOR-PLAN 2.9절 갈래 4의 예외와 같음). 다만 T2-0b·T2-V 측정 창 동안에는 같은 컴퓨터에서 Godot 검사를 돌리지 않는다 |

| 파일 | 이 문서의 단계 | 겹치는 다른 작업 | 규칙 |
|---|---|---|---|
| `core/chapter_profile.gd` | S1, S2(조금), S3 | T3-L1 | L1 → S1 → S2·S3 차례로 |
| `core/loot.gd`, `data/loot.json` | S1(낱말 형식), S2 | D6-B·C·D, 이름 교체(N40) | S2 끝까지 `loot.json`의 이름·구조를 다른 작업이 고치지 않는다 |
| `app/chapter_one.gd` | S1b | T3-L1, D4-A·D5-A 남은 것, T1 R1·R4, A4 U3·U4 연결 | 동시 금지 |
| `view/hud/chapter_hud.gd` | S2(최소) | A4 U0~U8, D6-A2, T3-L2 | S1은 고치지 않는다. S2는 그 파일을 아무도 안 만질 때 |
| `tests/hud_dump.gd` | S1(고정 묶음 함수 하나) | T3-L4, A4 시점 추가 | 더하기·그 함수만, 차례로 |
| `tools/dev/run_all.py` | S1(줄 둘), Q1(줄 하나) | T4-Q, T3-L6 | 차례로 |

---

## 16. 위험과 되돌리는 길

| 위험 | 막는 것 | 되돌리는 길 |
|---|---|---|
| 옮기는 코드가 v3 원본을 바꿈 | v4 실행본은 v3 시대 파일을 쓰지 않는다(2절 1). V-1이 폴더 sha256으로 확인 | v3 파일이 그대로라 v4 파일·폴더를 치우고 이전 실행본으로 돌아가면 그대로 읽힌다. **단, v4로 옮긴 뒤의 진행은 v3에 없다** |
| 옮긴 뒤 첫 판의 출발 장비가 달라짐 | T5-U1 (가), V-4가 S0 기대값과 대조 | 같은 v3에서 다시 옮겨 오기(5.5의 2) |
| 격리가 우리 코드의 버그를 조용히 숨김(새로 굴린 장비가 잘못돼도 파일이 거부되지 않음) | 쓰기는 엄격(`record_run`이 새 장비를 `validate`), 읽기 고침은 로그와 `read_report`로 늘 드러남, V-17 호환 묶음은 고치기 0이어야 함 | 격리한 원본은 남아 있어 고친 실행본이 되살린다 |
| 데이터 변경(이름·수치)이 저장을 건드림 | 이름은 저장에 없음(7절), 수치는 D5 고정 장비 묶음과 V-17 | 격리 → 데이터 되돌리면 되살아남 |
| 기록본 지우기가 다른 파일을 지움 | 12.2의 조건 전부, 12.3의 함정 파일 검사, 소스 검사 | 지워진 파일은 돌아오지 않는다. 그래서 S3는 따로 검수하고, 처음 배포할 때 상한(한 번에 10개)과 "읽기 고침이 있던 실행에서는 지우지 않음"을 둔다 |
| 옛 실행본(v3)으로 돌아가 놀면 진행이 갈라짐 | 옛 실행본은 배포하지 않는다. 개발 사본은 `--chapter1-profile-off`로 돈다(D5 2.3) | v4가 있으면 v3를 보지 않는다고 안내 문서에 적는다 |
| `quarantine`이 커져 파일 상한에 닿음 | 325개·한 원본 8,000자·파일 200만 자 상한, 넘으면 거부(조용히 버리지 않는다) | 거부 흐름(D5)으로 이어 하기 |
| 메모리에 다시 지은 이름(S1)과 파일 형식이 어긋남 | 메모리 이름은 S1의 쓰기에서 늘 뗀다. V-5가 파일을 검사 | S2에서 메모리 이름 자체가 없어진다 |
| 한 장비를 여러 마녀가 끼게 두면 세계관과 어긋남(D3 X1) | WORLD-BIBLE이 보관함 공용을 이미 받아들였다(가/나 권고) | T5-U2에서 "한 마녀만"을 고르면 옮기기를 (나)~(마) 가운데 하나로 바꿔야 한다 |
| L5 때문에 측정·캡처 조건이 흔들림 | 13절: 측정 도구는 프로필을 읽지 않음, 정적 검사(Q1), 창 측정은 `--chapter1-profile-off` | — |

S1의 큰 되돌리기: S1은 새 파일만 만든다. 작업 폴더의 변경을 버리면 이전 상태다(v3 파일은 아무도 쓰지 않았다). 배포 뒤라면 v4를 읽는 실행본만 뒤로 돌릴 수 없다는 점이 남는다. 그래서 V-17 호환 묶음을 S1 끝에 고정해 그 뒤의 모든 실행본이 v4를 계속 읽게 한다.

---

## 17. 사용자·디렉터가 정할 것

### 사용자

| # | 결정 | 선택지 | 권고와 이유 |
|---|---|---|---|
| T5-U1 | 지금의 공용 착용 묶음을 옮길 때 누구에게 주나 | (가) 세 마녀 모두에게 똑같이 / (나) 마지막으로 판을 한 마녀(저장에 기록이 없어 알 수 없다) / (다) 경험치가 가장 많은 마녀 하나 / (라) 서리만 / (마) 아무에게도(빈 묶음) | **(가)**. 지금 세 마녀가 같은 묶음으로 출발하므로 옮긴 뒤 첫 판이 지금과 똑같다. 아무것도 잃지 않는다. 요구 레벨이 모자란 장비는 지금처럼 표시만 하고 남긴다. (가)는 T5-U2의 "공유 허용"이 있어야 한다 |
| T5-U2 | 한 장비를 두 마녀 이상의 착용 묶음에 둘 수 있나 | 허용 / 한 마녀만 | **허용.** 보관함이 공용이고(세계관 문서도 같은 쪽), 마녀를 바꿀 때마다 장비를 벗겨 옮기는 귀찮음이 없다. 디아블로식 "캐릭터마다 따로 가진 장비"와는 다르다. 한 마녀만으로 하면 T5-U1은 (다)·(라)·(마) 중 하나가 된다 |
| T5-U3 | 의상은 마녀별인가 계정 공용인가 | 마녀별 / 공용 | **마녀별.** 말씀하신 "마녀마다 여러 벌"과 그림이 마녀마다 다르다는 점 |
| T5-U4 | 첫 컬렉션(마녀마다 두 벌)을 어떻게 얻나 | (가) 처음부터 가짐 / (나) 조건(예: 그 마녀의 우두머리 첫 처치) / (다) 나중에 정함 | **(가)**. 저장 형식은 어느 쪽이든 같다(데이터 `default_owned`만 다르다). 얻는 길은 다음 컬렉션을 만들 때 정한다 |
| T5-U5 | 판에서 바꿔 낀 장비를 어떤 판에서 이어 가나 | 이긴 판·진 판·포기한 판 모두 / 이긴 판만 | **모두.** 저장되는 판이면 언제나 같게 해야 "왜 이번엔 안 남았지"가 생기지 않는다. 출발 장비를 불러오지 못한 판만 예외(선택을 지킨다) |

### 디렉터

| # | 결정 | 권고 |
|---|---|---|
| T5-D1 | 장비 하나의 정체 검사 실패(모르는 id, 수치 불일치)를 파일 거부 대신 격리 보관으로 | **격리.** 사용자는 나머지를 그대로 쓰고, 그 장비는 버려지지 않으며 데이터가 돌아오면 되살아난다. 위조된 장비는 격리되어 쓸 수 없으므로 위조 방지도 약해지지 않는다. D5 P-3 검사의 기대가 바뀐다. 데이터 변경 경고는 D5 고정 장비 묶음과 V-17이 맡는다 |
| T5-D2 | 투자 위반(포인트 초과, 선행 깨짐, 레벨 부족)을 거부 대신 반환·알림으로 | **반환.** 잃는 것이 포인트 배치뿐이고 이미 리비전 불일치에 같은 길이 있다. G1 5~7 검사의 기대가 바뀐다 |
| T5-D3 | 기록본 보존 규칙과 지우는 코드(= T4 S-D3) | 12.1의 규칙, 한 번에 10개, S3로 따로 검수 |
| T5-D4 | 기록본을 하위 폴더 `revisions/`로 | 예. 자동 클라우드 패턴과 겹치지 않게. 패턴 문법은 T4-C가 확인 |
| T5-D5 | 영구 id의 모양: 희귀 낱말 `f01`~`f10`·`s01`~`s10`, 의상 `chapter1.outfit.<frost|ember|arc>.swim_1|swim_2` | 뜻 없는 번호. 낱말을 바꿔도 id는 그대로라 옛 희귀가 새 낱말로 다시 입혀진다(N46 "나"). 뜻 있는 영어 id는 이름이 바뀌면 뜻이 어긋난다 |
| T5-D6 | v4가 거부되고 v4 기록본도 다 거부될 때 v3 원본에서 다시 옮겨 오기를 이어 하기 후보로 | 넣는다. 비용이 작고(옮기는 코드를 다시 부를 뿐), 잃는 것을 줄인다 |
| T5-D7 | S1을 T3-L1 뒤에 | L1 뒤(T3·DIRECTOR-PLAN 2.9 순서). S0·M0은 지금 바로 |
| T5-D8 | 마지막에 고른 마녀 같은 화면 편의 값은 설정 파일로 | 설정 파일. 프로필에 두면 메뉴에서 오갈 때마다 기록본이 생긴다 |
| T5-D9 | 균열 깊이 기록을 던전 id 키 사전(`{"d1": n}`)으로(D6 8.1은 정수) | 사전. 던전이 늘 때(D2~D6) 스키마 5가 필요 없다 |

---

## 18. 확인하지 못한 것

- 스팀 자동 클라우드의 경로 패턴 문법(하위 폴더, 제외 규칙)을 문서로 확인하지 않았다(T4와 같음).
- `DirAccess.is_link`가 Windows의 정션·심볼릭 링크를 모두 잡는지 실행으로 보지 않았다. S3 구현자가 확인한다.
- 판당 저장 횟수(12.1의 "며칠이면 따라잡는다")는 셈하지 않은 어림이다.
- 사용자 저장에 장비가 몇 개, 희귀가 몇 개, 옛 낱말을 쓴 희귀가 있는지 보지 않았다(사용자 폴더를 열지 않는다). 옮기기의 실제 결과(격리 0개인지)는 사용자가 처음 실행할 때 로그 한 줄(`CHAPTER1_PROFILE_READ_FIXES`)로만 알 수 있다.
- A4 U4의 "잠긴 의상 = 실루엣 + 얻는 법"과 T5-U4 (가)가 맞물리는지는 화면 설계 쪽에서 다시 봐야 한다(처음부터 다 가지면 잠긴 카드가 없다).
- `collectibles.json`·`story_beats.json`의 형식은 D3의 초안만 보았다. id 형식(4.7절)에 맞는지만 맞추면 된다.

## 19. 직접 실행한 것

| 명령 | 결과 |
|---|---|
| `python tools/dev/run_all.py --only profile,loot,app-guard` | profile 115, loot 36, app-guard 5 검사 실패 0 |
| `python tools/dev/godot.py --headless --path . --script res://_local/t5-probe/userdir.gd`(한 줄짜리 탐침, `_local/` 안) | `T5_USERDIR C:/Project/witch-moira/_local/appdata/godot/WitchMoira` — 격리 실행에서 `user://`가 사용자 폴더가 아님 |
| `loot.json`의 `rare_names`를 Python으로 읽기만 | 앞말 10·뒷말 10, 공백 든 낱말 0, 두 목록 공통 낱말 0 |

코드·데이터는 고치지 않았다. 사용자 폴더는 열지 않았다.
