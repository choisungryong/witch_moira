# T8 — 화면 계약 구조: 폴더·이름, 계약 판과 검사기, 첫 두 화면을 옛 층에서 떼어 내기

작성: tech-lead, 2026-11-20. 상위 문서: `docs/SCREEN-DESIGN-HARNESS.ko.md`(이하 하네스) 2절·3.5·3.6·5·6절, 9.2절.
이 문서는 하네스의 분리선(“화면은 화면 계약만 읽는다”)을 코드 구조로 고정한다. **화면의 모습을 바꾸는 일은 여기 없다.** 첫 두 화면은 지금 모습 그대로 새 구조로 옮기고(동작 불변), 새 디자인은 하네스 ③~⑤를 지난 뒤 같은 구조 위에서 한다.

다섯 사상과의 관계: 이 지시서 자체는 어느 것도 직접 키우지 않는다. 성장 선택 화면(도박·보상·성장)과 첫 화면 겸 캐릭터 선택(섹시)을 사용자 선택안으로 갈아 끼울 수 있게 하는 바탕이다. 하네스 8절의 첫 바퀴가 이것을 기다린다.

표시: [봄] 코드에서 확인 · [가설] · [미확인].

---

## 0. 묶음 한눈

| 묶음 | 담당 | 고치는 파일(이 밖은 건드리지 않음) | 의존 | 병렬 |
|---|---|---|---|---|
| **S0-a** 계약 검사기(T-1) | manager-tools | 새 `tools/dev/screen_contract_check.py`, 새 `tools/dev/test_screen_contract_check.py`, `tools/dev/run_all.py`(검사 등록만), `docs/TOOLS-INDEX.ko.md`, `tools/manager/tools_index.json` | 없음 | S0-b, S0-c와 함께 |
| **S0-b** 계약 캡처·덤프(T-2) | qa-perf | `chapter1/tests/scene_shot.gd`, `chapter1/tests/hud_dump.gd`, 새 `chapter1/tests/test_screen_contracts.gd`, `tools/dev/equiv.py` | 없음 | S0-a, S0-c와 함께 |
| **S0-c** 제안 뽑기를 코어로 | gameplay-systems | `chapter1/core/combat_core.gd`, `chapter1/core/run_growth.gd`, 필요하면 `chapter1/core/chapter_core.gd`, 골든 파일 | 없음 | S0-a, S0-b와 함께 |
| **S1** 성장 선택 떼어 내기 | refactor-architect | `chapter1/view/hud/chapter_hud.gd`(**점유**), `chapter1/view/hud/spell_card.gd`, 새 `chapter1/view/contracts/growth_choice_contract.gd`, 새 `chapter1/view/hud/screens/growth_choice.gd`, 새 스키마·픽스처, `chapter1/tests/scene_shot.gd`의 `boon`·`boon_spells` 장면 | S0-a, S0-b 병합 뒤 | 단독(점유) |
| **S2** 첫 화면 떼어 내기 | refactor-architect | `chapter1/view/hud/chapter_hud.gd`(**점유**), `chapter1/app/chapter_one.gd`의 `menu_character_id()`만, 새 `chapter1/view/contracts/title_contract.gd`, 새 `chapter1/view/hud/screens/title.gd`, 새 스키마·픽스처, `scene_shot.gd`의 `title` 장면 | S1 병합 뒤 | 단독(점유) |

S0-c는 S1을 막지 않는다(S1의 어댑터는 `get_offer()`를 한 곳에서만 부르는 것으로 S0-c 전에도 성립한다). S0-c가 들어오면 그 한 곳의 주석만 고친다.

---

## 1. 폴더와 이름 규칙(모든 화면 공통)

| 무엇 | 자리 | 이름 | 내보낸 빌드에 |
|---|---|---|---|
| 화면 | `chapter1/view/hud/screens/` | `<id>.gd` (예: `growth_choice.gd`, `title.gd`) | 들어감 |
| 어댑터 | `chapter1/view/contracts/` | `<id>_contract.gd` | 들어감 |
| 계약 스키마 | `chapter1/tests/contracts/` | `<id>.contract.json` | **빠짐**(`chapter1/tests/*`는 내보내기 제외 [봄: `export_presets.cfg`]) |
| 계약 픽스처 | `chapter1/tests/fixtures/contracts/` | `<id>.<변형>.json` | 빠짐 |
| 시안 장면 | `chapter1/tests/proposals/<id>/` | `<a|b|c>.gd` | 빠짐 |

