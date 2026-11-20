# 기술 지시서 T2-H — 세 마녀의 새 3D 모델을 게임 본체에 넣는 구조 (2026-11-20)

작성: tech-lead. 구현하지 않는다. 받는 담당은 이 문서의 4절(자기 묶음)과 공통 규칙만 읽고 일할 수 있게 썼다.
표기: [코드] 저장소 파일에서 직접 읽음, [파일] 산출물 파일에서 직접 읽음, [계산] 읽은 값으로 계산함(모델의 답), [짐작] 확인하지 않은 추정.

---

## 0. 받은 지시와 받을 명세 (문 ①)

- 디렉터 지시(요지): 세 마녀의 새 3D 모델을 게임 본체에 넣기 위한 구조 작업의 지시서. 다룰 것: 마녀별 모델 자리, 겉모습 값의 계약, 클립 이름과 길이의 계약, 지팡이 붙는 자리, 꺼진 채 들이기와 불변 확인, 담당·순서·검수 명령·프레임 시간, 물어야 할 것.
- 받을 명세: `docs/specs/A7-hero-look-and-motion-20261120.ko.md` 5.1절 TR-1~TR-4, 2.3절(겉모습 칸), 4.1절(클립 논리 이름), 6절 공통(건드리지 않는 파일).
- 같이 따르는 구조: `docs/specs/T7-asset-swap-structure-20261120.ko.md`(자리표·해결기). T7-1(`9a3c46d`)과 T7-2(`28123ed`)는 main에 들어가 있다 [코드: git log]. **T7-3(모델 호출부)은 아직이다**: `chapter_actors.gd`는 여전히 `const MODEL`과 `load(MODEL)`을 쓰고 `asset_slots.gd`를 부르지 않는다 [코드: 417·474행, Grep].
- 이 문서가 다루지 않는 것: A7 TR-4의 "표현기 규칙 이식"(서기↔달리기 섞기, 회피 클립, 시전 종류별 라우팅). 그 입력이 될 A7-3 시험 표현기 결과(`hero_motion.json`)가 없다. `_local/art/a7/A7-3/`의 패치는 기본 몸 굽기 도구(`tools/art/base_*.py`)이고 표현기가 아니다 [파일: patch.diff·patch-v4.diff의 파일 목록]. 6절에 남은 일로 적는다.

---

## 1. 요약 한 장

| 묻는 것 | 이 문서의 답 |
|---|---|
| 마녀별 모델 자리 | 자리표에 `actor.hero.frost.model`·`actor.hero.ember.model`·`actor.hero.arc.model`(+ 같은 마녀의 `.emission` 텍스처 자리). 고르는 열쇠는 주력 기술 id의 끝 마디(`chapter1.skill.frost` → `frost`). 마녀 자리가 없거나 계획 상태면 지금의 `actor.hero.model`. 경로는 자리표 한 곳에만 있다 |
| 겉모습 값 | 모델 자리의 곁 JSON(`meta`) `actors/hero/<마녀>/hero.json`의 `look` 칸. 본체가 읽는 칸 9개(3.2). 경로는 이 파일에 적지 않는다(발광 가면은 자리 id로) |
| 클립 길이 | **본체가 실행 중에 클립 길이를 읽지 않는다.** 자리 계약 `pose`의 숫자(지금 이미 표에 있는 키 + `hit_start_s`, `stride_world_m`)를 모델마다 따로 둔다. 숫자가 클립 길이 안에 드는지는 검사(`test_asset_slots.gd`)가 본다. 그래서 옛 모델은 숫자가 그대로라 화면이 바뀌지 않고, 새 모델은 원래 클립 전체를 쓸 수 있다. 임시 클립 `run_c06`·`cast_shot`·`hit_quick`은 필요 없어진다(계약이 어느 쪽을 가리켜도 된다) |
| 걸음 폭·배율 | 배율과 걸음 폭은 한 쌍이다. 지금 본체의 2.15m는 새 달리기 클립과 맞지 않아 발이 미끄러진다 [계산, 3.4]. 둘 다 계약 숫자로 옮기고, 값은 카메라 결정 뒤 고른다 |
| 지팡이 | 곁 JSON의 `staff.mode`: `upright`(지금 동작, 기본) / `hand`(손 뼈의 회전을 따름). 지금 곧게 서는 까닭은 살아 있는 동안 지팡이 회전을 손과 상관없이 덮어쓰기 때문이다 [코드: 543행] |
| 스위치 | 표현 스위치 `--chapter1-hero-models`(꺼짐이 기본, `--chapter1-vat-walker`와 같은 꼴). 꺼진 값에서 골든·`equiv.py`·덤프 해시 불변 |
| 작업 수 | 다섯 묶음: HM-0(character-artist) · HM-1, HM-2, HM-3(refactor-architect, 순차) · HM-4(qa-perf) |

---

## 2. 지금 상태 — 직접 본 것

### 2.1 본체의 주인공 경로 [코드] `chapter1/view/actors/chapter_actors.gd`
- 모델: `const MODEL := "res://chapter1/art/rigged_mage/v01/mage_animated.glb"`(417), `load(MODEL)`(474), 배율 `HERO_MODEL_SCALE 1.32`(420, 476). 주인공 노드는 `setup__cloister`에서 한 번 만든다(51행 `hero=_create("hero")`). **판의 마녀가 정해지기 전(메뉴 전)에 만들어진다.**
- 머티리얼: `_setup_materials`(487~500)가 모든 면을 복제해 albedo ×(1.35,1.25,1.18), 림 .28, albedo 텍스처를 발광으로 쓴다. `_apply_hero_element`(517~532)는 주력이 처음 정해질 때(`sync__rigged` 548행) 한 번 albedo 섞음·림 1.0·발광 원소색 ×.15·세기 .6으로 덮는다. `_hero_materials`를 바꾸는 곳은 이 둘과 메뉴 복귀(`rest_for_menu` 1957행)뿐이다(Grep).
- 전용 조명: `_setup_artist_lights`(457~462)가 층 2 방향광 둘(1.6, .85)을 만든다. 변수에 담지 않는다. 시험 도구 `model_swap.gd`는 `light_cull_mask==2`로 찾아낸다.
- 지팡이: `ember_staff_visual.gd`(코드로 만든 메시, 길이 -1.05~1.13). 위치는 `hand_cr_r`와 `finger_middle.01.r`의 가운데(452, 538~540). **살아 있으면 회전을 `Basis.from_euler(-3°+sin(위상)·4°, 0, 5°)`로 덮는다(543)** — 손을 따르지 않는다. 죽었을 때만 손 회전 × 첫 프레임에 잡은 `_grip_basis`(541~542). 바닥 아래로 내려가면 들어 올린다(544~545).
- 동작(581~592): `run`은 `_phase*.6`, `idle`은 `fposmod(age,1.2)`, `cast`는 `.15+age*2.25`(age ≤ .2초), `hit`은 `age*3`(age ≤ .1초), `death`는 `min(.9, age)`(568). 걸음 위상은 이동 거리 ÷ `HERO_STRIDE 2.15`(45, 318, 579). 상체 판정은 뼈 이름 접두(483).
- 메뉴 복귀: `_capture_menu_rest`/`rest_for_menu`(1913~1966)가 뼈 자세·머티리얼 값·지팡이를 인덱스로 저장·복원한다. 모델을 바꾸면 이 인덱스가 어긋난다.

