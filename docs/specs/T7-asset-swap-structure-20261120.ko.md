# 기술 지시서 T7 — 에셋을 바꿔 끼울 때 고칠 곳이 가장 적게 되는 구조

작성: tech-lead, 2026-11-20. 구현 안 함. Godot·회귀를 돌리지 않고 Grep, `_local/refactor-map/refmap.*`, 파일 읽기로만 셌다.
표기: [확인] 파일·Grep으로 직접 본 것 / [추정] 코드를 읽고 짐작한 것(실행으로 확인 안 함) / [미확인] 보지 못한 것.

사용자 지시(원문, 2026-11-20): "원장은 어차피 다 바꿀 거야. 개발 계속 진행. 다만 원장 변경되었을 때 최소한으로 변경이 가능하게 구조 작성."
받는 명세 절: 이 문서. `CLAUDE.md` "점검 절차"의 마지막 줄(에셋은 모두 바뀔 것이다)을 구체화한다.

---

## 1. 디렉터용 요약 한 장

**목표 상태**: 에셋 하나를 바꾸는 일 = ① 파일을 넣고 ② 자리표(`chapter1/art/asset_slots.json`) 한 줄을 고치고 ③ 점검을 돌린다. 코드는 고치지 않는다.

**지금**: 실행 때 쓰이는 코드 파일 11개와 JSON 11개, `project.godot`에 에셋 경로가 박혀 있다. 경로보다 더 큰 문제는 **에셋의 모양에 기대는 숫자와 이름**이다. 뼈 이름 문자열이 `chapter_actors.gd` 한 파일에만 50곳 넘게 있고, UI 아틀라스 좌표 37조각이 코드 상수이며, 지형의 "풀" 판정은 파일 이름(`ends_with("cloister_foliage_v01.png")`)으로 한다. 그래서 같은 이름으로 파일만 덮어써도 모델의 뼈·클립 이름이나 시트 배치가 다르면 깨진다.

**좋은 소식**:
- 코어와 골든은 에셋을 모른다. `chapter1/core/`에 에셋 경로 0건, `golden_core.gd`는 코어·자동 조작·문자 검사기만 로드한다. [확인]
- 이미 반쯤 있는 간접 층이 있다. 2D 시트(`actors/*.json`), 소품 아틀라스(`quality03/cloister_*_v01.json`), 살아 있는 초상(`living_portrait/*.json`)은 칸 좌표·발 위치·뼈대 기준점을 곁 파일(JSON)에 둔다. 소리는 SD1(`audio_map.json`)이 같은 일을 하기로 계획되어 있다. [확인]
- 런타임 폴더 훑기(DirAccess)로 에셋을 찾는 곳은 0건이다(지도의 20건은 모두 저장·검사). [확인]
- 전투 효과에는 텍스처 에셋이 없다(모두 셰이더). 효과를 "바꾸는" 일은 코드 작업이고 이 구조의 대상이 아니다. [확인]

**권고(작은 안)**: 파일 셋을 새로 만들고 기존 도구 셋을 넓힌다.
1. 자리표 `chapter1/art/asset_slots.json`: 뜻 id(`actor.walker.model`) → 파일 경로, 곁 파일, 계약(뼈·클립 대응, 배율, 크기, 필수 조각 이름).
2. 해결기 `chapter1/view/assets/asset_slots.gd`: 코드는 id로만 부른다. 파일이 없으면 대체물을 쓰고 기록한다.
3. 검사 `chapter1/tests/test_asset_slots.gd`(Godot에서 실제 로드해 계약 확인) + `asset_intake.py --slot`(넣기 전 대조) + `asset_ledger.py check`(자리표와 원장 대조).
소리는 SD1의 `audio_map.json`이 자리표 구실을 하므로 따로 만들지 않는다. 원장과 자리표는 **합치지 않고** 경로로 잇는다(3.2).

**첫 묶음**: T7-0 "실제로 로드되는 에셋 목록"(qa-perf, 반나절 규모) — 출처 미확인 2D 스프라이트 11개 가운데 상당수가 **로드는 되지만 그려지지 않거나 아예 로드되지 않는 것**으로 보인다[추정]. 그렇다면 바꿀 것이 아니라 빼면 된다. 그 뒤 T7-1(해결기·자리표)과 T7-2(도구)를 병렬로.

**디렉터가 정할 것**(9절): 자리표 위치, 원장과의 관계, 안 쓰는 에셋을 내보내기에서 뺄지, T1 4번(옛 층 정리)과의 순서, 이름(slot 충돌).

---

## 2. 진단 — 지금 에셋은 어떻게 불리는가

### 2.1 세는 법

- 대상: 게임 실행 때 로드되는 코드(`chapter1/app/`, `chapter1/view/`, `chapter1/presentation/`)와 그 코드가 읽는 JSON. 옛 층 파일(`chapter1/view/` 바로 아래 `cloister_*.gd`, `chapter_world*.gd`)은 따로 적는다(아래 2.4).
- "경로" = `res://chapter1/art/` 리터럴, 폴더 상수 + 파일 이름 조립, JSON의 경로 칸.
- "모양" = 에셋이 바뀌면 함께 맞아야 하는 숫자·이름(뼈, 클립, 배율, 칸 좌표, 앵커, 변주 수, 글꼴 축 등).
- 지도(`refmap.md`)의 불확실 항목 가운데 에셋 관련: 동적 경로 조립 38건 중 실행 코드의 에셋 폴더 상수 5건(`combat_audio.gd:6`, `chapter_actors.gd:84`, `living_portrait.gd:38`, `ui_style.gd:13`, `world/chapter_world.gd:20`), `load(변수)` 36건 중 실행 코드의 에셋 로드 12건, 폴더 훑기 20건 중 에셋 0건. [확인]

### 2.2 종류별 진단 표

