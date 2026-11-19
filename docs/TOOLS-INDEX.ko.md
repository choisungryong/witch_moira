# 도구 색인 (TOOLS-INDEX)

`python tools/manager/catalog.py --tools-index`가 만든 파일이다. 손으로 고치지 않는다. 역할별 묶음은 `tools/manager/tools_index.json`에서 고친다.

설명과 예시 명령은 파일 머리 주석에서 그대로 뽑은 글이고, 역할 묶음은 사람이 적은 것입니다. 이 색인이 도구를 돌려 보거나 쓰임새를 잰 것이 아닙니다.

생성: 2026-11-20 03:13:40 · 도구 84개

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
| `tools/dev/godot_ps.py` | 떠 있는 Godot 프로세스 표(어느 작업 폴더의 것인지, 몇 분 됐는지). --kill-stale은 이 저장소의 도구가 띄운 오래된 것만 종료 | List the Godot processes that are running now, and end the stale ones this repository's tools started. | `python tools/dev/godot_ps.py`<br>`python tools/dev/godot_ps.py --stale-min=60 --kill-stale --dry-run` |
| `tools/dev/repo_lock.py` | Godot 동시 실행 좌석(기계 전체, 기본 6, MOIRA_GODOT_SLOTS)과 임포트 잠금(작업 폴더별). godot.py·run_all.py·run_dev.py가 알아서 씀. 기다린다는 한 줄이 찍히면 정상 | Lock files that keep Godot processes from tripping over each other (TECH-REVIEW-20261120 M2 and M3). |  |

## 기술 관리(tech-lead)

