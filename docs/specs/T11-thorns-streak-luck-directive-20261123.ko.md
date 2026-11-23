# T11 지시서 — D23 T17 가시·몰아침, D23 T8 운 (2026-11-23)

작성: 기술 책임자(tech-lead) · 판정: 총괄 디렉터 · 구현: `gameplay-systems`(코어·검사·골든), `content-balance`(B5·측정)
기준 커밋: main `9cb39fa`(D23 T9 천장, B1·B4, 강림 옛 필드 정리가 들어간 뒤).

**사용자 지시(원문, 2026-11-22, U-78)**: "장비는 확률을 적용하면 좋겠어. 확률에 따라 옵션들이 붙는걸로 이 설계도 필요할 거 같네." 큰 방향은 D23 6.1 U1~U7 "권고대로"로 확정됐다(장부 U-81). U1(운)은 (b) "머리·목걸이·반지에 운 한 줄, 상한 30%, 판 시작 때 값으로 고정"이다.

**받는 명세 절.**
- 가시 `thorns_bps`: D12 D2 표의 `thorns_bps` 줄. 칸·갈래는 D12 D3 몸통.
- 몰아침 `streak_projectiles`: D12 D2, D6 5.2 H4("3초 안 처치 20회마다 다음 시전 발사체 +N").
- 운 `luck_bps`: D23 3.1 ②, 3.9 안 B, 3.14의 `luck` 블록, 3.16의 운 줄. 상한은 D23-T1 지시서 1절 "라".
- 은총 운 `grace_luck_bps`: D12 D2, D13 4.11.3. `run_growth.set_grade_luck`의 `gear_bps`가 받는 자리다.
- 순서: D23-T1 지시서 3절·5절(T17은 T1-B 뒤 P2, T8은 T1-B 뒤 곁가지).
- B5: `docs/reviews/TECH-REVIEW-20261123.ko.md` 116행.

**표기.**
- [코드]: 이 문서를 쓰며 코드를 직접 읽었다.
- [정함]: 명세에 없어 기술 책임자가 정했다. 뒤집으려면 design-lead가 고친다.
- [가설]: 재기 전의 첫 값이다.
- 줄 번호는 `9cb39fa` 기준이다. 받을 때 다시 확인한다.

다섯 요소 약호: 섹(섹시) · 쾌(쾌감) · 도(도박) · 보(보상) · 성(성장).

---

## 0. 한눈에

| 조각 | 담당 | 작업 트리 | 선행 | 고치는 파일 |
|---|---|---|---|---|
| **T17** 가시·몰아침 | gameplay-systems | `wt-d23-t17` | 없음(T1-B 병합됨) | 2.7 |
| **T8** 운·은총 운 | gameplay-systems | `wt-d23-t8`(T17 병합 뒤 main에서) | T17 병합 | 3.8 |
| **B5** 시뮬레이터 빈 통과 막기 | content-balance | `wt-d23-b5` | 없음 | `chapter1/tests/sim_loot.gd`만 |
| **T8-M** 운 측정 | content-balance | 본 저장소(읽기) | T8·B5 병합 | 파일을 고치지 않음 |

- T17과 T8은 같은 줄 여럿을 잡는다(4절). 그래서 한 담당이 **T17 → T8 차례로** 한다.
- B5는 다른 파일만 잡으므로 지금 나란히 돌린다.

---

## 1. 지금 코드에서 확인한 것 [코드]

- `loot.gd` 23행 `STATS_READ`에 키 27개가 있다(T1-B까지). `thorns_bps`, `streak_projectiles`, `luck_bps`, `grace_luck_bps`는 없다.
- `loot.json` `affix_rolls.pool`에서 `core_reads:false`인 행:
  - `thorns_1~5`: 몸통 접두, condition, 가중 40, 값 300~3000.
  - `streak_3`·`streak_5`: 신발 접두, condition, 가중 40, 값 1·2, `excludes:["projectiles"]`.
  - `luck_1~5`: 머리·목걸이·반지 접미, number, 가중 100, 값 200~1800.
  - `grace_luck_3~5`: 머리 접두, skill, 가중 15, 레벨 10부터.
  - 그 밖에 `kill_essence_*`(T12)와 `vs_heated/shocked_*`(T16). 이번 범위가 아니다.
- `limits`에 `thorns_bps [0,3000]`, `streak_projectiles [0,4]`, `luck_bps [0,3000]`, `grace_luck_bps [0,5000]`가 이미 있다.
- `loot.json`에 최상위 `luck` 블록이 없다. `pity`는 있다(꺼짐).
- `combat_core._hero_damage`(828~856행)는 `source_kind`·`source_id`를 받고 `hero_hit`를 낸다.
  - 막힌 맞음(무적)은 이벤트를 내지 않는다.
  - 몸통 공격은 `_step_enemies`(676·697행)와 `_resolve_elite_attack`(1311행, chapter_core 1087행)에서 들어온다.
  - 적 탄은 `_step_projectiles`(1213행)에서 `_hostile_src`로 쏜 적을 찾는다.
  - 바닥 위험은 `source_id` 0이다(chapter_core 1652행).
- 한 틱에 맞음은 많아야 하나다. 맞으면 `_invulnerable_until = tick+iframes`이기 때문이다.
- 처치는 `chapter_core._damage_enemy`(2832행~, 2960행 `kills+=1`)와 `combat_core._damage_enemy`(1256행~)에서 일어난다.
  - 둘 다 `_emit("death", … {"skill_id", "role"})`을 낸다.
  - `chapter_core._emit`(1089행)이 `death`를 받아 봉인 처치·강림 게이지·처치 몰아 보상을 센다.
- 주문 아닌 한 방의 선례가 `_descent_blow`(chapter_core 2409행)다. 맥락 하나를 만들어 `_damage_enemy`를 부른다.
- `_condition_bps`(chapter_core 2820행)는 모든 `_damage_enemy` 호출에 걸린다. 강림의 한 방도 받는다.
- 시전은 `combat_core._auto_casts`(907~966행)에서만 일어난다. chapter_core에는 재정의가 없다.
  - 발사체는 `_skill_with`(399행)에서 `gear.projectiles`를 더한다. 연쇄 주문은 그 값을 `chain_targets`로 받는다.
- `combat_tuning.gd` 31행 `GEAR_CONDITIONS_KEYS`는 키가 정확히 같아야 통과한다(`keys_match`). 데이터에 키를 더하면 같은 패치에서 검사기도 고쳐야 한다.
- 운이 들어갈 자리:
  - `loot.roll_class(rng, class_id, zone_level, primary, mods, first_quality)`(555행)의 `mods`는 지금 `drop_bps`·`quality_bps`만 읽는다.
  - 코어의 `roll_class` 호출은 다섯 곳이다(chapter_core 1178·1180·1206·1220·1972행).
  - 판 안 사당은 그 가운데 일반·정예(1206·1220행)에만 `_luck_mods()`를 넘긴다.
