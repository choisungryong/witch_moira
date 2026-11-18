# 기술 지시서 T6 — 저장 스키마 5(퀘스트·전투 기록·마을)

2026-11-19, 기술 책임자(tech-lead) 작성. 총괄 디렉터가 배정한다. 10절의 지시서는 받는 에이전트에게 그대로 넘길 수 있게 썼다. 받는 쪽은 이 문서와 여기에 적힌 파일만 보고 일할 수 있어야 한다.

근거: `docs/specs/D11-run-rhythm-and-reward-loop.ko.md`(D4, E1~E4, F1, H1의 W7·W8·W9), `docs/specs/T5-schema4-directives-20261117.ko.md`(스키마 4의 원칙·흐름·검사), `docs/specs/D5-save-safety-spec.ko.md`, `chapter1/core/chapter_profile.gd`(1309줄), `chapter1/core/chapter_core.gd`(`progress_summary` 236~243행), `chapter1/core/character_progression.gd`(145~148행), `chapter1/app/chapter_one.gd`(348~606행), `chapter1/tests/`의 `test_chapter_profile.gd`·`test_profile_v4.gd`·`test_profile_legacy_fixtures.gd`·`profile_legacy_snapshot.gd`·`make_profile_legacy_fixtures.gd`·`hud_dump.gd`(100~172행)·`sim_progression.gd`, `chapter1/tests/fixtures/profile_legacy/README.ko.md`, `chapter1/tests/fixtures/profile_v4_compat.json`, `tools/dev/run_all.py`(34~40행).

표기: [확인]은 파일을 읽어 본 것, [추정]은 읽은 것에서 미루어 본 것, [미확인]은 확인하지 못한 것. 이 문서를 쓰는 동안 **Godot·회귀·시뮬레이션은 하나도 돌리지 않았다**(다른 에이전트가 창 성능을 재는 중). 그래서 실행 결과로 확인한 줄은 없다. 행 번호는 2026-11-19 작업 트리(커밋 `7de9f92`)의 파일 기준이다.

---

## 0. 디렉터용 요약

1. 스키마 5는 새 파일 `user://chapter-one-profile-v5.json`이다. v4 파일(본 파일, 기록본, r-파일, v4 가리키는 파일)은 **읽기만 하고 한 바이트도 쓰지 않는다.** 첫 정상 저장 때 v5 파일이 생긴다. 스키마 3→4 때와 같은 길이다.
2. 더하는 키는 셋이다. 최상위 `town`(마을: 열린 장소, 상점 진열, 한 번만 사는 물건), 마녀 항목의 `quests`(퀘스트 상태), 마녀 항목의 `records`(판 수, 지난 판 기록, 던전별 최고 기록). 이미 있는 키는 하나도 빼거나 바꾸지 않는다.
3. D11 E4의 꼴을 따르되 네 곳을 정했다(디렉터 확인 필요, 4.6절). ① 반복 퀘스트는 `claimed`에 넣지 않고 `repeat_claims`로 센다. ② 현상금이 언제 뽑혔는지 알려고 `bounty_run`을 둔다. ③ 한 번만 사는 물건(회수약 상한 등)을 담을 `town.bought`를 둔다. ④ 최고 기록 `best`는 던전 깊이 키(`d1`)로 나눈다.
4. 퀘스트로 받는 스킬 포인트는 따로 저장하지 않는다. `character_progression.json`의 첫 처치 보상 목록에 퀘스트 보상 id를 넣고, 지금 있는 `first_rewards` 길로 준다(T6-D4). 그래서 포인트 계산 코드도 바뀌지 않는다.
5. 거부·복구 흐름은 스키마 4와 같다. 거부 종류는 셋(`damaged`, `incompatible`, `legacy`), 원본은 그대로 두고, 기록본에서 이어 하기와 새 저장으로 시작하기를 쓴다. 달라지는 곳은 셋이다. ① 이어 하기 후보에 "v4 원본을 다시 옮겨 오기"가 들어간다. ② v4 기록본은 본 파일 옆이 아니라 `revisions/` 하위 폴더에 있다. ③ 새 기록 칸(`records.last`, 상점 진열)은 깨져도 파일을 거부하지 않고 버린다. 다시 만들어지는 표시용 값이기 때문이다(T6-D5·D6).
6. 일은 셋으로 나눈다. **T6-S0** v4 고정 묶음(qa-perf, 코드를 바꾸기 전에 반드시 먼저), **T6-S1** 프로필 v5와 판 끝 기록(gameplay-systems), **T6-S2** 퀘스트·상점 쓰기 함수(gameplay-systems, W9 설계와 함께 하거나 그 직전). S1은 `chapter_one.gd`와 화면을 고치지 않는다.
7. 코어 골든에는 영향이 없어야 한다. 시뮬레이션 파일과 데이터는 고치지 않는다. 골든·측정 도구가 프로필을 읽지 않는다는 것을 정적 검사로 묶어 둔다(V5-16). `run_all.py` 전체에서 골든 4건, 글 없는 골든 4건, 드랍 시뮬레이션이 그대로여야 하고 `--update`는 하지 않는다.
8. 가장 큰 위험은 스키마 밖에 있다. 보상 단계 경험치 보너스(D11 D3, W5)를 넣으면 한 판 경험치가 `run_xp_max`를 넘는다. 그러면 `apply_progress`가 **저장 전체를 거부**한다(`chapter_profile.gd:991`). W5에서 막아야 한다(11절 R1).
9. 문서 불일치: `CLAUDE.md`의 "저장" 절은 아직 "스키마 3, `chapter-one-profile-v3.json`"이라고 적혀 있다. 코드는 이미 스키마 4다(`chapter_profile.gd:2,19`). S1이 끝나면 디렉터가 고쳐야 한다(하위 에이전트는 `CLAUDE.md`를 고치지 않는다).

---

## 1. 지금의 저장(스키마 4) [확인: 파일을 읽음]

| 항목 | 지금 | 위치(`chapter_profile.gd`) |
|---|---|---|
| 파일 | 본 `user://chapter-one-profile-v4.json`, 읽기만 하는 `-v3`·`-v2`·`-v1`, 가리키는 파일 `-v4-active.json`(v3은 `chapter-one-profile-active.json`), 거부 뒤 새 저장 `-v4-r<시각>[-n].json` | 19~28 |
| 최상위 키 | `TOP_KEYS` 14개를 **정확히** 맞춘다(`keys_match`) | 34, 636 |
| 마녀 키 | `CHAR_KEYS` 10개를 정확히 맞춘다 | 37, 823 |
| 스키마 번호 | `Catalog.integer(value.schema_version,4,4)`. 아니면 `incompatible` | 637 |
| 새 문서·기본 항목 | `fresh()`, `default_entry()` | 149~160 |
| 읽는 순서 | v4 가리키는 파일 → v4 본 → v3(가리키는 파일 → 본) → v2 → v1. 먼저 있는 것이 정하고, 거부되어도 아래로 내려가지 않는다 | 167~200 |
| v3→v4 | `upgrade_v3()`가 v4 문서를 만들고 `read_document(...,false)`(너그러운 읽기)로 받는다. v2·v1은 `normalize`/`upgrade_v1` → `_as_v3_document` → `upgrade_v3` | 389~438, 476~520 |
| 너그러운 읽기 | 장비가 데이터와 안 맞으면 `quarantine`으로 옮기고, 모르는 마녀도 `quarantine`으로 옮긴다. 모르는 id는 보존하고 `read_report`에 센다 | 635~758, 821~918 |
| 격리된 마녀 되살리기 | `Catalog.keys_match(set_aside.raw,CHAR_KEYS)`일 때만 | 733 |
| `origin.from_schema` | 0~4 | 753 |
| 파일 꼴 | `_document()`가 `schema_version` 4를 **박아 넣는다** | 939 |
| 쓰기 | `_persist`: 엄격 검사 → 다른 실행이 바꿨는지 확인 → `revisions/` 기록본 → 임시 파일 → 바꿔 끼우기 → 다시 읽어 확인 | 946~978 |
| 기록본 | `<폴더>/revisions/<본 바탕>.revision-<rev6>-<YYYYMMDD>-<pid>-<usec>.json` | 242~251, 962~963 |
| 거부 | `_reject(kind,…)`: 파일을 쓰지 않고 로그 한 줄만 남긴다. 이어 하기 후보는 v4 기록본 → v3 원본을 다시 옮김(`_v3_source_resume`). `legacy`일 때는 v3 기록본(본 파일 **옆**) | 375~384, 268~299 |
| 새 저장으로 | `start_fresh_after_reject`: v4가 거부되면 r-파일과 가리키는 파일, 옛 형식만 거부되면 본 경로에 새로(가리키는 파일 없음) | 331~360 |
| 판 끝 저장 | `record_run(receipt, inventory, pending, victory, ticks, progress={}, carry={})`. 한 번에 원자적으로 쓴다. 같은 영수증이면 아무것도 하지 않는다. `carry`가 잘못되면 보상만 저장하고 `carry_note="kit_not_saved"`를 남긴다 | 1008~1058 |
| 경험치 상한 | `apply_progress`가 `xp_gained`를 `0..run_xp_max`로 검사한다. `run_xp_max = seal+champion+boss+victory` | 991, `character_progression.gd:145` |
| 영수증 | 64개까지만 두고 넘치면 앞에서 버린다 | 1053~1054 |
| 시험 훅 | `use_data_for_test(loot_path)`, `use_ids_for_test({story,collectibles,shared})` | 123~132 |
| 기록본 지우기(T5-S3) | **구현되지 않았다**: `chapter1/`에 `_prune_journals`·`plan_journal_prune` 없음, `remove_absolute`는 `test_loc.gd` 한 곳뿐 | Grep |
| T5-Q1 독립 검사 | `chapter1/tests/test_profile_v4_guard.gd`가 **없다** | Glob |

앱 [확인: `chapter_one.gd`]: 377행의 `profile.configure()`는 기본 인수로 부른다. 판 끝 저장은 594~598행(`run.progress_summary()`, `carry`, `record_run`)이다. `progress_summary()`가 내놓는 키는 `character_id, xp_gained, sources{seal,champion,boss,victory}, first_kills, level_before, level_after`다(`chapter_core.gd:236~243`). 퀘스트를 세는 데 쓸 처치·정예·상자 수는 **아직 없다**(W1·W5·W9의 일).