하네스 3.5·3.9와 다른 점 둘(디렉터 결정 9.2-1의 권고, 9절):
- 스키마를 `chapter1/view/contracts/`가 아니라 `chapter1/tests/contracts/`에 둔다. 검사기만 읽는 파일이 게임 빌드에 실려 나가지 않게 한다.
- 새 픽스처를 `fixtures/ui/`가 아니라 `fixtures/contracts/`에 둔다. 지금 `fixtures/ui/title.*.json`, `boon*.json`은 **코어 상태의 씨앗**이고(하네스 2.3) 옛 화면이 남아 있는 동안 계속 쓰인다. 같은 이름을 다른 꼴로 덮으면 옛 장면이 깨진다. 옛 씨앗 픽스처는 그 화면의 옛 층이 지워지는 묶음(S1·S2)에서 함께 지운다.

파일 규칙:
- 새 화면·어댑터 파일에 `class_name`을 쓰지 않는다. `preload`로 부른다. (`class_name`은 `.godot/global_script_class_cache.cfg`를 고쳐 쓰게 해 병렬 실행의 캐시 경합을 늘린다 — `docs/reviews/TECH-REVIEW-20261120.ko.md` 2절 H2.)
- `extends RefCounted`(어댑터), `extends Control` 또는 그 하위(화면). 옛 층(`cloister_*.gd`, `chapter_world_quality*.gd`, `chapter_hud.gd`의 `__q*` 메서드)을 상속하거나 부르지 않는다.
- 새 파일마다 `.gd.uid`를 함께 올린다(Godot가 만든 것).

## 2. 계약의 꼴과 판 번호

### 2.1 계약(Dictionary)

```
{ "screen": "<id>", "contract_version": <정수>, ...화면이 그리는 필드... }
```

- 필드는 **화면이 지금 그리는 것만**(하네스 2.4-3). “쓸지 몰라” 넣지 않는다.
- 글: 코어·데이터에서 오는 글(카드 이름, 설명, 마녀 이름)은 어댑터가 `Loc.t`로 옮긴 문자열로 담는다. 화면이 늘 같은 자리에 쓰는 고정 문구(단추 이름, 제목)는 화면이 직접 가진다.
- 수치는 그린 그대로의 꼴(이미 만든 문자열이면 문자열, 막대면 0~1 실수). 색·좌표·글꼴은 담지 않는다. 색은 뜻 이름(`element:"frost"`)으로.
- **참조값**: 화면이 신호로 돌려줘야 하는 코어의 식별자(제안 토큰, 카드 id, 시작 기술 id)는 `ref`로 끝나는 필드에 불투명 문자열로 담는다. 화면은 이것을 해석하거나 쪼개지 않고 신호에 그대로 실어 보낸다.

### 2.2 스키마 파일(`chapter1/tests/contracts/<id>.contract.json`)

```
{ "screen": "growth_choice",
  "contract_version": 1,
  "fields": { "<이름>": <타입>, ... },
  "variants": ["normal", "long", ...],
  "signals": ["chosen(card_ref)"] }
```

타입은 이것뿐이다(검사기가 아는 말):

| 꼴 | 뜻 |
|---|---|
| `{"type":"string","max_len":N}` | 문자열. `max_len`은 선택 |
| `{"type":"int","min":a,"max":b}` / `{"type":"float","min":a,"max":b}` | 수 |
| `{"type":"bool"}` | 참거짓 |
| `{"type":"enum","values":[...]}` | 정해진 문자열 중 하나 |
| `{"type":"array","min":a,"max":b,"item":<타입>}` | 배열 |
| `{"type":"object","fields":{...}}` | 사전(아래 필드가 전부. 모르는 키는 실패) |
| 공통 선택 키 | `"optional":true`(없어도 됨), `"nullable":true`(null 허용), `"requested":"<장부 줄>"`(시스템이 아직 주지 못함: 어댑터 출력에서는 없어도 되고, 픽스처에는 가짜 값이 있어야 한다) |

### 2.3 판 번호 규칙

- 스키마의 `fields`·`signals`가 **조금이라도** 바뀌면 `contract_version`을 1 올린다(추가도 올린다. 판 번호를 비교하는 것이 유일한 검사라서 단순하게 간다).
- 같은 정수가 세 곳에 있어야 한다: 스키마의 `contract_version`, 어댑터의 `const CONTRACT_VERSION := N`, 화면의 `const CONTRACT_VERSION := N`. 모든 픽스처의 `contract_version`도 같아야 한다. 검사기가 넷을 맞춰 본다.
- 화면의 `apply(contract)`는 판이 다르면 `push_error`하고 아무것도 그리지 않는다(검사기가 막으므로 실행 중에는 일어나지 않아야 한다).

### 2.4 픽스처 파일(`chapter1/tests/fixtures/contracts/<id>.<변형>.json`)

