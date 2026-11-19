# CLAUDE.md — Witch Moira

Godot 4.5.1 기반 군중 생존 ARPG. 지금의 제품 범위는 제1장 「잿빛 회랑」(`chapter1/`)이다. 사용자와는 한국어로 소통한다.

2026-11-16에 옛 저장소(`d2r-combat-baseline`)에서 실행에 쓰이는 것만 옮겨 새로 시작했다. 옛 검증 원시, 과거 빌드, 실행에 쓰이지 않던 옛 상속 체인은 가져오지 않았다.

## 먼저 읽을 것

1. `docs/DIRECTOR-PLAN.ko.md` — 감사, 재설계, 로드맵, 진행 기록(2.8절이 최신 상태)
2. `docs/SYSTEMS-DESIGN.ko.md` — 서사, 마을→던전, 두 겹 성장, 장비
3. `docs/QUALITY-TARGETS.ko.md` — 단계별 통과 기준과 현재 측정값
4. `docs/PROJECT-GOAL.ko.md` — 사용자 목표
5. `docs/PROCESS-CHECKS.ko.md` — 구멍을 막는 절차(작업의 다섯 문, 점검). 아래 "점검 절차"가 요약이다

문서의 "당시 상태"를 현재 상태로 읽지 않는다. 실제 파일과 실행 결과가 근거다. 2026-11-16 이전 문서에 나오는 "스테이지", `builds/`, `evidence/`, `plans/` 같은 말은 옛 저장소의 것이다.

## 제품의 바탕 사상(사용자 지침, 2026-11-19)

이 게임의 저변에 깔린 다섯 요소는 **섹시, 쾌감, 도박, 보상, 성장**이다. 시스템과 화면을 설계할 때 이 다섯을 더 끌어내는지를 먼저 본다.

사용자 원문: "스킬 구성과 장비들의 옵션 구성도 재설계해야 할 것 같다. 한 스킬이 다른 스킬에 영향을 주는 구조도 있어야 하고, 다양한 효과와 종류들이 설계되고 구현되어야 한다. 스킬 트리도 속성마다 재구성해야 한다. 우리 게임의 저변에 깔려 있는 중요한 사상은 섹시, 쾌감, 도박, 보상, 성장이 대표적인 요소다. 이 부분을 더 끌어낼 수 있는 시스템 설계를 좀 더 검토해서 반영해 달라."

- 스킬: 한 스킬이 다른 스킬에 영향을 주는 구조를 둔다. 효과와 종류를 넓힌다. 스킬 트리는 속성(원소)마다 다시 짠다.
- 장비: 옵션 구성을 다시 설계한다.
- 명세·지시서·검수는 각 결정이 다섯 요소 중 무엇을 키우는지 적는다. 어느 것도 키우지 않는 항목은 뒤로 미룬다.
- 설계가 먼저다. 이 사상에 닿는 화면이라도 명세 없이 낱개로 고치지 않는다.

## 폴더

| 폴더 | 내용 |
|---|---|
| `chapter1/`, `combat/` | 게임. 저장소 루트가 Godot 프로젝트다(`project.godot`) |
| `docs/` | 계획, 설계, 명세(`specs/`), 검수(`reviews/`), 원화 프롬프트 |
| `tools/dev/` | 실행·회귀 도구 |
| `tools/manager/` | 제작 관리 툴 |
| `art-archive/` | 게임에 쓰지 않는 예전 원화 보관 |
| `_local/` | 캡처, 측정 원시, 검사용 임시 파일. git에 올라가지 않고 언제든 지워도 된다 |
| `.claude/agents/` | 역할별 하위 에이전트 |

`docs/`, `tools/`, `art-archive/`, `_local/`에는 `.gdignore`가 있어 Godot가 들여다보지 않는다.

## 명령

