# 기술 검수 — 저장 스키마 4 S1(프로필 v4와 앱 연결), T3-L1 검수 지적 R1·R2

2026-11-17, 기술 책임자(tech-lead). 대상: main `ca11a18` 위 작업 트리의 커밋 전 변경(`chapter1/core/chapter_profile.gd` 전면 개정, `loot.gd`, `loot.json`의 `rare_names`, 새 `outfits.json`, `app/chapter_one.gd`, `chapter1/tests/`의 검사들, `tools/dev/run_all.py`, `tools/manager/test_rare_words.py`). 지시서 `docs/specs/T5-schema4-directives-20261117.ko.md`.

코드·데이터는 고치지 않았다. 사용자 폴더(`%APPDATA%\WitchMoira`)는 열지 않았다. 내가 띄운 Godot는 모두 `python tools/dev/godot.py --headless`(APPDATA가 `_local/appdata/godot/`)였고, 탐침 파일과 작업 파일은 `_local/review-s1/` 아래에만 있다.

---

## 0. 판정

| 문턱 | 판정 | 조건 |
|---|---|---|
| **커밋** | **조건부** | B1(판 보상이 통째로 저장되지 않는 경우)과 B2(앱이 화면의 비공개 값을 읽다 스크립트 오류가 나는 길)를 고치고 `run_all.py` 전체를 다시 통과시킨 뒤. B3(R1 미완)은 같은 작업 안에서 고친다 |
| **사용자 플레이** | **아직 안 됨** | B1을 고친 뒤. 그 전에 사용자가 이 작업 트리로 게임을 띄우면 옛 저장은 안전하게 옮겨지지만(아래 1·2절), 판 결과 저장이 거부되어 그 판의 장비·경험치를 잃는 일이 실제로 생길 수 있다 |
| 플레이 전 사용자 폴더 복사 | **권한다** | 첫 실행 전에 `%APPDATA%\WitchMoira` 폴더를 통째로 다른 곳에 복사해 두시라고 사용자께 말씀드린다(사용자가 직접. 에이전트는 그 폴더를 건드리지 않는다). 새 코드는 옛 파일을 쓰지 않지만, 옮긴 뒤의 진행은 v4에만 있어 옛 실행본으로 돌아갈 수 없고, 아직 사용자 실제 저장으로 옮겨 본 적이 없다 |

주의: 이 변경은 이미 main 작업 트리에 들어 있다. 커밋과 무관하게 지금 `run_dev.py`로 게임을 띄우면 이 코드가 돈다. B1을 고치기 전에는 사용자께 이 트리로 플레이하지 마시라고 알려야 한다.

---

## 1. 사용자 폴더 안전

### 1.1 결론

- **새 코드가 v3·v2·v1 파일, 그 기록본, v3 가리키는 파일, v3 r-파일을 쓰기로 열거나 지우거나 이름을 바꾸는 경로는 없다.** [확인: 아래 표의 모든 호출과 그 대상 경로를 코드에서 따라감, 탐침으로 바이트 비교]
- 제품 실행(QA 아님)에서 쓰기 대상이 될 수 있는 경로는 `user://chapter-one-profile-v4.json`, `user://chapter-one-profile-v4-r<시각>[-n].json`, `user://chapter-one-profile-v4-active.json`, `user://revisions/` 아래의 v4 기록본, 그리고 각각의 `.tmp` 임시 파일뿐이다.
- `chapter1/` 전체에 `remove_absolute`·`DirAccess.remove`가 게임 코드에는 0건이다(검사 파일과 `_local` 정리에만 있다, 1.3).
- 두 실행이 같은 저장을 함께 쓰는 경우(하나가 v3에서 옮겨 메모리에 들고 있는 동안 다른 하나가 v4를 먼저 씀): 뒤의 저장은 `save_changed_elsewhere`로 거부되고 앞의 v4 파일을 덮지 않는다(`chapter_profile.gd:954-956`).

### 1.2 게임 코드의 쓰기·이름 바꾸기·폴더 만들기(전부)