검사 [확인]: `run_all.py` 34~40행이 `profile`(`test_chapter_profile.gd`), `app-guard`, `profile-legacy`(`test_profile_legacy_fixtures.gd`), `profile-v4`(`test_profile_v4.gd`), `app-loadout`를 돌린다. 옛 저장 고정 묶음은 `fixtures/profile_legacy/`(v3·v2·v1, 다시 만들지 않는다)에 있고, v4 호환 파일은 `fixtures/profile_v4_compat.json`(스키마 4, 리비전 18, 장비 38개, 마녀 셋, `origin.from_schema` 3)에 있다.

---

## 2. 원칙(T5 2절을 그대로 잇는다)

1. **옛 파일은 읽기만 한다.** v5 실행본은 v4·v3·v2·v1 시대의 모든 파일(본, r-파일, 기록본, 가리키는 파일)을 쓰지도, 이름을 바꾸지도, 지우지도 않는다.
2. **사실만 저장하고, 계산할 수 있는 것은 저장하지 않는다.** 퀘스트 스킬 포인트(→ `first_rewards`로 계산), 상점 아이템 레벨(→ `depth_cleared`로 계산), 상점 가격(→ 데이터로 계산), 전체 판 수(→ 마녀별 `records.runs`의 합)가 여기에 든다.
3. **저장 파일에 화면 글을 넣지 않는다.** 퀘스트·장소·물건은 id만 둔다. 상점 진열 장비는 `items`와 같은 글 없는 꼴로 둔다.
4. **읽기는 너그럽게, 쓰기는 엄격하게.** 읽은 결과는 언제나 엄격한 쓰기 검사를 통과해야 한다(불변식, V5-13).
5. **새로 더하는 것은 엄격하게, 이미 있는 것은 보존한다.** 퀘스트·장소·구매 id를 새로 쓰는 함수는 데이터에 있는 id만 받는다. 저장된 id가 데이터에서 사라져도 지우지 않는다.
6. **스키마 5 안에서는 키를 더하지 않는다.** 그래서 마을·퀘스트·기록 자리를 이번에 한꺼번에 연다. 아직 쓰지 않는 자리는 기본값으로 둔다.
7. **(새) 다시 만들어지는 표시용 값은 깨져도 파일을 거부하지 않는다.** `records.last`, `records.best`의 한 항목, 상점 진열 한 개가 그렇다. 버리고 센다(`dropped_record`, `dropped_stock`). 플레이어가 **가진 것**(장비, 재, 경험치, 퀘스트 완료)은 지금처럼 버리지 않는다.

---

## 3. 파일 이름과 위치

| 파일 | 이름 | 비고 |
|---|---|---|
| 본 | `user://chapter-one-profile-v5.json` | 상수 `PATH_V5` |
| 거부 뒤 새 저장 | `user://chapter-one-profile-v5-r<YYYYMMDD-HHMMSS>[-n].json` | 이름 규칙 `^chapter-one-profile-v5-r[0-9-]+\.json\z`(`FRESH_NAME_PATTERN_V5`) |
| 가리키는 파일 | `user://chapter-one-profile-v5-active.json` | v4의 `-v4-active.json`과 **따로 둔다.** v5 실행본은 v4 가리키는 파일을 읽기만 한다(옮겨 올 원본을 찾을 때) |
| 기록본 | `user://revisions/chapter-one-profile-v5.revision-…json` | 지금 규칙 그대로 쓴다. 바탕 이름이 달라 v4 기록본과 섞이지 않는다(`journal_files()`가 바탕 이름 접두사로 거른다, 250~251행) |
| 임시 | `user://chapter-one-profile-v5.json.next-<stamp>.tmp` | 지금 규칙 그대로 |
| 읽기만 | `-v4.json`, `-v4-active.json`, `-v4-r*.json`, `revisions/chapter-one-profile-v4*.revision-*.json`, 그리고 v3·v2·v1 파일(지금 그대로) | |

- 남겨 둘 상수: `PATH_V4`, `POINTER_PATH`(v4), `FRESH_NAME_PATTERN`(v4). 이름을 `PATH_V4`·`POINTER_PATH_V4`·`FRESH_NAME_PATTERN_V4`로 정리해도 되지만, 그 경우 모든 참조를 같은 작업 안에서 고친다.
- QA 모드: 모든 경로는 지금처럼 `res://_local/` 아래여야 하고 `..`가 없어야 한다(171~174행의 검사 대상 목록에 새 인수 둘을 더한다).

---

## 4. 스키마 5 필드

### 4.1 최상위(키 집합은 정확히 이것)

`TOP_KEYS_V5 = TOP_KEYS(v4의 14개) + ["town"]`. 지금의 `TOP_KEYS`는 `TOP_KEYS_V4`로 남긴다(옮기기용).

| 키 | 형 | 기본값 | 범위·검증 | 깨졌을 때(읽기) |
|---|---|---|---|---|
| `schema_version` | int | 5 | 정확히 5 | 거부 `incompatible` |
| v4의 13개 키 | 지금과 같음 | 지금과 같음 | 지금과 같음. 다만 `origin.from_schema`는 **0~5**(753행) | 지금과 같음 |
| `town` | 사전, 키는 정확히 `unlocked, bought, shop` | 아래 | 아래 | 키 집합이나 형이 다르면 거부 |

**`town.unlocked`** — 마을에서 열린 장소 id 목록. 계정 공용이다(T6-D2).
- 형: 문자열 배열, **16개 이하**, 각 원소는 `ID_PATTERN`(48행), 기본값 `[]`.
- 처음부터 열려 있는 장소는 데이터(W9가 만들 마을 데이터)가 정하고 저장에 쓰지 않는다. 의상의 `default_owned`와 같은 방식이다. 저장에는 퀘스트 보상 등 **사건으로 연** 장소만 들어간다.
- 모르는 id는 보존(`unknown_ids`), 중복은 하나로 줄인다(`deduped`). 쓸 때 중복이면 거부한다.

**`town.bought`** — 한 번만 사는 물건(예: 회수약 상한 올리기) id 목록. 계정 공용이다. D11에는 없는 키라 이번에 더했다(T6-D2).
- 형: 문자열 배열, **32개 이하**, `ID_PATTERN`, 기본값 `[]`. 보존·중복 규칙은 `unlocked`와 같다.
- 이 값을 판에 넘기는 일(회수약 상한을 코어 빌드에 넣는 것)은 W9의 일이다. 그때 코어 입력이 바뀌지만 골든은 프로필을 읽지 않으므로 그대로다(8절).

**`town.shop`** — 상점 진열. 계정 공용이다. 키는 정확히 `seed, refreshed_run, stock`.

| 키 | 형 | 기본값 | 검증 |
|---|---|---|---|
| `seed` | int | 0 | 0~2147483647 |
| `refreshed_run` | int | 0 | 0~10억. 진열을 새로 뽑았을 때의 **전체 판 수**(알려진 마녀 `records.runs`의 합). 앱은 지금 전체 판 수가 이 값보다 크면 진열을 새로 뽑는다(W9) |
| `stock` | 배열 | `[]` | **8개 이하.** 각 원소는 문법 2 장비의 파일 꼴(`ITEM_KEYS_V4` 필수 키 + `ITEM_KEYS_V4_OPTIONAL`, 43~44행). `name`·`description`이 없고, 희귀는 `rare_words` 또는 `legacy_name`을 가진다. v1 장비(`grammar` 없음)는 받지 않는다. 가격은 저장하지 않는다(데이터로 계산) |

- 진열 장비 하나가 지금 데이터와 안 맞으면 읽을 때 **그 장비만 버리고** `dropped_stock`에 센다(T6-D6). 플레이어가 가진 물건이 아니고, 다음 진열 때 다시 뽑히기 때문이다. 쓸 때는 거부한다.
- 진열 장비는 메모리에서도 글 없는 꼴로 둔다. 화면에 보여 줄 때는 W9가 `loot.dress`로 옷을 입힌다. `items`처럼 메모리에서 이름을 다시 지어 넣지 않는다. 그러면 `_document`가 진열 장비를 따로 손볼 필요가 없다.

### 4.2 마녀 항목(키 집합은 정확히 이것)

`CHAR_KEYS_V5 = CHAR_KEYS(v4의 10개) + ["quests","records"]`. 지금의 `CHAR_KEYS`는 `CHAR_KEYS_V4`로 남긴다.

**`quests`** — 그 마녀의 퀘스트 상태. 마녀별이다(D11 E4. 판정은 `narrative-lead`, T6-D1). 키는 정확히 아래 여덟.

| 키 | 형 | 기본값 | 범위 | 뜻 |
|---|---|---|---|---|
| `active` | id 배열 | `[]` | **8개 이하**(D11 E3: 이야기 1 + 곁일 3 + 현상금 2 = 6, 여유 2) | 받아서 진행 중이고 아직 조건을 채우지 못한 것 |
| `progress` | 사전 `{id: int}` | `{}` | 8개 이하, 값 0~10억 | 여러 판에 걸쳐 세는 진행값. 키는 `active`의 부분집합. `in_one_run` 퀘스트는 판마다 처음부터 세므로 여기에 남기지 않아도 된다(W9) |
| `done` | id 배열 | `[]` | **8개 이하** | 조건을 채웠고 보상을 아직 받지 않은 것 |
| `claimed` | id 배열 | `[]` | **256개 이하** | 보상을 받은 **한 번짜리** 퀘스트. 다시 받을 수 없다는 기록 |
| `bounty_offer` | id 배열 | `[]` | **3개 이하**(D11 D4: 판마다 셋 중에서 고름) | 지금 게시판에 걸린 현상금 |
| `bounty_seed` | int | 0 | 0~2147483647 | 현상금을 뽑은 시드 |
| `bounty_run` | int | 0 | 0~10억 | 현상금을 뽑았을 때 이 마녀의 `records.runs`. **D11에 없던 키** |
| `repeat_claims` | int | 0 | 0~10억 | 반복 퀘스트(현상금)의 보상을 받은 횟수. **D11에 없던 키** |

불변식(쓸 때 엄격, 읽을 때 고침):
- `active`, `done`, `claimed`, `bounty_offer`는 서로 겹치지 않는다. 겹치면 읽을 때 가장 앞선 단계 하나만 남긴다. 순서는 `claimed` > `done` > `active` > `bounty_offer`이고 `quest_fixed`에 센다.
- `progress`의 키는 `active` 안에 있다. 밖에 있는 키는 버리고 `quest_fixed`에 센다.
- 각 목록 안의 중복은 `deduped`로 센다(지금 `_id_list` 규칙, 613~623행).
- 모르는 퀘스트 id(데이터에 없는 id)는 그 자리에 **보존**하고 `unknown_ids`에 센다. 화면과 계산은 무시한다.
- 개수 상한을 넘거나 형이 다르면(배열 자리에 사전 등) 거부한다(`incompatible`).