| 종류 | 파일(지금) | 경로가 박힌 곳 | 모양이 박힌 곳 | 지금 바꿀 때 고칠 파일 | 실행 때 쓰임 |
|---|---|---|---|---|---|
| 주인공 3D | `rigged_mage/v01/mage_animated.glb` | `chapter_actors.gd:441` 상수 1 | 배율 1.32(`:444`), 뼈 이름 2(`hand_cr_r`, `finger_middle.01.r`, `:476`), 상체 판정 뼈 접두 8개(`:507`), 클립 idle·run·cast·hit·death | 코드 1 + `.import` | 쓰임 [추정, 코드 경로상 `_create__rigged`의 hero 분기] |
| 사슬 악마 몸(원거리·돌진·정예·우두머리 공유) | `chained_warden/v01/chained_demon_animated.glb` | `chapter_actors.gd:639` 상수 1, 로드 `:652`·`:872`, 경로 비교 `:1228` | 배율 6곳(`:652` 1.15, `:872` .80/.52, `:1151` 비등방 두 벡터, `:1533` .52), 뼈 이름 리터럴 42회(Spine1~3, Head, Hand.R, Shoulder.L/R, Arm.L/R, Neck.001, 손가락 사슬), 클립 idle·walk·windup_slam·windup_fan·slam·fan·hit·death, 표면 하나로 합치는 재질(`Minion19Batched`, `:1061`·`:1102`) | 코드 1 | 쓰임 [추정] |
| 해골 무법자(walker) | `skeleton_outlaw/v02/skeleton_outlaw_merged.glb` | `chapter_actors.gd:1663` preload, `vat/walker_vat_spec.gd:5` — **같은 경로 둘** | `ORG-*` 뼈 이름 32회(actors 15, vat_spec 15, walker_crowd 2), 클립 idle·walk·attack_slam·death·hit, 시간 상수(`WALK34`·`SWING34`·`STRIKE34`, 맞음 46/60초)가 actors와 vat_spec에 **복사본**, 머리 배율 .72 두 곳, 몸 배율 .62 | 코드 3 | 쓰임 [추정] |
| 2D 행동 시트 | `actors/{hero,walker,ranged,charger,elite}{,_actions}.png` 10 + `battle_mage_walk_4x4_v01.png` + `quality03/hero_cast_v01.png` | 조립 2(`chapter_actors.gd:72`·`:84`), JSON의 `texture` 칸 약 162(시트 JSON 5개 × 29, hero_cast 17) | 칸 좌표·발 위치·ppm은 JSON에 있음(좋음). 코드는 상태 cast·hit·death, 방향 south·east·north·west를 기대(`:77`·`:98`) | JSON 최대 6 | **hero 시트와 hero_cast는 로드 안 됨**(`_load_sprite`가 hero를 건너뜀, hero_cast는 hero 정의가 있어야 읽음) [추정]. 적 시트 4종은 셋업 때 로드되지만 보이는 몸은 3D 모델로 대체 [추정]. `battle_mage_walk_4x4_v01.png`는 참조 0 [확인, 지도] |
| 주인공 원화 | `characters/{frost,ember,storm}_witch_v02.png` | `skill_tree_panel.gd:31-33` 3 | 얼굴 자르기 `Rect2` 3개(같은 줄), 도구 쪽 앵커 `tools/art/portrait_slots.json` | 코드 1 + 도구 데이터 | 스킬 트리 화면 |
| 살아 있는 초상 | `portraits/<마녀>/layers/*.png`, 눈 2장씩 (37) | `living_portrait.gd:38` 설정 폴더 + `id.json`, 설정 JSON의 `layer_dir`·눈 경로 3칸 × 3 | 캔버스 1024×1536, 뼈대 기준점(y_hip, y_chest, split_x, neck), 겹마다 y0·y1·무릎·발목, 눈 위치 — **모두 JSON**(좋음). 겹 id = 파일 이름. 코드의 `WITCHES` 목록과 겹 종류의 뜻(static·field·cloth·head·spring)은 코드·셰이더 | JSON 3 | 메뉴 초상 |
| 초상 효과 그림 | `view/hud/living_portrait/flake_{disc,rings}.png` | `snowflake_fx.gd:7-8` preload 2 | — | 코드 1 | 쓰임. **`chapter1/art/` 밖이라 원장에 없음** [확인] |
| UI 키트 | `ui/kit/` PNG 6 | `ui_style.gd:13` 폴더 + 파일 이름 4곳(`:64`, `:178`, `:183`, `:245`) | **아틀라스 37조각 좌표가 코드 상수**(`:15-51`, `build_kit.py`가 출력한 것을 손으로 붙임), 9조각 여백(`:178`·`:183`·`:245`), AtlasBox 여백(`:202`·`:212`·`:234`), 키트 밀도 `CODE = 1/2.4`(`:53`), 액체 셰이더의 UV 가정(`:98-131`). 조각 이름 사용: combat_bar 19, chapter_hud 10 | 코드 1(조각 이름·배치가 같을 때) | 쓰임 |
| 장비 아이콘 | `equipment_icons35/*.svg` 7 | `equipment_sigil_quality35.gd:4-10` preload 7(장비 칸 이름이 키) | 정사각 가정 | 코드 1 | 쓰임 |
| 지형·소품 | `quality03/ground_{flagstone,soil}_v01.png`, `cloister_{props,foliage}_v01.{png,json}` | `world/chapter_world.gd:20` 폴더 + 파일 이름 12줄(`:94`, `:102-103`, `:109`, `:155`, `:302`, `:396`, `:403`, `:487`, `:604`, `:782-783`) | **파일 이름이 분류 표지**(`ends_with("cloister_foliage_v01.png")`, `:155`·`:403`), 소품 id 문자열 12종 39회(pillar_whole 7, pillar_broken 9, arch 5, wall 4 …), 칸 좌표·발·높이는 JSON(좋음), 지면 셰이더가 두 텍스처(돌·흙) 역할을 기대 | 코드 1 + JSON 2 | 쓰임 |
| 전투 효과 | 텍스처 없음 | — | 셰이더 코드(`chapter1/view/*.gdshader`) | (코드 작업) | — |
| 소리 | `quality03_audio/*.wav` 22 | `combat_audio.gd:6` 폴더 + `cue_%d.wav` 조립(`:29`), `ambience.wav`(`:36`) | 변주 수 `COUNTS` 13큐, 이득·쿨다운, 음높이 세 값, 앱의 큐 이름 19곳(`chapter_one.gd`), **환경음 반복 끝 = `data.size()/2`(16비트 모노 가정, `:38`)** | 코드 1~2 | 쓰임. SD1이 `audio_map.json`으로 옮길 계획 |
| 글꼴 | `fonts/PretendardVariable.ttf`, `NotoSerifKR-VF.ttf` | `loc.gd:289-290` 2, `project.godot:19` 1 | 가변 축 `wght` 필요, 숫자는 `tnum`, 글자 범위는 `tools/dev/check_glyphs.py`가 검사 | 코드 1 + 설정 1 | 쓰임 |

합계(실행 코드): 경로가 박힌 코드 파일 11개(`chapter_actors.gd`, `walker_vat_spec.gd`, `walker_crowd.gd`, `combat_audio.gd`, `equipment_sigil_quality35.gd`, `loc.gd`, `skill_tree_panel.gd`, `ui_style.gd`, `world/chapter_world.gd`, `living_portrait.gd`, `snowflake_fx.gd`), 경로가 든 JSON 11개, `project.godot`. 모양 숫자가 가장 많이 모인 곳은 `chapter_actors.gd`(2,076줄)다. [확인]

### 2.3 검사·도구가 에셋에 기대는 곳

- `chapter1/tests/`: 에셋 경로 리터럴 0건. [확인]
- `chapter1/tests/hud_dump.gd:232`·`:270`: 덤프에 `TextureRect`의 텍스처 경로와 셰이더 경로를 적는다. **파일을 옮기면 덤프 해시가 바뀐다**(화면이 같아도). 그래서 구조 작업 묶음은 파일을 옮기지 않는다. [확인]
- 도구: `tools/manager/catalog.py`(에셋 목록, 사용 판정), `tools/dev/check_build.py:143-157`(아트 폴더 JSON의 "참조 없음" 판정을 `.gd` 본문 검색으로 함), `tools/dev/refactor_map.py`(참조 지도), `tools/dev/run_all.py:65`, 소리 도구 셋(`audio_measure.py` 등은 `quality03_audio` 기본값), `tools/manager/test_backend.py`(**실제 에셋 파일을 표본으로 씀**: `hero.png`, 사슬 악마 glb, `frost_witch_v02.png`, `ground_flagstone_v01.png`, `fire_0.wav`), `tools/dev/make_living_portrait_flake.py`(원화를 읽음). [확인]
- 경로를 JSON으로 옮기면 `check_build.py`·`refactor_map.py`·`catalog.py`가 모든 에셋을 "참조 없음"으로 보게 된다. 도구를 먼저 넓혀야 한다(T7-2). [확인: 세 도구 모두 코드 본문 검색 방식]
- 내보내기: 세 프리셋 모두 `export_filter="all_resources"`. 문자열로만 부르는 파일도 들어간다. 반대로 **안 쓰는 에셋(출처 미확인 시트 포함)도 지금 배포 묶음에 들어간다**. [확인]

### 2.4 옛 층과 겹치는 곳

- 옛 층 파일에도 경로 리터럴이 있다: `cloister_actors.gd:53`·`:65`, `cloister_world_quality03.gd:6`·`:77`·`:92`, `chapter_world.gd:32`(view 바로 아래), `chapter_world_quality10.gd:19`·`:25`, `quality17.gd:22`, `quality22.gd:62`. [확인]
- T1 4번 R1(`chapter_one.gd:7-11`의 옛 층 preload 제거)은 아직 안 되었다(지금도 7~11행에 있다). [확인] 옛 층 인스턴스가 실제로 에셋을 로드하는지는 [미확인] — 생성 직후 버려지므로 `setup`이 불리지 않는다고 본다[추정].
- 이 문서의 묶음은 **옛 층 파일을 고치지 않는다**. 그 안의 경로는 T1 4번 R3 뒤 디렉터가 지울 때 함께 사라진다.

### 2.5 이미 있는 간접 층과 빠진 것