계약 그 자체(위 2.1의 Dictionary)를 담는다. 코어 상태의 씨앗(`give`, `cards` id로 풀에서 찾기)을 넣지 않는다. “가장 긴 글” 변형은 실제로 나올 수 있는 가장 긴 문자열을 쓴다(지어낸 벽글 금지 — `scene_shot.gd` 머리 주석의 규칙).

## 3. 화면과 어댑터의 규칙

**화면(`screens/<id>.gd`)**
- 공개 진입점은 `func apply(contract: Dictionary) -> void` 하나와 `signal`들뿐이다. (`show`라는 이름은 쓰지 않는다: `CanvasItem.show()`와 겹쳐 서명이 달라 컴파일되지 않는다.)
- 나오면 안 되는 것(검사기가 0을 확인): 낱말 `run`, `growth`; 다른 객체의 사적 필드 읽기(`<이름>._<이름>`); `Color("`(색은 `Palette`); 숫자로 자식 찾기(`get_child(<숫자>)`); `res://chapter1/core/`, `res://chapter1/app/`의 preload.
- 화면은 자기 노드만 만든다. 다른 화면의 노드를 자식 번호로 고쳐 쓰지 않는다.
- 그림은 `chapter1/view/assets/asset_slots.gd`의 자리 이름으로 부른다(T7). 파일 경로를 쓰지 않는다.

**어댑터(`contracts/<id>_contract.gd`)**
- `static func build(run: RefCounted, app_state: Dictionary = {}) -> Dictionary` 하나. `app_state`는 호스트(`chapter_hud.gd`)가 가진 앱 쪽 상태(프로필 요약, 고른 마녀 번호 등)를 넘길 때 쓴다.
- 코어를 **읽기만** 한다. 검사기가 막는 것: `run.<…> =`, `+=`, `-=`, 그리고 코어의 바꾸는 함수 이름(`choose(`, `start(`, `step(`, `equip(`, `reroll(`, `open_inventory(`, `close_inventory(`, `set_`, `import_`, `configure_`, `clear_build(`).
- `run.get_offer()`는 예외로 **어댑터에서만** 허용한다. 지금 이 함수는 걸린 제안이 없으면 그 자리에서 뽑는다 [봄: `run_growth.gd` 172~195행]. S0-c가 끝나면 뽑기 없는 읽기가 되고 이 예외 주석을 지운다.
- 깊은 복사를 매번 만들지 않는다: `run.growth.snapshot()`을 부르지 않고, 호스트가 프레임마다 이미 만든 `_frame_growth`가 필요하면 `app_state`로 받는다.

**호스트(`chapter_hud.gd`)**
- 화면 하나당 “어댑터를 부르고 → `apply` → 신호를 기존 `signal`에 잇는” 자리만 둔다. 계약을 만드는 시점은 지금 모달을 다시 짓는 시점(`sync__cloister`의 서명 변화, 141~149행 [봄])과 같다. **매 프레임 만들지 않는다.**

**전투 HUD(이번 묶음 밖, 규칙만)**: 매 프레임 그리는 화면은 계약 Dictionary를 처음 한 번 만들고, 어댑터의 `static func fill(run, contract: Dictionary, frame_growth: Dictionary) -> void`가 그 값을 제자리에서 덮어쓴다. 새 배열·사전을 프레임마다 만들지 않는다. `frame_probe.gd`로 HUD 동기화 +0.1ms 이내를 재어 보고서에 붙인다(하네스 2.5, A4 3.2.5). 사적 필드(`_next_cast` 등)는 코어의 읽기 전용 함수가 생긴 뒤에 옮긴다(검수 기록 V-1).

## 4. 계약 검사기가 볼 것(T-1)

`python tools/dev/screen_contract_check.py` — 인수 없이 전부. `--dumps=<폴더>`가 있으면 실판 어댑터 출력도 본다. 마지막 줄 `SCREEN_CONTRACT {"screens":N,"fixtures":N,"dumps":N,"failures":[...]}`, 실패가 있으면 종료 코드 1.

1. 스키마마다: 2.2의 꼴인가(모르는 타입·키는 실패).
2. 판 번호: 스키마 = 어댑터 `const CONTRACT_VERSION` = 화면 `const CONTRACT_VERSION` = 모든 픽스처(2.3). 상수는 정규식 `^const CONTRACT_VERSION\s*:?=\s*(\d+)`로 읽는다.
3. 픽스처마다: 스키마를 따르는가(필수·타입·범위·`max_len`·모르는 키). `requested` 필드는 픽스처에 있어야 한다.
4. 변형: 스키마의 `variants` 하나하나에 픽스처 파일이 있는가.
5. 신호: 화면 파일의 `signal` 선언 이름 = 스키마 `signals`의 이름.
6. 화면 파일 정적 검사: 3절의 금지 목록이 0인가(주석 줄 제외).
7. 어댑터 정적 검사: 3절의 쓰기·바꾸는 함수가 0인가. `get_offer(`는 어댑터에서 1곳까지.
8. `--dumps`: `chapter1/tests/test_screen_contracts.gd`가 쓴 실판 출력이 스키마를 따르는가. `requested` 필드는 없어도 된다.