반복 퀘스트를 `claimed`에 넣지 않는 이유: 현상금은 판마다 되풀이되므로 넣으면 256개가 곧 찬다. 반복 퀘스트는 보상을 받으면 `done`에서 빠지고 `repeat_claims`만 오른다. 한 번짜리 퀘스트는 `done`에서 `claimed`로 옮겨진다. 두 번 받지 않는 것은 "받기는 `done`에 있을 때만 된다"는 규칙과 원자적 쓰기가 지킨다(T6-S2).

**`records`** — 그 마녀의 전투 기록. 키는 정확히 `runs, wins, last, best`.

| 키 | 형 | 기본값 | 범위 | 깨졌을 때(읽기) |
|---|---|---|---|---|
| `runs` | int | 0 | 0~10억 | 형·범위가 틀리면 거부 |
| `wins` | int | 0 | 0~10억, `wins ≤ runs` | 범위가 틀리면 거부, `wins > runs`이면 `wins=runs`로 고치고 `quest_fixed`가 아니라 `record_fixed`에 센다 |
| `last` | 사전 | `{}` | `{}` 또는 4.3의 꼴 | 꼴이 틀리면 `{}`로 바꾸고 `dropped_record`에 센다(T6-D5) |
| `best` | 사전 `{깊이 키: {ticks, grade, kills}}` | `{}` | 키는 `DEPTH_KEY_PATTERN`(50행), 16개 이하. 값의 키는 정확히 셋: `ticks` 0~10억(가장 빠른 **승리**, 0이면 아직 없음), `grade` 0~4(가장 높은 보상 단계, 0이면 단계 없음), `kills` 0~10억(가장 많은 처치) | 키가 17개 이상이거나 형이 사전이 아니면 거부. 항목 하나의 꼴이 틀리면 그 항목만 버리고 `dropped_record`에 센다 |

- `best`를 깊이별로 나눈 이유: D11 E2의 "이 던전의 최고 단계"와 F1의 "이 던전의 최고 단계 대비"를 담기 위해서다. 깊이가 늘어도(D6 1.3) 스키마 6이 필요 없다. `depth_cleared`(T5-D9)와 같은 방식이다(T6-D7).
- 최상위 `best_ticks`(계정 전체 최단 승리)는 그대로 둔다. 결과 화면이 지금 읽는 값이라 빼면 화면이 바뀐다.

### 4.3 `records.last`의 꼴(F1의 숫자만)

키는 정확히 아래와 같다. 모두 숫자, 참거짓, id만 둔다.

| 키 | 형 | 범위 | F1 항목 |
|---|---|---|---|
| `depth` | 문자열 | `DEPTH_KEY_PATTERN` | 어느 던전·깊이 |
| `victory` | bool | | 승리 여부 |
| `ticks` | int | 0~10억 | 생존 시간(60Hz 틱) |
| `kills` | int | 0~10억 | 처치 |
| `elite_kills` | int | 0~10억 | 정예 처치(현상금 "정예 6"과 대조) |
| `champion_kills` | int | 0~16 | 수호자 처치 |
| `boss_kill` | bool | | 우두머리 처치 |
| `grade` | int | 0~4 | 보상 단계(W5 전에는 0) |
| `potions_used` | int | 0~10억 | 쓴 회수약 |
| `damage_taken` | int | 0~10억 | 받은 피해의 합(생명 단위, 코어 `UNIT`=256으로 나눈 값) |
| `xp_gained` | int | 0~10억 | 영구 경험치 |
| `essence_gained` | int | 0~10억 | 재 |
| `items` | 사전 `{출처: int}` | 키 16개 이하, 키는 `ID_PATTERN`, 값 0~10억 | 출처별 장비 수(D11 D5의 `source` 값: `normal`, `forced`, `chest`, `elite`, `carrier`, `ritual`, `champion`, `boss`, `first_kill`, `quest`, `shop`). 모르는 출처 키도 꼴만 맞으면 받는다 |
| `skills` | 배열 | **16개 이하** | 기술 표. 원소의 키는 정확히 `id`(`ID_PATTERN`), `got_tick`(0~10억), `got_level`(0~99), `rank`(0~99), `evolved`(bool), `damage`(0~10^12, 넘친 피해를 뺀 생명 단위 합, W7의 `dealt_raw`/256), `kills`(0~10억) |

- 넣지 않는 것: 초당 피해(`damage`와 `ticks - got_tick`으로 계산된다), 비중(%), 희귀 이상 장비 목록(장비는 `items`에 있다), 기술 이름(id로 짓는다). "최근 60초 초당 피해"는 저장하지 않는다. 지난 판과 비교할 때는 전체 초당 피해만 쓴다(T6-D5에 같이 적음).
- 이 꼴은 W7(`RunRecord`)이 만들 값이다. W7이 숫자를 더하거나 빼야 하면 **S1이 끝나기 전에** 이 표를 고친다. S1 뒤에 고치면 옛 v5 실행본은 그 `last`를 버린다. 거부되지는 않는다(원칙 7).

### 4.4 기본값

```
fresh() 에 더할 것: "schema_version":5, "town":{"unlocked":[],"bought":[],"shop":{"seed":0,"refreshed_run":0,"stock":[]}}
default_entry() 에 더할 것:
  "quests":{"active":[],"progress":{},"done":[],"claimed":[],"bounty_offer":[],"bounty_seed":0,"bounty_run":0,"repeat_claims":0},
  "records":{"runs":0,"wins":0,"last":{},"best":{}}
```

### 4.5 `read_report`의 새 키

`quest_fixed`(겹침·고아 진행값을 고침), `record_fixed`(`wins>runs`), `dropped_record`(`last`나 `best` 항목을 버림), `dropped_stock`(진열 장비를 버림). 지금 있는 키(`unknown_ids`, `deduped` 등)는 그대로 쓴다. 로그 한 줄 `CHAPTER1_PROFILE_READ_FIXES`(231~235행)도 그대로다.

### 4.6 D11 E4와 달라진 곳(디렉터 확인 필요)

| D11 E4 | 이 문서 | 이유 |
|---|---|---|
| `quests.done`, `claimed`의 뜻을 정하지 않음 | `done`은 보상 대기, `claimed`는 받은 한 번짜리. 서로 겹치지 않음 | 두 번 받기를 막는 규칙이 이 뜻 위에 선다 |
| 반복 퀘스트를 어떻게 둘지 정하지 않음 | `claimed`에 넣지 않고 `repeat_claims`로 셈 | 256개 상한, 파일이 계속 커지는 것을 막음 |
| `bounty_seed`만 | `bounty_run`을 더함 | "판마다 다시 뽑는다"를 판정하려면 언제 뽑았는지 알아야 함 |
| `records.best = {ticks, grade, kills}` | 깊이 키로 나눈 사전 | 깊이가 늘어도 스키마가 그대로 |
| `records`에 판 수가 없음 | `runs`, `wins`를 더함 | `bounty_run`, `refreshed_run`의 기준이 됨. 판 수는 다른 값에서 계산할 수 없음(영수증은 64개에서 잘림, 1053행) |
| `town = {unlocked, shop}` | `bought`를 더함 | E2 "회수약 상한 올리기(1회성)"를 담을 자리 |
| `shop.stock: [장비 기록]` | 장비 사전의 배열(`storage_id` 없음). 깨지면 버림 | 아직 가진 물건이 아님. 산 순간에 `items`로 들어가 `storage_id`를 받음 |
| 퀘스트 보상 스킬 포인트(D4)를 어디에 둘지 정하지 않음 | 저장 키 없음. `first_rewards`에 퀘스트 보상 id(예: `quest:q.ch1.end`)를 넣고, `character_progression.json`의 `first_rewards`에 그 id의 포인트를 둠 | 포인트 계산(`points_earned`)과 상한(`points_cap`, `character_progression.gd:148`)이 지금 코드 그대로 맞음. 데이터 파일 수정은 W9/content-balance(T6-D4) |

---

## 5. 읽는 순서와 옮기기

### 5.1 `configure()`의 순서

시그니처는 **뒤에 인수 둘을 더한다**. 지금 부르는 쪽(앱 377행, 검사들)이 깨지지 않게 하기 위해서다.

```
configure(destination=PATH_V5, qa=false, legacy_v2="", legacy_v1="", pointer="", legacy_v3="", legacy_v3_pointer="", legacy_v4="", legacy_v4_pointer="")
```

제품 모드(`qa=false`)에서는 지금처럼 함수 안에서 옛 경로를 채운다(179행). 여기에 `legacy_v4=PATH_V4`, `legacy_v4_pointer=POINTER_PATH(v4)`를 더하고, `pointer_path=POINTER_PATH_V5`로 바꾼다. 177행의 `destination!=PATH_V4` 검사는 `PATH_V5`로 바꾼다.

1. v5 가리키는 파일이 v5 이름 규칙에 맞고 같은 폴더에 있으면 그 r-파일을, 아니면 v5 본 파일을 본다. **있으면 v5로 읽는다.** 거부되면 6.3의 거부 흐름으로 가고, 아래 단계로 내려가지 않는다.
2. v5가 없으면 **v4 원본**을 찾는다. v4 가리키는 파일이 v4 이름 규칙(`FRESH_NAME_PATTERN`, 27행)에 맞고 그 파일이 있으면 그 r-파일, 아니면 `legacy_v4`다. 있으면 5.2의 방법으로 옮긴다(메모리에서만). 구조가 깨져 옮길 수 없으면 `_reject("legacy",…)`를 부르고, 아래(v3)로 내려가지 않는다.
3. v4도 없으면 지금의 v3 → v2 → v1 길을 그대로 탄다. 각 함수가 만든 v4 문서를 `upgrade_v4`에 한 번 더 넣는다(5.3).
4. 아무것도 없으면 빈 v5.

어느 경우든 **읽기만으로는 파일을 쓰지 않는다.** `imported_from_v4`(새 변수)를 두고 첫 정상 저장 때 거짓으로 돌린다(977행에 더함). 첫 저장 때 `origin`이 채워진다.

### 5.2 v4 → v5(한 번, 메모리에서)

새 정적 함수 `upgrade_v4(value, reasons_out=[]) -> Dictionary`:

