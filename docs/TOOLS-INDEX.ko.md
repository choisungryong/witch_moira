# 도구 색인 (TOOLS-INDEX)

`python tools/manager/catalog.py --tools-index`가 만든 파일이다. 손으로 고치지 않는다. 역할별 묶음은 `tools/manager/tools_index.json`에서 고친다.

설명과 예시 명령은 파일 머리 주석에서 그대로 뽑은 글이고, 역할 묶음은 사람이 적은 것입니다. 이 색인이 도구를 돌려 보거나 쓰임새를 잰 것이 아닙니다.

생성: 2026-11-23 12:30:49 · 도구 161개

## 이미 있는데 놓치기 쉬운 것

- 코어를 고치는 동안에는 골든을 전부 돌리지 말고 사례 하나만: golden_core.gd -- --case=11:chapter1.skill.frost (`chapter1/tests/golden_core.gd`)
- 앞 구간만 볼 때는 hud_dump.gd --until=<틱>으로 한 판 8~11분을 1~3분으로 줄인다 (`chapter1/tests/hud_dump.gd`)
- hud_dump.gd --dump의 Control 사각형은 화면 배치(겹침·잘림) 점검의 재료다 (`chapter1/tests/hud_dump.gd`)
- 코어 없이 화면만 띄우는 선례: skill_tree_preview.gd (`chapter1/tests/skill_tree_preview.gd`)
- 회귀는 --only(일부), --quick(골든 제외), --json 이 있다 (`tools/dev/run_all.py`)
- 회귀가 통과·실패를 본다면 audit.py는 구멍의 수를 세고 지난번과 견준다(종료 코드는 나빠진 줄이 있을 때만 1) (`tools/dev/audit.py`)
- 판 안 스킬 구성(run_spells.json, 꺼진 채 들어옴)을 켠 판을 보려면: hud_dump.gd --run-spells=on [--spells-pick=synergy] (이 실행에서만 켬, 데이터·앱은 그대로) (`chapter1/tests/hud_dump.gd`)
- 스킬 구성의 성장 카드 화면은 픽스처로: scene_shot.gd --scenes=boon_spells (--variants=arc,ember는 다른 두 마녀. 최종 확인은 실제 판 캡처) (`chapter1/tests/scene_shot.gd`)
- 게임을 띄워 시험 플레이할 때 꺼진 장치를 이 실행에서만 켜기: --chapter1-trial=spells,rhythm (--chapter1-profile-off와 함께일 때만, 저장에 쓰지 않음) (`chapter1/app/chapter_one.gd`)
- 새 그림·모델을 넣기 전에 계약 대조: asset_intake.py <파일> --slot <자리 id>. 묶음은 --slot 'actor.walker.*' --dir <새 폴더>. 파일 없이 부르면 지금 자리의 파일을 대조 (`tools/art/asset_intake.py`)
- 3D 캐릭터는 생성 메시 -> mesh_reduce -> rig_build -> rig_clips -> rig_parts -> rig_check -> 게임 차례. 쓰는 법 한 쪽: docs/ART-3D-PIPELINE.ko.md (`docs/ART-3D-PIPELINE.ko.md`)
- 서버가 낡았는지는 화면 머리가 알린다(서버를 띄운 뒤 파이썬 코드가 바뀌면 「서버가 낡았습니다」). 화면 파일(js·css)은 다시 시작하지 않아도 새로 생긴 것까지 준다 (`tools/manager/server.py`)
- 소리: audio_mix_offline.py --stats, audio_measure.py --compare-s1 (`tools/dev/audio_measure.py`)
- 새 이름·글을 짓기 전에 낱말 검사기를, 새 결정 번호를 붙이기 전에 결정 번호 장부를 돌려 본다 (`tools/dev/wording_lint.py`)

## 모두가 쓰는 것

Godot를 직접 부르지 말고 godot.py로 부른다(저장 폴더 격리, 시간 제한: 창 20분·헤드리스 40분, --timeout-s=N). 회귀는 run_all.py.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `tools/dev/godot.py` | 검사·측정·캡처의 Godot 실행(사용자 저장 폴더를 건드리지 않음) | Thin Godot launcher for checks, goldens, measurements and captures. | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_loc.gd`<br>`python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd -- --update` |
| `tools/dev/run_all.py` | 회귀 한 번에. --only·--quick으로 일부만 | Single regression entry point for the current working tree. | `python tools/dev/run_all.py`<br>`python tools/dev/run_all.py --quick` |
| `tools/dev/audit.py` | 기록과 약속이 어긋났는지 수를 세고 지난번과 견줌(작업 묶음을 닫을 때, 날마다 첫 일). 화면은 「점검」 | 기록과 약속이 어긋났는가를 한 장으로 센다. 회귀(run_all.py)가 통과/실패를 본다면, 이것은 수를 세고 지난번과 견준다. | `python tools/dev/audit.py`<br>`python tools/dev/audit.py --list` |
| `tools/dev/run_dev.py` | 게임을 임포트하고 띄운다 | Dev loop: import the project when needed, then run the game from the repository root. | `python tools/dev/run_dev.py -- --chapter1-start`<br>`python tools/dev/run_dev.py --resolution 1920x1080 -- --chapter1-start --chapter1-pilot --chapter1-profile-off` |
| `tools/dev/godot_ps.py` | 떠 있는 Godot 프로세스 표(어느 작업 폴더의 것인지, 몇 분 됐는지). --kill-stale은 이 저장소의 도구가 띄운 오래된 것만 종료 | List the Godot processes that are running now, and end the stale ones this repository's tools started. | `python tools/dev/godot_ps.py`<br>`python tools/dev/godot_ps.py --stale-min=60` |
| `tools/dev/disk_report.py` | 디스크 사용 표(저장소·worktree별 큰 폴더, 지워도 되는지). --clean은 지울 목록만, --apply를 줘야 재생성 가능한 캐시만 삭제(저장·HANDOVER·recheck·ref·24시간 내 사용·살아 있는 프로세스는 절대 안 지움) | Disk use of the repository and its .claude/worktrees: a fast size table, a worktree table, and a guarded clean-up of regenerable caches. | `python tools/dev/disk_report.py`<br>`python tools/dev/disk_report.py --worktrees` |
| `tools/dev/repo_lock.py` | Godot 동시 실행 좌석(기계 전체, 기본 6, MOIRA_GODOT_SLOTS)과 임포트 잠금(작업 폴더별). godot.py·run_all.py·run_dev.py가 알아서 씀. 기다린다는 한 줄이 찍히면 정상 | Lock files that keep Godot processes from tripping over each other (TECH-REVIEW-20261120 M2 and M3). |  |

## 기술 관리(tech-lead)

지시서 검수에 쓰는 검사들.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `tools/dev/run_all.py` | 검수 때 회귀 결과 확인 | Single regression entry point for the current working tree. | `python tools/dev/run_all.py`<br>`python tools/dev/run_all.py --quick` |
| `chapter1/tests/golden_core.gd` | 코어 동작이 바뀌었는지 해시로 확인 | Golden replay of the runtime core. Same seed + same input policy must give the | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd` |
| `tools/dev/check_glyphs.py` | 화면 글자가 글꼴에 다 있는지 | L3-c: every character the game can print must exist in the bundled font chain. | `python tools/dev/check_glyphs.py`<br>`python tools/dev/check_glyphs.py --verbose` |
| `tools/dev/i18n_scan.py` | 코드 안 한글 리터럴이 늘었는지(번역 틀 지키기) | Count Hangul string literals in product GDScript files and compare with a baseline. | `python tools/dev/i18n_scan.py`<br>`python tools/dev/i18n_scan.py --update` |
| `tools/dev/check_build.py` | 만든 빌드의 점검 | Checks for a finished build (T4-Q). Nothing here opens a window and nothing touches %APPDATA%/WitchMoira. | `python tools/dev/build.py --preset qa`<br>`python tools/dev/build.py --preset store --stamp S` |
| `tools/dev/build.py` | Windows 실행 파일 만들기(다른 에이전트가 쓰는 작업 트리에서는 돌리지 않음) | Build a Windows executable with Godot's export. | `python tools/dev/build.py --preset store`<br>`python tools/dev/build.py --preset qa` |

## 기획 관리(design-lead)

