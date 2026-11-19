# 기술 지시서 T6 — 저장 스키마 5(퀘스트·전투 기록·마을)

2026-11-19, 기술 책임자(tech-lead) 작성. **2026-11-20 개정**: T6-S0 완료 반영, 디렉터 결정(13절) 반영, D12의 저장 자리(S5-1~S5-4)와 질문 Q-T1~Q-T5 반영, `records.last`를 너그러운 꼴로 바꿈, 회귀 도구(`run_all.py --jobs`, 별칭, 골든 한 판 묶음)와 점검 절차에 맞춤. 고친 절의 제목에 "(2026-11-20 개정)"을 붙였다.

총괄 디렉터가 배정한다. 10절의 지시서는 받는 에이전트에게 그대로 넘길 수 있게 썼다. 받는 쪽은 이 문서와 여기에 적힌 파일만 보고 일할 수 있어야 한다.

근거: `docs/specs/D11-run-rhythm-and-reward-loop.ko.md`(D4, E1~E4, F1, H1의 W7·W8·W9), `docs/specs/D12-skill-and-gear-redesign.ko.md`(맨 앞 "★ 저장 스키마 5에 지금 넣어야 하는 자리", C5·C6, D4.4, G4, H-4·H-8), `docs/specs/T5-schema4-directives-20261117.ko.md`(스키마 4의 원칙·흐름·검사), `docs/specs/D5-save-safety-spec.ko.md`, `chapter1/core/chapter_profile.gd`(1308줄), `chapter1/core/chapter_core.gd`(`progress_summary` 312~319행), `chapter1/core/character_progression.gd`(145~148행), `chapter1/core/skill_tree.gd`(`legal_ranks` 453~469행), `chapter1/core/loot.gd`(`validate` 296~346행), `chapter1/app/chapter_one.gd`(348~606행), `chapter1/tests/`의 `test_chapter_profile.gd`·`test_profile_v4.gd`·`test_profile_legacy_fixtures.gd`·`profile_legacy_snapshot.gd`·`make_profile_legacy_fixtures.gd`·`test_profile_v4_fixtures.gd`·`profile_v4_snapshot.gd`·`hud_dump.gd`(1~44, 119~216행)·`sim_progression.gd`, `chapter1/tests/fixtures/profile_legacy/README.ko.md`, `chapter1/tests/fixtures/profile_v4/`(S0 묶음), `chapter1/tests/fixtures/profile_v4_compat.json`, `tools/dev/run_all.py`(41~89, 98~125행), `tools/dev/snapshot_diff.py`, `docs/PROCESS-CHECKS.ko.md`, `docs/TOOLS-INDEX.ko.md`, S0 보고서 `_local/t6/S0-REPORT.ko.md`.

표기: [확인]은 파일을 읽어 본 것, [추정]은 읽은 것에서 미루어 본 것, [미확인]은 확인하지 못한 것. 이 문서를 쓰고 고치는 동안 **Godot·회귀·시뮬레이션은 하나도 돌리지 않았다.** 그래서 실행 결과로 확인한 줄은 없다(S0의 실행 결과는 S0 보고서를 옮긴 것이다). 행 번호는 작업 트리(커밋 `f36b0a7`)의 파일 기준이다. `chapter_profile.gd`, `chapter_one.gd`, `test_chapter_profile.gd`, `test_profile_v4.gd`, `test_profile_legacy_fixtures.gd`, `profile_legacy_snapshot.gd`, `skill_tree.gd`, `character_progression.gd`는 커밋 `7de9f92`에서 바뀌지 않았다(`git diff --stat 7de9f92 HEAD`, 2026-11-20). 바뀐 것은 `chapter_core.gd`(`progress_summary`가 236행 → 312행으로 옮김)와 `hud_dump.gd`(인수 검사가 더해짐)다.

---

## 0. 디렉터용 요약 (2026-11-20 개정)

1. 스키마 5는 새 파일 `user://chapter-one-profile-v5.json`이다. v4 파일(본 파일, 기록본, r-파일, v4 가리키는 파일)은 **읽기만 하고 한 바이트도 쓰지 않는다.** 첫 정상 저장 때 v5 파일이 생긴다. 스키마 3→4 때와 같은 길이다.
2. 더하는 것: 최상위 `town`(마을: 열린 장소, 한 번만 산 물건, 상점 진열, **보장 문턱 진행값 `luck`**), 마녀 항목의 `quests`(퀘스트 상태), `records`(판 수, 지난 판 기록, 던전별 최고 기록), **`grace`(은총 영구 금지 목록)**, 그리고 장비의 선택 키 **`forge`·`rerolls`**. 이미 있는 키는 하나도 빼거나 바꾸지 않는다.
3. D12가 요구한 네 자리(S5-1~S5-4)를 모두 **빈 기본값으로** 연다(4.1, 4.2, 4.7). 강화·다시 굴리기(H-4)와 영구 금지(H-8)는 기능이 보류이거나 미정이라, 이번에는 자리와 읽기·쓰기 검사만 들어가고 그 값을 바꾸는 함수는 없다. 열지 않으면 그 기능만을 위해 스키마 6이 필요하다.
4. `records.last`는 **핵심 키는 엄격, 그 밖의 키는 꼴만 맞으면 보존하는 너그러운 꼴**로 바꾼다(4.3, T6-D14). 그래서 W7(전투 기록기)이 뒤에 숫자를 더해도 스키마를 올리지 않는다. S1의 시작 조건 가운데 W7에 걸린 것은 "W7 보고가 온 뒤 디렉터가 4.3절 핵심 키를 확정"으로 줄었다.
5. 퀘스트로 받는 스킬 포인트는 따로 저장하지 않는다. `character_progression.json`의 첫 처치 보상 목록에 퀘스트 보상 id를 넣고, 지금 있는 `first_rewards` 길로 준다(T6-D4, 채택). 포인트 계산 코드도 바뀌지 않는다.
6. 스킬 트리를 다시 짜는 일(D12 C장, 3판 작성 중)은 **저장 꼴을 바꾸지 않는다.** 트리 개정은 `tree_revision`을 올리면 지금 코드가 투자를 전액 반환한다(4.8, Q-T1). 판 안 스킬 구성은 저장되지 않으므로 영향이 없다.
7. 거부·복구 흐름은 스키마 4와 같다. 거부 종류는 셋(`damaged`, `incompatible`, `legacy`), 원본은 그대로 두고, 기록본에서 이어 하기와 새 저장으로 시작하기를 쓴다. 달라지는 곳은 셋이다. ① 이어 하기 후보에 "v4 원본을 다시 옮겨 오기"가 들어간다. ② v4 기록본은 본 파일 옆이 아니라 `revisions/` 하위 폴더에 있다. ③ 새 기록 칸(`records.last`, 상점 진열)은 깨져도 파일을 거부하지 않고 버린다. 다시 만들어지는 표시용 값이기 때문이다(T6-D5·D6).
8. 일은 셋이다. **T6-S0** v4 고정 묶음 — **끝남**(커밋 `2ed41f0`, 검사 `profile-v4-fixtures`). **T6-S1** 프로필 v5와 판 끝 기록(gameplay-systems) — 10절의 지시서로 **바로 배정할 수 있다**(남은 시작 조건은 10절 T6-S1 표). **T6-S2** 퀘스트·상점 쓰기 함수(gameplay-systems, W9 직전, T6-D9).
9. 코어 골든에는 영향이 없어야 한다. 시뮬레이션 파일과 데이터는 고치지 않는다. 골든·측정 도구가 프로필을 읽지 않는다는 것을 정적 검사로 묶어 둔다(V5-16). `python tools/dev/run_all.py --jobs 4` 전체에서 `golden`, `golden-textless`, `core-text`, `loot-sim`의 불일치가 0이어야 하고 `--update`는 하지 않는다.
10. 가장 큰 위험은 스키마 밖에 있다(그대로). 보상 단계 경험치 보너스(D11 D3, W5)를 넣으면 한 판 경험치가 `run_xp_max`를 넘는다. 그러면 `apply_progress`가 **저장 전체를 거부**한다(`chapter_profile.gd:991`). W5에서 막아야 한다(12절 R1).
11. 문서 불일치(그대로, 디렉터 몫): `CLAUDE.md`의 "저장" 절은 아직 "스키마 3, `chapter-one-profile-v3.json`"이다. 코드는 스키마 4다(`chapter_profile.gd:2,19`). S1이 끝나면 디렉터가 v5로 고친다(하위 에이전트는 `CLAUDE.md`를 고치지 않는다).

---

## 1. 지금의 저장(스키마 4) [확인: 파일을 읽음] (2026-11-20 개정)

| 항목 | 지금 | 위치(`chapter_profile.gd`) |
|---|---|---|
| 파일 | 본 `user://chapter-one-profile-v4.json`, 읽기만 하는 `-v3`·`-v2`·`-v1`, 가리키는 파일 `-v4-active.json`(v3은 `chapter-one-profile-active.json`), 거부 뒤 새 저장 `-v4-r<시각>[-n].json` | 19~28 |
| 최상위 키 | `TOP_KEYS` 14개를 **정확히** 맞춘다(`keys_match`) | 34, 636 |
| 마녀 키 | `CHAR_KEYS` 10개를 정확히 맞춘다 | 37, 823 |
| 장비 키(문법 2) | 필수 `ITEM_KEYS_V4` 8개 + 선택 `ITEM_KEYS_V4_OPTIONAL`(`legendary_id, rare_words, legacy_name, veiled`). 모르는 키는 장비 검사 실패(→ 격리) | 43~44, 785~788 |
| 스키마 번호 | `Catalog.integer(value.schema_version,4,4)`. 아니면 `incompatible` | 637 |
| 새 문서·기본 항목 | `fresh()`, `default_entry()` | 149~160 |
| 읽는 순서 | v4 가리키는 파일 → v4 본 → v3(가리키는 파일 → 본) → v2 → v1. 먼저 있는 것이 정하고, 거부되어도 아래로 내려가지 않는다 | 167~200 |
| v3→v4 | `upgrade_v3()`가 v4 문서를 만들고 `read_document(...,false)`(너그러운 읽기)로 받는다. v2·v1은 `normalize`/`upgrade_v1` → `_as_v3_document` → `upgrade_v3` | 389~438, 476~520 |
| 너그러운 읽기 | 장비가 데이터와 안 맞으면 `quarantine`으로 옮기고, 모르는 마녀도 `quarantine`으로 옮긴다. 모르는 id는 보존하고 `read_report`에 센다 | 635~758, 821~918 |
| 격리된 마녀 되살리기 | `Catalog.keys_match(set_aside.raw,CHAR_KEYS)`일 때만 | 733 |
| `origin` | `from_schema` 0~4. 옮길 때 메모리의 `origin`은 0이고 `_origin_hint`가 출처를 들고 있다가 첫 저장 때 채운다 | 96, 436, 753, 949~950 |
| 파일 꼴 | `_document()`가 `schema_version` 4를 **박아 넣는다**. 장비 사전은 `name`·`description`만 떼고 나머지 키를 그대로 복사한다 | 921~942 |
| 쓰기 | `_persist`: 엄격 검사 → 다른 실행이 바꿨는지 확인 → `revisions/` 기록본 → 임시 파일 → 바꿔 끼우기 → 다시 읽어 확인 | 946~978 |
| 기록본 | `<폴더>/revisions/<본 바탕>.revision-<rev6>-<YYYYMMDD>-<pid>-<usec>.json` | 242~251, 962~963 |
| 거부 | `_reject(kind,…)`: 파일을 쓰지 않고 로그 한 줄만 남긴다. 이어 하기 후보는 v4 기록본 → v3 원본을 다시 옮김(`_v3_source_resume`). `legacy`일 때는 v3 기록본(본 파일 **옆**) | 375~384, 268~299 |
| 새 저장으로 | `start_fresh_after_reject`: v4가 거부되면 r-파일과 가리키는 파일, 옛 형식만 거부되면 본 경로에 새로(가리키는 파일 없음) | 331~360 |
| 판 끝 저장 | `record_run(receipt, inventory, pending, victory, ticks, progress={}, carry={})`. 한 번에 원자적으로 쓴다. 같은 영수증이면 아무것도 하지 않는다. `carry`가 잘못되면 보상만 저장하고 `carry_note="kit_not_saved"`를 남긴다 | 1008~1058 |
| 경험치 상한 | `apply_progress`가 `xp_gained`를 `0..run_xp_max`로 검사한다. `run_xp_max = seal+champion+boss+victory` | 991, `character_progression.gd:145` |
| 트리 투자 읽기 | 트리 없는 마녀에 투자가 있으면 반환. `tree_revision`이 데이터와 다르면 `ranks={}`(모르는 노드 id까지 전부)로 반환하고 알림. 같은 리비전이어도 `SkillTree.legal_ranks`가 문제를 내면(모르는 노드, 랭크 범위, 레벨, 포인트, 선행) 전액 반환. 엄격 쓰기에서는 모두 거부 | 842~859 |
| 의상 | `wardrobe.owned`(64개 이하) + 데이터의 `default_owned`. 화면의 소유 목록은 둘의 합(`wardrobe_view`) | 889~898, 1185~1210 |
| 영수증 | 64개까지만 두고 넘치면 앞에서 버린다 | 1053~1054 |
| 시험 훅 | `use_data_for_test(loot_path)`, `use_ids_for_test({story,collectibles,shared})` | 123~132 |
| 기록본 지우기(T5-S3) | **구현되지 않았다** | Grep |
| T5-Q1 독립 검사 | `chapter1/tests/test_profile_v4_guard.gd`가 **없다** | Glob |

앱 [확인: `chapter_one.gd`]: 377행의 `profile.configure()`는 기본 인수로 부른다. 판 끝 저장은 594~598행(`run.progress_summary()`, `carry`, `record_run`)이다. `progress_summary()`가 내놓는 키는 `character_id, xp_gained, sources{seal,champion,boss,victory}, first_kills, level_before, level_after`다(`chapter_core.gd:312~319`). 퀘스트를 세는 데 쓸 처치·정예·상자 수는 **아직 없다**(W1·W5·W7·W9의 일).

검사 [확인: `run_all.py` 98~125행]: 프로필 쪽은 `profile`(`test_chapter_profile.gd`), `app-guard`, `profile-legacy`(`test_profile_legacy_fixtures.gd`), `profile-v4`(`test_profile_v4.gd`), `profile-v4-fixtures`(`test_profile_v4_fixtures.gd`, S0), `app-loadout`이다. 별칭 `profile-all`(42행)이 이 여섯을 묶고, `--changed`의 `app` 선택(84행)도 같은 여섯을 고른다. 옛 저장 고정 묶음은 `fixtures/profile_legacy/`(v3·v2·v1), v4 고정 묶음은 `fixtures/profile_v4/`(S0), v4 호환 파일은 `fixtures/profile_v4_compat.json`이다.

