# 기술 사후 검수 — 2026-11-23 밤에 병합된 코어 변경과 얹기 직전의 패치 셋

검수: tech-lead. 읽기 전용(코드 읽기, `git show`/`git diff`, 임시 폴더에서 `git apply --check`, 데이터 파일을 파이썬으로 읽음). **Godot는 띄우지 않았다**(본 저장소에서 디렉터의 전체 회귀가 도는 중). 그래서 이 문서의 "불변"은 모두 코드 읽기의 결론이거나 담당 보고의 인용이며, 이번에 실행해 본 것이 아니다.

범위:
- main `60287c4..6f042f3`(+ 그 뒤 `d263c72`는 글자만이라 제외) 가운데 코어·앱을 건드린 것: `2e91340` R0-B(앱), `7f317f7` D23 T1-A(`loot.gd`, `chapter_core.gd` 한 줄), `0794027`·`6f042f3` D24 12.1·12.1-b(강림, `chapter_core.gd`·`descent.gd`·`descent.json`), 표현 쪽 `6137c90`(강림 효과)·`243dc23`(HUD)은 "표현이 코어를 바꾸는가"만.
- 얹기 직전의 패치: `_local/d23-t1b/t1b.patch`(D23 T1-B), `_local/d22-r1b/r1b.patch`(D22 R1-B), 디렉터가 더한 `_local/d23-data1/data1.patch`(D23 데이터 손질). 이 셋은 지금 본 저장소 작업 트리에 이미 얹혀 있다(`git status`에서 확인, 커밋 전).

## 0. 판정

**막을 결함: 없음.**
병합 때 지킬 것(결함은 아님): 골든 여섯째 건(`11:chapter1.skill.frost:affix-on`)의 해시는 **세 패치를 모두 얹은 트리에서** 다시 만든 값이어야 한다. T1-B 패치 안의 값은 데이터 손질 전의 것이다(T1-B 보고 4절 마지막 줄도 같은 말). 지금 작업 트리의 골든 파일은 여섯째 건만 바뀌고 다섯 건은 그대로다(파일 비교로 확인, 실행은 안 함) — 이 값이 어느 트리에서 나왔는지 디렉터가 확인한다.

| 갈래 | 수 |
|---|---|
| 막을 것 | 0 |
| 병합 뒤 고칠 것 | 5 (B1~B5) |
| 참고 | 8 (C1~C8) |

---

## 1. 디렉터가 더한 물음 — 데이터 손질에도 여섯째 골든이 그대로인 까닭

**결론: 여섯째 건은 실제로 켠 경로로 굴린다. 해시가 안 바뀐 것은 그 한 판의 굴림이 바뀐 행을 우연히 비켜 간 것으로 본다. 골든이 켠 경로를 지키지 못하는 결함은 아니고, 이 데이터 갈래들에 대한 골든의 감도가 낮은 것이다(B1).**

근거 [봄]:
1. 켠 경로가 실제로 돈다.
   - `golden_core.gd:74~76` → `trial_docs.gd:55~60` `enable_affix_rolls_problem`: `LootTables.new()`, `load_file()`(기본 경로 = `res://chapter1/data/loot.json`, 그 트리의 데이터), `set_affix_rolls(true)`, `run.loot = tables`.
   - 코어는 `loot`를 `_init`에서만 정하고(`chapter_core.gd:30~36`, 정적 `_shared_loot`) `start()`가 다시 넣지 않는다 → 끼운 표가 판 내내 쓰인다.
   - 여섯째 건의 결과(틱 18241, 처치 4666)가 같은 시드의 꺼진 냉기 건(17723, 4483)과 다르다 → 켠 가지가 굴림을 바꾼다.
   - T1-B가 `STATS_READ`를 19 → 27로 늘리자 여섯째 건만 600틱에서 어긋났다(T1-B 보고 4절) → 켠 가지가 해시에 잡힌다.