| 단계 | 내용 |
|---|---|
| 구조 검사 | `value`가 사전이고 `keys_match(value, TOP_KEYS_V4)`이고 `schema_version`이 정확히 4. 아니면 `{}` + 사유(`"schema 4 keys"`, `"schema version"`) |
| 최상위 | 모든 키를 그대로 복사하고 `schema_version=5`, `town`은 4.4의 기본값 |
| 마녀 항목 | `characters`의 각 값이 사전이고 `keys_match(값, CHAR_KEYS_V4)`이면 `quests`·`records` 기본값을 더한다. 꼴이 다른 값은 **손대지 않고** 둔다. 그러면 `read_document`가 지금 규칙대로 거부하거나 격리한다 |
| `quarantine`의 마녀 | `kind=="character"`이고 `raw`가 `CHAR_KEYS_V4`에 맞는 사전이면 `raw`에도 두 기본값을 더한다. 되살리기(733행)가 v5 키로만 맞추기 때문이다. 장비 격리 항목은 그대로 둔다 |
| `origin` | `{"from_schema":4,"from_file":<v4 파일 이름>,"from_revision":<v4 revision>,"at_unix":0}`. v4의 `origin`(v3에서 왔다는 기록)은 v4 파일에 그대로 남는다. v5에는 옮기지 않는다 |
| 그 밖 | 장비·격리·도감·서사는 바꾸지 않는다. 이어서 `read_document(…, false)`(너그러운 읽기)가 장비를 지금 데이터로 다시 검사한다(T5 5.4와 같음) |

- `revision`은 이어진다. 첫 v5 저장은 v4 `revision`+1이다(948행 규칙).
- 옮기기를 두 번 해도 결과가 같아야 한다(V5-1).
- `records.runs`·`wins`는 0에서 시작한다. v4에는 마녀별 판 수가 없다. 최상위 `completed_runs`는 계정 전체 승리 수라 마녀별로 나눌 수 없다. 퀘스트도 비어서 시작한다(소급 완료 없음, T6-D3).

### 5.3 v3·v2·v1의 취급

**지금 규칙을 그대로 유지한다.** v5도 v4도 없을 때만 읽고, 읽기만 한다. 길은 `upgrade_v3`(v4 문서) → `upgrade_v4`(v5 문서) → `read_document(…,false)`다. `origin`은 지금처럼 `{3|2|1, 파일 이름, revision}`이다(436행의 `_origin_hint`). 이 경우에는 `upgrade_v4`가 만든 `origin`(from_schema 4)이 아니라 `_origin_hint`가 이긴다. 지금처럼 `_persist`가 `at_unix==0`일 때 `_origin_hint`로 채운다(949~950행). 그래서 `upgrade_v4`는 v3 길에서는 `origin`을 0으로 두고, `_origin_hint`가 출처를 기록하게 한다. 구현할 때 이 두 길이 섞이지 않게 한다. v4에서 온 경우에만 `_origin_hint={4, v4 파일 이름, v4 revision}`이다.

### 5.4 되돌릴 수 없게 되는 지점

- **파일 기준으로는 없다.** v4 파일과 기록본은 한 바이트도 바뀌지 않는다. v5 파일·폴더를 치우고 v4 실행본을 쓰면 v4는 옮기기 직전 상태로 읽힌다.
- **진행 기준으로는 첫 v5 저장이다.** 그 뒤의 진행(퀘스트, 상점 구매, 새 장비, 경험치)은 v5에만 있다. v4 실행본으로 돌아가면 그 진행이 보이지 않는다. 그 상태에서 v4로 놀다가 다시 v5 실행본을 쓰면 v4에서 한 진행은 버려진다. v5가 있으면 v4를 보지 않기 때문이다. 이 갈라짐은 T5의 v3/v4 때와 같고, 막는 길도 같다. 옛 실행본은 배포하지 않고, 개발 사본은 `--chapter1-profile-off`로 돈다.
- 새로 생기는 위험: 사용자가 이미 스키마 4 실행본으로 플레이하고 있다. v5 첫 실행에서 옮기기가 장비를 격리하거나 마녀를 격리하면 그 결과가 v5에 굳는다. 원본은 v4에 남아 있고, 격리 원본도 `quarantine`에 남아 되살릴 수 있다. 사용자 저장을 열어 보지 않으므로 실제로 몇 개가 격리될지는 알 수 없다(13절).

---

## 6. 검증 — 거부, 고쳐 읽기, 보존, 그리고 거부 흐름

### 6.1 v5 파일을 읽을 때의 표(새 줄만 적는다. T5 6.1표의 줄은 그대로다)

| 경우 | 처리 | 보고 키 |
|---|---|---|
| `schema_version`이 5가 아님(4, 6, 99 포함) | 거부 `incompatible` | — |
| 최상위에 `town`이 없거나 다른 키가 더 있음 | 거부 `incompatible` | — |
| `town`의 키 집합이 다르거나 형이 다름, `unlocked` 17개 이상, `bought` 33개 이상, `stock` 9개 이상, `shop`의 키·정수 범위가 틀림 | 거부 `incompatible` | — |
| 마녀 항목에 `quests`·`records`가 없음(v4 꼴의 항목) | 거부 `incompatible`. v5 파일 안의 v4 꼴 항목은 손으로 고친 것이다 | — |
| `quests`의 키 집합·형·상한·정수 범위가 틀림 | 거부 `incompatible` | — |
| `quests` 안의 겹침, `progress`의 고아 키 | 고쳐 읽기 | `quest_fixed` |
| 모르는 퀘스트·장소·구매 id | 보존 | `unknown_ids` |
| 목록 안의 중복 | 고쳐 읽기 | `deduped` |
| `records`의 키 집합이 틀림, `runs`·`wins`의 범위가 틀림, `best`가 사전이 아니거나 17개 이상 | 거부 `incompatible` | — |
| `wins > runs` | 고쳐 읽기(`wins=runs`) | `record_fixed` |
| `records.last`의 꼴이 4.3과 다름 | `{}`로 바꿈(T6-D5) | `dropped_record` |
| `records.best`의 항목 하나의 꼴이 틀림(키 패턴 포함) | 그 항목만 버림 | `dropped_record` |
| `shop.stock`의 장비 하나가 장비 검사 실패(`_evaluate_record`의 실패와 같음) 또는 v1 장비 | 그 장비만 버림(T6-D6) | `dropped_stock` |
| `quarantine`의 마녀 `raw`가 v4 꼴(`CHAR_KEYS_V4`) | 되살리기를 시도할 때 기본값을 더해 맞춘다 | 지금처럼 `restored_characters` |

### 6.2 쓰기 규칙(`_persist`의 엄격 검사)

6.1에서 "거부", "고쳐 읽기", "버림"에 해당하는 것은 쓸 때 모두 거부한다. "보존"(모르는 id)은 꼴만 맞으면 쓴다. **불변식**: 받아들인 결과를 그대로 엄격 쓰기 검사에 넣으면 통과한다(V5-13).

`_document()`(921~942행)는 `schema_version` 5를 쓰고 `town`을 그대로 복사한다(`stock` 장비는 메모리에서도 글이 없으므로 따로 손보지 않는다).

### 6.3 거부 흐름(D5·T5 6.3을 v5 이름으로 그대로)

`reject_kind`는 지금의 셋을 그대로 쓴다. 안내 화면(안내, 저장 없이 플레이, 새 저장으로 시작, 기록본에서 이어 하기)도 바뀌지 않는다. 바뀌는 것은 이름과 이어 하기 후보뿐이다.

| 거부된 것 | `reject_kind` | 이어 하기 후보(위에서부터, 읽기만) | "새 저장으로 시작"이 만드는 것 |
|---|---|---|---|
| v5 본 파일 또는 r-파일(크기, JSON) | `damaged` | ① 가장 최근의 읽히는 v5 기록본(지금 `latest_readable_revision`) ② 없으면 **v4 원본을 다시 옮긴 것**(새 `_v4_source_resume`, 종류 `"v4_source"`) ③ v4도 없으면 v3 원본을 다시 옮긴 것(지금 `_v3_source_resume`, `"v3_source"`) ④ 빈 저장 | `chapter-one-profile-v5-r<시각>[-n].json` + v5 가리키는 파일 |
| v5 파일의 구조 | `incompatible` | 위와 같음 | 위와 같음 |
| v5가 없고 v4 원본의 구조가 깨짐 | `legacy` | 가장 최근의 읽히는 **v4 기록본**(새 `_v4_journal_resume`, 종류 `"v4_journal"`). v4 기록본은 원본 옆이 아니라 `<원본 폴더>/revisions/<원본 바탕>.revision-*`에 있다. v3 기록본(원본 옆, 283~291행)과 찾는 곳이 다르다. 바탕은 r-파일이면 r-파일 이름이다 | 본 경로에 v5(가리키는 파일 없음). 지금 `legacy` 규칙(335~336행) 그대로 |
| v5·v4가 없고 v3·v2·v1이 깨짐 | `legacy` | 지금 그대로(v3이면 v3 기록본) | 지금 그대로, 이름만 v5 |

- `resume_info().kind`에 `"v4_source"`, `"v4_journal"` 두 값이 더해진다. 화면 문구는 `profile.resume.*` 키로 다는데, 그것은 ui-hud의 일이다. 그 문구가 없는 동안 화면은 지금의 기본 문구를 쓴다. 화면이 모르는 kind를 받으면 어떻게 하는지는 **[미확인]**이다. S1이 `chapter_hud.gd`에서 `resume`의 `kind`를 읽는 곳을 Grep으로 찾아 보고서에 적는다. 고치지는 않는다.
- 이어 하기 후보 ②(T6-D10): T5-D6과 같은 이유로 넣는다. v4 원본을 다시 옮기는 코드를 한 번 더 부를 뿐이다.
- 64개 상한(`MAX_JOURNAL_SCAN`)과 크기 상한은 그대로 둔다.

### 6.4 미래 스키마

- v5 경로의 파일에 `schema_version` 6 이상이 들어 있으면 `incompatible`로 거부한다(지금 637행 규칙과 같다). 원본은 그대로다.
- 정상이라면 스키마 6은 새 이름(`-v6.json`)을 쓸 것이므로 v5 실행본은 그 파일을 보지 못한다. 그래서 사용자가 v6 실행본에서 v5 실행본으로 돌아가면 **조용히 옛 v5를 읽는다.** 막을 길(T6-D8, 권고): `configure`가 본 파일 폴더에서 `^chapter-one-profile-v([6-9]|[1-9][0-9])(-r[0-9-]+)?\.json\z`에 맞는 파일을 **읽지 않고 이름만** 찾는다. 있으면 읽기 전용 필드 `newer_save_file`(파일 이름)을 채우고 로그 `CHAPTER1_PROFILE_NEWER_PRESENT {"file":…}` 한 줄을 찍는다. 거부하지 않고 저장도 막지 않는다. 화면 안내는 나중의 일이다. 디렉터가 넣지 않기로 하면 S1에서 뺀다.