`run_all.py` 등록: 이름 `screen-contract`, 빠른 묶음(`--quick`)에 넣는다. 한 단위 안에서 먼저 `test_screen_contracts.gd`를 격리 APPDATA로 돌려 `_local/run-all-fixtures/contracts-<시각>/`에 덤프를 쓰게 하고, 이어 검사기를 `--dumps`로 부른다. `CHANGE_TABLE`의 `view`·`app` 선택에 `screen-contract`를 더한다. 스크린 파일이 아직 하나도 없을 때는 `screens 0`으로 통과한다.

## 5. 지시서

### S0-a — 계약 검사기 (manager-tools)

**할 일**: 4절의 1~8을 하는 `tools/dev/screen_contract_check.py`(표준 라이브러리만)와 그 자체 검사 `tools/dev/test_screen_contract_check.py`를 만든다. 자체 검사는 임시 폴더에 가짜 스키마·픽스처·화면·어댑터를 만들어 각 실패 종류가 하나씩 잡히고, 다 맞는 경우가 통과하는지 본다(진짜 저장소 파일에 기대지 않는다 — 기대면 다른 담당의 작업 중 변경에 흔들린다). 검사기는 `--root`(기본 저장소 루트)를 받아 자체 검사가 임시 폴더를 가리킬 수 있게 한다. `run_all.py`에 4절대로 등록하되, Godot 부분(`test_screen_contracts.gd`)은 S0-b가 만든다 — 그 파일이 없으면 덤프 없이 검사기만 돌리고 결과에 `dumps 0 (test missing)`을 적는다. 도구 색인 두 곳에 한 줄씩.

**지킬 것**: 기존 검사의 이름·결과 줄·종료 코드를 바꾸지 않는다. `run_all.py`는 검사 목록·`SELECTIONS`·`WEIGHTS`·러너 추가만 고친다.

**끝 기준**:
- `python tools/dev/test_screen_contract_check.py` → 종료 0.
- `python tools/dev/screen_contract_check.py` → `SCREEN_CONTRACT {"screens":0,...,"failures":[]}`, 종료 0(아직 화면이 없음).
- `python tools/dev/run_all.py --only screen-contract,tools-selftest,manager` → 모두 pass.
- 보고서에 위 세 결과 줄을 그대로.

**건드리지 않음**: `chapter1/` 전부, `tools/dev/godot.py`·`godot_guard.py`·`isolated_env.py`(병렬 실패 대책 묶음이 따로 고친다).

### S0-b — 계약 캡처·덤프와 동작 불변 도구 (qa-perf)

**할 일**:
1. `chapter1/tests/test_screen_contracts.gd`(헤드리스): 인수 `--out=<폴더>`(`_local/` 아래만 허용). (a) `chapter1/tests/fixtures/contracts/`의 픽스처마다 해당 화면을 띄우고 `apply`한 뒤 2프레임 기다려 스크립트 오류가 없는지, 스키마의 신호가 화면에 다 있는지 본다. (b) 어댑터가 있는 화면마다 실제 코어로 계약을 만들어 `<out>/<id>.<경우>.json`에 쓴다. 경우: `growth_choice`는 꺼진 판 첫 제안·켠 판 첫 제안(시드 11, 세 기술), `title`은 프로필 없음 메뉴(`app_state`는 S2가 정한 꼴의 빈 값). 켠 판은 코어에 `run_spells.json` 사본을 `enabled=true`로 넣는다. 이 일을 하는 함수를 `chapter1/tests/support/trial_docs.gd`의 `static func enable_spells(run) -> bool` 한 곳에 두고, `modal_input_check.gd`·`scene_shot.gd`·`hud_dump.gd`의 같은 코드도 이것을 부르게 바꾼다(검수 기록 F-5). 결과 줄 `CHAPTER1_SCREEN_CONTRACTS_RESULT {"checks":N,"failures":[...]}`. 화면·어댑터가 아직 없으면 `checks 0`으로 통과.
2. `scene_shot.gd --contract=<id> --variant=<변형>`: 코어 없이 화면 파일만 띄워 픽스처를 `apply`하고 찍는다(지금의 코어 씨앗 장면은 그대로 둔다).
3. `hud_dump.gd --dump-contracts=<폴더>`: 기존 덤프 순간(`menu`, 성장 선택 순간)에 그 화면 어댑터의 출력을 JSON으로 쓴다. 기본 덤프 내용은 바꾸지 않는다.
4. `tools/dev/equiv.py --game-args="<인수들>"`: 두 쪽 실행에 같은 게임 인수를 더 넘긴다(예: `--chapter1-trial=spells`). 켠 판의 성장 선택을 S1에서 비교하려면 필요하다. 기본값은 지금과 같다.