### 2.2 자리표 [파일] `chapter1/art/asset_slots.json`, 해결기 `chapter1/view/assets/asset_slots.gd`
- `actor.hero.model`이 이미 있다: `file`, `contract.scale 1.32`, `bones.hand_r/finger_r`, `bone_groups.upper_prefixes/upper_contains`, `clips`(idle·run·cast·hit·death), `pose`(`run_time_scale .6`, `idle_loop_s 1.2`, `cast_start_s .15`, `cast_time_scale 2.25`, `hit_time_scale 3`, `death_max_age_s .9`). 코드가 아직 읽지 않는다.
- 해결기는 `scene(id)`, `texture(id)`, `meta(id)`(곁 JSON), `contract(id)`, `clip(id,논리)`, `bone(id,논리)`, `scale3(id)`, `is_planned(id)`, `missing()`를 준다. `inherit`는 계약을 **최상위 키 단위로** 덮는다(`pose`를 덮으면 `pose` 전체를 다시 적어야 한다). 계약 `pose`의 값은 **0 이상 숫자만** 허용된다(556행). 자리가 비면 자홍 캡슐(뼈 없음)을 준다.
- id 규칙 `^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$`, 앞 마디는 `actor` 등. `actor.hero.frost.model`은 통과한다.

### 2.3 새 모델 셋 [파일] `D:/Project/witch-moira-work/char3d/a8/{frost,storm,ember}/final.glb` (glb 머리 JSON을 직접 읽음)
| | 냉기 | 번개(폴더 이름 storm) | 화염 | 옛 마법사 |
|---|---|---|---|---|
| 파일 크기 | 16.8MB | 17.1MB | 16.9MB | 24.2MB |
| 삼각형 | 14,428 | (같은 기본 몸 + 부품) | | 11,014 |
| 스킨 관절 | 65 | 65 | 65 | 53 |
| 메시 | body, frost_fur_collar, frost_outfit | body, storm_hip_panel, storm_hip_rim, storm_outfit | body, ember_outfit, ember_pauldron | 하나 |
| 이미지 이름 | `frost_a8_albedo` 등 3장 | 4장 | 3장 | color, normal |

- **뼈 이름이 옛 마법사와 같다**: `pelvis_cr`, `spine_cr_01~03`, `neck_cr`, `head_cr`, `shoulder_cr_*`, `upper_arm_cr_*`, `forearm_cr_*`, `hand_cr_*`, `finger_middle.01.r` 등. 새 모델은 손가락 끝 `*_leaf`와 `toe_end_cr_*`가 더 있다. 그래서 지금의 상체 접두 규칙과 지팡이 뼈 이름이 그대로 걸린다.
- 클립(셋 모두 같은 목록, 초): idle 16.633, run 0.683, run_c06 0.6, cast 4.267, cast_shot 1.8, hit 2.433, hit_quick 1.2, hit_b 1.833, death 2.4, dodge 2.333, dodge_side 1.433, cast_area 2.667, 그 밖에 run_ual·run_sprint·run_jog_natural·walk·swing·interact·cast_enter/loop/exit. 옛 마법사: idle 1.225, run .625, cast .625, hit .325, death .925.
- 기본 몸 키(모델 공간) 1.681m, 옛 마법사 2.03m [파일: `a8/frost/clips.json`의 `height`, A7 1.4].

### 2.4 겉모습 값 [파일] `_local/art/a7/A7-3/{frost,storm,ember}_a8.look.json`
- 칸: `albedo_mul`(.45/.42/.50), `element_lean` 0, `emission_mode`(냉기·화염 `mask`, 번개 `none`), `emission_energy` .6, `rim` .03, `rim_tint` .15, `rim_color`, `light_key`(.4/.38/.4), `light_fill`(.25/.23/.25), `emission_texture`(로컬 절대 경로).
- 이 값을 화면에 입히는 코드는 `chapter1/tests/model_swap.gd`의 `apply_look`(매 프레임). `rim_color`는 StandardMaterial3D에 림 색이 없어 적용되지 않는다고 그 파일이 적고 있다. 발광 가면은 albedo 텍스처 크기가 가면과 같은 면에만 붙인다(부품은 발광 없음).

### 2.5 마녀 id [코드]
- `chapter1/data/character_progression.json`: `chapter1.character.frost`/`ember`/`arc`, 각 `signature_skill_id`가 `chapter1.skill.<같은 끝 마디>`. 앱은 시작 기술로 마녀를 고르고(`chapter_one.gd` 452~458, `_character_for` 488), 저장이 꺼져 있으면 `run_character_id`가 빈다. 표현이 받는 것은 `run.growth.snapshot().primary`다(`chapter_actors.gd` 546).
- 그래서 자리 id의 마녀 마디는 **코어 id 끝 마디(`arc`)** 를 쓰기를 권한다. 아트 폴더 이름 `storm`과 다르다(6절 결정 1).

### 2.6 출처 [파일] `chapter1/art/ASSET-LEDGER.json`
- 옛 마법사 glb는 `third_party_derived`, **CC BY-SA 3.0**(OpenGameArt "Rigged textured mage", thecubber/Julius), `release_cleared false`.
- 인계 메모(`_local/HANDOVER-20261120b.ko.md` 3절)에 따르면 새 모델은 Quaternius 기본 몸(CC0)에 **옛 모델의 머리·장화·치마를 붙였다.** 그렇다면 새 모델에도 BY-SA 조건이 따라온다 [짐작: 법적 판단이 아니다]. 뼈 이름이 옛 마법사와 같은 것도 이 경로와 맞는다.
- 동작: Quaternius Universal Animation Library(CC0, zip SHA256 앞 `CC73FC4E`, 끝 `7724`), Universal Base Characters(CC0, `FDBF1804`…`5F40`), Mixamo(Adobe 계정으로 사용자가 내려받은 FBX 8개, `D:/Project/witch-moira-work/downloads/mixamo/`). Mixamo 약관은 이 문서에서 열어 보지 않았다.

---

## 3. 계약

### 3.1 자리와 고르는 규칙 (TR-1)

**자리표에 더할 줄(마녀마다 둘)**
```
"actor.hero.frost.model": {
  "kind": "model",
  "file": "actors/hero/frost/model.glb",
  "meta": "actors/hero/frost/hero.json",
  "used": "unverified",
  "source": "T2-H 3.1: per-witch hero body, chosen by the primary skill's last segment; switch --chapter1-hero-models",
  "contract": { "scale": <HM-0 값>, "bones": {...actor.hero.model과 같음}, "bone_groups": {...같음},
                "clips": { "idle": "idle", "run": "<HM-0이 고름>", "cast": "...", "hit": "...", "death": "death" },
                "pose": { 3.3의 키 전부 }, "budget_profile": "hero" }
},
"actor.hero.frost.emission": { "kind": "texture", "file": "actors/hero/frost/emission.png", "used": "unverified", "source": "...", "contract": {"size": [w,h]} }
```
- `fallback` 칸을 두지 않는다. 마녀 자리가 안 되면 **코드가** `actor.hero.model`(자기 계약과 함께)로 돌아간다. 마녀 자리의 `fallback`을 옛 glb로 두면 새 모델의 배율·시간 숫자가 옛 모델에 붙어 틀린 몸이 나온다.
- `inherit`는 쓰지 않는다(계약 `pose`를 통째로 다시 적어야 해서 얻는 것이 없다). 대신 `bones`·`bone_groups`가 `actor.hero.model`과 같은지 검사가 본다(HM-2).
- 번개의 발광 가면이 아직 없으면(`emission_mode none`) `actor.hero.arc.emission`은 만들지 않는다.

