# T9 — 그림 교체 파이프라인 도구와 관리 툴의 보기 화면

작성: tech-lead, 2026-11-22. 기준 커밋 `462c685`(main). 구현하지 않은 지시서다.

> **개정 1 — tech-lead, 2026-11-23.** 사용자 결정 U-89~U-91(`docs/DIRECTIVES-LEDGER.ko.md`): 3D 생성은 **Tripo를 웹에서 손으로**(구독, API 아님), 얼굴은 `face_reproject.py`로 다시 입힐 수 있고, 뼈대·동작은 **Mixamo 웹**. 냉기는 Tripo 모델(`pipeline/frost/tripo_out/20261123_tripo_smart_v2_8k_face2.glb`)을 채택해 15k로 줄이고 Mixamo에 올릴 FBX까지 왔다(`_local/t9-mixamo/GUIDE.ko.md`, `REPORT.txt`, `REPORT-walk.txt`).
> **장부 U-80("Tripo API로 파이프라인 점검")은 U-89로 바뀌었다**: API를 부르는 단계는 없다. Tripo 단계는 사람이 웹에서 하는 "주문" 단계다.
> 바뀐 절: 1(B2 두 줄), 2.5(지도 전체), 3.6(허용치 확정 — T10 2.1), 6.1~6.4(공급처 층, 사람 단계, 명령), 새 6.6(화염·번개를 같은 길로), 7의 B1-d·B2-a·B2-b, 8의 마지막 줄, 10의 R11·R12와 새 R18~R20. 개정 전 문장은 git 기록에 있다. B1-a·B1-b·B1-c는 끝났으므로(커밋 `819eda1`, `a0b8813`) 고치지 않았다.
받는 명세: `docs/OPEN-WORK-20261121.ko.md` 12절(12.1 단계 표, 12.2 보기 화면 표, 12.3 걷기), 10.1절(그림의 순서), 3절(주인공 3D의 지금 길).

표시: **[봄]** 코드·파일에서 직접 확인 · **[짐작]** 확인하지 않은 추정 · **[미확인]** 확인할 길을 아직 못 찾음 · **(모델의 답)** 계산식의 결과이며 게임에서 측정한 값이 아님.

---

## 0. 사용자 지시와 다섯 사상

**원문(장부 U-73)**. 전문은 `docs/OPEN-WORK-20261121.ko.md` 12절에 있다. 이 문서에 옮긴 부분:
"일단 이미지교체에 대한 모든 후속작업들을 파이프라인으로 진행할 수 있게 툴을 만들자 그때그때 따로 작업하지 말고 지금 냉기마녀 겜상의 뛰는 모습은 완전 별루야 차라리 걷는 모습으로 보고 싶어 그런데 이 일련의 과정들을 꼭 게임을 수행하지 않고서도 관리툴에서 볼 수 있게 해야잖아 스킬 종류와 설명 효과 이펙트 등 장비나 (…) 마찬가지고 그래야 디렉터도 편하지 않겠어 매번 나한테 묻지 않아도 되고"
덧붙임(11-21): "이것도 툴에 넣고 봐야 알거 같아 느낌상은 조금 빨리 걷는걸로 하면 괜찮을거 같았어"

**다섯 사상과의 관계**
| 묶음 | 키우는 것 | 까닭 |
|---|---|---|
| 1 캐릭터 화면(걸음 고르기) | 섹시, 쾌감 | 걸음걸이는 주인공의 매력이 가장 오래 보이는 자리다. 이동의 손맛(빠른 걸음 대 달리기)이 걸린다 |
| 2 파이프라인 도구 | (직접은 없음) 섹시의 바탕 | 메인 이미지 → 3D → 게임 → 영상 사슬(10.1)이 낱개 작업으로 끊기는 것을 막는다. 사용자 지시(U-73)이고 1차 차수라 뒤로 미루지 않는다 |
| 3 스킬 화면 | 쾌감, 성장 | 효과 영상과 스킬끼리의 영향을 한 화면에서 견준다 |
| 4 장비 화면 | 도박, 보상 | 무작위 표본과 등급색, 감정 전후 |
| 5 화폐·성장, 적·우두머리 | 보상, 성장 | 얻는 곳·쓰는 곳, 문턱의 박자 |

---

## 1. 한눈

| 묶음 | 담당 | 끝난 모양 | 의존 | 병렬 |
|---|---|---|---|---|
| **B1-a** 캐릭터 화면 + 고름 저장 + 계약 계산 + 적용 도구 | manager-tools | 관리 툴에서 냉기 마녀의 `run`과 `walk`를 나란히 돌리고, 동작 배율·이동 속도 막대를 움직이고, 발 미끄러짐 수치를 보고, 고름을 저장한다 | 없음 | B1-b, B1-c와 함께 |
| **B1-b** 게임 안 걸음 측정 도구 | qa-perf | 지금 계약과 덮어쓴 값으로 게임 안 동작 배율·발 미끄러짐을 숫자로 낸다. 화면 계산과 견주는 도구 | 없음(공식은 2.3절) | B1-a, B1-c와 함께 |
| **B1-c** 동작 후보 묶음 | character-artist | 받아 둔 Mixamo 걷기·달리기 후보 4~8개가 든 미리보기 glb와 지면 속도 보고서(저장소 밖) | 없음 | B1-a, B1-b와 함께 |
| **B1-d** 고른 값 적용과 확인 | character-artist | 사용자가 고른 값이 `asset_slots.json`에 들어가고, 게임 안 측정이 화면 계산과 맞는다 | B1-a·B1-b 병합, **사용자의 고름** | 단독(자리표 점유) |
| **B2-a** 파이프라인 도구 (개정 1) | manager-tools | `tools/art/pipeline.py status/next/order/run/mark/confirm/adopt`, 사람 단계(Tripo·Mixamo 웹)는 주문을 찍고 받은 파일을 기다림, 캐릭터 화면의 단계 칸이 「3D 만들기(수동)」 칸과 같은 폴더를 읽음 | B1-a 병합(끝남) | B2-b와 함께 |
| **B2-b** 일회용 스크립트를 도구로 + 세 마녀의 줄 (개정 1) | character-artist | Mixamo 올릴 FBX 만들기(`gen3d_to_fbx.py`)가 도구가 되고, 묶기 설정을 줄 정의에서 만들고, 세 마녀의 줄 정의가 생기고, 냉기의 Tripo 산출물이 `adopt`로 올라간다 | 도구 올리기는 없음, 줄 정의·adopt는 B2-a 뒤 | B2-a와 함께(앞 절반) |
| **B3** 스킬 화면 | qa-perf(효과 영상 뜨기) + manager-tools(화면) | 5.1절 | B1-a(고름 저장) | B4와 함께 |
| **B4** 장비 화면 | qa-perf(무작위 표본) + manager-tools(화면) | 5.2절 | B1-a | B3과 함께 |
| **B5** 화폐·성장, 적·우두머리 | manager-tools (+ 적은 B2의 줄) | 5.3·5.4절 | B2-a, B3 | — |

**첫 묶음이 가장 짧은 길인 까닭** [봄]: 지금 게임에 들어가는 냉기 몸 `chapter1/art/actors/hero/frost/model.glb`에 이미 클립 9개(`idle run walk cast cast_area hit death dodge dodge_back`)가 들어 있고, 곁의 `model.pack-report.json`에 클립마다 길이와 지면 속도가 있다. 그래서 파이프라인 도구 없이도 화면 하나(B1-a)만 있으면 사용자가 "달리기 대 빠른 걸음"을 고를 수 있다. B1-b·B1-c는 같은 때 돌아 고른 값이 게임에서 같은 결과인지 확인할 길과 후보를 더한다.

refactor-architect는 1·2묶음에 일이 없다(본체 코드를 고치지 않는 길로 짰다). 9절의 "계약 칸 이름 정리"가 생기면 그때 배정한다.

---

## 2. 코드에서 본 것

### 2.1 주인공 걸음이 게임에서 도는 방식 [봄]

- 계약은 **`chapter1/art/asset_slots.json`의 `actor.hero.frost.model.contract`** 에 있다(줄 58~102). `hero.json`(`chapter1/art/actors/hero/frost/hero.json`, git 밖)에는 `look`과 `staff`만 있다. 걸음 값은 hero.json이 아니라 자리표에 있다.
  - `contract.clips.run = "run"`, `contract.pose.run_time_scale = 0.5333333`, `contract.pose.stride_world_m = 5.104`, `contract.scale = 1.32`.
- `chapter_actors.gd`의 `_hero_slot_values()`(532~547)가 이것을 읽고, `_use_hero_values()`(549~557)가 `_clip_run`, `_run_time_scale`, `_hero_stride`에 넣는다.
- 걸음 위상: `_present_position()`(307~330)이 틱마다 `phase += 이동거리 / stride`로 올린다. `_update_pose__rigged()`(768)가 `clip_time = phase × run_time_scale`로 `_clip_run`을 샘플한다.
- 따라서:
  - `run_time_scale`은 이름과 달리 **한 주기의 길이(초)** 다. 클립 전체를 한 바퀴로 쓰려면 클립 길이와 같아야 한다.
  - 게임에서의 **동작 배율** r(클립을 원래 속도의 몇 배로 돌리는가) = `v × L / stride`. v = 이동 속도(m/s), L = 주기 길이(s).
  - 이동 속도가 바뀌면(장비 `move_speed_bps`) 위상이 거리로 움직이므로 배율이 같은 비로 따라 바뀐다. 보폭은 그대로다.
- 이동 속도 v: `chapter1/core/combat_core.gd:22 const BASE_SPEED := 5.8`에 장비 `move_speed_bps`를 곱한다(358). **데이터 파일이 아니라 코드 상수**다.
- `test_asset_slots.gd`의 `hero_checks()`(368~)는 `run_time_scale ≤ 클립 길이 + 0.001`과 `clips` 키 집합만 본다. `clips.run`에 `"walk"`를 넣고 `run_time_scale`을 걷기 길이로 바꾸면 이 검사를 그대로 지난다.
- 카메라: 직교, 위치 `CAMERA_OFFSET = (11, 19, 14)`에서 원점을 봄(`view/world/chapter_world.gd:9, 73~74`), 크기 `19.5`(`view/fx/combat_juice.gd:292`). 14는 사용자 결정 대기 중인 후보(OPEN-WORK 9절). Godot `Camera3D.size`가 세로 폭인지(기본 `keep_aspect = KEEP_HEIGHT`)는 [짐작: Godot 문서 기억, 이 프로젝트에서 확인 안 함].
- 주인공 전용 조명 둘: 키 `rotation_degrees(-42,-35,0)` 색 `eddbc4` 세기 1.6, 채움 `(-28,145,0)` 색 `7faad8` 세기 0.85(`chapter_actors.gd:463~464, 500`). 냉기 `hero.json`의 look이 키 0.65, 채움 0.38로 덮는다.
- 이 경로는 스위치 `--chapter1-hero-models`가 켜졌을 때만 돈다(461). 꺼진 기본 경로와 코어는 자리표의 냉기 칸을 읽지 않는다. 따라서 **냉기 칸의 걸음 값을 바꿔도 골든과 꺼진 값 덤프는 바뀌지 않는다** [짐작: 코드 경로로 본 결론, B1-d에서 실행으로 확인].

### 2.2 클립 수치 [봄: `model.pack-report.json`]

| 클립 | 원본 FBX | 길이 L(s) | 지면 속도(엉덩이 기준, 모델 공간 m/s) | 발끝 기준 |
|---|---|---|---|---|
| run | Fast Run.fbx | 0.53333 | 7.1168 | 7.2215 (설정 파일 값 7.25) |
| walk | Walking.fbx | 0.96667 | 2.0997 | 2.2125 |