**지킬 것**: 코어·`chapter1/view/`·`chapter1/app/`를 고치지 않는다. 기존 도구의 기본 출력이 바뀌지 않는다(바꾸면 `equiv.py` 비교가 깨진다).

**끝 기준**:
- `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_screen_contracts.gd -- --out=_local/t8/s0b` → `checks 0, failures []`.
- `python tools/dev/equiv.py --until 600 --primary frost --skip-golden` → `EQUIV IDENTICAL`(도구만 바뀌었으므로), 그리고 `--game-args="--chapter1-trial=spells"`를 붙여 한 번 더 → `EQUIV IDENTICAL`.
- `python tools/dev/run_all.py --quick` → 통과(돌린 줄 그대로 붙임).
- `python tools/dev/test_equiv.py` → 종료 0(`--game-args` 분해의 검사 하나 추가).

**건드리지 않음**: `tools/dev/run_all.py`(S0-a가 등록), 골든 파일.

### S0-c — 성장 제안을 코어가 뽑아 두기 (gameplay-systems)

**왜**: 지금은 화면(`chapter_hud.gd` 144·193·726·1189행)이 `run.get_offer()`를 불러 제안 뽑기를 일으킨다 [봄]. 결과는 같지만(성장 RNG가 따로라서) “표현은 읽기 전용”을 문자 그대로 어긴다(검수 기록 C-3).

**할 일**: 레벨업으로 `mode`가 `choice`가 되는 그 틱에 코어가 `growth.next_offer()`를 불러 제안을 걸어 둔다. 다시 빌기(`reroll`)는 지금대로. `get_offer()`는 걸린 제안의 복사본만 돌려주고 뽑지 않는다(걸린 것이 없으면 `{}`). 자동 조작·HUD·검사 도구가 그대로 동작하는지 확인한다.

**지킬 것**: 카드의 내용과 순서가 바뀌면 안 된다. 꺼진 판·켠 판 모두.

**끝 기준**:
- `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd` → 불일치 0. **해시가 바뀌면 멈추고** 어디서 바뀌는지(스냅숏의 `offer`가 한 틱 일찍 채워지는 것 등) 보고한다. 의도한 변경으로 받을지는 tech-lead와 디렉터가 정한다. `--update`를 스스로 하지 않는다.
- `python tools/dev/run_all.py --only core-all` → 통과.
- `test_growth.gd`에 “`get_offer()`를 두 번 불러도 RNG 상태(`snapshot().rng_state`)가 같다” 검사 하나.

**건드리지 않음**: `chapter1/view/`, `chapter1/app/`, 데이터 파일.

### S1 — 성장 선택을 새 구조로 옮기기 (refactor-architect, `chapter_hud.gd` 점유)

**목표**: 성장 선택 창이 지금과 **픽셀·노드·글이 같은 채로** `screens/growth_choice.gd` + `contracts/growth_choice_contract.gd`로 그려진다. 옛 층을 걷어 낸다.

**지금 이 창을 짓는 곳 [봄]** — 모두 읽고 시작한다:
- `chapter_hud.gd` `_build_modal__cloister`의 `"choice"` 갈래(192~214행): 제목, 안내, 카드 상자(`box.get_child(2)`), 카드마다 문장(Emblem), 이름, 종류, 설명, 여백, 단추(`choice.emit(token, card_id)`).
- `_build_modal__q38`(700~717행): 창 크기·위치, `_growth_cards38` 호출, `_decorate38`, 초점.
- `_growth_cards38__q38`(722~747행): 테두리 색, 문장을 `ElementSeal38`로 바꿈, 자식 번호 2·3·4로 글색·크기·여백, 단추 글 “서약 선택”.
- `_growth_cards38`(1170~1193행): 설명을 `ScrollContainer "CardText"`로 감쌈, 켠 판이면 `SpellCard.dress`, 창 높이.
- `_build_modal`(1297~1303행): 안내 문구 교체.
- 설명 글의 사슬: `_card_description` → `__q36` → `__q16` → `__cloister`(233·394·599·1165행).
- `spell_card.gd` 전체(켠 판 카드), `spell_mark.gd`.