2. 해시가 장비의 줄을 본다: `combat_core.gd` `snapshot()`이 `items`(바닥)·`inventory`·`equipped`를 통째로 담고, `chapter.pending_rewards`도 담는다(`chapter_core.gd`의 snapshot). 수호자·우두머리 전리품은 가방으로 바로 간다(`chapter_core.gd:1091`).
3. `roll_class`가 `lines_profile`을 넘긴다(`loot.gd:541, 546, 553`), `_roll_lines_v2`가 `quality=="rare"`이고 표에 `rare_boss`가 있을 때 그 표를 쓴다. content-balance의 `sim_loot --affix-rolls=on`(같은 `roll_class`)에서 우두머리 출처 희귀 줄 수가 3.255 → 3.389로 움직였다(그 보고의 값, 10,000판) → 데이터의 `lines_profile`은 굴림에 닿는다.
4. 그런데 그 한 판에서 데이터 손질이 닿는 자리는 좁다:
   - `lines_profile`: 희귀일 때의 **줄 수 한 번 뽑기**에만 닿는다. 뽑는 횟수는 표와 상관없이 한 번(`_weighted`)이라 결과가 같으면 뒤의 난수가 그대로다. `rare`(3:6000, 4:3600, 5:400)와 `rare_boss`(3:4000, 4:5000, 5:1000)의 결과가 다른 뽑기 값은 4001~6000과 9001~9600, 곧 26%다(모델의 답). 한 판에서 이 표를 쓰는 희귀는 수호자 둘 + 우두머리의 보장 희귀 셋과, 수호자·우두머리 나머지 뽑기에서 희귀가 나온 경우뿐(희귀 몫 약 8%). 셋 모두 비켜 갈 확률 0.74³ ≈ 0.41(모델의 답).
   - Ⅳ·Ⅴ단 값 범위: 아이템 레벨 13 이상에서만 열린다. 수호자는 구역 0·1(레벨 7·11), 우두머리만 15 → 우두머리 다섯 줄 안팎에서 `wrath`·`flame`·`haste` 사다리의 Ⅳ·Ⅴ가 뽑혀야 값이 달라진다.
   - `vs_status` 가중: 데이터 손질만 얹은 트리(T1-B 없음)에서는 이 행들이 `core_reads:false`라 후보에서 빠진다(`loot.gd` `_roll_lines_v2`의 `STATS_READ` 거름) → **아무 효과 없음**이 정상이다.
   - 의식 상자 등급의 `lines_profile`: 의식 보상은 등급표를 거치지 않고 `roll_item(...,"rare_boss")`로 이미 굴린다(`chapter_core.gd:1441`), 지키는 상자류는 `extras`가 꺼져 판에 없다.
   - 그래서 그 판에서 해시가 그대로일 확률은 대략 0.4 × (우두머리에서 Ⅳ·Ⅴ 미등장) — 드물지만 있을 수 있는 크기다(모델의 답).
5. 바로 확인하는 길(회귀가 끝난 뒤, 데이터 손질 작업 트리와 그 직전 커밋에서 각각): `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd -- --case=11:chapter1.skill.frost:affix-on --dump-at=18241 --dump-out=_local/review/affix_on_<트리>.json` 두 번 → 두 덤프의 `inventory`·`chapter.pending_rewards`에서 수호자·우두머리 장비의 줄 수와 `wrath4/5·flame4/5·haste4/5` 줄을 비교. 위 설명이 맞다면 두 덤프가 같고 그 줄들이 없다(또는 희귀의 줄 수 뽑기가 같은 칸에 떨어졌다).
6. T1-B와 견줌: T1-B는 후보 집합 자체(읽는 키 8개, 풀 40행)를 넓혀 **모든** 장비 줄의 사다리 뽑기 합계를 바꾸므로 첫 장비부터(600틱) 어긋난다. 데이터 손질은 위 좁은 자리만 바꾼다. 둘의 차이는 감도의 차이로 설명된다.

---

## 2. 병합된 커밋

### 2.1 `2e91340` R0-B(앱)