**폴더**: `chapter1/art/actors/hero/<frost|ember|arc>/` — `model.glb`, `emission.png`, `hero.json`, `ATTRIBUTION.ko.md`. 버전 숫자를 붙이지 않는다(T7 3.8). 다음에 몸을 바꿀 때는 같은 폴더 안 파일을 바꾸거나 새 폴더로 넣고 **자리표 한 줄**만 고친다.

**고르는 규칙(코드)**
1. 스위치가 꺼져 있으면 언제나 `actor.hero.model`. 오늘과 같은 경로.
2. 켜져 있으면 주력이 처음 정해지는 순간(지금 `_apply_hero_element`가 불리는 자리)에 열쇠 `key = primary.get_slice(".", 마지막)`을 만든다. `actor.hero.<key>.model`이 표에 있고 계획 상태가 아니고 실제 파일이 있으면 그 모델로 바꿔 끼운다. 아니면 `actor.hero.model`을 유지하고 경고 한 번.
3. 메뉴로 돌아가면(`rest_for_menu`) 먼저 `actor.hero.model`로 되돌린 뒤 지금의 복원을 한다. 그래서 메뉴 화면은 스위치와 상관없이 오늘과 같다(메뉴에도 마녀 몸을 보일지는 6절 결정 4).
4. 경로 문자열은 자리표에만 있다. `chapter_actors.gd`에 `res://chapter1/art/`가 남지 않는다(주인공 부분).

### 3.2 겉모습 계약 (TR-2) — 곁 JSON `hero.json`의 `look`

본체가 읽는 칸. **아홉 칸은 모두 있어야 한다**(빠지면 `test_asset_slots.gd`가 실패). 한 번 적용하면 다음 바꿔 끼우기 전까지 그대로다(지금 `_hero_materials`를 매 프레임 바꾸는 코드가 없으므로 시험 도구처럼 매 프레임 덮을 필요가 없다).

| 칸 | 꼴 | 뜻(본체가 하는 일) |
|---|---|---|
| `albedo_mul` | 수 또는 [r,g,b] | 모든 몸 면의 `albedo_color` 바탕 |
| `element_lean` | 0~1 | 바탕에서 원소색 ×1.3 쪽으로 섞는 비율 |
| `emission_mode` | `none`/`albedo`/`mask` | `none`: 발광 끔. `albedo`: 지금 방식(albedo 텍스처 × 원소색 ×.15). `mask`: `actor.hero.<key>.emission` 텍스처를 발광 텍스처로, 발광 색은 검정(Godot의 더하기 규칙 때문, `model_swap.gd` 129행 주석) |
| `emission_energy` | ≥0 | 발광 세기 |
| `rim` | ≥0 | 림 세기(0이면 림 끔) |
| `rim_tint` | 0~1 | 림 색조 |
| `light_key` | ≥0 | 주인공 전용 키 조명 세기(옛 1.6) |
| `light_fill` | ≥0 | 주인공 전용 채움 조명 세기(옛 .85) |
| `mask_rule` | `"same_size"` | 발광 가면을 붙일 면을 고르는 규칙. 지금은 `model_swap.gd`와 같은 "albedo 텍스처 크기 = 가면 크기"만 둔다. 부품(목도리·어깨 갑옷·허리 자락)은 발광이 없다 |

선택 칸: `light_key_color`, `light_fill_color`(색 글자). 없으면 지금 색.

- 원소색은 지금처럼 `HERO_ELEMENT_COLORS`(주력)에서 온다. 바닥 고리·원반 색도 지금 그대로다(번개 색을 보라로 옮기는 일은 A7 8.2의 별도 결정).
- **`rim_color`는 넣지 않는다**(본체가 읽을 수 없는 칸은 썩는다, T7 3.3). 의도한 림 색은 A7 2.2 표에 이미 있다.
- **경로를 적지 않는다**: 지금 look.json의 `emission_texture`(로컬 절대 경로)는 빼고 자리 id로 부른다.
- **옛 마법사**(`actor.hero.model`)에는 `meta`를 달지 않는다. `look`이 없는 모델은 지금 코드(`_setup_materials`의 보정 + `_apply_hero_element`)를 그대로 탄다. A7 TR-2는 "옛 값을 그대로 적어 같은 화면"을 요구했으나, 두 단계로 나뉜 지금 값을 표 한 장으로 옮기면 적용 순서가 바뀌어 덤프가 갈릴 위험이 있다. 옛 모델을 내리는 날 이 갈래를 지운다(그날 고칠 곳: `_setup_materials`, `_apply_hero_element` 두 함수).
- 적용 차례(새 모델): 끼울 때 `_setup_materials`가 면을 복제(보정 값은 곧 덮이므로 상관없음) → 주력이 정해진 그 프레임에 `_apply_hero_element`의 고리·원반 색 부분만 → `look` 아홉 칸 적용 → 전용 조명 둘의 세기·색. 조명은 변수 둘(`_hero_key_light`, `_hero_fill_light`)에 담고, 옛 모델로 되돌릴 때 1.6/.85와 원래 색으로 돌린다.

### 3.3 클립 이름과 시간 계약 (TR-3)

**결정: 본체는 실행 중에 클립 길이(`Animation.length`)를 읽지 않는다. 모델마다 계약 숫자를 읽는다.**
- 까닭 1: 옛 마법사는 클립 길이와 쓰는 숫자가 다르다(run .625인데 .6, idle 1.225인데 1.2) [파일]. 길이를 읽게 바꾸면 꺼진 값에서도 화면이 바뀐다.
- 까닭 2: Mixamo 클립은 앞뒤에 쓰지 않을 부분이 있다(cast는 2.0초쯤에 쏨, hit는 0.3~0.4초부터 반응 [파일: A7-4 REPORT 13행]). 길이만으로는 어디를 쓸지 정할 수 없다. 시작 시각이 필요하다.
- 결과: 새 모델은 원래 클립(`run`, `idle`, `cast`, `hit`, `death`)을 시작 시각과 함께 그대로 쓸 수 있다. 임시 클립 `run_c06`·`cast_shot`·`hit_quick`은 필요 없어진다. 계약 `clips`가 그쪽을 가리켜도 같은 코드로 돈다(어느 쪽을 쓸지는 HM-0이 골라 숫자와 함께 낸다).

**`pose` 키(모두 초 단위·0 이상, 본체가 읽는 식)**
| 키 | 본체의 식 | 옛 마법사 값(지금 코드 그대로) |
|---|---|---|
| `run_time_scale` | run 표본 시각 = 위상(0~1) × 이 값. 새 모델은 = 그 달리기 클립의 한 주기 길이 | .6 |
| `stride_world_m` | **새 키.** 위상 += 이동 거리 ÷ 이 값(318·579행의 `HERO_STRIDE`) | 2.15 |
| `idle_loop_s` | idle 표본 시각 = fposmod(대기 나이, 이 값) | 1.2 |
| `cast_start_s` | cast 표본 시각 = 이 값 + 나이(0~.2초) × `cast_time_scale` | .15 |
| `cast_time_scale` | 위 식 | 2.25 |
| `hit_start_s` | **새 키.** hit 표본 시각 = 이 값 + 나이(0~.1초) × `hit_time_scale` | 0 |
| `hit_time_scale` | 위 식 | 3 |
| `death_max_age_s` | death 표본 시각 = min(이 값, 죽은 나이) | .9 |