**할 일**:
1. `chapter1/tests/contracts/growth_choice.contract.json`(판 1): 지금 창이 그리는 것만. 최소한 `offer_ref`(제안 토큰), `spells_on`(bool), `cards`(1~4개; 각 `ref`, `element`(enum `ember|frost|arc|none`), `title`, `kind`, `kind_label`, `description`, 켠 판일 때 `spell` 객체). `spell` 객체의 필드는 `spell_card.gd`가 지금 코어에서 읽는 것을 하나하나 적어 정한다(`run.spells`, `run.run_spells_view()`, `run.growth.effective_skill()`에서 읽는 값 → 그린 결과의 꼴로). 다시 빌기·등급 같은 새 필드는 넣지 않는다(디자인 ⑤의 일). 신호는 `chosen(card_ref)`.
2. 어댑터: 1의 계약을 `run`에서 만든다. 설명 글 사슬(`_card_description*`)의 글 만들기는 어댑터로 옮긴다(한글 리터럴은 옮기기만, 새로 늘리지 않음). `spell_card.gd`의 코어 읽기는 어댑터로 옮긴다.
3. 화면: 지금과 같은 노드 트리(이름·순서·크기·글·색·글꼴 크기·`CardText` 스크롤·`ElementSeal38`)를 계약만으로 짓는다. `spell_card.gd`의 덧입히기는 화면 안의 카드 짓기로 합친다(덧입히기 대신 처음부터 그 모습으로). `spell_card.gd`·`spell_mark.gd`가 다른 곳에서 쓰이지 않으면(먼저 Grep) `spell_card.gd`는 지우고 `spell_mark.gd`는 화면이 부르는 부품으로 남긴다.
4. 호스트: `"choice"` 갈래와 `_growth_cards38*` 두 층, 설명 사슬 넷 중 다른 곳에서 부르지 않는 것을 지운다(지우기 전에 `chapter1/`·`tools/` 전체를 Grep: `hud_dump.gd`, `scene_shot.gd`, `modal_input_check.gd`, `modal_fit_probe.gd`가 이름이나 자식 번호로 이 창을 찾는지 본다. 찾으면 그 도구를 노드 이름으로 찾도록 함께 고친다). 신호 `chosen(ref)`는 `choice.emit(contract.offer_ref, ref)`로 잇는다. 창 크기·`_decorate38`·초점 이동은 호스트에 남겨도 되고 화면으로 옮겨도 된다 — 결과가 같아야 한다.
5. 픽스처: `fixtures/contracts/growth_choice.<변형>.json` — `normal`, `long`, `spells_on`, `max`(카드 넷). 지금의 `fixtures/ui/boon*.json`와 같은 장면이 나오도록 그 내용을 계약 꼴로 옮겨 적는다. `scene_shot.gd`의 `boon`·`boon_spells` 장면은 `--contract` 길로 바꾸고 옛 씨앗 픽스처 넷(`boon.normal/long`, `boon_spells.*`)과 `run.growth._offer`에 쓰는 줄(290행)을 지운다.

**지킬 것**: 코어·데이터·`chapter1/app/` 무수정. 화면 파일·어댑터는 3절 규칙. 골든 불변. 다른 화면(장비·결과·메뉴)의 코드 경로를 바꾸지 않는다.

**끝 기준**(모두 본 저장소가 아니라 작업 폴더에서 돌리고, 결과 줄을 보고서에):
- `python tools/dev/equiv.py --base <S1 직전 커밋> --primary frost,ember,arc --until 2400` → `EQUIV IDENTICAL`.
- `python tools/dev/equiv.py --base <같은 커밋> --primary frost,ember,arc --until 2400 --game-args="--chapter1-trial=spells --chapter1-profile-off"` → `EQUIV IDENTICAL`. (노드 경로가 피할 수 없이 달라지면, 다른 줄 하나하나를 보고서에 적고 위치·크기·글·보임이 같다는 근거를 붙인다. 판정은 tech-lead.)
- `python tools/dev/screen_contract_check.py` → `screens 1`, 실패 0.
- `python tools/dev/run_all.py --quick` + 골든(`--only golden-all`) → 통과.
- `scene_shot.gd --contract=growth_choice`로 네 변형 × 1280×720·1920×1080 캡처, 그리고 같은 변형의 S1 전 캡처(`--scene=boon…`)와 `shot_review.py`로 나란히. 보고서에는 “캡처만 있음”으로 적는다(직접 보는 것은 art-lead·디렉터).
- `modal_input_check.gd`(꺼진 판, `--run-spells=on`) 통과.

**건드리지 않음**: `chapter_hud.gd`의 메뉴·장비·결과·흐름 창 부분, `combat_bar.gd`, 코어.

### S2 — 첫 화면(겸 캐릭터 선택)을 새 구조로 옮기기 (refactor-architect, `chapter_hud.gd` 점유, S1 병합 뒤)