- 은총 운: `run_growth.set_grade_luck(shrine_mul, reward_grade, gear_bps)`(646행)는 은총 등급이 꺼져 있으면 거절한다. 지금 `combat_tuning.grace.enabled`와 `grace.grades.enabled`가 모두 false다. 장비 몫의 상한은 `grace.grades.luck.gear_cap_bps` 5000이다.
- 시작 장비는 `import_starting_gear`(chapter_core 1551행)로 들어온다. 틱 0에서만 받는다.
- 코어 스냅숏(combat_core 1441행, chapter_core 2778행~)에 `metrics`가 통째로 들어간다. 그래서 새 계수는 장비가 있을 때만 만들어야 꺼진 판의 골든이 그대로다.
- `test_loot.gd` 500행 `ROLL_HASH`는 켠 경로 굴림 2,400번의 해시다(723~739행).
  - `roll_class`는 `mods` 없이 부른다. 그래서 운 공식은 이 해시를 바꾸지 않는다.
  - **`STATS_READ`가 바뀌면 후보가 바뀌어 해시가 바뀐다.**
- `golden_core.gd` 40행 `CASES`는 일곱 건이다.
  - 꺼진 판 다섯: frost, ember, arc, L20-lance, rhythm-c1.
  - `affix-on`, `pity-armed`.
  - `--update`는 기본 코어에서 **모든 건을 한 번에** 다시 쓴다(225행).
- `sim_loot.gd`:
  - 89~99행은 `--luck>0`일 때 `set_affix_rolls`가 있는지만 본다.
  - 105행은 `mods={"luck_bps":N}`를 넘기는데 `roll_class`가 이 값을 읽지 않는다. 이것이 B5의 빈 통과다.
- 자동 조작(`chapter_pilot.gd` 10행)의 장비 점수에 새 키 넷이 없다(가중 0). 판 중에 더 나은 드랍이 오면 그 칸의 장비를 바꿔 낀다.

---

## 2. T17 — 가시·몰아침 (`gameplay-systems`, `wt-d23-t17`)

### 2.0 한 줄

몸통의 `thorns_bps`는 맞은 피해의 일부를 가해자에게 돌려준다. 신발의 `streak_projectiles`는 3초 안 처치 20회마다 다음 주력 시전에 발사체를 더한다. 두 키를 `STATS_READ`에 넣는다. 꺼진 판(이 키를 가진 장비가 없는 판)은 한 틱도 바뀌지 않는다.

### 2.1 가시 규칙

| # | 규칙 | 출처 | 요소 |
|---|---|---|---|
| G1 | 돌려줄 양은 `max(1, raw × thorns_bps / 10000)`이다. `raw`는 스치기(graze)를 적용한 뒤, **피해 감소를 적용하기 전**의 값이다(`_hero_damage` 안에서 `Resolver.damage`를 부르기 직전의 `raw`). | 정함 — D12의 "받은 피해"를 감소 전으로 읽었다. 감소 후로 하면 같은 몸통 칸의 보호 줄과 서로 깎아 먹는다 | 쾌(버티며 되갚기)·성(몸통 빌드가 공격이 됨) |
| G2 | `thorns_bps`는 `_gear_stats`의 합(사당 버프 포함)이다. 새 상한은 두지 않는다. 몸통 한 칸이라 `limits`의 3000이 곧 상한이다. 전설·고유가 이 키를 주게 되면 그때 `stat_caps`에 상한을 더한다. | 정함 | 성 |
| G3 | 받는 쪽은 `source_id`의 적이다. 적이 `enemies`에 있고 `hp_raw > 0`이며 `generation == _epoch`일 때만 받는다. `source_id == 0`(바닥 위험, 우두머리 바닥 내려찍기)은 아무것도 하지 않는다. 적 탄은 쏜 적이 아직 살아 있으면 거리와 상관없이 받는다. | D12(가해자) + 정함(거리 무관) | 쾌 |
| G4 | 맞음이 막혔을 때(무적, 이벤트 없음)와 그 맞음으로 주인공이 쓰러졌을 때(`hero.hp_raw <= 0`)는 돌려주지 않는다. | 정함 | — |
| G5 | **미룬 한 방.** `_hero_damage`는 돌려줄 것을 `_thorns_pending`(배열, 한 틱에 많아야 하나)에 적기만 한다. 적 목록과 탄 목록을 도는 중에 적을 죽이지 않기 위해서다. `combat_core.step()`에서 `_step_projectiles()` 바로 뒤, 끝남 검사(`if not _terminal_mode.is_empty()`) **앞**에서 `_resolve_thorns()`가 처리한다. 가시로 우두머리가 죽으면 같은 틱에 승리로 닫혀야 하기 때문이다. `step()` 첫머리에서 배열을 비운다(`_step_enemies`에서 패배하면 그 틱은 처리하지 않는다). | 정함 | — |
| G6 | 한 방은 `_descent_blow`와 같은 꼴로 `_damage_enemy(id, context, 0)`를 부른다. `context = {"uid": ++_cast_sequence, "skill_id": "gear.thorns", "effects": {damage_raw, proc_depth 0, death_burst 0, shatter_count 0, radius_cm 0, slow_bps 0, freeze_stacks 0, pierce 0, hit_budget 1, cooldown_ticks 0, projectiles 0, chain_targets 0, branches 0}, "remaining_hits": 1, "hit_ids": [], "evolved": false, "reflect": true}`. 이 함수는 두 코어에서 모두 돌아야 하므로 combat_core에 둔다. | 정함 | — |
| G7 | **가시는 조건형 피해 줄(`_condition_bps`)을 받지 않는다.** `chapter_core._damage_enemy` 2851행을 `var condition_bps := 0 if bool(context.get("reflect", false)) else _condition_bps(e, was_frozen)`로 바꾼다. 다음은 `skill_id` 검사가 이미 막는다: R1(주력에만), 표식 공명(주력에만), 주문 구성(`spells`에 없는 id), 자식 탄(주력에만), 냉기 감속. | 정함 — "돌려준다"를 글자 그대로 지켜, 화면에 보이는 수가 맞은 수의 비율로 읽히게 한다 | 쾌(읽히는 되갚기) |
| G8 | 가시의 처치는 마녀의 처치다. 봉인 처치, 처치 몰아 보상(C1-e), 강림 게이지, 드랍, 경험치 구슬이 주문의 처치와 똑같이 센다. 지금 `_emit` 경로가 그렇게 하므로 막지 않는다. | 정함 | 보 |
| G9 | 이벤트: 한 방 **앞에** `thorns` 하나를 낸다. `{"target_id", "amount_raw", "source_kind", "from": 주인공 위치}`. 그 뒤 `_damage_enemy`가 평소처럼 `hit`(그리고 죽으면 `death`)를 `skill_id:"gear.thorns"`로 낸다. 표현은 이 이벤트만 읽는다. | 정함 | 쾌 |
| G10 | 계수: 가시 장비가 처음 걸린 때에만 `metrics.thorns = {"hits", "raw", "kills"}`를 만든다. 꺼진 판의 `metrics`에는 키가 없어야 한다. | 정함 | — |

### 2.2 몰아침 규칙