지면 속도는 디딘 발이 엉덩이 기준으로 뒤로 가는 속도이고, 배율(1.32)을 곱하기 전 값이다. HM-2 보고(`_local/t2h/HM-2-frost/REPORT.txt`)가 같은 방법의 오차를 약 ±6%로 적었다.

### 2.3 계산 (모델의 답, 지면 속도 ±6%)

기호: s = 배율 1.32, g = 클립 지면 속도(발끝), L = 주기 길이, v = 이동 속도, r = 동작 배율.

- 보폭 계약 값: `stride_world_m = v × L / r`
- 발이 미끄러지지 않는 배율: `r0 = v / (g × s)`
- 평균 미끄러짐 속도: `slip = v − r × g × s` (양수: 발이 땅 위로 앞으로 끌려감, 음수: 러닝머신처럼 헛돎), 비율 = `slip / v`

| 경우 | v | r | stride_world_m | 미끄러짐 |
|---|---|---|---|---|
| 지금 계약(달리기) | 5.8 | 0.606 | 5.104 | 약 0 (g=7.25로 맞춘 값) |
| 걷기, 미끄럼 없음 | 5.8 | 1.99 | 2.82 | 0 — 다리가 두 배 빨리 감긴다 |
| 걷기, "조금 빨리"(예: 1.3배) | 5.8 | 1.3 | 4.31 | 2.0 m/s, 약 35% |
| 걷기 1.3배, 미끄럼 없게 속도를 낮춤 | 3.80 | 1.3 | 2.82 | 0 — 이동 속도 −35%, 코어 값 |
| 걷기 1.5배, 미끄럼 없게 | 4.38 | 1.5 | 2.82 | 0 — 이동 속도 −24% |

**디렉터가 미리 알 것**: 사용자가 말한 "조금 빨리 걷기"를 지금 이동 속도 그대로 붙이면 계산으로는 발이 3분의 1쯤 미끄러진다. 미끄러짐을 없애려면 다리를 두 배로 감거나(빨리 감기처럼 보임) 이동 속도를 낮춰야 한다(전투 균형, 코어). 화면은 이 셋을 막대 둘로 바로 보여 주는 것이 목적이고, 어느 쪽이 괜찮게 보이는지는 사용자가 화면에서 본다.

### 2.4 관리 툴의 지금 [봄]

- `tools/manager/server.py`: 표준 라이브러리 HTTP, 127.0.0.1만, Host·Origin 검사. 파일은 `/files/<경로>`로 카탈로그가 등록한 저장소 안 파일만 준다(`permitted_file`). 정적 파일은 `tools/manager/` 맨 위의 `.html/.js/.css`와 `STATIC_EXTRA = {'vendor/model-viewer.min.js'}`. `.mp4`는 `FILE_TYPES`에 없다. POST 길이 상한 65536.
- 화면은 왼쪽 단추 + `<section>` + 화면별 js + 파이썬 모듈 꼴이다(원화 시안 `drafts.js/drafts.py`, 플레이 기록, 균형 실험실, 도구, 점검). `index.html`이 각 js를 `defer` 고전 스크립트로 싣는다.
- 3D 미리보기: `vendor/model-viewer.min.js`(Google model-viewer 4.1.0, Apache-2.0, 오프라인)가 이미 있다. `app.js:114~136`이 클립 고르기와 돌림 단추를 준다. 하지만 **주인공 몸은 카탈로그에서 빠져 있다**(`catalog.py:772`, git 밖 폴더라서).
- 사용자 표시 저장 선례 둘: `drafts.py`의 판정(`like/hold/drop` + 메모, `tools/manager/local-drafts.json`)과 표시(`candidate/final/archive`, `_local/art/drafts/selection.json`). 둘 다 revision 검사 + 원자적 쓰기.
- 균형 실험실 약속: "게임 데이터 파일은 이 화면이 절대 고치지 않습니다"(`사용안내.ko.md`). 이 지시서도 같은 약속을 지킨다(3.5절).
- 관리 툴 화면 확인 선례: Edge 헤드리스로 캡처(`_local/manager-ui/REPORT.txt` 45줄). 도구로 올라가 있지 않다.
- 회귀: `run_all.py`의 `manager`가 `tools/manager/test_*.py`, `tools-selftest`가 `tools/dev/test_*.py`·`tools/art/test_*.py`를 모두 돈다. 새 시험 파일은 이름만 맞으면 자동으로 들어간다.

### 2.5 낱개 도구와 일회용 스크립트의 지도 (개정 1)

주인공 3D는 **공급처 층** 두 겹으로 만든다: 3D 생성은 Tripo(웹, 사람), 뼈대·동작은 Mixamo(웹, 사람). 그 사이와 앞뒤는 저장소 도구가 한다. 사람이 하는 단계는 파이프라인이 "주문"(무엇을 올리고, 어떤 설정으로, 받은 파일을 어디에 둘지)을 찍고 받은 파일을 기다린다.

| 단계 | 사람/도구 | 지금 있는 것 [봄] | 이 지시서에서의 처리 |
|---|---|---|---|
| ① 메인 이미지 | 사람 확정 | `tools/art/gen_queue.py`, `gallery.py`, 관리 툴 원화 시안(표시 `final`) | 그대로. 확정 = 원화 시안의 `final` |
| ② 보낼 그림 | 도구 | 턴어라운드 시트를 낱장으로: `tools/art/sheet_split.py`(새, U-89). A자세 생성: `_local/art/gen3d/run_apose*.py`·`post_apose*.py`(일회용) | 출력은 `pipeline/<id>/tripo_in/`(관리 툴 「3D 만들기(수동)」의 「보낼 그림」이 읽는 곳). A자세 일회용 스크립트를 도구로 올리는 일(옛 B2-b 1·2)은 **뒤로 미룬다** — 냉기는 시트 나누기로 Tripo에 보냈고, A자세 생성이 다시 필요해질 때 올린다 |
| ③ 3D 생성 | **사람: Tripo 웹** | 관리 툴 「3D 만들기(수동)」(보낼 그림 내려받기·경로 복사·폴더 열기, 받은 glb 넣기와 돌려 보기) [봄: `tools/manager/characters.py` 162~164, 224~225, 294행] | 주문: `tripo_in/`의 그림, 받은 glb는 `tripo_out/`. 무료 재시도·얼굴 재생성은 사람 판단. 채택한 파일 하나를 상태에 적는다 |
| ③-b 얼굴 다시 입히기(선택) | 도구 + 사람(표지점) | `tools/art/face_reproject.py`(새, U-91. 파이썬+numpy·scipy·Pillow, 메시·UV 불변, 질감만 바꿈). 얼굴 그림은 Dreamina(비용) | 출력은 `tripo_out/<이름>_face<N>.glb`(냉기 선례). 얼굴 그림 생성은 비용 단계(`--execute --yes`) |
| ④ 게임용 | 도구 | `gen3d_inspect.py`, `gen3d_prepare.py`(줄이기·UV·굽기, `--target 15000 --height 2.03 --face-boost 1.8`) | 출력 `pipeline/<id>/game_a/`(냉기 선례 이름). 비교용 `game_b/`·`game_c/`는 선택 |
| ⑤-a Mixamo에 올릴 FBX | 도구 | `D:/…/char3d/gen3d/to_fbx.py`(일회용) | **도구로 올린다**(B2-b): `tools/art/gen3d_to_fbx.py`. 출력 `pipeline/<id>/mixamo_in/<id>_t15k.fbx` |
| ⑤-b 뼈대·동작 | **사람: Mixamo 웹** | 냉기 안내서 `_local/t9-mixamo/GUIDE.ko.md`(표지점 주의, 받을 몸 1 + 동작 9, 설정, 파일 이름) | 주문의 본문은 이 안내서를 줄 정의의 동작 표로 만든 것. 받는 곳 `pipeline/<id>/mixamo_out/`. **동작은 몸마다 다시 받는다**(아래 R11) |
| ⑤-c 받은 것 살피기 | 도구 | `tools/art/mixamo_inspect.py`(뼈 수, 길이, 제자리, 반복 이음) | 그대로 부른다. 몸과 동작의 뼈 이름·수가 다르면 멈춘다 |
| ⑥ 묶기 | 도구 | `gen3d_mixamo_pack.py` + `gen3d_mixamo_blender.py`, 설정 `gen3d_mixamo_configs/<마녀>.json`(냉기 Tripo 몸은 작업 뿌리의 `pipeline/frost/frost.t15k.pack.json`) | 설정은 **줄 정의에서 만든다**(6.2): 파이프라인이 `pipeline/<id>/pack/pack.json`을 쓰고 그것으로 부른다. 출력은 `pipeline/<id>/pack/model.glb` + `model.pack-report.json` — **게임 자리가 아니다** |
| ⑦ 계약 검사 | 도구 | `rig_check.py --slot actor.hero.<key>.model --require-dodge`, `gen3d_views.py`(모양 판) | 그대로. `rig_check`의 기본 뼈 목록이 옛 길의 24개라 `--slot`을 줘도 뼈 줄이 어긋나게 나온다(냉기 걷기 미리보기 보고) → 6.6의 고칠 것 |
| ⑧ 게임에 끼워 보기 | 도구 | `gen3d_ingame.py --glb <pack/model.glb> --look <hero.json>`, `hero_burn.py`, `gen3d_sheet.py`, `rig_game_probe.gd` | 그대로. 제품 파일을 바꾸지 않는다 |
| ⑨ 걸음 고르기 | **사람: 관리 툴 캐릭터 화면** | 캐릭터 화면(걸음 나란히 보기, 배율·속도, 미끄러짐), 고름 저장(`picks.py`) | 새 몸의 `pack/model.pack-report.json`으로 화면 값을 다시 낸다. 게임 안 측정은 `motion_verify.py --report <그 보고서>`(T10 2.1) |
| ⑩ 적용 | 사람 확정 + 도구 | 없음(손으로 복사했음) | `pipeline.py run <id> apply --yes`: `pack/model.glb`·보고서를 자리표가 가리키는 자리로 복사, `motion_apply.py --pick`, `test_asset_slots.gd --strict`. 앞선 몸은 `pipeline/<id>/replaced/<날짜>/`로 옮겨 둔다 |
| ⑪ 파생 | 사람 확정 + 비용 | Dreamina CLI, 감싸는 도구 없음 | 그대로(주문만 찍음) |
| (옛 길) | — | `gen3d_rig.py`, `mesh_reduce/rig_*`, `docs/ART-3D-PIPELINE.ko.md`, HY 3D 웹 | 주인공은 Tripo + Mixamo 길. HY 3D는 줄 정의에서 공급처를 바꾸면 쓸 수 있게 남긴다(6.2 `supplier`) |

---

## 3. 캐릭터 화면 (묶음 1)

### 3.1 3D를 무엇으로 그리나

- **권고: three.js를 `tools/manager/vendor/three/`에 넣는다**(MIT). model-viewer로는 안 되는 것이 셋이다: 바닥을 이동 속도로 흘리는 것, 발끝 뼈의 세계 위치를 프레임마다 읽어 미끄러짐을 수치로 내는 것, 게임과 같은 직교 카메라. model-viewer는 속에 three.js를 품지만 장면을 공식으로 열어 주지 않는다 [짐작: 4.1.0 문서 기준].
- 넣을 파일: `three.module.min.js`, `addons/loaders/GLTFLoader.js`, `addons/controls/OrbitControls.js`, `addons/utils/SkeletonUtils.js`(나란히 보기 위해 같은 모델을 둘로 복제). 판 하나로 고정하고, `vendor/three/README.md`에 판 번호·내려받은 주소·크기·sha256, `LICENSE` 원문을 둔다(`vendor/README.md`의 model-viewer 꼴). 내려받기는 구현할 때 한 번만 인터넷을 쓰고, 화면은 인터넷 없이 뜬다.
- `index.html` 머리에 import map 한 줄: `{"imports":{"three":"/vendor/three/three.module.min.js","three/addons/":"/vendor/three/addons/"}}`. `character.js`는 다른 화면처럼 고전 스크립트로 싣고, 3D는 화면을 열 때 `import()`로 부른다(지금의 model-viewer 방식과 같음).
- `server.py`의 `STATIC_EXTRA`를 `vendor/three/` 아래의 위 파일 목록까지 넓힌다(폴더째 열지 않고 이름 목록으로).
- model-viewer는 지우지 않는다(카탈로그의 다른 모델 미리보기가 쓴다).