---

## 7. 프로필 함수(S1과 S2의 계약)

### 7.1 S1 — 읽기와 판 끝 기록

| 함수 | 계약 |
|---|---|
| `quests_view(character_id) -> Dictionary` | 그 마녀의 `quests` 사본. 모르는 마녀나 프로필 미준비면 `{}` |
| `records_view(character_id) -> Dictionary` | 그 마녀의 `records` 사본. 같은 규칙 |
| `town_view() -> Dictionary` | `town` 사본. `stock`은 글 없는 꼴 그대로 |
| `total_runs() -> int` | 알려진 마녀의 `records.runs` 합(계산, 저장하지 않음) |
| `record_run(receipt, inventory, pending, victory, ticks, progress={}, carry={}, outcome={})` | **인수 하나를 뒤에 더한다**(앱 598행은 고치지 않아도 지금처럼 돈다). 규칙은 아래 |

`record_run`의 새 규칙:
1. `progress.character_id`가 있으면(프로필이 있고 판에 마녀가 있음) 그 마녀의 `records.runs`를 1 올리고, `victory`면 `wins`도 1 올린다. `outcome`이 비어 있어도 그렇게 한다. 그래서 앱을 고치기 전에도 판 수가 쌓인다.
2. `outcome.record`가 있으면 4.3의 꼴로 엄격하게 검사한다. 통과하면 `last`를 바꾸고 `best[record.depth]`를 갱신한다. `ticks`는 승리일 때만 더 작은 값으로, `grade`·`kills`는 더 큰 값으로. 통과하지 못하면 **보상은 저장하고** 기록만 빼며, `carry_note`와 같은 방식의 새 필드 `outcome_note="record_not_saved"`를 남기고 로그 `CHAPTER1_PROFILE_RECORD_DROPPED {"reason":…}`를 찍는다. 지금의 B1 원칙("기록 하나 때문에 보상을 잃지 않는다", 1047~1052행)과 같다.
3. `outcome.record.depth`와 `progress.character_id`가 없는데 `outcome.record`만 있으면 기록을 빼고 `record_not_saved`를 남긴다.
4. 같은 영수증이면 아무것도 하지 않는다(1010행 그대로). 판 수가 두 번 오르지 않는다.
5. `outcome`의 다른 키(예: `quests`)는 S1에서 받지 않는다. 키가 있으면 기록을 뺀 것과 같게 처리하고 `outcome_note="outcome_unknown_key"`를 남긴다. 퀘스트 갱신은 S2가 더한다.

### 7.2 S2 — 퀘스트와 마을 쓰기(W9 설계와 함께)

S1이 자리를 열고, S2가 쓰는 길을 연다. 데이터(`quests.json`, 마을 장소·구매 목록)가 아직 없으므로, 지금 `use_ids_for_test`(128행)처럼 시험 훅에 `"quests"`, `"places"`, `"purchases"` 목록을 더한다. 데이터 파일이 생기면 훅 대신 그 파일을 읽는다(W9). 모든 함수는 `_persist` 한 번으로 원자적으로 쓰고, 실패하면 아무것도 바꾸지 않는다.

| 함수 | 계약 |
|---|---|
| `accept_quest(character_id, quest_id) -> bool` | 알려진 id여야 하고 `active`·`done`·`claimed`에 없어야 한다. 한 번짜리면 `claimed`에도 없어야 한다. `active` 8개 미만. 현상금이면 `bounty_offer`에서 빼서 `active`로 옮긴다 |
| `record_run(…, outcome={"record":…, "quests":{…}})` | `outcome.quests`는 판이 끝난 뒤 그 마녀의 **다음 `quests` 전체**다(W9의 퀘스트 모듈이 판 요약으로 계산한다). 엄격 검사에 더해 단조성을 본다. 옛 `claimed`는 모두 남아야 하고, `repeat_claims`는 내려가지 않으며, `done`과 `claimed`에 새로 들어가는 id는 옛 `active`에 있던 것이어야 한다. 실패하면 보상은 저장하고 `outcome_note="quests_not_saved"`를 남긴다 |
| `claim_quest(character_id, quest_id, grant) -> bool` | `quest_id`가 `done`에 있을 때만 된다. 한 번짜리는 `done`에서 `claimed`로, 반복은 `done`에서 빼고 `repeat_claims`+1. `grant = {"essence":int≥0, "xp":int≥0, "items":[장비], "first_rewards":[id], "unlock":[장소 id]}`. 재는 10억까지 더하고, 경험치는 `xp_cap`까지 더한다(`run_xp_max`가 아니라 퀘스트 보상 상한으로 검사. 데이터가 생기기 전에는 시험 훅 값). 장비는 `record_run`처럼 `loot.validate`를 통과해야 새 `storage_id`를 받는다. `first_rewards`는 `character_progression.json`에 있는 id만 받는다. `unlock`은 알려진 장소만 받는다. 하나라도 틀리면 전체를 거부한다 |
| `roll_bounties(character_id, seed, offer) -> bool` | `offer`는 알려진 반복 퀘스트 id 3개 이하. `bounty_seed=seed`, `bounty_run=records.runs`. 뽑는 규칙은 W9가 정한다 |
| `restock_shop(seed, stock) -> bool` | `stock`은 8개 이하 장비. 각 장비는 `loot.validate`를 통과하고 글이 없는 꼴이다(프로필이 `name`·`description`을 떼고 희귀는 `rare_words`로 바꾼다. 지금 `record_run`의 장비 정리 1033~1038행과 같은 규칙). `refreshed_run=total_runs()` |
| `buy_from_shop(index, price) -> bool` | `0 ≤ index < stock.size()`, `essence ≥ price ≥ 0`, 보관함이 `MAX_ITEMS` 미만. 진열에서 빼서 새 `storage_id`로 `items`에 넣고 재를 깎는다. 고유·전설은 도감에 더한다(1039~1040행 규칙) |
| `buy_once(purchase_id, price) -> bool` | 알려진 id, `bought`에 없음, 재가 충분함. `bought`에 더하고 재를 깎는다. 이미 샀으면 아무것도 쓰지 않고 거짓 |
| `unlock_place(place_id) -> bool` | 알려진 id. 이미 열렸으면 아무것도 쓰지 않고 참(기록본이 늘지 않게, `mark_story_seen`과 같은 규칙) |

가격과 아이템 레벨은 W9가 데이터로 계산해 넘긴다. 프로필은 범위와 잔액만 본다.

---

## 8. 골든·측정과의 관계 — 영향이 없다는 것을 확인하는 법

| 단계 | 바뀌는 파일 | 골든 4건 | 글 없는 골든 4건 | 드랍 시뮬레이션 |
|---|---|---|---|---|
| T6-S0 | 검사 파일·고정 묶음 추가뿐 | 돌리지 않아도 됨 | — | — |
| T6-S1 | `chapter_profile.gd`, 검사, `run_all.py` | **그대로여야 함** | **그대로여야 함** | 그대로여야 함 |
| T6-S2 | `chapter_profile.gd`, 검사 | 그대로여야 함 | 그대로여야 함 | — |

확인하는 법(S1·S2 모두):
1. **바뀐 파일 목록**: `git status --short`와 `git diff --stat`에 `chapter1/core/chapter_core.gd`, `combat_core.gd`, `combat_run.gd`, `loot.gd`, `run_growth*.gd`, `chapter_pilot.gd`, `chapter1/data/` 아래 파일, 골든 기준 파일이 **없다**.
2. **정적 검사(V5-16)**: `golden_core.gd`, `measure_combat.gd`, `sim_loot.gd`, `report_run_loot.gd`가 `chapter_profile.gd`를 `preload`/`load`하지 않고 `import_starting_gear`를 부르지 않는다. `chapter1/core/` 아래 시뮬레이션 파일(`chapter_core.gd`, `combat_core.gd`, `combat_run.gd`, `run_growth*.gd`, `loot.gd`, `chapter_pilot.gd`)도 `chapter_profile.gd`를 참조하지 않는다. T5-Q1이 만들기로 했던 검사가 아직 없으므로(1절) 이번에 `test_profile_v5.gd` 안에 넣는다.
3. **실행**: `python tools/dev/run_all.py` 전체에서 `golden`, `golden-textless`, `loot-sim`이 통과한다. 해시가 하나라도 바뀌면 멈추고 보고한다. **`--update` 금지.**
4. `hud_dump.gd --profile-fixture=rejected`(146~172행)는 경로를 스스로 정하고 v5 꼴로 다시 만들므로 고치지 않고 돈다 [추정]. 실행해서 `HUD_DUMP_REJECT` 줄을 확인한다.

---

## 9. 검사 목록

모든 검사는 `res://_local/` 아래 격리 경로만 쓰고, 첫 줄에서 `OS.get_user_data_dir()`에 `/_local/appdata/`가 없으면 `quit(1)`한다(지금 `test_profile_v4.gd:79~80`과 같은 줄). Godot는 `python tools/dev/godot.py …` 또는 `run_all.py`로만 띄운다.

### 9.1 새 고정 묶음(T6-S0, 코드 변경 전에)

`chapter1/tests/fixtures/profile_v4/`:

| 파일 | 대표하는 것 |
|---|---|
| `v4_full.json` | 지금 코드가 `fixtures/profile_legacy/v3_full.json`을 옮긴 뒤 저장 몇 번으로 v4의 모든 칸을 기본값이 아닌 값으로 채운 파일. 서리·화염 의상 입음, 서리 `story.seen`·`found`(시험 훅 id), `shared_story.seen`, `tree_reset`에 id 하나, `depth_cleared` `{"d1":1}`, `codex` 채움, `locked`·`new` 표시 장비 각 하나, 마녀별로 다른 `loadout`, 격리 장비 하나(장비 하나의 `base_id`를 모르는 id로 손으로 바꾼 뒤 읽고 저장), 격리 마녀 하나(`chapter1.character.ghost`) |
| `v4_with_journals/` | 본 파일 `chapter-one-profile-v4.json`(구조를 깨서 거부되게: 두 장비가 같은 `storage_id`) + `revisions/chapter-one-profile-v4.revision-00000N-20261119-0-0.json` 4개(리비전 1~4, 읽힘) + `chapter-one-profile-v4-active.json` + 그 파일이 가리키는 `chapter-one-profile-v4-r20261119-120000.json`(리비전 4에서 이어 만든 것) |
| `expected_v4.json` | 각 장면을 **지금(스키마 4) 코드**가 읽은 결과. 형식은 `profile_legacy_snapshot.gd`의 `describe()`와 같고, 각 파일의 sha256을 함께 둔다 |
| `README.ko.md` | 만든 날, 커밋, 명령, "다시 만들지 않는다" |