| # | 규칙 | 출처 | 요소 |
|---|---|---|---|
| S1 | 처치를 세는 곳: `combat_core._emit`에서 `type == "death"`일 때 `_streak_note(details)`를 부른다. 이렇게 하면 두 코어가 모두 지난다. 첫 줄에서 `int(_gear_stats.get("streak_projectiles",0)) <= 0`이면 돌아간다. | 정함 | 쾌 |
| S2 | 세는 처치: 역할과 상관없이 모든 `death`. 다만 `skill_id`가 `"descent."`로 시작하면 세지 않는다. 강림 한 번이 몰아침을 공짜로 채우면 안 되기 때문이다. 가시의 처치(`gear.thorns`)는 센다. | 정함(처치 몰아 보상 `_kill_burst_note`와 같은 거름) | 쾌 |
| S3 | 창과 문턱은 `combat_tuning.gear_conditions`의 새 선택 키 둘이다. `streak_window_ticks` 180과 `streak_kills` 20(D6 H4의 "3초·20회"). 처치 틱을 목록에 넣고, 창보다 오래된 것을 지우고, 개수가 `streak_kills` 이상이면 **장전**한다. 키가 없으면 장전되지 않는다. 다른 조건 키가 `gear_conditions` 없이는 참이 되지 않는 것과 같다. | D6 H4 + 정함(데이터 자리) | 쾌 |
| S4 | 장전: `_streak_charge = mini(4, streak_projectiles)`. 처치 목록을 비우고 `streak_ready` `{"charge", "kills"}`를 낸다. **장전된 동안에는 처치를 세지 않는다**(쌓아 두지 않음). 장전은 시전 전에 장비를 벗어도 남는다. | 정함 | 쾌 |
| S5 | 쓰기: `_auto_casts`에서 `id_ == _primary_id`이고 링 주문이 아니며 `_streak_charge > 0`이면, 그 시전만 `var g := _gear_with_conditions().duplicate(); g.projectiles = int(g.get("projectiles",0)) + _streak_charge; skill = _skill_with(id_, g)`로 다시 계산한다. 연쇄 주문(번개)은 `_skill_with`의 기존 규칙대로 연쇄 대상으로 받는다. 16·32 상한과 `hit_budget`의 +8도 기존 규칙 그대로다. 대상을 찾지 못해 시전하지 않은 틱에는 쓰지 않는다(장전 유지). 시전하면 `cast` 이벤트에 `"streak": charge`를 붙이고 `_streak_charge = 0`으로 둔다. 보조 주문은 받지 않는다. | D6 H4(다음 시전) + 정함(주력만) | 쾌·섹(한 번 터지는 큰 부채꼴) |
| S6 | `effective_skill`과 능력치 판(`stat_sheet`)에는 장전을 넣지 않는다. 읽기 함수가 상태를 바꾸지 않게 하고, 장전은 시전 한 곳에서만 쓰이게 하기 위해서다. | 정함 | — |
| S7 | 스냅숏: `streak_projectiles > 0`을 끼고 있거나 `_streak_charge > 0`일 때만 `result.streak = {"kills": [틱…], "charge": n}`을 넣는다. | 정함(T1-B `gear_clock`과 같은 방식) | — |
| S8 | 계수: 처음 장전될 때 `metrics.streak = {"armed", "casts", "extra"}`를 만든다(lazy). | 정함 | — |
| S9 | 전설 `torrent`(D6 5.3 10번, +3)는 이번 범위가 아니다. 들어오면 같은 장전을 쓴다(키 합). | — | — |

### 2.3 데이터(같은 패치에서 gameplay-systems가 고친다)

`GEAR_CONDITIONS_KEYS`가 정확히 같아야 통과하므로, 검사기와 데이터는 한 패치에 함께 들어가야 한다. 그래서 이번에는 데이터도 구현 담당이 고친다. 값은 명세 값이고 지어낸 수가 아니다.

1. `combat_tuning.gd`: `gear_conditions`의 필수 키 셋은 그대로 둔다. 선택 키 `streak_kills`(1~200)와 `streak_window_ticks`(1~3600)는 **둘 다 있거나 둘 다 없어야** 한다. 하나만 있으면 거절한다.
2. `combat_tuning.json` 62행: `"streak_kills": 20, "streak_window_ticks": 180`을 더한다.
3. `loot.json`: `thorns_1~5`, `streak_3`, `streak_5`의 `core_reads`를 `true`로 바꾼다.
4. `loot.gd`:
   - `STATS_READ`에 `"thorns_bps"`, `"streak_projectiles"`를 더한다.
   - `score` 가중에 `"thorns_bps": .003`(조건형 절반, T1-B 2.6과 같은 규칙)와 `"streak_projectiles": 8.0`(발사체 16의 절반)을 더한다 [가설].

### 2.4 꺼진 판 불변 조건

- 가시·몰아침 키가 0인 판(지금의 모든 판)에서 다음이 지금과 같아야 한다: 난수 소비, `_cast_sequence`, 이벤트, `metrics`, 스냅숏 키.
- 증거:
  - 골든 일곱 건 가운데 `affix-on`을 뺀 **여섯 건의 해시가 그대로**다.
  - `affix-on`은 `STATS_READ`가 바뀌어 몸통·신발의 후보가 바뀌므로 해시가 바뀔 수 있다. 그 판이 몸통·신발 희귀를 굴리지 않았다면 그대로일 수도 있다.
- **`--update` 전에** 비교를 먼저 돌려, `mismatches`가 `11:chapter1.skill.frost:affix-on` 하나(또는 0)인지 확인한다. 다른 건이 바뀌었으면 `--update` 하지 말고 멈춰서 보고한다. 어느 건의 몇 번째 확인점인지 함께 적는다.
- `measure_combat.gd -- --arc-combined --secondary-off`의 출력이 main과 같다(데이터 파일을 고쳤으므로 CLAUDE.md 규칙대로 돌린다).
- `sim_loot --runs=10000`(끔)의 `LOOT_SIM` 줄이 main과 글자 단위로 같다.

### 2.5 켠 경로 골든 — 새 건 `gear-t17`

- `CASES`에 `[11,"chapter1.skill.frost","gear-t17","","gear-t17"]`을 더한다(여덟째).
- 새 고정 파일 `chapter1/tests/fixtures/golden_gear.json`을 만든다. `gear_kits.json`과 같은 꼴로 `kits.kit.golden.t17`을 적는다.
  - 몸통은 `thorns_5` 한 줄과 숫자형 줄로 된 희귀다.
  - 신발은 `streak_5` 한 줄과 숫자형 줄로 된 희귀다.
  - **자동 조작이 이 둘을 판 중에 벗지 않게** 다른 줄은 `chapter_pilot.gd` 10행 점수가 높은 숫자형으로 채운다. 몸통은 생명·보호, 신발은 이동, Ⅲ단 위 끝.
  - `gear_kits.json`은 content-balance가 F2 묶음을 쓰는 파일이므로 건드리지 않는다.
- `trial_docs.gd`에 `wear_fixture_kit_problem(run, kit_id) -> String`을 더한다.
  - `GearKits.items(run.loot, GearKits.load_fixture("res://chapter1/tests/fixtures/golden_gear.json"), kit_id)`로 짓는다.
  - 각 항목에 `storage_id`와 `equip_slot`을 붙여 **`run.import_starting_gear(...)`로** 끼운다. 실제 마을→판 경로다. `GearKits.install`의 사적 접근은 쓰지 않는다.