### 3.2 화면 구성

왼쪽 단추 「캐릭터」 → 줄 목록(지금은 냉기 하나, 자리표의 `actor.hero.*.model` 가운데 파일이 있는 것 + B2 뒤로는 파이프라인 줄) → 한 캐릭터 화면.

| 칸 | 내용 | 값의 출처 |
|---|---|---|
| 보기 둘(A·B) | 같은 몸을 두 칸에 나란히. 칸마다 클립 고르기, 동작 배율 막대(0.3~2.5, 0.01 단위) + 「미끄럼 없는 배율로」 단추 + 「게임 지금 값」 단추 | 몸: 자리표 `file`. 클립 목록: glb 머리. 후보 묶음이 있으면(B1-c) 그 glb의 클립도 고를 수 있게 칸마다 「몸 / 후보 묶음」 고르기 |
| 이동 속도 막대(두 칸 공통) | 2.0~8.0 m/s, 기본 = `BASE_SPEED`. 게임 값에 눈금. 값이 게임 값과 다르면 막대 옆에 "코어 값과 다름 — 제안으로만 저장됨" | `combat_core.gd`의 `BASE_SPEED`를 글로 읽음(카탈로그의 `gd_const` 같은 방식) |
| 바닥 | 바둑판 또는 게임 바닥 그림을 이동 속도로 뒤로 흘림. 디딘 발 자리에 짧게 남는 발자국 점(미끄러지면 점이 끌려 보인다) | — |
| 수치 띠(칸마다) | 동작 배율 r, 주기 길이 L, 보폭 계약 값 `v×L/r`, 계산 미끄러짐(m/s, %), **측정 미끄러짐**(화면 안에서 발끝 뼈로 잰 디딤 구간 RMS), 미끄럼 없는 배율 r0, 지면 속도 출처(보고서의 발끝/엉덩이 값, ±6%) | 2.3절의 식, `pack-report.json`, 측정은 3.3절 |
| 카메라 | 「게임 19.5」「게임 14」「자유(돌려 보기)」. 게임 두 값은 직교 카메라, 방향 (11,19,14)→원점, 세로 폭 19.5/14, 16:9 칸. 「1080p 크기」 표시를 켜면 칸 높이를 1080으로 놓았을 때 주인공이 차지할 화소 높이를 숫자로 | 2.1절 |
| 겉모습 | 「look 반영(근사)」 켬/끔: `albedo_mul`, `rim`, `light_key`, `light_fill`을 three.js 조명·머티리얼에 근사로 옮긴다. 화면에 "근사: 게임과 같은 색이 아님. 색 판단은 ⑦의 게임 캡처로" 한 줄 | `hero.json`의 `look` |
| 단계 칸 | 1묶음: 비어 있는 자리와 "파이프라인 도구가 들어오면 채워짐". B2-a가 채운다(4.4절) | — |
| 그림·영상 | 메인 이미지, A자세 앞·뒤·옆, 대기 영상(있으면) | 1묶음: 정해진 자리를 찾아봄 — `chapter1/art/characters/<key>_witch_v02.png`, `D:/Project/witch-moira-work/char3d/gen3d/<key>/{front,back,side}.png`, `D:/Project/witch-moira-work/video/idle/<key>_idle_*_pingpong.mp4`. B2 뒤로는 줄의 상태 파일에서 |
| 고르기 | 칸마다 「이걸로」「아님」「보류」 + 한 줄 말, 「저장」. 4절 | — |
| 바로 가는 주소 | 지금 상태를 담은 주소 `#character/frost?a=run@0.606&b=walk@1.3&v=5.8&cam=19.5`를 복사하는 단추. 디렉터가 사용자에게 "이 주소를 열어 보세요"로 물을 수 있다 | — |

캐릭터 키는 자리표 이름을 따른다(`frost`, `ember`, `arc`). 사람에게 보이는 이름은 `drafts.py`의 `CHARACTER_NAMES`처럼 한 곳에 둔다.

### 3.3 화면 안의 발 미끄러짐 측정

- 발끝 뼈: `mixamorig_LeftToeBase`, `mixamorig_RightToeBase`(glTF 안 이름은 `mixamorig:LeftToeBase`일 수 있음 — 둘 다 찾는다) [짐작: Mixamo 표준 이름, glb 안에서 확인 안 함].
- 프레임마다 발끝의 세계 위치를 구하고, 몸은 제자리이므로 땅에 대한 발끝 속도 = (발끝의 앞뒤 속도) + v. 디딤 = 발끝 높이가 그 클립의 최저 높이 + 3 cm(배율 적용 뒤) 안. 디딤 프레임의 땅 기준 수평 속도의 RMS를 "측정 미끄러짐"으로 낸다. `gen3d_mixamo_blender.py`의 `ground_speed()`(129~142)와 같은 생각이고, 숫자 정의를 같은 말로 `motion_math.py` 머리에 적는다.
- 프레임 시간에 따라 값이 흔들리지 않게, 측정은 렌더 프레임이 아니라 클립을 일정한 간격(1/120 s)으로 샘플한 값으로 한다(화면의 그림은 실시간, 수치는 따로 계산).

### 3.4 공용 계산 모듈

`tools/art/motion_math.py`(표준 라이브러리만): `rate_from_contract(v, L, stride)`, `stride_for(v, L, r)`, `rate_no_slip(v, g, s)`, `slip(v, r, g, s)`. 관리 툴(`characters.py`), 적용 도구(`motion_apply.py`), 검증 도구(`motion_verify.py`)가 모두 이것을 부른다. 같은 식이 세 곳에 따로 있지 않게 한다. 화면 쪽 JS의 같은 식은 서버가 내려 준 값을 쓰고, 막대를 움직일 때의 즉석 계산만 JS로 한다. JS와 파이썬의 식이 같은지는 시험(6절 B1-a 끝난 기준 3)이 본다.

### 3.5 고른 값이 본체로 가는 길

**화면은 게임 파일을 쓰지 않는다**(균형 실험실과 같은 약속). 길은 이렇다:

1. 사용자가 화면에서 「이걸로」를 누르고 저장 → 고름 기록(4절)에 `values`가 남는다:
   `{"line":"frost","slot":"actor.hero.frost.model","clip":"walk","clip_source":"body|motions","rate":1.3,"speed_seen":5.8,"speed_game":5.8,"L":0.96667,"stride_world_m":4.313,"slip_calc_mps":2.0,"slip_measured_mps":…,"camera":19.5,"look":true}`
2. 이동 속도 막대가 게임 값과 다르면 같은 기록에 `proposals: [{"to":"design-lead","what":"hero BASE_SPEED","value":3.8,"why":"걷기 1.3배에서 발이 미끄러지지 않는 속도"}]`가 붙고, `values`에는 두 벌이 들어간다: `contract_now`(게임 속도 5.8에서 같은 배율이 나오는 보폭)와 `contract_if_speed`(제안 속도에서 같은 배율이 나오는 보폭).
3. 디렉터가 기록을 읽고 B1-d를 배정 → character-artist가 `python tools/art/motion_apply.py --pick <id>`(기본은 바꿀 줄만 보여 줌) → `--write`로 `asset_slots.json`의 그 캐릭터 칸에서 `clips.run`, `pose.run_time_scale`(= L), `pose.stride_world_m`, 그리고 `source` 글의 걸음 문장을 고친다.
4. `motion_apply.py`는 **그 값들의 글자만 바꾼다**. JSON을 읽어 다시 쓰면 안 된다: 지금 파일은 `json.dumps(indent=2)`로 다시 쓰면 다른 줄 90바이트가 바뀐다(`"size": [1536, 1024]` 같은 한 줄 배열) [봄: 이번에 시험해 봄]. 고친 뒤 파일을 다시 읽어 세 값이 기대와 같고 나머지 칸이 그대로인지 스스로 확인한다.
5. 이동 속도 제안은 B1-d가 적용하지 않는다. design-lead가 전투 균형과 함께 보고, 채택되면 `BASE_SPEED`를 데이터 파일로 옮기는 일(gameplay-systems, 골든 갱신 포함)과 함께 따로 지시서가 나간다.

### 3.6 본체에서 같은 결과인지

- **계약 수준**(B1-a의 `motion_apply.py --check`): 적용 뒤 자리표에서 읽은 `v×L/stride`가 고름의 `rate`와 1e-3 안에서 같은가. 산술이라 틀리면 적용 도구의 결함이다.
- **게임 수준**(B1-b의 `hero_motion_probe.gd` + `motion_verify.py`): 실제 게임 장면에서 스위치를 켜고 걸을 때, 프레임마다 클립 시각과 발끝 뼈의 세계 위치를 읽어 (가) 동작 배율 실측 (나) 디딤 미끄러짐 RMS를 낸다. 화면의 값과 견준다: 배율 차 2% 안, 미끄러짐은 **화면이 같은 조건에서 잰 값과의 차** 0.15 m/s 안이면 "같음". (개정 1: B1-b 실측 — 달리기 +0.040, 걷기 1.3배 −0.009 — 을 보고 고정. 게임 안 측정에는 디딤 흔들림의 바닥(달리기 약 0.4, 걷기 약 0.2 m/s)이 있어 계산값과는 견주지 않는다. 화면 값이 없으면 미끄러짐은 판정하지 않고 종료 코드 3. 자세한 규칙과 지시서는 `T10-pity-save-key-and-tech-decisions-20261123.ko.md` 2.1·2.4.)
- 적용 전에도 덮어쓴 값(`--pose-override`)으로 같은 측정을 해 둘 수 있으므로, 사용자가 고르기 전에 디렉터가 "화면 값과 게임이 맞는다"를 먼저 확인할 수 있다.

---

## 4. 고름과 표시가 디렉터에게 닿는 길

### 4.1 저장 자리

`tools/manager/picks.py` + 저장 파일 `tools/manager/local-picks.json`(`tools/manager/.gitignore`에 한 줄 더함, `local-state.json`과 같은 대접). `_local/`에 두지 않는 까닭: `_local`은 "언제든 지워도 되는" 곳이고 사용자의 결정은 지워지면 안 된다. `tools/dev/move_bundle.py`의 옮길 목록에 이 파일을 더한다(지금은 `local-state.json`·`local-drafts.json`도 빠져 있다 [봄: `LOCAL_KEEP`, `PARTS`] — 같은 줄에서 함께 더한다).

### 4.2 꼴

```json
{
  "revision": 12,
  "records": {
    "pk-20261122-153012-frost-locomotion": {
      "screen": "character",
      "subject": "frost/locomotion",
      "verdict": "pick",
      "note": "조금 빠른 걸음이 낫다",
      "values": { "...": "3.5절" },
      "proposals": [],
      "by": "user",
      "created": "2026-11-22 15:30:12",
      "status": "open",
      "closed_ref": ""
    }
  }
}
```