| 위치 | 호출 | 대상 | 제품 실행에서의 실제 경로 | v3 시대 파일이 될 수 있나 |
|---|---|---|---|---|
| `chapter_profile.gd:363` | `FileAccess.open(…, WRITE)` | `pointer_path+".next-<usec>.tmp"` | `user://chapter-one-profile-v4-active.json.next-….tmp` | 아니다. `pointer_path`는 제품에서 `POINTER_PATH`(v4) 상수(`:176`) |
| `chapter_profile.gd:367` | `DirAccess.rename_absolute(tmp, pointer_path)` | v4 가리키는 파일 | 위와 같음 | 아니다 |
| `chapter_profile.gd:963-964` | `make_dir_recursive_absolute` | `path`의 폴더, `journal_dir()` | `user://`, `user://revisions` | 폴더 생성만 |
| `chapter_profile.gd:966` | `FileAccess.open(…, WRITE)` | 기록본 `revisions/<바탕>.revision-<rev6>-<날짜>-<pid>-<usec>.json`, 임시 `<path>.next-<같은 표>.tmp` | 바탕은 `chapter-one-profile-v4` 또는 `chapter-one-profile-v4-r…` | 아니다. 기록본은 하위 폴더, 바탕 이름이 v4 |
| `chapter_profile.gd:971` | `DirAccess.rename_absolute(tmp, path)` | `path` | `PATH_V4`, 또는 v4 가리키는 파일이 가리키는 v4 r-파일(`_pointed`, 이름 규칙 `^chapter-one-profile-v4-r[0-9-]+\.json\z`), 또는 거부 뒤 새로 만든 v4 r-파일 | 아니다. `path`가 정해지는 길은 셋뿐이고(`:178`, `:340-342`, legacy 거부 때는 `:178`의 v4 경로 그대로) 셋 다 v4 이름이다. v3 가리키는 파일은 v3 이름 규칙으로 따로 읽기만 한다(`:218-222`) |
| `chapter_one.gd:111-112` | `FileAccess.open(…, WRITE)` | QA 입력 기록 | 바뀌지 않음(S1 밖) | — |
| `chapter_one.gd:329`, `:660` | `make_dir_recursive_absolute` | 캡처 폴더 | 바뀌지 않음(S1 밖) | — |
| `view/loc.gd:130` | `ConfigFile.save` | `user://settings.cfg` | 바뀌지 않음(S1 밖) | — |

읽기만 하는 곳: `configure`(`:179-196`), `_pointer_target`(`:206-215`), `_journal_rows`(`:250-262`, `DirAccess.open`으로 목록만), `latest_readable_revision`, `_v3_journal_resume`, `_v3_source_resume`, `_reject`(`:379`, 파일 바이트의 sha256 앞 16자만 로그).

임시 파일과 기록본의 자리: v4 기록본은 `user://revisions/`, 임시는 본 파일 옆의 `.tmp`. 바꿔 끼우기 실패 때 남은 `.tmp`와 기록본은 지우지 않는다(지우는 코드는 S3). v3 기록본(본 파일 옆 `chapter-one-profile-v3.revision-*.json`)과 이름 규칙이 겹치지 않는다.

### 1.3 검사·도구가 격리 밖을 건드릴 길

| 검사 | 맨 앞의 `OS.get_user_data_dir()` 확인 | 작업 폴더 | 판단 |
|---|---|---|---|
| `test_chapter_profile.gd` | 있음(`:321`, `execute`의 첫 문장) | `--fixture-dir`, `res://_local/`로 시작해야 함(`:326`), 이미 있으면 중단(`:328-329`) | 됨 |
| `test_profile_v4.gd` | 있음(`:79`, 첫 문장) | `--work-dir`, `res://_local/` 확인(`:83`) | 됨 |
| `test_profile_legacy_fixtures.gd` | 있음(`:31`) | `--work-dir`, 확인(`:37`) | 됨 |
| `test_profile_app_loadout.gd` | 있음(`:37`) | `res://_local/app-loadout/<usec>` 고정 접두사 | 됨 |
| `test_profile_app_guard.gd` | 없음 | 앱을 트리에 넣지 않아 `_ready`(제품 `configure()`)가 돌지 않는다 | S1 밖, 지금과 같음 |
| `hud_dump.gd` | 없음 | 앱 `_ready`가 `--chapter1-profile-off`가 없으면 제품 `configure()`를 부른다 | 지금과 같음. `godot.py`가 `--script`를 늘 격리하므로 정해진 명령으로는 사용자 폴더에 닿지 않는다 |

남는 구멍(작음, 지금 고칠 필요는 없음):
- QA 경로 확인이 `begins_with("res://_local/")`뿐이라 `res://_local/../../..`처럼 `..`를 넣으면 프로젝트 밖을 가리킬 수 있다(`chapter_profile.gd:171`, 검사들의 `--work-dir`·`--fixture-dir` 확인도 같음). 일부러 그런 인수를 넣어야만 생기는 일이다. Q1이나 다음 프로필 작업에서 `..`를 거부하는 한 줄을 더하기를 권한다.
- 원시 Godot 실행 파일을 `godot.py` 없이 `--script`로 직접 부르면 격리되지 않는다. 그때도 위 네 검사는 맨 앞 확인으로 멈춘다. `hud_dump.gd`는 `--chapter1-profile-off`를 빼면 사용자 저장을 읽고, 자동 조작 판이 끝나면 쓴다(지금과 같은 위험, CLAUDE.md의 명령은 profile-off를 넣고 있다).

---

## 2. 옮김의 정확성 — 직접 탐침