S0 실행 때의 검사 개수(S0 보고서, `run_all.py --quick`, 커밋 `67b2184`): `profile` 124, `profile-legacy` 298, `profile-v4` 120, `profile-v4-fixtures` 44, `app-guard` 5, `app-loadout` 14. S1은 이 숫자를 시작 커밋에서 다시 잰 값과 대조한다(10절).

---

## 2. 원칙(T5 2절을 그대로 잇는다) (2026-11-20 개정)

1. **옛 파일은 읽기만 한다.** v5 실행본은 v4·v3·v2·v1 시대의 모든 파일(본, r-파일, 기록본, 가리키는 파일)을 쓰지도, 이름을 바꾸지도, 지우지도 않는다.
2. **사실만 저장하고, 계산할 수 있는 것은 저장하지 않는다.** 퀘스트 스킬 포인트(→ `first_rewards`로 계산), 상점 아이템 레벨(→ `depth_cleared`로 계산), 상점 가격(→ 데이터로 계산), 전체 판 수(→ 마녀별 `records.runs`의 합), 장비로 오른 트리 랭크(→ 착용 장비로 계산, Q-T4), 강화된 능력치(→ `forge`와 데이터로 계산, 4.7)가 여기에 든다.
3. **저장 파일에 화면 글을 넣지 않는다.** 퀘스트·장소·물건·카드는 id만 둔다. 상점 진열 장비는 `items`와 같은 글 없는 꼴로 둔다. `records.last`의 문자열 값은 id 꼴만 받는다.
4. **읽기는 너그럽게, 쓰기는 엄격하게.** 읽은 결과는 언제나 엄격한 쓰기 검사를 통과해야 한다(불변식, V5-13).
5. **새로 더하는 것은 엄격하게, 이미 있는 것은 보존한다.** 퀘스트·장소·구매·카드 id를 새로 쓰는 함수는 데이터에 있는 id만 받는다. 저장된 id가 데이터에서 사라져도 지우지 않는다. 예외는 트리 투자(`ranks`)다. 투자는 포인트로 다시 계산되는 값이라 데이터와 안 맞으면 전액 반환한다(지금 규칙, 4.8).
6. **스키마 5 안에서는 키를 더하지 않는다.** 그래서 마을·퀘스트·기록·금지 목록·장비 손질의 자리를 이번에 한꺼번에 연다. 아직 쓰지 않는 자리는 기본값으로 둔다. 예외 하나: `records.last`의 핵심 키 밖 자리(4.3)는 처음부터 "꼴만 맞으면 받는" 열린 자리로 정의한다. 키를 더하는 것이 아니라 열린 자리를 쓰는 것이다.
7. **다시 만들어지는 표시용 값은 깨져도 파일을 거부하지 않는다.** `records.last`, `records.best`의 한 항목, 상점 진열 한 개가 그렇다. 버리고 센다(`dropped_record`, `dropped_stock`). 플레이어가 **가진 것**(장비, 재, 경험치, 퀘스트 완료, 강화 단계, 보장 문턱 진행값, 금지 목록)은 버리지 않는다. 깨진 장비는 지금처럼 원본째 `quarantine`으로 간다.

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

### 4.1 최상위(키 집합은 정확히 이것) (2026-11-20 개정)

`TOP_KEYS_V5 = TOP_KEYS(v4의 14개) + ["town"]`. 지금의 `TOP_KEYS`는 `TOP_KEYS_V4`로 남긴다(옮기기용).

| 키 | 형 | 기본값 | 범위·검증 | 깨졌을 때(읽기) |
|---|---|---|---|---|
| `schema_version` | int | 5 | 정확히 5 | 거부 `incompatible` |
| v4의 13개 키 | 지금과 같음 | 지금과 같음 | 지금과 같음. 다만 `origin.from_schema`는 **0~5**(753행) | 지금과 같음 |
| `town` | 사전, 키는 정확히 `unlocked, bought, shop, luck` | 4.4 | 아래 | 키 집합이나 형이 다르면 거부 |

**`town.unlocked`** — 마을에서 열린 장소 id 목록. 계정 공용이다(T6-D2, 채택).
- 형: 문자열 배열, **16개 이하**, 각 원소는 `ID_PATTERN`(47행), 기본값 `[]`.
- 처음부터 열려 있는 장소는 데이터(W9가 만들 마을 데이터)가 정하고 저장에 쓰지 않는다. 의상의 `default_owned`와 같은 방식이다. 저장에는 퀘스트 보상 등 **사건으로 연** 장소만 들어간다. 데이터 쪽 규칙: 처음부터 열린 장소를 나중에 "닫힌 장소"로 바꾸지 않는다(4.8의 의상 규칙과 같은 이유).
- 모르는 id는 보존(`unknown_ids`), 중복은 하나로 줄인다(`deduped`). 쓸 때 중복이면 거부한다.

**`town.bought`** — 한 번만 사는 물건(예: 회수약 상한 올리기) id 목록. 계정 공용이다. D11에는 없는 키라 이번에 더했다(T6-D2).
- 형: 문자열 배열, **32개 이하**, `ID_PATTERN`, 기본값 `[]`. 보존·중복 규칙은 `unlocked`와 같다.
- 이 값을 판에 넘기는 일(회수약 상한을 코어 빌드에 넣는 것)은 W9의 일이다. 그때 코어 입력이 바뀌지만 골든은 프로필을 읽지 않으므로 그대로다(8절).

**`town.shop`** — 상점 진열. 계정 공용이다. 키는 정확히 `seed, refreshed_run, stock`.

| 키 | 형 | 기본값 | 검증 |
|---|---|---|---|
| `seed` | int | 0 | 0~2147483647 |
| `refreshed_run` | int | 0 | 0~10억. 진열을 새로 뽑았을 때의 **전체 판 수**(알려진 마녀 `records.runs`의 합). 앱은 지금 전체 판 수가 이 값보다 크면 진열을 새로 뽑는다(W9) |
| `stock` | 배열 | `[]` | **8개 이하.** 각 원소는 문법 2 장비의 파일 꼴(`ITEM_KEYS_V4` 필수 키 + 선택 키 `legendary_id`, `rare_words`, `legacy_name`). `name`·`description`이 없고, 희귀는 `rare_words` 또는 `legacy_name`을 가진다. v1 장비(`grammar` 없음)는 받지 않는다. **`veiled`, `forge`, `rerolls`는 진열 장비에 두지 않는다**(아직 가진 물건이 아니다. 산 뒤에 붙는다). 가격은 저장하지 않는다(데이터로 계산) |

- 진열 장비 하나가 지금 데이터와 안 맞거나 금지된 키를 가지면 읽을 때 **그 장비만 버리고** `dropped_stock`에 센다(T6-D6, 채택). 플레이어가 가진 물건이 아니고, 다음 진열 때 다시 뽑히기 때문이다. 쓸 때는 거부한다. (W9가 흐린 진열을 원하면 그때 `veiled`를 풀어도 된다. 옛 v5 실행본은 그 진열 장비를 버릴 뿐 파일을 거부하지 않는다.)
- 진열 장비는 메모리에서도 글 없는 꼴로 둔다. 화면에 보여 줄 때는 W9가 `loot.dress`로 옷을 입힌다. `items`처럼 메모리에서 이름을 다시 지어 넣지 않는다. 그러면 `_document`가 진열 장비를 따로 손볼 필요가 없다.

**`town.luck`** — 도박·강화의 보장 문턱(천장) 진행값. 계정 공용이다(재와 보관함이 공용이므로). D12 S5-3. **(2026-11-20 개정, 새 자리)** 키는 정확히 `gamble_since_legendary, forge_fails_in_row`.

| 키 | 형 | 기본값 | 범위 | 뜻 |
|---|---|---|---|---|
| `gamble_since_legendary` | int | 0 | 0~10억 | 마지막으로 전설 이상이 나온 뒤의 도박 횟수(D12 D4.4: 40번 안에 없으면 41번째 보장). W9(도박 상점)가 쓴다 |
| `forge_fails_in_row` | int | 0 | 0~10 | 강화 연속 실패 횟수(D12 D4.4: 3번이면 다음은 성공). 강화는 보류(H-4)라 지금은 0으로만 남는다 |

- 깨졌을 때(키 집합, 형, 범위): 거부 `incompatible`. 플레이어가 쌓은 값이라 버리지 않는다(원칙 7).
- 이 자리를 바꾸는 함수는 S1·S2에 없다. 도박을 고치는 작업(W9 또는 D12의 도박 묶음)이 `chapter_profile.gd`의 도박 저장과 같은 `_persist` 한 번으로 갱신한다.

### 4.2 마녀 항목(키 집합은 정확히 이것) (2026-11-20 개정)

`CHAR_KEYS_V5 = CHAR_KEYS(v4의 10개) + ["quests","records","grace"]`(13개). 지금의 `CHAR_KEYS`는 `CHAR_KEYS_V4`로 남긴다.

**`quests`** — 그 마녀의 퀘스트 상태. 마녀별이다(D11 E4, T6-D1 잠정 채택. 서사 확인은 `narrative-lead`가 W9 전에 한다. 공용으로 바뀌면 S2 전에 스키마 문제를 다시 본다 — 12절 R2). 키는 정확히 아래 여덟.

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
| `wins` | int | 0 | 0~10억, `wins ≤ runs` | 범위가 틀리면 거부, `wins > runs`이면 `wins=runs`로 고치고 `record_fixed`에 센다 |
| `last` | 사전 | `{}` | `{}` 또는 4.3의 꼴 | 꼴이 틀리면 `{}`로 바꾸고 `dropped_record`에 센다(T6-D5, 채택) |
| `best` | 사전 `{깊이 키: {ticks, grade, kills}}` | `{}` | 키는 `DEPTH_KEY_PATTERN`(50행), 16개 이하. 값의 키는 정확히 셋: `ticks` 0~10억(가장 빠른 **승리**, 0이면 아직 없음), `grade` 0~4(가장 높은 보상 단계, 0이면 단계 없음), `kills` 0~10억(가장 많은 처치) | 키가 17개 이상이거나 형이 사전이 아니면 거부. 항목 하나의 꼴이 틀리면 그 항목만 버리고 `dropped_record`에 센다 |

- `best`를 깊이별로 나눈 이유: D11 E2의 "이 던전의 최고 단계"와 F1의 "이 던전의 최고 단계 대비"를 담기 위해서다. 깊이가 늘어도(D6 1.3) 스키마 6이 필요 없다(T6-D7, 채택). `best`는 프로필이 스스로 계산해 쓰는 값이라 열린 자리를 두지 않는다.
- 최상위 `best_ticks`(계정 전체 최단 승리)는 그대로 둔다. 결과 화면이 지금 읽는 값이라 빼면 화면이 바뀐다.

**`grace`** — 그 마녀의 은총 설정. D12 S5-4(B5.3 "영구 금지"). **(2026-11-20 개정, 새 자리)** 키는 정확히 `banned`.

| 키 | 형 | 기본값 | 범위 | 뜻 |
|---|---|---|---|---|
| `banned` | id 배열 | `[]` | **8개 이하**, 각 원소 `ID_PATTERN` | 모든 판의 은총 카드 뽑기에서 뺄 카드 id |

- 마녀별인 이유: 카드 묶음이 마녀(원소)마다 다르다(D12 B0).
- 모르는 카드 id(D12 3판에서 카드 id가 바뀌어 사라진 것 포함)는 **보존**하고 `unknown_ids`에 센다. 뽑기는 모르는 id를 무시한다. 플레이어가 고른 것이라 지우지 않는다(원칙 5). 화면이 "더는 없는 카드"를 보여 주고 빼게 하는 일은 그 기능을 만들 때의 일이다.
- 중복은 `deduped`. 9개 이상, 형이 틀림, 키 집합이 틀림은 거부(`incompatible`).
- 기능(H-8)이 미정이라 이 자리를 쓰는 함수는 S1·S2에 없다. 빈 자리만 연다(T6-D13). H-8이 "하지 않음"으로 정해져도 빈 배열로 남을 뿐 해가 없다.
- 이 목록을 판에 넘기는 일(빌드 입력)은 그 기능의 일이다. 그때 코어 입력이 바뀌지만 골든은 프로필을 읽지 않는다.

### 4.3 `records.last`의 꼴 — 핵심 키는 엄격, 그 밖은 열린 자리 (2026-11-20 개정)

`last`는 지난 판을 다음 판·마을에서 보여 주고 비교하는 데 쓰는 표시용 값이다. 결과 화면은 판이 끝난 직후 메모리의 기록기(W7 `RunRecord`)를 읽으므로 `last`에 F1의 모든 숫자를 담을 필요가 없다. 그래서 **핵심 키**(지난 판 대비, 현상금 대조, 최고 기록 갱신에 쓰는 것)만 엄격히 정하고, 나머지는 꼴만 맞으면 받는 **열린 자리**로 둔다(T6-D14).

**① 핵심 키** — 모두 있어야 하고 형·범위가 맞아야 한다. 하나라도 틀리면 `last` 전체가 꼴이 틀린 것이다.

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
| `items` | 사전 `{출처: int}` | 키 16개 이하, 키는 `ID_PATTERN`, 값 0~10억 | 출처별 장비 수(D11 D5의 `source` 값). 모르는 출처 키도 꼴만 맞으면 받는다 |
| `skills` | 배열 | **16개 이하** | 기술 표. 원소마다 핵심 키 `id`(`ID_PATTERN`), `got_tick`(0~10억), `got_level`(0~99), `rank`(0~99), `evolved`(bool), `damage`(0~10^12, 넘친 피해를 뺀 생명 단위 합, W7의 `dealt_raw`/256), `kills`(0~10억)가 있어야 하고, 원소 안에도 ②의 열린 자리를 둘 수 있다 |