- 바뀐 것: `--chapter1-trial=elites`를 이름 목록에 더함(`chapter_one.gd:389`), 도입부 "처음 온 사람"을 `start_run`에서 `opening_first_visit_for(profile.available, profile.total_runs(), args)`로 정함(426~430, 460).
- `profile.total_runs()`(`chapter_profile.gd:1698`)는 읽기만 한다. 저장 꼴 변화 없음.
- 코어 입장에서는 `start()` 전에 들어오는 불 하나(`first_boss_kill`과 같은 꼴). 프로필 꺼짐(골든·측정)에서는 `true` 그대로 → 골든 불변이 코드로도 맞다.
- 결함 없음. C6 참고.

### 2.2 `7f317f7` D23 T1-A(`loot.gd`)

- 꺼진 경로: `roll_item`의 갈래는 `if _affix_on: return _roll_item_v2(...)` 한 줄(`loot.gd:407`). 그 앞의 등급·전설·칸·밑바탕 뽑기는 그대로. `roll_class`는 `lines_profile`을 넘기기만 하고 난수를 더 쓰지 않는다. `chapter_core.gd:1441`의 `"rare_boss"` 인수는 꺼진 경로에서 읽히지 않는다. → 분기 한 줄이 맞다.
- `validate` 넓힘(`VALID_COUNTS`, `VALID_KIND_CAPS`, `_in_window`): 넓히기만 한다. 새로 생긴 좁힘은 `VALID_CLASS_CAPS`(마법 condition 1·skill 0 등) 하나인데, 살아 있는 `affixes` 20행의 `class`는 `number`·`shape`뿐이라(데이터로 셈) **지금 저장된 장비 가운데 새로 거절되는 것은 없다**.
- 풀 행이 `_affixes`에 들어가 꺼진 상태에서도 `validate`가 풀 id를 받는다 — 켠 판에서 저장된 장비를 끈 뒤에도 읽기 위한 것이라 맞다.
- 저장·스냅숏: 장비 꼴(`id, group, stat, value`) 그대로. 스냅숏 키 추가 없음.
- C4(쓰이지 않는 `tier_window`), C5(단 가중 합이 0일 때) 참고.

### 2.3 `0794027`·`6f042f3` D24 12.1·12.1-b(강림)

- 꺼진 경로(배포 `descent.json`은 `enabled:false` → `descent`가 빈 사전): 공유 함수에 들어간 줄은 모두 `descent.is_empty()` 또는 `_d_sweep.is_empty()`로 먼저 걸러진다 — `_emit` 덮어쓰기(1013~1015), `_spawn_wave`의 쓸어버림 중 생성(627), `_descent_spawn_interval`(2069~2073, 꺼짐이면 틱 그대로). `start()`의 `_d_seed = seed ^ 0x44455343`은 값만 정하고 난수를 쓰지 않으며 스냅숏에 없다. → 꺼진 판 불변이 코드로 맞다.
- 난수: 강림은 어떤 난수 흐름도 뽑지 않는다. 흩어짐은 판 시드의 정수 해시(`descent_hash`, `_lowbias32` 세 번, 2097~2108)다. 결정론적이고 다른 흐름의 소비를 바꾸지 않는다.
- 코어가 화면에 매이는가: 범위가 "화면 사각형"이지만 코어는 카메라·해상도를 읽지 않는다. 사각형은 데이터 값이다(`descent.json` `area {shape:"screen", right_deg:-38.2, half_w_m:17.3, half_h_m:13.4, edge_m:1.0}`). 창 크기·해상도가 바뀌어도 판은 같다. 다만 **카메라 값을 손으로 옮겨 적은 것**이라 카메라가 바뀌면 판의 범위와 화면이 어긋난다 → B3.
- 표현이 코어를 바꾸는가: `6137c90`의 `view/fx/descent*`, `243dc23`의 HUD에서 코어 필드 대입·코어 변경 함수 호출을 찾지 못했다(정규식 검색: `run.x = …`, `request_descent`, `release_descent`, `step`, `abandon`, `_emit`). 셰이더의 `seed`는 표현 자신의 값이다.
- 켠 경로의 스냅숏: 강림 상태는 `descent.json`이 켜진 판에만 들어간다(`snapshot()` 주석, 2614~). 저장에는 아무것도 남기지 않는다.

### 2.4 공통 확인