- `verdict`: `pick`(이걸로) · `reject`(아님) · `hold`(보류) · `note`(표시 없이 말만).
- `subject`는 화면이 정한다: `<캐릭터>/locomotion`, `skill/<id>`, `item/<id>`, `enemy/<id>` 등. 한 `subject`에 여러 기록이 쌓이며, 마지막 `pick`이 그 주제의 답이다.
- POST `/api/picks`: `{revision, action:"add"|"update", id?, record}`. revision이 어긋나면 409(지금 `drafts.py`와 같은 규칙). `by`는 서버가 `"user"`로 채운다(화면에서 온 것만 사용자 것).
- 명령줄: `python tools/manager/picks.py list [--open] [--subject frost/] [--json]`, `python tools/manager/picks.py close <id> --ref "<커밋이나 지시서>"`. **에이전트가 기록을 더하는 명령은 두지 않는다**(사용자의 답을 에이전트가 만들 수 없게). 에이전트는 닫기만 한다.
- 디렉터의 쓰임: 세션을 열면 `picks.py list --open`을 본다. 사용자에게 묻기 전에 그 주제의 기록이 있는지 본다.
- 원화 시안의 옛 판정(`local-drafts.json`)과 표시(`selection.json`)는 옮기지 않는다. 그 화면은 그대로 둔다.

---

## 5. 둘째 묶음 이후의 보기 화면

공통 규칙:
- 값은 데이터 파일에서 서버가 열 때마다 읽는다. 해석은 `catalog.py`에 이미 있는 함수를 불러 쓴다(같은 파싱을 두 번 짜지 않는다). 카탈로그의 항목(`run:skill:*`, `gear:*` 등)과 새 화면 사이에 서로 가는 고리를 단다.
- 캡처·영상은 도구가 떠서 `_local/manager-media/<화면>/`에 두고, 같은 폴더의 `index.json`(무엇을, 어느 커밋에서, 어느 명령으로 떴는지)을 관리 툴이 읽는다. 색인에 없는 파일은 주지 않는다. 오래된 캡처(색인의 커밋 ≠ 지금 HEAD이고 관련 데이터 파일이 그 뒤 바뀜)는 "낡음" 꼬리표.
- 고름은 4절의 같은 저장으로.
- `.mp4`를 주려면 `server.py`에 `video/mp4`와 범위 요청(206) 하나를 더한다. 범위 요청 없이도 도는지는 [미확인].

### 5.1 스킬 화면 (B3) — 쾌감, 성장

| 보일 것 | 읽는 곳 |
|---|---|
| 기술마다 이름·설명·랭크별 수치·진화 | `chapter1/data/growth_quality37.json`(skills, ranks, evolution, passives) [봄], 이름·설명 글은 `chapter1/i18n/ko.po`·`en.po`에서 오는지 [미확인] |
| 판 안 주문 구성(꺼진 채) | `chapter1/data/run_spells.json`(spells 6, pairs, statuses, `enabled:false`) [봄] |
| 한 스킬이 다른 스킬에 주는 영향 | `run_spells.json`의 `pairs`(`kind: detonate` 등, a→b, status), `skill_trees.json`의 `synergies`, `combat_tuning.json`의 `primary_bonus`·`children` [봄]. 그림: 스킬을 점, 영향을 화살표로 그린 판 + 같은 내용의 표 |
| 아이콘·은총 카드 | 자리표 `icon.spell.*`, `ui.grace.spell.*`, `ui.grace.emblem.*`, `ui.grace.frame.*` [봄] → `slot_paths`로 파일 경로. 카드 모습은 `scene_shot.gd --scenes=boon_spells`(픽스처 `boon_spells.*.json`) 캡처 [봄: 도구 색인] |
| 효과 영상 | 새 도구 `tools/dev/fx_clips.py`(qa-perf): 기술마다 `hud_dump.gd --primary=<id> --burst=cast:… --burst-frames=N --shots=…`(판 안 주문은 `--run-spells=on`)로 낱장을 뜨고, `fx_strip.py`로 띠 한 장, `gen3d_video.py`나 ffmpeg로 짧은 mp4. 결과 `_local/manager-media/skills/<skill_id>/` + `index.json`. `--burst`의 이벤트 이름 규칙은 `chapter1/tests/burst_capture.gd` 머리 [봄]. 기술마다 시전 이벤트를 무엇으로 거르는지는 [미확인] — qa-perf가 첫 일로 표를 만든다 |

겹침: 카탈로그 「한 판의 기술과 은총」이 랭크 표와 패시브를 이미 보인다. 새 화면은 표를 다시 그리지 않고 카드·영향 그림·영상을 더한다.

### 5.2 장비 화면 (B4) — 도박, 보상

| 보일 것 | 읽는 곳 |
|---|---|
| 칸·등급·접사 문법·전설·고유·보물 등급표 | `chapter1/data/loot.json` [봄] — 카탈로그 「장비」가 이미 낱개 항목으로 보임 |
| 등급색 | `chapter1/view/hud/palette.gd`의 등급 색 [미확인: 상수 이름] |
| 아이콘 | 자리표와 `tools/art/make_equipment_icons.py`의 산출 [봄: 도구 있음, 자리 이름 미확인] |
| 무작위 표본 | 새 도구 `chapter1/tests/loot_samples.gd`(qa-perf, 헤드리스): 실제 코어 `loot.gd`로 시드를 바꿔 등급별 N개를 굴려 `_local/manager-media/loot/samples.json`. 「다시 굴리기」 단추는 서버가 이 도구를 돌린다(균형 실험실의 실행 방식, 동시에 하나, 시간 제한) |
| 감정 전후 | `veiled`·`identify`가 코드에 아직 없다(OPEN-WORK 5절, D21 W6) → 그 칸은 "D21 W6 뒤" 자리만 |

### 5.3 화폐·성장 (B5) — 보상, 성장

- 지금 데이터에서 찾은 화폐는 **essence** 하나다: `character_progression.json`의 `respec.essence_per_point`, `chapter_profile.gd`의 `essence`·`essence_gained` [봄]. 상점·금화는 코드에 없다(OPEN-WORK 5절). `winter_shard`는 장비(부적)이지 화폐가 아니다 [봄: `loot.json`].
- 레벨 문턱은 세 곳: `character_progression.json`(영구), `growth_quality37.json`의 `xp_thresholds`(한 판), `combat_tuning.json`의 `xp_thresholds`(한 판, 카탈로그가 "어느 쪽이 쓰이는지 코드에서 확인해야 함"이라 적음) [봄]. 화면은 셋을 한 그래프에 얹고 어느 것이 실제로 쓰이는지 모르면 그렇게 적는다.
- 은총 간격: `growth.json`·`descent.json`에 있는지 [미확인].
- 곡선의 시간 축은 시뮬레이터(`sim_progression.gd`, `tools/dev/sim_economy.py`)의 결과를 "모델의 답"으로 붙인다.
- 겹침: 카탈로그 「영구 성장」「전투 수치」의 레벨 표. 새 화면은 그래프와 얻는 곳·쓰는 곳 흐름도를 더한다.

### 5.4 적·우두머리 (B5)

- 수치: `combat_tuning.json`의 `enemies`·`champions`·`elites`(꺼짐) [봄], 코드 기본값 `combat_core.gd:35~38` [봄].
- 생김새: 자리표의 적 모델(사슬 수문장 `chained_warden/v01/…glb` 등) [봄: `chapter_actors.gd:802`]. 캐릭터 화면을 그대로 다시 써서 돌려 본다(같은 `character.js`, 줄 종류만 다름).
- 공격 꼴: 적 클립 `windup_<kind>`, `fan`, `slam`, `walk` [봄: `chapter_actors.gd:898~915`]. 공격 영상은 5.1의 `fx_clips.py`를 적 이벤트로도 쓰게 넓힌다.
- 앞으로의 우두머리·정예·악마 원화와 3D는 파이프라인의 줄로 올린다(6.2절의 줄 종류).
- 겹침: 카탈로그 「전투 수치」의 적·수호자 항목.

---

## 6. 파이프라인 도구 (묶음 2)

### 6.1 파일의 자리와 경계

| 무엇 | 자리 | git |
|---|---|---|
| 도구 | `tools/art/pipeline.py`(표준 라이브러리만, 낱개 도구는 `subprocess`로 부름) | 올림 |
| 줄 정의(캐릭터 하나 = 파일 하나) | `tools/art/pipeline_lines/<id>.json` | 올림 |
| 작업 뿌리 | 환경 변수 `MOIRA_WORK_ROOT`, 없으면 `D:/Project/witch-moira-work` | 밖 |
| 줄의 작업 폴더 | `<작업 뿌리>/pipeline/<id>/<폴더>/` — 폴더 이름은 냉기가 이미 쓰는 것을 표준으로 한다: `tripo_in`, `tripo_out`, `face`, `game_a`, `mixamo_in`, `mixamo_out`, `pack`, `motions`, `replaced` (개정 1). 관리 툴 「3D 만들기(수동)」이 `tripo_in`·`tripo_out`을 이미 읽는다 | 밖 |
| 상태 파일 | `<작업 뿌리>/pipeline/<id>/state.json` — 원본과 같은 곳에 둔다(원본 없는 상태는 뜻이 없다). PC 이사 때 `move_bundle.py`가 `witch-moira-work`를 통째로 옮긴다 [봄] | 밖 |
| 확인 캡처(⑦) | `_local/pipeline/<id>/check/` (지워지면 ⑦이 "없음"이 되고 다시 돌리면 된다) | 밖 |
| 게임에 들어가는 것(⑥ 출력) | 자리표가 가리키는 자리(`chapter1/art/actors/hero/<key>/` 등) + `asset_slots.json`의 칸 | 몸은 지금 `.gitignore`(약관 확인 전), 자리표는 올림 |

- 상태의 경로는 `work:`·`repo:`·`local:` 접두를 붙인 상대 경로로 적는다(드라이브가 바뀌어도 읽힘).
- 기존 냉기 원본은 옮기지 않는다. `adopt`가 지금 자리를 그대로 상태에 적는다. (개정 1) 냉기의 채택 줄은 Tripo 몸이다: `pipeline/frost/tripo_out/20261123_tripo_smart_v2_8k_face2.glb` → `game_a/` → `mixamo_in/frost_t15k.fbx` → `mixamo_out/`(받는 중). 게임에 지금 들어가 있는 앞선 몸(`char3d/gen3d/frost/…`, `downloads/mixamo/frost_rigged/…`)은 `adopt --as replaced`로 "바뀔 것"으로만 적는다.

### 6.2 줄 정의 (개정 1)