**② 열린 자리** — 핵심 키가 아닌 키(최상위와 `skills` 원소 안)는 아래를 모두 지키면 **그대로 보존**한다. 읽을 때도, 쓸 때도, `record_run`이 받을 때도 같은 규칙이다.
- 키 이름: `^[a-z][a-z0-9_]{0,31}\z`. 핵심 키와 같은 이름은 열린 자리가 아니다.
- 값: int(−10^12~10^12), bool, `ID_PATTERN`에 맞는 문자열, 또는 이 셋으로만 된 배열(32개 이하)·사전(32키 이하, 키는 위 이름 규칙). 배열·사전 안의 배열·사전은 한 겹까지(깊이 2). **실수(float)와 자유 글은 받지 않는다**(비율·초당 피해는 화면이 계산한다, 원칙 3).
- 크기: `last` 전체의 키는 48개 이하, `JSON.stringify(last)`는 16,000자 이하.
- 열린 자리 하나가 규칙을 어기면 **그 키만 버리고** `dropped_record`에 센다(핵심 키가 맞으면 `last`는 남는다). 쓸 때는 거부한다(그래서 `record_run`이 받을 때 걸러야 한다. 7.1).
- JSON에서 읽은 정수는 실수로 들어오므로 정수 꼴(소수부 0)이면 int로 바꾼다(지금 `Catalog.integer` 규칙).

**③ 바꾸는 규칙**
- 핵심 키는 스키마 5 안에서 빼거나 이름·뜻을 바꾸지 않는다. 기록기가 더 이상 세지 않는 값은 0/거짓으로 채운다.
- 새 숫자는 열린 자리로 더한다. 프로필 코드를 고치지 않아도 저장된다. 옛 v5 실행본도 그 키를 보존한다.
- 열린 자리의 키를 화면이 쓰기 시작하면, 그 키는 화면 쪽에서 "없을 수 있는 값"으로 다룬다(옛 판의 `last`에는 없다).
- W7 쪽에 미리 알려 둘 것 [추정: D11 F1 2026-11-19 개정 2]: 죽음 원인(`death_cause`: `swarm`/`single`/`ranged`/`other` 같은 id), 궁극기 횟수, 반응·조합별 피해, 은총 순서는 모두 열린 자리로 담을 수 있다. 은총 순서처럼 길어지는 값은 16,000자 상한 안에서 담는다.

넣지 않는 것: 초당 피해(`damage`와 `ticks - got_tick`으로 계산), 비중(%), 희귀 이상 장비 목록(장비는 `items`에 있다), 기술 이름(id로 짓는다), 최근 60초 초당 피해(T6-D5). 지난 판과 비교할 때는 전체 초당 피해만 쓴다.

**S1과 W7의 관계**: W7(`gameplay-systems`, 구현 중)은 `to_last_record()`가 이 꼴을 내도록 만들고, 핵심 키에 더하거나 뺄 것이 있으면 보고하기로 했다. **디렉터가 W7 보고를 받고 핵심 키 표를 확정한 뒤 S1을 시작한다**(10절). 열린 자리 덕분에 그 뒤에 W7이 숫자를 더하는 것은 S1을 막지 않는다. 핵심 키를 S1 뒤에 바꿔야 하면, 옛 v5 실행본은 그 `last`를 버린다. 파일은 거부되지 않는다(원칙 7).

### 4.4 기본값 (2026-11-20 개정)

```
fresh() 에 더할 것: "schema_version":5,
  "town":{"unlocked":[],"bought":[],"shop":{"seed":0,"refreshed_run":0,"stock":[]},
          "luck":{"gamble_since_legendary":0,"forge_fails_in_row":0}}
default_entry() 에 더할 것:
  "quests":{"active":[],"progress":{},"done":[],"claimed":[],"bounty_offer":[],"bounty_seed":0,"bounty_run":0,"repeat_claims":0},
  "records":{"runs":0,"wins":0,"last":{},"best":{}},
  "grace":{"banned":[]}
장비: forge·rerolls는 키 없음이 기본값(0)이다. 0을 쓰지 않는다.
```

### 4.5 `read_report`의 새 키 (2026-11-20 개정)

`quest_fixed`(겹침·고아 진행값을 고침), `record_fixed`(`wins>runs`), `dropped_record`(`last` 전체, `last`의 열린 자리 한 키, `best` 항목을 버림), `dropped_stock`(진열 장비를 버림). 지금 있는 키(`unknown_ids`, `deduped`, `dropped_flags`, `quarantined_items` 등)는 그대로 쓴다. 장비의 `forge: 0`·`rerolls: 0`을 지운 것은 `veiled`와 같이 `dropped_flags`에 센다. 로그 한 줄 `CHAPTER1_PROFILE_READ_FIXES`(231~235행)도 그대로다.

### 4.6 D11 E4·D12와 달라진 곳 (2026-11-20 개정: 디렉터 확인 끝, D12 줄을 더함)

| 원래 | 이 문서 | 이유 |
|---|---|---|
| D11: `quests.done`, `claimed`의 뜻을 정하지 않음 | `done`은 보상 대기, `claimed`는 받은 한 번짜리. 서로 겹치지 않음 | 두 번 받기를 막는 규칙이 이 뜻 위에 선다 |
| D11: 반복 퀘스트를 어떻게 둘지 정하지 않음 | `claimed`에 넣지 않고 `repeat_claims`로 셈 | 256개 상한, 파일이 계속 커지는 것을 막음 |
| D11: `bounty_seed`만 | `bounty_run`을 더함 | "판마다 다시 뽑는다"를 판정하려면 언제 뽑았는지 알아야 함 |
| D11: `records.best = {ticks, grade, kills}` | 깊이 키로 나눈 사전 | 깊이가 늘어도 스키마가 그대로 |
| D11: `records`에 판 수가 없음 | `runs`, `wins`를 더함 | `bounty_run`, `refreshed_run`의 기준이 됨. 판 수는 다른 값에서 계산할 수 없음(영수증은 64개에서 잘림, 1053행) |
| D11: `town = {unlocked, shop}` | `bought`를 더함 | E2 "회수약 상한 올리기(1회성)"를 담을 자리 |
| D11: `shop.stock: [장비 기록]` | 장비 사전의 배열(`storage_id` 없음, `veiled`·`forge`·`rerolls` 없음). 깨지면 버림 | 아직 가진 물건이 아님. 산 순간에 `items`로 들어가 `storage_id`를 받음 |
| D11: 퀘스트 보상 스킬 포인트(D4)를 어디에 둘지 정하지 않음 | 저장 키 없음. `first_rewards`에 퀘스트 보상 id(예: `quest:q.ch1.end`)를 넣고, `character_progression.json`의 `first_rewards`에 그 id의 포인트를 둠 | 포인트 계산(`points_earned`)과 상한(`points_cap`, `character_progression.gd:148`)이 지금 코드 그대로 맞음. `first_rewards`는 32개 이하(825행) — D12 C1의 예산(첫 처치 3 + 퀘스트 1)에 넉넉함. 데이터 수정은 W9/content-balance(T6-D4) |
| D11 F1: `last`에 F1 숫자 전부 | 핵심 키 14개 + 열린 자리 | W7이 숫자를 더해도 스키마가 그대로(T6-D14) |
| D12 S5-1 `forge` int 1~5 | 그대로. 0은 쓰지 않음. 범위 밖은 장비째 격리 | 4.7 |
| D12 S5-2 `rerolls` int 1~20 | 그대로. 규칙은 `forge`와 같음 | 4.7 |
| D12 S5-3 `town.luck` | 그대로. 깨지면 거부(버리지 않음) | 플레이어가 쌓은 값 |
| D12 S5-4 `grace.banned` 8개 이하 | 그대로. 모르는 id 보존. H-8 전이라 빈 자리만 | T6-D13 |

### 4.7 장비의 선택 키 `forge`·`rerolls` (2026-11-20 개정, 새 절)

D12 S5-1·S5-2. 강화·다시 굴리기는 **보류**(H-4: 계획만 기록, 나중에 검토)지만, 장비 키는 정확히 맞아야 읽히므로(785~788행) 지금 자리를 열지 않으면 그 기능만을 위해 스키마 6이 필요하다. 그래서 선택 키 둘을 연다.

`ITEM_KEYS_V5_OPTIONAL = ITEM_KEYS_V4_OPTIONAL + ["forge","rerolls"]`(`legendary_id, rare_words, legacy_name, veiled, forge, rerolls`). 지금의 상수는 `ITEM_KEYS_V4_OPTIONAL`로 남긴다(v4 옮기기에서 v4 꼴 장비를 검사할 때. v4 파일에 `forge`가 있으면 v4 코드처럼 장비 검사 실패 → 격리).

| 키 | 형 | 범위 | 없음의 뜻 | 읽을 때 | 쓸 때 |
|---|---|---|---|---|---|
| `forge` | int | 1~5 | 강화 안 함(0) | 값 0 → 키를 지우고 `dropped_flags`. 그 밖의 형·범위 오류 → 장비 검사 실패 → 지금 규칙대로 **원본째 `quarantine`**(사유 `"forge"`) | 0이나 범위 밖이면 거부 |
| `rerolls` | int | 1~20 | 다시 굴린 적 없음(0) | `forge`와 같음(사유 `"rerolls"`) | `forge`와 같음 |

- 플레이어가 가진 것이라 값만 버리지 않고 장비째 격리한다(원칙 7). 격리 원본은 지금처럼 데이터가 맞으면 되살아난다.
- `_item_shape`(588~605행)에서 두 값을 int로 바꾼다. `_document`(921~942행)는 장비 사전을 그대로 복사하므로 따로 손보지 않아도 두 키가 파일에 남는다 [확인: 925행 `duplicate(true)` 뒤 `name`·`description`만 지움]. 읽기 → 저장 → 다시 읽기에서 값이 남는지 V5-18이 확인한다.
- `loot.validate`(`loot.gd` 296~346행)는 모르는 키를 보지 않으므로 두 키가 있어도 장비 검사를 통과한다 [확인]. `loot.gd`는 고치지 않는다.
- **강화 기능을 만들 때 지킬 계약(기록, 지금 구현 안 함)**: 강화는 저장된 `stats`·`affixes` 값을 **바꾸지 않는다.** 강화된 값은 착용 합성 때 `forge`와 데이터로 계산한다. 저장된 값을 바꾸면 `loot.validate`의 "기본+접사 = stats" 검사(344행)와 접사 범위 검사(334행)에 걸려 장비가 격리된다. 다시 굴리기는 결과를 `affixes`에 쓰므로(D12 D4.4) 결과가 지금 접사 규칙(범위, 갈래 중복, 종류 상한) 안에 있어야 하고 `stats`도 다시 합성해 써야 한다.
- 상점 진열 장비와 도박으로 막 받은 장비에는 두 키가 없다. 산 뒤에 `items`로 들어간 장비만 가진다.
- 이 키를 쓰는 함수는 S1·S2에 없다. 검사(V5-18)는 손으로 넣은 값으로 한다.

### 4.8 스킬 트리·의상·미감정 — 저장 꼴은 그대로, 규칙만 (2026-11-20 개정, 새 절: D12 C6 Q-T1~Q-T5의 답)

D12 3판이 쓰이는 중이라 트리와 판 안 구성은 더 바뀔 수 있다. 아래 규칙을 지키면 그 변화는 저장 꼴을 바꾸지 않는다.

**판 안 스킬 구성(D12 B0, `run_spells.json`)** — 판은 저장되지 않는다. `record_run`의 `carry`는 장비 묶음이고 기술을 담지 않는다 [확인: 1008~1058행]. 판 안 구성이 저장에 닿는 곳은 `records.last.skills[].id` 하나뿐이고, 이것은 id 문자열이며 모르는 id도 보존된다. 그래서 판 안 구성의 id·칸·축이 어떻게 바뀌어도 저장에는 영향이 없다. 지난 판 기술 표에서 사라진 id는 화면이 이름 없이 건너뛴다(그 화면 작업의 일).

**Q-T1 — 영구 트리의 노드 id가 바뀔 때** [확인: 842~859행, `skill_tree.gd` 453~469행]
- 리비전이 다르면: 읽을 때 `ranks={}`로 **전부** 비운다. 모르는 노드 id(`rime`, `deep_oath`)도 남지 않는다. 알림(`notices`)이 켜지고 `refunded_trees`에 센다. 엄격 쓰기는 리비전 불일치를 거부하므로 메모리 상태는 언제나 새 리비전이다. 포인트는 `xp`와 `first_rewards`로 계산되므로 잃는 것이 없다. 원칙 5(모르는 id 보존)의 의도된 예외다.
- 리비전이 같은데 노드가 사라지면: `legal_ranks`가 `unknown_node`를 내고, 그것도 전액 반환으로 간다(855~858행). 안전망은 있다.
- **데이터 규칙(트리를 고치는 쪽에 넘길 것)**: 노드 id를 바꾸거나 빼거나, 최대 랭크를 낮추거나, 요구 레벨·선행 조건·포인트 비용을 올리거나, 노드의 효과를 바꾸면 그 트리의 `revision`을 올린다. 효과만 바뀌고 투자가 여전히 합법이면 안전망이 잡지 못하므로, 리비전을 올리는 것만이 "바뀐 노드에 묶인 투자"를 풀어 준다. 리비전은 다른 값이면 무엇이든 반환이 일어나므로(850행 `!=`), 내리지 말고 올리기만 한다. 개발 중 초안마다가 아니라 사용자에게 가는 묶음마다 한 번 올린다.
- `respecs`, `tree_reset`(16자 id), `first_rewards`는 트리 개정과 무관하게 그대로다.

**Q-T2 — 화염·번개의 `tree_id`가 `null`에서 값으로 바뀔 때** [확인: 842~855행, 1264~1306행]
- 지금 그 마녀 항목은 `tree_revision` 0, `ranks {}`다(트리 없는 마녀의 투자는 읽을 때 비워진다, 842~845행). 트리가 생기면 0 리비전 + 빈 투자는 위반이 아니므로 그대로 읽히고, 쌓인 포인트는 모두 자유 포인트가 된다. 첫 `commit_tree`가 리비전을 채운다(1287행). 저장 꼴은 그대로다.
- **위험(R11)**: `character_progression.json`에서 마녀의 `tree_id`를 채웠는데 `skill_trees.json`에 그 트리가 없으면, 그 마녀 항목을 가진 **모든 저장이 `incompatible`로 거부된다**(847행 `"tree data"`). 데이터 두 파일은 같은 커밋에서 함께 바뀌어야 하고, `tree` 검사(`test_skill_tree.gd`)나 데이터 검사가 "모든 `tree_id`가 `skill_trees.json`에 있다"를 확인해야 한다. 지금 그런 검사가 있는지는 **[미확인]**. 트리를 넣는 작업의 지시서에 넣는다(디렉터 전달).