- `assert(` — 이 범위의 코어 diff와 두 패치에 새로 생긴 것 없음. 기존 `chapter_items.gd:44,48,72,79`는 부작용 없는 조건(이번 범위 밖).
- `chapter_profile.gd`는 이 범위의 어느 커밋·패치도 고치지 않았다 → 저장 꼴 변화 없음.

---

## 3. 얹기 직전의 패치(지금 작업 트리에 있음)

### 3.1 T1-B(`t1b.patch`)

- 꺼진 경로(`affix_rolls.enabled:false`)에서 새 능력치 여덟은 장비에 생길 수 없으므로 `_condition_bps`·`max_hp_bps`·`lowhp`·회피 뒤 guard는 모두 0을 보고 건너뛴다. 새 상태 `_last_move_tick`은 매 틱 적히지만 그 키를 낀 장비가 있을 때만 스냅숏(`gear_clock`)에 들어간다 → 해시 불변(보고: 다섯 건 불일치 0).
- **꺼진 경로에서도 바뀌는 것 하나**: `stat_caps.damage_reduction_bps = 7500`이 스위치와 상관없이 늘 걸린다(`_reduction_bps`, 받는 피해와 능력치 판 둘 다). 지시서 결정(나)대로라 결함은 아니다. 지금 데이터로 7500을 넘을 수 있는지 셈(모델의 답): `ward2` 1200 × 네 칸(몸·머리·신발·반지; 반지 두 칸이면 다섯) + 밑바탕(`iron_vest` 600, `ward_ring` 500 ×2 등) + 트리 900 → 8000~9000까지 이론상 닿는다. 골든 판은 닿지 않았다. → C1.
- 난수: 새 난수 뽑기 없음. 켠 경로의 해시 변화는 후보 집합이 넓어진 것(의도, 보고 4절).
- `score()` 가중 추가는 줍기 알림·자동 조작의 장착 판단에 쓰인다. 꺼진 경로의 장비에는 그 키가 없어 영향 없음.
- `combat_tuning.gd`의 `stat_caps`·`gear_conditions`는 선택 블록, 없으면 이전 동작.

### 3.2 R1-B(`r1b.patch`)

- 새 키 다섯은 모두 선택 키. 없을 때: `_rhythm_mix_kind`의 `mix.get(...)`는 `int(mix.walker)`와 같은 값, `_ranged_left = -1`이면 갈래를 타지 않음, `guardian` 없으면 `steady=10000`·`heads=true`, `count_jitter_bps` 0이면 뽑지 않음, `squad` 없으면 부르지 않음. `_wave_heading`은 늘 적히지만 `_threat_on`(squad나 jitter가 문서에 있을 때)일 때만 스냅숏에 들어간다 → rhythm-c1 골든 불변(보고와 코드가 맞음).
- 난수: 새 뽑기는 모두 `_spawn_rng`, 키가 있을 때만. 돌격의 고리 거리 접기는 뽑는 횟수를 바꾸지 않는다(같은 값을 접음).
- `_guardian_alive()`는 `_champion_id`를 본다. 우두머리 구역(2)은 리듬 생성을 타지 않으므로(`_spawn_wave` 628행 조건) 우두머리에게는 걸리지 않는다 — 보고 5절과 맞다.
- 시험판의 머리(`rhythm.trial`)는 검사기가 키 집합을 정확히 요구해(`combat_tuning.gd:536`) `count_jitter_bps`가 들어갈 수 없다 → `String(rule.id)`(trial에는 `id`가 없을 수 있음)를 타는 길이 없다.
- C7 참고.

### 3.3 데이터 손질(`data1.patch`)과 얹은 결과