```json
{
  "id": "frost",
  "kind": "hero",
  "name": "냉기 마녀",
  "slot": "actor.hero.frost.model",
  "supplier": {"gen3d": "tripo_web", "rig": "mixamo_web"},
  "stages": {
    "main":     {"human": "confirm", "how": "원화 시안에서 final 표시", "outputs": ["main/main.png"]},
    "views":    {"tool": "sheet_split", "inputs": ["@main"], "args": {"names": ["front","left","back"]}, "outputs": ["tripo_in/*.png"]},
    "gen3d":    {"human": "order", "site": "tripo_web", "give": ["tripo_in/*.png"], "receive": "tripo_out/*.glb", "pick_one": true},
    "face":     {"optional": true, "tool": "face_reproject", "inputs": ["@gen3d", "face/face_front.png", "face/landmarks.json"], "cost_inputs": {"face/face_front.png": "dreamina"}, "outputs": ["tripo_out/{stem}_face{n}.glb"]},
    "game":     {"tool": "gen3d_prepare", "inputs": ["@face|@gen3d"], "args": {"target": 15000, "height": 2.03, "face_boost": 1.8}, "outputs": ["game_a/{id}_t15k.glb", "game_a/{id}_t15k_color.png", "game_a/{id}_t15k_normal.png"]},
    "rig_in":   {"tool": "gen3d_to_fbx", "inputs": ["@game"], "outputs": ["mixamo_in/{id}_t15k.fbx"]},
    "rig":      {"human": "order", "site": "mixamo_web", "give": ["mixamo_in/{id}_t15k.fbx"], "receive": "mixamo_out/*.fbx",
                 "body": "{id}_t15k.fbx", "motions": "hero_default"},
    "inspect":  {"tool": "mixamo_inspect", "inputs": ["@rig"], "outputs": ["local:pipeline/{id}/mixamo_inspect.json"]},
    "pack":     {"tool": "gen3d_mixamo_pack", "inputs": ["@rig", "@game"], "config": "generated", "outputs": ["pack/model.glb", "pack/model.pack-report.json"]},
    "check":    {"tool": ["rig_check", "gen3d_views"], "inputs": ["@pack"], "outputs": ["local:pipeline/{id}/check/"]},
    "ingame":   {"tool": ["gen3d_ingame", "motion_verify"], "inputs": ["@pack"], "godot": true, "outputs": ["local:pipeline/{id}/ingame/"]},
    "walk":     {"human": "pick", "where": "관리 툴 캐릭터 화면", "inputs": ["@pack"], "outputs": ["picks:{id}/locomotion"]},
    "apply":    {"human": "confirm", "tool": ["copy_to_slot", "motion_apply", "test_asset_slots"], "inputs": ["@pack", "@walk"], "outputs": ["repo:chapter1/art/actors/hero/{key}/model.glb"]},
    "derive":   {"human": "confirm", "cost": "dreamina", "inputs": ["@main", "@ingame"], "outputs": ["derive/"]}
  }
}
```

- `kind`: `hero`(위 전부), `boss`·`elite`(① ~ ⑧, ⑩은 그 적의 자리표 칸으로, ⑨ 없음), `demon`·`portrait`(①과 ⑪만: 2D). 종류별 기본 단계는 도구 안의 표 하나에 두고, 줄 정의는 다른 점만 적는다.
- `supplier`: 공급처 층. `gen3d`는 `tripo_web`(기본) 또는 `hy3d_web`, `rig`는 `mixamo_web`. 공급처가 바뀌면 그 단계의 주문 글과 받는 파일 꼴만 바뀐다. **API를 부르는 공급처는 두지 않는다**(U-89).
- `human: "order"` 단계는 **주문을 찍고 기다린다**: `pipeline.py order <id> <단계>`가 올릴 파일의 절대 경로, 사이트에서 고를 설정, 받은 파일을 둘 폴더와 이름 규칙을 찍고 상태를 `waiting_human`으로 둔다. 사람이 받은 파일을 그 폴더에 넣으면(관리 툴 「받은 모델 넣기」도 같은 폴더) 다음 `status`가 파일을 찾아 해시를 적고 다음 단계를 `ready`로 바꾼다. `pick_one`이면 여러 파일 가운데 하나를 `pipeline.py mark <id> gen3d --file <이름>`으로 채택한다(냉기는 재시도 셋 가운데 하나).
- `motions: "hero_default"`: Mixamo에서 받을 동작 표(게임 이름, 검색어, In Place, 받을 파일 이름, 프레임 자르기)는 도구 안의 표 하나에 둔다. 처음 값은 냉기 안내서 C-2의 아홉 줄(idle, run, walk, cast, cast_area, hit, death, dodge, dodge_back). 받을 때의 공통 설정(FBX Binary, 30fps, 키프레임 줄이기 none, 동작은 Without Skin, 몸은 With Skin)도 그 표에.
- `config: "generated"`: ⑥의 설정 JSON은 줄 정의 + 동작 표 + 앞 단계 출력으로 파이프라인이 `pack/pack.json`에 만든다. 저장소의 `gen3d_mixamo_configs/<key>.json`은 앞선 몸의 기록으로 남기고 새 몸에 쓰지 않는다(D 드라이브 절대 경로를 저장소에 새로 넣지 않으려고).
- `@<단계>`는 앞 단계의 출력, `@a|@b`는 앞의 것이 있으면 그것. 낡음 판정이 이 고리로 흐른다.
- `godot: true` 단계는 본 저장소에서 회귀가 도는 동안 돌리지 않는다(`run`이 `tools/dev/godot.py`의 잠금을 보고 기다리거나 멈춘다).

### 6.3 상태 파일과 "낡음"

```json
{
  "line": "frost", "updated": "2026-11-22 16:00:00",
  "stages": {
    "game": {
      "status": "done",
      "inputs":  [{"path": "work:pipeline/frost/gen3d/frost_hy31.glb", "sha256": "…", "size": 40213344}],
      "args_sha": "…", "tool": "tools/art/gen3d_prepare.py", "tool_sha": "…",
      "outputs": [{"path": "work:pipeline/frost/game/low15k.glb", "sha256": "…"}],
      "started": "…", "finished": "…", "log": "work:pipeline/frost/game/run.log", "by": "pipeline", "note": ""
    }
  }
}
```

- `status`: `missing`(입력이 아직 없음) · `ready`(돌릴 수 있음) · `waiting_human`(사람 손을 기다림 — 주문이 찍혔고 받는 폴더가 비어 있음) · `waiting_pick`(받은 파일이 둘 이상인데 채택이 없음, 개정 1) · `waiting_cost`(비용 승인을 기다림) · `running` · `done` · `stale`(낡음) · `failed`. 사람 단계의 상태에는 `order_printed`(시각)와 `received`(파일 목록·해시)를 적는다.
- **낡음**: 어떤 단계의 기록된 입력 해시가 앞 단계의 지금 출력 해시와 다르거나, `args_sha`·줄 정의가 바뀌었거나, 출력 파일이 사라졌거나 해시가 바뀌면 그 단계와 그 뒤 모든 단계가 `stale`. `tool_sha`(도구 파일의 해시)가 바뀐 것은 낡음이 아니라 "도구가 바뀜" 알림만(도구 고침마다 모든 줄이 낡지 않게).
- 해시는 큰 파일에서 느리므로 (경로, 크기, mtime) → sha256 저장소를 `<작업 뿌리>/pipeline/.hash-cache.json`에 둔다.
- 상태 파일 쓰기는 원자적(임시 파일 → `os.replace`), 줄마다 잠금 파일 하나(두 명령이 한 줄을 같이 돌리지 않게).

### 6.4 명령

```
python tools/art/pipeline.py status [<id>|--all] [--json]       # 표: 줄 × 단계, 낡음·기다림의 까닭 한 줄
python tools/art/pipeline.py next <id>                          # 다음에 할 일을 문장으로(돌리지 않음)
python tools/art/pipeline.py order <id> <단계>                   # 사람 단계(Tripo·Mixamo 웹)의 주문을 다시 찍음(개정 1)
python tools/art/pipeline.py run <id> [<단계>] [--until <단계>]   # 자동 단계를 차례로 돌리고, 사람 손·비용 단계에서 멈춰 안내를 찍음
python tools/art/pipeline.py run <id> apose --execute --yes     # 비용이 드는 단계(Codex·Dreamina)는 두 깃발이 있어야만 실제로 부름(gen_queue.py와 같은 약속)
python tools/art/pipeline.py mark <id> <단계> --file <받은 파일>  # 받은 파일(Tripo glb, Mixamo FBX)을 받는 폴더로 복사하고 해시를 적음. 이미 폴더에 있으면 채택만
python tools/art/pipeline.py confirm <id> main [--from-gallery]  # ①·⑧의 사용자 확정을 적음. --from-gallery는 원화 시안의 final 표시를 읽음
python tools/art/pipeline.py adopt <id>                          # 이미 있는 산출물을 지금 자리 그대로 done으로 올림(냉기)
python tools/art/pipeline.py doctor                              # Blender·ffmpeg·Codex·Dreamina CLI·작업 뿌리가 있는지
python tools/art/pipeline.py ledger <id>                         # 저장소에 들어가는 출력의 원장 add 명령을 찍음(실행은 사람이)
```

- `run`은 낱개 도구를 **고치지 않고** 명령줄 인수로 부른다. 낱개 도구의 출력·종료 코드·마지막 20줄을 `log`에 남긴다.
- 사람 단계에서 찍는 주문의 꼴(개정 1, 예):
  `③ 3D 생성 — 사람: Tripo 웹(구독). 올릴 그림(여러 면): D:\…\pipeline\frost\tripo_in\front.png, left.png, back.png — 관리 툴 캐릭터 화면 「3D 만들기(수동)」에서도 내려받을 수 있음. 받은 glb는 D:\…\pipeline\frost\tripo_out\ 에 넣으세요(관리 툴 「받은 모델 넣기」도 같은 곳). 여러 개면 "python tools/art/pipeline.py mark frost gen3d --file <이름>"으로 하나를 고르세요.`
  `⑤-b 뼈대·동작 — 사람: Mixamo 웹. 올릴 파일: …\mixamo_in\frost_t15k.fbx. 표지점 주의 …(줄 정의의 메모). 받을 것: 몸 1(With Skin, 이름 frost_t15k.fbx) + 동작 9(Without Skin, 30fps, 키프레임 줄이기 none, In Place는 run·walk만) — 표: … 받는 곳: …\mixamo_out\. 다 넣으면 "python tools/art/pipeline.py run frost"`
- 사람 단계는 기다리기만 하고 시간 제한이 없다. `status`는 사람 단계에서 멈춘 줄을 "누가 무엇을 기다리는지" 한 줄로 보인다(디렉터가 사용자에게 전할 문장).
- ⑤의 동작 다시 쓰기(개정 1): **몸이 바뀌면 동작은 다시 받는다.** 받아 둔 Mixamo 동작 FBX에는 뼈 위치 키가 들어 있어 그 동작을 받을 때의 뼈 길이를 새 몸에 덮어쓴다(`gen3d_mixamo_blender.py`는 이름만 맞춰 얹고 옮겨 붙이기를 하지 않음, 냉기 Tripo 보고 3절). `inspect` 단계는 몸과 동작의 뼈 이름·수가 같은지(같은 Mixamo 캐릭터에서 받았는지)만 본다. 냉기 Tripo 몸은 뼈 65개(표준)로 받았다 — 앞선 몸 41개와 섞지 않는다.
- ⑦의 결과(캡처 판, 타는 화소, 걸음 측정)는 캐릭터 화면의 단계 칸과 그림 칸에 그대로 뜬다.

### 6.5 원장

`ledger <id>`는 `asset_ledger.py add …` 명령을 채워 찍는다(출처 HY 3D·Mixamo·Dreamina, 모델, 프롬프트 파일, 날짜, "출시 전 약관 확인"). 주인공 몸 폴더는 지금 원장 점검에서 빠져 있다(`asset_ledger.py:93 NOT_KEPT_PREFIXES`) [봄]. 이 빼기를 푸는 것은 사용자의 약관 결정 뒤이고 이 지시서의 일이 아니다.

### 6.6 화염·번개 마녀를 같은 길로 (개정 1)

냉기가 지난 길(그림 → 시트 나누기 → Tripo 웹 → 얼굴 입히기 → 15k → Mixamo 웹 → 묶기 → 검사 → 끼워 보기 → 걸음 → 적용)을 둘째·셋째 마녀가 그대로 타려면:

| # | 필요한 것 | 지금 | 담당 |
|---|---|---|---|
| 1 | 확정된 메인 이미지와 Tripo에 보낼 여러 면 그림(턴어라운드 시트 또는 A자세 셋) | 원화 시안의 `final` 여부를 줄마다 확인 [미확인] | art-lead → 디렉터(사용자 확정) |
| 2 | 줄 정의 `pipeline_lines/ember.json`, `storm.json`(자리표 키 `ember`, `arc`와 줄 id의 대응을 줄 정의에 적음) | 없음 | character-artist(B2-b) |
| 3 | 사람 단계 두 번(Tripo 재시도 포함, Mixamo 몸 1 + 동작 9) | 사용자 시간. 냉기의 Tripo 무료 재시도 3회, Mixamo 무료 | 사용자 |
| 4 | 얼굴 다시 입히기의 정면 얼굴 그림(비용, Dreamina 약 11크레딧/장 — 냉기 선례)과 표지점 json | 냉기 것만 있음 | character-artist(비용은 디렉터 승인) |
| 5 | 마녀별 `look`(빛·색 보정) json — 냉기는 `gen3d_mixamo_configs/frost.hero.json` | 없음 | character-artist |
| 6 | `rig_check.py`가 `--slot`의 자리표 계약에서 뼈 목록을 읽게(지금 기본 24개 옛 이름이라 Mixamo 몸에서 뼈 줄이 어긋남으로 나옴) | 고칠 것 | B2-b(도구 고침, `rig_check`의 기본 동작은 그대로 두고 `--slot`일 때만) |
| 7 | 자리표 `actor.hero.ember.model`·`actor.hero.arc.model` 칸의 계약(clips·pose·scale) | 냉기 칸만 채워짐 [짐작: 다른 칸의 꼴은 T7-3에서 확인] | T7-3 담당과 디렉터 차례 |
| 8 | 게임이 마녀별 몸을 고르는 길(`--chapter1-hero-models`가 냉기 칸만 보는지) | [미확인] | gameplay 쪽이 아니라 표현(`chapter_actors.gd`) — 별도 지시서, 이 문서 밖 |
| 9 | 손이 나팔 치마를 파고드는 흠(냉기 걷기에서 봄): 마녀 옷 꼴이 비슷하면 같은 흠 | 냉기 미해결 | 원화 단계(art-lead)에서 치마 폭을 먼저 볼 것 |

---

## 7. 지시서 (그대로 전달)

### B1-a — manager-tools: 캐릭터 화면, 고름 저장, 걸음 계산, 적용 도구

**목표**: 관리 툴에서 게임을 띄우지 않고 냉기 마녀의 걸음 후보(지금 몸의 `run`·`walk`, 있으면 후보 묶음의 클립)를 나란히 돌려 보고, 동작 배율과 이동 속도를 따로 움직이며 발 미끄러짐을 수치로 보고, 고른 값을 저장한다. 고른 값을 게임 자리표로 옮기는 도구를 만든다(이 묶음에서는 실제 자리표를 고치지 않는다).

**먼저 읽을 것**: 이 문서 2.1~2.4, 3, 4절. `tools/manager/server.py`, `drafts.py`(저장 꼴의 선례), `app.js:110~140`(지금의 3D 미리보기), `사용안내.ko.md`, `chapter1/art/asset_slots.json`의 `actor.hero.frost.model`, `chapter1/art/actors/hero/frost/model.pack-report.json`, `chapter1/view/actors/chapter_actors.gd:532~557, 307~330, 750~780`(읽기만), `tools/art/slot_paths.py`.

**만들거나 고칠 파일(이 밖은 건드리지 않음)**:
- 새: `tools/manager/vendor/three/`(3.1절의 파일, `README.md`, `LICENSE`), `tools/manager/character.js`, `tools/manager/characters.py`, `tools/manager/picks.py`, `tools/manager/test_characters.py`, `tools/manager/test_picks.py`, `tools/manager/ui_shot.py`, `tools/art/motion_math.py`, `tools/art/motion_apply.py`, `tools/art/test_motion_math.py`(motion_apply의 글자 고침 시험 포함, 자리표 사본을 임시 폴더에 만들어 씀).
- 고침: `tools/manager/server.py`(경로: `GET /api/characters`, `GET /api/characters/<id>`, `GET /media/<id>/<key>`, `GET/POST /api/picks`; `STATIC_EXTRA`; `FILE_TYPES`에 `.mp4`와 범위 요청), `tools/manager/index.html`(import map, 단추, `<section id="character">`, 스크립트 한 줄), `tools/manager/app.css`(화면 꼴, 기존 토큰만 씀), `tools/manager/.gitignore`(`local-picks.json`, `local-picks.tmp`), `tools/manager/사용안내.ko.md`(「캐릭터」 절), `tools/manager/tools_index.json`과 다시 만든 `docs/TOOLS-INDEX.ko.md`(`python tools/manager/catalog.py --tools-index`), `tools/dev/move_bundle.py`(옮길 목록에 `tools/manager/local-*.json` 셋).

**지킬 계약**:
- 서버는 127.0.0.1만, 지금의 Host·Origin 검사를 새 경로에도 그대로.
- `/media/<id>/<key>`는 `characters.py`가 그 줄에 대해 내놓은 목록의 key만 푼다(경로를 URL에서 받지 않는다). 저장소 밖(D 드라이브) 파일도 이 목록에 있을 때만. 확장자는 `.glb .png .jpg .webp .mp4 .json`만.
- 화면과 서버는 `chapter1/` 아래 어떤 파일도 쓰지 않는다. `asset_slots.json`은 `motion_apply.py --write`만 쓰며, 이 묶음에서는 임시 사본에만 써서 시험한다.
- `motion_apply.py`: 기본은 바꿀 줄의 앞뒤를 보여 주기만. `--write`는 그 칸의 값 글자만 바꾸고(JSON을 읽어 통째로 다시 쓰기 금지, 3.5절 4), 줄바꿈 바이트를 그대로 둔다(`.gitattributes`가 `* -text`). `--slots <경로>`로 다른 파일을 줄 수 있게(시험용). `--check`는 자리표에서 읽은 `v×L/stride`가 고름의 rate와 1e-3 안인지 보고 종료 코드 0/1.
- `motion_math.py`의 식과 기호는 2.3절 그대로. 같은 식을 다른 파일에 다시 쓰지 않는다(JS의 즉석 계산은 예외, 시험이 맞춤).
- 이동 속도 `BASE_SPEED`, 카메라 `CAMERA_OFFSET`·`19.5`는 코드에서 글로 읽는다. 못 읽으면 화면에 "읽지 못함"을 띄우고 기본값을 지어내지 않는다.
- 고름 저장은 4절 꼴. revision 409 규칙. `by`는 서버가 `"user"`로 채운다. 명령줄에는 `list`·`close`만.
- 3D 묶음은 인터넷 없이 떠야 한다: `character.js`와 넣은 three 파일에 바깥 주소로의 요청이 없어야 한다.
- `catalog.py`의 주인공 폴더 빼기(772줄)는 그대로 둔다. 주인공 몸은 `characters.py`의 경로로만 준다.
- `ui_shot.py`: Edge(`C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe`) 헤드리스로 주소(해시 포함)를 열어 PNG를 `_local/` 아래에 쓰고, `--dump-dom`이면 화면이 `data-ready="1"`과 수치를 `data-*` 속성으로 내놓은 것을 읽어 JSON으로 찍는다. 출력 경로는 `_local/` 아래만 허용. WebGL이 헤드리스에서 안 뜨면 `--use-angle=swiftshader` 같은 깃발을 시도하고, 끝내 안 되면 그렇다고 보고한다(지어내지 않는다).

**끝났다는 기준(직접 돌려 결과를 보고서에 붙임)**:
1. `python -m unittest discover -s tools/manager -p "test_*.py"` 통과. `python tools/art/test_motion_math.py` 통과.
2. `test_motion_math.py`가 냉기 지금 계약에서 `rate_from_contract(5.8, 0.5333333, 5.104)`를 0.606±0.001로, walk·1.3배의 보폭을 4.313±0.002로 낸다. JS 식과 같은지 보는 시험(같은 입력 표를 JSON으로 두고 JS 쪽 식을 Node 없이 확인할 수 없으면, JS 식을 서버가 내려 주는 표와 견주는 화면 자체 검사를 `data-selfcheck`로 내고 `ui_shot.py --dump-dom`에서 읽는다).
3. `motion_apply.py --pick <시험 기록> --slots <임시 사본> --write` 뒤 원본과 사본의 바이트 차가 그 칸의 세 값 줄과 `source` 한 줄뿐(시험이 `difflib`로 확인).
4. 서버를 `--port 8791`로 띄우고 `python tools/manager/ui_shot.py --port 8791 --hash "#character/frost?a=run&b=walk@1.3&v=5.8&cam=19.5" --size 1440x900 --out _local/shots/t9/char-1440.png --dump-dom` → PNG가 생기고, 덤프에 A칸 rate 0.606, B칸 계산 미끄러짐 약 35%(지면 속도 출처와 함께), 측정 미끄러짐 숫자. 1024x900, 800x600에서도 가로 넘침 없음.
5. 같은 실행을 바깥 연결을 막고(`--host-resolver-rules="MAP * ~NOTFOUND , EXCLUDE 127.0.0.1"`) 다시 해도 같은 결과.
6. 화면에서 저장한 고름이 `python tools/manager/picks.py list --open`에 보인다.
7. `python tools/dev/run_all.py --only manager,tools-selftest,asset-ledger` 통과, 그다음 `python tools/dev/run_all.py --quick` 통과.
8. `git diff --stat -- chapter1` 비어 있음.

**건드리지 말 것**: `chapter1/` 전부, `tools/manager/catalog.py`(도구 색인을 다시 만드는 명령만 돌림), `drafts.py`·`balance_lab.py`의 동작, 사용자 저장.

**보고**: 고친 파일, 돌린 명령과 결과, 캡처 경로(직접 봄 / 캡처만 있음 / 보지 않음), three.js 판·크기·sha256, 헤드리스 WebGL이 떴는지, 못 한 것.

### B1-b — qa-perf: 게임 안 걸음 측정

**목표**: 게임 장면에서 주인공 새 몸이 걸을 때의 동작 배율과 발 미끄러짐을 숫자로 내고, 캐릭터 화면의 계산과 견주는 도구.

**먼저 읽을 것**: 이 문서 2.1~2.3, 3.3, 3.6절. `chapter1/tests/rig_game_probe.gd`, `model_swap.gd`, `hud_dump.gd` 머리, `chapter1/view/actors/chapter_actors.gd:460~600, 711~780`(읽기만), `tools/art/gen3d_mixamo_blender.py:129~170`(지면 속도의 정의).

**만들 파일**: 새 `chapter1/tests/hero_motion_probe.gd`(+ `.gd.uid`), 새 `tools/art/motion_verify.py`, 새 `tools/art/test_motion_verify.py`(가짜 측정 출력으로 비교 규칙 시험). `tools/manager/tools_index.json`에 두 도구 줄(B1-a와 같은 파일이므로 **B1-a 병합 뒤**에 더하거나, 보고서에 줄 내용만 적어 tech-lead가 넣는다 — 기본은 후자).

**지킬 계약**:
- 실행은 `tools/dev/godot.py`로, `--chapter1-profile-off --chapter1-hero-models --chapter1-primary=chapter1.skill.frost`. 쓰는 곳은 `_local/` 아래뿐.
- `--pose-override=<json>`(`{"clip":"walk","run_time_scale":0.96667,"stride_world_m":4.313}`): 이 프로세스 안에서만, 주인공 몸이 냉기 자리로 바뀐 뒤(`_hero_slot_id == "actor.hero.frost.model"`) 한 번 표현 객체의 `_clip_run`, `_run_time_scale`, `_hero_stride`를 덮는다. 제품 파일과 코어 상태는 바꾸지 않는다.
- 측정: 렌더 프레임마다 주인공 위치, 걷는 중인지, 클립 시각, 두 발끝 뼈의 세계 위치. 연속 이동 구간(1초 이상)만 쓴다. 출력 한 줄 `HERO_MOTION_PROBE {json}`: 평균 이동 속도, 동작 배율 실측(클립 시각 증가 ÷ 실제 초), 디딤 미끄러짐 RMS(m/s), 디딤 표본 수, 구간 수. `--shots=<폴더>`면 걷는 중 연속 24프레임을 함께 저장.
- 헤드리스에서 뼈 자세를 읽을 수 있는지 먼저 확인한다. 안 되면 창 실행으로 하고 그렇다고 적는다.
- `motion_verify.py --pick <id> | --clip walk --rate 1.3 | --current`: 프로브를 부르고 `motion_math.py`의 예측(배율)과 캐릭터 화면이 내놓은 측정 미끄러짐(고름 기록의 `slip_measured_mps`, 없으면 계산값)과 견주어 표 한 장과 종료 코드.