- `golden_core.gd`의 `play()`: 장치 준비는 `start()` 전에, 장비는 `start()`가 성공한 **직후**(첫 `step` 전)에 끼운다. `setup == "gear-t17"`일 때만이다.
- **빈 골든 막기**: `test_chapter_run.gd`에 같은 설정(시드 11, frost, 같은 묶음, 자동 조작)으로 판을 끝까지 돌리는 검사를 둔다. `thorns` 이벤트 1회 이상, `streak_ready` 1회 이상, `"streak"`가 붙은 `cast` 1회 이상을 확인한다. 이 셋이 없으면 골든 건이 가시·몰아침을 지키지 못한다는 뜻이므로 묶음을 고친다. 시간이 많이 들면 일정 틱까지만 돌리고 그 틱을 적는다.

### 2.6 단위 검사(`test_chapter_run.gd`, T1-B 검사 곁에)

| # | 기대 |
|---|---|
| K1 | 가시 0: walker의 맞음 한 번 앞뒤로 적 생명·이벤트·`metrics`·스냅숏 키가 가시 코드 전과 같다(`thorns` 이벤트 없음, `metrics.thorns` 없음) |
| K2 | 가시 3000, raw 10000(UNIT 단위로 맞춤): 가해자 생명이 정확히 3000 준다. `hit.skill_id == "gear.thorns"`, `thorns.amount_raw == 3000`, `hero_hit`와 같은 틱 |
| K3 | 피해 감소 7500을 낀 채 같은 맞음: 돌려준 양이 여전히 3000이다(감소 전 기준, G1) |
| K4 | 스치기(`heavy_hit`가 graze로 깎은 맞음): 깎인 raw의 30%를 돌려준다 |
| K5 | `vs_elite_bps` 5000을 함께 끼고 정예가 때림: 돌려준 양이 조건형 배수 없이 같다(G7) |
| K6 | `source_id` 0(바닥 위험), 무적 중의 맞음, 쓰러지는 맞음: `thorns` 이벤트 0 |
| K7 | 적 탄: 쏜 적이 멀리 있어도 받는다. 쏜 적이 탄보다 먼저 죽었으면 0 |
| K8 | 가시로 처치: `death.skill_id == "gear.thorns"`, `kills`+1, 봉인 처치+1(구역 안일 때), 경험치 구슬 1 |
| K9 | 가시로 우두머리 마지막 생명을 깎음: 같은 틱에 `victory` |
| K10 | 몰아침 0: 처치 30회에도 `streak_ready` 0, 스냅숏에 `streak` 없음 |
| K11 | 몰아침 2, 창 180·문턱 20: 179틱 안 19처치 → 장전 없음. 20번째 → `streak_ready{charge:2}`. 창보다 오래된 처치는 빠진다 |
| K12 | 장전 뒤 첫 주력 시전: frost·ember는 `effects.projectiles`가 +2, arc는 `chain_targets`가 +2, `cast.streak == 2`. 그다음 시전은 원래대로. 같은 틱의 보조 주문은 받지 않는다 |
| K13 | 강림의 처치(`descent.*`)는 세지 않고, 가시의 처치는 센다 |
| K14 | 발사체 상한 16을 넘지 않는다 |
| K15 | `gear_conditions`에 `streak_kills`만 있는 문서는 `set_tuning`이 거절한다. 둘 다 없으면 받지만 장전되지 않는다 |

`test_loot.gd`:
- 기존 `core_reads`↔`STATS_READ` 일치 검사가 통과해야 한다(2.3의 3·4가 같은 패치여야 한다).
- B1의 시그마 검사가 모두 통과한 **뒤에** `ROLL_HASH`만 실패하면, 그 값을 갱신한다(4.2).

### 2.7 고칠 파일(T17)

`chapter1/core/combat_core.gd`(`_hero_damage`, `step`, 새 `_resolve_thorns`·`_streak_note`, `_auto_casts`, `_emit`, `snapshot`, `start`의 초기화) · `chapter1/core/chapter_core.gd`(2851행 한 줄) · `chapter1/core/combat_tuning.gd` · `chapter1/data/combat_tuning.json` · `chapter1/core/loot.gd`(`STATS_READ`·`score`) · `chapter1/data/loot.json`(`core_reads` 일곱 행) · `chapter1/tests/test_chapter_run.gd` · `chapter1/tests/test_loot.gd`(`ROLL_HASH`) · `chapter1/tests/golden_core.gd` · `chapter1/tests/support/trial_docs.gd` · `chapter1/tests/fixtures/golden_gear.json`(새 파일) · `chapter1/tests/golden/*.json`

---

## 3. T8 — 운·은총 운 (`gameplay-systems`, `wt-d23-t8`, T17 병합 뒤)

### 3.0 한 줄

머리·장신구의 `luck_bps` 합을 **판의 첫 틱에 한 번** 읽고 3000에서 자른다. 그 값을 판 내내 모든 무작위 등급 굴림의 희귀·전설·고유 가중에 체감 공식으로 곱한다. `grace_luck_bps`는 같은 순간에 은총 등급의 장비 몫으로 넘긴다(등급이 켜진 판에서만). 꺼진 스위치 또는 운 0에서는 굴림이 한 번도 달라지지 않는다.

### 3.1 데이터 블록(`loot.json` 최상위, 같은 패치)

```json
"luck": {"enabled": false, "stat": "luck_bps", "cap_bps": 3000, "k": {"rare": 6000, "legendary": 4000, "unique": 2500}, "snapshot": "run_start"}
```

- D23 3.14의 블록 그대로이고, `cap_bps`를 더했다 [정함]. D23-T1 1절 "라"의 합계 상한 3000을 데이터에 둔 것이다. 숫자를 코드에 박지 않는다.
- `_check`(pity 검사 곁)에서 다음을 검사한다. 틀리면 `load_file`이 실패한다.
  - 키 여섯이 정확히 있다. `enabled`는 bool이다. `stat == "luck_bps"`이고 `limits`에 있다.
  - `1 ≤ cap_bps ≤ 10000`. `k`의 키는 `rare`·`legendary`·`unique` 셋이고 값은 1 이상이다. `snapshot == "run_start"`다.
- 블록이 없으면 운은 꺼진 것이다.

### 3.2 `loot.gd`