**Q-T3 — 키스톤 배타(`exclusive`)를 어긴 `ranks`**
- 권고대로 **전액 반환**이다. 그리고 프로필 코드는 고치지 않아도 된다: `SkillTree.legal_ranks`가 `exclusive` 위반을 오류로 내기만 하면, 읽을 때는 지금 길(855~858행)이 전액 반환 + 알림 + `refunded_trees`로, 엄격 쓰기는 거부로, `commit_tree`는 1285행의 같은 검사로 막는다.
- 그래서 일은 `skill_tree.gd`에 있다: `exclusive` 문법을 넣는 작업이 `legal_ranks`에 "같은 `exclusive` 값을 가진 노드 둘 이상에 랭크가 있으면 오류"를 더하고, `tree` 검사와 프로필 검사 하나(위반 저장 → 반환, `refunded_trees` 1)를 더한다. 그 작업은 데이터에 `exclusive`가 생길 때의 것이라 S1에는 넣지 않는다.

**Q-T4 — 장비 `tree_rank_*`로 오른 랭크** — 저장하지 않는다(원칙 2). 프로필의 `ranks`는 **산 랭크만** 담는다. 판 시작의 트리 합성이 착용 장비를 입력으로 받아 더한다. 지켜야 할 것: 장비로 더한 랭크를 `commit_tree`·`legal_ranks`에 넘기지 않는다(최대 랭크를 넘으면 `rank_range`로 투자 전체가 거부·반환된다). 화면이 "장비로 오른 랭크"를 따로 보여 주는 읽기 함수는 `skill_tree.gd`의 순수 함수(예: `effective_ranks(tree, bought, gear_bonus) -> {node: {bought, bonus, total}}`)로 둔다. 프로필에는 새 함수가 필요 없다(`character_view().ranks`가 산 랭크다).

**Q-T5 — 검사 목록에 더하는 것** — V5-18(장비 `forge`·`rerolls`), V5-19(`town.luck`), V5-20(`grace.banned`), V5-21(`records.last` 열린 자리)을 9.2에 더했다. S2의 검사는 V5-30부터로 번호를 옮겼다.

**의상 해금(D12 A1 "첫 키스톤에 의상 하나")** — 새 키가 필요 없다. `wardrobe.owned`(64개 이하)와 `grant_outfit`(1203행)이 이미 있다. 다만 S0에서 드러났듯 지금 `outfits.json`의 모든 의상이 `default_owned: true`라 "가지지 않은 의상"이 실제 데이터에 없다(S0 보고서 "지시서와 달라진 점" 2). 넘길 규칙 둘:
- 해금할 의상은 **새 의상으로 `default_owned: false`** 를 준다. 이미 있는 의상을 `true` → `false`로 바꾸지 않는다. 바꾸면 그 의상을 입고 있던 저장은 `owned`에 기록이 없으므로(기본 소유일 때 `grant_outfit`은 아무것도 쓰지 않는다, 1206행) 화면에서 말없이 벗겨진다(1190행).
- 키스톤을 처음 확정할 때 의상을 주는 것은 `commit_tree`와 **같은 `_persist` 한 번**에 넣는다(투자는 됐는데 의상은 못 받은 반쪽 저장을 막는다). 초기화로 키스톤을 빼도 의상은 남는다(소유는 사건의 기록이다). 이것은 그 기능 작업의 일이다.

**미감정 장비** — 새 키가 필요 없다. 선택 키 `veiled`(참일 때만, 810~812행), 도박 횟수 `gambles`, 도감 `codex`가 이미 있다. v5에서 바뀌는 것은 진열 장비에 `veiled`를 두지 않는다는 것 하나다(4.1).

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

### 5.2 v4 → v5(한 번, 메모리에서) (2026-11-20 개정: `origin` 규칙을 하나로, `grace` 더함)

새 정적 함수 `upgrade_v4(value, reasons_out=[]) -> Dictionary`:

| 단계 | 내용 |
|---|---|
| 구조 검사 | `value`가 사전이고 `keys_match(value, TOP_KEYS_V4)`이고 `schema_version`이 정확히 4. 아니면 `{}` + 사유(`"schema 4 keys"`, `"schema version"`) |
| 최상위 | 모든 키를 그대로 복사하고 `schema_version=5`, `town`은 4.4의 기본값 |
| 마녀 항목 | `characters`의 각 값이 사전이고 `keys_match(값, CHAR_KEYS_V4)`이면 `quests`·`records`·`grace` 기본값을 더한다. 꼴이 다른 값은 **손대지 않고** 둔다. 그러면 `read_document`가 지금 규칙대로 거부하거나 격리한다 |
| `quarantine`의 마녀 | `kind=="character"`이고 `raw`가 `CHAR_KEYS_V4`에 맞는 사전이면 `raw`에도 세 기본값을 더한다. 되살리기(733행)가 v5 키로만 맞추기 때문이다. 장비 격리 항목은 그대로 둔다 |
| 장비 | 바꾸지 않는다. v4 장비에는 `forge`·`rerolls`가 없다(v4 코드가 그런 장비를 이미 격리했다) |
| `origin` | **언제나 `{"from_schema":0,"from_file":"","from_revision":0,"at_unix":0}`로 둔다.** 출처는 부르는 쪽이 `_origin_hint`에 둔다(5.3). v4의 `origin`(v3에서 왔다는 기록)은 v4 파일에 그대로 남고 v5에는 옮기지 않는다 |
| 그 밖 | 장비·격리·도감·서사는 바꾸지 않는다. 이어서 `read_document(…, false)`(너그러운 읽기)가 장비를 지금 데이터로 다시 검사한다(T5 5.4와 같음) |

- `revision`은 이어진다. 첫 v5 저장은 v4 `revision`+1이다(948행 규칙).
- 옮기기를 두 번 해도 결과가 같아야 한다(V5-1).
- `records.runs`·`wins`는 0에서 시작한다. v4에는 마녀별 판 수가 없다. 최상위 `completed_runs`는 계정 전체 승리 수라 마녀별로 나눌 수 없다. 퀘스트도 비어서 시작한다(소급 완료 없음, T6-D3 채택).

### 5.3 출처 기록(`_origin_hint`)과 v3·v2·v1의 취급 (2026-11-20 개정)

`origin`은 지금처럼 "메모리에는 0, 출처는 `_origin_hint`, 첫 저장 때 `_persist`가 채움"(949~950행)의 한 길로만 정한다. `upgrade_v4`는 `origin`을 0으로 두고, 부르는 쪽이 힌트를 정한다.

| 읽은 원본 | `_origin_hint` |
|---|---|
| v4(본 또는 r-파일) | `{4, v4 파일 이름, v4 revision}` |
| v4 기록본으로 이어 하기(`v4_journal`) | `{4, 기록본 파일 이름, 그 revision}` |
| v3·v2·v1 | 지금 그대로 `{3|2|1, 파일 이름, revision}`(436행). 길은 `upgrade_v3`(v4 문서) → `upgrade_v4`(v5 문서) → `read_document(…,false)` |
| v5 | 그대로 `{0,"",0}`(파일의 `origin`을 그대로 씀) |

v3·v2·v1은 **지금 규칙을 그대로 유지한다.** v5도 v4도 없을 때만 읽고, 읽기만 한다.

### 5.4 되돌릴 수 없게 되는 지점

- **파일 기준으로는 없다.** v4 파일과 기록본은 한 바이트도 바뀌지 않는다. v5 파일·폴더를 치우고 v4 실행본을 쓰면 v4는 옮기기 직전 상태로 읽힌다.
- **진행 기준으로는 첫 v5 저장이다.** 그 뒤의 진행(퀘스트, 상점 구매, 새 장비, 경험치)은 v5에만 있다. v4 실행본으로 돌아가면 그 진행이 보이지 않는다. 그 상태에서 v4로 놀다가 다시 v5 실행본을 쓰면 v4에서 한 진행은 버려진다. v5가 있으면 v4를 보지 않기 때문이다. 이 갈라짐은 T5의 v3/v4 때와 같고, 막는 길도 같다. 옛 실행본은 배포하지 않고, 개발 사본은 `--chapter1-profile-off`로 돈다.
- 새로 생기는 위험: 사용자가 이미 스키마 4 실행본으로 플레이하고 있다. v5 첫 실행에서 옮기기가 장비를 격리하거나 마녀를 격리하면 그 결과가 v5에 굳는다. 원본은 v4에 남아 있고, 격리 원본도 `quarantine`에 남아 되살릴 수 있다. 사용자 저장을 열어 보지 않으므로 실제로 몇 개가 격리될지는 알 수 없다(14절).

---

## 6. 검증 — 거부, 고쳐 읽기, 보존, 그리고 거부 흐름

### 6.1 v5 파일을 읽을 때의 표(새 줄만 적는다. T5 6.1표의 줄은 그대로다) (2026-11-20 개정)

| 경우 | 처리 | 보고 키 |
|---|---|---|
| `schema_version`이 5가 아님(4, 6, 99 포함) | 거부 `incompatible` | — |
| 최상위에 `town`이 없거나 다른 키가 더 있음 | 거부 `incompatible` | — |
| `town`의 키 집합이 다르거나 형이 다름, `unlocked` 17개 이상, `bought` 33개 이상, `stock` 9개 이상, `shop`의 키·정수 범위가 틀림 | 거부 `incompatible` | — |
| `town.luck`의 키 집합·형·범위가 틀림(`forge_fails_in_row` 11 등) | 거부 `incompatible` | — |
| 마녀 항목에 `quests`·`records`·`grace`가 없음(v4 꼴의 항목) | 거부 `incompatible`. v5 파일 안의 v4 꼴 항목은 손으로 고친 것이다 | — |
| `quests`의 키 집합·형·상한·정수 범위가 틀림 | 거부 `incompatible` | — |
| `quests` 안의 겹침, `progress`의 고아 키 | 고쳐 읽기 | `quest_fixed` |
| `grace`의 키 집합이 틀림, `banned`가 배열이 아님, 9개 이상, 원소가 `ID_PATTERN`이 아님 | 거부 `incompatible` | — |
| 모르는 퀘스트·장소·구매·카드 id | 보존 | `unknown_ids` |
| 목록 안의 중복 | 고쳐 읽기 | `deduped` |
| `records`의 키 집합이 틀림, `runs`·`wins`의 범위가 틀림, `best`가 사전이 아니거나 17개 이상 | 거부 `incompatible` | — |
| `wins > runs` | 고쳐 읽기(`wins=runs`) | `record_fixed` |
| `records.last`의 핵심 키가 빠지거나 형·범위가 틀림 | `{}`로 바꿈(T6-D5) | `dropped_record` |
| `records.last`의 열린 자리 한 키가 4.3 ②를 어김 | 그 키만 버림 | `dropped_record` |
| `records.best`의 항목 하나의 꼴이 틀림(키 패턴 포함) | 그 항목만 버림 | `dropped_record` |
| `shop.stock`의 장비 하나가 장비 검사 실패(`_evaluate_record`의 실패와 같음), v1 장비, 또는 `veiled`·`forge`·`rerolls`를 가짐 | 그 장비만 버림(T6-D6) | `dropped_stock` |
| `items`의 장비가 `forge: 0` 또는 `rerolls: 0` | 키를 지움 | `dropped_flags` |
| `items`의 장비가 `forge`·`rerolls`의 형·범위가 틀림 | 장비째 `quarantine`(지금 격리 길) | `quarantined_items` |
| `quarantine`의 마녀 `raw`가 v4 꼴(`CHAR_KEYS_V4`) | 되살리기를 시도할 때 기본값을 더해 맞춘다 | 지금처럼 `restored_characters` |

### 6.2 쓰기 규칙(`_persist`의 엄격 검사)

6.1에서 "거부", "고쳐 읽기", "버림", "지움", "격리"에 해당하는 것은 쓸 때 모두 거부한다. "보존"(모르는 id, `last`의 열린 자리)은 꼴만 맞으면 쓴다. **불변식**: 받아들인 결과를 그대로 엄격 쓰기 검사에 넣으면 통과한다(V5-13).

`_document()`(921~942행)는 `schema_version` 5를 쓰고 `town`을 그대로 복사한다(`stock` 장비는 메모리에서도 글이 없으므로 따로 손보지 않는다).

### 6.3 거부 흐름(D5·T5 6.3을 v5 이름으로 그대로)

`reject_kind`는 지금의 셋을 그대로 쓴다. 안내 화면(안내, 저장 없이 플레이, 새 저장으로 시작, 기록본에서 이어 하기)도 바뀌지 않는다. 바뀌는 것은 이름과 이어 하기 후보뿐이다.

| 거부된 것 | `reject_kind` | 이어 하기 후보(위에서부터, 읽기만) | "새 저장으로 시작"이 만드는 것 |
|---|---|---|---|
| v5 본 파일 또는 r-파일(크기, JSON) | `damaged` | ① 가장 최근의 읽히는 v5 기록본(지금 `latest_readable_revision`) ② 없으면 **v4 원본을 다시 옮긴 것**(새 `_v4_source_resume`, 종류 `"v4_source"`) ③ v4도 없으면 v3 원본을 다시 옮긴 것(지금 `_v3_source_resume`, `"v3_source"`) ④ 빈 저장 | `chapter-one-profile-v5-r<시각>[-n].json` + v5 가리키는 파일 |
| v5 파일의 구조 | `incompatible` | 위와 같음 | 위와 같음 |
| v5가 없고 v4 원본의 구조가 깨짐 | `legacy` | 가장 최근의 읽히는 **v4 기록본**(새 `_v4_journal_resume`, 종류 `"v4_journal"`). v4 기록본은 원본 옆이 아니라 `<원본 폴더>/revisions/<원본 바탕>.revision-*`에 있다. v3 기록본(원본 옆, 283~291행)과 찾는 곳이 다르다. 바탕은 r-파일이면 r-파일 이름이다 | 본 경로에 v5(가리키는 파일 없음). 지금 `legacy` 규칙(335~336행) 그대로 |
| v5·v4가 없고 v3·v2·v1이 깨짐 | `legacy` | 지금 그대로(v3이면 v3 기록본) | 지금 그대로, 이름만 v5 |

- `resume_info().kind`에 `"v4_source"`, `"v4_journal"` 두 값이 더해진다. 화면 문구는 `profile.resume.*` 키로 다는데, 그것은 ui-hud의 일이다. 그 문구가 없는 동안 화면은 지금의 기본 문구를 쓴다. 화면이 모르는 kind를 받으면 어떻게 하는지는 **[미확인]**이다. S1이 `chapter1/view/`와 `chapter1/app/`에서 `resume`의 `kind`를 읽는 곳을 Grep으로 찾아 보고서에 적는다. 고치지는 않는다.
- 이어 하기 후보 ②(T6-D10, 채택): T5-D6과 같은 이유로 넣는다. v4 원본을 다시 옮기는 코드를 한 번 더 부를 뿐이다.
- 64개 상한(`MAX_JOURNAL_SCAN`)과 크기 상한은 그대로 둔다.