**끝났다는 기준**:
1. `--current`(지금 계약, 달리기)에서 배율 실측이 0.606의 2% 안. 미끄러짐 RMS 숫자와, 같은 조건의 화면 측정 값의 차를 그대로 보고한다(허용치는 이 숫자를 보고 tech-lead가 정한다).
2. `--clip walk --rate 1.3`과 `--clip walk --rate 1.99`의 두 결과(배율, 미끄러짐). 1.99에서 미끄러짐이 1.3보다 뚜렷이 작아야 측정이 뜻이 있다.
3. 꺼진 값 회귀: `python tools/dev/run_all.py --quick` 통과, `git diff --stat -- chapter1/core chapter1/view chapter1/app chapter1/data chapter1/art` 비어 있음.
4. `python tools/art/test_motion_verify.py` 통과.

**건드리지 말 것**: `chapter1/view/**`, `chapter1/core/**`, `chapter1/app/**`, `asset_slots.json`, `rig_game_probe.gd`·`model_swap.gd`의 기존 동작(불러 쓰는 것은 됨).

### B1-c — character-artist: 동작 후보 묶음

**목표**: 받아 둔 Mixamo 동작 가운데 걷기·빠른 걸음·가벼운 달리기 후보를 한 glb에 묶어 캐릭터 화면에서 고를 수 있게 한다. 게임 파일은 바꾸지 않는다.

**할 일**:
- `D:/Project/witch-moira-work/downloads/mixamo/frost_rigged/`에서 후보 4~8개를 고른다. 최소: `Walking.fbx`, `Standing Walk Forward.fbx`, `Fast Run.fbx`, `Standing Run Forward.fbx`. 고른 까닭을 한 줄씩.
- 새 설정 `tools/art/gen3d_mixamo_configs/frost.motions.json`: `body`·`texture_*`는 `frost.json`과 같게, `clips`는 후보마다 `name`(영문 소문자, 예 `walk_a`, `walk_std`, `run_fast`, `run_std`), `in_place: true`, `out`은 **저장소 밖** `D:/Project/witch-moira-work/pipeline/frost/motions/motions.glb`, `hero_json` 칸 없음.
- `python tools/art/gen3d_mixamo_pack.py tools/art/gen3d_mixamo_configs/frost.motions.json` → glb와 `motions.pack-report.json`.
- `python tools/art/gen3d_views.py`로 후보마다 옆모습 한 순간씩 한 판(확인용, `_local/pipeline/frost/motions/`).

**끝났다는 기준**: 보고서에 후보별 길이·지면 속도(엉덩이·발끝)·`in_place` 처리 뒤 엉덩이 이동 폭 표, 그리고 2.3절의 식으로 계산한 "이동 속도 5.8에서 미끄럼 없는 배율" 열(모델의 답). `git status`에 새 설정 파일 하나 말고 저장소 변화 없음.

**건드리지 말 것**: `gen3d_mixamo_pack.py`·`gen3d_mixamo_blender.py`(고치지 않고 부름), `chapter1/` 전부, `frost.json`.

### B1-d — character-artist: 고른 값 적용 (사용자가 고른 뒤)

**목표**: 고름 기록 하나를 게임 자리표에 적용하고, 게임에서 같은 결과인지 확인한다.

**할 일과 기준**:
1. `python tools/manager/picks.py list --open --subject frost/` 에서 디렉터가 지정한 기록 id를 확인.
2. 후보 묶음의 클립이 골라졌으면, 그 FBX를 `frost.json`의 `clips`에 `walk` 이름으로 넣거나(지금 `walk`를 바꾸는 것) 새 이름으로 더하고 `gen3d_mixamo_pack.py`를 다시 돌린다. 몸의 클립이면 이 걸음은 건너뜀. → `python tools/dev/run_dev.py --import-only`.
3. `python tools/art/motion_apply.py --pick <id>`(보기) → `--write` → `--check` 종료 0.
4. `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_asset_slots.gd -- --strict` 통과.
5. `python tools/art/motion_verify.py --pick <id>` 종료 0.
6. `python tools/art/gen3d_ingame.py … --force-clip <고른 클립> …`과 `gen3d_sheet.py`로 게임 안 판 한 장(cam 19.5와 14).
7. 꺼진 값 불변: `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd` 불일치 0, `python tools/dev/run_all.py --quick` 통과.
8. 사용자가 띄울 한 줄을 보고서 끝에: `python tools/dev/run_dev.py --resolution 1920x1080 -- --chapter1-start --chapter1-primary=chapter1.skill.frost --chapter1-hero-models --chapter1-profile-off`
9. `python tools/manager/picks.py close <id> --ref "<보고서 경로>"`는 tech-lead 검수 통과 뒤 디렉터가 한다.

**건드리지 말 것**: 자리표의 냉기 칸 밖, `chapter_actors.gd`, 코어, 이동 속도.

**새 몸에서의 B1-d (개정 1)**: 냉기 몸이 Tripo 몸으로 바뀌면 걸음 값은 **다시 잰다**. 같은 Mixamo `Walking`이라도 새 뼈대에서 발끝 지면 속도가 앞선 몸보다 6.6% 낮게 측정됐다(1.96 대 2.10 m/s, 엉덩이 기준, `_local/t9-mixamo/REPORT-walk.txt`). 지면 속도 g가 내려가면 미끄럼 없는 배율 `r0 = v/(g·s)`가 같은 비로 올라가고(5.8 m/s에서 걷기 약 1.99 → 약 2.13배, 모델의 답), 고른 배율이 같아도 미끄러짐 `v − r·g·s`가 달라진다. 그래서: (1) 새 몸의 ⑥이 끝나 `pack/model.pack-report.json`이 생기면 캐릭터 화면이 그 보고서로 값을 다시 낸다 (2) 사용자가 앞선 몸에서 고른 기록이 있으면 그 기록의 "클립 + 배율"을 새 몸에 그대로 얹었을 때의 미끄러짐을 화면이 보이고, 사용자가 다시 고르거나 그대로 둔다(새 기록) (3) `motion_verify.py --report <새 보고서>`로 게임 안 측정을 하되, 화면 값이 새 몸에서 잰 것인지 확인한다(옛 몸의 화면 값과 견주지 않음) (4) 적용은 ⑩(`pipeline.py run frost apply --yes`)으로 몸 파일과 걸음 값을 한 번에 넣는다. 앞선 몸에 B1-d를 먼저 적용했다면 그 값은 ⑩에서 새 값으로 덮인다.

### B2-a — manager-tools: 파이프라인 도구

**목표**(개정 1): 6절 그대로. 사람 단계(Tripo 웹, Mixamo 웹, 걸음 고르기, 적용 확정)는 주문을 찍고 받은 파일·기록을 기다린다. 캐릭터 화면의 단계 칸을 상태 파일로 채우고, 이미 있는 「3D 만들기(수동)」 칸과 같은 폴더(`tripo_in`·`tripo_out`)를 읽는다(같은 파일을 두 곳에서 따로 찾지 않게 `characters.py`가 상태 파일의 경로를 쓰도록 바꾼다).

**만들거나 고칠 파일**: 새 `tools/art/pipeline.py`, 새 `tools/art/pipeline_lines/`(이 묶음에서는 꼴을 보이는 `_example.json` 하나 + 스키마 설명을 `pipeline.py` 머리에), 새 `tools/art/test_pipeline.py`(Blender·인터넷 없이: 임시 작업 뿌리, 가짜 도구 명령으로 낡음 전파·사람 단계 멈춤과 받은 파일 감지·`waiting_pick`·비용 깃발·adopt·잠금·원자적 쓰기·`godot: true` 단계가 잠금 중 돌지 않음), 고침 `tools/manager/characters.py`·`character.js`(단계 칸, 그림·영상, 「3D 만들기(수동)」이 상태 파일의 경로를 씀), `tools/manager/tools_index.json`, `docs/TOOLS-INDEX.ko.md` 다시 만들기, `tools/manager/사용안내.ko.md`.

**계약**: 6.1~6.5절. 낱개 도구를 고치지 않는다(`rig_check.py`의 고침은 B2-b). `--execute --yes` 없이는 Codex·Dreamina를 부르지 않는다. **Tripo·Mixamo를 부르는 코드는 없다**(웹 주문만). 상태 파일은 작업 뿌리에만 쓴다. 저장소 안에 쓰는 것은 ⑩ `apply`(사람 확정 `--yes` 뒤)와 `_local/` 뿐. 받은 파일은 옮기지 않고 받는 폴더에 둔 채 해시만 적는다.

**끝났다는 기준**: `python tools/art/test_pipeline.py` 통과. B2-b의 `adopt frost` 뒤 `python tools/art/pipeline.py status frost`가 ③(Tripo 몸 채택)·④·⑤-a를 `done`, ⑤-b를 받은 파일 수대로(`mixamo_out/`에 몸·동작 10개가 다 있으면 `done`, 아니면 `waiting_human`과 빠진 이름), ⑥ 뒤를 그 결과대로 보인다. `pipeline.py order frost rig`가 냉기 안내서 C절과 같은 내용(몸 1 + 동작 9, 설정, 받는 곳)을 찍는다. 앞 단계 파일 하나의 해시를 바꾼 임시 사본에서 뒤가 모두 `stale`. 캐릭터 화면 캡처(`ui_shot.py`)에 단계 칸. `run_all.py --quick` 통과.

### B2-b — character-artist: 일회용 스크립트를 도구로, 세 마녀의 줄

**할 일**:
(개정 1: A자세 생성·마무리 도구 올리기는 뒤로 미룸 — 2.5 ②. 다시 필요해지면 옛 판의 1·2 항목을 그대로 쓴다.)
1. `D:/…/gen3d/to_fbx.py` → `tools/art/gen3d_to_fbx.py --in <glb> --out <fbx>`(Blender 명령줄, 뼈 지우고 메시만, 질감 넣기). 냉기 `mixamo_in/frost_t15k.fbx`를 다시 만들어 크기·삼각형 수·키가 같은지(바이트가 다르면 그 까닭).
2. `rig_check.py`: `--slot`을 주면 뼈 목록을 그 자리표 계약에서 읽는다(지금은 옛 24개 이름이 기본). `--slot` 없는 동작은 그대로.
3. 동작 표 `hero_default`(6.2절): 냉기 안내서 C-2의 아홉 줄과 공통 설정을 `pipeline.py`가 읽을 데이터 파일(`tools/art/pipeline_motions/hero_default.json`)로. 프레임 자르기(dodge 3~32, dodge_back 6~52)는 `frost.json`에서 옮긴다.
4. 각 도구의 Blender 없이 도는 부분 시험을 `tools/art/test_gen3d_tools.py`에 더하거나 새 시험 파일.
5. (B2-a 병합 뒤) `tools/art/pipeline_lines/frost.json`, `storm.json`, `ember.json`(공급처 `tripo_web`·`mixamo_web`). `python tools/art/pipeline.py adopt frost`(Tripo 줄, 앞선 몸은 `--as replaced`), `adopt storm`·`adopt ember`는 있는 단계까지.
6. `docs/ART-3D-PIPELINE.ko.md` 머리에 "주인공은 Tripo 웹 + Mixamo 웹 + `pipeline.py`" 한 단락과 옛 길이 어디에 아직 쓰이는지.
7. 옮긴 뒤 `D:/…/gen3d/*.py`와 `_local/art/gen3d/*apose*.py`는 지우지 않고 그대로 둔다(지우는 것은 디렉터 결정).