지시서 검수에 쓰는 검사들.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `tools/dev/run_all.py` | 검수 때 회귀 결과 확인 | Single regression entry point for the current working tree. | `python tools/dev/run_all.py`<br>`python tools/dev/run_all.py --quick` |
| `chapter1/tests/golden_core.gd` | 코어 동작이 바뀌었는지 해시로 확인 | Golden replay of the runtime core. Same seed + same input policy must give the | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd` |
| `tools/dev/check_glyphs.py` | 화면 글자가 글꼴에 다 있는지 | L3-c: every character the game can print must exist in the bundled font chain. | `python tools/dev/check_glyphs.py`<br>`python tools/dev/check_glyphs.py --verbose` |
| `tools/dev/i18n_scan.py` | 코드 안 한글 리터럴이 늘었는지(번역 틀 지키기) | Count Hangul string literals in product GDScript files and compare with a baseline. | `python tools/dev/i18n_scan.py`<br>`python tools/dev/i18n_scan.py --update` |
| `tools/dev/screen_contract_check.py` | 화면 계약 검사: 픽스처가 스키마를 따르는가, 변형이 다 있는가, 화면 파일이 코어(run·사적 필드·Color 리터럴)를 읽는 수(기준선보다 늘면 실패), 글자 대비 | Screen contract checker (docs/SCREEN-DESIGN-HARNESS.ko.md 6 T-1, docs/specs/T8-screen-contract-structure-20261120.ko.md 4). | `python tools/dev/screen_contract_check.py`<br>`python tools/dev/screen_contract_check.py --dumps=<folder>` |
| `tools/dev/check_build.py` | 만든 빌드의 점검 | Checks for a finished build (T4-Q). Nothing here opens a window and nothing touches %APPDATA%/WitchMoira. | `python tools/dev/build.py --preset qa`<br>`python tools/dev/build.py --preset store --stamp S` |
| `tools/dev/build.py` | Windows 실행 파일 만들기(다른 에이전트가 쓰는 작업 트리에서는 돌리지 않음) | Build a Windows executable with Godot's export. | `python tools/dev/build.py --preset store`<br>`python tools/dev/build.py --preset qa` |

## 기획 관리(design-lead)

목표 대비 수치 판정에 쓰는 측정과 시뮬레이터.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `tools/dev/balance_sim.py` | 코어를 돌리지 않는 흐름 모델로 스킬 구성의 서열을 몇 초에 본다 | 균형 시뮬레이터 (2차판) — 코어를 돌리지 않고 스킬 구성의 힘과 적의 위협을 흐름 모델로 맞물려 본다. |  |
| `chapter1/tests/measure_combat.gd` | 실제 코어 한 판의 전투 압박 지표(약 3분) | Plays whole pilot runs on the real core and measures the combat-pressure targets of | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/measure_combat.gd -- [options]` |
| `chapter1/tests/measure_rhythm.gd` | 난이도 리듬 측정 | Difficulty-rhythm meter (D11 G2). Plays whole pilot runs on the real core and only READS core state/events. | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/measure_rhythm.gd -- --seeds=11,12,13 --primaries=ember,frost,arc --out=_local/w0/rhythm.json --bin=30` |
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
| `chapter1/tests/vat_preview.gd` | 뼈 애니메이션과 구운 군중 나란히 보기 | Side by side: the bone-animated skeleton outlaw (left) and the baked MultiMesh instance (right), same clip, same time. | `python tools/dev/godot.py --resolution 1280x720 --path . res://chapter1/tests/vat_preview.tscn -- --chapter1-profile-off --shots=_local/shots/vat-walker [--vat=_local/vat/walker] [--crowd=300]` |
| `chapter1/tests/bake_vat.gd` | 정점 애니메이션 텍스처 굽기와 검증 | Bakes the walker (skeleton outlaw) into vertex animation textures and verifies the result. | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/bake_vat.gd -- --out=_local/vat/ [--save] [--cpu] [--no-verify]` |

## 캐릭터 아트(character-artist)

원화 가공.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `tools/dev/make_living_portrait_flake.py` | 원화에서 눈송이와 고리를 잘라 살아 있는 초상용으로 | Cuts the painted snowflake and its rings out of the original for the living portrait (v4). | `python tools/dev/make_living_portrait_flake.py` |
| `chapter1/tests/portrait_select_shots.gd` | 초상이 제목 화면에서 어떻게 보이는지 캡처 | Captures the title menu's living portrait with the real input path (focus on a start button picks the witch). | `python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/portrait_select_shots.gd -- --chapter1-profile-off --chapter1-qa-ignore-focus --shots=_local/shots/portrait-select --tag=1080` |

## 환경 아트(environment-artist)

3D 에셋.

| 도구 | 언제 쓰나 | 머리 주석 | 예시 명령 |
|---|---|---|---|
| `chapter1/tests/bake_vat.gd` | 걷는 적을 정점 애니메이션으로 굽기 | Bakes the walker (skeleton outlaw) into vertex animation textures and verifies the result. | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/bake_vat.gd -- --out=_local/vat/ [--save] [--cpu] [--no-verify]` |
| `chapter1/tests/vat_preview.gd` | 구운 결과를 뼈 애니메이션과 나란히 | Side by side: the bone-animated skeleton outlaw (left) and the baked MultiMesh instance (right), same clip, same time. | `python tools/dev/godot.py --resolution 1280x720 --path . res://chapter1/tests/vat_preview.tscn -- --chapter1-profile-off --shots=_local/shots/vat-walker [--vat=_local/vat/walker] [--crowd=300]` |

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
| `chapter1/tests/core_text_probe.gd` | The text checks of test_core_text.gd as an observer. One object can watch a run that something else is stepping |  |
| `chapter1/tests/equiv_dump.gd` | Equivalence dump for tools/dev/equiv.py (QA tool, reads presentation state only, writes no game state). | `python tools/dev/godot.py --headless --fixed-fps 60 --path <root> --script res://chapter1/tests/equiv_dump.gd -- --chapter1-pilot` |
| `chapter1/tests/layout_dump.gd` | Control-tree dump shared by hud_dump.gd (--dump-extra) and scene_shot.gd, read by tools/dev/hud_layout_check.py. |  |
| `chapter1/tests/make_profile_legacy_fixtures.gd` | One-shot generator (T5-S0). Run it ONCE with the schema-3 code, before schema 4 lands: | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/make_profile_legacy_fixtures.gd` |
| `chapter1/tests/make_profile_v4_fixtures.gd` | One-shot generator (T6-S0). Run it ONCE with the schema-4 code, before schema 5 lands: | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/make_profile_v4_fixtures.gd` |
| `chapter1/tests/modal_fit_probe.gd` | Real-run probe for the two in-run windows: the equipment compare ("장비와 전투 선택") and the growth choice ("성장 선택"). | `python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/modal_fit_probe.gd -- \` |
| `chapter1/tests/modal_input_check.gd` | Input check on the real core for the two in-run windows, with real GUI routing (events pushed into the window): | `python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/modal_input_check.gd -- \` |
| `chapter1/tests/perf_probe.gd` | Frame and tick timing probe for exported builds and the editor (QA tool, never product code). |  |
| `chapter1/tests/perf_probe_mark.gd` | QA-only timestamp node for perf_probe.gd. Records the time its _process ran. |  |
| `chapter1/tests/profile_legacy_snapshot.gd` | Shared by make_profile_legacy_fixtures.gd (once) and test_profile_legacy_fixtures.gd (every run). |  |
| `chapter1/tests/profile_v4_snapshot.gd` | Shared by make_profile_v4_fixtures.gd (once) and test_profile_v4_fixtures.gd (every run). |  |
| `chapter1/tests/record_input_check.gd` | Input check for the battle record window, with real GUI routing (events pushed into the window): | `python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/record_input_check.gd -- \` |
| `chapter1/tests/record_run_shot.gd` | The battle record on a REAL run: the app plays a whole run with the built-in pilot (the core is stepped by calling the | `python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/record_run_shot.gd -- \` |
| `chapter1/tests/sim_power.gd` | Power bench ("short proving ground", D12 P3 / P9): measures what a FIXED in-run spell build really does on the real core. |  |
| `tools/art/gallery.py` | Draft gallery index tool (replaces organize.py / register_*.py / reg_*.py / setpick*.py). Works on | `python tools/art/gallery.py lint  [--check-manager] [--json OUT]`<br>`python tools/art/gallery.py add` |
| `tools/art/gen.py` | Codex image-generation batch runner (replaces the per-batch batch_*.py / run_*.py / revise.py copies). | `python tools/art/gen.py CONFIG.json`<br>`python tools/art/gen.py CONFIG.json --only a-1 a-2` |
| `tools/art/portrait_anchor_table.py` | Eye line / head top / feet of the three witches in one table, and how far they drift when placed side by side. | `python tools/art/portrait_anchor_table.py [--heights 400,800] [--out DIR] [--slots JSON]`<br>`python tools/art/portrait_anchor_table.py --selftest` |
| `tools/art/portrait_derive.py` | Derive per-slot crops of one witch illustration (A6 section 8.7). Pillow + NumPy only, deterministic, no models. | `python tools/art/portrait_derive.py --witch ember [--slots tools/art/portrait_slots.json] [--out DIR] [--only a,b]`<br>`python tools/art/portrait_derive.py --all` |
| `tools/art/portrait_motion_table.py` | Living-portrait motion numbers as pixel displacements (A6 8.7 / TOOLS-REVIEW 2). Reads, never edits, the | `python tools/art/portrait_motion_table.py [--heights 200,400,800] [--zoom 1.0] [--motion-scale 1.0] [--deep]`<br>`python tools/art/portrait_motion_table.py --selftest` |
| `tools/art/prompt_lint.py` | Check attempt prompts against the direction sheet (지시서) and the wording rules. Read-only. | `python tools/art/prompt_lint.py CONFIG.json [--dir DIR] [--only name ...]`<br>`python tools/art/prompt_lint.py --scan DIR` |
| `tools/art/review_sheet.py` | Standard review sheet for generated attempts (replaces sheet_*.py / mkover*.py copies). Read-only on the sources. | `python tools/art/review_sheet.py --items cinder_staff=equipment_icon/cinder_staff-r2.png linen_robe=... [--prev cinder_staff=equipment_icon/cinder_staff-r1.png]`<br>`python tools/art/review_sheet.py --list ROWS.json [--name sheet-name] [--kind icon\|image] [--out FILE.jpg]` |
| `tools/dev/audio_recheck_20261120.py` | Builds the 2026-11-20 recheck bundle (fire comparison again under one rule set + running-current lightning candidates). | `python tools/dev/make_lightning_candidates.py --out _local/audio/lightning-cands-20261120`<br>`python tools/dev/audio_recheck_20261120.py --out C:/Project/witch-moira/_local/sfx/recheck-20261120` |
| `tools/dev/audio_scene_audition.py` | Scene audition: lay candidate sounds under captured game footage, one video per candidate, plus an answer key and measurements. | `python tools/dev/audio_scene_audition.py CAPTURE_DIR --requests REQ.json --candidates CANDS.json --out _local/audio/audition/20261119-scene`<br>`python tools/dev/audio_scene_audition.py _local/sfx/ember-a --requests _local/sfx/req_ember.json --candidates cands.json --out OUT --open-labels --no-video` |
| `tools/dev/balance_search.py` | balance_search.py — 균형 시뮬레이터 위의 값 탐색(모델의 답이지 게임의 답이 아니다. 재미는 평가하지 않는다). | `python tools/dev/balance_search.py --stage power --plan A --rounds 3 --out _local/balsim2/s1A`<br>`python tools/dev/balance_search.py --stage threat --init _local/balsim2/s1A.json --out _local/balsim2/s2A` |
| `tools/dev/equiv.py` | Behaviour-preservation check for refactors: run a base commit and the working folder the same way and compare what they dump. | `python tools/dev/equiv.py`<br>`python tools/dev/equiv.py --base f36b0a7 --primary frost,ember,arc --until 2400` |
| `tools/dev/godot_guard.py` | Time limit and process-tree kill for Godot child processes (used by godot.py and run_all.py). |  |
| `tools/dev/isolated_env.py` | Environment for Godot child processes that must not touch the user folder. |  |
| `tools/dev/judge_targets.py` | 목표 판정표: tools/dev/targets.json 과 측정 JSON 여러 개를 맞대어 통과·미달·못 잼·미평가를 낸다. | `python tools/dev/judge_targets.py --out-md _local/tools/judge/table.md --out-json _local/tools/judge/table.json \`<br>`python tools/dev/judge_targets.py --check-constants --out-md _local/tools/judge/constants.md` |
| `tools/dev/make_lightning_candidates.py` | Lightning (running current) cast sound candidates for the scene audition. Candidates only: nothing here goes into the game. | `python tools/dev/make_lightning_candidates.py --out _local/audio/lightning-cands-20261120`<br>`python tools/dev/make_lightning_candidates.py --out ... --sources D:/witch-moira-audio-sources` |
| `tools/dev/perf_ab.py` | Performance before/after measurement: alternate variants, watch foreign Godot processes, print one fixed table set. | `python tools/dev/perf_ab.py run  PLAN.json --out _local/perf/<date>-<name>`<br>`python tools/dev/perf_ab.py run  PLAN.json --out ... --dry-run` |
| `tools/dev/refactor_map.py` | 참조 지도: 구조 리팩토링용 읽기 전용 정적 도구. | `python tools/dev/refactor_map.py [--out=_local/refactor-map/]`<br>`python tools/dev/refactor_map.py --rename-check <옛 경로> <새 경로>` |
| `tools/dev/shot_review.py` | 캡처 전후 비교와 화면 측정 (이미 찍힌 그림만 본다. Godot를 돌리지 않는다). |  |
| `tools/dev/sim_economy.py` | 경제·성장 시뮬레이터 — 판과 판 사이의 흐름(영구 경험치·레벨·스킬 포인트·트리·재·장비·상점·퀘스트·균열 깊이)을 계산하는 모델. | `python tools/dev/sim_economy.py`<br>`python tools/dev/sim_economy.py --preset now --runs 30` |
| `tools/dev/snapshot_diff.py` | Compare two snapshot dumps field by field. | `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd -- --case=11:chapter1.skill.frost --dump-at=1800 --dump-out=_local/diff/a.json`<br>`python tools/dev/snapshot_diff.py _local/diff/a.json _local/diff/b.json [--limit 200]` |
| `tools/manager/audit_view.py` | 점검 화면의 뒷면: 가장 최근 audit 결과를 읽고(읽기 전용), 다시 돌리기는 audit.py 를 하위 프로세스로 부른다. |  |

chapter1/tests/test_*.gd 19개는 회귀 검사라 목록에서 뺐습니다. python tools/dev/run_all.py 가 돌립니다.