### 6.4 미래 스키마

- v5 경로의 파일에 `schema_version` 6 이상이 들어 있으면 `incompatible`로 거부한다(지금 637행 규칙과 같다). 원본은 그대로다.
- 정상이라면 스키마 6은 새 이름(`-v6.json`)을 쓸 것이므로 v5 실행본은 그 파일을 보지 못한다. 그래서 사용자가 v6 실행본에서 v5 실행본으로 돌아가면 **조용히 옛 v5를 읽는다.** 막을 길(T6-D8, **채택**): `configure`가 본 파일 폴더에서 `^chapter-one-profile-v([6-9]|[1-9][0-9])(-r[0-9-]+)?\.json\z`에 맞는 파일을 **읽지 않고 이름만** 찾는다. 있으면 읽기 전용 필드 `newer_save_file`(파일 이름)을 채우고 로그 `CHAPTER1_PROFILE_NEWER_PRESENT {"file":…}` 한 줄을 찍는다. 거부하지 않고 저장도 막지 않는다. 화면 안내는 나중의 일이다.

---

## 7. 프로필 함수(S1과 S2의 계약)

### 7.1 S1 — 읽기와 판 끝 기록 (2026-11-20 개정)

| 함수 | 계약 |
|---|---|
| `quests_view(character_id) -> Dictionary` | 그 마녀의 `quests` 사본. 모르는 마녀나 프로필 미준비면 `{}` |
| `records_view(character_id) -> Dictionary` | 그 마녀의 `records` 사본. 같은 규칙 |
| `grace_view(character_id) -> Dictionary` | 그 마녀의 `grace` 사본. 같은 규칙 |
| `town_view() -> Dictionary` | `town` 사본(`luck` 포함). `stock`은 글 없는 꼴 그대로 |
| `total_runs() -> int` | 알려진 마녀의 `records.runs` 합(계산, 저장하지 않음) |
| `record_run(receipt, inventory, pending, victory, ticks, progress={}, carry={}, outcome={})` | **인수 하나를 뒤에 더한다**(앱 598행은 고치지 않아도 지금처럼 돈다). 규칙은 아래 |

`record_run`의 새 규칙:
1. `progress.character_id`가 있으면(프로필이 있고 판에 마녀가 있음) 그 마녀의 `records.runs`를 1 올리고, `victory`면 `wins`도 1 올린다. `outcome`이 비어 있어도 그렇게 한다. 그래서 앱을 고치기 전에도 판 수가 쌓인다.
2. `outcome.record`가 있으면 4.3의 꼴로 검사한다. 핵심 키가 맞지 않으면 기록을 빼고(아래), 열린 자리 가운데 규칙을 어긴 키는 **떼어 내고** 나머지를 받는다(뗀 키 이름은 로그 `CHAPTER1_PROFILE_RECORD_TRIMMED {"keys":[…]}`에 남긴다. 기록기가 틀린 값을 내고 있다는 신호다). 받으면 `last`를 바꾸고 `best[record.depth]`를 갱신한다. `ticks`는 승리일 때만 더 작은 값으로(0이면 그 값으로), `grade`·`kills`는 더 큰 값으로. 핵심 키가 틀려 받지 못하면 **보상은 저장하고** 기록만 빼며, `carry_note`와 같은 방식의 새 필드 `outcome_note="record_not_saved"`를 남기고 로그 `CHAPTER1_PROFILE_RECORD_DROPPED {"reason":…}`를 찍는다. 지금의 B1 원칙("기록 하나 때문에 보상을 잃지 않는다", 1047~1052행)과 같다.
3. `progress.character_id`가 없는데 `outcome.record`가 있으면 기록을 빼고 `record_not_saved`를 남긴다.
4. 같은 영수증이면 아무것도 하지 않는다(1010행 그대로). 판 수가 두 번 오르지 않는다.
5. `outcome`의 다른 키(예: `quests`)는 S1에서 받지 않는다. 키가 있으면 기록을 뺀 것과 같게 처리하고 `outcome_note="outcome_unknown_key"`를 남긴다. 퀘스트 갱신은 S2가 더한다.
6. `town.luck`, `grace`, 장비의 `forge`·`rerolls`는 `record_run`이 바꾸지 않는다(4.1, 4.2, 4.7).

### 7.2 S2 — 퀘스트와 마을 쓰기(W9 설계와 함께)

S1이 자리를 열고, S2가 쓰는 길을 연다. 데이터(`quests.json`, 마을 장소·구매 목록)가 아직 없으므로, 지금 `use_ids_for_test`(128행)처럼 시험 훅에 `"quests"`, `"places"`, `"purchases"` 목록을 더한다. 데이터 파일이 생기면 훅 대신 그 파일을 읽는다(W9). 모든 함수는 `_persist` 한 번으로 원자적으로 쓰고, 실패하면 아무것도 바꾸지 않는다.

| 함수 | 계약 |
|---|---|
| `accept_quest(character_id, quest_id) -> bool` | 알려진 id여야 하고 `active`·`done`·`claimed`에 없어야 한다. 한 번짜리면 `claimed`에도 없어야 한다. `active` 8개 미만. 현상금이면 `bounty_offer`에서 빼서 `active`로 옮긴다 |
| `record_run(…, outcome={"record":…, "quests":{…}})` | `outcome.quests`는 판이 끝난 뒤 그 마녀의 **다음 `quests` 전체**다(W9의 퀘스트 모듈이 판 요약으로 계산한다). 엄격 검사에 더해 단조성을 본다. 옛 `claimed`는 모두 남아야 하고, `repeat_claims`는 내려가지 않으며, `done`과 `claimed`에 새로 들어가는 id는 옛 `active`에 있던 것이어야 한다. 실패하면 보상은 저장하고 `outcome_note="quests_not_saved"`를 남긴다 |
| `claim_quest(character_id, quest_id, grant) -> bool` | `quest_id`가 `done`에 있을 때만 된다. 한 번짜리는 `done`에서 `claimed`로, 반복은 `done`에서 빼고 `repeat_claims`+1. `grant = {"essence":int≥0, "xp":int≥0, "items":[장비], "first_rewards":[id], "unlock":[장소 id]}`. 재는 10억까지 더하고, 경험치는 `xp_cap`까지 더한다(`run_xp_max`가 아니라 퀘스트 보상 상한으로 검사. 데이터가 생기기 전에는 시험 훅 값). 장비는 `record_run`처럼 `loot.validate`를 통과해야 새 `storage_id`를 받는다. `first_rewards`는 `character_progression.json`에 있는 id만 받는다. `unlock`은 알려진 장소만 받는다. 하나라도 틀리면 전체를 거부한다 |
| `roll_bounties(character_id, seed, offer) -> bool` | `offer`는 알려진 반복 퀘스트 id 3개 이하. `bounty_seed=seed`, `bounty_run=records.runs`. 뽑는 규칙은 W9가 정한다 |
| `restock_shop(seed, stock) -> bool` | `stock`은 8개 이하 장비. 각 장비는 `loot.validate`를 통과하고 글이 없는 꼴이며 `veiled`·`forge`·`rerolls`가 없다(프로필이 `name`·`description`을 떼고 희귀는 `rare_words`로 바꾼다. 지금 `record_run`의 장비 정리 1033~1038행과 같은 규칙). `refreshed_run=total_runs()` |
| `buy_from_shop(index, price) -> bool` | `0 ≤ index < stock.size()`, `essence ≥ price ≥ 0`, 보관함이 `MAX_ITEMS` 미만. 진열에서 빼서 새 `storage_id`로 `items`에 넣고 재를 깎는다. 고유·전설은 도감에 더한다(1039~1040행 규칙) |
| `buy_once(purchase_id, price) -> bool` | 알려진 id, `bought`에 없음, 재가 충분함. `bought`에 더하고 재를 깎는다. 이미 샀으면 아무것도 쓰지 않고 거짓 |
| `unlock_place(place_id) -> bool` | 알려진 id. 이미 열렸으면 아무것도 쓰지 않고 참(기록본이 늘지 않게, `mark_story_seen`과 같은 규칙) |

가격과 아이템 레벨은 W9가 데이터로 계산해 넘긴다. 프로필은 범위와 잔액만 본다. 도박의 `town.luck.gamble_since_legendary` 갱신, 강화·다시 굴리기, 영구 금지 쓰기는 S2에 없다(각 기능 작업이 같은 규칙으로 더한다).

---

## 8. 골든·측정과의 관계 — 영향이 없다는 것을 확인하는 법 (2026-11-20 개정)

| 단계 | 바뀌는 파일 | `golden` | `golden-textless` | `core-text` | `loot-sim` |
|---|---|---|---|---|---|
| T6-S0(끝남) | 검사 파일·고정 묶음 추가뿐 | 돌리지 않음(S0 보고서) | — | — | — |
| T6-S1 | `chapter_profile.gd`, 프로필 검사, `run_all.py` | **불일치 0** | **불일치 0** | 실패 0 | 불일치 0 |
| T6-S2 | `chapter_profile.gd`, `test_profile_v5.gd` | 불일치 0 | 불일치 0 | 실패 0 | — |

확인하는 법(S1·S2 모두):
1. **바뀐 파일 목록**: `git status --short`와 `git diff --stat`에 `chapter1/core/` 아래 `chapter_profile.gd` 밖의 파일, `chapter1/data/` 아래 파일, `chapter1/app/`, `chapter1/view/`, 골든 기준 파일이 **없다**.
2. **정적 검사(V5-16)**: 아래 파일들이 `chapter_profile.gd`를 `preload`/`load`하지 않고 `import_starting_gear`를 부르지 않는다 — `golden_core.gd`, `test_core_text.gd`, `measure_combat.gd`, `measure_rhythm.gd`, `sim_loot.gd`, `sim_builds.gd`, `report_run_loot.gd`, 그리고 `chapter1/core/` 아래 시뮬레이션 파일(`chapter_core.gd`, `combat_core.gd`, `combat_run.gd`, `run_growth*.gd`, `loot.gd`, `chapter_pilot.gd`, `skill_tree.gd`). T5-Q1이 만들기로 했던 검사가 아직 없으므로(1절) 이번에 `test_profile_v5.gd` 안에 넣는다. 파일이 없으면 "없음"을 실패가 아니라 결과 줄에 적는다(도구 이름이 바뀔 수 있다).
3. **실행**: `python tools/dev/run_all.py --jobs 4` 전체에서 `golden`, `golden-textless`, `core-text`, `loot-sim`이 통과한다. 골든 셋은 한 판에 함께 돈다(`golden_core.gd --both --text-check`, `run_all.py` 18~19행). 해시가 하나라도 바뀌면 멈추고 보고한다. **`--update` 금지.**
4. **갈림이 났을 때의 진단(보고용, 고치지 않는다)**: 바뀐 사례 하나를 시작 커밋과 바뀐 트리에서 같은 틱에 떠서 비교한다.
   ```
   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd -- --case=<사례 키> --dump-at=<틱> --dump-out=_local/t6/s1/diff/before.json
   (바뀐 트리에서 --dump-out=_local/t6/s1/diff/after.json)
   python tools/dev/snapshot_diff.py _local/t6/s1/diff/before.json _local/t6/s1/diff/after.json --limit 200
   ```
   사례 키 목록은 `golden_core.gd -- --list-cases`가 낸다. `snapshot_diff.py`는 같으면 0, 다르면 1을 돌려준다. 처음 갈린 필드는 원인이 아니라 갈림이 처음 보인 곳이다(도구 머리 주석). 프로필만 고친 S1에서 갈림이 나면 원인은 프로필 밖(다른 에이전트의 동시 변경 등)일 가능성이 크다.
5. `hud_dump.gd --profile-fixture=rejected`(149~216행)는 경로를 스스로 정하고 v5 코드로 저장을 만든 뒤 깨뜨리므로 고치지 않고 돈다 [추정]. 실행해서 `HUD_DUMP_REJECT` 줄을 확인한다(명령은 10절 T6-S1 통과 기준 (4)). 주의: `--shots`는 `--headless`와 함께 쓰면 인수 오류로 끝나고(137~138행), 같은 `--profile-tag` 폴더의 `revisions/`는 지워지지 않으므로(193행 `_wipe_folder`는 폴더 바로 아래만 지운다) 새 태그를 쓴다.

---

## 9. 검사 목록

모든 검사는 `res://_local/` 아래 격리 경로만 쓰고, 첫 줄에서 `OS.get_user_data_dir()`에 `/_local/appdata/`가 없으면 `quit(1)`한다(지금 `test_profile_v4.gd:79~80`과 같은 줄). Godot는 `python tools/dev/godot.py …` 또는 `run_all.py`로만 띄운다.

### 9.1 v4 고정 묶음(T6-S0) — 끝남 (2026-11-20 개정)

커밋 `2ed41f0`. `chapter1/tests/fixtures/profile_v4/`에 `v4_full.json`, `v4_with_journals/`(본 파일 + `revisions/` 기록본 4개 + 가리키는 파일 + r-파일), `expected_v4.json`, `README.ko.md`. 생성기 `make_profile_v4_fixtures.gd`(두 번째 실행은 거부, 종료 1, `--force` 없음), 장면 정의 `profile_v4_snapshot.gd`, 검사 `test_profile_v4_fixtures.gd`(마커 `CHAPTER1_PROFILE_V4_FIXTURES_RESULT`, 44개), `run_all.py`의 `profile-v4-fixtures`.

S0 보고서에서 S1이 알아야 할 것:

| 장면 | 스키마 4 코드가 읽은 결과(`expected_v4.json`) |
|---|---|
| `v4_full` | 받아들임. 장비 43, 격리 2(장비 하나, 마녀 `chapter1.character.ghost`), `read_report` `{}`. `origin.from_schema` 3(v3_full에서 옮김) |
| `v4_compat` | 받아들임. 장비 38, 격리 0, `read_report` `{}` |
| `v4_journals_main_only` | `incompatible`(사유 `storage id`). 이어 하기 후보 기록본 리비전 4, kind `journal` |
| `v4_journals_with_pointer` | 받아들임. `chapter-one-profile-v4-r20261119-120000.json`(장비 8) |