| 있는 것 | 넓히면 되는 것 | 없는 것 |
|---|---|---|
| 2D 시트·소품 아틀라스·초상의 곁 JSON(칸, 발, 기준점) | 곁 파일 관례를 UI 아틀라스(`hud_atlas.json`)에도 적용 | id → 파일 대응표(코드가 경로를 직접 조립) |
| `outfits.json`의 `"art": {}` 칸(비어 있음, 프로필은 id·소유만 읽음) | 의상 그림이 생기면 이 칸에 자리 id를 적는다 | 빠진 파일 처리 규칙(시트는 없으면 도형으로 대체하지만 모델·UI·소리는 오류 또는 충돌) |
| `asset_intake.py`(GLB 머리 읽기, 뼈·클립·삼각형 수, 예산표 `asset_budget.json`) | `--slot id`로 자리 계약과 대조 | 뼈·클립의 "이름" 계약(지금은 개수만 셈) |
| `asset_ledger.py`(경로 키 출처 원장 104항목) | 자리표·`audio_map.json`과 대조 | 어떤 파일이 어떤 자리에 쓰이는지 |
| `check_glyphs.py`(글꼴 글자 범위) | 자리표의 글꼴 계약에서 부름 | — |
| `tools/art/portrait_slots.json`(원화 앵커와 자르기 자리, A6 8.7) | 자르기 결과물이 자리 id(`portrait.<마녀>.<자리>`)가 되게 | — |
| `.import` 설정 | 계약의 `import` 칸으로 필요한 값만 대조 | — |
| SD1 계획 `audio_map.json`(S1 5절) | 소리의 자리표로 그대로 씀, 계약 칸 둘 추가(6.7) | 아직 파일 없음 [확인] |

`loot.json`에는 아이콘 대응이 없다(데이터 폴더 Grep 0건). 장비 아이콘은 장비 칸 이름으로 코드에서 고른다. [확인]

---

## 3. 목표 구조

### 3.1 원칙

1. **코드는 뜻 id로 부른다.** `res://chapter1/art/` 문자열은 해결기와 자리표에만 있다.
2. **모양은 데이터에 둔다.** 무거운 모양(칸 좌표, 프레임, 초상 기준점)은 에셋 옆 곁 JSON(이미 하는 방식), 가벼운 계약(배율, 뼈·클립 대응, 필수 이름, 크기)은 자리표의 `contract` 칸.
3. **계약 칸은 코드가 읽거나 검사가 확인하는 것만** 둔다. 아무도 읽지 않는 칸은 만들지 않는다.
4. **파일이 없어도 개발 실행은 죽지 않는다.** 눈에 띄는 대체물과 기록. 배포 빌드에서는 대체물 사용이 실패다.
5. **표현만의 일.** 코어·데이터(`chapter1/data/`)·골든은 바뀌지 않는다.

### 3.2 자리표와 원장의 관계 — 권고: 따로 두고 경로로 잇는다

| | (가) 따로 두기 [권고] | (나) 원장 항목에 `slot`을 단다 |
|---|---|---|
| 단위 | 원장 = 파일 하나(출처), 자리표 = 뜻 하나(쓰임) | 파일 하나 |
| 맞는 경우 | 한 자리에 파일 여럿(초상 겹, 소리 변주), 한 파일이 여러 자리(아틀라스, 공유 몸) | 1:1일 때만 |
| 실행 때 | 자리표만 읽음(작은 파일) | 출처 글·프롬프트 전문이 든 원장을 게임이 읽음 |
| 고치는 사람 | 자리표는 사람이 한 줄 고침, 원장은 도구(`add`)가 해시와 함께 씀 | 둘이 한 파일을 고쳐 충돌 |

(가)의 이음: `asset_ledger.py check`가 자리표와 `audio_map.json`이 가리키는 파일이 원장에 있는지(없으면 **경고**, 지금은 출처 구멍이 개발을 막지 않으므로 오류가 아님), 원장 파일 중 어느 자리에도 없는 것을 "자리 없음(안 쓰임 후보)"으로 낸다. 원장은 고치지 않는다.

### 3.3 자리표 `chapter1/art/asset_slots.json`

- 위치 권고: `chapter1/art/`(원장 옆, 아트 담당이 고침, 경로 기준이 원장과 같은 `chapter1/art` 상대). 대안은 `chapter1/data/`(9절 결정 1).
- `file`·`meta`는 `chapter1/art/` 기준 상대 경로. 예외로 `res://`로 시작하면 그대로 쓴다(지금 `view/` 안에 있는 초상 설정·눈송이 그림용). 검사는 `art` 밖을 경고로 낸다.
- id 문법: `<종류>.<대상>.<부분>`. 종류는 `actor`, `portrait`, `illustration`, `ui`, `icon`, `world`, `fx`, `font`(소리는 `audio_map.json`의 큐 id). 대상은 코어 id에서 온 이름(`walker`, `frost`, 장비 칸 `weapon`)을 그대로 쓴다.
- `kind`: `model`, `sprite_sheet`, `texture`, `atlas`, `nine_slice`, `portrait_rig`, `prop_atlas`, `font`. 검사가 kind마다 볼 것을 정한다(3.5).

모양(초안, T7-1에서 확정하되 아래 칸 이름은 바꾸지 않는다 — T7-2가 같은 꼴을 읽는다):

```json
{
  "schema": 1,
  "about": "뜻 id -> 파일과 계약. 코드는 id로만 부른다. 경로는 chapter1/art 기준(res:// 로 시작하면 그대로). 출처는 ASSET-LEDGER.json, 소리는 chapter1/data/audio_map.json.",
  "slots": {
    "actor.walker.model": {
      "kind": "model",
      "file": "skeleton_outlaw/v02/skeleton_outlaw_merged.glb",
      "fallback": null,
      "contract": {
        "scale": 0.62,
        "bones": {"spine": "ORG-spine", "chest": "ORG-chest", "neck": "ORG-neck", "head": "ORG-head",
                  "shoulder_l": "ORG-shoulder_L", "upper_arm_l": "ORG-upper_arm_L", "forearm_l": "ORG-forearm_L",
                  "shoulder_r": "ORG-shoulder_R", "upper_arm_r": "ORG-upper_arm_R", "forearm_r": "ORG-forearm_R"},
        "bone_groups": {"hit": ["spine","chest","neck","head","shoulder_l","upper_arm_l","forearm_l","shoulder_r","upper_arm_r","forearm_r"],
                        "hit_exclude": ["neck","head"], "tracked": ["spine","head"]},
        "clips": {"idle": "idle", "walk": "walk", "attack": "attack_slam", "death": "death", "hit": "hit"},
        "timing_s": {"walk_cycle": 0.9333, "swing": 1.1333, "strike": 0.4167, "hit": 0.7667},
        "pose": {"head_scale": 0.72},
        "budget_profile": "enemy"
      }
    },
    "actor.walker.sheet": {"kind": "sprite_sheet", "file": "actors/walker.png", "meta": "actors/walker.json",
      "contract": {"states": ["cast","hit","death"], "directions": ["south","east","north","west"]}},
    "ui.hud.atlas": {"kind": "atlas", "file": "ui/kit/hud_atlas.png", "meta": "ui/kit/hud_atlas.json",
      "contract": {"px_per_code": 2.4, "pieces_required": ["orb_frame","orb_empty","…37개"], "import": {"mipmaps/generate": true}}},
    "ui.window": {"kind": "nine_slice", "file": "ui/kit/window_96.png", "contract": {"margin": 40, "content": [44,44,44,44]}},
    "icon.equip.weapon": {"kind": "texture", "file": "equipment_icons35/weapon.svg", "contract": {"square": true}},
    "illustration.frost": {"kind": "texture", "file": "characters/frost_witch_v02.png",
      "contract": {"size": [1024,1536], "crops": {"face": [295,5,300,300]}}},
    "portrait.frost.rig": {"kind": "portrait_rig", "file": "res://chapter1/view/hud/living_portrait/frost.json",
      "contract": {"canvas": [1024,1536], "eyes": true}},
    "world.props.cloister": {"kind": "prop_atlas", "file": "quality03/cloister_props_v01.png", "meta": "quality03/cloister_props_v01.json",
      "contract": {"group": "stone", "ids_required": ["pillar_whole","pillar_broken","arch","wall","…"]}},
    "font.body": {"kind": "font", "file": "fonts/PretendardVariable.ttf", "contract": {"axes": ["wght"], "features": ["tnum"]}}
  }
}
```

- 코드는 **논리 이름**(`head`, `attack`, `strike`)만 쓰고 실제 이름은 계약에서 얻는다. 새 모델의 뼈 이름이 달라도 대응만 고치면 된다.
- 곁 파일(`meta`)은 지금 있는 JSON을 그대로 쓴다. 새로 생기는 곁 파일은 `ui/kit/hud_atlas.json` 하나(`build_kit.py`가 씀).