**지금 이 창을 짓는 곳 [봄]**: `_build_modal__cloister`의 `"menu"` 갈래(177~191행), `_build_modal__chapter`·`_build_modal__q40`의 메뉴 추가분(보관함 단추·프로필 줄 — 직접 읽어 확인), `_build_modal__q41`·`_build_menu41`(1057~1161행: 자식 번호 0~6으로 옛 상자를 뜯어 다시 붙임, 살아 있는 초상), `_build_modal__q45`의 단추 글 교체(1198~1201행), `_build_witch_summary`·`_refresh_witch_summary`·`menu_select_skill`(1634~1686행), `_sync_portrait`·`_fit_menu_portrait`(1043~1055행).

**할 일**: S1과 같은 방식. 계약 판 1의 필드는 지금 그리는 것만(제목·설명·조작 줄·안내, 시작 셋(`ref`=시작 기술 id, 이름 줄, 요약 줄, `element`), 고른 마녀 번호, 마녀 요약(이름·레벨·경험치 글·막대 비율·포인트·트리 단추 보임), 흔들림 토글 값, 보관함 단추와 프로필 줄, 범위 줄, 임시 그림 안내). `app_state`로 `profile_state`·`character_views`·고른 번호·`temporary_art`·`motion_enabled`·`profile_note`를 받는다. 신호: `start(skill_ref)`, `witch_focused(index)`, `stash()`, `skill_tree(character_ref)`, `mute()`, `motion(enabled)`. 살아 있는 초상은 화면이 가진 부품으로 두고 그림 경로는 자리표로.
`chapter_one.gd` `menu_character_id()`(449~456행)의 사적 필드 읽기(`hud.get("_menu_witch")`) 대신 호스트에 공개 `menu_character_id()`를 두어 앞 갈래(`has_method`)가 늘 쓰이게 하고 뒤 갈래를 지운다(앱에서 고치는 것은 이 함수뿐).
`summaries`처럼 화면에 박힌 수치 글(1133행 “기본 피해 12 · 화염탄 1발” 등)은 어댑터로 옮기기만 한다(데이터에서 만드는 일은 디자인 ⑤ 뒤).
픽스처: `title.<변형>` — `normal`(저장 없음), `long`, `saved`(레벨·포인트 있음), 마녀별 `ember`·`frost`·`storm`(고른 번호만 다름). 옛 `fixtures/ui/title.*.json`과 `scene_shot`의 코어 씨앗 `title` 장면을 지운다.

**지킬 것**: S1과 같음. 저장 흐름(거부 안내·새로 시작·저장 없이 하기)의 신호와 순서를 바꾸지 않는다 — 이 창 위에 뜨는 흐름 창은 호스트에 그대로 둔다.

**끝 기준**: S1과 같은 줄(`equiv.py` 두 번 — 메뉴 순간은 `menu`·`stash` 덤프가 본다 [봄: `hud_dump.gd` 438~447행]), 더해서 `python tools/dev/run_all.py --only profile-all` 통과, `portrait_select_shots.gd`로 세 마녀 × 두 해상도 캡처 전후 비교(“캡처만 있음”).

## 6. `chapter_hud.gd` 동시 수정을 막는 규칙

1. **점유 표시**: `chapter_hud.gd`를 고치는 묶음은 시작할 때 `docs/DIRECTIVES-LEDGER.ko.md`의 해당 줄에 “파일 점유: chapter_hud.gd”를 적고, 병합 뒤 지운다. 디렉터는 점유 중에 같은 파일을 고치는 지시를 배정하지 않는다.
2. **점유 중 다른 담당의 화면 일**은 새 파일에만 쓴다(`screens/`, `contracts/`, 부품). 호스트에 한 줄을 이어야 하면 그 줄을 보고서에 “호스트에 넣을 줄”로 적어 점유 묶음 뒤에 넣는다.
3. 묶음 하나는 한 화면. S1과 S2를 한 패치로 합치지 않는다(동작 불변 판정이 화면 단위여야 원인을 가린다).
4. 점유 묶음 동안 tech-lead는 `git log -- chapter1/view/hud/chapter_hud.gd`로 다른 커밋이 없는지 검수 때 본다.

## 7. 코어의 화면 계약 본보기와 맞추기

- `growth.card_contract(card)`(`run_growth.gd` 438행~)와 `run_spells_view().offer`는 **코어의 읽기 전용 원료**다. 어댑터는 이것을 읽어 화면 계약을 만든다. 화면이 이것을 직접 읽지 않는다. 원료의 키 이름(`pair_links`, `changed{before,after}`, `prefer_i0` 등)을 화면 계약에 그대로 노출하지 않고, 그린 결과의 꼴(“조합 줄 글”, “전후 값 줄”)로 바꾼다 — 코어가 키를 바꿔도 어댑터만 고친다(하네스 2.2).
- 전투 기록(`run_record_view`, `run_record.gd` `_build_summary`)은 이미 “앱이 만든 Dictionary를 받는 화면”이다. 다음에 이 화면을 하네스로 옮길 때 같은 규칙(스키마·판 번호·픽스처 폴더)으로 등록만 하면 된다. 지금 `fixtures/ui/combat_record.*.json`은 그 꼴이라 S1·S2 범위 밖에서 그대로 둔다.
- 코어가 새 원료를 낼 때(D13의 은총 등급·기연, D14의 강림)는 원료 함수 이름을 `<무엇>_view()` 또는 `<무엇>_contract()`로 하고 머리 주석에 키를 적는다(지금 두 본보기와 같게). 화면 계약은 그 위에 어댑터가 만든다.