목표 대비 수치 판정에 쓰는 측정과 시뮬레이터.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `tools/dev/balance_sim.py` | 코어를 돌리지 않는 흐름 모델로 스킬 구성의 서열을 몇 초에 본다 | 균형 시뮬레이터 (2차판) — 코어를 돌리지 않고 스킬 구성의 힘과 적의 위협을 흐름 모델로 맞물려 본다. |  |
| `chapter1/tests/measure_combat.gd` | 실제 코어 한 판의 전투 압박 지표(약 3분) | Plays whole pilot runs on the real core and measures the combat-pressure targets of | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/measure_combat.gd -- [options]` |
| `chapter1/tests/measure_rhythm.gd` | 난이도 리듬 측정. 인수: --thirds(판을 셋으로 자른 은총 간격·쓸기·큰 적 표) --tuning=/--descent-doc=(튜닝 복사본) --policy=synergy(은총 정책) | Difficulty-rhythm meter (D11 G2). Plays whole pilot runs on the real core and only READS core state/events. | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/measure_rhythm.gd -- --seeds=11,12,13 --primaries=ember,frost,arc --out=_local/w0/rhythm.json --bin=30`<br>`python tools/dev/godot.py --headless --path . --script res://chapter1/tests/measure_rhythm.gd -- --thirds --tuning=_local/d19/v0/wd_1.json --policy=synergy --out=_local/d19/v0/x.json` |
| `tools/dev/tuning_copy.py` | 데이터 문서의 복사본에 키 몇 개만 바꿔 _local/에 쓴다(measure_rhythm --tuning=의 입력) | tuning_copy.py - a copy of a data document with a few keys changed, written under _local/ (D19 V0). | `python tools/dev/tuning_copy.py --out _local/d19/v0/w_d1.json --set hp_time_bps_per_s=90 --set champions.0.xp=300 --set xp_thresholds=[0,10,25]`<br>`python tools/dev/tuning_copy.py --src chapter1/data/descent.json --out _local/x/descent.json --set cost=[3000,5000,6000]` |
| `chapter1/tests/sim_loot.gd` | 한 판 드랍 양을 많이 굴려 목표와 대조 | Drop simulation for loot grammar v2. Rolls the treasure classes for a whole | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_loot.gd` |
| `chapter1/tests/sim_builds.gd` | 성장 선택 정책별 구성의 벌어짐 | Build-spread meter (D11 G / D12 K1 measurement policy). Plays whole runs on the real core with the pilot's movement, | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_builds.gd -- --seeds=11 --runs=5 --primaries=ember,frost,arc --policies=pilot,random,worst,narrow --out=_local/builds/now.json [--rhythm-on]` |
| `chapter1/tests/sim_progression.gd` | 영구 성장 속도 | G1 progression simulation (docs/specs/G1-permanent-growth-spec.ko.md, section 10.1). Plays whole pilot runs of the | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_progression.gd -- [options]` |
| `tools/dev/decision_ledger.py` | 결정 번호의 겹침과 다음 빈 번호 | 결정 번호 장부: docs/ 전체에서 결정 번호(N숫자, U숫자)를 모아 겹친 번호와 다음 빈 번호를 낸다. | `python tools/dev/decision_ledger.py`<br>`python tools/dev/decision_ledger.py --json --out=_local/decisions/ledger.json` |

## 전투 코어(gameplay-systems)

코어를 고친 뒤의 확인.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `chapter1/tests/golden_core.gd` | 코어를 고쳤으면 먼저. 사례 하나만(--case)도 가능 | Golden replay of the runtime core. Same seed + same input policy must give the | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd` |
| `chapter1/tests/measure_combat.gd` | 수치를 고친 뒤 전투 지표 재측정 | Plays whole pilot runs on the real core and measures the combat-pressure targets of | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/measure_combat.gd -- [options]` |
| `chapter1/tests/sim_loot.gd` | 드랍을 고친 뒤 | Drop simulation for loot grammar v2. Rolls the treasure classes for a whole | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_loot.gd` |
| `chapter1/tests/report_run_loot.gd` | 실제 코어 한 판에서 무엇이 떨어졌는지 | Plays whole pilot runs on the real core and reports what actually dropped, | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/report_run_loot.gd -- --seeds=11,12,13 --primary=chapter1.skill.frost` |
| `tools/dev/run_all.py` | 마지막 전체 회귀 | Single regression entry point for the current working tree. | `python tools/dev/run_all.py`<br>`python tools/dev/run_all.py --quick` |

## 기획 수치(content-balance)

데이터 수치 조정 뒤 재는 도구.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `tools/dev/balance_sim.py` | 값을 바꿔 보고 서열이 서는지 먼저 본다 | 균형 시뮬레이터 (2차판) — 코어를 돌리지 않고 스킬 구성의 힘과 적의 위협을 흐름 모델로 맞물려 본다. |  |
| `tools/manager/balance_lab.py` | 관리 툴의 「균형 실험실」 화면의 뒷면(시뮬레이터를 화면에서 돌림) | Balance lab backend: runs tools/dev/balance_sim.py as a subprocess and reads its --out JSON (stdlib only). |  |
| `chapter1/tests/measure_combat.gd` | 확정 전 실제 코어로 대조 | Plays whole pilot runs on the real core and measures the combat-pressure targets of | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/measure_combat.gd -- [options]` |
| `chapter1/tests/sim_loot.gd` | 드랍 수치 대조 | Drop simulation for loot grammar v2. Rolls the treasure classes for a whole | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_loot.gd` |
| `chapter1/tests/sim_builds.gd` | 구성 간 격차 | Build-spread meter (D11 G / D12 K1 measurement policy). Plays whole runs on the real core with the pilot's movement, | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_builds.gd -- --seeds=11 --runs=5 --primaries=ember,frost,arc --policies=pilot,random,worst,narrow --out=_local/builds/now.json [--rhythm-on]` |
| `tools/dev/wording_lint.py` | 새 이름·설명을 데이터에 넣기 전 낱말 검사 | 낱말 검사기: 플레이어에게 보이는 글에서 금지·제한 낱말, 이름 꼴, 이름 글자 수, 영어 용어집을 찾는다. | `python tools/dev/wording_lint.py`<br>`python tools/dev/wording_lint.py --summary` |

## 세계관·스토리(narrative-lead)

글을 새로 쓰거나 바꾸기 전과 뒤.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `tools/dev/wording_lint.py` | 금지 낱말·이름 꼴·글자 수·영어 용어집(규칙은 docs/story/wording-rules.json) | 낱말 검사기: 플레이어에게 보이는 글에서 금지·제한 낱말, 이름 꼴, 이름 글자 수, 영어 용어집을 찾는다. | `python tools/dev/wording_lint.py`<br>`python tools/dev/wording_lint.py --summary` |
| `tools/dev/decision_ledger.py` | 새 결정 번호를 붙이기 전에 다음 빈 번호와 겹침 확인 | 결정 번호 장부: docs/ 전체에서 결정 번호(N숫자, U숫자)를 모아 겹친 번호와 다음 빈 번호를 낸다. | `python tools/dev/decision_ledger.py`<br>`python tools/dev/decision_ledger.py --json --out=_local/decisions/ledger.json` |
| `tools/dev/check_glyphs.py` | 새 글자가 글꼴에 있는지 | L3-c: every character the game can print must exist in the bundled font chain. | `python tools/dev/check_glyphs.py`<br>`python tools/dev/check_glyphs.py --verbose` |

## 구조 리팩토링(refactor-architect)

동작이 그대로인지 확인.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `tools/dev/flatten_chain.py` | 상속 체인을 한 파일로 펴기 | Inline a GDScript inheritance chain into one script without changing behaviour. | `python tools/dev/flatten_chain.py chapter1/view/ui51/chapter_hud_quality51.gd chapter1/view/hud/chapter_hud.gd` |
| `chapter1/tests/hud_dump.gd` | 전후 HUD 노드 트리 덤프 비교 | Records the HUD's Control tree at fixed moments of a deterministic pilot run. | `python tools/dev/godot.py --headless --fixed-fps 60 --path . --script res://chapter1/tests/hud_dump.gd -- \` |
| `chapter1/tests/golden_core.gd` | 코어 동작 불변 확인 | Golden replay of the runtime core. Same seed + same input policy must give the | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd` |
| `tools/dev/i18n_scan.py` | 한글 리터럴 수 비교 | Count Hangul string literals in product GDScript files and compare with a baseline. | `python tools/dev/i18n_scan.py`<br>`python tools/dev/i18n_scan.py --update` |
| `tools/dev/screen_contract_check.py` | 화면 계약 검사: 픽스처가 스키마를 따르는가, 변형이 다 있는가, 화면 파일이 코어(run·사적 필드·Color 리터럴)를 읽는 수(기준선보다 늘면 실패), 글자 대비 | Screen contract checker (docs/SCREEN-DESIGN-HARNESS.ko.md 6 T-1, docs/specs/T8-screen-contract-structure-20261120.ko.md 4). | `python tools/dev/screen_contract_check.py`<br>`python tools/dev/screen_contract_check.py --dumps=<folder>` |

## 검증·성능(qa-perf)

회귀, 프레임 시간, 캡처.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `tools/dev/run_all.py` | 회귀 전체/일부 | Single regression entry point for the current working tree. | `python tools/dev/run_all.py`<br>`python tools/dev/run_all.py --quick` |
| `chapter1/tests/frame_probe.gd` | 실시간 프레임 간격 기록 | Real-time frame interval recorder for the ChapterOne scene (QA tool, no gameplay writes). | `python tools/dev/godot.py --path . --resolution 1920x1080 --script res://chapter1/tests/frame_probe.gd -- \` |
| `chapter1/tests/hud_dump.gd` | 화면 상태 덤프와 캡처 | Records the HUD's Control tree at fixed moments of a deterministic pilot run. | `python tools/dev/godot.py --headless --fixed-fps 60 --path . --script res://chapter1/tests/hud_dump.gd -- \` |
| `tools/dev/check_build.py` | 빌드 점검 | Checks for a finished build (T4-Q). Nothing here opens a window and nothing touches %APPDATA%/WitchMoira. | `python tools/dev/build.py --preset qa`<br>`python tools/dev/build.py --preset store --stamp S` |
| `tools/dev/build.py` | 빌드 만들기 | Build a Windows executable with Godot's export. | `python tools/dev/build.py --preset store`<br>`python tools/dev/build.py --preset qa` |