- `actor.hero.model`에 `stride_world_m 2.15`, `hit_start_s 0`을 더한다. 0을 더하는 식은 float에서 값이 그대로다. JSON의 2.15와 코드 리터럴 2.15가 비트까지 같은지는 확인하지 않았다 [짐작: 같다] — HM-1의 `equiv.py`가 다르면 잡는다.
- 시전 창 .2초, 무게 곡선 `smoothstep(.04,.2)`, 피격 무게 .55·창 .1초는 이번에 옮기지 않는다(TR-4의 섞기 규칙과 함께 바뀔 값이다).
- **검사(HM-2가 `test_asset_slots.gd`에 더함)**: 모든 `actor.hero*.model` 자리에서, 임포트된 실제 클립 길이 L에 대해 `run_time_scale ≤ L(run)`, `idle_loop_s ≤ L(idle)`, `cast_start_s + .2×cast_time_scale ≤ L(cast)`, `hit_start_s + .1×hit_time_scale ≤ L(hit)`, `death_max_age_s ≤ L(death)` (허용 1e-3). 옛 마법사는 다섯 줄 모두 통과한다 [계산: .6≤.625, 1.2≤1.225, .6≤.625, .3≤.325, .9≤.925].
- 클립 논리 이름은 지금 다섯 개(idle·run·cast·hit·death)만 쓴다. A7 4.1의 새 이름(`cast_basic_*`, `cast_ring`, `dash`, `descent_*`)은 TR-4 때 계약에 더한다. 그 전에 glb 안에 있어도 된다(계약 밖 클립).

### 3.4 배율과 걸음 폭은 한 쌍이다 [계산]

- 발이 미끄러지지 않으려면 `stride_world_m = (클립의 모델 공간 지면 속도) × 배율 × run_time_scale`이다. 게임 속도와는 상관없다(속도는 걸음 박자만 바꾼다).
- 아트 도구는 게임 속도 5.8m/s ÷ 클립 지면 속도 3.652m/s = **배율 1.588**을 전제로 클립을 맞췄다 [파일: `a8/frost/clips.json`의 `ground_speed 3.652`, `rig_config.json`의 `ground_mps_game 5.8`, `run_cycle.stride_game_m 3.5 / stride_model_m 2.204 = 1.588`]. 그런데 본체 배율은 1.32이고 걸음 폭은 2.15m다.
- 지금 `play_with_model.gd`로 본 화면은 배율 1.32·걸음 폭 2.15다. 이 조합에서 `run_c06`은 한 주기에 약 2.9m를 디뎌야 할 몸을 2.15m마다 한 바퀴 돌린다 [계산: 2.204 × 1.32 = 2.91]. A7-4 보고의 게임 안 미끄러짐 중앙값 2.1m/s는 이 어긋남과 맞는다 [짐작].
- 키: 새 몸 1.681m × 1.32 = **2.22m**, × 1.588 = **2.67m**. 옛 마법사는 2.68m(A7 1.4) [계산]. 즉 새 몸을 1.32로 그리면 옛 주인공보다 17% 작다.
- 화면 높이(QUALITY-TARGETS 2절 9~12%): A7 2.1의 "카메라 19.5에서 키 100픽셀"(옛 몸 2.68m 기준)을 비례로 옮기면 [계산, 대략]

| | 카메라 19.5 | 카메라 14 |
|---|---|---|
| 배율 1.32(2.22m) | 약 83px, 7.7% (미달) | 약 116px, 10.7% |
| 배율 1.588(2.67m) | 약 100px, 9.2% | 약 139px, 12.9% (넘음) |

- 그래서 **배율·걸음 폭 숫자는 카메라 결정 뒤에 고른다.** 구조는 어느 쪽에서도 같다(계약 숫자 두 개). 이 표는 비례 계산이라 HM-4가 실제 가면 측정으로 바꾼다.

### 3.5 지팡이 (A7에 없던 항목) — 곁 JSON `hero.json`의 `staff`

| 칸 | 꼴 | 뜻 |
|---|---|---|
| `mode` | `upright`/`hand` | `upright`: 지금 동작(위치만 손, 회전은 고정 + 위상 흔들림). `hand`: 살아 있을 때도 지금의 죽음 갈래처럼 손 뼈 회전 × 쥔 회전을 따른다 |
| `grip_ref` | `{"clip": "idle", "time": 0}` | `hand` 모드에서 "이 자세에서 지팡이가 곧게 선다"로 잡을 기준 자세. 끼울 때 그 자세를 표본해 `_grip_basis`를 한 번 잡는다(지금은 첫 동기화 프레임에 잡는다, 541행) |
| `tilt_deg` | [x,y,z] | 쥔 회전 위에 더하는 기울기(음수 가능 — 계약 `pose`는 0 이상만 받으므로 곁 JSON에 둔다) |
| `scale` | 수 | 지팡이 메시 배율(메시 길이 2.18m, 몸 키가 바뀌면 맞춘다) |

- 바닥 아래로 내려가면 들어 올리는 규칙(544~545)은 두 모드 모두 그대로.
- `hero.json`이 없거나 `staff`가 없으면 `upright` = 지금 코드.
- 지팡이 뼈는 계약 `bones.hand_r`·`finger_r`에서 읽는다(지금 리터럴 452행).

### 3.6 스위치와 꺼진 값의 불변 (A7 5절에 없는 운용 규칙)

- 스위치: `chapter_one.gd` 71행 옆에 `actors.hero_models_enabled="--chapter1-hero-models" in _user_args()` 한 줄(`vat_walker_enabled`와 같은 꼴). 표현만 바뀌고 저장과 무관하므로 `--chapter1-trial`(저장 꺼짐 필수)에 넣지 않는다. 켜는 날은 이 기본값 한 줄을 바꾼다.
- 꺼진 값에서 같아야 하는 것: 골든 리플레이 불일치 0, `equiv.py` 전 부분 해시 같음(주인공 뼈·메시·지팡이·애니메이션 포함), `hud_dump` 덤프 셋 해시 같음.
- 켠 값에서: 코어·데이터 파일 변경 0(`git diff --stat`), 골든 불일치 0(골든은 표현을 로드하지 않는다), `equiv_dump` 켬/끔 비교에서 **차이가 주인공 부분에만** 있다. 적·효과 부분 해시는 같아야 한다.

### 3.7 원장

- 넣는 날(HM-0) `python tools/art/asset_ledger.py add`로 파일마다 올린다: 각 `model.glb`, `emission.png`, Godot가 glb에서 풀어 놓는 PNG(`model_<이미지 이름>.png`), `ATTRIBUTION.ko.md`는 `--record-file`.
- `--source-type third_party_derived`. `--origin`에 넷을 모두: Quaternius Universal Base Characters(CC0, zip 전체 SHA256), Quaternius Universal Animation Library(CC0, zip 전체 SHA256), 옛 마법사의 머리·장화·치마(OpenGameArt "Rigged textured mage", CC BY-SA 3.0, 원장 기존 줄과 같은 글), Mixamo(Adobe, 동작 이름 8개). 면별 그림을 만든 생성 모델과 프롬프트는 기록을 찾아 적고, 못 찾으면 "미확인: ..."으로 적는다(지어내지 않는다).
- `--license`는 "CC0 + CC BY-SA 3.0(붙인 부품) + Mixamo 약관" 세 줄. `release_cleared`는 false 그대로. BY-SA와 Mixamo 약관의 판단은 6절 결정 6.
- 인계 메모의 SHA 앞머리(`CC73FC4E…7724`, `FDBF1804…5F40`)와 HM-0이 다시 계산한 전체 값이 같은지 보고서에 적는다.

---

## 4. 작업 지시서