### 3.4 해결기 `chapter1/view/assets/asset_slots.gd`

`extends RefCounted`, 정적 함수만. 표는 처음 부를 때 한 번 읽고 캐시한다.

```gdscript
static func path(id: String) -> String          # 실제 res:// 경로(대체물을 썼으면 대체 경로). 자리 없음 = ""
static func contract(id: String) -> Dictionary  # 계약 칸(사본)
static func meta(id: String) -> Dictionary      # 곁 JSON 파싱 결과(캐시)
static func texture(id: String) -> Texture2D    # 없으면 대체물
static func scene(id: String) -> PackedScene    # 없으면 fallback 파일, 그것도 없으면 대체 장면
static func font(id: String) -> FontFile
static func bone(id: String, logical: String) -> String   # 계약 bones 대응, 없으면 ""
static func clip(id: String, logical: String) -> String   # 계약 clips 대응, 없으면 logical 그대로
static func missing() -> Array[String]          # 대체물을 쓴 자리 id
```

- 개발용 덮어쓰기: `--chapter1-asset-slots=<경로>`는 `res://_local/` 아래만 허용(`chapter_one.gd:108`의 캡처 폴더 규칙과 같음). 저장소를 고치지 않고 "이 파일로 바꾸면 어떻게 되나"를 시험한다. 해결기가 `OS.get_cmdline_user_args()`를 직접 읽는다(`chapter_one.gd`를 고치지 않으려고).
- 처음 대체물을 쓸 때 `push_warning` 한 번, 그리고 첫 로드 때 `CHAPTER1_ASSETS {"table":…, "slots":N, "missing":[…]}` 한 줄을 찍는다(덤프·로그로 확인용).

### 3.5 대체물과 빠짐 처리

| kind | 파일 없음 | 계약 불일치(뼈·클립·조각 없음) |
|---|---|---|
| texture, sprite_sheet, atlas, nine_slice | 64px 자홍·검정 바둑판(코드로 생성, 한 번만). 시트는 지금처럼 도형 몸으로 | 없는 조각은 바둑판 조각으로 그림 |
| model | `fallback` 파일(같은 계약을 채우는 지금 모델). 그것도 없으면 자홍 캡슐 + 리그 작업 건너뜀 | 없는 뼈 = `""` → 그 뼈에 기대는 꾸밈(지팡이 붙임, 손 빛, 맞음 흔들림)을 건너뜀. 지금의 `assert(index>=0)`는 배포 빌드에서 빠져 뒤에서 충돌하므로 이 분기로 바꾼다 |
| portrait_rig | 초상 자리를 비우고 원화 정지 그림(있으면) | 없는 겹 파일은 건너뜀 |
| font | 다른 번들 글꼴(본문↔제목). 둘 다 없으면 오류(글자를 못 그림) | 축 없으면 굵기 변화 없이 |
| 소리(`audio_map`) | 무음 + 빠짐 수 기록(SD1) | — |

배포 규칙: `store` 프리셋 빌드 전 검사(`test_asset_slots.gd -- --strict`)에서 대체물·fallback 사용이 1건이라도 있으면 실패. `qa` 프리셋은 경고만.

### 3.6 계약 검사 — 두 단계

1. **넣기 전**(Python, Godot 없이): `python tools/art/asset_intake.py <새 파일> --slot <id>` → 계약 칸마다 "계약 / 새 파일 / 판정" 표.
   - model: glTF의 스킨 관절 이름에 계약 `bones`의 실제 이름이 다 있는가, 애니메이션 이름에 `clips`가 다 있는가, 클립 길이 ≥ `timing_s`의 해당 값, 삼각형·뼈 수를 `budget_profile` 예산과 대조(기존 기능).
   - texture/atlas/sprite_sheet: 크기(`size`), 정사각(`square`), 알파 유무, 곁 JSON의 칸이 그림 안에 드는가, `pieces_required`·`ids_required`·`states`·`directions`가 곁 JSON에 다 있는가.
   - font: 축 목록, `tnum`, 글자 범위는 `check_glyphs.py`의 계산을 재사용.
   - `import` 칸: 새 파일 옆 `.import`가 있으면 그 값과 대조(없으면 "임포트 뒤 확인").
   - 불일치는 무엇이 다른지 이름으로 적는다(예: `bones.head: 계약 ORG-head, 새 파일에 없음. 비슷한 이름: DEF-head, head`).
2. **넣은 뒤**(Godot): `chapter1/tests/test_asset_slots.gd` — 모든 자리를 해결기로 실제 로드해 형식, 뼈·클립 존재(임포트 뒤의 이름. Godot 임포트가 이름을 바꿀 수 있어 이것이 최종 판정 [추정]), 아틀라스 조각이 텍스처 범위 안, 초상 겹 파일 크기 = 캔버스를 확인. 그리고 **코어 id 덮기**: `combat_tuning.json`의 적 종류마다 `actor.<종류>.model`, `loot.json`의 장비 칸마다 `icon.equip.<칸>`, 세 마녀마다 `portrait.<마녀>.rig`·`illustration.<마녀>`가 있는가.

### 3.7 모양을 데이터로 — 옮길 것과 남길 것

옮긴다(자리표 계약 또는 곁 JSON):
- 모델 배율 전부, 뼈 이름 전부(접두 규칙 포함: 주인공 상체 판정의 접두 8개는 `bone_groups.upper_prefixes`), 클립 이름, 시간 상수(`walker_vat_spec.gd`의 복사본을 없애고 같은 계약을 읽게).
- UI 아틀라스 좌표(곁 JSON), 9조각 여백, AtlasBox 여백, 키트 밀도.
- 원화 얼굴 자르기 `Rect2` 3개.
- 지형의 분류 표지: 파일 이름 대신 곁 JSON의 `group` 칸(`"foliage"`/`"stone"`).
- 장비 아이콘 7개의 칸 → 자리 id 대응(`icon.equip.<칸>`, 없으면 `icon.equip.charm`).

옮길 수 없는 것 — **바꿀 때 함께 고칠 것 목록**(자리표 `about` 옆이 아니라 이 절이 기준. T7-1이 `chapter1/art/README.ko.md`에 짧게 옮긴다):
1. UI 액체 셰이더(`ui_style.gd:98-131`): 구슬 조각이 원형 유리, 액체 그림이 가운데에 있다는 가정(반사 위치, 0.88 채움).
2. 초상 셰이더(`rig_body`·`rig_cloth`): 겹 종류의 뜻(천은 아래로 늘어짐, 엉덩이·가슴 높이 기준). 새 초상은 같은 겹 종류로 나눠야 한다.
3. 지면 셰이더(`chapter_ground*.gdshader`): 돌·흙 두 역할의 텍스처를 섞는다. 새 지형도 두 역할을 줘야 한다.
4. 원거리·돌진의 몸을 사슬 악마 몸을 비등방으로 눌러 만든다(`chapter_actors.gd:1151`). 역할마다 다른 모델이 오면 `_create__q21` 경로를 고쳐야 한다(코드).
5. 묶음 재질 `Minion19Batched`: 표면 하나·정점 색 가정. 재질이 여럿인 모델은 묶음이 깨진다.
6. 구운 움직임(VAT, `--chapter1-vat-walker`, 기본 꺼짐): 스킨이 있는 메시 가정. 모델을 바꾸면 다시 굽는다(자동인지는 [미확인]).
7. 글꼴: `project.godot:19`의 `theme/custom_font`(프로젝트 설정이라 해결기를 거치지 않음).
8. `.import` 설정: 같은 이름으로 덮어쓰면 유지, 새 이름이면 옛 `.import`의 필요한 값(밉맵, 필터, 압축, 모델 임포트 배율)을 옮긴다. 계약 `import` 칸이 대조한다.
9. 도구의 표본 파일: `tools/manager/test_backend.py`가 실제 에셋을 표본으로 쓴다. 표본 파일을 지우거나 이름을 바꾸면 그 검사를 고친다.
10. 원화를 바꾸면 사람이 앵커를 다시 찍는다(`tools/art/portrait_slots.json`, `portrait_anchor_table.py`), 자르기를 다시 만든다(`portrait_derive.py`), 계약 `crops`를 고친다. 초상 겹 분해(`layers_source.json`)도 새로.
11. 환경음 반복 끝 `data.size()/2`(`combat_audio.gd:38`)는 16비트 모노 가정 — SD1이 고친다(6.7).