| # | 규칙 | 출처 | 요소 |
|---|---|---|---|
| L1 | `luck_on()`, `luck_cap_bps()`, `set_luck(enabled) -> bool`. 켜기는 블록이 있을 때만 참이다. `set_pity`와 같은 꼴로, 데이터 파일은 고치지 않는다. 기본값은 데이터의 `enabled`다. | 정함(T9와 같은 계약) | — |
| L2 | `roll_class`의 **매개변수는 늘리지 않는다**. 운은 `mods.luck_bps`로 들어온다(sim_loot이 이미 그렇게 넘긴다). `first_quality`(T9)는 그대로다. | 정함 | — |
| L3 | 가중 계산: 사당의 `quality_bps`를 먼저 적용한다(지금 코드 그대로). 그 뒤 `luck_on()`이고 `L = mini(int(mods.get("luck_bps",0)), luck_cap_bps()) > 0`일 때만, `k`에 있는 등급 q마다 `w[q] = w[q] × (10000 + L×K[q]/(L+K[q])) / 10000`(정수 나눗셈, 이 순서)을 계산한다. 마법·일반은 그대로다. | D23 3.9 안 B | 도·보 |
| L4 | 운은 **무작위 등급 굴림에만** 걸린다. 보장 줄(`guaranteed`), 천장의 `first_quality`, `unique_primary`에는 걸리지 않는다. 드랍 확률(`drop`/`no_drop`)에도 걸리지 않는다. | D23 3.1 ②(등급 가중) | 도 |
| L5 | 읽기 도우미 `quality_weights(class_id, mods) -> Dictionary`(순수 함수). `roll_class`가 이 함수로 가중을 얻게 바꿔도 된다. 다만 `mods`가 비었거나 운이 0이면 지금과 **같은 사전**(같은 값, 같은 순회 순서 `data.qualities`)이어야 한다. 검사와 B5의 탐침이 이 함수를 쓴다. | 정함 | — |
| L6 | `STATS_READ`에 `"luck_bps"`를 더한다. `luck_1~5`의 `core_reads`를 `true`로 바꾼다. `score`에서 `luck_bps`의 가중은 **0**이다. 판 중에 운 장비로 바꿔 껴도 이번 판에는 소용이 없고, 자동 장착이 힘 줄을 버리게 하면 안 되기 때문이다. | 정함 | 도(운을 고르는 일은 판 밖에서 하는 결정) |
| L7 | `grace_luck_bps`는 **`STATS_READ`에 넣지 않는다**(`core_reads:false` 유지). 코어가 읽는 자리는 이번에 만든다(3.3 C5). 하지만 은총 등급(`grace.grades.enabled`)이 꺼진 지금은 죽은 줄이다. 등급을 켜는 패치가 같은 패치에서 `STATS_READ`에 넣는다(5절). | D23-T1 3절(등급이 켜져야 뜻이 있음) | 도 |

### 3.3 `chapter_core.gd`

| # | 규칙 | 출처 | 요소 |
|---|---|---|---|
| C1 | **스냅숏 시점**: `step()` 재정의(1657행)의 첫머리, `super.step(move)` **앞**에서 `tick == 0 and mode == "playing" and not _luck_taken`이면 `_take_luck()`을 부른다. 이렇게 하면 `start()` 뒤 `import_starting_gear`로 들어온 장비까지 잡히고, 어떤 굴림보다도 앞선다. `start()`에서 `_luck_taken = false; _run_luck_bps = 0; _run_luck_worn = 0`으로 둔다. | D23 3.9(판 시작 스냅숏) + 정함(첫 틱) | 도(갈아입기 꼼수 막기) |
| C2 | `_take_luck()`: `_run_luck_worn` = 낀 장비의 `luck_bps` 합. 사당 버프는 넣지 않는다(`_gear_totals(equipped)`로 계산). 그 뒤 `_run_luck_bps = mini(worn, loot.luck_cap_bps()) if loot.luck_on() else 0`로 정하고 `_luck_taken = true`로 둔다. 판 중에 장비를 바꿔도 `_run_luck_bps`는 그대로다. | D23-T1 1절 라 | 도 |
| C3 | `_run_luck_bps > 0`일 때 `super.step` **뒤에** `luck_locked` 이벤트 `{"luck_bps", "worn_bps", "capped": worn > cap}`를 한 번 낸다(`step`이 첫머리에서 `events`를 비우기 때문이다). `metrics.luck = {"rolls": 0}`도 이때 만든다. | 정함 | 도 |
| C4 | 굴림에 넘기기: 새 `_drop_mods(shrine: bool) -> Dictionary`. `shrine`이 참이면 `_luck_mods()`(사당)를 복사하고, `_run_luck_bps > 0`이면 `luck_bps`를 얹는다. 둘 다 없으면 `{}`다(지금과 같은 사전). 1206·1220행(일반·정예)은 `_drop_mods(true)`를 쓴다. 1180행(수호자·우두머리, 지금 `{}`)과 1972행(지키는 상자)은 `_drop_mods(false)`를 쓴다. 1178행(`boss_first_kill`, 고유만)은 바꾸지 않는다. `_run_luck_bps > 0`이고 `roll_class`를 부를 때마다 `metrics.luck.rolls`를 1 올린다. | D23 3.1 ②(모든 출처) + 정함(첫 처치 고유 제외, 사당의 적용 범위는 그대로) | 보·도 |
| C5 | 은총 운: `_take_luck()` 안에서 `_grace_on and growth.grades_on()`이고 낀 장비의 `grace_luck_bps` 합 G가 0보다 크면 `set_grace_luck(현재 shrine_mul_bps, 현재 reward_grade, mini(G, 10000))`을 부른다. 현재 값은 `growth.snapshot().grace.luck`에서 읽는다. 상한은 run_growth의 `gear_cap_bps`(5000)가 이미 자른다. G가 0이거나 등급이 꺼져 있으면 부르지 않는다. `_buffs_changed`(2020~2025행)는 이미 `gear_bps`를 보존하므로 고치지 않는다. | D13 4.11.3 + 정함(같은 스냅숏) | 도 |
| C6 | 읽기 함수 `luck_state() -> {"enabled", "worn_bps", "cap_bps", "run_bps", "locked": _luck_taken}`. `worn_bps`는 지금 낀 장비의 합이고 판 중에 변할 수 있다. `run_bps`는 판에 고정된 값이다. 화면(T7)이 "판 시작에 고정: 운 +N%, 지금 낀 것 +M%"를 보일 자리다. 상태를 바꾸지 않는다. 판 밖 `sheet_for`에서는 `locked: false`다. | 정함 | 도 |
| C7 | 스냅숏: `_run_luck_bps > 0`일 때만 `result.chapter.luck = {"run_bps", "worn_bps"}`를 넣는다. | 정함 | — |
| C8 | **저장은 건드리지 않는다.** 운 값은 판 안의 상태다. 저장의 `town.luck.drop_runs_since_legendary`(T9 천장)와 이름만 같고 아무 관계가 없다. 코드·이벤트 이름에 `town`을 쓰지 않는다. | 정함 | — |

### 3.4 꺼진 판 불변 조건

- 운 블록이 `enabled:false`이거나 운 장비가 없으면 `_drop_mods`가 지금과 같은 사전을 돌려준다(사당 있으면 사당 것, 없으면 `{}`). 그러면 `roll_class`의 가중과 난수 소비가 같다.
- 증거:
  - 골든 여덟 건 가운데 `affix-on`을 뺀 일곱 건의 해시가 그대로다. `affix-on`은 `STATS_READ`에 `luck_bps`가 더해져 머리·장신구 후보가 바뀌므로 바뀔 수 있다.
  - T9의 "빈 `first_quality` 동일성" 검사(test_loot 794행)가 그대로 통과한다.
  - `sim_loot --runs=10000`(끔)의 `LOOT_SIM` 줄이 main과 같다.

### 3.5 켠 경로 골든 — 새 건 `luck-on`