**끝났다는 기준**: 새 도구의 `--help`가 돌고, 1의 재생성 비교, `rig_check.py <냉기 걷기 미리보기 glb> --slot actor.hero.frost.model`에서 뼈 줄이 통과(클립 줄은 걷기만이라 어긋남 그대로), `pipeline.py status --all` 표, `run_all.py --only tools-selftest` 통과.

### B3·B4·B5

각 묶음 앞에 tech-lead가 5절을 바탕으로 따로 지시서를 쓴다. 효과 영상 도구(`fx_clips.py`)와 무작위 표본 도구(`loot_samples.gd`)는 qa-perf, 화면은 manager-tools. 화면 파일이 겹치지 않게 `skills.js/skills.py`, `gear.js/gear.py`처럼 화면마다 파일을 나누고, `server.py`·`index.html`은 한 묶음씩 차례로 잡는다.

---

## 8. 순서와 병렬

```
B1-a (manager-tools) ─┐
B1-b (qa-perf) ───────┼─ tech-lead 검수 ─ 디렉터가 사용자에게 화면 주소를 줌 ─ 사용자 고름 ─ B1-d (character-artist) ─ 검수 ─ 사용자 플레이
B1-c (character-artist)┘
                            └─ B2-a (manager-tools) ─┐
B2-b 앞 절반 (character-artist, B1-c 뒤) ────────────┴─ B2-b 뒤 절반(줄·adopt) ─ 검수
                                                       └─ B3 / B4 (qa-perf 도구 + manager-tools 화면, 화면은 차례로)
                                                                               └─ B5
```

- 동시에 셋: B1-a, B1-b, B1-c. 파일이 겹치지 않는다(B1-b는 도구 색인 줄을 보고서로만 넘김).
- `server.py`, `index.html`, `character.js`, `characters.py`는 manager-tools 한 담당이 차례로 잡는다(B1-a → B2-a → B3 화면 → B4 화면).
- `asset_slots.json`은 B1-d만 쓴다. 그동안 T7-3(자리표의 나머지)이나 다른 묶음이 이 파일을 잡지 않게 디렉터가 막는다.
- `chapter_actors.gd`는 이 지시서의 어느 묶음도 고치지 않는다.
- 냉기 새 얼굴 몸(U-70 → U-89~U-91의 Tripo 몸)이 들어오면: 지면 속도가 다르므로(걷기 −6.6%) 걸음 값은 다시 잰다 — B1-d의 "새 몸에서의 B1-d" 문단(개정 1). 파이프라인은 그때 ⑨ 뒤를 `stale`로 보인다.

---

## 9. 검수 때 tech-lead가 돌릴 것

본 저장소에서, 병합 뒤:

```powershell
python -m unittest discover -s tools/manager -p "test_*.py"
python tools/art/test_motion_math.py
python tools/art/test_motion_verify.py
python tools/manager/server.py --port 8791     # 따로 띄움
python tools/manager/ui_shot.py --port 8791 --hash "#character/frost?a=run&b=walk@1.3&v=5.8&cam=19.5" --size 1440x900 --out _local/shots/t9-review/char-1440.png --dump-dom
python tools/art/motion_verify.py --current
python tools/art/motion_verify.py --clip walk --rate 1.3
python tools/dev/run_all.py --quick
git diff --stat -- chapter1
```

캡처는 직접 열어 본다(화면의 바닥 흐름, 두 칸, 수치 띠, 카메라 19.5/14 전환). three 파일의 sha256를 README와 견준다. 화면에서 고름 하나를 저장하고 `picks.py list --open`으로 확인한 뒤, 그 기록을 임시 사본 자리표에 `motion_apply.py --slots <사본> --write`로 적용해 바이트 차를 본다.
B1-d 검수는 위에 더해 `golden_core.gd` 불일치 0, `test_asset_slots.gd --strict`, 게임 안 판을 직접 봄.

**계약 칸 이름(뒤로 미룸)**: `pose.run_time_scale`은 실제로 "걸음 한 주기의 길이"다. 이름이 뜻과 달라 다음 사람이 배율로 읽고 틀릴 수 있다. 바꾸려면 `chapter_actors.gd`, `asset_slots.json`, `test_asset_slots.gd`를 같이 고쳐야 해서(그리고 `chapter_actors.gd`는 여럿이 기다리는 파일) 지금은 하지 않는다. 바꿀 때 refactor-architect에 배정한다. 그 전까지 `motion_math.py`와 `사용안내.ko.md`에 뜻을 적는다.

---

## 10. 위험과 확인하지 못한 것

| # | 무엇 | 어떻게 다룸 |
|---|---|---|
| R1 | "조금 빠른 걸음"을 지금 속도에 붙이면 계산으로 발이 약 35% 미끄러진다(2.3절, 모델의 답). 사용자가 막대를 움직여 미끄럼을 없애면 이동 속도를 낮추는 쪽이 되고, 이는 코어·전투 균형이다 | 화면이 숫자와 함께 보이고, 속도는 제안으로만 남아 design-lead로 간다 |
| R2 | 지면 속도 추정 ±6%, 화면의 측정과 게임의 측정이 정의는 같아도 프레임 샘플이 달라 차가 난다 | B1-b가 지금 계약에서 차를 먼저 보고, 허용치는 그 뒤에 고정 |
| R3 | 브라우저의 빛·머티리얼은 Godot와 같지 않다 | 화면에 "근사" 표시. 색·밝기 판단은 ⑦의 게임 캡처로 |
| R4 | 헤드리스 Edge에서 WebGL이 뜨는지 [미확인] | 안 뜨면 캡처 검수는 창 있는 Edge로, 수치 검수는 서버의 계산 값으로. B1-a가 결과를 보고 |
| R5 | Godot 직교 `size`가 세로 폭인지 [짐작] | B1-a가 Godot 문서 또는 `play_with_model.gd --cam-size`의 캡처와 화면 캡처의 주인공 화소 높이를 견주어 확인 |
| R6 | 발끝 뼈 이름(glb 안) [짐작] | B1-a가 glb 머리에서 확인, 못 찾으면 이름 목록을 화면에 띄움 |
| R7 | 헤드리스에서 뼈 자세를 읽을 수 있는지 [짐작] | B1-b가 먼저 확인 |
| R8 | 자리표를 JSON 다시 쓰기로 고치면 다른 줄이 바뀐다 [봄] | `motion_apply.py`는 글자만 고침, 시험이 바이트 차를 봄 |
| R9 | 고름 파일이 git 밖 | `tools/manager/`에 두고 `move_bundle.py`에 더함. 지금 `local-state.json`·`local-drafts.json`도 옮길 목록에 없던 구멍을 같이 막음 |
| R10 | `BASE_SPEED`가 데이터가 아니라 코드 상수(CLAUDE.md의 "수치는 데이터 파일에서"와 어긋남) [봄] | 속도를 바꾸는 결정이 나면 gameplay-systems가 데이터로 옮기며 골든 갱신 |
| R11 | (개정 1) 받아 둔 동작은 새 몸에 맞지 않는다 — 뼈 위치 키가 앞선 몸의 뼈 길이를 담음 [봄: 냉기 Tripo 보고 3절] | 몸마다 다시 받는다(6.4). `inspect`가 같은 캐릭터에서 받은 파일인지 뼈 수·이름으로 본다 |
| R12 | (개정 1) Tripo·Mixamo는 사람 손(웹, 로그인, 구독). API는 쓰지 않는다(U-89) | pipeline이 주문을 찍고 받는 폴더를 기다림 |
| R18 | (개정 1) Tripo 결과가 재시도마다 다르다(얼굴이 찌그러진 첫 결과, U-90) | `pick_one` + `waiting_pick`. 채택은 사람 |
| R19 | (개정 1) 손이 나팔 치마를 파고든다(냉기 걷기 미리보기) | 표지점으로 고쳐지지 않음. 게임 크기에서 보이는 정도는 ⑧에서 봄, 원화 단계에서 다음 마녀의 치마 폭을 봄(6.6 #9) |
| R20 | (개정 1) 묶기 설정이 D 드라이브 절대 경로를 가짐(`pipeline/frost/frost.t15k.pack.json`) | 설정을 줄 정의에서 만들어 작업 뿌리에 씀(6.2 `config: generated`). 저장소에 새 절대 경로를 넣지 않음 |
| R13 | Codex·Dreamina는 비용 | `--execute --yes` 두 깃발 + 디렉터가 값을 보이고 승인 |
| R14 | 큰 파일 해시가 느림 | 크기·mtime 해시 저장소 |
| R15 | mp4 범위 요청 없이 브라우저가 영상을 트는지 [미확인] | 범위 요청 하나를 구현 |
| R16 | `docs/ART-3D-PIPELINE.ko.md`가 옛 길만 적음 [봄] | B2-b에서 머리 단락 |
| R17 | 생성 몸·동작의 이용 약관 미확인(몸 폴더가 git 밖, 원장 빼기) | 이 지시서는 바꾸지 않음. `pipeline.py ledger`가 명령만 준비 |

이 지시서를 쓰며 **실행하지 않은 것**: 관리 툴 서버, three.js 내려받기, 헤드리스 Edge의 WebGL, 게임 안 걸음 측정, 후보 FBX 묶기, glb 안 발끝 뼈 이름. 실행한 것은 파일 읽기와 두 가지 확인뿐이다: `model.glb` 머리의 클립 이름 9개, `asset_slots.json`을 `json.dumps(indent=2)`로 다시 쓰면 바이트가 달라지는 것.

---

## 11. 디렉터가 정할 것

1. **three.js를 관리 툴에 넣는가**(MIT, 구현 때 한 번 내려받음). 권고: 넣는다. 넣지 않으면 바닥 흐름·발 미끄러짐 수치·게임 카메라가 빠지고 model-viewer로 클립 돌려 보기만 된다.
2. **화면이 게임 파일을 직접 쓰지 않는 길**(고름 → 에이전트가 `motion_apply.py`로 적용). 권고: 이대로. 사용자가 "저장하면 바로 게임에"를 원하면 B1-d를 화면 단추로 바꿀 수 있으나, 그 경우 관리 툴이 처음으로 게임 파일을 쓰게 된다.
3. **파이프라인 상태를 D 드라이브 작업 뿌리에 두는가**. 권고: 둔다(원본과 함께 옮겨짐). 줄 정의만 저장소에.
4. **B1-c(후보 묶음)를 첫 묶음에 넣는가**. 권고: 넣는다. 작은 일이고, 사용자가 `Walking` 하나만이 아니라 두세 걸음을 견줄 수 있다.
5. **사용자가 이동 속도를 낮추는 쪽을 고르면**: design-lead 판단 → `BASE_SPEED`를 데이터로 옮기고 골든 갱신(gameplay-systems). 이 지시서는 거기까지 가지 않는다.
6. **고른 걸음을 옛 얼굴 몸에 먼저 적용하는가, 새 얼굴 몸(U-70)을 기다리는가**. 권고: 먼저 적용(사용자가 플레이로 판정할 수 있게). 새 몸이 오면 같은 고름에서 다시 계산한다.
7. **Dreamina CLI를 감싸는 도구의 담당**(⑧, U-74의 한 달 제작과 겹침). 이 지시서는 작업 주문 출력까지만.
8. **B3·B4의 차례**. 사용자 원문의 차례(스킬 → 장비 → 화폐)를 따를지.
9. 옮긴 뒤 일회용 스크립트(`_local/art/gen3d/*apose*.py`, `D:/…/gen3d/*.py`)를 지울지.