```powershell
# 회귀 전체(약 11분: 골든 두 번 포함) / 골든·드랍 시뮬레이션 제외(약 30초) / 일부만
python tools/dev/run_all.py
python tools/dev/run_all.py --quick
python tools/dev/run_all.py --only combat,golden

# 게임 실행(필요하면 임포트부터 한다). --chapter1-profile-off가 있는 실행과 --import-only만 _local/appdata/dev/로 격리된다.
# 그 인수 없이 띄우는 것은 사용자 본인의 플레이라 저장이 %APPDATA%\WitchMoira에 쓰인다.
python tools/dev/run_dev.py -- --chapter1-start
python tools/dev/run_dev.py --resolution 1920x1080 -- --chapter1-start --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus
python tools/dev/run_dev.py --import-only

# 검사·측정·캡처는 godot를 직접 부르지 말고 tools/dev/godot.py로 부른다(APPDATA를 _local/appdata/godot/로 격리, 인수와 종료 코드는 그대로).
# 코어 골든 리플레이: 비교 / 갱신(코어 동작을 의도적으로 바꿨을 때만) / 글을 뺀 비교(이름 교체·번역 때)
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd -- --update
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd -- --textless

# 전투 지표 측정(세 계열 × 시드 3개, 약 3분)
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/measure_combat.gd -- --arc-combined --secondary-off

# 화면 캡처와 상태 덤프(자동 조작으로 한 판)
python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.frost --shots=_local/shots/<이름> --dump=_local/shots/<이름>.json

# 드랍 시뮬레이션 / 실제 코어의 한 판 드랍
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_loot.gd -- --runs=10000
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/report_run_loot.gd -- --seeds=11,12,13

# Windows 실행 파일(결과는 _local/build/). 다른 에이전트가 쓰는 작업 트리에서는 돌리지 않는다.
python tools/dev/build.py --preset qa
python tools/dev/build.py --preset store
```

Godot: `C:/Project/rea-tools/godot-4.5.1/Godot_v4.5.1-stable_win64_console.exe`
Python: `C:/Users/twins/AppData/Local/Programs/Python/Python310/python.exe`
Blender: `D:/Blender Foundation/Blender 5.3/blender.exe`(5.3.0, 명령줄 실행 확인 2026-11-17)

## 구조

- 실행 루트: `chapter1/ChapterOne.tscn` → `chapter1/app/chapter_one.gd`(입력·조립).
- `chapter1/core/` — 60Hz 결정론 시뮬레이션. 실행 코어는 `chapter_core.gd` → `combat_core.gd`. 성장은 `run_growth.gd`(+`run_growth_quality37.gd`), 장비는 `loot.gd`, 영구 성장은 `skill_tree.gd`·`character_progression.gd`, 저장은 `chapter_profile.gd`, 자동 조작은 `chapter_pilot.gd`.
- `chapter1/data/` — 수치와 정의. `combat_tuning.json`(적·구역·생성·물약·경험치·주력 보정·규칙 스위치), `loot.json`(장비 문법과 드랍), `growth_quality36·37.json`(한 판의 기술·은총), `skill_trees.json`·`character_progression.json`(영구 성장).
- `chapter1/view/` — 표현. `hud/chapter_hud.gd`·`combat_bar.gd`·`skill_tree_panel.gd`·`palette.gd`, `fx/chapter_effects.gd`·`combat_juice.gd`, `actors/chapter_actors.gd`, `world/chapter_world.gd`.
- `chapter1/art/` — 모델, 텍스처, 아이콘, 소리, 세 주인공 원화(`characters/*_witch_v02.png`).
- `chapter1/tests/` — 검사, 골든, 측정·캡처 도구.

### 알아 둘 흔적