### 3.8 묶음 교체 단위와 폴더 규칙

| 묶음 | id 접두 | 폴더(새로 들일 때) | 한 번에 바꾸는 것 |
|---|---|---|---|
| 적 한 종 | `actor.<종류>.*` | `chapter1/art/actors/<종류>/` | 모델, 텍스처, 시트, 곁 JSON, ATTRIBUTION |
| 주인공 몸 | `actor.hero.*` | `chapter1/art/actors/hero/` | 같음 |
| 마녀 한 명의 초상 한 벌 | `portrait.<마녀>.*`, `illustration.<마녀>` | `chapter1/art/portraits/<마녀>/` | 원화, 겹, 눈, 초상 설정 JSON, 자르기 결과 |
| UI 키트 | `ui.*` | `chapter1/art/ui/kit/` | 아틀라스 + 곁 JSON, 9조각 |
| 아이콘 한 벌 | `icon.equip.*` | `chapter1/art/icons/equipment/` | 칸별 그림 |
| 지형 한 벌 | `world.*` | `chapter1/art/world/<장소>/` | 지면 두 장, 소품·풀 아틀라스 + 곁 JSON |
| 소리 팩 | `audio_map.json`의 큐 | `chapter1/art/audio/<무리>/`(S1 6절 그대로) | 파일, 원장, `audio_map.json`의 해당 큐 |
| 글꼴 | `font.*` | `chapter1/art/fonts/` | 파일, 라이선스 글 |

- **새 폴더 이름에 버전 숫자를 붙이지 않는다**(`v01/`, `quality03` 같은 것). 바꿀 때는 새 폴더(`actors/walker_b/`)에 넣고 자리표 줄을 돌린 뒤, 옛 폴더를 지운다(지우기는 디렉터 결정).
- 묶음 검사는 접두로 돈다: `asset_intake.py --slot 'actor.walker.*' --dir chapter1/art/actors/walker_b/`.
- 지금 있는 파일은 **옮기지 않는다**(덤프 해시 잡음, 2.3). 실제로 바꿀 때 새 규칙의 폴더로 들인다.

### 3.9 코어·골든과의 경계 [확인]

- `chapter1/core/` 에셋 경로 0건, `golden_core.gd`는 코어·자동 조작·`core_text_probe.gd`만 로드.
- 코어가 내는 것은 id(적 종류, 기술 id, 장비 칸, 마녀 id)뿐이고, 표현이 이것으로 자리 id를 만든다. 자리 id 조립(`"actor." + kind + ".model"`)은 허용한다. 대신 3.6의 "코어 id 덮기" 검사가 빠진 자리를 잡는다.
- 예외 하나: `chapter_profile.gd`가 `outfits.json`을 읽지만 `id`·`character_id`·`default_owned`만 쓴다. `art` 칸은 읽지 않는다. 의상 그림 자리를 이 칸에 적어도 저장·코어와 무관하다. [확인, `chapter_profile.gd:134-142`]

---

## 4. 지금 당장 지킬 규칙 세 줄(구조가 다 서기 전에도)

1. **새 코드에 `res://chapter1/art/` 문자열을 쓰지 않는다.** 해결기가 생기면 `AssetSlots.texture("<id>")`로 부른다. 그 전에는 파일 맨 위 `const` 한 곳에만 경로를 두고 줄 끝에 `# slot: <id>`를 단다(나중에 Grep으로 한 번에 옮긴다).
2. **새 에셋은 `chapter1/art/<종류>/<대상>/`에 버전 숫자 없이 두고, 넣는 날 `python tools/art/asset_ledger.py add`로 원장에 올린다.** 자리표가 생기면 같은 날 그 줄도 쓴다. 게임 그림을 `chapter1/view/` 안에 두지 않는다.
3. **에셋 모양에 기대는 숫자·이름(칸 좌표, 프레임, 뼈·클립 이름, 배율, 앵커, 변주 수)은 코드에 쓰지 않고 에셋 옆 곁 JSON에 둔다.** 피할 수 없으면 파일 맨 위 상수 한 곳 + `# shape: <id>`.

---

## 5. 옮기는 차례

값어치(사용자가 먼저 바꿀 것, 새로 생길 자리)와 위험(큰 파일, 다른 작업과의 겹침)으로 줄 세운다.

```
T7-0 실제 쓰임 확인(qa-perf) ─┐
                              ├─> T7-3 모델(refactor-architect) ──> T1-4 R4의 actors 단계
T7-1 해결기·자리표(refactor-architect) ─┤
T7-2 도구(manager-tools) ───────────────┼─> T7-4 UI·아이콘·글꼴·원화 자르기(ui-hud)
                                        ├─> T7-5 초상(ui-hud)
                                        └─> T7-6 지형(refactor-architect, T1-4 R2·R4-world 뒤)
SD1(sound-designer, 이미 배정 대상) ── 6.7의 추가 두 가지만 붙인다
T7-7 교체 연습(qa-perf) ── T7-3·T7-4 뒤
```

- **T7-0 먼저**: 출처 미확인 시트 11개가 실제로 쓰이는지에 따라 할 일이 크게 준다.
- **T7-1과 T7-2는 병렬**: 파일이 겹치지 않고, 둘 다 이 문서의 자리표 꼴(3.3)만 따른다.
- **T7-2가 T7-3~6보다 먼저 들어가야 한다**: 안 그러면 경로를 JSON으로 옮기는 순간 `check_build.py`·`refactor_map.py`·`catalog.py`가 모든 에셋을 "참조 없음"으로 본다.
- **T7-3(모델)이 값어치 1순위**: 사용자가 바꾸려는 것(조건 붙은 모델: 사슬 악마 CC BY, 주인공 mage, 해골)과 Sunra로 만들 주인공 3D가 모두 여기로 들어온다.
- **T1 4번과의 순서**: T1 4번은 아직 시작 전이다(R1 미완, 2.4). `chapter_actors.gd`는 R4의 마지막 단계라, **T7-3을 먼저** 하고 R4-actors가 그 뒤에 층을 접는다. T7-3은 최상위 상수와 생성·셋업 함수 몇 곳만 고치므로 접기를 막지 않는다. 지형은 반대로 **R2·R4-world를 먼저** 한다: 층을 접으면 지면 텍스처를 부르는 7곳이 줄어 T7-6이 작아진다. 같은 파일을 두 묶음이 동시에 고치지 않는다.
- **새로 생길 자리는 처음부터 자리표로**(A6 10.5와 8.7): 진화 컷인 `portrait.<마녀>.cutin_evolve`, 우두머리 처치 컷인 `portrait.<마녀>.cutin_kill`, 궁극기 컷인 `portrait.<마녀>.cutin_ultimate`, 전투 기록 전신 `portrait.<마녀>.record`, 마을 바탕 `ui.town.backdrop`, 장소 단추 `ui.town.place.<장소>`, 스킬 트리 메달 `ui.medal.<트리>.<마디>`, 사당 표지 `icon.shrine.<종류>`, 상자 `world.prop.chest`, 사당 비석 `world.prop.shrine`, 새 적 `actor.<종류>.*`, 의상 `outfits.json`의 `art` 칸 → `portrait.<마녀>.outfit.<의상>`. T7-1이 끝난 뒤 이 자리를 만드는 지시서는 "코드는 id로, 그림이 없으면 대체물로 먼저 들어간다"를 붙인다. 그러면 그림 승인을 기다리지 않고 코드를 들일 수 있다.
- `portrait_derive.py`의 출력 이름을 자리 id에 맞춘다(`tools/art/portrait_slots.json`의 `slots[].name` → `portrait.<마녀>.<name>`). 이 일은 T7-5에 묶는다.

---

## 6. 작업 묶음(지시서)