- 세 패치를 `HEAD`의 해당 파일 사본에 차례로 얹어 봄(임시 폴더, `git apply --check`): T1-B ✓, 그 위 R1-B ✓, 그 위 데이터 손질은 `loot.json` 194행 근처에서 **충돌**(T1-B의 `core_reads` 40줄과 데이터 손질의 `vs_status` 가중 20줄이 같은 줄). T1-B 보고 8절이 예고한 충돌이다.
- 지금 작업 트리의 손으로 합친 결과를 읽어 봄 [돌림: 파이썬으로 `loot.json` 읽기]: `vs_frozen`·`vs_marked` 1~5는 가중 10·`core_reads:true`, `vs_heated`·`vs_shocked` 1~5는 가중 10·`false`, `wrath4/5`·`flame4/5`·`haste4/5`는 새 범위, 보물 등급 일곱에 `lines_profile:"rare_boss"`, `STATS_READ` 27개. **양쪽을 다 살린 합침이 맞다.** 한쪽을 통째로 택했다면 가중 되돌림은 어떤 검사도 잡지 못했을 것이다(`test_loot`는 `core_reads`만 견줌) → B4.
- 합친 뒤에는 `vs_frozen`·`vs_marked`가 후보가 되므로 그 가중 변경(40 → 10)이 켠 경로에 처음으로 닿는다. 여섯째 골든은 이 합친 트리에서 다시 만든 값이어야 한다(0절).

---

## 4. 결함과 할 일

### 막을 것
없음.

### 병합 뒤 고칠 것

| # | 무엇 | 자리 | 담당 |
|---|---|---|---|
| B1 | 켠 경로의 데이터 갈래(`lines_profile`, Ⅳ·Ⅴ단 값, 사다리 가중)를 골든 한 판이 우연히 비켜 갈 수 있다. 굴림 단위의 고정 시험을 `test_loot.gd`에 더한다: 켠 표에서 고정 시드로 `roll_class("boss", 12, …)`를 2,000번 → 보장 희귀의 줄 수 분포가 `rare_boss` 표를 따르는지(같은 시드에서 `lines_profile`을 지운 표와 결과가 다름), 레벨 15의 `wrath`·`haste`·`flame` 줄 값이 데이터 범위 안이고 Ⅳ·Ⅴ가 한 번 이상 나옴, `vs_status` 가중을 0으로 둔 사본과 견주어 후보 비율이 바뀜 | `chapter1/tests/test_loot.gd`; 근거 `golden_core.gd:40`, `loot.gd:525~556` | gameplay-systems |
| B2 | `test_motion_verify.py`가 git 밖 파일(주인공 몸 보고서)을 읽어 새 작업 트리에서 실패, `test_audio_tools.py`가 자식 실패를 `FileNotFoundError`로 가림 | `tools/art/motion_verify.py:27,37~41,131`, `tools/art/test_motion_verify.py:59~67`, `tools/dev/test_audio_tools.py:43,63~65,183` | qa-perf — 지시서 `docs/specs/T10-pity-save-key-and-tech-decisions-20261123.ko.md` 2.4 |
| B3 | 강림의 화면 사각형이 카메라 값을 손으로 옮겨 적은 데이터다. 카메라 크기 결정(19.5 대 14, OPEN-WORK 9절)이 바뀌면 판의 범위가 화면과 어긋난다. `descent.json`의 `area`와 `view/world/chapter_world.gd`의 `CAMERA_OFFSET`·`view/fx/combat_juice.gd`의 크기에서 계산한 사각형이 같은지 보는 검사 하나(코어는 계속 데이터만 읽음) | `chapter1/data/descent.json` `area`, `chapter_core.gd:2110~2116` | qa-perf(검사), 값은 gameplay-systems |
| B4 | `loot.json`의 손 합침은 맞았지만, 가중이 되돌아가도 잡는 검사가 없다. `sim_loot`의 켠 출력이나 `test_loot`에서 `vs_status` 행의 가중이 다른 조건 사다리보다 낮은지(데이터 손질의 뜻) 한 줄 | `chapter1/tests/test_loot.gd` | content-balance(데이터 뜻을 시험으로) — B1과 같은 파일이므로 B1 뒤에 |
| B5 | `sim_loot.gd --luck=N`이 **아무것도 재지 않으면서 잰 것처럼 끝난다**. 거절 조건이 `set_affix_rolls`의 유무뿐이라(T1-A 뒤로 늘 있음) `--luck`이 통과하고, `mods={"luck_bps":N}`를 받은 `roll_class`는 `drop_bps`·`quality_bps`만 읽어 굴림이 운 0과 같다. D23 3.16의 "운 3000에서 고유 ≤0.28"이 빈 통과가 된다. 운 가지(D23 T8)가 코어에 생기기 전에는 `--luck`>0을 종료 코드 3으로 거절(`loot.has_method("set_luck")` 같은 확인)하게 고친다 | `chapter1/tests/sim_loot.gd:78~84,95`, `loot.gd:525~538` | content-balance |