탐침 `_local/review-s1/probe_migrate.gd`. 기대값을 `expected_v3.json`에만 기대지 않고 **원본 v3 파일을 직접 읽어** 비교했다. 결과: **184개 확인 통과, 1개 실패(B1)**.

```
python tools/dev/godot.py --headless --path . --script res://_local/review-s1/probe_migrate.gd
PROBE_RESULT {"fails":["a run that wore a new piece in a kept slot saves (got: Worn kit rejected: kept slot)"],"ok":184}
```

| 확인 | 표본 | 결과 |
|---|---|---|
| 읽기만으로 폴더의 어떤 파일도 생기거나 바뀌지 않음(폴더 전체 sha256) | v3 셋, v2, v1, 기록본 묶음 | 통과 |
| 장비 수와 번호(`storage_id` 순서까지), 등급·기본·접사·능력치·아이템 레벨·요구 레벨·전설 id가 원본 v3와 같음 | `v3_full`·`v3_rare_oldword`·`v3_rare_threeword`(각 38개) | 통과 |
| 희귀 이름이 원본 v3에 저장된 글과 같음 | 세 파일, 희귀 각 16개 이상 | 통과(옛 낱말·세 낱말은 `legacy_name`으로 같은 글) |
| 모든 장비의 화면 이름이 `expected_v3.json`과 같음 | 세 파일 | 통과 |
| `next_id`·`completed_runs`·`best_ticks`·`essence`·`receipts`·`revision` | 세 파일 | 통과 |
| 마녀별 `xp`·`tree_revision`·`ranks`·`first_rewards`·`respecs` | 세 파일(서리: 투자 3·첫 처치 셋, 화염: 경험치만) | 통과 |
| 세 마녀의 `loadout`이 v3 `equipped`와 같음(T5-U1) | v3 셋, v2, v1 | 통과 |
| 세 마녀의 출발 장비(이름·설명 뺀 비교), 막힌 장비, 레벨이 기대와 같음 | v3 셋, v2, v1 | 통과 |
| `depth_cleared`가 `boss` 영수증에서 `{"d1":1}` | `v3_full` 서리 | 통과 |
| 첫 저장 뒤 v3 바이트 그대로, 다시 열면 v4를 읽고 리비전 n+1, 장비 중복 없음 | 세 파일 | 통과 |
| v3에 있던 옛 영수증으로 다시 `record_run` → 아무것도 바뀌지 않음(중복 지급 없음) | 세 파일 | 통과 |
| 새 영수증 두 번 → 경험치 한 번, 세 번째로 열어도 경험치·장비 한 번 | 세 파일 | 통과 |
| v4가 생긴 뒤 v3를 더 새것으로 바꿔도 v4를 읽음 | 세 파일 | 통과 |
| v2·v1에서 옮김: 장비 수, 경험치 규칙, 출발 장비, 첫 저장 뒤 원본 바이트 그대로 | `v2_sample`, `v1_sample` | 통과 |
| 기록본 묶음의 본 파일(v3 코드는 거부하던 것): 받아들임, 장비 하나만 격리(사유 `Base+affix identity/stats`), 나머지 7개, 경험치·첫 처치·영수증·재가 원본과 같음 | `v3_with_journals` | 통과 |
| 격리된 장비를 데이터와 맞게 돌려놓으면 같은 `storage_id`로 되살아남(`restored_items` 1) | 같은 묶음, 저장 뒤 파일을 손으로 고쳐 | 통과 |
| v3 본·기록본·가리키는 파일·r-파일 바이트 그대로 | 같은 묶음 | 통과 |
| 끊긴 옮김: `revisions/`에 기록본과 `.tmp`만 있고 v4 본 파일 없음 → v3에서 다시 옮기고 다음 저장이 v4를 만듦, 장비 한 번, 남은 파일 바이트 그대로 | `v3_full` | 통과 |
| v4 가리키는 파일만 있고 그것이 가리키는 r-파일 없음 → v3에서 옮기고 v4 본 경로를 씀 | `v3_full` | 통과 |
| v4 본 파일이 깨지고 v4 기록본도 모두 깨짐 → 이어 하기 후보 `v3_source`, 새 저장으로 시작하면 38개, 기존 파일 하나도 안 바뀜, 다음 실행은 가리키는 파일로 r-파일을 읽음 | `v3_full` | 통과 |
| **출발에서 빠진 칸(`kept_slots`)에 판에서 새 장비를 낀 판의 저장** | `v3_full` 서리(반지 칸이 요구 레벨로 빠짐) | **실패 — B1** |