모든 묶음에 공통:
- 시작 때 `git merge --ff-only`로 본 저장소 HEAD에 맞춘다. 결과는 패치와 보고서(`_local/tools/t7-<묶음>/`)로 낸다. 커밋·푸시하지 않는다.
- 사용자 저장(`%APPDATA%\WitchMoira`)을 열지 않는다. Godot는 `python tools/dev/godot.py`로만 부른다.
- **에셋 파일을 옮기거나 이름을 바꾸지 않는다**(T7-7의 `_local` 사본 제외). 그래야 덤프 해시가 전후 같아야 한다는 기준이 선다.
- 건드리지 않는 파일: `chapter1/core/**`, `chapter1/data/**`, `chapter1/tests/golden/**`, 옛 층 파일(`chapter1/view/cloister_*.gd`, `chapter1/view/chapter_world*.gd`), `CLAUDE.md`, `chapter1/art/ASSET-LEDGER.json`(도구 `add` 외에는).
- 덤프 비교 명령(이하 "덤프 셋"): 주력 셋 각각.
  ```powershell
  python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.<frost|ember|arc> --shots=_local/t7/<묶음>/<전|후>-<주력> --dump=_local/t7/<묶음>/<전|후>-<주력>.json --scene=_local/t7/<묶음>/<전|후>-<주력>-scene.json
  ```
  기준: `HUD_DUMP`·`SCENE_DUMP` 해시가 전후 같다. 알려진 흔들림(T1 4번의 "허용 차이 목록": ✓ 라벨 폭 82/83px, 소리 알림 문구)은 허용. 그 밖의 차이는 JSON에서 찾아 보고하고 반려 사유로 본다.
- 캡처 비교: `python tools/dev/shot_review.py`로 전후 같은 시점 캡처를 나란히 본다(직접 봄/캡처만 있음을 보고에 적는다).
- 공통 끝 확인: `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd` 불일치 0, `python tools/dev/run_all.py --quick` 통과, 창 실행 20초(`python tools/dev/run_dev.py -- --chapter1-start --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-quit-after=20`) 로그에 `SCRIPT ERROR`·`Parse Error`·`Could not resolve` 0건.
- 되돌리기: 묶음마다 패치 하나. 에셋을 옮기지 않으므로 패치를 거꾸로 적용하면 원상태다.

### T7-0 실제로 로드되는 에셋 목록 — `qa-perf`

**목표**: 한 판과 메뉴 화면들을 지나는 동안 `chapter1/art/` 아래 에셋 파일 각각이 로드되었는지, 2D 시트가 실제로 그려지는지 표로 낸다.

**고칠 파일**: `chapter1/tests/hud_dump.gd`에 선택 인수 `--asset-usage=<_local 아래 경로>`만 더한다(인수가 없으면 지금과 같은 동작). 끝에서 `chapter1/art/`의 에셋 확장자 파일(`.png .svg .glb .wav .ttf`)과 `chapter1/view/hud/living_portrait/*.png` 각각에 `ResourceLoader.has_cached(path)`를 적고, 2400틱 시점 장면 트리에서 보이는 `Sprite3D`/`AnimatedSprite3D`의 수와 그 텍스처 경로를 적는다. `chapter_actors.gd`의 `raw_texture_fallbacks`(원시 PNG로 읽은 것은 캐시에 안 잡힘)도 함께 적는다.
**건드리지 않을 파일**: 공통 목록 + `chapter1/view/**`, `chapter1/app/**`.
**실행**: 덤프 셋(주력 셋)에 `--asset-usage=_local/t7/usage-<주력>.json`을 붙여 한 번씩.
**통과 기준**: (1) 인수 없이 돌린 덤프 해시가 고치기 전과 같다(주력 하나면 충분). (2) 결과 표: 파일마다 로드 여부(주력 셋 합집합), 2D 시트는 "로드됨/그려짐" 두 칸. (3) 보고서에 "로드 안 됨" 목록과 "로드됐지만 그려지지 않음" 목록을 따로 적는다. 메뉴에서 열지 않는 화면(예: 스킬 트리를 덤프가 열지 않는다면)은 "확인 못 함"으로 적는다.
**되돌리기**: `hud_dump.gd` 패치 되돌림.

### T7-1 해결기·자리표·Godot 검사 — `refactor-architect`

**목표**: 3.3~3.6의 구조를 만든다. 아직 아무 호출부도 바꾸지 않는다.
**새 파일**:
- `chapter1/art/asset_slots.json`: 지금 실행 때 쓰이는 파일 전부의 자리(T7-0의 "로드됨" 목록 기준. T7-0이 없으면 2.2 표의 "쓰임" 행 전부). 계약 칸은 2.2 표의 "모양" 열에 있는 값을 **코드에서 그대로 옮겨 적는다**(값을 바꾸지 않는다). 사슬 악마 몸은 역할마다 자리를 두되(`actor.ranged.model` 등) 같은 파일을 가리킨다.
- `chapter1/view/assets/asset_slots.gd`: 3.4의 함수와 3.5의 대체물. 결과 캐시. 덮어쓰기 인수 `--chapter1-asset-slots=`는 `res://_local/` 아래만.
- `chapter1/tests/test_asset_slots.gd`: 3.6의 2단계 검사. `--strict`이면 대체물·fallback 사용을 실패로.
- `chapter1/art/README.ko.md`에 자리표 설명 몇 줄과 3.7의 "함께 고칠 것" 목록.
**건드리지 않을 파일**: 공통 목록 + 모든 기존 `.gd`(호출부는 T7-3~6). `tools/**`(T7-2 몫). `tools/dev/run_all.py`(지금 다른 에이전트가 고치는 중 — 검사 등록은 디렉터가 그 작업이 끝난 뒤 따로 배정).
**확인**: (1) `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_asset_slots.gd` 통과, `--strict`도 통과(지금 파일이 다 있으므로). (2) 일부러 망가뜨린 표를 `_local/t7/broken_slots.json`에 만들어 `-- --slots=` 인수로 돌리면, 없는 파일·없는 뼈·없는 클립·범위 밖 조각을 각각 이름으로 보고하고 실패한다. (3) 같은 망가진 표로 창 실행 20초 + `--chapter1-asset-slots=_local/t7/broken_slots.json` → 이 시점에는 호출부가 해결기를 쓰지 않으므로 화면 변화 없음과 `CHAPTER1_ASSETS` 줄이 안 찍힘을 확인(해결기가 로드되지 않음). (4) 공통 끝 확인.
**되돌리기**: 새 파일 삭제.

### T7-2 도구: 넣기 전 대조, 원장 대조, 참조 판정 — `manager-tools`

**목표**: 자리표를 도구들이 이해하게 한다. T7-1과 병렬(자리표 꼴은 3.3이 기준. T7-1이 아직 없으면 `tools/art/test_data/asset_slots_sample.json`으로 시험).
**고칠 파일**:
- `tools/art/asset_intake.py`: `--slot <id 또는 접두*>`와 `--slots <표 경로>`(기본 `chapter1/art/asset_slots.json`). 3.6의 1단계 대조 표. 모델은 기존 GLB 읽기에 스킨 관절 이름·애니메이션 이름 목록을 더한다. PNG 크기·알파는 표준 라이브러리로(머리와 IHDR, tRNS/색 형식). SVG는 `viewBox`로 정사각 판정. TTF는 `check_glyphs.py`의 cmap 읽기를 import해 쓴다(복사하지 않는다). `--dir`로 묶음 대조.
- `tools/art/asset_ledger.py check`: 자리표와 `chapter1/data/audio_map.json`(있으면)이 가리키는 파일이 원장에 있는지(없으면 경고), 원장 파일 가운데 어느 자리에도 없는 것 목록("자리 없음"). 종료 코드 규칙은 지금 그대로(경고는 0).
- `tools/dev/check_build.py`의 `unreferenced_data_files`와 `tools/dev/refactor_map.py`, `tools/manager/catalog.py`의 사용 판정: 자리표·`audio_map.json`·곁 JSON에 적힌 경로를 참조로 센다.
- 각 도구의 자체 검사(`tools/art/test_asset_intake.py`, `test_asset_ledger.py`, `tools/dev/test_refactor_map.py`, 관리 툴 검사).
**건드리지 않을 파일**: 공통 목록 + `chapter1/**` 전체(표본 자리표는 `tools/` 아래에). `tools/dev/run_all.py`.
**통과 기준**: (1) 자체 검사 전부 통과. (2) 표본 표로: 같은 파일 대조 = 차이 0, 뼈 이름 하나 바꾼 표본 GLB(시험 데이터로 만든 작은 glTF) = 그 뼈만 "없음"과 비슷한 이름 제시, 크기 다른 PNG = 크기 차이 보고. (3) 지금 저장소에서 `asset_ledger.py check` 종료 0, 출력에 "자리 없음" 목록이 나옴(자리표가 아직 없으면 그 줄을 "자리표 없음"으로). (4) 경로를 JSON으로만 부르는 표본 프로젝트(시험 데이터)에서 세 도구가 그 파일을 "참조 있음"으로 본다.
**되돌리기**: 도구 패치 되돌림.