- `chapter1/view/` 바로 아래의 `cloister_*.gd`, `chapter_world_quality*.gd`는 옛 층이다. 평탄화한 파일들은 이것을 상속하지 않지만(모두 `extends RefCounted`), `app/chapter_one.gd`와 `view/world/chapter_world.gd`가 아직 `preload`로 불러와 실행 때 로드된다(2026-11-17 확인). 정리 지시서(`docs/specs/T1-tech-directives-20261116.ko.md` 4번)가 끝나기 전에는 지우면 안 된다. 새 기능은 여기가 아니라 `hud/`, `fx/`, `actors/`, `world/`의 파일에 넣는다.
- 평탄화한 파일 안의 `sync__q40`처럼 `이름__층`으로 끝나는 메서드는 옛 체인의 앞선 층이고, 접미사 없는 것이 최종 진입점이다. 고치는 부분부터 정리한다.
- 파일 이름의 `quality10`, `quality43` 같은 숫자는 옛 버전 번호다. 이름에 숫자가 붙어 있어도 이 저장소에 있으면 쓰이는 파일이다.
- `core/chapter_items.gd`(장비 v1)는 옛 저장의 장비를 검증하려고 남아 있다. 지우면 안 된다.
- `core/combat_run.gd`는 `test_combat_run.gd`와 진입 스크립트가 아직 참조한다.

## 저장

- 스키마 3, `user://chapter-one-profile-v3.json`. 사용자 폴더는 `%APPDATA%\WitchMoira`다.
- 스키마 2·1 파일은 같은 폴더에 있으면 읽기만 한다. 옛 저장소 시절의 저장(`%APPDATA%\AshenCloisterChapterOne*`)은 자동으로 넘어오지 않는다.
- 검사는 `_local/` 아래의 격리 경로만 쓴다. 검사가 사용자 폴더를 읽거나 쓰게 만들지 않는다.
- 검사·도구의 Godot 실행은 `APPDATA`를 `_local/appdata/<용도>/`로 바꿔 사용자 폴더에 로그·캐시도 쓰지 않는다(`tools/dev/isolated_env.py`). Godot를 직접 부르면 헤드리스 실행도 `%APPDATA%\WitchMoira\logs`에 로그를 쓴다.

## 반드시 지킬 것

- 사용자 저장(`%APPDATA%\WitchMoira`)을 지우거나 고치지 않는다.
- `git add .` 금지. 커밋·푸시는 사용자가 요청할 때만.
- `.gitattributes`가 `* -text`다. 줄바꿈을 바꾸는 도구(`sed -i` 등)로 기존 파일을 고치지 않는다.
- 표현(view)은 코어 이벤트와 읽기 전용 상태만 쓴다. 표현이 피해·판정·코어 상태를 바꾸지 않는다.
- 코어를 고치면 골든 리플레이를 돌린다. 해시가 바뀌면 의도한 변경인지 밝히고 `--update`한다.
- 수치는 데이터 파일에서 고친다. 고친 뒤 `measure_combat.gd`, `sim_loot.gd`, 골든을 다시 돌린다.
- 캡처·측정 원시·임시 파일은 `_local/`에만 둔다. 저장소에 올리지 않는다.
- `assert()` 안에 부작용을 넣지 않는다(릴리스 빌드에서 제거됨).
- Sunra 등 유료 생성은 비용을 제시하고 승인받은 뒤에만 실행한다.
- 실행하지 않은 검사, 보지 않은 화면, 듣지 않은 소리를 통과로 적지 않는다. 사람의 재미·미감 평가는 사용자 플레이로만 채운다.

## 점검 절차(사용자 승인, 2026-11-20)

자세한 것은 `docs/PROCESS-CHECKS.ko.md`. 도구 목록은 `docs/TOOLS-INDEX.ko.md`(관리 툴의 「도구」 화면과 같다).