- `CASES`에 `[11,"chapter1.skill.frost","luck-on","","luck-on"]`을 더한다(아홉째).
- `trial_docs.gd`에 `enable_luck_problem(run)`을 더한다. 이 판만의 loot 표를 만들고 `set_luck(true)`로 켠다.
- `golden_gear.json`에 `kit.golden.t8`을 둔다. 머리·목걸이·반지·반지2에 `luck_5` 한 줄씩을 넣어 합이 3000을 넘게 한다(상한이 실제로 걸리는 판). 머리 칸 줄 하나는 `grace_luck_4`로 둔다. 등급이 꺼진 판이므로 아무 일도 없어야 하고, 그것까지 골든이 지킨다.
- 장비를 끼는 방법은 2.5와 같다(`start()` 직후 `import_starting_gear`).
- 빈 골든 막기: `test_chapter_run.gd`에서 같은 설정으로 다음을 확인한다.
  - `luck_locked{luck_bps:3000, capped:true}` 1회.
  - `metrics.luck.rolls ≥ 1`.
  - 판 중에 머리를 벗겨도(`unequip`) `luck_state().run_bps == 3000`이고 `worn_bps`는 준다.

### 3.6 단위 검사

`test_loot.gd`:

| # | 기대 |
|---|---|
| LK1 | 운 블록의 틀린 꼴 여섯 가지가 각각 `load_file` 실패: 키 빠짐, 키 더함, `enabled` 문자열, `cap_bps` 0, `k.rare` 0, `snapshot` 다른 값. 블록이 없으면 불러지고 `set_luck(true)`는 거절된다 |
| LK2 | `quality_weights`: `mods` 없음 = `{}` = `{luck_bps:0}` = 운 끔 상태의 `{luck_bps:3000}`. 넷 모두 데이터의 `quality` 그대로 |
| LK3 | 운 켬, `luck_bps` 3000: 일반 등급의 희귀·전설·고유 가중이 L3 공식값과 정수까지 같다(K는 데이터에서 읽는다). 마법·일반은 그대로다. 사당 `quality_bps`와 함께 줄 때는 사당을 먼저 곱한다 |
| LK4 | `luck_bps` 9000을 줘도 3000과 같은 가중이다(상한) |
| LK5 | 동일성: 운 끔 상태에서 `{luck_bps:3000}`을 준 `roll_class`가 `mods` 없는 호출과 같은 결과다(6등급 × 300번 해시, T9 794행과 같은 방식) |
| LK6 | 분포: 운 켬, 고정 시드, `roll_class("normal", 8)` 20만 번. 무작위 줄의 등급 비율이 L3 공식의 비율과 5시그마 안. 같은 시드의 운 0보다 희귀·전설·고유가 모두 많다 |
| LK7 | 보장 줄 불변: `roll_class("boss", …, {luck_bps:3000})`의 첫 줄 등급 분포가 운 0과 같다(보장 희귀) |
| LK8 | 데이터 정합: `affix_rolls.enabled`가 참이면 `luck.enabled`도 참이다. 운 줄만 구르고 효과가 없는 상태를 막는다. 지금은 둘 다 거짓이라 통과한다 |
| LK9 | `core_reads`↔`STATS_READ` 일치(기존 검사). `grace_luck_*`는 `false`이고 `STATS_READ`에 없다 |

`test_chapter_run.gd`:

| # | 기대 |
|---|---|
| R1 | 운 장비 없음: `luck_state().run_bps == 0`, `luck_locked` 없음, `metrics.luck`·`chapter.luck` 없음 |
| R2 | 운 1800×2를 `import_starting_gear`로 끼고 첫 `step`: `run_bps == 3000`, `capped:true`. `start()` 직후(첫 step 전)에는 `locked:false` |
| R3 | 판 중에 운 장비를 끼거나 벗음: `run_bps`는 그대로, `worn_bps`만 변한다 |
| R4 | 운 블록 끔(`set_luck(false)`): 장비가 있어도 `run_bps == 0` |
| R5 | `_drop_mods(true)`는 사당이 켜졌을 때 사당의 두 키에 `luck_bps`를 더한 사전이고, 사당이 없으면 `{luck_bps}`만이다. `_drop_mods(false)`는 사당이 켜져 있어도 `{luck_bps}`만이다 |
| R6 | 은총 등급 꺼짐: 머리에 `grace_luck_4`가 있어도 `growth.snapshot().grace.luck.gear_bps`가 0이고 `errors`가 비어 있다 |
| R7 | 은총 등급 켬(`tuning_with`로 `grace.enabled`·`grades.enabled`): 첫 step 뒤 `gear_bps`가 장비 합이다. 판 중에 벗어도 그대로다. 사당 "행운" 버프가 시작·끝나도 `gear_bps`가 보존된다 |

### 3.7 `ROLL_HASH`와 골든 갱신

4.2를 따른다. T8 패치에서 `ROLL_HASH`를 한 번 더 갱신한다(`luck_bps`가 `STATS_READ`에 들어감).

### 3.8 고칠 파일(T8)

`chapter1/core/loot.gd` · `chapter1/data/loot.json`(`luck` 블록, `luck_*`의 `core_reads`) · `chapter1/core/chapter_core.gd`(`start`, `step`, `_take_luck`, `_drop_mods`, 1180·1206·1220·1972행, `luck_state`, `snapshot`) · `chapter1/tests/test_loot.gd` · `chapter1/tests/test_chapter_run.gd` · `chapter1/tests/golden_core.gd` · `chapter1/tests/support/trial_docs.gd` · `chapter1/tests/fixtures/golden_gear.json` · `chapter1/tests/golden/*.json`

---

## 4. 같은 파일, 순서, 오늘 들어온 것과의 충돌

### 4.1 겹치는 곳

| 파일·자리 | T17 | T8 | B5 |
|---|---|---|---|
| `loot.gd` 23행 `STATS_READ`(한 줄) | +2 | +1 | — |
| `loot.gd` `score` 가중(한 줄) | +2 | +1(0) | — |
| `loot.json` `affix_rolls.pool`의 `core_reads` | 7행 | 5행 | — |
| `test_loot.gd` 500행 `ROLL_HASH` | 갱신 | 갱신 | — |
| `golden_core.gd` 40행 `CASES`, `play()` | +1건 | +1건 | — |
| `trial_docs.gd`, `golden_gear.json` | 새 함수·묶음 | 새 함수·묶음 | — |
| `chapter1/tests/golden/*.json` | 갱신 | 갱신 | — |
| `chapter_core.gd` | 2851행 | `step`·드랍 자리 | — |
| `test_chapter_run.gd` | 새 검사 | 새 검사 | — |
| `sim_loot.gd` | — | — | 89~105행 |

같은 줄을 여섯 군데 넘게 함께 잡는다. 그러므로 **둘로 가르지 않는다.** gameplay-systems 한 담당이 T17을 병합한 뒤 main에서 T8의 트리를 새로 만든다. B5는 겹침이 없어 지금 나란히 간다.

### 4.2 오늘 들어온 것과 부딪히는 곳