### T7-3 모델과 2D 시트의 호출부 — `refactor-architect` (T7-1·T7-2 뒤)

**목표**: 3D 모델 셋과 2D 시트를 자리 id로 부르고, 뼈·클립·배율·시간 상수를 계약에서 읽는다.
**고칠 파일**: `chapter1/view/actors/chapter_actors.gd`, `chapter1/view/actors/vat/walker_vat_spec.gd`, `chapter1/view/actors/vat/walker_crowd.gd`.
- 상수 `MODEL`, `WARDEN`, `OUTLAW34`(preload → 셋업 때 한 번 로드해 변수에 캐시), `walker_vat_spec.gd`의 `MODEL_PATH`·`HEAD_BONE`·`TRACKED_BONES`·`HIT_BONES`·`HIT_EXCLUDE_BONES`·시간 상수 → 해결기와 계약. vat_spec은 계약을 읽는 얇은 꼴로 남긴다(복사본 주석 삭제).
- 뼈 이름 리터럴(`ORG-*` 15, 사슬 악마 42, 주인공 2 + 접두 8), 배율 6곳 + .62 + 1.32 + 머리 .72, 클립 이름 → 논리 이름 + `AssetSlots.bone/clip`. 접두 규칙은 `bone_groups.upper_prefixes`.
- `assert(index>=0)` 꼴의 뼈 확인(`:1049`, `:1160`, 34b `setup`)은 `if index<0: push_warning(...); <그 꾸밈 건너뜀>`으로.
- 2D 시트: `:72`·`:84`의 경로 조립 → `actor.<종류>.sheet`, `actor.hero.cast_sheet`. 곁 JSON은 그대로.
- `:1228`의 `path.begins_with(WARDEN+"::")`는 해결기가 준 실제 경로와 비교.
**건드리지 않을 파일**: 공통 목록 + 다른 `view/` 파일. `__층` 메서드를 접거나 지우지 않는다(T1-4 R4 몫). 배율·시간 값 자체를 바꾸지 않는다.
**확인**: (1) 덤프 셋 해시 전후 같음. (2) 구운 움직임 켠 실행: 덤프 셋을 `--chapter1-vat-walker`를 붙여 주력 하나로 전후 비교. (3) 캡처 비교(2400·9000틱의 전투 장면, 정예와 우두머리가 나온 시점 포함). (4) `test_asset_slots.gd --strict` 통과. (5) `--chapter1-asset-slots=_local/t7/no_warden.json`(사슬 악마 파일을 없는 경로로 바꾼 사본, `fallback`은 지금 파일)으로 창 실행 20초 → 죽지 않음, `CHAPTER1_ASSETS`의 `missing`에 그 id, 화면은 지금과 같음. 같은 사본에서 `fallback`도 없앤 실행 → 자홍 캡슐, 오류 없이 20초. (6) `chapter_actors.gd`에 `res://chapter1/art/` 0건, `"ORG-`·`"Spine`·`"Hand.` 리터럴 0건(Grep 결과를 보고에). (7) 공통 끝 확인.
**되돌리기**: 패치 되돌림.

### T7-4 UI 키트·장비 아이콘·글꼴·원화 자르기 — `ui-hud` (T7-1·T7-2 뒤)

**고칠 파일**: `chapter1/view/hud/ui_style.gd`, `chapter1/art/ui/kit/build_kit.py`, 새 `chapter1/art/ui/kit/hud_atlas.json`, `chapter1/view/equipment_sigil_quality35.gd`(옛 층이 아니라 쓰이는 부품. 이 파일의 `PAINTINGS`만), `chapter1/view/loc.gd`(글꼴 상수 두 줄과 `_font_file`), `chapter1/view/hud/skill_tree_panel.gd`(`PORTRAITS`).
- `ATLAS` 37조각 → `build_kit.py`가 쓰는 `hud_atlas.json`(`{"size":[w,h],"pieces":{…}}`). 지금 코드의 좌표를 그대로 옮겨 첫 파일을 만들고, `build_kit.py`는 앞으로 같은 꼴로 쓰게 고친다(지금 그림을 다시 만들지 않는다).
- 9조각·AtlasBox 여백과 `CODE`는 계약 칸에서.
- 장비 아이콘 7개 → `icon.equip.<칸>`, 없는 칸은 `icon.equip.charm`(지금 동작).
- 글꼴 → `font.body`, `font.heading`. `project.godot`는 고치지 않는다(3.7-7).
- 원화 경로와 얼굴 `Rect2` → `illustration.<마녀>`의 `file`과 `crops.face`.
**건드리지 않을 파일**: 공통 목록 + `chapter_hud.gd`, `combat_bar.gd`(조각 이름은 그대로 쓰므로 고칠 일 없음), `equipment_sigil_quality17.gd`, 그림 파일 자체.
**확인**: 덤프 셋 해시 같음. 스킬 트리 화면은 덤프가 열지 않으면 `python tools/dev/godot.py --path . --script res://chapter1/tests/skill_tree_preview.gd`(인수는 그 파일 머리 주석) 전후 캡처 비교. `python tools/dev/check_glyphs.py` 통과. 아이콘 하나를 `_local` 덮어쓰기 표에서 없는 파일로 → 바둑판이 그 칸에만. 네 파일에 `res://chapter1/art/` 0건. 공통 끝 확인.
**되돌리기**: 패치 되돌림.

### T7-5 살아 있는 초상과 초상 효과 — `ui-hud` (T7-4 뒤, 같은 영역이라 순차)

**고칠 파일**: `chapter1/view/hud/living_portrait/living_portrait.gd`(`CONFIG_DIR + id + ".json"` → `portrait.<마녀>.rig`, `WITCHES`는 자리표의 `portrait.*.rig` 목록과 대조만), `snowflake_fx.gd`(눈송이 두 장 → `fx.portrait.flake_disc`·`fx.portrait.flake_rings`), `tools/art/portrait_derive.py`(출력 파일 이름을 자리 id에 맞춤, 5절).
- 초상 설정 JSON과 그림은 옮기지 않는다. 설정 JSON 안의 `layer_dir`·눈 경로는 지금처럼 그 JSON이 가진다(곁 파일).
- `living_portrait_demo.gd`(게임에 안 붙음)는 그대로.
**확인**: 메뉴 시점 덤프 해시 같음 + 메뉴 초상 캡처 비교(움직임이 있으므로 같은 프레임 번호끼리). 겹 하나를 `_local` 사본에서 없앤 설정 → 그 겹만 빠지고 오류 없음. 공통 끝 확인.

### T7-6 지형·소품 — `refactor-architect` (T1-4 R2와 R4-world 뒤)

**고칠 파일**: `chapter1/view/world/chapter_world.gd`, `chapter1/art/quality03/cloister_props_v01.json`·`cloister_foliage_v01.json`에 `"group"` 칸 하나씩 추가(그 밖의 칸은 그대로).
- `ART_BASE` + 파일 이름 → `world.ground.flagstone`·`world.ground.soil`·`world.props.cloister`·`world.props.foliage`.
- `ends_with("cloister_foliage_v01.png")` 두 곳 → 곁 JSON의 `group == "foliage"`.
- 소품 id 문자열은 그대로 두고 계약 `ids_required`에 적어 검사가 확인한다.
**확인**: 덤프 셋 해시 같음, 캡처 비교(풀과 기둥이 보이는 시점), 공통 끝 확인.

### SD1에 붙일 것 — `sound-designer` (S1 7절의 SD1을 그대로 하되 두 가지만 더함)

1. `audio_map.json`의 큐마다 계약 칸 `variants_min`(지금 `COUNTS` 값)과 `max_len_s`를 둔다. T7-2의 `asset_intake.py --slot`이 `audio:<큐 id>`로 WAV를 대조할 수 있게(채널, 표본 빈도, 길이).
2. 환경음 반복 끝을 `data.size()/2`로 계산하지 않는다(16비트 모노일 때만 맞음). 임포트 설정의 반복이나 형식에 맞는 계산으로.
SD1의 나머지 기준(S1 7절 SD1 행)은 그대로다.