### 공통 (모든 묶음)
- 저장소: `C:/Project/witch-moira`. 시작할 때 본 저장소 main HEAD에 맞춘다(`git merge --ff-only`). 시작한 커밋을 보고서 첫 줄에 적는다. 결과는 패치와 보고서로 **본 저장소의 절대 경로** `C:/Project/witch-moira/_local/t2h/<묶음>/`에 둔다(작업 폴더 안의 `_local`에 두지 않는다). 커밋·푸시하지 않는다.
- Godot는 `python tools/dev/godot.py`(검사)나 `python tools/dev/run_dev.py`(창)로만 부른다. 창 실행은 한 번에 하나, 끝나면 `python tools/dev/godot_ps.py`로 남은 프로세스가 없는지 본다.
- 사용자 저장(`%APPDATA%\WitchMoira`)을 열지 않는다. `.gitattributes`가 `* -text`이니 줄바꿈을 바꾸는 도구로 기존 파일을 고치지 않는다.
- 건드리지 않는 파일: `chapter1/core/**`, `chapter1/data/**`, `chapter1/tests/golden/**`, `chapter1/view/` 바로 아래의 `cloister_*.gd`·`chapter_world_quality*.gd`, `CLAUDE.md`, `chapter1/art/ASSET-LEDGER.json`(도구 `add` 외에는). `chapter_actors.gd`의 `__층` 메서드를 접거나 지우지 않는다(T1-4 R4 몫).
- 화면은 "직접 봄 / 캡처만 있음 / 보지 않음" 가운데 하나를 적는다. 실행하지 않은 검사를 통과로 적지 않는다.
- 글·이름·주석의 금지 낱말 규칙(디렉터 메모 `no-ai-sounding-words`)을 따른다. 낱말 검사가 막는 줄기를 피한다.
- **덤프 셋**(꺼진 값 불변 확인, 주력 셋):
  ```powershell
  python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.<frost|ember|arc> --shots=_local/t2h/<묶음>/<전|후>-<주력> --dump=_local/t2h/<묶음>/<전|후>-<주력>.json --scene=_local/t2h/<묶음>/<전|후>-<주력>-scene.json
  ```
  "전"은 시작 커밋에서(`git stash` 없이: 패치 적용 전에 먼저 돌린다), "후"는 패치 뒤. `HUD_DUMP`·`SCENE_DUMP` 해시가 같아야 한다. 알려진 흔들림(T1 4번의 허용 차이 목록: ✓ 라벨 폭 82/83px, 소리 알림 문구)만 허용.
- **공통 끝 확인**: `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd` 불일치 0 · `python tools/dev/run_all.py --quick` 통과 · `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_asset_slots.gd -- --strict` 통과 · 창 20초 `python tools/dev/run_dev.py -- --chapter1-start --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-quit-after=20` 로그에 `SCRIPT ERROR`·`Parse Error`·`Could not resolve` 0건.

---

### HM-0 세 몸을 저장소에 들일 꼴로 — `character-artist` (HM-1과 병렬)

**목표**: 3절 계약에 맞는 세 마녀 묶음을 만든다. 코드는 고치지 않는다.

**입력**: `D:/Project/witch-moira-work/char3d/a8/{frost,storm,ember}/final.glb`, `clips.json`, `rig_config.json` · `C:/Project/witch-moira/_local/art/a7/A7-3/{frost,storm,ember}_a8.look.json`, `frost_a8_emission.png`, `ember_a8_emission.png` · 이 문서 3.2~3.5, 3.7.

**할 일**
1. 묶음 폴더를 `C:/Project/witch-moira/_local/t2h/HM-0/stage/chapter1/art/actors/hero/{frost,ember,arc}/`에 만든다(번개는 폴더 이름 `arc`, 6절 결정 1이 다르게 나면 이름만 바꾼다). 각각 `model.glb`, `emission.png`(냉기·화염만), `hero.json`, `ATTRIBUTION.ko.md`.
2. glb 안의 이미지 이름에서 버전 표시(`_a8`)를 뺀다(예: `albedo`, `skirt_albedo`, `collar`). Godot가 `model_<이미지 이름>.png`로 풀어 놓으므로 폴더마다 이름이 겹치지 않는다(`docs/ART-3D-PIPELINE.ko.md` "게임에 끼울 때" 1항의 함정).
3. `hero.json`: `{"look": {3.2의 아홉 칸 + 선택 칸}, "staff": {3.5의 칸}}`. `look` 값은 A7-3 look.json에서 옮기고 `rim_color`·`emission_texture`·`_about`은 뺀다. `staff`는 `mode: "hand"`의 첫 값을 넣는다(`grip_ref`, `tilt_deg`, `scale`). 첫 값을 어떻게 골랐는지 보고에 적는다.
4. 자리표 조각 `C:/Project/witch-moira/_local/t2h/HM-0/slots_fragment.json`: 3.1의 여섯 줄(번개 가면이 없으면 다섯). 계약 `pose`는 3.3의 여덟 키 전부. **배율과 `stride_world_m`은 두 벌**을 낸다: (가) 배율 1.32, (나) 배율 1.588. 각 벌의 `stride_world_m`은 3.4의 식으로, 클립 지면 속도는 도구가 실제로 쓰는 값으로 계산하고 식과 숫자를 보고에 적는다. `run`이 가리킬 클립(`run` 또는 `run_c06`), `cast_start_s`·`cast_time_scale`(쏘는 순간이 나이 0~.05초 안에 오게), `hit_start_s`(반응 시작), `death_max_age_s`를 고른 까닭을 적는다.
5. 원장 명령: 3.7의 `asset_ledger.py add` 명령을 파일마다 완성한 꼴로 `C:/Project/witch-moira/_local/t2h/HM-0/ledger_commands.ps1`에 적는다(**실행하지 않는다**. 파일이 저장소에 들어간 뒤 HM-2가 실행한다). Quaternius 두 zip의 전체 SHA256을 `D:/Project/witch-moira-work/downloads/quaternius-ual/`, `quaternius-ubc/`에서 계산해 인계 메모의 앞머리와 대조한다.
6. 예산: `python tools/art/asset_intake.py <model.glb> --slot actor.hero.model`로 지금 계약과 대조한 표를 보고서에 붙인다(뼈·클립 이름 일치, 삼각형·뼈 수). 계약 밖 클립 목록도 적는다(지우지 않아도 된다. 지우면 파일 크기 변화를 적는다).

**건드리지 않을 파일**: 공통 목록 + `chapter1/**` 전체(묶음은 `_local` 아래에만), `tools/**`(도구 고침이 필요하면 따로 보고).
**끝난 모양**: `stage/` 폴더 셋, `slots_fragment.json`, `ledger_commands.ps1`, `REPORT.txt`(위 4·5·6의 근거). 묶음을 기존 시험 경로로 한 번 확인: `play_with_model.gd` 또는 `rig_game_probe.gd`에 `--model-glb=<stage의 model.glb> --hero-look=<hero.json의 look만 뺀 임시 파일>`로 냉기 한 판 앞부분 캡처(화면: 직접 봄/캡처만 있음 표기).
**다섯 요소**: 성장(고른 마녀가 제 몸으로 나온다), 섹시(원화의 실루엣이 제품에 들어오는 길).

---

### HM-1 주인공 호출부를 자리표로 (T7-3의 주인공 몫) — `refactor-architect`

**목표**: 주인공 모델·배율·뼈·클립·시간 숫자를 `actor.hero.model` 계약에서 읽는다. **화면·덤프는 하나도 바뀌지 않는다.** 마녀별 자리와 스위치는 아직 없다.