`v3_journals_main_only`의 판정 변화(거부 → 받아들임 + 격리 1개)는 결정 T5-D1의 귀결로 받아들인다. 그 표본에서 받아들인 상태의 경험치·첫 처치·영수증·재는 원본(리비전 4)과 같고, 잃는 것은 위조된 장비 하나의 사용뿐이며 그 원본은 `quarantine`에 남는다. 다만 `test_profile_legacy_fixtures.gd`의 `_journals_main_only`(`:123-133`)는 격리 개수와 사유만 보고 나머지 상태를 비교하지 않는다. 위 표의 비교(경험치·첫 처치·영수증·재, 장비 수 = 원본-1)를 두 줄 더하기를 권한다(필수 아님).

---

## 3. 결정대로인가 — L4·L5·의상·tree_reset

| 항목 | 결정 | 확인 |
|---|---|---|
| 공용 착용을 세 마녀에게 복사(U1) | `upgrade_v3` `:505-512`, 탐침 통과 | 맞음 |
| 한 장비를 여러 마녀가 동시에(U2) | `select_item`에 막는 검사 없음, `_read_character`의 "같은 장비 두 칸" 검사는 한 마녀 안에서만(`:868`), V-12 | 맞음 |
| 의상은 마녀별, 첫 컬렉션 처음부터(U3·U4) | `outfits.json` 여섯 줄 모두 `default_owned: true`, `wardrobe_view`가 데이터 기본 소유를 합침(`:1175-1180`), 파일에는 쓰지 않음 | 맞음 |
| 이어 가기는 이긴·쓰러진·포기한 판 모두(U5) | `_save_terminal`이 모드와 무관하게 `carry`를 만듦(`chapter_one.gd:593-594`), 앱 검사가 포기한 판으로 확인 | 맞음 |
| 출발 장비를 못 넣은 판은 묶음을 안 바꿈 | `_import_profile_kit`(`chapter_one.gd:427-434`)의 `_run_carry_ok`, 앱 검사 | 맞음 |
| `carry`가 영수증과 같은 한 번의 쓰기 | `record_run` 끝의 `_persist` 하나(`:1050`), 같은 영수증이면 `carry`가 달라도 무시(`:1007`, V-11) | 맞음 |
| 해체한 장비는 모든 묶음에서 빠짐 | `salvage` `:1133-1136`, V-12 | 맞음 |
| 격리된 장비를 가리키는 칸은 남고 출발에서 빠짐, 판이 끝나도 그 칸은 이전 값 유지 | `starting_kit`이 `kept_slots`에 넣음(`:1153`), `_apply_carry`가 `kept_slots`의 이전 값 유지(`:1077`), V-8 | 맞음. 단 B1 |
| `tree_reset` 자리(D8 8.2 S1+) | `CHAR_KEYS`에 포함, 기본값 `{granted:[], used:[]}`, 읽기 고침(중복 하나로, `used`에만 있는 id를 `granted`에), 쓰기 엄격, 키 없거나 형이 다르면 거부. `reset_checks`가 D8 P1·P2를 다룸 | 맞음. 옮길 때 채워 넣기(P12)는 R1 몫이라 비어 있는 것이 맞다 |

---

## 4. `loot.json` 변경과 골든

- `rare_names`를 `{id,name}`으로 바꾼 것은 굴림 결과와 난수 소비를 바꾸지 않는다. **직접 대조**: HEAD의 `loot.gd`·`loot.json`을 `_local/review-s1/old_*`로 꺼내 지금 파일과 같은 시드로 굴렸다.

```
python tools/dev/godot.py --headless --path . --script res://_local/review-s1/probe_loot.gd
PROBE_LOOT {"compared":11850,"diffs":0,"loaded":[true,true],"rares":1000,"rng_same":true,"sample":["폐허 숨결","새벽 그림자","새벽 맹세","폐허 맹세","서약 숨결","순례 파편"]}
```
  `roll_item` 4,000번과 `roll_class` 4,000번(장비 11,850개, 희귀 1,000개)이 바이트까지 같고, 끝난 뒤 난수 상태가 같으며, 희귀 1,000개 모두 `rare_name_for(rare_word_ids(이름)) == 이름`이다.
- 골든·글 없는 골든·드랍 시뮬레이션: 디렉터의 전체 회귀(1.5절)에서 불일치 0, 갱신 없음. 위 대조와 합치면 증거로 충분하다.
- 관리 툴(`test_rare_words.py`)은 새 형식을 읽고 옛 형식 검사는 이름만 뽑아 돌린다. 통과.

---

## 5. 불안정한 회귀

### 5.1 사실