### T7-7 교체 연습 — `qa-perf` (T7-3·T7-4 뒤)

**목표**: "파일 넣기 → 자리표 한 줄 → 점검"이 코드 수정 없이 되는지 실제로 해 본다. 저장소의 에셋은 바꾸지 않고 `_local` 사본으로 한다.
**절차**: (1) 장비 아이콘 하나를 다른 그림(예: 다른 칸의 svg 사본)으로 `_local/t7/drill/`에 두고 `_local/t7/drill/asset_slots.json`(사본)의 한 줄만 바꾼다. `asset_intake.py --slot icon.equip.ring --slots <사본>` → `--chapter1-asset-slots=<사본>`으로 덤프 → 덤프 차이가 그 아이콘의 텍스처 경로 한 곳뿐. (2) 같은 방법으로 해골 모델 자리를 사슬 악마 파일로 가리키게 하고 계약의 뼈·클립 대응만 사슬 악마 이름으로 바꾼 사본 → `asset_intake.py`가 차이 0을 내는지, 창 실행 20초가 오류 없이 도는지, `SCRIPT ERROR` 0건. (3) 결과 보고: 고친 줄 수, 코드 수정 0인지, 막힌 곳(3.7 목록에 없던 것이 나오면 그것이 이 문서의 결함이다).

---

## 7. 병렬로 돌릴 수 있는 묶음

| 묶음 | 함께 돌려도 됨 | 함께 돌리면 안 됨 |
|---|---|---|
| T7-0 | T7-1, T7-2, SD1 | `hud_dump.gd`를 고치는 다른 작업 |
| T7-1 | T7-0, T7-2, SD1 | — |
| T7-2 | T7-0, T7-1, SD1 | `run_all.py`를 고치는 작업과는 파일이 겹치지 않음(등록은 하지 않음) |
| T7-3 | T7-4, T7-5, SD1 | T1-4 R4-actors, `chapter_actors.gd`를 고치는 vfx-feel·character-artist 작업 |
| T7-4 → T7-5 | T7-3, T7-6 | `ui_style.gd`·`skill_tree_panel.gd`·`living_portrait/`를 고치는 A6 화면 작업 |
| T7-6 | T7-3, T7-4 | T1-4 R2·R4-world(그 뒤에) |

---

## 8. 위험

1. **도구가 모든 에셋을 "안 쓰임"으로 오판**: 경로가 JSON으로 옮겨지면 지금 도구들은 코드 본문만 본다. → T7-2를 T7-3~6보다 먼저.
2. **덤프 해시가 경로에 묶임**: 파일을 옮기면 화면이 같아도 해시가 바뀐다. → 구조 묶음에서는 파일을 옮기지 않는다. 실제 교체 때의 해시 변화는 "텍스처 경로만 다름"인지 덤프 JSON으로 확인.
3. **preload → 실행 중 로드로 첫 사용 끊김**: 장비 아이콘(인벤토리 첫 열기), 해골 모델(셋업). 셋업 때 미리 한 번 로드해 캐시. 프레임 시간을 이 문서는 재지 않았다 — 끊김이 의심되면 qa-perf의 기존 프레임 측정으로.
4. **대체물이 배포에 섞임**: 개발 편의의 fallback이 빠진 파일을 가린다. → `store` 프리셋 전 `test_asset_slots.gd --strict`(빌드 검사에 묶는 일은 T7-1 뒤 디렉터가 `build.py`·`check_build.py` 담당에게).
5. **Godot 임포트가 뼈 이름을 바꿀 수 있음**: Python 대조(glTF 원래 이름)와 Godot의 이름이 다를 수 있다 [추정]. → 최종 판정은 Godot 검사.
6. **계약 칸이 썩음**: 아무도 읽지 않는 칸은 사실과 멀어진다. → 3.1-3, 그리고 `test_asset_slots.gd`가 계약 칸 이름을 kind별 허용 목록과 대조해 모르는 칸을 경고.
7. **큰 파일 충돌**: `chapter_actors.gd`(2,076줄)는 화면 작업이 자주 고친다(최근 커밋 `d93d061`). → T7-3 동안 그 파일의 다른 배정을 막는다.
8. **이름 충돌**: "slot"이 장비 칸(`loot.json`의 slot)과 `portrait_slots.json`의 자르기 자리와 겹친다. 글에서는 "자리표", 파일·클래스는 `asset_slots`/`AssetSlots`로 구분하지만 혼동 여지가 있다(9절 결정 6).
9. **안 쓰는 에셋이 지금 배포 묶음에 들어감**: `all_resources` 내보내기라 출처 미확인 시트·조건부 모델이 쓰이지 않아도 들어간다. 구조와 별개의 위험이라 9절에 결정으로 올린다.

---

## 9. 디렉터가 정할 것

1. **자리표 위치**: `chapter1/art/asset_slots.json`(권고: 원장 옆, 아트 담당 소유) / `chapter1/data/asset_slots.json`(데이터 한곳).
2. **원장과의 관계**: 따로 두고 경로로 잇기(권고, 3.2) / 원장 항목에 `slot` 칸.
3. **T7-0 결과 뒤 안 쓰는 에셋 처리**: 내보내기에서 빼기(`export_presets.cfg`의 `exclude_filter`, 권고: 지우지 않고 바로 할 수 있음) / `art-archive/`로 옮기기 / 지우기. 사용자가 "다 바꾼다"고 했으므로 안 쓰는 것을 바꿀 까닭은 없다.
4. **T1 4번과의 순서**: T7-3 → R4-actors, R2·R4-world → T7-6(권고, 5절).
5. **주인공 3D가 Sunra 등에서 올 때 뼈 이름을 표준으로 맞출지**: Godot 임포트의 휴머노이드 리타깃(`SkeletonProfileHumanoid`)을 쓰면 계약의 뼈 대응이 표준 이름 하나로 고정된다. 지금 정할 일은 아니고, 첫 새 주인공 모델이 올 때 시험해 보고 정한다(큰 안의 일부, 10절).
6. **이름**: `asset_slots`/"자리표" 그대로(권고) / 다른 이름(`asset_map` 등. 단 `audio_map`과 헷갈림).
7. **검사 등록**: `test_asset_slots.gd`와 도구 검사를 `run_all.py --quick`에 넣는 시점(지금 `run_all.py`를 고치는 작업이 끝난 뒤).

---

## 10. 큰 안(권하지 않음, 참고)

- 자리마다 Godot 사용자 리소스(`AssetSlot.tres`, 형식 있는 계약 칸)와 편집기 플러그인, 임포트 플러그인에서 계약 검사, 관리 툴에서 끌어다 놓아 교체, 휴머노이드 리타깃을 모든 인물 모델에 적용.
- 얻는 것: 편집기 안 확인, 형식 검사. 잃는 것: 새 체계를 만들고 익히는 비용, `.tres` 묶음의 병합 충돌, 헤드리스 도구(Python)가 읽기 어려움. 사용자의 "최소한으로"에 맞지 않는다. 작은 안이 막히는 곳이 T7-7에서 나오면 그 부분만 가져온다.

---

## 11. 확인하지 못한 것

- Godot·회귀를 돌리지 않았다(지시). 2.2 표의 "실행 때 쓰임"은 코드 읽기에 따른 [추정]이고, T7-0이 확인한다. 특히 "적 2D 시트는 로드되지만 그려지지 않음", "hero 시트와 hero_cast는 로드되지 않음"은 [추정].
- 옛 층 인스턴스(`chapter_one.gd:14-21`)가 에셋을 로드하는지 [미확인].
- 구운 움직임이 모델을 바꾸면 자동으로 다시 굽는지 [미확인].
- Godot glTF 임포트의 뼈 이름 변환 여부 [미확인].
- 해결기를 거친 로드의 프레임 비용 [미측정].
- 지금 `chapter1/view/**`를 고치는 다른 에이전트가 있는지 [미확인] — 배정 전 디렉터 확인.
- SD1이 시작되었는지: `chapter1/data/audio_map.json`은 없다 [확인]. 배정 상태는 [미확인].
- 2.2의 수는 Grep 패턴으로 센 것이라 한두 개 오차가 있을 수 있다(뼈 이름은 문자열 리터럴만 셌고, 이어 붙여 만드는 이름 `"Arm."+side`는 하나로 셌다).