장면(새 `chapter1/tests/profile_v4_snapshot.gd`의 `SCENARIOS`): `v4_full`, `v4_compat`(기존 `profile_v4_compat.json`), `v4_journals_main_only`(거부 → 이어 하기 후보 리비전 4), `v4_journals_with_pointer`(r-파일을 읽음).

기록본 이름은 실제 저장이 붙이는 pid·마이크로초를 `0-0`으로, 날짜를 `20261119`로 고정한다(T5-S0의 v3 묶음과 같은 방식). 생성기는 `expected_v4.json`이 있으면 실행을 거부한다.

### 9.2 새 검사 `chapter1/tests/test_profile_v5.gd`(마커 `CHAPTER1_PROFILE_V5_RESULT`)

| # | 검사 | 통과 기준 |
|---|---|---|
| V5-1 | v4 → v5 옮기기 | 읽기만으로는 파일이 생기지 않는다. 첫 저장 뒤 v5가 생긴다. v4 폴더의 모든 파일(본, `revisions/`, 가리키는 파일, r-파일)의 sha256이 그대로다. `origin={4, 파일 이름, v4 revision, >0}`, `revision`은 v4+1. 같은 파일을 두 번 옮기면 메모리 상태가 같다 |
| V5-2 | v5가 생긴 뒤 | v4·v3 파일을 깨뜨려도 v5를 읽는다 |
| V5-3 | 가리키는 파일 | v4 가리키는 파일 → r-파일에서 옮긴다. v4 가리키는 파일의 바이트는 그대로다. v5 가리키는 파일에 v4 이름을 넣으면 무시한다 |
| V5-4 | S0 v4 묶음 대조 | 각 장면에서 `state`는 `expected_v4`의 `state`에 `town` 기본값과 `schema_version` 5만 다르다. `characters`는 각 항목에 `quests`·`records` 기본값만 더해졌다. 세 마녀의 `starting_kit`·`blocked_gear`·장비 화면 이름이 같다. `quarantine`이 같다. `read_report`는 v4 코드가 낸 값과 같다(`v4_full`은 격리가 이미 파일에 있으므로 고침 0) |
| V5-5 | v3·v2·v1 | `test_profile_legacy_fixtures.gd`가 v5 기준으로 통과한다(9.3) |
| V5-6 | v4 원본의 구조가 깨짐 | `reject_kind=="legacy"`, 아무 파일도 생기지 않는다. `resume_info().kind=="v4_journal"`이고 리비전이 4다. `start_fresh_after_reject(true)` 뒤 본 경로에 v5가 생기고 v5 가리키는 파일은 없다. v4 폴더의 sha256이 그대로다. v4 기록본을 모두 깨뜨리면 후보가 비거나, v3 원본이 함께 있으면 무엇이 되는지를 정해 검사한다(T6-D10) |
| V5-7 | v5 거부 | 6.1표의 거부 줄마다 하나씩(`town` 없음, `town` 키 더함, `unlocked` 17개, `stock` 9개, `quests` 키 빠짐, `active` 9개, `progress` 값 −1, `records` 키 빠짐, `runs` 문자열, `best` 17개, 마녀 항목이 v4 꼴, `schema_version` 4·6). 모두 `incompatible`이고 폴더 sha256이 그대로다. 이어 하기 후보는 v5 기록본 → `v4_source` → `v3_source` → 빈 저장 순서(각각 하나씩 만들어 확인). 새 저장은 `-v5-r` 이름과 v5 가리키는 파일 |
| V5-8 | 고쳐 읽기 | 겹침·고아 진행값 → `quest_fixed`, 모르는 퀘스트·장소·구매 id → `unknown_ids`, 저장 한 번을 거쳐도 남음, `wins>runs` → `record_fixed`, 꼴이 틀린 `last` → `{}`와 `dropped_record`, `best` 항목 하나 → 그 항목만 빠짐, 진열 장비 하나의 `base_id` 위조 → 그 장비만 빠지고 `dropped_stock`. 각 경우 읽기로 파일 바이트는 그대로이고, 결과는 엄격 쓰기를 통과한다 |
| V5-9 | 엄격 쓰기 | V5-8의 각 고침 전 문서를 `read_document(…, true)`에 넣으면 거부한다 |
| V5-10 | `record_run` 판 끝 기록 | `outcome` 없이도 `runs`/`wins`가 오른다. `outcome.record`가 맞으면 `last`가 그것이고 `best`가 규칙대로 갱신된다(진 판은 `ticks`를 바꾸지 않는다). 잘못된 기록이면 보상·경험치는 저장되고 기록은 그대로이며 `outcome_note=="record_not_saved"`. 같은 영수증 두 번이면 `runs`가 한 번만 오른다. `progress`가 비면 어느 마녀의 `records`도 그대로다. 다른 마녀의 `records`도 그대로다 |
| V5-11 | 격리된 마녀 되살리기 | v4 꼴 `raw`(`CHAR_KEYS_V4`)를 가진 격리 마녀가, 시험 데이터로 그 id를 알게 하면 기본값이 더해져 되살아난다 |
| V5-12 | 글 없는 파일 | T5 7절의 검사(한글 문자열, `name`·`description`·`title`·`text` 키)를 v5 파일 전체에 적용한다. 예외는 지금처럼 `legacy_name`, v1 장비, `quarantine[].raw`. `town.shop.stock`에도 글이 없다 |
| V5-13 | 불변식 | 모든 고정 묶음(v3·v2·v1 7장면, v4 4장면)과 이 검사가 만든 모든 파일에서 "읽은 결과 → 엄격 쓰기 통과" |
| V5-14 | 호환 파일 | ① `profile_v4_compat.json`이 v4 원본으로 옮겨지고 `read_report`가 비어 있다. ② `--write-compat`로 `fixtures/profile_v5_compat.json`을 **한 번** 만든다(`town`·`quests`·`records`가 모두 기본값이 아닌 값. S2 전이면 손으로 채운 문서를 엄격 쓰기로 확인한 뒤 저장). 이후 이 파일을 `read_report` 0으로 읽는다. 파일이 이미 있으면 덮어쓰기를 거부한다 |
| V5-15 | 미래 | v5 경로의 파일에 `schema_version` 6 → `incompatible`. T6-D8을 채택하면 `chapter-one-profile-v6.json`이 옆에 있을 때 `newer_save_file`이 채워지고, 읽기·저장은 지금처럼 되며, 그 파일의 바이트는 그대로다 |
| V5-16 | 골든 조건 정적 검사 | 8절 2의 파일들에 `chapter_profile.gd`·`import_starting_gear` 참조가 0이다 |
| V5-17 | 기록본 | v5 저장의 기록본은 `revisions/chapter-one-profile-v5.revision-*`이다. `journal_files()`는 v4 기록본을 포함하지 않는다 |
| (S2) V5-20~ | 퀘스트·마을 쓰기 | 7.2의 함수마다 성공 1, 거부 각 조건 1. 거부 때 파일 바이트는 그대로다. `claim_quest` 두 번 → 두 번째는 거짓이고 재·경험치가 두 번 오르지 않는다. 반복 퀘스트 `repeat_claims`, `claimed` 단조성, `outcome.quests` 단조성 위반은 보상이 저장되고 `quests_not_saved`. `buy_from_shop` 재 부족·보관함 가득 참. `buy_once` 두 번. `unlock_place` 두 번째에 기록본 수가 그대로다 |

### 9.3 고칠 검사(말없이 빠지는 검사가 없어야 한다. 보고서에 "그대로 / v5로 옮김 / 바뀐 규칙으로 대체(이유)" 표를 붙인다)

| 파일 | 고칠 곳 [확인: 행 번호] | 방법 |
|---|---|---|
| `test_chapter_profile.gd` | 53행(`schema_version==4`), 251행(`-v4-r` 이름), 265·273·296행(가리키는 파일 이름 규칙: v5 이름은 받고 v4·v3 이름은 거부), 405행(`schema_version==4`), 그 밖에 `profile-v4.json` 같은 경로 이름 | 뜻은 그대로 두고 스키마 번호와 이름만 v5로 바꾼다. 경로 이름(`profile-v4.json`)은 QA 경로라 아무 이름이나 되지만, 읽는 사람이 헷갈리지 않게 v5로 바꾼다 |
| `test_profile_v4.gd` | 119행(`schema_version==4`) → 5. 491행은 **호환 파일 자체**의 번호라 4 그대로. 475~491행(V-17)은 `profile_v4_compat.json`을 본 경로로 읽는다. 이제 v4 원본(`legacy_v4`)으로 넘겨 옮겨야 한다. 468~472행(V-15 호환)도 같다. V-9의 경우 목록에 `town` 빠짐을 하나 더한다. 손으로 만드는 문서는 모두 지금 코드가 저장한 파일에서 출발하므로 자동으로 v5가 된다 [추정: 223, 258, 268, 297, 419, 440행이 모두 `profile.path`나 `paths.v4`에서 읽음]. `stage_v3`의 `"v4"` 경로 이름(59행)은 v5로 바꾼다 | 마커·`run_all.py` 줄 이름(`profile-v4`)은 그대로 둔다. 이 파일은 "v3 → 현재 스키마" 검사로 남는다 |
| `test_profile_legacy_fixtures.gd` | 88행(`schema_version==4`) → 5, 145~147행의 `chapter-one-profile-v4.json` 경로 → v5 이름, 3절 비교에 "`town`·`quests`·`records`는 기본값" 확인을 더한다 | 기대 파일(`expected_v3.json`)은 **고치지 않는다** |
| `profile_legacy_snapshot.gd` | 72행 본 경로 이름 → `chapter-one-profile-v5.json` | |
| `make_profile_legacy_fixtures.gd` | 고치지 않는다(이미 거부 장치가 있다) | |
| `hud_dump.gd` | 고치지 않는다. 실행 결과만 확인한다(8절 4) | |
| `test_profile_app_guard.gd`, `test_profile_app_loadout.gd` | 고치지 않는다(파일 이름·스키마 번호 참조 없음 [확인: Grep]). 통과만 확인한다 | |
| `tools/dev/run_all.py` | `profile-v4-fixtures`(S0)와 `profile-v5`(S1) 두 줄을 34~40행 묶음에 더한다 | 같은 `--work-dir=` 규칙 |