**고칠 파일**: `chapter1/view/actors/chapter_actors.gd`, `chapter1/art/asset_slots.json`(`actor.hero.model`의 `pose`에 `stride_world_m: 2.15`, `hit_start_s: 0` 두 키만 더함).
- 맨 위에 `const AssetSlots = preload("res://chapter1/view/assets/asset_slots.gd")`.
- `const MODEL`(417) → 자리 id. `load(MODEL)`(474) → `AssetSlots.scene(id)`. `HERO_MODEL_SCALE`(420, 476) → `AssetSlots.scale3(id)`. `RIGGED_HERO_READY` 출력의 `source`는 `AssetSlots.path(id)`.
- 상체 접두(483) → `bone_group(id,"upper_prefixes")`·`"upper_contains"`. 지팡이 뼈(452) → `bone(id,"hand_r")`·`"finger_r"`.
- 클립 이름(`_sample("run"/"idle"/"cast"/"hit"/"death")`) → `AssetSlots.clip(id, 논리)`. 시간 숫자(568, 581, 583~584, 589~590) → 계약 `pose`의 3.3 키. `HERO_STRIDE`(45, 318, 579) → `stride_world_m`. 바꾸는 식은 3.3 표의 식과 글자 그대로 같은 연산 순서로 둔다(예: `hit_start_s + age*hit_time_scale`).
- 지금 쓰는 계약 값을 **셋업 때 한 번** 변수에 담는다(프레임마다 `contract()`를 부르면 딕셔너리 복사가 생긴다. `contract()`는 `duplicate(true)`를 돌려준다 [코드: asset_slots.gd 177행]).
- 자리가 대체물(뼈 없는 캡슐)일 때 죽지 않게: `rig_skeleton`·`rig_player`가 null이면 `setup__rigged`의 뼈 찾기(452)와 `_sample("idle",0)`(453)을 건너뛴다.
- 이 묶음 안의 함수 하나로 모은다: `_hero_slot_values(id) -> Dictionary`(배율, 뼈, 클립, pose). HM-2가 마녀를 바꿀 때 같은 함수를 다시 부른다.

**건드리지 않을 파일**: 공통 목록 + `chapter_actors.gd`의 주인공 밖 부분(사슬 악마 `WARDEN`, 해골 `OUTLAW34`, 2D 시트, `vat/` — T7-3의 나머지 몫), 다른 `view/` 파일. 배율·시간 값 자체를 바꾸지 않는다.
**확인**
1. 덤프 셋 해시 전후 같음(주력 셋).
2. `python tools/dev/equiv.py --base <시작 커밋> --primary frost,ember,arc --until 2400` → 모든 부분 해시 같음. 주인공 뼈(`hero.bones`)와 지팡이(`staff`)가 같아야 한다.
3. `--chapter1-asset-slots=_local/t2h/HM-1/no_hero.json`(`actor.hero.model`의 `file`을 없는 경로로 바꾼 사본)으로 창 20초 → 죽지 않음, 자홍 캡슐, `CHAPTER1_ASSETS`의 `missing`에 그 id, `SCRIPT ERROR` 0.
4. `chapter_actors.gd`의 주인공 부분(414~611행 범위와 `HERO_STRIDE`를 쓰던 곳)에 `res://chapter1/art/`, `"hand_cr_r"`, `"spine_"`, `.6 if moving`, `2.15` 리터럴 0건(Grep 결과를 보고서에).
5. 공통 끝 확인.
**되돌리기**: 패치 하나를 거꾸로 적용.
**다섯 요소**: 직접 키우는 것 없음(바꿔 끼울 때 고칠 곳을 한 곳으로 만드는 바탕).

---

### HM-2 마녀별 모델, 스위치, 겉모습 계약 — `refactor-architect` (HM-1·HM-0 뒤)

**목표**: 3.1·3.2·3.6을 구현한다. 스위치 꺼짐이 기본이고, 꺼진 값에서 화면·덤프가 바뀌지 않는다.

**고칠 파일**
- `chapter1/art/` — HM-0의 `stage/chapter1/art/actors/hero/` 세 폴더를 그대로 복사해 들이고, `python tools/dev/run_dev.py --import-only`로 임포트. 풀려 나온 PNG와 `.import` 파일도 함께 패치에 넣는다.
- `chapter1/art/asset_slots.json` — HM-0의 `slots_fragment.json`을 들인다. 배율·걸음 폭은 **(가) 1.32 벌**을 넣는다(6절 결정 2가 나면 숫자만 바꾼다). 스위치가 꺼져 있으므로 어느 벌이든 꺼진 값에는 영향이 없다.
- `chapter1/art/ASSET-LEDGER.json` — HM-0의 `ledger_commands.ps1`을 실행해서만(손으로 고치지 않음). `python tools/art/asset_ledger.py check` 종료 0.
- `chapter1/app/chapter_one.gd` — 71행 옆 스위치 한 줄(3.6). 이 밖은 고치지 않는다.
- `chapter1/view/actors/chapter_actors.gd`:
  - `var hero_models_enabled := false`.
  - `_setup_artist_lights`가 만든 조명 둘을 변수에 담는다(순서와 값은 그대로).
  - `_swap_hero_model(id)`: 지금 `rig_model`을 떼고 새로 인스턴스, `HM-1`의 `_hero_slot_values(id)`를 다시 읽고, `rig_player`·`rig_skeleton`·`_upper`·`_hand`·`_finger`·`_hero_materials`를 새로 채우고, `_grip_ready=false`, `_sample(idle,0)`. 스위치가 켜져 있을 때만 `setup`에서 세 마녀의 `PackedScene`을 미리 로드(인스턴스는 하지 않음)해 판 시작의 끊김을 줄인다.
  - 주력이 처음 정해지는 자리(지금 `sync__rigged` 548행 둘레)에서 3.1의 고르는 규칙 → 바꿔 끼우기 → 3.2의 적용 차례.
  - `rest_for_menu` 첫머리: 스위치가 켜져 있고 지금 몸이 기본 자리가 아니면 기본 자리로 되돌리고 조명 값을 1.6/.85와 원래 색으로. 그 뒤 지금의 복원.
  - 계약 숫자는 바꿔 끼울 때마다 다시 읽는다(모델마다 다르다).
- `chapter1/tests/test_asset_slots.gd` — 더할 검사: (1) 3.3의 클립 길이 검사(모든 `actor.hero*.model`). (2) 마녀 자리가 있으면 `meta`가 있고 `look` 아홉 칸이 모두 있고 꼴이 맞음, `emission_mode == "mask"`면 `actor.hero.<key>.emission`이 있고 크기가 그 모델의 몸 albedo 텍스처와 같음. (3) 마녀 자리의 `bones`·`bone_groups`가 `actor.hero.model`과 같음. (4) 코어 id 덮기: `character_progression.json`의 마녀마다 `signature_skill_id`의 끝 마디 = 캐릭터 id의 끝 마디(열쇠 규칙의 전제)이고, 마녀 자리가 있으면 그 마디 이름.