지시서와 달라진 점(그대로 받아들인다):
- 의상은 `outfits.json`의 모든 의상이 `default_owned: true`라 `grant_outfit`으로 소유를 늘릴 수 없었다. 서리 `swim_1`, 화염 `swim_2`를 `wear_outfit`으로 입혔고, 서리 `wardrobe.owned`의 `swim_2`는 파일 글 편집으로 넣었다.
- 실제 함수로 쓸 수 없는 칸(`locked`, `new`, `depth_cleared`, `tree_reset`, 격리 장비의 `base_id`, 격리 마녀)은 파일 글을 고친 뒤 실제 코드로 읽고 다시 저장했다.
- 검사는 화면 글을 뺀 전체 비교와 화면 이름 표 비교를 따로 한다. 장비 이름 데이터를 바꾸면 후자가 실패한다(옛 묶음 검사와 같은 노출).
- 시험 훅 id(`beat.one`, `beat.two`, `beat.shared`, `item.coin`)는 파일에만 남고 검사는 훅 없이 읽는다. 그래서 v5에서도 이 id들은 `unknown_ids`가 아니라 지금처럼 보존된다 [추정: S0의 `read_report`가 `{}`인 것으로 미루어 봄. S1이 확인].
- **S1에 미치는 것**: `profile_v4_snapshot.gd`의 `run_scenario`는 v4 파일을 **본 경로(`destination`)로** 읽는다(67행). v5 코드에서는 그 파일이 v5로 읽혀 `incompatible`이 된다. 그래서 S1이 이 검사를 "v4 원본으로 넘겨 옮기는" 꼴로 바꾼다(9.3, V5-4).

### 9.2 새 검사 `chapter1/tests/test_profile_v5.gd`(마커 `CHAPTER1_PROFILE_V5_RESULT`) (2026-11-20 개정)

| # | 검사 | 통과 기준 |
|---|---|---|
| V5-1 | v4 → v5 옮기기 | 읽기만으로는 파일이 생기지 않는다. 첫 저장 뒤 v5가 생긴다. v4 폴더의 모든 파일(본, `revisions/`, 가리키는 파일, r-파일)의 sha256이 그대로다. 첫 저장 뒤 `origin={4, v4 파일 이름, v4 revision, >0}`, `revision`은 v4+1. 같은 파일을 두 번 옮기면 메모리 상태가 같다 |
| V5-2 | v5가 생긴 뒤 | v4·v3 파일을 깨뜨려도 v5를 읽는다 |
| V5-3 | 가리키는 파일 | v4 가리키는 파일 → r-파일에서 옮긴다. v4 가리키는 파일의 바이트는 그대로다. v5 가리키는 파일에 v4 이름을 넣으면 무시한다 |
| V5-4 | S0 v4 묶음 대조 | **`test_profile_v4_fixtures.gd`를 고쳐 이 검사를 맡긴다**(9.3). 각 장면을 v4 원본(`legacy_v4`, `legacy_v4_pointer`)으로 넘겨 v5 코드로 읽는다. `v4_full`·`v4_compat`·`v4_journals_with_pointer`: `state`는 `expected_v4`의 `state`와 비교해 `schema_version`(5), `town`(기본값), `origin`(0, 5.2)만 다르다. `characters`는 각 항목에 `quests`·`records`·`grace` 기본값만 더해졌다. 세 마녀의 `starting_kit`·`blocked_gear`·장비 화면 이름이 같다. `quarantine`이 같다(격리 마녀 `raw`에는 기본값이 더해짐). `read_report`는 v4 코드가 낸 값과 같다. `v4_journals_main_only`: V5-6의 기준 |
| V5-5 | v3·v2·v1 | `test_profile_legacy_fixtures.gd`가 v5 기준으로 통과한다(9.3) |
| V5-6 | v4 원본의 구조가 깨짐 | S0 장면 `v4_journals_main_only`를 v4 원본으로 넘김: `reject_kind=="legacy"`, 아무 파일도 생기지 않는다. `resume_info().kind=="v4_journal"`이고 리비전이 4다. `start_fresh_after_reject(true)` 뒤 본 경로에 v5가 생기고 v5 가리키는 파일은 없다. v4 폴더의 sha256이 그대로다. v4 기록본을 모두 깨뜨리면 후보가 비거나, v3 원본이 함께 있으면 무엇이 되는지를 정해 검사한다(T6-D10) |
| V5-7 | v5 거부 | 6.1표의 거부 줄마다 하나씩(`town` 없음, `town` 키 더함, `unlocked` 17개, `stock` 9개, `luck` 키 빠짐, `forge_fails_in_row` 11, `quests` 키 빠짐, `active` 9개, `progress` 값 −1, `grace` 없음, `banned` 9개, `records` 키 빠짐, `runs` 문자열, `best` 17개, 마녀 항목이 v4 꼴, `schema_version` 4·6). 모두 `incompatible`이고 폴더 sha256이 그대로다. 이어 하기 후보는 v5 기록본 → `v4_source` → `v3_source` → 빈 저장 순서(각각 하나씩 만들어 확인). 새 저장은 `-v5-r` 이름과 v5 가리키는 파일 |
| V5-8 | 고쳐 읽기 | 겹침·고아 진행값 → `quest_fixed`, 모르는 퀘스트·장소·구매·카드 id → `unknown_ids`, 저장 한 번을 거쳐도 남음, `wins>runs` → `record_fixed`, 핵심 키가 틀린 `last` → `{}`와 `dropped_record`, `best` 항목 하나 → 그 항목만 빠짐, 진열 장비 하나의 `base_id` 위조 → 그 장비만 빠지고 `dropped_stock`, 진열 장비에 `veiled` → 그 장비만 빠짐. 각 경우 읽기로 파일 바이트는 그대로이고, 결과는 엄격 쓰기를 통과한다 |
| V5-9 | 엄격 쓰기 | V5-8, V5-18~V5-21의 각 고침 전 문서를 `read_document(…, true)`에 넣으면 거부한다 |
| V5-10 | `record_run` 판 끝 기록 | `outcome` 없이도 `runs`/`wins`가 오른다. `outcome.record`가 맞으면 `last`가 그것이고 `best`가 규칙대로 갱신된다(진 판은 `ticks`를 바꾸지 않는다). 핵심 키가 틀린 기록이면 보상·경험치는 저장되고 기록은 그대로이며 `outcome_note=="record_not_saved"`. 열린 자리 하나가 틀린 기록이면 그 키만 빠진 채 저장되고 `CHAPTER1_PROFILE_RECORD_TRIMMED`가 찍힌다. 같은 영수증 두 번이면 `runs`가 한 번만 오른다. `progress`가 비면 어느 마녀의 `records`도 그대로다. 다른 마녀의 `records`도 그대로다. `town.luck`·`grace`·장비 `forge`는 그대로다 |
| V5-11 | 격리된 마녀 되살리기 | v4 꼴 `raw`(`CHAR_KEYS_V4`)를 가진 격리 마녀가, 시험 데이터로 그 id를 알게 하면 기본값이 더해져 되살아난다 |
| V5-12 | 글 없는 파일 | T5 7절의 검사(한글 문자열, `name`·`description`·`title`·`text` 키)를 v5 파일 전체에 적용한다. 예외는 지금처럼 `legacy_name`, v1 장비, `quarantine[].raw`. `town.shop.stock`과 `records.last`(열린 자리 포함)에도 글이 없다 |
| V5-13 | 불변식 | 모든 고정 묶음(v3·v2·v1 7장면, v4 4장면)과 이 검사가 만든 모든 파일에서 "읽은 결과 → 엄격 쓰기 통과" |
| V5-14 | 호환 파일 | ① `profile_v4_compat.json`이 v4 원본으로 옮겨지고 `read_report`가 비어 있다. ② `--write-compat`로 `fixtures/profile_v5_compat.json`을 **한 번** 만든다(`town`(`luck` 포함)·`quests`·`records`(`last`에 열린 자리 키 하나 이상)·`grace`, 장비 하나의 `forge`·`rerolls`가 모두 기본값이 아닌 값. S2 전이면 손으로 채운 문서를 엄격 쓰기로 확인한 뒤 저장). 이후 이 파일을 `read_report` 0으로 읽는다. 파일이 이미 있으면 덮어쓰기를 거부한다 |
| V5-15 | 미래 | v5 경로의 파일에 `schema_version` 6 → `incompatible`. `chapter-one-profile-v6.json`이 옆에 있을 때 `newer_save_file`이 채워지고 `CHAPTER1_PROFILE_NEWER_PRESENT`가 찍히며, 읽기·저장은 지금처럼 되고, 그 파일의 바이트는 그대로다(T6-D8 채택) |
| V5-16 | 골든 조건 정적 검사 | 8절 2의 파일들에 `chapter_profile.gd`·`import_starting_gear` 참조가 0이다 |
| V5-17 | 기록본 | v5 저장의 기록본은 `revisions/chapter-one-profile-v5.revision-*`이다. `journal_files()`는 v4 기록본을 포함하지 않는다 |
| V5-18 | 장비 `forge`·`rerolls`(4.7) | `forge` 3·`rerolls` 7인 장비가 읽기 → 저장 → 다시 읽기에서 값이 그대로이고 int다. `forge` 0 → 키가 지워지고 `dropped_flags`. `forge` 6, −1, `"3"`, 2.5 / `rerolls` 21 → 그 장비만 `quarantine`(사유에 `forge`/`rerolls`), 나머지 장비는 그대로. 격리 원본의 바이트가 `raw`에 남는다. 엄격 쓰기는 0·범위 밖을 거부한다. v4 원본 장비에 `forge`가 있으면 옮길 때 격리된다(v4 코드와 같은 판정). 장비 화면 이름(`loot.dress`)은 두 키가 있어도 같다 |
| V5-19 | `town.luck`(4.1) | 기본값으로 시작한다. `{gamble_since_legendary: 39, forge_fails_in_row: 2}`가 저장 한 번을 거쳐 그대로다. 키 하나 빠짐·더함, 음수, `forge_fails_in_row` 11, 문자열 → `incompatible`(V5-7과 겹쳐도 된다) |
| V5-20 | `grace.banned`(4.2) | 기본값 `[]`. 모르는 카드 id 둘이 저장 한 번을 거쳐 남고 `unknown_ids` 2. 중복 → `deduped`, 엄격 쓰기는 거부. 8개는 받고 9개는 `incompatible` |
| V5-21 | `records.last` 열린 자리(4.3) | 핵심 키 + 열린 자리(`death_cause:"swarm"`, `ultimate_casts:3`, `reactions:{"steam":1200}`, `skills[0].detonations:5`)가 읽기·저장에서 그대로 남는다. 열린 자리의 실수(1.5)·한글 문자열·깊이 3·키 이름 `Bad-Key` → 그 키만 빠지고 `dropped_record`, 핵심 키는 남는다. 키 49개 또는 16,001자 → `last`가 `{}`. 핵심 키 하나 빠짐 → `last`가 `{}` |
| (S2) V5-30~ | 퀘스트·마을 쓰기 | 7.2의 함수마다 성공 1, 거부 각 조건 1. 거부 때 파일 바이트는 그대로다. `claim_quest` 두 번 → 두 번째는 거짓이고 재·경험치가 두 번 오르지 않는다. 반복 퀘스트 `repeat_claims`, `claimed` 단조성, `outcome.quests` 단조성 위반은 보상이 저장되고 `quests_not_saved`. `buy_from_shop` 재 부족·보관함 가득 참. `restock_shop`에 `veiled` 장비 → 거부. `buy_once` 두 번. `unlock_place` 두 번째에 기록본 수가 그대로다 |

### 9.3 고칠 검사(말없이 빠지는 검사가 없어야 한다. 보고서에 "그대로 / v5로 옮김 / 바뀐 규칙으로 대체(이유)" 표를 붙인다) (2026-11-20 개정)

| 파일 | 고칠 곳 [확인: 행 번호] | 방법 |
|---|---|---|
| `test_chapter_profile.gd` | 53행(`schema_version==4`), 251행(`-v4-r` 이름), 265·273·296행(가리키는 파일 이름 규칙: v5 이름은 받고 v4·v3 이름은 거부), 405행(`schema_version==4`), 그 밖에 `profile-v4.json` 같은 경로 이름 | 뜻은 그대로 두고 스키마 번호와 이름만 v5로 바꾼다. 경로 이름(`profile-v4.json`)은 QA 경로라 아무 이름이나 되지만, 읽는 사람이 헷갈리지 않게 v5로 바꾼다 |
| `test_profile_v4.gd` | 119행(`schema_version==4`) → 5. 491행은 **호환 파일 자체**의 번호라 4 그대로. 475~491행(V-17)은 `profile_v4_compat.json`을 본 경로로 읽는다. 이제 v4 원본(`legacy_v4`)으로 넘겨 옮겨야 한다. 468~472행(V-15 호환)도 같다. V-9의 경우 목록에 `town` 빠짐을 하나 더한다. 손으로 만드는 문서는 모두 지금 코드가 저장한 파일에서 출발하므로 자동으로 v5가 된다 [추정: 223, 258, 268, 297, 419, 440행이 모두 `profile.path`나 `paths.v4`에서 읽음]. `stage_v3`의 `"v4"` 경로 이름(59행)은 v5로 바꾼다 | 마커·`run_all.py` 줄 이름(`profile-v4`)은 그대로 둔다. 이 파일은 "v3 → 현재 스키마" 검사로 남는다 |
| `test_profile_legacy_fixtures.gd` | 88행(`schema_version==4`) → 5, 145~147행의 `chapter-one-profile-v4.json` 경로 → v5 이름, 3절 비교에 "`town`·`quests`·`records`·`grace`는 기본값" 확인을 더한다 | 기대 파일(`expected_v3.json`)은 **고치지 않는다** |
| `profile_legacy_snapshot.gd` | 72행 본 경로 이름 → `chapter-one-profile-v5.json` | |
| `profile_v4_snapshot.gd` **(새 줄)** | `run_scenario`(52~77행)에 v5 읽기 방식을 더한다: 장면 파일을 지금처럼 `work`에 늘어놓고, `configure(work+"/chapter-one-profile-v5.json", true, "", "", work+"/chapter-one-profile-v5-active.json", "", "", work+"/"+MAIN, work+"/"+POINTER(가리키는 장면만))`로 읽는다. 지금 방식(v4를 본 경로로)은 생성기가 쓰므로 함수 이름을 나눠 남긴다(예: `run_scenario`는 그대로, 새 `run_scenario_as_source`). `describe()`는 고치지 않는다 | 생성기(`make_profile_v4_fixtures.gd`)는 고치지도 돌리지도 않는다(묶음이 있으면 스스로 거부한다) |
| `test_profile_v4_fixtures.gd` **(새 줄)** | 1부(묶음 sha256, 파일 8개)는 **그대로**. 2부(50~57행)와 3부(59~90행)를 `run_scenario_as_source`로 바꾸고, 비교를 V5-4의 규칙(허용 차이: `schema_version`, `town`, `origin`, 마녀 항목의 `quests`·`records`·`grace`, 격리 마녀 `raw`의 같은 세 키)으로 바꾼다. 70행(`schema 4`)은 "메모리 상태가 스키마 5"로, 67~68행은 `legacy`·`v4_journal`·리비전 4로(V5-6). 90행(`from_schema==3`)은 "`expected_v4`에 3이 기록되어 있다"로 남기고, 지금 읽은 값은 `origin` 0 + `_origin_hint` 4를 확인한다(5.3) | 마커와 `run_all.py` 줄 이름(`profile-v4-fixtures`)은 그대로. **검사 개수가 44보다 줄면 안 된다.** `expected_v4.json`·묶음 파일은 **고치지 않는다** |
| `make_profile_legacy_fixtures.gd`, `make_profile_v4_fixtures.gd` | 고치지 않는다(이미 거부 장치가 있다) | |
| `hud_dump.gd` | 고치지 않는다. 실행 결과만 확인한다(8절 5) | |
| `test_profile_app_guard.gd`, `test_profile_app_loadout.gd` | 고치지 않는다(파일 이름·스키마 번호 참조 없음 [확인: Grep, 2026-11-19]). 통과만 확인한다 | |
| `tools/dev/run_all.py` | ① `checks()`(98~125행)의 `profile-v4-fixtures` 줄 다음에 `godot_check('profile-v5', 'res://chapter1/tests/test_profile_v5.gd', 'CHAPTER1_PROFILE_V5_RESULT', ['--work-dir=' + FIXTURES + 'v5-' + stamp])` 한 줄. ② `ALIASES['profile-all']`(42행)에 `'profile-v5'`. ③ `SELECTIONS['app']`(84행)에 `'profile-v5'`(빠지면 앱만 고친 `--changed` 실행에서 v5 검사가 말없이 빠진다) | 줄 더하기만. 다른 줄은 고치지 않는다 |