- 디렉터가 본 저장소에서 돌린 전체 회귀 `_local/run_all-s1-20261117.log`: **17개 모두 통과, `exit=0`**. 이 작업의 첫 전체 통과다. 그 사이 나는 같은 저장소에서 Godot 검사 24번과 탐침 다섯 개를 동시에 돌렸다.
- 구현자의 두 실패는 구현자의 작업 폴더(`.claude/worktrees/agent-ad4cb00579c7376f5`)에서 났다. 그 폴더의 Godot 로그(`_local/appdata/run_all/WitchMoira/logs/godot2026-11-17T19.42.57.log`)에 원인 줄이 남아 있다.
  ```
  ERROR: Attempt to open script 'res://chapter1/core/chapter_pilot.gd' resulted in error 'Can't open file'.
     [0] play (res://chapter1/tests/golden_core.gd:47)
  SCRIPT ERROR: Attempt to call function 'new' in base 'null instance' on a null instance.
  ```
  첫 실패는 `Cannot read growth definitions: res://chapter1/data/growth_quality36.json`. 둘 다 **바뀌지 않은 파일(그 작업 폴더에서 16:34 이후 수정 없음)을 여는 데 실패**한 것이다(`ERR_FILE_CANT_OPEN`, "없음"이 아니라 "열 수 없음"). 같은 golden-textless 실행에서 둘째~넷째 사례는 같은 파일을 다시 읽어 통과했다 → 한순간의 열기 실패.
- 그 시각에 구현자는 같은 작업 폴더에서 다른 Godot 검사를 따로 돌리고 있었다(그 폴더의 `godot` 격리 로그 19:04·19:08·19:23과 `t_*.log` 시각이 두 전체 회귀와 겹친다).

### 5.2 재현 시도

```
# 같은 저장소에서, 디렉터의 golden-textless가 도는 동안, 네 검사를 동시에 6번
for i in 1..6: godot.py … test_chapter_run.gd & test_profile_app_loadout.gd & test_profile_v4.gd --work-dir=…/v4-$i & test_profile_legacy_fixtures.gd --work-dir=…/legacy-$i & wait
→ 24번 모두 결과 줄 실패 0, SCRIPT ERROR·"Can't open"·"Cannot read" 0
```

### 5.3 판단

- **S1이 만든 경쟁 조건은 아니다**[추정이지만 근거가 셋]. 실패한 파일은 S1이 건드리지 않은 읽기 전용 파일이고, S1의 새 검사는 실행마다 다른 폴더(`run_all`의 초 단위 표, `app-loadout`의 마이크로초 표)에만 쓰며, 같은 저장소에서 동시 실행 24번과 전체 회귀 한 번이 깨끗했다.
- 원인은 확인하지 못했다. 가장 그럴듯한 것은 Windows에서 다른 프로세스(백신 검사, 같은 폴더의 동시 실행 등)가 파일을 잠깐 잡은 것이다[미확인].
- 대신 이 일로 드러난 도구의 약점 둘은 qa-perf에 넘긴다(S1을 막지 않음):
  - `golden_core.gd:47`처럼 `load()` 결과를 확인하지 않는 검사는 열기 실패 하나에 스크립트 오류 → 종료하지 않음 → 600초 시간 초과가 된다. `load()`가 null이면 결과 줄에 실패를 적고 `quit(1)` 하게.
  - `run_all.py:28`의 표가 초 단위라 두 `run_all`이 같은 초에 시작하면 `profile` 검사가 "Fresh isolated fixture directory"로 실패한다. 또 `test_loc.gd`(`res://_local/test-loc` 고정, 시작 때 설정 파일을 지움)와 `test_loot.gd`(`res://_local/d5` 고정 파일)는 두 실행이 겹치면 서로를 깬다. **같은 작업 폴더에서 `run_all.py`를 두 개 동시에 돌리지 않는다**는 규칙을 운용에 적고, 표에 프로세스 번호를 붙이기를 권한다.

---

## 6. 구현자가 지시서와 다르게 정한 것

| 항목 | 판정 | 이유 |
|---|---|---|
| `normalize_v3` 삭제 | 받아들임 | v3 읽기가 `upgrade_v3` + v4 너그러운 읽기로 바뀌어(5.4절) 옛 엄격 검사기가 남으면 D1과 어긋난다. v2용 `normalize`는 남았다 |
| `starting_gear()`의 마녀 없는 호출 제거 | 받아들임 | 공용 묶음이 없어져 뜻이 없다. 호출하는 곳 0(검색 확인) |
| `configure` 끝에 인수 둘(`legacy_v3`, `legacy_v3_pointer`) | 받아들임 | QA에서 v3 경로를 격리 경로로 줄 방법이 필요하다. 제품 경로는 상수로 덮어쓴다(`:176`) |
| `resume_info()`에 `kind` | 받아들임 | 지시서 5.5절이 요구한 것 |
| 이야기·수집품 id를 시험 훅으로만 | 받아들임 | 데이터 파일이 아직 없다. 훅이 없으면 모르는 id로 모두 거부되는 것이 지시서 6.2절의 "파일이 없으면 비어 있어야 한다"와 맞다 |
| "번역 바꿈" 검사 생략 | 조건부 | 파일에 글이 없으므로(V-5) 언어와 무관하다는 것은 따라 나온다. 다만 7절의 표에 있는 검사다. Q1에 넣는다 |
| 앱이 `hud._menu_witch`(비공개 값)를 읽음 | **고칠 것(B2)** | 임시 방식 자체는 받아들이나 실패하는 모양이 나쁘다. 아래 B2 |
| `v3_journals_main_only`의 판정 변화 | 받아들임 | 2절 끝 |
| `expected_v3.json`의 `error` 문장 대신 `error_code` 표 비교(C1) | 받아들임 | 표본을 다시 만들지 않고 대응표(`test_profile_legacy_fixtures.gd:19`)로 비교. 표본 바이트는 그대로(sha256 검사 통과) |