- **B1 `ROLL_HASH`**: `STATS_READ`를 바꾸는 패치는 모두 이 해시를 바꾼다. 갱신 절차:
  1. 패치를 넣고 `test_loot`를 돌린다.
  2. B1의 시그마·창·가중 검사(a~f)가 **모두 통과**하고 실패가 "pinned hash" 한 줄뿐인지 본다.
  3. 실패 줄의 `got` 값을 `ROLL_HASH`에 옮긴다.
  4. 보고서에 "의도한 변경: `STATS_READ` +키"를 적는다.

  시그마 검사가 하나라도 실패하면 해시를 고치지 않고 멈춘다. B1 (e)의 "아직 읽지 않는 행이 있다" 검사(566행)는 T8 뒤에도 `kill_essence`·`vs_heated/shocked`·`grace_luck`이 남아 통과한다. B1 (d) "head at 12"는 `open_ladders`가 `STATS_READ`를 읽으므로 운 사다리가 저절로 들어간다.
- **T9 `first_quality`·`pity`**: 운은 `mods`로만 들어오고 매개변수를 늘리지 않는다(L2). 천장의 첫 보장 줄에는 운이 걸리지 않는다(L4). 운이 전설·고유를 늘리면 천장이 걸리는 판이 줄어드는데, 그것은 의도한 상호작용이다. `pity-armed` 골든 건은 운 장비가 없으므로 그대로다.
- **골든 `--update`**: 모든 건을 한 번에 다시 쓴다. 그러므로 반드시 비교 → `mismatches` 확인 → `--update` 순서로 한다. T17·T8 모두 허용하는 변경은 `affix-on` 한 건과 새 건 추가뿐이다.
- **T5(`loot_flow.boss_spray`)**: 1180행 주변의 분출 코드는 `drops`를 받은 뒤의 일이다. T8은 `roll_class` 호출의 `mods` 인수만 바꾼다. 같은 함수를 고치므로 T8은 T5가 들어간 main(지금 main) 위에서 시작한다.

### 4.3 저장 계약

- T17과 T8 모두 저장 꼴, 스키마 번호, `chapter_profile.gd`를 건드리지 않는다.
- `thorns_*`·`streak_*`·`luck_*` 줄이 붙은 장비는 T1-A부터 이미 `validate`를 통과한다. 풀 행이기 때문이다.
- `import_starting_gear`로 끼우는 검사는 이것을 실행으로 다시 확인한다.
- 운 스냅숏은 저장되지 않는다(C8).
- 끝난 기준에 `test_chapter_profile`(run_all `chapter`·`profile` 묶음)이 그대로 통과하는 것을 넣는다.

---

## 5. 켜기 전 남은 일

이 세 키에는 자기 스위치가 없다. `affix_rolls.enabled`가 켜져야 장비에 붙는다. T8의 `luck.enabled`는 따로 있다.

| # | 남은 일 | 담당 |
|---|---|---|
| 1 | 가시·몰아침·운 줄이 드러날 때의 화면: `thorns` 되갚기 선, `streak_ready` 장전 표시와 `cast.streak` 큰 부채꼴, `luck_locked` 한 줄. 표현은 이벤트만 읽는다. 캡처를 직접 본다 | vfx-feel · ui-hud |
| 2 | 설명 판(T7): 운 "판 시작에 고정"(`luck_state`의 `run_bps`·`worn_bps`), 가시는 "맞은 피해의 N% 되갚음", 몰아침은 "3초 안 20처치 → 다음 시전 +N" | ui-hud |
| 3 | 표현이 모르는 `skill_id`(`gear.thorns`)를 받아도 오류가 없는지. `hud_dump`를 가시 묶음으로 한 판 돌리는 길이 지금은 없다 | qa-perf |
| 4 | 이름 확정(형극·쇄도·행운 후보, D23-T1 2.9) | narrative-lead → content-balance |
| 5 | 수치 판정(6절의 design-lead 몫이 정해진 뒤) | content-balance |
| 6 | `luck.enabled`를 `affix_rolls.enabled`와 같은 날 켠다(LK8 검사가 막는다) | 디렉터 |
| 7 | 은총 등급을 켜는 날 `grace_luck_bps`를 `STATS_READ`에 넣고 `grace_luck_*`의 `core_reads`를 켠다 | gameplay-systems |
| 8 | 사람 플레이: 운 한 줄을 힘 대신 골랐나, 가시가 "맞아도 좋은" 맛을 줬나, 몰아침이 터지는 순간을 알아봤나. 모두 **미평가** | 사용자 |

---

## 6. design-lead에게 넘길 것(지어내지 않음)

- **D1. 몰아침이 얼마나 자주 터져야 하나.** 명세에는 "3초 안 20처치"만 있고 목표 빈도가 없다. 마디별 살아 있는 수(기 3.4 · 승1 11.8 · 승2 21.5 · 전 32.8, D23-T1 A.2)로 보면 승2부터 닿을 것 같지만 재지 않았다. 판당 장전 횟수의 목표가 있어야 content-balance가 창·문턱을 판정할 수 있다.
- **D2. 가시의 몫 목표.** 가시 3000(맞은 피해의 30%)이 처리량의 몇 %가 되어야 "버팀 빌드가 공격이 된다"고 말할 수 있는지 정해야 한다. 정예·우두머리에 대한 몫도 함께 정한다.
- **D3. 운 3000에서도 `QUALITY-TARGETS` 4절의 네 목표가 적용되나.** D23 3.16은 "기존 넷, 켬·끔 모두"와 "운 3000에서 고유 ≤0.28"만 적었다. 공식으로 셈하면 희귀 가중 +20%·전설 +17%·고유 +27%다. 그런데 D23 3.9 모델 표는 희귀 +6%(4.72→5.00), 전설 +15%, 고유 +13%다(보장 줄과 마법 몫 때문으로 보인다). 지금 `sim_loot` 기준(희귀 4.655, 전설 0.38)에서 운 3000이 희귀 5 또는 전설 0.45를 넘으면 목표 위반인가, 운 장비를 낀 판의 예외인가.
- **D4. (정함을 뒤집을 경우만)** 가시가 감소 전 피해를 기준으로 하고(G1) 조건형 배수를 받지 않는 것(G7). 운이 보장 줄·첫 처치 고유에 걸리지 않는 것(L4·C4). 자동 장착 점수에서 운이 0인 것(L6).

---

## 7. 끝난 기준

### 7.1 T17(gameplay-systems)

```powershell
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_chapter_run.gd
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_loot.gd
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd -- --both
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/measure_combat.gd -- --arc-combined --secondary-off
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_loot.gd -- --runs=10000
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_loot.gd -- --runs=10000 --affix-rolls=on
python tools/dev/run_all.py
```