---

## 10. 지시서

공통 규칙(모든 지시서)
- 코드를 고치는 에이전트는 별도 작업 폴더에서 일한다. 커밋하지 않는다.
- `.gitattributes`가 `* -text`다. 줄바꿈을 바꾸는 도구로 기존 파일을 고치지 않는다. 새 파일은 UTF-8, LF. 새 `.gd` 파일의 `.uid`도 함께 둔다(Godot가 임포트 때 만든다. 임포트는 `python tools/dev/run_dev.py --import-only`).
- 검사는 `_local/` 아래 격리 경로만 쓴다. Godot는 `python tools/dev/godot.py …` 또는 `python tools/dev/run_all.py`로만 띄운다. 둘 다 `APPDATA`를 `_local/appdata/`로 돌린다. **사용자 폴더(`%APPDATA%\WitchMoira`)를 읽거나 쓰지 않는다. 열어 보지도 않는다.**
- `assert()` 안에 부작용을 넣지 않는다.
- 표현(view)과 시뮬레이션 코어를 고치지 않는다.
- 디렉터가 성능 측정 창(T2 계열)을 열어 둔 동안에는 같은 컴퓨터에서 Godot 검사를 돌리지 않는다. 시작 전에 디렉터에게 확인한다.
- 실행하지 않은 검사를 통과로 적지 않는다. 보고서에 실제 명령과 출력의 결과 줄(마커 줄)을 붙인다.

### T6-S0 — v4 고정 묶음(qa-perf, 지금 바로, 코드 변경 전에 반드시)

| 항목 | 내용 |
|---|---|
| 목적 | 스키마 5 코드가 들어가기 **전의** 실행본으로 v4 저장 파일과 "그 파일을 읽으면 무엇이 나오는가"를 고정한다. S1이 옮긴 결과를 이것과 대조한다. 코드가 바뀐 뒤에는 만들 수 없으므로 S1보다 먼저 끝나야 한다 |
| 시작 조건 | `chapter_profile.gd`를 고치는 작업이 없을 때. 작업 트리의 `chapter_profile.gd`가 커밋 `7de9f92`와 같은지 `git diff --quiet -- chapter1/core/chapter_profile.gd`로 확인하고 결과를 보고서에 적는다 |
| 만들 파일 | `chapter1/tests/make_profile_v4_fixtures.gd`(한 번 돌리는 생성기. `res://_local/` 아래에서 실제 `chapter_profile.gd`로 저장을 만들어 결과를 고정 폴더로 복사한다. `expected_v4.json`이 있으면 `quit(1)`), `chapter1/tests/profile_v4_snapshot.gd`(장면 정의와 `describe`. `profile_legacy_snapshot.gd`의 `describe()`를 재사용하거나 같은 꼴로), `chapter1/tests/fixtures/profile_v4/` 아래 9.1절의 파일, `chapter1/tests/test_profile_v4_fixtures.gd`(마커 `CHAPTER1_PROFILE_V4_FIXTURES_RESULT`: 묶음 sha256이 `expected_v4.json`과 같고, 지금 코드가 각 장면을 기대대로 읽는지), `tools/dev/run_all.py`에 `profile-v4-fixtures` 한 줄 |
| 건드리지 않을 파일 | `chapter1/core/` 전부, `chapter1/data/` 전부, 기존 검사 파일, `fixtures/profile_legacy/`, `fixtures/profile_v4_compat.json` |
| 통과 기준 | (1) `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/make_profile_v4_fixtures.gd` 종료 0. 한 번 더 돌리면 거부(종료 1). (2) `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_profile_v4_fixtures.gd` 실패 0. `v4_full`·`v4_compat`·`v4_journals_with_pointer`는 받아들이고 `v4_journals_main_only`는 `incompatible`이며 이어 하기 후보 리비전이 4. (3) `python tools/dev/run_all.py --quick` 통과. (4) 묶음 파일 목록과 sha256, 컴퓨터 경로·사용자 이름이 파일에 없다는 검색 결과를 보고서에 |

### T6-S1 — 프로필 스키마 5와 판 끝 기록(gameplay-systems)

| 항목 | 내용 |
|---|---|
| 목적 | 이 문서 3~6절과 7.1절. 새 파일 이름, `town`·`quests`·`records` 자리, v4→v5 옮기기, v3·v2·v1을 v5로 잇기, 너그러운 읽기·엄격 쓰기, 거부 흐름, `record_run`의 판 수·기록 |
| 시작 조건 | T6-S0 검수 통과. 디렉터 결정 T6-D1·D2·D5·D6·D7·D10(D8은 넣을지 말지만). `chapter_profile.gd`를 고치는 다른 작업이 없을 때. **W7(전투 기록)이 `records.last`의 꼴(4.3)을 받아들였는지** 디렉터가 확인 |
| 고칠 파일 | `chapter1/core/chapter_profile.gd`(상수 19~28·34·37행, `fresh` 149~152, `default_entry` 155~160, `configure` 167~200, 새 `_v4_source`·`_v4_source_resume`·`_v4_journal_resume`·`upgrade_v4`·`import_v4_text`, `_reject` 375~384, `_read_body` 635~758(637행 번호, 753행 `from_schema` 0~5, `town` 검사, 733행 v4 꼴 되살리기), `_read_character` 821~918(`quests`·`records`), `_document` 921~942, `_persist` 977행(`imported_from_v4`), `record_run` 1008~1058(`outcome`, `runs`/`wins`/`last`/`best`), 새 읽기 함수 7.1절. 2~12행의 머리 주석도 스키마 5로), 9.3절 표의 검사 파일, 새 `chapter1/tests/test_profile_v5.gd`(9.2절 V5-1~V5-17), `tools/dev/run_all.py`(`profile-v5` 한 줄) |
| 남길 것 | `upgrade_v3`, `normalize`, `upgrade_v1`, `migrated_characters`, `import_v3_text`, `import_v2_text`, `import_v1_text`, `TOP_KEYS_V3/V2`, `CHAR_KEYS_V3`, v3 가리키는 파일 길. 모두 옮기기용이다 |
| 건드리지 않을 파일 | `chapter1/app/chapter_one.gd`(S1은 앱을 고치지 않는다. 기본 인수만으로 v5가 열린다), `chapter1/view/` 전부, `chapter1/core/`의 `chapter_profile.gd` 밖 전부(`loot.gd`, `chapter_core.gd`, `character_progression.gd` 포함), `chapter1/data/` 전부, `golden_core.gd`와 골든 기준 파일, `fixtures/profile_legacy/`, `fixtures/profile_v4/`, `fixtures/profile_v4_compat.json`, `fixtures/loot_compat_items.json`, `CLAUDE.md` |
| 지킬 계약 | (1) 지금의 공개 함수 시그니처는 뒤에 인수를 더하는 것 말고는 바꾸지 않는다(`configure`, `record_run`). (2) `state`의 키 이름과 뜻은 그대로이고 `town`만 더한다. 화면이 읽는 `hud.profile_state`(앱 540~542행)가 깨지지 않는다. (3) 저장 한 번 = `_persist` 한 번. 판 끝 저장의 원자성(1003~1007행 주석)을 지킨다. (4) 읽기는 아무 파일도 쓰지 않는다 |
| 통과 기준 | (1) `python tools/dev/run_all.py` **전체** 통과(골든 4 + 글 없는 골든 4 불일치 0, 드랍 시뮬레이션, `profile`, `profile-legacy`, `profile-v4`, `profile-v4-fixtures`, `profile-v5`, `app-guard`, `app-loadout`). (2) V5-1~V5-17의 결과 줄(마커 줄 전문). (3) 9.3절 고친 검사의 대응표: 검사마다 그대로 / 옮김 / 대체(이유). 개수가 줄었으면 그 이유. (4) `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --profile-fixture=rejected --shots=_local/shots/t6-rejected --dump=_local/shots/t6-rejected.json`의 `HUD_DUMP_REJECT` 줄과 시점 이름 목록. (5) `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_progression.gd -- --runs=1`이 오류 없이 끝난다. (6) 8절 1의 `git diff --stat` 출력. (7) 소스 검사 결과: `chapter1/` 아래 `user://`가 나오는 곳 목록과 각 이유, `remove_absolute` 0건(테스트 밖). (8) 6.3절에서 화면이 `resume.kind`를 읽는 곳(Grep 결과, 고치지 않음) |
| 멈추고 보고할 때 | 골든·글 없는 골든·드랍 시뮬레이션이 하나라도 바뀜. 고정 묶음이 기대와 다르게 읽힘(묶음이나 기대 파일을 고쳐서 통과시키지 않는다). `chapter_profile.gd` 밖을 고쳐야 할 것 같음 |

### T6-S2 — 퀘스트·마을 쓰기 함수(gameplay-systems, W9 설계와 함께)

| 항목 | 내용 |
|---|---|
| 목적 | 7.2절의 함수와 `record_run`의 `outcome.quests` |
| 시작 조건 | T6-S1 검수 통과. W9의 퀘스트 데이터 꼴(`quests.json`, D11 E3)과 마을 장소·구매 id 목록이 정해짐(파일은 아직 없어도 된다. 시험 훅으로 검사). 디렉터 결정 T6-D3·D4 |
| 고칠 파일 | `chapter1/core/chapter_profile.gd`(7.2절 함수, `use_ids_for_test`의 키 셋 추가, `record_run`의 `outcome.quests`), `chapter1/tests/test_profile_v5.gd`(V5-20~) |
| 건드리지 않을 파일 | S1과 같음. 데이터 파일(`quests.json`, `character_progression.json`)은 W9·content-balance가 만든다 |
| 통과 기준 | `run_all.py` 전체 통과(골든 불변), V5-20~의 결과 줄, 함수마다 성공·거부 표. 거부 때 파일 바이트가 그대로라는 확인 |

S2를 W9 지시서에 합쳐도 된다. 다만 같은 사람이 같은 차례에 `chapter_profile.gd`를 고쳐야 한다(11절의 파일 겹침).

---