---

## 7. T3-L1 검수 지적

| 지적 | 결과 | 근거 |
|---|---|---|
| **R1** 은총 카드 경로를 실제로 검사 | **안 됨(B3)** | 아래 |
| **R2** 후계 성장 설정의 "이름만 다르면 받음, 다른 필드면 거부" | 됨 | `test_growth.gd`에 세 줄(이름만 다름 → 받음, 피해 값 → 거부·상태 그대로, 카드 무게 → 비교 규칙으로 거부). 전체 회귀 growth 192 통과 |
| C1 프로필 `error`를 영어로 | 됨 | `chapter_profile.gd`의 한글 0줄. 단 `tools/dev/i18n_baseline.json`의 이 파일 기준이 40으로 남아 있어 다시 늘어도 잡히지 않는다(`I18N_SCAN … "shrunk": ["chapter1/core/chapter_profile.gd: 0 < 40"]`). 기준을 0으로 내리기를 권한다 |
| C2 앱이 `profile.error`에 글을 넣지 않음 | 됨 | `_app_error`(`chapter_one.gd:357`, `:375`, `:482`) |
| C3 덤프가 앱의 문장 함수를 거침 | 됨 | `hud_dump.gd:170`, `:479` |

---

## 8. 고칠 것

### B1 (반드시, 커밋·플레이 전) 출발에서 빠진 칸에 판에서 새 장비를 끼면 판 저장 전체가 거부된다

- 위치: `chapter1/core/chapter_profile.gd:1075-1077`(`_apply_carry`)
  ```gdscript
  for slot in kept:
      if not slot is String or not slot in EQUIP_SLOTS or next.has(slot):return "kept slot"
  ```
- 재현(탐침 `kept_slot_case`): `v3_full`을 옮긴 서리는 요구 레벨 때문에 반지 칸이 출발에서 빠진다(`kept_slots: ["ring"]`). 판에서 반지를 주워 끼면 코어는 빈 `ring` 칸에 넣는다(`combat_core.gd:237-243`의 `target_slot`, `quick_equip`). 판이 끝나 앱이 `carry = {equipped: run.equipped, kept_slots: ["ring"]}`를 넘기면 `record_run`이 `Worn kit rejected: kept slot`으로 **저장 전체를 거부**한다. 그 판의 장비·경험치·첫 처치·영수증이 저장되지 않고, 결과 화면의 다시 시도도 같은 이유로 계속 실패한다.
  ```
  KEPT_SLOT_SAVE {"code":"save_candidate_rejected","error":"Worn kit rejected: kept slot","saved":false,"slot":"ring"}
  ```
- 흔한 경우다: 옛 공용 묶음이 세 마녀에게 복사되므로 레벨이 낮은 마녀(옮긴 표본에서 번개는 다섯 칸, 화염도 다섯 칸)가 빠진 칸을 많이 가진 채 출발한다.
- 지시서의 빈틈이다(8.2절이 "판에서 낀 칸"과 "빠진 칸"이 겹치는 경우를 정하지 않았다). 정한다: **판에서 낀 것이 이긴다.** 그 칸은 판의 장비로 바뀌고, 빠져 있던 이전 장비는 보관함에 그대로 남는다.
- 고치는 법: `_apply_carry`에서 `next.has(slot)`인 빠진 칸은 오류 대신 건너뛴다(형식이 틀린 칸 이름만 거부). 앱(`chapter_one.gd:594`)은 그대로 둬도 된다.
- 더할 검사(`test_profile_v4.gd` V-11): 빠진 칸에 새 장비를 낀 `carry` → 저장됨, 그 칸 = 새 장비의 `storage_id`, 이전 장비는 보관함에 있음. 그리고 같은 경우를 앱 검사(`test_profile_app_loadout.gd`)에서 한 번: 요구 레벨이 높은 반지가 묶음에 있는 마녀로 출발 → 판에서 반지를 `quick_equip` → `_save_terminal` 성공.
- 덧붙여 권함(필수 아님): 보상 저장이 착용 묶음 때문에 막히지 않게, 앱이 `carry` 거부(`save_candidate_rejected` + 사유 `Worn kit rejected`)를 받으면 `carry` 없이 한 번 더 저장한다. 그러면 앞으로 다른 빈틈이 나와도 잃는 것은 묶음 변경뿐이다.