---

## 10. 지시서 (2026-11-20 개정)

공통 규칙(모든 지시서)
- 코드를 고치는 에이전트는 별도 작업 폴더에서 일한다. 커밋하지 않는다. 결과는 패치(`git diff --binary`, 새 파일은 `git add -N` 뒤)와 보고서로 낸다(점검 절차의 문 ③).
- `.gitattributes`가 `* -text`다. 줄바꿈을 바꾸는 도구로 기존 파일을 고치지 않는다. 새 파일은 UTF-8, LF, BOM 없음. 새 `.gd` 파일의 `.uid`도 함께 둔다(Godot가 임포트 때 만든다. 임포트는 `python tools/dev/run_dev.py --import-only`. 이때 생기는 남의 `.uid`(예: `chapter1/view/hero_light.gdshaderinc.uid`)는 패치에 넣지 않는다).
- 검사는 `_local/` 아래 격리 경로만 쓴다. Godot는 `python tools/dev/godot.py …` 또는 `python tools/dev/run_all.py`로만 띄운다. 둘 다 `APPDATA`를 `_local/appdata/`로 돌린다. **사용자 폴더(`%APPDATA%\WitchMoira`)를 읽거나 쓰지 않는다. 열어 보지도 않는다.**
- `assert()` 안에 부작용을 넣지 않는다.
- 표현(view)과 시뮬레이션 코어를 고치지 않는다.
- 디렉터가 성능 측정 창(T2 계열)을 열어 둔 동안에는 같은 컴퓨터에서 Godot 검사를 돌리지 않는다. 시작 전에 디렉터에게 확인한다.
- **말의 규칙**(`CLAUDE.md` "점검 절차"): "통과"는 실제로 돌린 것에만 쓴다. 회귀를 일부만 돌렸으면 무엇을 돌렸는지 쓴다(`--quick`, `--only …`, `--changed`). `--changed`의 결과(`"selected": true`)는 통과 판정에 쓰지 않는다. 보고서에 실제 명령과 출력의 결과 줄(마커 줄, `RUN_ALL` 줄)을 붙인다.
- 새 일회용 스크립트를 `_local/`에 쓰기 전에 `docs/TOOLS-INDEX.ko.md`를 본다. 같은 일을 두 번 하게 되면 `chapter1/tests/`의 검사로 올린다.

### T6-S0 — v4 고정 묶음(qa-perf) — **끝남**

커밋 `2ed41f0`. 결과와 달라진 점은 9.1절. 검수 기록: S0 보고서 `_local/t6/S0-REPORT.ko.md`(그 보고서 기준 통과 기준 (1)~(4) 실행, `run_all.py`는 `--quick`만).

### T6-S1 — 프로필 스키마 5와 판 끝 기록(gameplay-systems)

| 항목 | 내용 |
|---|---|
| 목적 | 이 문서 2~6절과 7.1절. 새 파일 이름, `town`(`luck` 포함)·`quests`·`records`·`grace` 자리, 장비의 `forge`·`rerolls` 선택 키, v4→v5 옮기기, v3·v2·v1을 v5로 잇기, 너그러운 읽기·엄격 쓰기, `records.last`의 핵심 키·열린 자리, 거부 흐름, 더 새 저장 알림(6.4), `record_run`의 판 수·기록 |
| 받는 쪽이 읽을 절 | 이 문서 1~9절 전부(특히 2, 4, 5, 6, 7.1, 8, 9.2, 9.3)와 이 표. 12절 R1·R11은 배경으로 읽되 S1에서 고치지 않는다 |
| 시작 조건 | (1) T6-S0 끝남 — **충족**(커밋 `2ed41f0`). (2) 디렉터 결정 T6-D1·D2·D5·D6·D7·D8·D10 — **충족**(13절). T6-D13·D14 — 이 개정의 결정, 디렉터가 반대하지 않으면 충족. (3) **W7 보고가 온 뒤 디렉터가 4.3절 ① 핵심 키 표를 확정**(바뀌면 디렉터가 이 문서 4.3을 고치거나 지시서와 함께 차이를 넘긴다). (4) `chapter_profile.gd`와 `run_all.py`를 고치는 다른 작업이 없을 때. (5) 시작 커밋에서 `git diff --stat 7de9f92 HEAD -- chapter1/core/chapter_profile.gd`가 비어 있음을 보고서에 적는다(비어 있지 않으면 행 번호가 어긋났으니 멈추고 보고) |
| 고칠 파일 | `chapter1/core/chapter_profile.gd`(상수 19~28·34·37·44행, `fresh` 149~152, `default_entry` 155~160, `configure` 167~200, 새 `_v4_source`·`_v4_source_resume`·`_v4_journal_resume`·`upgrade_v4`·`import_v4_text`, `_reject` 375~384, `_item_shape` 588~605(`forge`·`rerolls`), `_read_body` 635~758(637행 번호, 753행 `from_schema` 0~5, `town` 검사, 733행 v4 꼴 되살리기), `_evaluate_record` 762~818(선택 키, 진열 장비 규칙), `_read_character` 821~918(`quests`·`records`·`grace`), `_document` 921~942, `_persist` 977행(`imported_from_v4`), `record_run` 1008~1058(`outcome`, `runs`/`wins`/`last`/`best`), 새 읽기 함수 7.1절, 6.4의 `newer_save_file`. 2~12행의 머리 주석도 스키마 5로), 9.3절 표의 검사 파일(`test_chapter_profile.gd`, `test_profile_v4.gd`, `test_profile_legacy_fixtures.gd`, `profile_legacy_snapshot.gd`, `profile_v4_snapshot.gd`, `test_profile_v4_fixtures.gd`), 새 `chapter1/tests/test_profile_v5.gd`(9.2절 V5-1~V5-21), `tools/dev/run_all.py`(9.3절의 세 곳) |
| 남길 것 | `upgrade_v3`, `normalize`, `upgrade_v1`, `migrated_characters`, `import_v3_text`, `import_v2_text`, `import_v1_text`, `TOP_KEYS_V3/V2`, `CHAR_KEYS_V3`, v3 가리키는 파일 길, 그리고 새로 이름 붙는 `TOP_KEYS_V4`·`CHAR_KEYS_V4`·`ITEM_KEYS_V4_OPTIONAL`. 모두 옮기기용이다 |
| 건드리지 않을 파일 | `chapter1/app/chapter_one.gd`(S1은 앱을 고치지 않는다. 기본 인수만으로 v5가 열린다), `chapter1/view/` 전부, `chapter1/core/`의 `chapter_profile.gd` 밖 전부(`loot.gd`, `chapter_core.gd`, `character_progression.gd`, `skill_tree.gd` 포함), `chapter1/data/` 전부, `golden_core.gd`와 골든 기준 파일, `fixtures/profile_legacy/`, `fixtures/profile_v4/`(묶음과 `expected_v4.json`), `fixtures/profile_v4_compat.json`, `fixtures/loot_compat_items.json`, `make_profile_legacy_fixtures.gd`, `make_profile_v4_fixtures.gd`, `hud_dump.gd`, `CLAUDE.md`, `docs/` |
| 지킬 계약 | (1) 지금의 공개 함수 시그니처는 뒤에 인수를 더하는 것 말고는 바꾸지 않는다(`configure`, `record_run`). (2) `state`의 키 이름과 뜻은 그대로이고 `town`만 더한다. 화면이 읽는 `hud.profile_state`(앱 540~542행)가 깨지지 않는다. (3) 저장 한 번 = `_persist` 한 번. 판 끝 저장의 원자성(1003~1007행 주석)을 지킨다. (4) 읽기는 아무 파일도 쓰지 않는다. (5) 4.3 ①의 핵심 키 표는 디렉터가 확정한 그대로 쓴다. 바꿔야 할 것 같으면 멈추고 보고한다 |
| 시작할 때 | 고치기 전에 시작 커밋에서 `python tools/dev/run_all.py --jobs 4 --json _local/t6/s1/before.json`을 한 번 돌려 검사별 개수를 남긴다(돌릴 수 없으면 그 사유와 함께 1절의 S0 숫자를 기준으로 쓴다). 개발 중에는 `python tools/dev/run_all.py --only profile-all,profile-v5 --jobs 4`(②를 더한 뒤에는 `--only profile-all`)로 빠르게 돈다 |
| 통과 기준 | (1) `python tools/dev/run_all.py --jobs 4 --json _local/t6/s1/after.json` **전체**의 `RUN_ALL` 줄이 `"failed": []`, `"skipped": []`. 그 안에서 `golden`·`golden-textless` 불일치 0, `core-text` 실패 0, `loot-sim` 불일치 0, 그리고 `profile`, `profile-legacy`, `profile-v4`, `profile-v4-fixtures`, `profile-v5`, `app-guard`, `app-loadout` 통과. (2) `before.json`과 `after.json`의 검사별 개수 표. 프로필 쪽 검사 개수가 줄었으면 줄마다 이유(9.3 대응표). 프로필 밖 검사의 개수는 같아야 한다. (3) V5-1~V5-21의 결과가 담긴 `CHAPTER1_PROFILE_V5_RESULT` 줄 전문과, 번호별로 그 번호를 확인한 검사 이름 목록. (4) `python tools/dev/godot.py --headless --fixed-fps 60 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --profile-fixture=rejected --profile-tag=t6-s1 --result-mock --dump=_local/t6/s1/rejected.json`와 같은 명령에 `--reject-choice=fresh --profile-tag=t6-s1-fresh --dump=_local/t6/s1/rejected-fresh.json`을 바꿔 넣은 것: 각각의 `HUD_DUMP_REJECT` 줄 전문(첫 줄의 `kind`가 `incompatible`, `resume.kind`가 `journal`), 종료 코드, 덤프의 시점 이름 목록. (5) `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_progression.gd -- --runs=1`이 오류 없이 끝난다(인수가 맞지 않으면 파일 머리 주석의 예시 명령으로 바꾸고 그 사실을 적는다). (6) 8절 1의 `git status --short`·`git diff --stat` 출력. (7) 소스 검사 결과: `chapter1/` 아래 `user://`가 나오는 곳 목록과 각 이유, `remove_absolute` 0건(테스트 밖). (8) 6.3절에서 화면·앱이 `resume`의 `kind`를 읽는 곳(Grep 결과, 고치지 않음). (9) 9.1의 시험 훅 id가 v5에서 어떻게 보고되는지(`read_report`) |
| 멈추고 보고할 때 | 골든·글 없는 골든·글 검사·드랍 시뮬레이션이 하나라도 바뀜(8절 4의 진단 결과를 붙인다. `--update` 금지). 고정 묶음이 기대와 다르게 읽힘(묶음이나 기대 파일을 고쳐서 통과시키지 않는다). `chapter_profile.gd`와 9.3절 표 밖을 고쳐야 할 것 같음. 4.3의 핵심 키를 바꿔야 할 것 같음. 시작 조건 (5)가 어긋남 |

### T6-S2 — 퀘스트·마을 쓰기 함수(gameplay-systems, W9 직전)

| 항목 | 내용 |
|---|---|
| 목적 | 7.2절의 함수와 `record_run`의 `outcome.quests` |
| 시작 조건 | T6-S1 검수 통과. W9의 퀘스트 데이터 꼴(`quests.json`, D11 E3)과 마을 장소·구매 id 목록이 정해짐(파일은 아직 없어도 된다. 시험 훅으로 검사). T6-D1의 서사 확인(`narrative-lead`)이 "마녀별"로 끝남. 디렉터 결정 T6-D3·D4·D9 — 충족 |
| 고칠 파일 | `chapter1/core/chapter_profile.gd`(7.2절 함수, `use_ids_for_test`의 키 셋 추가, `record_run`의 `outcome.quests`), `chapter1/tests/test_profile_v5.gd`(V5-30~) |
| 건드리지 않을 파일 | S1과 같음. 데이터 파일(`quests.json`, `character_progression.json`)은 W9·content-balance가 만든다 |
| 통과 기준 | `python tools/dev/run_all.py --jobs 4` 전체 통과(`RUN_ALL` 줄, 골든 셋 불일치 0), V5-30~의 결과 줄, 함수마다 성공·거부 표. 거부 때 파일 바이트가 그대로라는 확인 |

S2를 W9 지시서에 합치지 않는다(T6-D9 채택: 따로, W9 직전).

---

## 11. 순서·의존·파일 겹침 (2026-11-20 개정)

```
끝남:                 T6-S0 (qa-perf, 커밋 2ed41f0)
진행 중:              W7 (gameplay-systems, to_last_record) ──▶ W7 보고 ──▶ 디렉터가 4.3 ① 확정
                                                                              ↓
배정 가능(조건 충족 시): T6-S1 (gameplay-systems) ─▶ [검수: tech-lead] ─┬─▶ W7 앱 연결(record_run에 outcome.record를 넘김)
                                                                        ├─▶ 디렉터가 CLAUDE.md "저장" 절을 v5로
                                                                        └─▶ T6-S2 (W9 직전) ─▶ W9 마을 허브
```