## 11. 순서·의존·파일 겹침

```
지금 바로:            T6-S0 (qa-perf)        ← 다른 에이전트의 성능 측정이 끝난 뒤 실행
디렉터 결정 D1·D2·D5~D7·D10, W7이 4.3 꼴을 받아들임
                      ↓
T6-S0 검수 ─────────▶ T6-S1 (gameplay-systems) ─▶ [검수] ─┬─▶ W7 앱 연결(record_run의 outcome.record를 넘김)
                                                         └─▶ T6-S2 (W9 설계와 함께) ─▶ W9 마을 허브
```

병렬로 돌릴 수 있는 것: T6-S0은 W0(측정 도구, `content-balance`)·W1(리듬 코어)과 파일이 겹치지 않는다. T6-S1도 W1~W5와 파일이 겹치지 않는다(코어·데이터를 고치지 않음). 단 `run_all.py`는 차례대로 고친다.

| 파일 | 이 문서의 단계 | 겹치는 다른 작업 | 규칙 |
|---|---|---|---|
| `core/chapter_profile.gd` | S1, S2 | T5-S3(기록본 보존, 미착수), W9 | S1 → S2 → (T5-S3) 차례로. 동시 금지 |
| `app/chapter_one.gd` | 없음 | W7, W9, W1 | T6은 고치지 않는다 |
| `tests/test_chapter_profile.gd`, `test_profile_v4.gd`, `test_profile_legacy_fixtures.gd`, `profile_legacy_snapshot.gd` | S1 | 없음 | — |
| `tools/dev/run_all.py` | S0(한 줄), S1(한 줄) | W0(측정 도구 추가 가능성) | 차례로, 줄 더하기만 |
| `data/character_progression.json` | 없음(T6-D4는 W9·content-balance) | W5(`grade_bonus_bps`) | T6은 고치지 않는다 |

---

## 12. 위험과 되돌리는 길

| # | 위험 | 막는 것 | 되돌리는 길 |
|---|---|---|---|
| R1 | **보상 단계 경험치 보너스(W5, D11 D3 +10~30%)로 한 판 `xp_gained`가 `run_xp_max`를 넘으면 `apply_progress`가 거부하고(991행), `record_run`이 저장 전체를 거부한다(1016행).** 장비·재·경험치를 모두 잃고 결과 화면에 "저장 실패"가 뜬다. 퀘스트 경험치를 판 경험치에 섞어도 같은 일이 생긴다 | W5 지시서에 "`character_progression.gd` `xp_bounds`의 `run_xp_max`에 최대 단계 보너스를 반영"을 넣는다(디렉터가 W5에 전달). 퀘스트 경험치는 `claim_quest`의 별도 상한으로 준다(7.2) | W5 검수에서 단계 Ⅳ 판의 `record_run` 성공을 확인 |
| R2 | S1 뒤에 W7·W9가 `last`나 `quests`의 꼴을 바꾸고 싶어 함 → 스키마 6 | S1 시작 전에 W7·W9 담당과 디렉터가 4.2~4.3절의 꼴을 확인(T6-D11). `last`는 원칙 7에 따라 깨져도 거부하지 않음 | 꼴이 바뀌면 스키마 6. 같은 방식으로 한 번 더 옮긴다 |
| R3 | 옮기기가 v4 원본을 바꿈 | v5 실행본은 v4 시대 파일을 쓰지 않는다. V5-1·V5-6이 폴더 sha256으로 확인 | v5 파일을 치우면 v4가 그대로 읽힌다(그 뒤의 진행은 잃는다, 5.4) |
| R4 | 사용자의 v4에 격리될 장비·마녀가 있음 | 옮기기는 지금 v4 읽기 규칙과 같다(이미 v4 실행본이 같은 판정을 하고 있다) | 격리 원본은 `quarantine`에 남아 데이터가 맞으면 되살아난다 |
| R5 | 화면이 모르는 `resume.kind`(`v4_source`, `v4_journal`)를 받음 | S1이 화면이 읽는 곳을 찾아 보고(통과 기준 8). 문구는 ui-hud의 다음 작업 | 화면이 kind를 몰라도 파일 이름·리비전은 보인다 [추정] |
| R6 | 판 수가 S1 전의 판을 세지 못함(`runs`가 0에서 시작) | 받아들인다. 현상금 판정과 진열 새로고침은 상대 비교라 영향이 없다 | — |
| R7 | 기록본이 계속 쌓임(T5-S3 미착수) | v5도 판당 저장 횟수는 그대로다(`record_run` 한 번). S2의 마을 행동(받기, 사기)이 저장을 늘린다 | T5-S3을 S2 뒤에 배정하기를 권한다(디렉터) |
| R8 | 옛 v4 실행본으로 돌아가 놀면 진행이 갈라짐 | 옛 실행본을 배포하지 않음. T6-D8(더 새 파일 표시) | 안내 문서 |
| R9 | 검사 대량 수정 중에 검사가 말없이 빠짐 | 9.3절의 대응표를 통과 기준으로 둔다 | 검수에서 개수를 대조 |
| R10 | `CLAUDE.md` "저장" 절이 스키마 3으로 적혀 있어 다른 에이전트가 틀린 파일 이름을 씀 | 디렉터가 S1 뒤에 v5로 고친다 | — |

---

## 13. 디렉터가 정할 것

| # | 결정 | 선택지 | 권고와 이유 |
|---|---|---|---|
| T6-D1 | 퀘스트는 마녀별인가 계정 공용인가 | 마녀별 / 공용 | **마녀별**(D11 E4). 세 마녀의 이야기가 따로다. 서사 판정은 `narrative-lead`가 W9 전에 한다. 공용으로 바꾸면 `quests`를 최상위로 옮겨야 하므로 S1 전에 정한다 |
| T6-D2 | 마을(열린 장소, 상점 진열, 한 번만 산 물건)은 공용인가 | 공용 / 마녀별 | **공용**. 재와 보관함이 공용이다. 진열의 아이템 레벨은 세 마녀 `depth_cleared`의 최댓값으로 계산한다(W9) |
| T6-D3 | 옮길 때 퀘스트를 소급 완료할 것인가(이미 수호자·우두머리를 잡은 마녀) | 하지 않음 / `first_rewards`로 이야기 퀘스트를 `done`에 | **하지 않음.** `quests.json`이 아직 없어 소급 규칙이 데이터에 묶이고, 상점 개방이 늦어지는 문제는 첫 이야기 퀘스트를 쉽게 하는 것으로 푼다(W9·content-balance) |
| T6-D4 | 퀘스트 스킬 포인트를 어디에 두나 | `first_rewards`에 퀘스트 보상 id + `character_progression.json` / 새 저장 키 | **`first_rewards`.** 포인트 계산·상한·투자 검사 코드가 그대로다. 데이터 수정은 W9 때 content-balance가 한다. D4의 "첫 처치 보상과 겹치지 않게 영수증"도 이 방식으로 만족한다 |
| T6-D5 | `records.last`가 깨졌을 때 | 버림 / 파일 거부 | **버림.** 다음 판에 다시 생기는 표시용 값이다. 거부하면 기록 하나 때문에 장비 전체에 손이 닿지 않는다. "최근 60초 초당 피해"는 저장하지 않는다 |
| T6-D6 | 상점 진열 장비가 데이터와 안 맞을 때 | 버림 / `quarantine` | **버림.** 아직 가진 물건이 아니다. 격리하면 `storage_id`가 없는 항목이 생겨 격리 규칙이 복잡해진다 |
| T6-D7 | 최고 기록을 깊이별로 | 깊이 사전 / D11의 단일 값 | **깊이 사전.** 깊이가 늘어도 스키마 6이 필요 없다 |
| T6-D8 | 더 새 저장 파일(`-v6` 이후)이 옆에 있으면 알릴 것인가 | 알림(읽지 않고 이름만) / 하지 않음 | **알림.** 비용이 작고, 되돌아간 실행본이 조용히 옛 진행을 읽는 일을 드러낸다. 화면 문구는 나중 |
| T6-D9 | S2를 따로 둘지 W9에 합칠지 | 따로 / 합침 | **따로, W9 직전.** 저장 안전 검사가 마을 화면 작업에 묻히지 않게 한다 |
| T6-D10 | v5가 거부되고 v5 기록본도 없을 때 v4 원본에서 다시 옮겨 오기를 이어 하기 후보로 | 넣음 / 빼고 빈 저장 | **넣음**(T5-D6과 같은 이유) |
| T6-D11 | S1 시작 조건으로 W7·W9 담당이 4.2~4.3절의 꼴을 받아들이게 할 것인가 | 예 / 아니오 | **예.** 꼴을 S1 뒤에 바꾸면 스키마 6이다. W7의 F1 숫자 목록이 바뀔 여지가 있으면 S1 전에 정한다 |
| (전달) | R1: W5 지시서에 `run_xp_max` 보정을 넣기 | — | 넣지 않으면 단계 Ⅳ 판의 저장이 실패한다 |
| (전달) | `CLAUDE.md` "저장" 절을 스키마 5로 고치기(S1 뒤) | — | 지금도 스키마 3으로 잘못 적혀 있다 |

---

## 14. 확인하지 못한 것

- 이 문서를 쓰는 동안 Godot·회귀·시뮬레이션을 하나도 돌리지 않았다(디렉터 지시). `run_all.py`의 지금 통과 여부, 검사 개수(T5 19절 당시 profile 115개)는 지금 실행으로 확인하지 않았다.
- `test_profile_v4.gd`가 손으로 만드는 문서가 모두 지금 코드가 저장한 파일에서 출발하는지는 행을 훑어 본 [추정]이다. S1이 고치면서 확인한다.
- `hud_dump.gd`의 `rejected` 고정 묶음이 v5에서도 고치지 않고 도는지는 코드를 읽고 한 [추정]이다(경로·이름을 스스로 정하고 구조 깨기는 스키마와 무관).
- 화면(`chapter_hud.gd`)이 `resume_info().kind`를 어떻게 쓰는지 읽지 않았다(R5).
- 사용자 저장이 지금 스키마 4인지, 격리될 것이 있는지 보지 않았다(사용자 폴더를 열지 않는다).
- W7(`RunRecord`)과 W9(`quests.json`)의 최종 꼴은 아직 없다. 4.2~4.3절은 D11 F1·E3·E4를 바탕으로 한 안이다.
- 스팀 자동 클라우드 패턴에 `-v5*`를 더해야 하는지는 T4-C의 일이다(T5 18절과 같음).