| 지표 | 기대 |
|---|---|
| `test_chapter_run`·`test_loot` | 통과(K1~K15, `core_reads` 일치, B1 a~f 통과 뒤 `ROLL_HASH` 갱신 한 번) |
| 골든 `--both` | 꺼진 다섯 + `pity-armed` = **여섯 건 불변**. `affix-on`은 바뀌거나 그대로. 새 `gear-t17` 추가. 갱신 전 `mismatches` 원문을 보고서에 붙인다 |
| `measure_combat` | main과 같은 출력(계열 셋 × 시드 3) |
| `sim_loot` 끔 | `LOOT_SIM` 줄이 main과 글자 단위로 같음 |
| `sim_loot` 켬 | 3.16 줄(희귀 기대 줄 수, 칸마다 5줄, 판당 5줄 0.30~0.45, Ⅴ단 판 10~18%, 대박 판 35~50%)을 패치 전후로 나란히 적는다. 판정은 content-balance가 하고, 여기서는 **기록만** 한다 |
| `run_all.py` 전체 | 통과(건수와 걸린 시간) |

### 7.2 T8(gameplay-systems)

7.1과 같은 명령을 돌린다. 기대는 다음과 같다.
- 골든: `affix-on`을 뺀 **일곱 건 불변**(꺼진 다섯 + `pity-armed` + `gear-t17`). 새 `luck-on` 추가.
- `test_loot` LK1~LK9와 `test_chapter_run` R1~R7이 통과한다. `ROLL_HASH`는 한 번 갱신한다.
- `sim_loot` 끔은 글자 단위로 같다.
- `--luck`의 판정은 7.3의 B5가 들어간 뒤 content-balance가 한다.

### 7.3 B5·T8-M(content-balance)

B5(`wt-d23-b5`, `sim_loot.gd`만, 지금):
1. `--luck>0`일 때 `loot.has_method("set_luck")`가 거짓이면 `LOOT_AFFIX_SIM_UNSUPPORTED {"requested":["--luck=N"], "reason":"코어에 운 가지 없음(D23 T8 전)", "measured":false}`를 찍고 **종료 3**. `set_luck(true)`가 거짓이면(블록 없음) 종료 2.
2. 운 탐침: `--luck>0`이고 운이 켜졌으면, 본 시뮬레이션 전에 `loot.quality_weights("normal", {})`와 `loot.quality_weights("normal", {"luck_bps":N})`를 견준 `LOOT_LUCK_PROBE {"luck":N, "weights_off":…, "weights_on":…, "changed":bool}`을 찍는다. `changed`가 거짓이면 종료 3이다(운이 아무것도 바꾸지 않았는데 잰 것처럼 끝나지 않게).
3. 머리 주석 7행과 36~37행에 위 규칙을 적는다.
4. 검사: T8 전 main에서 `--luck=3000`이 종료 3, `--luck=0`과 `--affix-rolls=on`만은 지금과 같은 출력.

T8-M(T8·B5 병합 뒤, 본 저장소, 파일 수정 없음). 명령:

```powershell
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_loot.gd -- --runs=10000 --affix-rolls=on
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_loot.gd -- --runs=10000 --affix-rolls=on --luck=1000
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_loot.gd -- --runs=10000 --affix-rolls=on --luck=3000
```

| 지표 | 목표 |
|---|---|
| `LOOT_LUCK_PROBE.changed` | 참(1000·3000 모두) |
| 운 0 → 1000 → 3000 | 희귀·전설·고유가 모두 늘어남(단조) |
| 운 3000의 고유(판당) | **≤ 0.28**(D23 3.16). 넘으면 넘었다고 적고 멈춘다 |
| 운 3000의 희귀·전설 | 기록만. 4절 목표(희귀 3~5, 전설 0.25~0.45) 밖이면 표시하고 design-lead D3에 올린다 |
| D23 3.9 모델 표와의 차 | 증가율을 나란히 적는다(모델 희귀 +6%·전설 +15%·고유 +13%). 차가 크면 까닭을 한 줄 적는다 |

모든 값은 10,000판 시뮬레이터의 값이다. 보고서에는 "시뮬레이터 10,000판"이라고 적는다.

### 7.4 패치와 보고서의 자리

| 조각 | 패치 | 보고서 |
|---|---|---|
| T17 | `_local/d23-t17/t17.patch` | `_local/d23-t17/REPORT.txt`(명령별 원문 출력 꼬리, 골든 `mismatches` 원문, `ROLL_HASH` 전후, 3.16 표 전후) |
| T8 | `_local/d23-t8/t8.patch` | `_local/d23-t8/REPORT.txt`(같은 꼴 + LK6 분포 표) |
| B5 | `_local/d23-t8/b5.patch` | `_local/d23-t8/B5-REPORT.txt` |
| T8-M | — | `_local/d23-t8/T8M-REPORT.txt` |

보고서에는 실제로 돌린 명령과 종료 코드만 "통과"로 적는다. 돌리지 않은 것은 "돌리지 않음"으로 적는다.

---

## 8. 건드리면 안 되는 것

- `chapter1/view/` 전부. 화면은 5절의 다른 담당 몫이다. 특히 `chapter1/view/` 바로 아래의 `cloister_*.gd`, `chapter_world_quality*.gd`는 건드리지 않는다.
- `chapter1/core/chapter_pilot.gd`. 바꾸면 모든 골든 건의 장비 선택이 흔들린다.
- `chapter1/core/chapter_profile.gd`, 저장 파일, `%APPDATA%\WitchMoira`.
- `loot.gd`의 꺼진 경로 굴림(`roll_item` 끔 가지)과 `_roll_lines_v2`의 후보 규칙. `STATS_READ` 목록만 바꾼다.
- `roll_class`의 매개변수 목록(L2).
- `chapter1/tests/fixtures/gear_kits.json`(content-balance F2 작업 파일). `sim_loot.gd`는 B5 담당만 고친다.
- `run_growth.gd`, `run_growth_quality37.gd`. 은총 운은 기존 `set_grade_luck`만 부른다.
- 골든을 `--update`할 때 허용되지 않은 건의 해시 변경을 덮어쓰는 일.
- `git add .`, 커밋·푸시. 디렉터가 한다.

---

## 9. 직접 확인한 것과 하지 못한 것

직접 확인 [코드]:
- 1절의 모든 줄 번호와 동작을 `9cb39fa` 작업 트리에서 읽었다.
- `loot.json`은 파이썬으로 펼쳐 `core_reads:false` 행, `limits`, `pity`, `luck` 블록이 없음, 보물 등급의 `lines_profile`을 봤다.
- `GEAR_CONDITIONS_KEYS`의 정확 일치, `golden_core --update`가 모든 건을 다시 쓴다는 것, `sim_loot` 89~105행의 B5 상태를 확인했다.

하지 못한 것:
- 아무 검사도 돌리지 않았다(코드·데이터를 고치지 않았다). 골든·`sim_loot`·`run_all`의 현재 통과는 디렉터가 전한 "오늘 아침 전체 회귀 40건 통과"를 근거로 삼았고, 다시 돌리지 않았다.
- 가시·몰아침 묶음을 낀 자동 조작 판에서 이벤트가 실제로 나는지는 2.5의 "빈 골든 막기" 검사가 처음 확인한다.
- 표현 쪽이 `gear.thorns`라는 `skill_id`를 받아도 안전한지는 `palette.gd` 83행(`has` 검사)과 `combat_juice.gd` 349행만 봤다. 전수 확인은 하지 않았다(5절 3).
- 운 공식이 실제 판당 수를 얼마나 올리는지는 모델의 답(D23 3.9)뿐이다.