### B2 (반드시, 커밋 전) 앱이 화면의 비공개 값을 읽다 스크립트 오류가 나는 길

- 위치: `chapter1/app/chapter_one.gd:469`
  ```gdscript
  var index: int=int(hud.get("_menu_witch"))
  ```
- `ui-hud`가 `chapter_hud.gd`를 고치는 중이다. 그 값의 이름이 바뀌거나 없어지면 `hud.get`이 null을 주고 `int(null)`은 **스크립트 오류**다(직접 확인: `SCRIPT ERROR: Invalid call. Nonexistent 'int' constructor.`, 탐침 `_local/review-s1/probe_null.gd`). `menu_character_id()`는 `_sync_profile`(`:539`)에서 불리므로 `_ready`, 메뉴 복귀, 저장 뒤마다 프로필 줄 갱신이 중간에 끊긴다.
- 고치는 법: `if not "_menu_witch" in hud: return ""`를 앞에 둔다(빈 마녀면 `select_item`이 `unknown_character`로 거부하고 묶음은 `{}`로 보인다 — 조용히 엉뚱한 마녀에게 끼우지 않는다).
- 그리고 `ui-hud`에 공개 함수 `menu_character_id() -> String`을 요청한다(이미 `has_method`로 먼저 찾게 되어 있다, `:468`). 이 요청은 디렉터가 지금 `chapter_hud.gd`를 고치는 `ui-hud` 작업에 한 줄로 더하면 된다.

### B3 (같은 작업 안에서) R1이 실제로는 아무것도 검사하지 않는다

- 위치: `chapter1/tests/test_core_text.gd:69-78`
- `run.growth.snapshot().offer`는 앱이나 조작이 `get_offer()`를 부르기 전까지 비어 있다(`combat_core.gd:211`, 제안은 그때 만들어진다). 자동 조작은 다음 `decide()`에서 그것을 부르므로, 이 검사가 보는 시점의 제안은 늘 `{}`이고 `token`은 `""`다. `last_offer_token`의 처음 값도 `""`라 조건이 **한 번도 참이 되지 않는다.** 그래서 카드도 `_eligible_cards()`도 걷지 않는다. 그리고 "카드 경로를 적어도 한 번 보았다"는 검사 줄이 없어 이것이 드러나지 않는다(`card_titles`는 반환만 하고 확인하지 않음).
- 직접 확인(같은 반복을 냉기 시드 11로 돌린 탐침 `_local/review-s1/probe_r1.gd`):
  ```
  OFFER {}
  OFFER {}
  PROBE_R1 {"card_keys":[],"choice_ticks":11,"mode":"victory","offers":1,"tick":25005,"titled_cards":0}
  ```
- 고치는 법: `mode == "choice"`인 틱에 `run.get_offer()`를 불러 그 결과를 걷는다(조작이 곧 부를 것과 같은 제안이 캐시되므로 결과·난수가 바뀌지 않는다 — 고친 뒤 골든·글 없는 골든 불변으로 확인), 처음 값 비교를 없애거나 `token`이 빈 문자열이 아닐 때만 갱신, 그리고 `check(card_titles_seen > 0, "…saw at least one grace card")`를 세 주력마다 더한다.

### 권함(필수 아님, 이번이나 다음 작업)

| # | 위치 | 내용 |
|---|---|---|
| N1 | `chapter1/tests/hud_dump.gd:126-129` | `_wipe_folder`가 하위 폴더 `revisions/`를 지우지 않아, 같은 태그로 다시 돌리면 앞선 실행의 v4 기록본이 남는다. 거부 시점의 이어 하기 후보와 `files` 목록이 실행마다 달라진다(사용자 안전과 무관, 덤프 비교의 재현성). `res://_local/` 아래인지 확인한 뒤 `revisions/`의 파일도 지운다. 일반 고정 묶음(`:110-113`)도 같은 이유로 `profiles/revisions/<태그>.revision-*`가 쌓인다 |
| N2 | `chapter1/tests/test_profile_legacy_fixtures.gd:123-133` | 2절 끝: 격리 표본의 나머지 상태 비교 두 줄 |
| N3 | `tools/dev/i18n_baseline.json:6` | `chapter_profile.gd` 기준 40 → 0 |
| N4 | `chapter_profile.gd:513-514` | 모르는 마녀 id의 v3 항목은 v3 키 다섯 개 그대로 격리되어, 나중에 그 마녀가 데이터에 생겨도 되살리기 조건(`keys_match(raw, CHAR_KEYS)`, `:730`)을 영영 통과하지 못한다. 지금 데이터에 없는 마녀 id가 저장에 있을 일은 없어 실제 영향은 없다. 되살릴 때 v3 모양이면 `default_entry`에 다섯 키를 덮어 읽게 하거나, 주석으로 "v3에서 온 모르는 마녀는 되살리지 않는다"고 남긴다 |
| N5 | `chapter_profile.gd:171` 등 | QA 경로에 `..` 거부(1.3) |
| N6 | `golden_core.gd:47`, `run_all.py:28` | 5.3의 도구 약점(qa-perf) |