- T6-S1과 W7은 **같은 담당(`gameplay-systems`)** 이다. 파일은 겹치지 않는다(W7은 `chapter1/app/` 또는 `view/hud/`, S1은 `chapter_profile.gd`와 프로필 검사). 같은 에이전트가 W7을 마친 뒤 S1을 잇는 것이 자연스럽다. 두 작업을 다른 작업 폴더에서 나란히 돌려도 되지만, `run_all.py`는 한 쪽만 고친다(W7이 `run_all.py`를 고치면 S1은 그 뒤에 줄을 더한다).
- W7 앱 연결(앱이 `record_run`에 `outcome`을 넘김)은 S1 검수 뒤다. 그 전에는 S1의 `record_run`이 `outcome` 없이 판 수만 센다(7.1 규칙 1).
- T6-S1은 W1~W5, J1·J2, KS·K2 등 코어·데이터 작업과 파일이 겹치지 않는다. 다만 그 작업들이 골든을 갱신하는 동안 S1의 통과 기준 (1)이 흔들린다. 디렉터가 골든 갱신 차례(D12 G2) 사이에 S1의 최종 회귀를 둔다.

| 파일 | 이 문서의 단계 | 겹치는 다른 작업 | 규칙 |
|---|---|---|---|
| `core/chapter_profile.gd` | S1, S2 | T5-S3(기록본 보존, 미착수), W9, 도박 저장(`town.luck`), 강화·금지(보류) | S1 → S2 → (T5-S3) 차례로. 동시 금지 |
| `core/skill_tree.gd` | 없음 | D12 트리 재설계(`exclusive`, Q-T3·Q-T4) | T6은 고치지 않는다 |
| `app/chapter_one.gd` | 없음 | W7, W9, W1 | T6은 고치지 않는다 |
| `tests/test_chapter_profile.gd`, `test_profile_v4.gd`, `test_profile_legacy_fixtures.gd`, `profile_legacy_snapshot.gd`, `profile_v4_snapshot.gd`, `test_profile_v4_fixtures.gd` | S1 | 없음 | — |
| `tools/dev/run_all.py` | S1(세 곳, 줄 더하기) | 회귀 도구 작업, 다른 검사 추가 | 차례로, 줄 더하기만 |
| `data/character_progression.json`, `data/skill_trees.json` | 없음(T6-D4는 W9·content-balance) | W5(`grade_bonus_bps`), D12 트리 재설계 | T6은 고치지 않는다. 두 파일은 같은 커밋에서 함께(R11) |
| `data/outfits.json` | 없음 | 의상 해금(D12 A1) | 기본 소유를 거두지 않는다(4.8) |

---

## 12. 위험과 되돌리는 길 (2026-11-20 개정)

| # | 위험 | 막는 것 | 되돌리는 길 |
|---|---|---|---|
| R1 | **보상 단계 경험치 보너스(W5, D11 D3 +10~30%)로 한 판 `xp_gained`가 `run_xp_max`를 넘으면 `apply_progress`가 거부하고(991행), `record_run`이 저장 전체를 거부한다(1016행).** 장비·재·경험치를 모두 잃고 결과 화면에 "저장 실패"가 뜬다. 퀘스트 경험치를 판 경험치에 섞어도 같은 일이 생긴다 | W5 지시서에 "`character_progression.gd` `xp_bounds`의 `run_xp_max`에 최대 단계 보너스를 반영"을 넣는다(디렉터가 W5에 전달). 퀘스트 경험치는 `claim_quest`의 별도 상한으로 준다(7.2) | W5 검수에서 단계 Ⅳ 판의 `record_run` 성공을 확인 |
| R2 | S1 뒤에 W7·W9가 `last`나 `quests`의 꼴을 바꾸고 싶어 함 → 스키마 6 | `last`: 열린 자리로 숫자를 더할 수 있다(4.3, T6-D14). 핵심 키만 S1 전에 확정한다. `quests`: T6-D1 서사 확인과 W9 데이터 꼴을 S2 전에 맞춘다. `quests`의 꼴(4.2)이 바뀌어야 하면 S2 전에 알린다 | 핵심 키가 바뀌면 옛 v5 실행본은 `last`를 버릴 뿐이다. `quests`가 바뀌면 스키마 6. 같은 방식으로 한 번 더 옮긴다 |
| R3 | 옮기기가 v4 원본을 바꿈 | v5 실행본은 v4 시대 파일을 쓰지 않는다. V5-1·V5-6이 폴더 sha256으로 확인 | v5 파일을 치우면 v4가 그대로 읽힌다(그 뒤의 진행은 잃는다, 5.4) |
| R4 | 사용자의 v4에 격리될 장비·마녀가 있음 | 옮기기는 지금 v4 읽기 규칙과 같다(이미 v4 실행본이 같은 판정을 하고 있다) | 격리 원본은 `quarantine`에 남아 데이터가 맞으면 되살아난다 |
| R5 | 화면이 모르는 `resume.kind`(`v4_source`, `v4_journal`)를 받음 | S1이 화면이 읽는 곳을 찾아 보고(통과 기준 8). 문구는 ui-hud의 다음 작업 | 화면이 kind를 몰라도 파일 이름·리비전은 보인다 [추정] |
| R6 | 판 수가 S1 전의 판을 세지 못함(`runs`가 0에서 시작) | 받아들인다. 현상금 판정과 진열 새로고침은 상대 비교라 영향이 없다 | — |
| R7 | 기록본이 계속 쌓임(T5-S3 미착수) | v5도 판당 저장 횟수는 그대로다(`record_run` 한 번). S2의 마을 행동(받기, 사기)이 저장을 늘린다 | T5-S3을 S2 뒤에 배정하기를 권한다(디렉터) |
| R8 | 옛 v4 실행본으로 돌아가 놀면 진행이 갈라짐 | 옛 실행본을 배포하지 않음. T6-D8(더 새 파일 표시, 채택) | 안내 문서 |
| R9 | 검사 대량 수정 중에 검사가 말없이 빠짐 | 9.3절의 대응표와 `before.json`/`after.json` 개수 대조를 통과 기준으로 둔다. `run_all.py`의 `profile-all` 별칭과 `app` 선택에 `profile-v5`를 넣는다 | 검수에서 개수를 대조 |
| R10 | `CLAUDE.md` "저장" 절이 스키마 3으로 적혀 있어 다른 에이전트가 틀린 파일 이름을 씀 | 디렉터가 S1 뒤에 v5로 고친다 | — |
| R11 **(새)** | 트리 데이터를 고치다 `character_progression.json`의 `tree_id`가 `skill_trees.json`에 없는 트리를 가리키면 그 마녀를 가진 모든 저장이 거부된다(847행) | 두 데이터 파일을 같은 커밋에서 함께 바꾼다. 데이터 검사에 "모든 `tree_id`가 트리 파일에 있다"를 넣는다(트리 재설계 지시서, 디렉터 전달) | 데이터를 되돌리면 원본 파일은 그대로라 다시 읽힌다(거부는 파일을 쓰지 않는다) |
| R12 **(새)** | 트리 노드를 바꾸고 `revision`을 올리지 않음 → 효과가 바뀐 노드에 옛 투자가 그대로 묶임 | 4.8 Q-T1의 데이터 규칙을 트리 재설계 지시서에 넣는다 | 다음 개정에서 리비전을 올리면 전액 반환된다 |
| R13 **(새)** | 의상 데이터에서 기본 소유를 거두면 입고 있던 저장이 말없이 벗겨진다 | 4.8 의상 규칙(새 의상만 잠금) | 데이터를 되돌리면 다시 보인다(저장은 바뀌지 않았다) |
| R14 **(새)** | 강화 기능을 만들 때 저장된 `stats`를 바꿔 장비가 격리됨 | 4.7의 계약(강화 값은 계산)을 강화 지시서에 넣는다 | 격리 원본이 남는다 |

---

## 13. 디렉터 결정 (2026-11-20 개정: 결과를 적음)

| # | 결정 | 결과 | 비고 |
|---|---|---|---|
| T6-D1 | 퀘스트는 마녀별인가 계정 공용인가 | **마녀별, 잠정 채택** | 서사 확인(`narrative-lead`)은 W9 전에. 공용으로 바뀌면 `quests`를 최상위로 옮겨야 하므로 S2 시작 조건에 넣었다. S1에서는 자리만 열리고 쓰는 함수가 없으므로, S1 뒤에 공용으로 바뀌면 스키마 6이 필요하다(R2). 그 위험을 알고 S1을 먼저 하는 것이 디렉터의 결정이다 |
| T6-D2 | 마을(열린 장소, 상점 진열, 한 번만 산 물건)은 공용인가 | **공용, 채택** | `town.luck`도 같은 이유로 공용 |
| T6-D3 | 옮길 때 퀘스트를 소급 완료할 것인가 | **하지 않음, 채택** | |
| T6-D4 | 퀘스트 스킬 포인트를 어디에 두나 | **`first_rewards`, 채택** | |
| T6-D5 | `records.last`가 깨졌을 때 | **버림, 채택** | T6-D14로 "열린 자리 한 키만 버림"이 더해졌다 |
| T6-D6 | 상점 진열 장비가 데이터와 안 맞을 때 | **버림, 채택** | |
| T6-D7 | 최고 기록을 깊이별로 | **깊이 사전, 채택** | |
| T6-D8 | 더 새 저장 파일(`-v6` 이후)이 옆에 있으면 알릴 것인가 | **알림, 채택** | S1에 넣는다(6.4, V5-15) |
| T6-D9 | S2를 따로 둘지 W9에 합칠지 | **따로, W9 직전, 채택** | |
| T6-D10 | v5가 거부되고 v5 기록본도 없을 때 v4 원본에서 다시 옮겨 오기를 이어 하기 후보로 | **넣음, 채택** | |
| T6-D11 | S1 시작 조건으로 W7·W9 담당이 4.2~4.3절의 꼴을 받아들이게 할 것인가 | **갈음됨** | "W7 보고 뒤 디렉터가 4.3 ① 핵심 키를 확정"(10절 T6-S1 시작 조건 (3))과 열린 자리(T6-D14)로 바뀌었다. W9 쪽(`quests`)은 S2 시작 조건으로 옮겼다 |
| T6-D12 **(새)** | D12 S5-1~S5-3(`forge`, `rerolls`, `town.luck`)을 스키마 5에 둘 것인가 | **둔다(기술 책임자 판단, 디렉터 위임)** | 기능은 보류(H-4)지만 빈 자리 비용이 작고, 열지 않으면 그 기능만을 위해 스키마 6이 필요하다. 꼴은 4.1·4.7 |
| T6-D13 **(새)** | D12 S5-4(`grace.banned`)를 H-8 결정 전에 열 것인가 | **빈 자리로 연다(기술 책임자 판단)** | H-8이 "하지 않음"이면 빈 배열로 남을 뿐이다. 늦게 "함"으로 정해지면 스키마 6이 필요해진다 |
| T6-D14 **(새)** | `records.last`를 핵심 키 + 열린 자리로 둘 것인가 | **권고: 연다.** 디렉터가 반대하지 않으면 S1에 넣는다 | 원칙 6의 예외 하나를 만든다. 대신 W7이 숫자를 더할 때마다 스키마나 프로필 코드를 고치지 않는다. 열린 자리는 숫자·참거짓·id만 받으므로 글이 파일에 들어가지 않는다(원칙 3). 반대하면 4.3 ①의 표가 꼴 전체가 되고, S1 시작 조건 (3)이 "W7의 최종 숫자 목록 확정"으로 무거워진다 |
| (전달) | R1: W5 지시서에 `run_xp_max` 보정을 넣기 | 그대로 | 넣지 않으면 단계 Ⅳ 판의 저장이 실패한다 |
| (전달) | `CLAUDE.md` "저장" 절을 스키마 5로 고치기(S1 뒤) | 그대로, 디렉터 몫 | 지금도 스키마 3으로 잘못 적혀 있다 |
| (전달, 새) | 트리 재설계 지시서에 4.8 Q-T1 데이터 규칙(리비전 올리기), Q-T3(`legal_ranks`에 `exclusive`), R11(두 데이터 파일을 함께, `tree_id` 검사)을 넣기 | — | `design-lead`·`gameplay-systems`의 D12 묶음 |
| (전달, 새) | 의상 해금 작업에 4.8 의상 규칙 둘을 넣기 | — | D12 A1 |
| (전달, 새) | 강화·다시 굴리기를 다시 검토할 때 4.7의 계약(저장된 `stats`를 바꾸지 않음)을 넣기 | — | H-4 |

---

## 14. 확인하지 못한 것 (2026-11-20 개정)

- 이 문서를 쓰고 고치는 동안 Godot·회귀·시뮬레이션을 하나도 돌리지 않았다. `run_all.py`의 지금 통과 여부와 검사 개수는 S0 보고서(커밋 `67b2184`, `--quick`)의 값만 있다. `--jobs 4` 전체 회귀의 걸리는 시간과 골든 사례 수는 재지 않았다.
- `test_profile_v4.gd`가 손으로 만드는 문서가 모두 지금 코드가 저장한 파일에서 출발하는지는 행을 훑어 본 [추정]이다. S1이 고치면서 확인한다.
- `hud_dump.gd`의 `rejected` 고정 묶음이 v5에서도 고치지 않고 도는지는 코드를 읽고 한 [추정]이다(경로·이름을 스스로 정하고 구조 깨기는 스키마와 무관). `--result-mock`과 `--reject-choice=fresh`를 함께 쓸 수 있는지도 머리 주석만 읽었다.
- 화면(`chapter_hud.gd`)이 `resume_info().kind`를 어떻게 쓰는지 읽지 않았다(R5).
- 사용자 저장이 지금 스키마 4인지, 격리될 것이 있는지 보지 않았다(사용자 폴더를 열지 않는다).
- W7(`RunRecord`)의 실제 출력과 W9(`quests.json`)의 최종 꼴은 아직 보지 못했다. 4.3 ①은 D11 F1을 바탕으로 한 안이고, W7 보고 뒤 디렉터가 확정한다.
- 데이터 검사가 "모든 `tree_id`가 `skill_trees.json`에 있다"를 확인하는지(R11) 읽지 않았다.
- `sim_progression.gd -- --runs=1`의 인수가 지금 도구에 맞는지 확인하지 않았다.
- 스팀 자동 클라우드 패턴에 `-v5*`를 더해야 하는지는 T4-C의 일이다(T5 18절과 같음).