- **작업 하나는 다섯 문을 지난다**: ① 사용자 지시를 원문으로 적고 받을 명세 절을 정한다(없으면 "명세 없음"으로 올린다) → ② 명세(디렉터는 구현을 배정하는 절을 직접 읽는다) → ③ 구현(작업 폴더, 패치와 보고서, 꺼진 값에서 골든 불변) → ④ 검수(본 저장소에서 다시 돌리고, 화면이 걸리면 캡처를 직접 본다) → ⑤ 닫기(커밋, 켜기 전에 남은 일을 적는다).
- **말의 규칙**: "통과"는 실제로 돌린 것에만 쓰고, 일부만 돌렸으면 무엇을 돌렸는지 쓴다. 시뮬레이터·계산의 값에는 "모델의 답"을 붙이고, 판 수가 적은 결과에는 판 수를 붙인다. 화면은 "직접 봄 / 캡처만 있음 / 보지 않음" 가운데 하나를 적는다.
- **일회용 스크립트를 되풀이해 쓰지 않는다.** 같은 일을 두 번 하게 되면 `tools/`나 `chapter1/tests/`의 도구로 올린다. 새로 쓰기 전에 도구 색인을 본다.
- **꺼진 채 들어온 장치**(`rhythm.enabled`, `run_spells.enabled` 등)는 켜기 전에 남은 일(수치, 화면이 알아야 할 이벤트, 켠 경로의 골든, 실측 판정, 사용자 플레이)을 적어 두고, 남은 일이 0일 때 켠다.
- **전체 점검**: 큰 변경이 있을 때 하고, 그런 일이 없어도 주마다 한 번 한다(더 자주 하지 않는다). 관리자들이 자기 영역을 읽기 전용으로 감사하고(명세와 구현의 어긋남, 낡은 문서, 쌓인 임시 스크립트, 안 쓰는 도구, 빠진 기록, 측정 없이 넘어간 것) 디렉터가 `docs/reviews/AUDIT-<날짜>.ko.md`로 묶는다.
- **에셋은 모두 바뀔 것이다**(사용자, 2026-11-20). 출처 기록의 구멍은 지금 개발을 막지 않는다. 대신 그림·모델·소리를 바꿔 끼울 때 고칠 곳이 가장 적게 되도록 구조를 잡는다: 코드가 파일 경로를 여기저기서 직접 부르지 않게 하고, 새 에셋은 원장(`tools/art/asset_ledger.py`)에 올린다.

## 지휘 체계

- 총괄 디렉터: 주 세션. 목표·우선순위·사용자 소통·최종 판정.
- 중간 관리(Opus, 구현 안 함): `tech-lead`, `design-lead`, `art-lead`, `audio-lead`. 작업 지시서 작성과 검수. 소리의 기준 문서는 `docs/AUDIO-PLAN.ko.md`다.
- 세계관·스토리(Opus, 코드·데이터 수정 안 함): `narrative-lead`. 기준은 `docs/SEASON1_WORLD_STORY_MASTER.md`(기획자 원문)와 `docs/reviews/STORY-REVIEW-20261116.ko.md` 11절(결정 기록), 산출물은 `docs/story/`. 이름·대사·원화 프롬프트처럼 설정이 걸린 일은 이 문서들을 먼저 읽는다.
- 개발(Sonnet): `gameplay-systems`, `refactor-architect`, `manager-tools`, `qa-perf`(기술) · `content-balance`(기획) · `vfx-feel`, `ui-hud`, `character-artist`, `environment-artist`, `asset-producer`(화면·아트) · `sound-designer`(소리).
- Codex: 작업 에이전트 하나로 쓴다. 디렉터가 호출마다 역할 하나를 준다(지금은 그림 생성). 운용은 `codex-operator`가 맡고, Codex가 읽는 지침은 루트의 `AGENTS.md`다. `AGENTS.md`에는 Codex의 역할과 금지만 적고 이 파일의 내용을 옮겨 적지 않는다.
- 하위 에이전트는 다른 하위 에이전트를 부를 수 없다. 흐름은 디렉터 → 관리자(지시서) → 디렉터가 개발 에이전트에 배정 → 관리자(검수) → 디렉터.

## 검증용 실행 인수

`--chapter1-start` 바로 시작 · `--chapter1-pilot` 내장 자동 조작 · `--chapter1-profile-off` 저장 비활성(빌드 없이 돈다) · `--chapter1-qa-ignore-focus` 포커스 상실 시 정지 안 함 · `--chapter1-primary=chapter1.skill.{ember|frost|arc}` · `--chapter1-seed=N` · `--chapter1-quit-after=초` · `--chapter1-no-juice` 전투 효과 끔 · `--chapter1-capture-dir=경로`(`_local/` 아래만 허용)