## HUD(ui-hud)

화면 배치를 보는 도구.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `chapter1/tests/skill_tree_preview.gd` | 코어 없이 기술 트리 화면만 띄워 캡처 | Stand-alone preview of the skill-tree panel (G1 spec section 8) on fixture data. No core, no profile. | `python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/skill_tree_preview.gd -- --shots=<dir>` |
| `chapter1/tests/hud_dump.gd` | Control 사각형 덤프(겹침·잘림 점검 재료)와 캡처 | Records the HUD's Control tree at fixed moments of a deterministic pilot run. | `python tools/dev/godot.py --headless --fixed-fps 60 --path . --script res://chapter1/tests/hud_dump.gd -- \` |
| `chapter1/tests/portrait_select_shots.gd` | 제목 화면 살아 있는 초상 캡처 | Captures the title menu's living portrait with the real input path (focus on a start button picks the witch). | `python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/portrait_select_shots.gd -- --chapter1-profile-off --chapter1-qa-ignore-focus --shots=_local/shots/portrait-select --tag=1080` |
| `chapter1/tests/scene_shot.gd` | 화면 하나를 정해진 데이터로 띄워 캡처(boon_spells = 스킬 구성의 성장 카드). 최종 확인은 실제 판 캡처 | Screen scene renderer: one named screen on fixed data, shot at the window size the process was started with, plus a | `python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720  --path . --script res://chapter1/tests/scene_shot.gd -- \`<br>`python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/scene_shot.gd -- \` |
| `tools/dev/hud_layout_check.py` | scene_shot·hud_dump의 Control 덤프에서 겹침·잘림 점검 | HUD layout check: reads Control dumps and lists layout violations. | `python tools/dev/hud_layout_check.py <dump.json> [<dump.json> ...] [--allow tools/dev/hud_layout_allow.json]` |
| `tools/dev/check_glyphs.py` | 새 글자의 글꼴 확인 | L3-c: every character the game can print must exist in the bundled font chain. | `python tools/dev/check_glyphs.py`<br>`python tools/dev/check_glyphs.py --verbose` |
| `tools/dev/i18n_scan.py` | 한글 리터럴을 번역 틀로 옮겼는지 | Count Hangul string literals in product GDScript files and compare with a baseline. | `python tools/dev/i18n_scan.py`<br>`python tools/dev/i18n_scan.py --update` |

## 이펙트(vfx-feel)

효과의 비용과 모양 확인.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `chapter1/tests/hud_dump.gd` | 정해진 순간의 캡처와 3D 노드 덤프(--scene) | Records the HUD's Control tree at fixed moments of a deterministic pilot run. | `python tools/dev/godot.py --headless --fixed-fps 60 --path . --script res://chapter1/tests/hud_dump.gd -- \` |
| `chapter1/tests/frame_probe.gd` | 효과 켜고 끈 프레임 시간 | Real-time frame interval recorder for the ChapterOne scene (QA tool, no gameplay writes). | `python tools/dev/godot.py --path . --resolution 1920x1080 --script res://chapter1/tests/frame_probe.gd -- \` |
| `tools/dev/fx_strip.py` | 효과 캡처 여러 장을 불꽃 색 중심으로 잘라 확대해 한 장의 띠로 잇기 | Contact strip of effect captures: crops every frame around its fire-coloured pixels (or a fixed box) and enlarges them. | `python tools/dev/fx_strip.py <out.png> <scale> <crop> <frame> [<frame> ...]` |
| `chapter1/tests/fx_stress_probe.gd` | 가짜 투사체 N개를 그려 보며 실제 장면의 프레임 시간 재기 | QA tool (never product code): frame times of the real ChapterOne scene while N extra fire projectiles are DRAWN. | `python tools/dev/godot.py --path . --resolution 1920x1080 --script res://chapter1/tests/fx_stress_probe.gd -- \` |
| `chapter1/tests/meteor_fx_probe.gd` | 메테오 표현에 가짜 이벤트를 넣어 한 발·8발·16발·일시정지·초기화·흔들림 끔을 확인 | QA tool (never product code): drives the meteor presentation (view/fx/meteor_fx.gd) with synthetic core events in the real | `python tools/dev/godot.py --path . --resolution 1920x1080 --script res://chapter1/tests/meteor_fx_probe.gd -- \` |
| `chapter1/tests/vat_preview.gd` | 뼈 애니메이션과 구운 군중 나란히 보기 | Side by side: the bone-animated skeleton outlaw (left) and the baked MultiMesh instance (right), same clip, same time. | `python tools/dev/godot.py --resolution 1280x720 --path . res://chapter1/tests/vat_preview.tscn -- --chapter1-profile-off --shots=_local/shots/vat-walker [--vat=_local/vat/walker] [--crowd=300]` |
| `chapter1/tests/bake_vat.gd` | 정점 애니메이션 텍스처 굽기와 검증 | Bakes the walker (skeleton outlaw) into vertex animation textures and verifies the result. | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/bake_vat.gd -- --out=_local/vat/ [--save] [--cpu] [--no-verify]` |

## 캐릭터 아트(character-artist)

원화 가공.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `tools/dev/make_living_portrait_flake.py` | 원화에서 눈송이와 고리를 잘라 살아 있는 초상용으로 | Cuts the painted snowflake and its rings out of the original for the living portrait (v4). | `python tools/dev/make_living_portrait_flake.py` |
| `chapter1/tests/portrait_select_shots.gd` | 초상이 제목 화면에서 어떻게 보이는지 캡처 | Captures the title menu's living portrait with the real input path (focus on a start button picks the witch). | `python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/portrait_select_shots.gd -- --chapter1-profile-off --chapter1-qa-ignore-focus --shots=_local/shots/portrait-select --tag=1080` |
| `tools/art/mesh_reduce.py` | 3D 1단계: 생성 도구의 고폴리 메시를 게임용(약 1만2천) 또는 크게 보일 때용(약 5만) 삼각형으로 줄이고 색·노멀을 새 UV로 굽기. 실루엣 대조 보고서(Blender) | 그림→3D 생성 도구가 준 고폴리 메시를 게임용 저폴리로 줄인다(Blender 5.3 명령줄). | `python tools/art/mesh_reduce.py --in HIGH.glb --out-glb OUT.glb --profile game [--target N] [--height 2.0] [--report r.json] [--work DIR]`<br>`python tools/art/mesh_reduce.py --in HIGH.glb --out-glb OUT.glb --profile showcase` |
| `tools/art/rig_build.py` | 3D 2단계: 뼈 없는 인간형 메시에서 뼈 24개 뼈대와 가중치 만들기(Blender) | 뼈 없는 인간형 메시 한 덩어리에서 뼈대를 세우고 가중치를 입힌다(Blender 5.3 명령줄). | `python tools/art/rig_build.py --in MESH.glb --out-blend D:/.../rigged.blend [--config my.json] [--report report.json] [--clips]` |
| `tools/art/rig_clips.py` | 3D 3단계: 동작 6개(idle·run·cast·hit·death·dodge, 60fps)를 코드로 찍어 glb로. --retarget-from으로 기존 동작 옮기기(Blender) | rig_build가 만든 뼈대에 동작 6개(idle, run, cast, hit, death, dodge)를 코드로 찍어 glb로 내보낸다(Blender 5.3 명령줄). | `python tools/art/rig_clips.py --blend RIGGED.blend --out-glb OUT.glb [--config my.json] [--report r.json] [--fps 60] [--preview DIR]`<br>`python tools/art/rig_clips.py --blend RIGGED.blend --out-glb OUT.glb --retarget-from SOURCE.glb [--retarget-map map.json]` |
| `tools/art/rig_parts.py` | 3D 4단계: 같은 뼈대에 소품 메시를 뼈에 붙여 한 glb로, 단색 텍스처(Blender) | 같은 뼈대에 별도 메시(뼈에 단단히 붙는 소품)를 묶어 한 glb로 내보낸다(Blender 5.3 명령줄). | `python tools/art/rig_parts.py --blend WITH_CLIPS.blend --parts parts.json --out-glb OUT.glb [--report r.json] [--out-blend x.blend]` |
| `tools/art/rig_check.py` | 3D 5단계: 내보낸 glb가 게임의 계약(뼈·클립·재질·삼각형·방향·크기)을 지키는지. asset_intake의 자리표 대조를 부름(Blender 필요 없음) | 내보낸 캐릭터 glb가 게임의 계약을 지키는지 검사한다(표준 라이브러리만, Blender 필요 없음). | `python tools/art/rig_check.py FILE.glb [--slot actor.hero.model] [--require-dodge] [--max-tris 15000] [--scale 1.32] [--json]` |
| `chapter1/tests/rig_game_probe.gd` | 3D 6단계: 시험 glb를 게임의 주인공 자리에 끼워 한 판을 캡처, 회피·사망 같은 동작을 강제로 틀어 캡처(창 실행). A7-0 시험 인수: --hero-look(겉모습 값 덮기), --hero-mask·--hero-crop-ticks(주인공 가면과 240x240 원 크기 자르기), --burst=틱,수(연속 캡처), --foot-log(발 미끄러짐·걸음 박자), --hero-cast-overlay=0\|1. 자르기 측정과 판 A·B는 tools/dev/shot_review.py --hero-sheet | 시험용 glb를 게임의 주인공 모델 자리에 끼워 한 판 앞부분을 돌리고, 지정한 동작(회피·사망 등)을 강제로 틀어 캡처한다. | `python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/rig_game_probe.gd -- \` |
| `tools/art/rig_common.py` | 3D 도구들이 불러 쓰는 공용 모듈(따로 돌리지 않음) | 3D 캐릭터 도구 묶음(rig_build / rig_clips / rig_parts)의 공용 모듈. 따로 돌리지 않는다. |  |
| `tools/art/motion_math.py` | 걸음 계약 계산(동작 배율·보폭·발 미끄러짐, 모델의 답). 관리 툴 캐릭터 화면과 적용·검증 도구가 부르는 공용 모듈(따로 돌리지 않음) | 걸음 계약 계산(표준 라이브러리만). 관리 툴(characters.py), 적용 도구(motion_apply.py), 검증 도구가 모두 이 식을 부른다. |  |
| `tools/art/motion_apply.py` | 캐릭터 화면에서 고른 걸음 값을 자리표(asset_slots.json)의 그 칸에 글자만 바꿔 옮김. 기본은 바뀔 줄 보기, --write로 씀, --check로 자리표와 고름이 맞는지(종료 코드) | 고름 기록(관리 툴 「캐릭터」 화면에서 저장)을 게임 자리표(chapter1/art/asset_slots.json)의 그 캐릭터 칸으로 옮긴다. | `python tools/art/motion_apply.py --pick <기록 id>`<br>`python tools/art/motion_apply.py --pick <기록 id> --write` |
| `tools/art/sheet_split.py` | 턴어라운드 시트 한 장을 정면·옆·뒤 낱장으로 나눔(그림→3D 서비스의 여러 면 입력용). 바탕과 다른 덩어리를 왼쪽부터 --names 순서로 자름, --square로 정사각 | 턴어라운드 시트 한 장을 보기별 낱장으로 나눈다(그림→3D 서비스의 여러 면 입력용). | `python tools/art/sheet_split.py <시트.png> --out <폴더> [--names front,left,back] [--pad 0.06] [--square]` |
| `tools/art/face_reproject.py` | 정면 얼굴 그림을 3D 모델(glb)의 얼굴 살갗 텍셀에만 다시 입힘(메시·UV 불변, 표지점 json으로 맞춤). 그림→3D 모델의 얼굴이 어긋났을 때 | 정면 얼굴 그림을 3D 모델(glb)의 얼굴 살갗 텍셀에만 다시 입힌다 (메시·UV·텍스처 해상도는 그대로). | `python face_reproject.py --model 모델.glb --image 정면얼굴.png --landmarks 표지점.json` |
| `chapter1/tests/hero_motion_probe.gd` | 게임 안 걸음 측정: 주인공을 직진시켜 프레임마다 클립 시각과 발끝 뼈 위치를 적음(동작 배율 실측, 디딤 미끄러짐). motion_verify.py가 부름 | Walk probe (T9 B1-b): the hero's new body, in the real game scene, while the pilot moves it. Per render frame it reads the hero's | `python tools/dev/godot.py --headless --fixed-fps 60 --path . --script res://chapter1/tests/hero_motion_probe.gd -- \` |
| `tools/art/motion_verify.py` | 화면에서 고른 걸음 값(또는 --current)이 게임 안에서 같은 배율·미끄러짐인지 견줌. hero_motion_probe.gd를 돌려 배율은 계산과 2% 안, 미끄러짐은 화면이 잰 값과 0.15 m/s 안인지 판정(계산값과는 견주지 않음). 종료 코드 0 같음 / 1 어긋남 / 2 측정 못 함 / 3 화면 값이 없어 배율만 판정. --report로 몸 보고서를 줄 수 있음 | 게임 안 걸음 측정(chapter1/tests/hero_motion_probe.gd)을 돌려 캐릭터 화면의 계산과 견준다. | `python tools/art/motion_verify.py --current`<br>`python tools/art/motion_verify.py --clip walk --rate 1.3` |