---

## 9. 직접 실행한 명령과 결과

| 명령 | 결과 |
|---|---|
| `_local/run_all-s1-20261117.log`(디렉터가 본 저장소에서 실행한 `run_all.py` 전체) 읽기 | growth 192, tree 118, combat 75, chapter 474, profile 124, loot 36, loc 876, app-guard 5, profile-legacy 298, profile-v4 109, app-loadout 13 검사 실패 0, golden 4·golden-textless 4 불일치 0, core-text 21 실패 0, loot-sim 3000판 불일치 0, manager 55, i18n-scan 538(기준 578). `RUN_ALL {"passed": 17, "failed": [], "skipped": []}`, `exit=0` |
| `python tools/dev/godot.py --headless --path . --script res://_local/review-s1/probe_migrate.gd` | `PROBE_RESULT {"ok":184, "fails":[B1 하나]}`, `JOURNALS_MAIN`·`KEPT_KIT`·`KEPT_SLOT_SAVE` 줄은 본문 |
| `python tools/dev/godot.py --headless --path . --script res://_local/review-s1/probe_loot.gd` | `diffs 0`, `rng_same true`, 11,850개·희귀 1,000개 |
| `python tools/dev/godot.py --headless --path . --script res://_local/review-s1/probe_r1.gd`(두 번) | `choice_ticks 11`, 보인 제안 `{}`, 카드 0 |
| `python tools/dev/godot.py --headless --path . --script res://_local/review-s1/probe_null.gd` | `int(null)` → `SCRIPT ERROR: Invalid call. Nonexistent 'int' constructor.` |
| 네 검사(`test_chapter_run`, `test_profile_app_loadout`, `test_profile_v4 --work-dir=…/v4-N`, `test_profile_legacy_fixtures --work-dir=…/legacy-N`)를 동시에 6번, 디렉터의 golden-textless와 겹쳐서 | 24번 모두 실패 0, 스크립트 오류·열기 실패 0. 로그 `_local/review-s1/flaky/` |
| `python tools/dev/i18n_scan.py` | `"shrunk": ["chapter1/core/chapter_profile.gd: 0 < 40"]`, 늘어난 것 0 |
| 구현자 작업 폴더의 로그 읽기(`.claude/worktrees/agent-ad4cb00579c7376f5/_local/`의 `run_all_full.log`, `run_all_final.log`, `run_gt.log`, 격리 폴더의 Godot 로그) | 5.1절 |
| `profile_v4_compat.json`을 Python으로 읽기만 | 한글 0(`legacy_name`·`raw`·v1 장비 밖), 키 14개, 장비 38, 격리 0, 서리 `depth_cleared {"d1":1}`, 세 마녀 8칸 묶음 |

---

## 10. 확인하지 못한 것

- **사용자의 실제 저장을 옮긴 결과.** 사용자 폴더를 열지 않았다. 장비 수, 옛 낱말 희귀, 격리가 0개인지는 사용자가 처음 실행할 때 로그 한 줄(`CHAPTER1_PROFILE_READ_FIXES`, 없으면 고친 것 0)로만 알 수 있다. 화면 안내는 아직 없다(ui-hud의 `profile.read_fix.*`).
- 불안정한 회귀의 근본 원인(5.3). 재현하지 못했다.
- 창이 뜨는 실행으로 화면을 보지 않았다. 보관함의 "다음 도전에 장착"이 메뉴에서 고른 마녀 카드와 맞게 보이는지, 카드를 바꿀 때 보관함 표시가 따라 바뀌는지(지금은 보관함을 열 때만 `_sync_profile`)는 화면에서 확인하지 않았다.
- `hud_dump.gd --profile-fixture=rejected`(통과 기준 4)는 다시 돌리지 않았다. 구현자 작업 폴더의 로그에 D5-U 다섯 시점과 `HUD_DUMP_REJECT` 줄(`reason: "storage id"`, 원본 바이트 그대로)이 남아 있는 것만 읽었다.
- `sim_progression.gd`(통과 기준 5)는 다시 돌리지 않았다. 구현자 로그에 한 판 결과 줄이 있다.
- 115개 옛 검사 대응표(통과 기준 3)는 구현자 보고서에 있다고 들었고 나는 보지 않았다. 지금 `test_chapter_profile.gd`는 124개다.
- 같은 사용자가 이 코드로 옮긴 뒤 옛 실행본(이 변경 이전 커밋)으로 돌아가 놀면 v3가 다시 쓰여 진행이 갈라진다(지시서 16절의 위험). 사용자께 함께 알린다.