**건드리지 않을 파일**: 공통 목록 + `chapter_actors.gd`의 주인공 밖 부분, `chapter_one.gd`의 스위치 한 줄 밖, 다른 `view/` 파일.
**확인**
1. 꺼진 값: 덤프 셋 해시 전후 같음(주력 셋). `python tools/dev/equiv.py --base <시작 커밋> --primary frost,ember,arc --until 2400` 모든 부분 같음.
2. 켠 값: 주력 셋 각각 `hud_dump.gd`에 `--chapter1-hero-models`를 붙여 한 판(`--shots`, `--dump`). 각 판의 `RIGGED_HERO_READY` 또는 새 출력 줄에 끼운 자리 id가 찍힌다. 판 시작·600·2400틱 캡처를 직접 보고 세 마녀가 각자 몸으로 나오는지 적는다(직접 봄/캡처만 있음).
3. 켠 값 메뉴 복귀: 한 판 → 메뉴(`hud_dump`가 메뉴로 돌아가는 흐름이 있으면 그것으로, 없으면 "확인 못 함") → 메뉴 덤프가 꺼진 값의 메뉴 덤프와 같다.
4. 켠 값 망가뜨림: `--chapter1-asset-slots=_local/t2h/HM-2/no_frost.json`(냉기 자리 `file`을 없는 경로로) + `--chapter1-hero-models` + 냉기 주력으로 창 20초 → 옛 마법사로 돌고 경고 한 번, `SCRIPT ERROR` 0.
5. `chapter_actors.gd`·`chapter_one.gd`에 `res://chapter1/art/actors/hero` 0건.
6. 공통 끝 확인(`test_asset_slots.gd --strict` 포함), `python tools/art/asset_ledger.py check` 종료 0.
**다섯 요소**: 성장(마녀마다 제 몸), 섹시(원화 쪽 실루엣과 부품이 제품 화면에 들어오는 길).

---

### HM-3 지팡이 쥐기 — `refactor-architect` (HM-2 뒤, 같은 파일이라 순차)

**목표**: 3.5. `staff.mode == "hand"`인 몸에서 지팡이가 손을 따른다. `upright`와 곁 JSON이 없는 몸은 지금 그대로.

**고칠 파일**: `chapter1/view/actors/chapter_actors.gd`의 `sync__rigged` 지팡이 부분(537~549)과 `_swap_hero_model`(쥔 회전 잡기), `chapter1/view/ember_staff_visual.gd`는 고치지 않는다(배율은 노드 `scale`로).
- `hand` 모드: 끼울 때 `grip_ref` 자세를 표본해 `_grip_basis = hand.basis.orthonormalized().inverse() * hero.global_basis`(지금 541행과 같은 식)를 잡고 표본 수 세기(`_pose_samples`)는 되돌린다(메뉴 복원과 같은 요령, 1952~1953행). 살아 있을 때 `_staff.global_basis = (hand.basis.orthonormalized() * _grip_basis * Basis.from_euler(tilt)).orthonormalized()`. 바닥 들어 올림은 그대로.
- `upright`: 543행 그대로.

**확인**: 꺼진 값 덤프 셋·`equiv.py` 같음. 켠 값에서 세 마녀 × (서기, 달리기, 시전, 피격, 죽음) 지팡이 캡처: `rig_game_probe.gd`의 `--burst`(HM-4가 스위치 켬에 맞춰 둔 뒤라면 그것으로, 아니면 `hud_dump`의 `--burst=<이벤트>`)로 각 60프레임 띠. 지팡이가 손에서 떨어지거나 몸·바닥을 꿰뚫는 프레임 수를 적는다. 공통 끝 확인.
**다섯 요소**: 섹시(지팡이 쥔 손과 팔의 선), 쾌감(시전 때 지팡이가 같이 뻗음 — 클립이 그렇게 생겼을 때).

---

### HM-4 켠 값의 검증과 프레임 시간 — `qa-perf` (HM-2 뒤. HM-3과 병렬 가능: HM-4는 `chapter_actors.gd`를 고치지 않는다)

**목표**: 스위치를 켤지 판단할 근거를 숫자로 낸다. 제품 파일은 고치지 않는다.

**고칠 파일**(시험 도구만): `chapter1/tests/rig_game_probe.gd`, `chapter1/tests/model_swap.gd`.
- `rig_game_probe.gd`가 `--model-glb` 없이도 돌고(제품 몸 그대로 측정), `--chapter1-hero-models`가 주어지면 `--hero-mask`·`--hero-crop-ticks`·`--burst`·`--foot-log`가 바뀐 몸에서도 맞게 도는지 확인하고 고친다(바꿔 끼운 뒤 `rig_model`·`rig_skeleton`을 다시 찾아야 한다).
- `--cam-size=<m>`를 `play_with_model.gd`에서 옮겨 `model_swap.gd`의 공용 함수로 두고 두 도구가 같이 쓴다(복사하지 않는다).

**측정** (결과는 `C:/Project/witch-moira/_local/t2h/HM-4/`)
1. **화면 높이**: 세 마녀 × 카메라 19.5와 14 × 1920×1080, 시드 11, `--hero-mask --hero-crop-ticks=600,1500,2400`. 주인공 가면의 세로 화소 / 1080. QUALITY-TARGETS 2절 9~12% 대비. HM-0의 두 벌(배율 1.32, 1.588)을 `--chapter1-asset-slots=<_local 사본>`으로 각각. 3.4 표의 비례 계산을 이 측정값으로 바꾼다.
2. **발 미끄러짐**: 같은 조건에서 `--foot-log`. A7 3.3 표(직선 중앙값 ≤ .15m/s, 95번째 ≤ .5m/s, 박자 2.8~3.4회/초)로 판정. 두 벌 각각.
3. **꺼진 값 대비 켠 값의 차이가 주인공에만**: `equiv_dump.gd`를 `--eq-full`로 켬/끔 두 번(주력 하나, 2400틱까지) → 차이 나는 부분 목록. 주인공 밖이 하나라도 다르면 반려 사유로 보고. (`equiv.py`가 한쪽에만 인수를 줄 수 있으면 그것으로, 없으면 `equiv_dump.gd` 두 번 + 비교.)
4. **프레임 시간**: `tools/dev/perf_ab.py`. 계획: 같은 작업 폴더, 변형 `off`(인수 없음)와 `on`(`--chapter1-hero-models`), 블록 하나에서 번갈아, 웜업 + 3회, 180초, 1920×1080, 기본 인수 `--chapter1-start --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --chapter1-primary=<frost와 arc 두 블록>`. 표: p50·p95·50ms 초과. 판정어는 도구의 것(분리/가르지 못함)을 그대로 쓴다.
5. **바꿔 끼우는 순간의 끊김**: `chapter1/tests/frame_probe.gd`로 판 시작 뒤 3초의 최대 프레임 간격, 켬/끔 각 3회. 켬에만 있는 50ms 넘는 프레임이 있으면 보고(HM-2의 미리 로드가 부족하다는 뜻).
6. **메모리**: 켬/끔의 `Performance.MEMORY_STATIC`·`RENDER_TEXTURE_MEM_USED`를 2400틱에서 (도구가 이미 적으면 그 값, 없으면 "확인 못 함").

**측정 환경**: 다른 Godot가 돌지 않을 때만(`perf_ab.py`가 오염을 표시한다). 다른 담당이 창 실행 중이면 기다린다.
**끝난 모양**: `REPORT.txt`에 1~6의 표, 실행한 명령 전부, 판 수. 화면 표기.
**다섯 요소**: 직접 키우는 것 없음(켜는 판단의 근거).

---

## 5. 순서·의존·병렬