## 환경 아트(environment-artist)

3D 에셋.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `chapter1/tests/bake_vat.gd` | 걷는 적을 정점 애니메이션으로 굽기 | Bakes the walker (skeleton outlaw) into vertex animation textures and verifies the result. | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/bake_vat.gd -- --out=_local/vat/ [--save] [--cpu] [--no-verify]` |
| `chapter1/tests/vat_preview.gd` | 구운 결과를 뼈 애니메이션과 나란히 | Side by side: the bone-animated skeleton outlaw (left) and the baked MultiMesh instance (right), same clip, same time. | `python tools/dev/godot.py --resolution 1280x720 --path . res://chapter1/tests/vat_preview.tscn -- --chapter1-profile-off --shots=_local/shots/vat-walker [--vat=_local/vat/walker] [--crowd=300]` |
| `chapter1/tests/edge_shots.gd` | 맵 경계 캡처: 주인공을 걷는 땅의 가장자리 점(네 변·귀퉁이·1m 안)에 세워 찍고, 발에서 막는 것까지의 화소 거리를 json으로. --combat=<점>은 적이 모인 뒤 한 장. --at=x,y,이름으로 아무 점 | Map-edge capture tool (A10 W4, U-64). Starts a run on the real scene, holds the hero at points on the walkable edge of | `python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/edge_shots.gd -- \` |

## 에셋 제작(asset-producer)

그림 후처리.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `tools/art/make_equipment_icons.py` | 생성된 장비 아이콘을 게임 크기로 가공 | Post-process generated equipment icons (A3 spec section 9). Pillow + NumPy only, deterministic, no external models. | `python tools/art/make_equipment_icons.py [--src DIR] [--out DIR] [--pick item=rN ...] [--no-sheet]` |
| `tools/art/gen_queue.py` | 필요한 그림의 대기열(scan·status·next·run·record). 무료 Codex 길만 자동, 유료는 승인 필요 표시만. 절차는 docs/ART-QUEUE.ko.md | Picture queue: find the pictures the game will need, keep them as a list, and keep Codex making them ahead of time. | `python tools/art/gen_queue.py scan [--write]`<br>`python tools/art/gen_queue.py status [--json [FILE]]` |
| `tools/art/asset_intake.py` | 새 파일을 넣기 전에 자리표(asset_slots.json)의 계약과 대조 | 외부 에셋 가져오기 검수기(표준 라이브러리만, Python 3.10). | `python tools/art/asset_intake.py FILE.glb [--profile enemy] [--budget tools/art/asset_budget.json] [--json]`<br>`python tools/art/asset_intake.py --scan chapter1/art [--json] [--strict]` |
| `tools/art/asset_ledger.py` | 출처 원장 확인·등록. check는 자리표와 원장을 맞춰 본다 | 출처 원장 도구: chapter1/art/ASSET-LEDGER.json 을 만들고 점검한다. | `python tools/art/asset_ledger.py check`<br>`python tools/art/asset_ledger.py check --strict` |
| `tools/art/slot_paths.py` | 자리표·소리 표·곁 JSON이 가리키는 파일을 읽는 공용 모듈(다른 도구가 불러 씀, 따로 돌리지 않음) | 에셋 자리표(chapter1/art/asset_slots.json)와 소리 표(chapter1/data/audio_map.json)가 가리키는 파일을 읽는 공용 모듈. |  |
| `tools/dev/asset_usage_report.py` | 한 판에서 실제로 로드·그려진 에셋 표(hud_dump --asset-usage 결과를 합침) | Merge several `hud_dump.gd --asset-usage=` files into one asset usage table (T7-0). | `python tools/dev/asset_usage_report.py --out _local/tools/t7-0/asset-usage` |

## 소리(audio-lead · sound-designer)

소리 측정과 비교.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `tools/dev/audio_measure.py` | 소리 파일 측정(길이·피크·음량·무음·대역). --compare-s1로 기준표 대조 | Sound-file measurement (read only): length, peak, true peak, clipping, loudness, silence, attack/decay, bands, loop seam. | `python tools/dev/audio_measure.py`<br>`python tools/dev/audio_measure.py DIR_OR_FILES... --md out.md --json out.json` |
| `tools/dev/audio_audition.py` | 후보 비교 묶음(음량 맞춤, 정답표 따로) | Audition-bundle tool: level matching, blind files with a separate answer key, concatenation, m4a, zip, the P1 bundle. | `python tools/dev/audio_audition.py p1 --out C:/.../_local/audio/audition/20261117-P1 --requests _local/audio/requests`<br>`python tools/dev/audio_audition.py concat --gap 0.5 --match mmax:-23 -o out.wav a.wav b.wav ...` |
| `tools/dev/audio_mix_offline.py` | 녹음한 한 판에 지금의 재생 규칙을 적용해 WAV로 | Offline mix of a recorded run: applies today's player rules to a request log and renders a WAV. | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/report_audio_requests.gd -- --seed=11 --primary=chapter1.skill.ember --out=_local/audio/requests/req_ember.json`<br>`python tools/dev/audio_mix_offline.py _local/audio/requests/req_ember.json --best-window 10 --out _local/audio/mix/crowd_ember_10s.wav` |
| `chapter1/tests/report_audio_requests.gd` | 한 판에서 게임이 내는 소리 요청 기록(--run-spells=on --spells-pick=synergy로 켠 판의 새 이벤트 셈까지) | Audio request recorder (check script, not product code). Plays one pilot run on the real core with no view | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/report_audio_requests.gd -- --seed=11 --primary=chapter1.skill.ember --out=_local/audio/requests/req_ember.json` |
| `chapter1/tests/sfx_capture.gd` | 한 판의 틱 구간을 한 틱 한 장 JPG와 이벤트(events.json)로 뜸. 소리 후보를 실제 장면에 입히는 재료(켠 판: --run-spells=on --spells-pick=synergy) | Check tool, not product code (raised from the director's scratch script _local/director-scratch/sfx_capture.gd, AU-RS0). | `python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/sfx_capture.gd -- \` |
| `tools/dev/make_drop_sounds.py` | 허가된 원본이 없는 드랍 소리 합성 | Synthesize the loot drop cues that have no licensed source: jewelry and high-grade drops. | `python tools/dev/make_drop_sounds.py` |
| `tools/dev/audio_ledger_check.py` | 소리 출처 기록과 큐 표가 맞는지(AU-run-spells-sound의 새 큐도 이 표에 올린다) | Sound ledger check: every sound file has a ledger entry, every entry's SHA-256 matches, nothing is listed that is gone. | `python tools/dev/audio_ledger_check.py`<br>`python tools/dev/audio_ledger_check.py --dir chapter1/art/audio --ledger chapter1/art/audio/AUDIO-LEDGER.json` |

## 관리 툴(manager-tools)

이 화면과 그 뒷면.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `tools/manager/catalog.py` | 카탈로그 생성. --tools-index로 이 색인을 docs/TOOLS-INDEX.ko.md로 내보냄 | Read-only catalog of the working tree (stdlib only). Never writes, never runs the game. |  |
| `tools/manager/server.py` | 관리 툴 서버(127.0.0.1) | Loopback-only manager server: read-only catalog plus atomic management notes (stdlib only). |  |
| `tools/manager/balance_lab.py` | 균형 실험실의 뒷면 | Balance lab backend: runs tools/dev/balance_sim.py as a subprocess and reads its --out JSON (stdlib only). |  |
| `tools/manager/drafts.py` | 원화 시안 갤러리 | Character art draft gallery: reads _local/art/drafts/index.json on every request (read-only), |  |
| `tools/manager/playlog.py` | 플레이 기록 | Human playtest log: questions read from the docs, answers saved as _local/playtests/<date-time>.json. |  |
| `tools/manager/characters.py` | 「캐릭터」 화면의 뒷면(읽기 전용): 자리표의 주인공 몸, 걸음 계약, 코드 상수(BASE_SPEED·카메라), 그림·영상 자리. 화면은 character.js, 3D는 vendor/three | 「캐릭터」 화면의 서버 쪽(읽기 전용): 자리표의 주인공 몸, 걸음 계약, 코드 상수, 그림·영상의 자리를 모아 준다. |  |
| `tools/manager/picks.py` | 사용자의 고름(이걸로/아님/보류)을 읽는다. 세션을 열면 list --open 으로 확인하고, 반영한 뒤 close <id> --ref 로 닫는다. 기록을 더하는 명령은 없다(화면에서만) | 사용자의 고름(이걸로/아님/보류/말만)을 tools/manager/local-picks.json 에 모으고, 디렉터가 읽을 수 있게 한다. | `python tools/manager/picks.py list [--open] [--subject frost/] [--json]`<br>`python tools/manager/picks.py close <id> --ref "<커밋이나 지시서>"` |
| `tools/manager/ui_shot.py` | 관리 툴 화면을 헤드리스 Edge로 열어 PNG 캡처(--out, _local/ 아래만)와 화면이 내놓은 data-* 수치(--dump-dom)를 얻는다. --offline으로 바깥 연결을 막고 다시 확인 | 관리 툴 화면을 헤드리스 Edge로 열어 PNG 캡처와 화면이 내놓은 수치(data-*)를 얻는다. 표준 라이브러리만. | `python tools/manager/ui_shot.py --port 8791 --hash "#character/frost?a=run&b=walk@1.3&v=5.8&cam=19.5" --size 1440x900` |
| `tools/manager/tools_index.py` | 이 색인 | 도구 색인: tools/dev, tools/art, tools/manager, chapter1/tests 의 측정·검사 도구를 파일 머리 주석에서 읽어 역할별로 보여 준다. |  |

## Codex 운용(codex-operator)

그림 생성 뒤의 정리.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `tools/art/gen_queue.py` | 대기열에서 다음 K건의 작업 지시문(next)을 받고 run으로 생성, record로 검수 시트·갤러리 묶음 | Picture queue: find the pictures the game will need, keep them as a list, and keep Codex making them ahead of time. | `python tools/art/gen_queue.py scan [--write]`<br>`python tools/art/gen_queue.py status [--json [FILE]]` |
| `tools/art/make_equipment_icons.py` | 생성된 아이콘 후처리 | Post-process generated equipment icons (A3 spec section 9). Pillow + NumPy only, deterministic, no external models. | `python tools/art/make_equipment_icons.py [--src DIR] [--out DIR] [--pick item=rN ...] [--no-sheet]` |
| `tools/manager/drafts.py` | 갤러리 등록 상태 읽기 | Character art draft gallery: reads _local/art/drafts/index.json on every request (read-only), |  |

## 아직 역할에 묶지 않은 도구

| 도구 | 머리 주석 | 예시 명령 |
|---|---|---|
| `chapter1/tests/asset_usage_probe.gd` | T7-0: which files under chapter1/art/ (and the living-portrait flake pictures) a play-through really loads and draws. |  |
| `chapter1/tests/burst_capture.gd` | A6-0: burst screenshots after core events. Used by hud_dump.gd (--burst=<name,...> --burst-frames=<n>, needs --shots=<dir>). |  |
| `chapter1/tests/choice_frame_probe.gd` | Real-time frame interval while the growth-choice window is open (QA tool, no gameplay writes). The built-in pilot plays to the first choice, is parked, | `python tools/dev/godot.py --resolution 1920x1080 --path . --script res://chapter1/tests/choice_frame_probe.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.frost` |
| `chapter1/tests/core_text_probe.gd` | The text checks of test_core_text.gd as an observer. One object can watch a run that something else is stepping |  |
| `chapter1/tests/descent_fx_shots.gd` | QA tool (never product code): pictures and frame times of the descent's three sweeps (D24 12.2), on the real ChapterOne scene. | `python tools/dev/godot.py --timeout-s=900 --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/descent_fx_shots.gd -- --chapter1-start --chapter1-pilot --chapter1-trial=descent --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --chapter1-descent-cost=1000 --chapter1-primary=chapter1.skill.ember --element=ember --enemies=70 --shots=_local/shots/d24-fx --tag=ember` |
| `chapter1/tests/descent_policy.gd` | When a bot uses the descent (D15 A6.5). MEASUREMENT ONLY: chapter_pilot.gd is not touched (the golden replay plays it as it is), |  |
| `chapter1/tests/elite_sites_shot.gd` | Look study for guarded elites and the shrine/chest they guard (docs/reviews/ELITE-AND-GUARDED-SITES-LOOK-20261120.ko.md). | `python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/elite_sites_shot.gd -- \` |
| `chapter1/tests/equiv_dump.gd` | Equivalence dump for tools/dev/equiv.py (QA tool, reads presentation state only, writes no game state). | `python tools/dev/godot.py --headless --fixed-fps 60 --path <root> --script res://chapter1/tests/equiv_dump.gd -- --chapter1-pilot` |
| `chapter1/tests/layout_dump.gd` | Control-tree dump shared by hud_dump.gd (--dump-extra) and scene_shot.gd, read by tools/dev/hud_layout_check.py. |  |
| `chapter1/tests/make_profile_legacy_fixtures.gd` | One-shot generator (T5-S0). Run it ONCE with the schema-3 code, before schema 4 lands: | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/make_profile_legacy_fixtures.gd` |
| `chapter1/tests/make_profile_v4_fixtures.gd` | One-shot generator (T6-S0). Run it ONCE with the schema-4 code, before schema 5 lands: | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/make_profile_v4_fixtures.gd` |
| `chapter1/tests/modal_fit_probe.gd` | Real-run probe for the two in-run windows: the equipment compare ("장비와 전투 선택") and the growth choice ("성장 선택"). | `python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/modal_fit_probe.gd -- \` |
| `chapter1/tests/modal_input_check.gd` | Input check on the real core for the two in-run windows, with real GUI routing (events pushed into the window): | `python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/modal_input_check.gd -- \` |
| `chapter1/tests/model_swap.gd` | Puts a trial glb in the hero model's place without touching a product file (Resource.take_over_path on the path the game |  |
| `chapter1/tests/pause_input_check.gd` | Input check of the pause window and its confirm window (A10 W2), on the real core with real GUI routing (events pushed into the window), keyboard and mouse: | `python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/pause_input_check.gd -- \` |
| `chapter1/tests/perf_probe.gd` | Frame and tick timing probe for exported builds and the editor (QA tool, never product code). |  |
| `chapter1/tests/perf_probe_mark.gd` | QA-only timestamp node for perf_probe.gd. Records the time its _process ran. |  |
| `chapter1/tests/play_with_model.gd` | The user plays the game with a trial glb in the hero's place (no pilot, no capture). Product files are untouched. | `python tools/dev/godot.py --resolution 1920x1080 --path . --script res://chapter1/tests/play_with_model.gd -- \` |
| `chapter1/tests/profile_legacy_snapshot.gd` | Shared by make_profile_legacy_fixtures.gd (once) and test_profile_legacy_fixtures.gd (every run). |  |
| `chapter1/tests/profile_v4_snapshot.gd` | Shared by make_profile_v4_fixtures.gd (once) and test_profile_v4_fixtures.gd (every run). |  |
| `chapter1/tests/proposal_shot.gd` | Proposal renderer for the screen design harness (step 3): one proposal scene fed by contract fixtures | `python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/proposal_shot.gd -- \` |
| `chapter1/tests/proposal_smoke.gd` | Headless smoke test of the screen proposals: builds every fixture, plays the intro, moves the focus, confirms, re-pulls, and | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/proposal_smoke.gd -- --proposals=growth_choice/e_hand` |
| `chapter1/tests/record_input_check.gd` | Input check for the battle record window, with real GUI routing (events pushed into the window): | `python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/record_input_check.gd -- \` |
| `chapter1/tests/record_run_shot.gd` | The battle record on a REAL run: the app plays a whole run with the built-in pilot (the core is stepped by calling the | `python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/record_run_shot.gd -- \` |
| `chapter1/tests/sim_power.gd` | Power bench ("short proving ground", D12 P3 / P9): measures what a FIXED in-run spell build really does on the real core. |  |
| `chapter1/tests/spells_pick.gd` | Check tool, not product code. How a tool turns the in-run spell composition ON and how it picks growth cards for it |  |
| `chapter1/tests/trial_state_probe.gd` | Prints what the app's `--chapter1-trial=` handling (chapter_one.gd `_apply_trial`) did to the core, for the arguments this process got. |  |
| `tools/art/albedo_fix.py` | 구운 몸 그림(albedo)의 상자 구간 안을 피부색으로 매끈하게 메운다. numpy만 쓴다. base_build.py가 부른다. |  |
| `tools/art/arm_restore.py` | 맞춤(fit)이 납작하게 누른 팔 단면을 원본 기본 몸의 굵기로 되돌린다. numpy만 쓴다(Blender 없음). base_build.py가 부른다. |  |
| `tools/art/arm_section.py` | 팔 단면 재기(Blender 5.3). 위팔·아래팔·손목 근처의 단면(뼈 축에 수직인 평면에 정점을 내려 2차원 주성분으로 긴 폭·짧은 폭, 볼록 껍질 넓이)을 쉬는 자세와 지정한 동작 프레임에서 잰다. | `python tools/art/arm_section.py --blend X.blend [--gltf 원본.gltf] [--pose run:10] [--side l] [--json out.json]` |
| `tools/art/arm_shade.py` | 구운 몸 그림(albedo)의 팔 구간에 원통 음영을 넣는다. numpy만 쓴다(Blender 없음). base_build.py가 부른다. |  |
| `tools/art/base_bake.py` | 기본 몸 메시에 우리 면별 그림을 입힌다(numpy/scipy/PIL, Blender 필요 없음). 입력은 base_dump.py의 npz, 설정 json, 실루엣 방식 모델(목표 형상)이다. | `python tools/art/base_bake.py --config tools/art/base_configs/frost.json --dump dump.npz --out-dir DIR` |
| `tools/art/base_build.py` | 맞춘 기본 몸 + 구운 그림 + 부품(치마, 머리) + 사람 동작을 한 개의 리깅된 glb로 묶는다(Blender 5.3). base_dump -> base_bake 다음 걸음. | `python tools/art/base_build.py --config tools/art/base_configs/frost_build.json --out-blend X.blend --out-glb Y.glb` |
| `tools/art/base_dump.py` | 기본 몸을 쉬는 자세(T자)와 A자세 두 벌 좌표로 덤프한다(Blender 5.3). 그림 투영은 A자세에서 하고(원화가 A자세), 뼈대·동작은 T자 쉬는 자세 그대로 쓴다. | `python tools/art/base_dump.py --body body.gltf --out dump.npz [--arm-angle 38] [--mesh Superhero_Female]` |
| `tools/art/base_prep.py` | 기본 몸(Quaternius Universal Base Characters 같은 사람 몸 glTF)을 열어 점검하고, 같은 뼈대의 동작 묶음(UAL glb)의 동작을 붙여 .blend로 저장한다(Blender 5.3). | `python tools/art/base_prep.py --body body.gltf --actions ual.glb --out-blend body_ual.blend --report report.json` |
| `tools/art/char_blender.py` | char_from_sheets의 Blender 쪽: mesh.npz + 텍스처 -> 메시 한 덩어리 glb(뼈 없음). rig_build가 이어 받는다. | `python tools/art/char_blender.py --npz mesh.npz --albedo albedo.png --out-glb mesh.glb [--name frost] [--blend out.blend]` |
| `tools/art/char_board.py` | 세 마녀를 나란히 놓은 판과 잰 값(Blender 렌더 기준, Blender 필요 없음). | `python tools/art/char_board.py --out DIR --names ember,frost,storm` |
| `tools/art/char_from_sheets.py` | 그림 면별 시트(정면·측면·후면 + 3/4 + 머리 클로즈업) -> 게임용 리깅된 주인공 glb. Blender와 numpy/scipy/PIL만 쓴다(내려받기·외부 호출 0). | `python tools/art/char_from_sheets.py --config tools/art/char_configs/frost.json --work D:/Project/witch-moira-work/char3d-blender-only/v2/frost` |
| `tools/art/char_geom.py` | char_from_sheets의 기하 부분(numpy만, Blender 없이 돈다). |  |
| `tools/art/char_limbs_sheet.py` | 달리기 앞뒤 판: char_render game --seq 대신 프레임별 렌더(cmp.sh 형식 game_run_<f>_<이름>_<카메라>_<f>.png)를 모아 한 장으로 붙인다(PIL만). | `python tools/art/char_limbs_sheet.py --dir DIR --names before,after,lean03 --frames 0,5,10,... --out sheet.png` |
| `tools/art/char_montage.py` | 그림 여러 장을 한 장에 격자로 붙인다(원본 그림과 렌더 나란히 보기용). Blender 필요 없음. | `python tools/art/char_montage.py --out sheet.png --height 640 --row front.png,r/front.png,... --row 3q.png,...` |
| `tools/art/char_motion_sheets.py` | A7-2 동작 시트: 마녀마다 final.glb의 새 동작을 정면·측면 프레임 띠로 렌더하고(char_render poses) 한 장씩 붙인다(Blender 필요, 한 번에 하나씩 돈다). | `python tools/art/char_motion_sheets.py --work D:/Project/witch-moira-work/char3d/a7 --out _local/art/a7/A7-2 [--names ember,frost,storm]` |
| `tools/art/char_motion_video.py` | 동작 미리보기 영상: 마디(segment)를 이어 붙여 mp4 하나로 만든다(Blender + ffmpeg 필요, 한 번에 하나). | `python tools/art/char_motion_video.py --work DIR --out x.mp4 --mult 3` |
| `tools/art/char_paint.py` | 구운 텍스처(atlas) 위에 마녀별 원소 자리를 그리고, 같은 UV의 발광 가면 텍스처를 만든다(numpy + PIL만, Blender 없이 돈다). |  |
| `tools/art/char_render.py` | char_from_sheets 결과를 같은 조건으로 렌더한다(Blender 작업대 엔진, 평면 조명 + 텍스처 색. 게임 화면이 아니다). | `python tools/art/char_render.py views --model final.glb --views views.json --out DIR [--tag v2]` |
| `tools/art/char_sharpness.py` | 선명도 앞뒤 판: 같은 각도·같은 크기로 전신, 상체 확대, 머리 확대를 렌더해 모델 여러 개를 가로로 나란히 놓는다(Blender 필요, 평면 조명 작업대 렌더). | `python tools/art/char_sharpness.py --out sheet.png --work DIR --model before=a.glb --model after=b.glb [--model 4k=c.glb] [--az 0]` |
| `tools/art/gallery.py` | Draft gallery index tool (replaces organize.py / register_*.py / reg_*.py / setpick*.py). Works on | `python tools/art/gallery.py lint  [--check-manager] [--json OUT]`<br>`python tools/art/gallery.py add` |
| `tools/art/gen.py` | Codex image-generation batch runner (replaces the per-batch batch_*.py / run_*.py / revise.py copies). | `python tools/art/gen.py CONFIG.json`<br>`python tools/art/gen.py CONFIG.json --only a-1 a-2` |
| `tools/art/gen3d_ingame.py` | gen3d 모델을 게임 화면(rig_game_probe.gd)에 끼워 캡처하고 화소 잘림(hero_burn)을 잰다. 제품 파일은 바꾸지 않는다. 창이 필요하다. | `python tools/art/gen3d_ingame.py --glb final.glb --look look.json --out _local/art/gen3d/shots/NAME [--cam 14\|19.5] [--ticks 300,330,360] [--primary frost]`<br>`python tools/art/gen3d_ingame.py --glb final.glb --look look.json --out DIR --force-clip run --force-times 0,0.1,... [--cam 14]` |
| `tools/art/gen3d_inspect.py` | 이미지→3D 생성 모델(glb)을 게임용으로 만들기 전에 살펴본다(Blender 5.3 명령줄). 읽기 전용. | `python tools/art/gen3d_inspect.py --in MODEL.glb [--report r.json] [--dump-tex DIR]` |
| `tools/art/gen3d_mixamo_blender.py` | Blender 안에서 도는 몸통 일(gen3d_mixamo_pack.py가 부른다). 직접 부르지 않는다. |  |
| `tools/art/gen3d_mixamo_pack.py` | Mixamo 뼈대 몸 + 동작 FBX들 -> 클립 이름이 논리 이름인 glb 한 개(번개·화염에도 같은 설정 꼴로 되풀이한다). | `python tools/art/gen3d_mixamo_pack.py tools/art/gen3d_mixamo_configs/frost.json [--out chapter1/art/actors/hero/frost/model.glb]` |
| `tools/art/gen3d_prepare.py` | 이미지→3D 생성 모델(수십만 삼각형, 갈가리 찢긴 UV)을 게임용 저폴리로 줄이고 질감을 새로 굽는다(Blender 5.3 명령줄). | `python tools/art/gen3d_prepare.py --in HIGH.glb --out-glb OUT.glb --work DIR [--target 15000] [--height 1.681] [--tex 2048]` |
| `tools/art/gen3d_rig.py` | gen3d_prepare가 만든 저폴리 glb에 뼈대와 가중치를 입히고, 뼈 자리를 메시 위에 그려 확인한다(Blender 5.3 명령줄). | `python tools/art/gen3d_rig.py --in low.glb --out-blend rigged.blend --joints joints_frost.json --overlay DIR [--report r.json]`<br>`python tools/art/gen3d_rig.py --in low.glb --joints j.json --overlay DIR --overlay-only` |
| `tools/art/gen3d_sheet.py` | gen3d_ingame.py가 저장한 강제 동작 캡처(<동작>_NN_tTTT.png, 1920x1080)를 주인공 둘레로 잘라 2배 키워 한 장 판으로 잇는다(PIL만). | `python tools/art/gen3d_sheet.py --out sheet.png --box 300 --xy 935,455 --cols 4 --tile DIR:동작 --tile DIR:동작 ...` |
| `tools/art/gen3d_video.py` | 프레임 PNG 묶음을 이어 붙여 구간(6초 넘게)으로 만들고 한 mp4로 잇는다(ffmpeg 필요). 한 주기 프레임을 되풀이해 길이를 채운다. | `python tools/art/gen3d_video.py --out out.mp4 --seg "이름\|fps\|최소초\|패턴1[;패턴2;...]" [--seg ...] [--height 540]` |
| `tools/art/gen3d_views.py` | glb 몇 개를 같은 각도·같은 빛으로 렌더해 한 장 판으로 묶는다(Blender 5.3 Eevee). 줄이기 전후 비교, 뼈대 입힌 모델의 자세 확인에 쓴다. | `python tools/art/gen3d_views.py --model A.glb --label 줄이기전 --model B.glb --label 줄인뒤 --views front,q,side,back,face,hand,legs --out out.png [--size 420]` |
| `tools/art/hero_burn.py` | 게임 안 캡처에서 주인공 영역의 밝기 잘림을 잰다(PIL·numpy). rig_game_probe.gd --hero-mask --hero-crop-ticks 의 crop_tNNNN.png + crop_tNNNN.mask.png 가 입력이다. | `python tools/art/hero_burn.py <캡처 폴더> [--out burn.json]` |
| `tools/art/limb_audit.py` | 팔다리 점검(Blender 안): 키 대비 비율, 관절(팔꿈치·무릎)에서 가중치가 섞이는 폭, 팔다리 굵기를 잰다. 보고서 JSON과 표를 낸다. | `python tools/art/limb_audit.py --blend rigged.blend --out audit.json [--side l]` |
| `tools/art/limb_stick.py` | 원본 동작과 우리 뼈대를 막대 그림으로 같은 프레임에 나란히 놓는다(PIL만, Blender 필요 없음). rig_mocap의 `dump` 결과를 읽는다. | `python tools/art/limb_stick.py --dump run_dump.json --out sticks.png [--frames 0,5,10,...] [--src-scale 1.216]` |
| `tools/art/mixamo_inspect.py` | Mixamo FBX 동작을 열어 살핀다(Blender 5.3): 길이, 프레임 수, 원본 프레임률 추정, 엉덩이가 앞으로 나아가는지(제자리 여부), 반복 이음 오차, 뼈 이름, 손 뻗음 최댓값 시각. | `python tools/art/mixamo_inspect.py --dir DIR --out report.json [--files "Running.fbx,Idle.fbx"] [--src-fps 30]` |
| `tools/art/part_shapes.py` | rig_parts.py가 쓰는 부품 모양 생성기(numpy만, Blender 없이 검사된다). |  |
| `tools/art/part_textures.py` | rig_parts 부품용 작은 무늬 텍스처(numpy만, Blender 없이 검사된다). 부품이 색 한 덩어리로 보이지 않게 결·주름·금속 면을 넣는다. |  |
| `tools/art/portrait_anchor_table.py` | Eye line / head top / feet of the three witches in one table, and how far they drift when placed side by side. | `python tools/art/portrait_anchor_table.py [--heights 400,800] [--out DIR] [--slots JSON]`<br>`python tools/art/portrait_anchor_table.py --selftest` |
| `tools/art/portrait_derive.py` | Derive per-slot crops of one witch illustration (A6 section 8.7). Pillow + NumPy only, deterministic, no models. | `python tools/art/portrait_derive.py --witch ember [--slots tools/art/portrait_slots.json] [--out DIR] [--only a,b]`<br>`python tools/art/portrait_derive.py --all` |
| `tools/art/portrait_motion_table.py` | Living-portrait motion numbers as pixel displacements (A6 8.7 / TOOLS-REVIEW 2). Reads, never edits, the | `python tools/art/portrait_motion_table.py [--heights 200,400,800] [--zoom 1.0] [--motion-scale 1.0] [--deep]`<br>`python tools/art/portrait_motion_table.py --selftest` |
| `tools/art/prompt_lint.py` | Check attempt prompts against the direction sheet (지시서) and the wording rules. Read-only. | `python tools/art/prompt_lint.py CONFIG.json [--dir DIR] [--only name ...]`<br>`python tools/art/prompt_lint.py --scan DIR` |
| `tools/art/review_sheet.py` | Standard review sheet for generated attempts (replaces sheet_*.py / mkover*.py copies). Read-only on the sources. | `python tools/art/review_sheet.py --items cinder_staff=equipment_icon/cinder_staff-r2.png linen_robe=... [--prev cinder_staff=equipment_icon/cinder_staff-r1.png]`<br>`python tools/art/review_sheet.py --list ROWS.json [--name sheet-name] [--kind icon\|image] [--out FILE.jpg]` |
| `tools/art/rig_mocap.py` | 사람 동작(다른 뼈대의 glb 동작)을 우리 24뼈 뼈대로 옮긴다. rig_clips.py가 부른다(Blender 5.3 안에서). 순수 계산 부분(디딤 구간 찾기, 디딤 고정)은 Blender 없이 검사된다. |  |
| `tools/dev/audio_recheck_20261120.py` | Builds the 2026-11-20 recheck bundle (fire comparison again under one rule set + running-current lightning candidates). | `python tools/dev/make_lightning_candidates.py --out _local/audio/lightning-cands-20261120`<br>`python tools/dev/audio_recheck_20261120.py --out C:/Project/witch-moira/_local/sfx/recheck-20261120` |
| `tools/dev/audio_scene_audition.py` | Scene audition: lay candidate sounds under captured game footage, one video per candidate, plus an answer key and measurements. | `python tools/dev/audio_scene_audition.py CAPTURE_DIR --requests REQ.json --candidates CANDS.json --out _local/audio/audition/20261119-scene`<br>`python tools/dev/audio_scene_audition.py _local/sfx/ember-a --requests _local/sfx/req_ember.json --candidates cands.json --out OUT --open-labels --no-video` |
| `tools/dev/balance_search.py` | balance_search.py — 균형 시뮬레이터 위의 값 탐색(모델의 답이지 게임의 답이 아니다. 재미는 평가하지 않는다). | `python tools/dev/balance_search.py --stage power --plan A --rounds 3 --out _local/balsim2/s1A`<br>`python tools/dev/balance_search.py --stage threat --init _local/balsim2/s1A.json --out _local/balsim2/s2A` |
| `tools/dev/equiv.py` | Behaviour-preservation check for refactors: run a base commit and the working folder the same way and compare what they dump. | `python tools/dev/equiv.py`<br>`python tools/dev/equiv.py --base f36b0a7 --primary frost,ember,arc --until 2400` |
| `tools/dev/godot_guard.py` | Time limit and process-tree kill for Godot child processes (used by godot.py and run_all.py). |  |
| `tools/dev/hero_look_run.py` | 주인공 겉모습 값(look)을 게임 조명에서 맞춰 보는 실행: 마녀 여러 명을 같은 장면 조건(시드 11, 틱 600·1500·2400)으로 찍고 잰 값과 판 A·B를 낸다. | `python tools/dev/hero_look_run.py --out=_local/art/a7/A7-look/run1 --res=1920x1080 \` |
| `tools/dev/isolated_env.py` | Environment for Godot child processes that must not touch the user folder. |  |
| `tools/dev/judge_targets.py` | 목표 판정표: tools/dev/targets.json 과 측정 JSON 여러 개를 맞대어 통과·미달·못 잼·미평가를 낸다. | `python tools/dev/judge_targets.py --out-md _local/tools/judge/table.md --out-json _local/tools/judge/table.json \`<br>`python tools/dev/judge_targets.py --check-constants --out-md _local/tools/judge/constants.md` |
| `tools/dev/make_lightning_candidates.py` | Lightning (running current) cast sound candidates for the scene audition. Candidates only: nothing here goes into the game. | `python tools/dev/make_lightning_candidates.py --out _local/audio/lightning-cands-20261120`<br>`python tools/dev/make_lightning_candidates.py --out ... --sources D:/witch-moira-audio-sources` |
| `tools/dev/move_bundle.py` | Bundle what lives outside git into one zip for moving to another PC. | `python tools/dev/move_bundle.py --out D:/witch-moira-move-YYYYMMDD.zip`<br>`python tools/dev/move_bundle.py --out D:/witch-moira-move-YYYYMMDD.zip --update` |
| `tools/dev/perf_ab.py` | Performance before/after measurement: alternate variants, watch foreign Godot processes, print one fixed table set. | `python tools/dev/perf_ab.py run  PLAN.json --out _local/perf/<date>-<name>`<br>`python tools/dev/perf_ab.py run  PLAN.json --out ... --dry-run` |
| `tools/dev/proposal_batch.py` | Morning capture of the screen proposals in one go (docs/SCREEN-DESIGN-HARNESS.ko.md 6 T-2/T-3/T-5; it replaces the | `python tools/dev/proposal_batch.py --dry-run`<br>`python tools/dev/proposal_batch.py` |
| `tools/dev/refactor_map.py` | 참조 지도: 구조 리팩토링용 읽기 전용 정적 도구. | `python tools/dev/refactor_map.py [--out=_local/refactor-map/]`<br>`python tools/dev/refactor_map.py --rename-check <옛 경로> <새 경로>` |
| `tools/dev/shot_review.py` | 캡처 전후 비교와 화면 측정 (이미 찍힌 그림만 본다. Godot를 돌리지 않는다). |  |
| `tools/dev/sim_economy.py` | 경제·성장 시뮬레이터 — 판과 판 사이의 흐름(영구 경험치·레벨·스킬 포인트·트리·재·장비·상점·퀘스트·균열 깊이)을 계산하는 모델. | `python tools/dev/sim_economy.py`<br>`python tools/dev/sim_economy.py --preset now --runs 30` |
| `tools/dev/sim_grid.py` | sim_grid.py - 시험장(chapter1/tests/sim_power.gd) 유입률 칸을 격자로 돌리고 "같은 점수 견줌" 표를 낸다. | `python tools/dev/sim_grid.py list`<br>`python tools/dev/sim_grid.py run  <exp> [--out DIR] [--jobs 2] [--seeds 11,12,13] [--witches frost,ember,arc] [--dry] [--force]` |
| `tools/dev/snapshot_diff.py` | Compare two snapshot dumps field by field. | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd -- --case=11:chapter1.skill.frost --dump-at=1800 --dump-out=_local/diff/a.json`<br>`python tools/dev/snapshot_diff.py _local/diff/a.json _local/diff/b.json [--limit 200]` |
| `tools/dev/video_motion.py` | 녹화 영상의 화면 흐름(카메라가 주인공을 따라가므로 = 주인공의 이동 속도)을 프레임마다 잰다. |  |
| `tools/dev/video_strip.py` | 녹화 영상의 구간을 원래 프레임률로 뽑아 잘라 확대하고, 프레임 번호를 붙여 가로 띠(판)로 이어 붙인다. | `python tools/dev/video_strip.py _local/ref/sacrata/yt/sacrata-yt-0-21m.mp4 --start 342 --dur 2` |
| `tools/manager/audit_view.py` | 점검 화면의 뒷면: 가장 최근 audit 결과를 읽고(읽기 전용), 다시 돌리기는 audit.py 를 하위 프로세스로 부른다. |  |

chapter1/tests/test_*.gd 28개는 회귀 검사라 목록에서 뺐습니다. python tools/dev/run_all.py 가 돌립니다.