### 참고

| # | 무엇 | 자리 |
|---|---|---|
| C1 | `stat_caps`(감소 7500, 조건 피해 10000)는 꺼진 판에서도 걸린다. 지금 데이터로 감소 7500은 이론상 닿는다(3.1). 지시서 결정대로이며 골든 판은 닿지 않음. 사용자 판에서 체감될 수 있는 변화라 디자인 쪽에 한 줄 알림 | T1-B `combat_core.gd` `_reduction_bps` |
| C2 | T1-B의 `_gear_with_conditions()`는 키가 없을 때 `_gear_stats` 자체를 돌려준다(복사 아님). 지금 부르는 쪽이 고치지 않으므로 문제 없음. 부르는 쪽이 사전을 고치면 장비 합계가 바뀐다 — 고치지 말라는 주석 한 줄이 있으면 좋다 | T1-B `combat_core.gd` |
| C3 | 여섯째 골든 해시를 만든 트리(0절) | `chapter1/tests/golden/core_runtime*.json` |
| C4 | `affix_rolls.tier_window`(3)는 검사만 되고 굴림에서 쓰이지 않는다. "가장 높은 셋"은 각 행의 `level`·`max_level`·`legacy_windows`로 데이터에 박혀 있다. 필드를 지우거나, 창이 데이터와 맞는지 검사로 묶는다 | `loot.gd:169,203`, `_roll_lines_v2` |
| C5 | `_roll_lines_v2`의 단 뽑기에서 후보 행들의 `share` 합이 0이면 `randi_range(1,0)`. 풀 행은 단 번호를 검사하지만 살아 있는 행의 `tier`는 `tiers` 표에 있는지 검사하지 않는다. 지금 데이터(1~3)는 안전 | `loot.gd` `_check_affix_rolls`, `_roll_lines_v2` |
| C6 | R0-B: "저장 없이 하기"(`_profile_session_off`)에서는 프로필이 없어 늘 긴 도입부다. 의도와 맞는지 디자인 쪽에서 한 번 볼 것 | `chapter_one.gd:426~430` |
| C7 | R1-B: `start()`의 `_threat_on` 판정이 `beat.wave.crest`를 바로 읽는다. 검사기가 `wave`가 사전이면 `crest`를 요구하므로 지금은 안전 | R1-B `chapter_core.gd` start |
| C8 | `CLAUDE.md`의 "저장" 절이 낡았다: 코드는 스키마 5, `user://chapter-one-profile-v5.json`(`chapter_profile.gd:2,10,21`). 디렉터가 고칠 것 | `CLAUDE.md` |

---

## 5. 직접 실행한 명령과 실행하지 못한 확인

실행함:
- `git log --oneline 60287c4..HEAD`, `git show <커밋> -- <파일>`, `git diff 2e91340..6f042f3 -- chapter1/core/chapter_core.gd`, `git status --short`, `git diff --stat`.
- 임시 폴더(scratchpad)에 `HEAD`의 해당 파일을 꺼내 `git apply --check`로 세 패치를 차례로: T1-B ✓, R1-B ✓, 데이터 손질 ✗(`loot.json:194`).
- 파이썬으로 데이터 읽기: `loot.json`의 등급표·전설 레벨·살아 있는 접사의 `class`·감소 행, 작업 트리의 합친 `loot.json`, 골든 json 두 판(HEAD 대 작업 트리)의 사례별 해시.

실행하지 못함(디렉터의 전체 회귀가 도는 중이라 Godot를 띄우지 않음):
- 골든(꺼짐 다섯 건·여섯째 건), `--dump-at` 비교(1절 5번의 명령), `test_loot`, `test_chapter_run`, `test_rhythm`, `sim_loot`. 이 문서의 "불변"과 1절의 확률은 코드 읽기와 모델의 답이다.
- 화면: 보지 않음(강림 효과 캡처 포함).