```
HM-0 세 몸 묶음(character-artist) ───────────────┐
HM-1 주인공 호출부→자리표(refactor-architect) ────┴─> HM-2 마녀별 모델·스위치·겉모습(refactor-architect)
                                                        ├─> HM-3 지팡이(refactor-architect)
                                                        └─> HM-4 검증·프레임 시간(qa-perf)
                                                                 └─> art-lead 본체 검수 → 사용자 플레이 → 켜기 결정
```
- **바로 시작할 수 있는 것**: HM-0과 HM-1(파일이 겹치지 않음: HM-0은 `_local`만, HM-1은 `chapter_actors.gd`와 자리표 두 키).
- HM-1·HM-2·HM-3은 같은 파일(`chapter_actors.gd`)이라 한 담당이 차례로 한다. 그동안 `chapter_actors.gd`를 고치는 다른 배정(T7-3의 나머지, T1-4 R4-actors, A7의 vfx-feel·character-artist 표현 작업)을 막는다.
- **T7-3과의 관계**: HM-1이 T7-3의 주인공 몫을 먼저 떼어 한다. T7-3의 나머지(사슬 악마·해골·2D 시트·`vat/`)는 HM-3 뒤에 같은 담당이 이어서 한다. T7 문서 6절 T7-3의 확인 항목 가운데 주인공 줄은 HM-1이 채운다.
- HM-4는 `chapter_actors.gd`를 고치지 않으므로 HM-3과 병렬로 돌 수 있다. 단 프레임 시간(4번)은 HM-3이 끝난 상태로 한 번 더 잴지 디렉터가 정한다(지팡이 계산은 프레임당 몇 번의 행렬 곱이라 차이가 작을 것 [짐작]).
- **메테오 패치와의 관계**: 메테오 코어 패치(`_local/d20-meteor/`)가 먼저 main에 들어가면 골든이 갱신된다. 각 묶음은 시작 커밋의 골든과 비교하므로 문제없다. 다만 HM 묶음이 도는 동안 main이 움직이면 "전" 덤프를 시작 커밋에서 다시 뜬다.

## 6. 디렉터가 정할 것 / 사용자에게 물을 것

**디렉터가 정할 것**
1. **번개 마녀 자리의 이름**: 코어 id `arc`(권고 — 표현이 받는 주력 id와 같아 코드에 짝 표가 필요 없음) / 아트 폴더 이름 `storm`. `storm`을 고르면 `test_asset_slots.gd`의 열쇠 규칙과 3.1의 고르는 규칙에 짝 표가 하나 생긴다.
2. **배율·걸음 폭의 벌**: 카메라 결정(아래 사용자 1)에 묶인다. 권고: 카메라 19.5면 (나) 1.588, 14면 (가) 1.32. HM-4의 화면 높이 측정이 나온 뒤 고른다. 고른 값은 자리표 숫자 두 개만 바뀐다.
3. **T7-3을 HM-1·나머지로 나누는 것**(5절). 나누지 않으면 T7-3 전체가 끝난 뒤 HM-2로 간다(며칠 늦어짐 [짐작]).
4. **메뉴에서도 고른 마녀의 몸을 보일지**. 이 문서는 메뉴를 오늘 그대로 둔다(옛 마법사). 메뉴의 마녀 고르기(`menu_character_id`)에 맞춰 바꾸려면 HM-2의 `_swap_hero_model`을 메뉴 쪽에서 부르는 일이 하나 더 생긴다.
5. **켜기 전에 남은 일**(꺼진 채 들어온 장치 규칙): (a) 사용자 카메라 결정과 배율 벌 (b) 부품이 몸을 파고드는 것(화염 어깨 갑옷, 번개 허리 자락, 냉기 목도리 — A7-4 REPORT 15행) (c) 피격 클립 바꾸기(Hit Reaction은 싸움 자세, 인계 메모 2-1) (d) 번개 발광 가면 없음, 화염 한 톤(인계 메모 3절) (e) HM-3 지팡이 화면 판정 (f) HM-4 프레임 시간과 끊김 (g) A7 TR-4(섞기·회피·시전 라우팅)을 켜기 전에 할지 뒤에 할지 (h) 원장과 출처 판단(아래 6) (i) art-lead 본체 검수 (j) 사용자 플레이. 이 열 가지가 0이 될 때 3.6의 기본값 한 줄을 바꾼다.
6. **출처**: 새 몸에 옛 마법사의 머리·장화·치마가 붙어 있다면 BY-SA 3.0 조건이 새 몸에도 따른다 [짐작]. 배포 전에 (가) 그 부품을 CC0나 자체 제작으로 바꾸거나 (나) BY-SA 조건을 받아들이는 판단이 필요하다. Mixamo 동작의 게임 포함 조건도 약관으로 확인해야 한다(이 문서에서 열어 보지 않음). 사용자 방침("출처 기록의 구멍은 지금 개발을 막지 않는다")에 따라 개발은 막지 않고, 원장에 그대로 적는다.

**사용자에게 물을 것**
1. 카메라 거리 19.5 / 14(인계 메모 5절, 아직 답 없음). 구조는 어느 쪽에서도 선다. 답에 따라 배율 숫자 하나가 정해진다.
2. Mixamo 달리기가 이제 괜찮은지(인계 메모 5절). HM-0이 고를 `run` 클립과 숫자가 이 답에 걸린다. 답이 "아니다"여도 HM-1·HM-2의 구조는 그대로 쓴다(자리표 숫자와 glb만 바뀐다).

## 7. 위험

| 위험 | 막는 법 |
|---|---|
| 꺼진 값에서 덤프가 갈림(JSON 숫자와 리터럴의 비트 차이, 연산 순서) | HM-1에서 `equiv.py`와 덤프 셋. 3.3 표의 식을 글자 그대로 |
| 모델을 바꾼 뒤 메뉴 복원이 옛 인덱스로 뼈·머티리얼을 덮음 | `rest_for_menu`가 먼저 기본 몸으로 되돌림(HM-2). 켠 값 메뉴 덤프 비교 |
| 시험 도구(`model_swap.gd`)가 기본 경로만 덮어 켠 값에서 무력해짐 | HM-4가 도구를 켠 값에 맞춤. 꺼진 값에서는 지금처럼 돈다 |
| 판 시작에 17MB 장면 인스턴스로 끊김 | 켠 값에서만 셋업 때 미리 로드. HM-4의 5번 측정 |
| 발광 가면을 텍스처 크기로 고르는 규칙이 다른 몸에서 틀림 | `mask_rule` 칸으로 규칙 이름을 남겨 다른 규칙을 더할 자리를 둠. 검사가 크기 일치를 확인 |
| 같은 파일 충돌(`chapter_actors.gd`) | HM-1~3 한 담당 순차, 그동안 다른 배정 막음 |

## 8. 확인하지 못한 것

- 새 몸 셋의 Godot 임포트 결과(임포트 뒤 뼈·클립 이름이 바뀌는지, 풀려 나온 PNG 이름). glb 머리 JSON만 읽었다.
- JSON 2.15와 코드 리터럴 2.15의 비트 동일(HM-1이 잡는다).
- `run_c06`의 실제 지면 속도(`clips.json`은 `run`과 같은 3.652를 적고 있어 길이를 줄인 클립의 값인지 원본 값인지 가리지 못했다). 3.4의 1.588은 `run`과 도구 설정에서 나온 값이다.
- 화면 높이 표(3.4)는 비례 계산이다. 카메라가 기울어 있어 실제 화소는 다를 수 있다.
- `equiv.py`가 한쪽에만 인수를 줄 수 있는지, `hud_dump`가 메뉴 복귀 흐름을 가지는지.
- `perf_probe.gd`가 `actors.sync`를 따로 적는지(QUALITY-TARGETS의 2026-11-17 측정은 따로 적었으나 어느 도구인지 이 문서에서 확인하지 않았다).
- Mixamo 약관, 면별 그림을 만든 생성 모델의 기록.
- 화면: 이 문서를 쓰며 캡처를 하나도 보지 않았다(보지 않음).