## 8. 성능 조건

- 성장 선택·첫 화면: 계약은 창을 다시 짓는 순간에만 만든다(호스트의 서명 변화). 프레임마다 어댑터를 부르면 실패로 본다 — S1·S2 보고서에 “어댑터 호출 수”를 `print` 한 번 세어(시험 중에만) 적는다: 한 판의 성장 선택 수와 같아야 한다.
- 전투 HUD(뒤 묶음): 3절의 `fill` 규칙과 `frame_probe.gd` 전후 +0.1ms.
- 화면 파일은 `_process`를 갖지 않는다(움직임은 Tween이나 부품의 것). 살아 있는 초상은 지금처럼 메뉴가 보일 때만 돈다(`_sync_portrait`).

## 9. 디렉터가 정할 것(하네스 9.2)과 권고

| # | 정할 것 | 권고 |
|---|---|---|
| 1 | 계약·어댑터·화면 파일의 자리와 이름 | 1절 표대로. 하네스와 다른 두 곳(스키마를 `chapter1/tests/contracts/`, 새 픽스처를 `fixtures/contracts/`)을 받아 하네스 문서를 고친다. 까닭: 빌드에 검사용 파일을 싣지 않고, 옛 씨앗 픽스처와 이름이 부딪치지 않게 |
| 2 | 화면 줄 동시 수, `chapter_hud.gd` 순서 | 디자인 단계(①~④)는 둘 함께. 구현(⑥)은 한 번에 하나(6절). 순서는 **성장 선택 먼저**: 창 하나의 갈래에 모여 있고 코어 원료(`card_contract`)가 이미 있으며, 첫 화면은 앱(`menu_character_id`)·초상·저장 흐름이 얽혀 더 크다. 하네스의 “첫 화면 먼저” 권고와 다르다 |
| 3 | T1 4번(옛 층 정리)과의 순서 | S1·S2가 그 화면의 옛 층을 지우는 일을 겸한다. T1 4번의 남은 목록에서 두 화면 몫을 지운다 |
| 4 | T-1~T-5 배정과 차례 | T-1 = S0-a(manager-tools), T-2 = S0-b(qa-perf), 둘 다 지금. T-4(비교판, manager-tools)는 ④ 전. T-3(연속 캡처)·T-5(픽스처 입력)는 qa-perf, ⑦ 전. T-3의 영상 묶기는 하지 않고 띠 PNG만(ffmpeg가 이 기계에 있는지 확인하지 않았다 [미확인]; `test_audio_tools.py`가 없을 때 건너뛰는 것으로 보아 없을 수도 있다) |
| 5 | 요청 필드 장부 | 지시 장부(`DIRECTIVES-LEDGER`)의 둘째 표. 화면 목록(T-6)은 화면 줄이 셋 이상일 때 |
| 6 | 결정 번호 | 하네스 채택과 이 구조를 결정 하나로 묶어 다음 빈 번호(하네스가 적은 N74, `decision_ledger.py`로 다시 확인)를 붙인다. 이 문서의 1·3절이 그 내용 |

## 10. 확인하지 못한 것

- Godot를 돌리지 않았다. `apply`라는 이름이 `Control`의 기존 메서드와 겹치지 않는다는 것은 Godot 4.5 API 기억에 기댄 판단이다 [미확인] — S0-b가 첫 픽스처로 확인한다.
- `spell_card.gd`가 코어에서 읽는 값의 전체 목록은 이 문서에서 다 세지 않았다(35·68행만 봄). S1의 1번 일이다.
- `_build_modal__chapter`·`_build_modal__q40`이 메뉴에 더하는 노드를 줄 단위로 읽지 않았다. S2가 먼저 읽는다.
- `hud_dump.gd`의 `_choice_moment`(601~610행)는 처음 두 성장 선택에서만 `choice-1`·`choice-2`를 덤프한다 [봄]. 그래서 `equiv.py`의 동작 불변은 성장 선택 두 번만 본다. 카드 넷 같은 드문 경우는 픽스처 캡처 비교(`shot_review.py`)가 맡는다.
