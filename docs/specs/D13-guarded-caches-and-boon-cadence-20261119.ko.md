# D13 지시서 — 정예가 지키는 자리와 판 안 부가 혜택(W4+W5), 은총이 오는 박자와 제안 규칙(W3+K3)

0판 · 2026-11-19 · 작성: 기획 책임자(design-lead) · 대상: `gameplay-systems`(코어·검증기·검사), `content-balance`(수치·시뮬레이터·측정 도구), 화면 `ui-hud`·`vfx-feel`, 소리 `sound-designer`, 이름과 글 `narrative-lead` · 판정: 총괄 디렉터

기준 명세: `docs/specs/D11-run-rhythm-and-reward-loop.ko.md`(3.1판) B·C·D절, `docs/specs/D12-skill-and-gear-redesign.ko.md`(3.1판) B0.3·B0.4·B5·G1·G2, `docs/specs/D2-elite-carrier-spec.ko.md`. 기준작 점검표 `docs/reviews/BENCHMARK-CHECKLIST-20261119.ko.md` 2-4(빈칸). 지시 장부 U-04·U-05·U-06.

**표기**: [본 것] 이번에 코드·데이터를 직접 읽어 확인한 것(파일과 행) · [가설] 출발 값 · [N1 뒤 확정] 균형 시험 N1(또는 그 뒤 J1·J2)의 결과로 값을 정할 것. 구조는 지금 정한다 · [미확인] 읽지 못했거나 돌리지 않아 모르는 것 · [플레이] 사용자 플레이로만 판정(지금 모두 미평가). 사상 표지는 D12 A장: `[섹]` 섹시 · `[쾌]` 쾌감 · `[도]` 도박 · `[보]` 보상 · `[성]` 성장.

이 문서를 쓰는 동안 Godot를 돌리지 않았고 게임 코드·데이터를 고치지 않았다. 수치는 모두 가설이다. N1 결과는 아직 오지 않았다(N0 결과 `_local/tools/n0/REPORT.txt`만 읽음).

---

## 0. 한 장 요약

**묶음 둘, 여섯 걸음.**

| 차례 | 걸음 | 하는 일 | 담당 | 골든(꺼짐) |
|---|---|---|---|---|
| 0 | **G0 공용 자리** | 튜닝 검증기에 선택 최상위 키 `grace`·`elites`·`extras`를 연다(없으면 지금과 같음) | gameplay-systems | 불변 |
| 1 | **K3a 은총 박자와 제안 도구** | 진화 최소 레벨, 레벨 12의 큰 제안, 다시 뽑기·제외·보류의 코어 함수, 은총 간격 바닥(선택), 경험치 문턱의 역산 도구 | gameplay-systems → content-balance | 불변 |
| 2 | **W4-a 정예의 몸** | D2 E1(접사 없음): `grade` 필드, 정예 만들기 함수, 구역별 생성(꺼짐) | gameplay-systems | 불변 |
| 3 | **W5-a 지키는 자리** | 사용자 제안 C6: 정예가 지키는 사당 1·상자 1, 잠김과 풀림, 사당의 일시 강화 층 | gameplay-systems | 불변 |
| 4 | **W5-b 보상 단계** | 단계 Ⅰ~Ⅳ, 의식 보상을 큰 상자로, 우두머리 전리품 수, 영구 경험치 가산과 `run_xp_max` | gameplay-systems → content-balance | 불변 |
| 5 | **W5-c 지키지 않는 상자·사당**, **W4-b 운반자** | 같은 자리 코드에 지킴 없음, D2 3절 운반자(단계 +1) | gameplay-systems | 불변 |

- 모든 걸음은 **꺼진 채** 들어간다. 켜는 것은 D12 G2의 차례대로 J2(은총·리듬)와 K6'(부가 혜택·드랍 수치)에서 한다. 켜는 커밋과 수치 커밋은 나눈다.
- **D12 G2와 다른 점**: D12는 W4·W5를 J2 뒤에 둔다. 이 지시서는 그 **코드(모양)** 만 앞당긴다. 값(정예 체력, 상자 내용, 사당 크기)은 그대로 J2·K6' 뒤에 정한다. 디렉터 확인이 필요하다(7.2 D-1).
- 사용자 제안의 핵심 — "정예가 지키고, 잡아야 상자·장치가 작동해 이로운 효과를 준다" — 은 걸음 2·3만으로 게임에 생긴다.

**코드에서 확인한 가장 중요한 사실** [본 것]: 지금 코어에는 **새 정예도, 보물 운반자도, 상자·사당도, 보상 단계도 없다.** 있는 것은 의식 둘(`vigil`·`reliquary`)과 드랍 표의 이름(`loot.json`의 `elite`·`carrier`), 드랍 시뮬레이터의 가정(`sim_loot.gd`의 정예 6·운반자 1)뿐이다. 코드의 `e.elite`는 정예가 아니라 **수호자·우두머리**를 뜻한다(D2 1절). 그래서 W4-a가 W5-a의 앞선 것이다.

---

## 1. 지금 코드에 있는 것 [본 것]

| 무엇 | 어디 | 지금 | 이 지시서와의 관계 |
|---|---|---|---|
| 의식 둘 | `chapter_core.gd` 40~43행 `RITUALS` | `vigil`(1구역, (8,-7), 지키기 25초) · `reliquary`(2구역, (40,6), 둘레 10m 처치 60) | W5-b가 보상을 바꾼다(켤 때만) |
| 의식 시작 | `activate_ritual`(1031행), 앱 `chapter_one.gd` 603~606행 | E 키, 3m 안. 자동 조작은 부르지 않는다(`chapter_pilot.gd`에 `ritual` 0건) | 그대로 |
| 의식 진행 | `_step_rituals`(1039~1054행) | 5m 안이면 3초마다 보행자 6·돌격 2. 구역을 떠나면 `abandoned` | 지키는 자리의 "구역을 떠나면 사라짐" 규칙이 이를 따른다 |
| 의식 보상 | 1053~1054행 | 희귀 1개 가방 직행(`source:"ritual"`) + 물약 1 | W5-b에서 `ritual_chest`로 |
| 의식 상태 | `snapshot().chapter.rituals`(1137행) | 골든 해시에 든다 | 새 상태는 켰을 때만 스냅숏에 넣는다 |
| 수호자·우두머리 | `_spawn_wave` 517~530행 | `_spawn("elite",…)` + `title_key`. `e.elite`가 참 | 이름 충돌(D2 1절). 새 정예는 `grade`로 가른다 |
| 적 역할 | `_enemy_role` 507~510행 | `normal`/`champion`/`boss`(그리고 `elite`라는 이름은 수호자 쪽에서만 나옴) | W4-a가 `grade:"elite"`를 `role`에 반영 |
| 재배치 | `combat_core.gd` `_cleanup` 1242행 | 25m 밖의 `not e.elite`·이동 중인 적을 12m로 옮긴다 | 지키는 정예는 빼야 한다 |
| 적 이동 | `combat_core.gd` `_step_enemies` 548행~ | 모든 일반 적이 주인공을 향한다 | 지키는 정예의 "자리 지킴" 분기가 필요 |
| 드랍 출처 | `_publish_item` 816~831행 | `item_drop.source` 있음(`normal`·`forced`·`ritual`·`champion`·`boss`·`first_kill`) | 새 출처 `chest`·`elite`·`carrier`를 그대로 쓴다. 허용 목록은 `test_rhythm.gd` 15행에 이미 있음 |
| 드랍 표 | `loot.json` `treasure_classes` | `normal`(55/10000), `elite`(80%), `carrier`(2회, 장신구 가중), `champion`(3회), `boss`(5회), `boss_first_kill` | `chest`·`guarded_chest`·`ritual_chest`·`boss_g1~g4`를 **새로 더한다**(지금 표는 켤 때까지 그대로) |
| 드랍 표 검증 | `loot.gd` 90~97행 | 표마다 모양(뽑기·확률·품질 가중)만 본다. 표 이름 목록은 고정이 아님 | 새 표를 더해도 `loot.gd`를 고칠 필요가 없다 |
| 튜닝 검증 | `combat_tuning.gd` 7·44~49행 | 최상위 키가 **정확히** 맞아야 한다. `rhythm`만 선택 키 | G0이 `grace`·`elites`·`extras`를 같은 방식의 선택 키로 연다 |
| 영구 경험치 한도 | `character_progression.gd` 129~150행, `chapter_profile.gd` 1369행 | `run_xp_max` = 봉인 650 + 수호자 130 + 우두머리 120 + 승리 100 = 1000. 넘으면 저장이 판 결과를 거부(`xp_out_of_range`). `test_skill_tree.gd` 111행이 1000을 확인 | W5-b가 단계 가산만큼 늘린다 |
| 영구 경험치 출처 검증 | `character_progression.gd` 42~59행 | `sources` 키 수가 정확히 맞아야 한다 | `grade_bonus_bps`는 선택 키로 연다 |
| 전투 기록기 | `run_record.gd` 169~170행 | `reward_grade_up` 이벤트를 이미 읽는다 | W5-b의 이벤트 이름을 이것에 맞춘다 |
| 저장 스키마 5 | `chapter_profile.gd` 57행 `LAST_CORE` | `grade`·`elite_kills` 자리가 이미 있다 | 저장 변경 없음 |
| 은총 문턱 | `combat_tuning.json` `xp_thresholds` [0,10,23,71,186,444,740,1167,1772,2552,3898,12000], `chapter_core.gd` 206행이 성장 카탈로그 값을 덮어씀 | 첫 60초에 은총 4~5번(D11 0.3) | K3a |
| 마지막 은총 | `_seal_grace`(752~757행), `final_level_on_boss_spawn` | 우두머리 등장 때 경험치를 마지막 문턱까지 채운다 | K3a의 "큰 제안"이 이 순간에 걸린다 |
| 은총 제안 | `run_growth.gd` `next_offer` 172~196행 | 보호 카드 1 + 가중 뽑기로 3장. 은총 전용 난수 `_rng` | K3a |
| 보호 카드 | 지금 구성 `_protected_card` 164~170행(주력 진화 길), 새 구성 `_protected_spell_card` 354~364행(레벨 2 원형, 레벨 3·5 짝, 그 밖 진화 쪽) | 레벨 12 규칙 없음 | K3a의 `final_offer` |
| 다시 뽑기 | `run_growth.gd` `reroll` 103~117행, `chapter_core.gd` `reroll_offer` 361~364행(이벤트 `grace_reroll`) | 트리 규칙 `grace_rerolls`(0~3)로만 생긴다. **화면에 단추가 없다**(`chapter1/view`·`app`에 `reroll` 0건, 트리 창의 설명 글 한 줄뿐) | K3a가 기본 횟수와 읽기 함수를 주고, 단추는 U-26 화면 재설계로 넘긴다 |
| 제외·보류 | — | 없다 | K3a |
| 고르는 화면으로 넘어감 | `combat_core.gd` `_refresh_mode` 213~220행 | 밀린 레벨이 있으면 바로 `choice` | 간격 바닥(선택)이 여기에 걸린다 |
| 리듬 이벤트 | `chapter_core.gd` 574·650행 | `beat_started {id}`, `lull_started {beat}` 있음 | 지키지 않는 사당이 `lull_started`에 놓인다(W5-c) |
| 포위 압력·격앙 | `chapter_core.gd`에서 `pressure`·`enrage` 0건 | — | [미확인] W1b의 이 부분이 들어왔는지. 이 지시서와 직접 얽히지 않는다 |
| 측정 | `measure_rhythm.gd` 111행 | `ritual*`·`chest*`·`shrine*`·`trial*`·`lull_started`·`carrier_kill` 이벤트를 이미 센다. `--rhythm-on` 있음 | `--extras-on`·`--grace-on`·`--pilot-extras`를 더한다 |
| 균형 시뮬레이터 | `tools/dev/balance_sim.py` 270·937·991·1256·1343·1688행 | `xp_thresholds`, `evolve_min_level`, 보호 카드, 마지막 제안(`final`), 판마다 `grace_times`를 이미 모델링한다 | K3a의 문턱을 여기서 먼저 본다 |
| 경제 시뮬레이터 | `tools/dev/sim_economy.py` 240~383·604~619행 | 상자·의식 상자·사당·운반자·보상 단계·단계 경험치 가산을 이미 모델링한다 | W5-b의 가산과 판당 단계 분포를 여기서 먼저 본다 |
| 시험장 | `chapter1/tests/sim_power.gd` 머리말 19·31행 | `--elite-hp=HP`(무리 속 강한 적 하나의 처치 시간), `--mode=strong` | 지키는 정예의 체력을 여기서 먼저 본다 |

---

## 2. 두 묶음에 공통인 규칙

1. **꺼진 값에서 골든 불변.** 골든은 `snapshot()`의 JSON 해시다(`golden_core.gd` 19행) [본 것]. 그래서:
   - 새 상태(지키는 자리, 보상 단계, 사당 버프, 제외 목록, 보류 카드)는 **스위치가 켜졌을 때만** 스냅숏에 키를 만든다. 꺼졌으면 키 자체가 없어야 한다.
   - 새 난수를 꺼진 판에서 하나도 뽑지 않는다.
   - 이벤트는 스냅숏에 들지 않는다(D11 F1 [확인]). 이벤트 필드를 더하는 것은 골든과 무관하다.
2. **난수 흐름.** 자리의 위치·사당 종류·상자 등급은 **새 흐름 `_extras_rng`**(판 시드에서 고정 상수로 갈라 만든다)로 뽑는다. `_spawn_rng`를 쓰면 부가 혜택을 켜는 것만으로 모든 생성이 바뀌어, 같은 시드의 켬/끔 비교가 무너진다. 상자 내용물과 정예 드랍은 지금처럼 `_loot_rng`로 굴린다(드랍 흐름은 원래 판마다 달라진다). 은총의 제외·다시 뽑기는 은총 전용 `_rng`를 쓴다(D12 B5.2와 같은 이유).
3. **검증기.** 새 블록은 모두 `combat_tuning.gd`의 선택 최상위 키다. 키가 없거나 `enabled:false`면 지금 동작. 키가 있으면 아래 각 절의 범위로 검사한다.
4. **자동 조작은 고치지 않는다.** `chapter_pilot.gd`의 기본 동작이 바뀌면 골든이 바뀐다. 측정에 필요한 "자리에 들르기"는 측정 도구 안에서 이동 방향을 덮어쓰는 방식으로 한다(5.4).
5. **표현은 읽기만.** 화면·소리는 코어 이벤트와 읽기 함수만 쓴다. 화면 설계는 이 지시서의 범위가 아니다. 여기서는 화면이 알아야 할 이벤트와 읽기 함수만 정하고, 화면 모양은 U-26·U-27의 화면 재설계(하네스 `docs/SCREEN-DESIGN-HARNESS.ko.md`)에서 정한다. 사용자 지침(설계 먼저, 낱개 화면 수정은 나중)에 따라 이 묶음에 화면 낱개 작업을 붙이지 않는다.
6. **이름은 자리표.** "사당", "보상 단계", "지키는 상자", 정예·운반자의 호칭은 `narrative-lead`가 정한다. id만 쓴다.
7. **다섯 사상.** 각 결정마다 무엇을 키우는지 붙였다. 하나도 키우지 않는 항목은 넣지 않았다.

---

## 3. G0 — 공용 자리(먼저, 작음)

| 항목 | 내용 |
|---|---|
| 담당 | `gameplay-systems` |
| 고칠 파일 | `chapter1/core/combat_tuning.gd`(선택 최상위 키 `grace`·`elites`·`extras`, 지금 `rhythm`과 같은 방식: 44~49행에서 지우고 맞춘 뒤 따로 검사), `chapter1/core/character_progression.gd`(선택 키 `sources.grade_bonus_bps`), 각 검사 파일 |
| 건드리지 않을 것 | `combat_tuning.json`·`character_progression.json`의 값(이 걸음은 키를 넣지 않는다), `chapter_core.gd` |
| 받아들이는 기준 | ① 지금 데이터로 `python tools/dev/run_all.py --quick` 통과 ② 골든 비교 불변 ③ 검증기 검사: 세 키가 없으면 통과, 모양이 틀린 키는 거부(검사 사례를 `test_rhythm.gd` 또는 새 `test_extras.gd`에) ④ `grade_bonus_bps`가 없으면 `xp_bounds()` 결과가 지금과 같다 |
| 사상 | 없음(다음 걸음의 바탕) |

---

## 4. 지시서 2 — W3+K3: 은총이 오는 박자와 제안 규칙

(차례가 W4·W5보다 앞이라 먼저 적는다. D12 G1: W3+K3 → J1 → J2.)

### 4.1 문제 [본 것: D11 0.3, W0 9판 `_local/w0/rhythm_9.txt`]

| 지표 | 지금 | 목표(D11 B1) [가설] |
|---|---|---|
| 첫 은총 | 4.6~6.3초 | 15초 안 |
| 첫 60초 안의 은총 | 4~5번 | 2~3번 |
| 은총 사이 최장 간격 | 55~128초 | 70초 이하, 보통 25~55초 |
| 4:30 뒤 은총 | 마지막 은총(우두머리 등장) 하나뿐인 판이 많다 | 2번(L11 + 마지막) |
| 큰 선택(진화) | 레벨 6, 약 60초 | 레벨 7 이상, 2:30~3:30. 출발 값 — D12 P7로 판정 |
| 마지막 은총 | 우두머리 등장 때. 보호 카드는 주력만 본다 | 우두머리 등장 때 **큰 카드가 반드시 있다** |

원인 셋: ① 문턱이 앞에 낮다(10·23·71) ② 지금 구성의 보호 카드가 주력 진화 길을 늘 넣어 레벨 6에 진화가 끝난다(`_protected_card`) ③ 처치 속도가 30초에 세 배로 뛴다(리듬 꺼짐). ③은 리듬(W1, 꺼짐)이 맡고, ①②가 이 묶음이다.

### 4.2 구조 — 무엇으로 박자를 고르게 하나

| # | 손잡이 | 하는 일 | 지금 정하는 것 | N1 뒤 확정 |
|---|---|---|---|---|
| A | **문턱(주 손잡이)** | 레벨마다 목표 시각(D11 B2 표)에 맞춰 경험치 문턱을 정한다 | 역산 방법과 도구(4.6) | 문턱 값 전부. 처치 속도는 힘(N1·J1)과 위협(J2)에 달렸다 |
| B | **진화 최소 레벨** | 진화 카드가 그 레벨의 제안부터 후보에 든다 | 키와 규칙 | 값(출발 7) |
| C | **마지막 큰 제안** | 레벨 12(마지막 문턱)의 제안은 장수가 많고 보호 카드가 큰 것 | 모양(4.4) | 장수가 힘에 주는 크기 |
| D | **은총 간격 바닥(선택)** | 앞 제안을 닫은 뒤 정한 틱이 지나기 전에는 다음 레벨이 와도 고르는 화면을 열지 않는다(경험치는 계속 쌓이고 레벨은 밀려 있다) | 키와 규칙, 기본 0(꺼짐) | 쓸지와 값. 강한 빌드가 빨리 레벨을 올려 앞에 몰리는 것을 문턱만으로 못 막을 때만 쓴다(7.2 D-5) |
| E | **고르는 도구** | 다시 뽑기·제외·보류 | 코어 함수와 기본 횟수 키 | 기본 횟수(7.1 U-3) |

A가 주 손잡이다. B·C는 판의 가운데와 끝에 "큰 순간"을 박는다. D는 안전장치다. E는 박자가 아니라 **선택의 질**을 고친다(같은 박자라도 고를 것이 없는 제안을 줄인다).

D를 기본으로 켜지 않는 까닭: 레벨이 올랐는데 고르는 화면이 안 열리면 "왜 안 주나"가 생긴다. 화면이 "은총 대기 n초"를 보여야 하고, 위급할 때 힘이 늦게 온다. 문턱으로 충분하면 쓰지 않는다. `[성]`을 늦추는 장치라 신중히 쓴다.

### 4.3 데이터 — `combat_tuning.json` 새 선택 블록 `grace`

```json
"grace": {
  "enabled": false,
  "evolve_min_level": 7,
  "final_offer": {"mode": "big", "cards": 4,
                  "protect_order": ["evolve_keystone", "evolve", "passive", "axis", "survival"]},
  "min_gap_ticks": 0,
  "tools": {"base_rerolls": 1, "base_banishes": 1, "base_holds": 0,
            "banish_kinds": ["unlock", "axis", "rank", "survival", "link", "pact"]},
  "survival_from_level": 8, "pact_from_level": 8, "link_slots": 2,
  "rarity": {"common": 7000, "rare": 2500, "legendary": 500, "kinds": ["axis", "link", "survival"]}
}
```

| 키 | 뜻 | 범위(검증기) | 이 묶음에서 |
|---|---|---|---|
| `enabled` | 거짓이면 블록 전체를 읽지 않는다 | bool | 꺼짐 |
| `evolve_min_level` | 진화 카드(`kind=="evolve"`)가 후보에 드는 첫 레벨. 0이면 지금과 같다 | 0~12 | 구현. 값 [N1 뒤 확정] |
| `final_offer.mode` | `"none"`(지금) / `"big"` | — | 구현 |
| `final_offer.cards` | 마지막 제안의 장수 | 3~4 | 구현. 3이냐 4냐는 7.1 U-4 |
| `final_offer.protect_order` | 마지막 제안의 보호 카드를 고르는 차례. `evolve_keystone`은 K5(트리) 전에는 후보가 없어 건너뛴다 | 아는 낱말만 | 구현 |
| `min_gap_ticks` | 4.2 D. 0이면 꺼짐 | 0~3600 | 구현, 기본 0 |
| `tools.base_rerolls` / `base_banishes` / `base_holds` | 판마다 기본으로 주는 횟수. 트리 `grace_rerolls`와 장비(K6)가 그 위에 더한다 | 0~3 | 구현. 값은 7.1 U-3 |
| `tools.banish_kinds` | 제외할 수 있는 카드 종류. **결정(`passive`)과 진화(`evolve`)는 넣지 않는다** — 빼면 진화 길이 막혀 이해할 수 없는 막힘이 된다(D12 B0.9 ③의 위험) | 아는 종류만 | 구현 |
| `survival_from_level` 등 넷 | 생존·위험·연계·희귀도 카드의 자리. K3b가 읽는다 | D11 B3 | **키만 검사.** 카드는 K3b |

`growth_quality*.json`에 넣지 않는 까닭은 D11 B3 (2)와 같다(키가 정확히 맞아야 읽히고, 두 파일 비교 검사가 있다) [본 것: D11·D12 인용, `run_growth.gd` 74~94행의 허용 키 셋].

### 4.4 규칙

**(1) 진화 최소 레벨.**
- 지금 구성(`_eligible_cards` 160~161행)과 새 구성(`_spell_cards` 345~348행) 둘 다, 제안하는 레벨(`_pending[0]`)이 `evolve_min_level`보다 낮으면 `evolve` 카드를 풀에 넣지 않는다.
- 보호 카드가 진화를 가리키는 경우(`_protected_card`의 `"evolve"`, `_toward_evolve_card`)도 같은 문턱을 따른다. 그 전 레벨에서는 진화 대신 그다음 모자란 카드(결정·축·짝)를 보호한다.
- 영구 트리의 "결정 없이 진화"(`evolve_without_passive`)도 이 문턱을 따른다(D11 B3 (2)).
- `[성]`: 판 가운데에 모양이 바뀌는 순간이 생긴다. `[쾌]`: 그 순간이 승 2의 첫 파도에 맞는다.

**(2) 마지막 큰 제안(레벨 12).**
- 판단 조건: 제안하는 레벨이 마지막 문턱의 레벨(`xp_thresholds.size()`)과 같을 때. 이 레벨은 지금 `_seal_grace`가 우두머리 등장 때 채운다 [본 것]. 리듬의 버티기가 켜지면 버티기 끝, 우두머리가 나오는 순간이다(D11 A4).
- 장수: `final_offer.cards`(3이면 지금과 같은 장수).
- 보호 카드: `protect_order`의 차례로 풀에서 첫 번째로 맞는 카드 하나. 지금 구성(꺼진 판)에서는 "아무 기술의 진화 → 결정 → 랭크"로 읽는다. 둘째 보호 카드는 없다(나머지는 가중 뽑기 — 무엇이 나올지 모름이 남는다 `[도]`).
- 이벤트: `grace_final_offer {level, cards}`(화면이 이 제안을 다른 제안과 다르게 보일 신호).
- `[성][쾌][도]`: 우두머리 앞의 마지막 판돈이다. 큰 카드 하나는 보장, 나머지는 운.

**(3) 다시 뽑기(있는 것을 넓힘).**
- 판의 횟수 = `tools.base_rerolls` + 트리 `grace_rerolls`(지금 길 그대로) + 장비(K6 뒤). 지금 `set_options`의 `grace_rerolls` 상한 3은 트리 몫의 상한으로 두고, 합은 0~6으로 묶는다.
- 기본 횟수는 `set_options`에 섞지 않는다. 새 함수 `growth.set_grace(rules)`로 넘긴다(트리 옵션과 은총 규칙을 섞으면 `snapshot().options`의 뜻이 바뀌어 골든이 흔들린다).
- 동작은 지금 `reroll()` 그대로(같은 규칙, 같은 `_rng`, 보호 카드 포함).

**(4) 제외(새).** `growth.banish(token, card_id) -> bool`, 코어 `chapter_core.banish_offer(token, card_id)`.
- 조건: 고르는 중(`mode=="choice"`), 살아 있는 제안의 토큰, 남은 횟수 > 0, 카드 종류가 `banish_kinds` 안.
- 효과: 그 카드 id를 이 판의 제외 목록(`_banished`)에 넣는다. 이후 `_eligible_cards`·`_spell_cards`가 그 id를 내지 않는다. 지금 제안에서 그 자리에 **한 장을 새로 뽑아** 채운다(지금 제안의 다른 카드와 제외 목록은 뽑지 않는다, 같은 `_rng`). 새로 뽑을 카드가 없으면 그 자리는 비고 장수가 준다(횟수는 쓴 것으로 센다 — 화면이 미리 "남은 후보 없음"을 보이면 이 경우가 안 생긴다. 읽기 함수가 `banish_would_refill`을 준다).
- 축 카드의 id는 `axis:<주문>:<축>`이다 [본 것: `run_growth.gd` 337행]. 제외하면 그 주문의 그 축이 이 판 내내 안 나온다. 결과가 크므로 화면이 "이번 판에서 이 축은 더 나오지 않음"을 적어야 한다(F3 카드 문법의 손해 줄).
- 보호 카드도 제외할 수 있다(보호는 보이게 할 뿐 고르게 하지 않는다, D12 B0.4). 다음 제안에서 보호 카드는 제외 목록을 뺀 풀에서 다시 정한다.
- 이벤트 `grace_banish {card_id, left}`. 스냅숏 `growth.banished`(켜진 판만).
- `[도]`: 판을 내 쪽으로 기울이는 손. `[성]`: 원하는 빌드로 가는 길을 좁혀 간다.

**(5) 보류(새, 기본 0).** `growth.hold(token, card_id) -> bool`.
- 효과: 그 카드는 이번에 고르지 않고 **다음 제안에 그대로 한 자리로 남는다**. 이번 제안에서는 남은 카드 가운데 하나를 고른다(보류만 하고 닫을 수 없다).
- 다음 제안의 장수는 같다(보류 카드 1 + 보호 카드 + 뽑기). 보류 카드가 그때 규칙상 못 나오는 카드(칸이 찼거나 축 상한)면 보류는 사라지고 횟수는 돌려주지 않는다 — 화면이 그 조건을 카드에 적는다.
- 기본 횟수 0(반지 장비 `grace_holds`만, D12 B5.3). 함수는 지금 넣고, 쓰는 길은 K6에서 연다.
- 이벤트 `grace_hold {card_id, left}`. 스냅숏 `growth.held`(켜진 판만).

**(6) 은총 간격 바닥(선택, 기본 꺼짐).**
- `combat_core.gd` `_refresh_mode` 219행의 `choice` 조건에 덮어쓸 수 있는 판단 하나(`_grace_ready()`, 기본 참)를 끼운다. `chapter_core`가 `min_gap_ticks > 0`일 때만 "앞 제안을 닫은 틱 + 간격"이 지났는지 본다.
- 기다리는 동안 밀린 레벨은 그대로 있고 판은 돈다. 첫 대기 틱에 이벤트 `grace_waiting {level, until_tick}`을 한 번 낸다.
- 간격이 지나면 다음 `step`에서 `choice`가 된다(코어의 한 틱 안에서 정해지므로 결정론 유지).
- 마지막 큰 제안(레벨 12)은 바닥을 무시한다(우두머리 앞의 선택이 밀리면 안 된다).

**(7) 읽기 함수(화면용, 새).** `chapter_core.grace_tools() -> Dictionary`:
`{enabled, rerolls_left, banishes_left, holds_left, held_card_id, banished:[id], final:bool, waiting_until:int, banish_would_refill:{card_id:bool}}`. 아무것도 뽑지 않는다(지금 `run_spells_view`의 원칙과 같음, 1116행 주석).

### 4.5 고칠 파일 / 건드리지 않을 것

| 고칠 파일 | 내용 |
|---|---|
| `chapter1/core/run_growth.gd` | `set_grace`, 진화 문턱, 마지막 제안, `banish`·`hold`, 제외 목록이 풀에서 빠짐, 스냅숏의 새 키(켜진 판만) |
| `chapter1/core/chapter_core.gd` | `start()`에서 `grace`를 읽어 `growth.set_grace`, `banish_offer`·`hold_offer`, `grace_tools()`, `_grace_ready()`, 이벤트 넷 |
| `chapter1/core/combat_core.gd` | `_refresh_mode`에 `_grace_ready()` 한 군데(기본 참) |
| `chapter1/core/combat_tuning.gd` | `grace` 블록 검사(G0에서 연 자리) |
| `chapter1/tests/test_growth.gd`(있음), `test_run_spells.gd`(있음) | 4.7의 사례 |
| `chapter1/tests/measure_rhythm.gd`, `sim_builds.gd` | `--grace-on`(메모리에서만 `grace.enabled`를 켬, 지금 `--rhythm-on`과 같은 방식) |

건드리지 않을 것: `growth_quality36·37.json`, `growth_catalog.gd`, `run_spells.json`의 값, `chapter_pilot.gd`(자동 조작은 다시 뽑기·제외를 쓰지 않는다), 화면 파일 전부(단추는 U-26), `xp_thresholds` 값(4.6에서 따로).

### 4.6 경험치 문턱 — 역산하는 방법 [N1 뒤 확정]

문턱 값은 지금 정하지 않는다. 처치 속도가 힘 곡선(N1·J1)과 위협(J2)에 달렸기 때문이다. 정하는 **방법**만 고정한다.

1. 목표 시각표 `T_L`(D11 B2: L2 0:10, L3 0:35, L4 0:55, L5 1:20, L6 1:50, L7 2:35, L8 3:15, L9 3:55, L10 4:40, L11 5:30, L12 우두머리 등장).
2. 기준 정책의 경험치 곡선 `X(t)`(판 시작부터 줍기까지 쌓인 경험치, 마녀 셋 × 시드의 중앙값). 기준 정책은 `synergy`(D12 P6)로 한다. 까닭: 박자는 "잘 고른 사람"의 판에서 고르게 와야 하고, 못 고른 사람은 조금 늦는 것이 맞다(`[성]`의 차이가 보인다).
3. 문턱 `thr_L = X(T_L)`을 10 단위로 둥글게. 마지막 값은 지금처럼 자연히 닿지 않게 크게(`_seal_grace`가 채운다).
4. 확인: `narrow`·`random` 정책이 4:30에 `synergy`보다 1레벨 넘게 뒤처지지 않는가. 넘으면 앞 문턱을 낮추지 않고 그 원인(힘의 차이)을 J1에 돌려보낸다.
5. 이 셈은 **도구로 만든다**(일회용 스크립트 금지, `CLAUDE.md` 점검 절차). `balance_sim.py`에 `--xp-fit=<시각표 JSON>`(정책의 `X(t)`로 문턱 목록을 내고, 그 문턱으로 다시 돌린 `grace_times` 요약을 같이 냄)을 더하는 것을 권고한다. 담당 `content-balance`. 시뮬레이터 값은 "모델의 답"이므로, 마지막 확인은 실제 코어의 `measure_rhythm.gd --rhythm-on --grace-on`으로 한다.

D11 B3 (1)의 첫 값 [12, 80, 125, 260, 460, 625, 1005, 1385, 1775, 2380, 9000]은 `balance_sim.py` 270행에 이미 들어 있다 [본 것]. 이것은 리듬 첫 값과 지금 구성의 처치 속도로 셈한 것이라 출발점으로만 쓴다.

### 4.7 받아들이는 기준과 재는 도구

| # | 기준 | 도구 |
|---|---|---|
| K3a-1 | 지금 데이터(블록 없음)와 `grace.enabled:false`에서 골든 비교 불변(기본·글 뺀 둘 다) | `golden_core.gd`, `golden_core.gd -- --textless` |
| K3a-2 | 전체 회귀 통과 | `python tools/dev/run_all.py` |
| K3a-3 | 단위: 레벨 6 제안에 진화 카드 없음(문턱 7), 레벨 7부터 있음. 보호 카드가 문턱 전에는 진화를 가리키지 않음 | `test_growth.gd`, `test_run_spells.gd` |
| K3a-4 | 단위: 레벨 12 제안의 장수가 `cards`, 보호 카드가 `protect_order`의 첫 맞는 카드. 지금 구성(꺼진 판)·새 구성 둘 다 | 같음 |
| K3a-5 | 단위: 제외한 id가 그 판의 이후 제안에 다시 나오지 않음. `passive`·`evolve`는 거부. 남은 횟수 0이면 거부. 같은 시드·같은 입력이면 같은 결과(결정론) | 같음 |
| K3a-6 | 단위: 보류한 카드가 다음 제안에 있음. 못 나오는 카드면 사라짐 | 같음 |
| K3a-7 | 단위: `min_gap_ticks`가 0이면 지금과 같음. 양수면 간격 전에는 `playing`, 지나면 `choice`, 레벨 12는 무시 | `test_chapter_run.gd` |
| K3a-8 | 메모리에서 켠 판(`--rhythm-on --grace-on`, 9판)에서 `events_dropped` 0, 오류 0 | `measure_rhythm.gd` |
| K3a-9(J1·J2에서) | D11 B1 표: 첫 은총 ≤15초, 60초 안 2~3번, 간격 25~55초(최장 ≤70), 진화 2:30~3:30, 4:30 뒤 2번 — **N1 뒤 확정한 문턱으로** 잰다. 못 미치면 못 미쳤다고 적는다 | `measure_rhythm.gd --rhythm-on --grace-on`, `sim_builds.gd --policies=synergy,narrow,random --no-equip` |

### 4.8 화면이 알아야 할 이벤트와 읽기 함수

| 이벤트 / 함수 | 필드 | 화면이 할 일(설계는 U-26) |
|---|---|---|
| `grace_reroll`(있음) | `left` | 다시 뽑은 세 장이 뒤집혀 들어옴 |
| `grace_banish`(새) | `card_id`, `left` | 빠지는 카드와 새 카드. 손해 줄("이번 판에서 더 나오지 않음") |
| `grace_hold`(새) | `card_id`, `left` | 보류 표시가 다음 제안까지 남음 |
| `grace_waiting`(새, 간격 바닥을 쓸 때만) | `level`, `until_tick` | 경험치 막대 옆 "대기 n초" |
| `grace_final_offer`(새) | `level`, `cards` | 마지막 제안을 다르게 보임(우두머리 앞) |
| `grace_tools()`(새, 읽기) | 4.4 (7) | 카드 오른쪽 단추 셋과 남은 횟수(기준작 점검표 2-4) |

### 4.9 사상

| 결정 | 키우는 것 |
|---|---|
| 박자를 판 끝까지 고르게 | `[성]`(성장이 끝까지 이어진다), `[보]`(긴 빈 구간이 줄어든다) |
| 진화를 가운데로 | `[성][쾌]` |
| 마지막 큰 제안 | `[성][도][쾌]` |
| 다시 뽑기 기본 1회 | `[도]`(지금 손에 든 세 장을 버리고 다시 거는 판돈) |
| 제외 | `[도][성]` |
| 보류 | `[도]` |
| 간격 바닥 | 키우는 것 없음(안전장치). 그래서 기본 꺼짐 |

### 4.10 K3b(뒤) — 이 지시서 밖

생존(`survival`)·위험(`pact`)·연계(`link`)·희귀도 굴림은 K3b로 나눈다. 까닭: 사용자 결정 H-5(위험 카드를 제1장에 넣을지), H-9(희귀도 굴림)가 아직이고, 연계 카드는 D12 B4.3 명세를 따로 읽어 지시서를 써야 한다. 지금은 `grace` 블록에 그 자리 키만 검사한다. `pact.greed`의 보상 단계 +1은 W5-b의 `reward_grade_up {cause:"pact"}` 원인 자리에 비워 둔다.

---

## 5. 지시서 1 — W4+W5: 정예가 지키는 자리, 판 안 부가 혜택, 보상 단계

### 5.0 도박과 보상의 감정이 생기는 자리 — 설계의 뼈대

사용자 원문(2026-11-19): "맵에서 특별 효과를 주는 장치나 장소가 있는데 엘리트몹이 거기를 지키고 있어. 얘를 처치해야 그 상자든 장치가 작동해서 추가 이로운 효과를 주는 설계도 괜찮을 것 같아."

이 장치가 재미를 내는 순간은 다섯이다. 구현은 이 다섯이 실제로 생기도록 짠다.

| # | 순간 | 무엇이 걸리나 | 무엇을 모르나 | 설계로 보장하는 것 | 사상 |
|---|---|---|---|---|---|
| ① | **보인다** — 마디가 시작될 때 12~16m 떨어진 곳에 잠긴 사당·상자와 지키는 정예가 나타난다 | 길을 돌아가는 시간 | 갈 만한가 | 사당은 **종류가 보인다**(무엇을 얻을지 알고 위험을 고른다, D11 C6). 상자는 **내용이 보이지 않는다**. 화면 밖이면 가장자리 표시 | `[도]` |
| ② | **언제 가나** — 파도 중에 가면 무리와 정예를 함께, 골에 가면 정예만 | 생명, 물약 | 다음 파도가 언제 오나(골의 길이는 화면에 보임) | 지키는 정예는 파도·골과 무관하게 자리를 지킨다. 자리는 **그 구역을 떠나면 사라진다** → 관문 앞에서 "지금 갈까, 버릴까" | `[도]` |
| ③ | **붙는다** — 4m 안에 들어가거나 정예를 맞히면 싸움이 시작된다 | 물러서기 어려워짐(정예는 6m 끈을 넘어 쫓지 않는다 — 물러설 길은 있다) | 잡는 데 몇 초 걸릴지 | 정예의 처치 시간 목표 4~8초(D2), 넘으면 위험이 커진다 | `[쾌]`(D2 E2 접사가 붙으면 더) |
| ④ | **풀린다** — 정예가 쓰러지는 순간 잠김이 풀리고 상자가 열린다 | — | **상자에서 무엇이 나오나** | 상자는 그 자리에서 열려 장비가 바닥에 흩어지고 등급 색 빛기둥이 선다(줍는 순간까지가 보상). 사당은 그 자리에 30초 머물러 닿으면 걸린다 | `[쾌][보][도]` |
| ⑤ | **쓴다** — 사당의 45초를 다음 파도에 쓴다 | 사당의 시간 | — | 사당 효과는 장비 위에 얹는 일시 층. 끝나기 전 남은 초가 보인다 | `[성][쾌]` |

**의식(이미 있음)은 다른 판돈이다.** 의식은 시작하면 무리가 몰리는 **고른 위험**이고, 보상이 그 자리의 큰 상자와 함께 **우두머리 전리품의 수**(보상 단계)로도 온다 — 뒤로 미룬 판돈이다. 지키는 자리는 보상 단계를 올리지 않는다(D11 C6, I-1 가). 두 갈래를 섞지 않아야 "지금 받는 것"과 "끝에 받는 것"이 갈린다.

**도박을 한 칸 더 키우는 안 — 상자의 등급 표시(7.1 U-1).** 지키는 상자를 둘(보통/귀한)로 나눠, 상자의 테 색으로 **최소 등급만** 보이고 내용은 숨긴다. 귀한 상자의 정예는 더 세다(체력 ×1.5 또는 접사 +1). "보이는 판돈이 클수록 지키는 것도 세다"가 한 화면에 선다. 첫 구현은 등급 하나로 넣되 데이터 꼴은 등급 여럿을 받게 한다(`tiers` 배열). 값 [N1 뒤 확정].

### 5.1 W4-a — 정예의 몸(D2 E1)

| 항목 | 내용 |
|---|---|
| 담당 | `gameplay-systems` |
| 근거 | D2 2절·5절·6.1(K1·K2), D2 9절 결정 1·2·4(디렉터 확인 필요, 7.2) |
| 고칠 파일 | `chapter1/core/chapter_core.gd`(`_spawn_elite(kind, point, zone, opts)` 새 함수: 구역 기본 값 위에 `elites.hp[zone]`·`damage_bps`·`speed_bps`·`radius_bps`·`xp[zone]`, `e.grade="elite"`. 구역별 생성 `per_zone`·`at_seal_bps`와 막혔을 때 다시 시도·`metrics.elites_skipped`. 드랍 `_maybe_drop_item`에 `grade=="elite"` 갈래: `loot.roll_class(_loot_rng,"elite",…)`를 **바닥에**, `source:"elite"`. `_enemy_role`이 `"elite"`를 돌려줌), `chapter1/core/combat_core.gd`(`_spawn`이 `grade` 키를 넣지 않음 — 일반 적 사전은 지금과 같아야 골든 불변. `grade`는 정예에만 만든다), `combat_tuning.gd`(`elites` 검사: D2 5.1 범위) |
| 데이터 꼴 | D2 5.1의 `"elites"` 그대로(`per_zone` [0,0,0]이면 꺼짐). 이 걸음에서는 `combat_tuning.json`에 **넣지 않거나** `per_zone:[0,0,0]`으로 넣는다 |
| 건드리지 않을 것 | `e.elite`의 뜻(수호자·우두머리). `_on_elite_defeated`. 트리의 `elite_damage_bps`(정예에 걸지 않는다, D2 결정 2). `loot.json`의 `elite` 표 값(80%→100%는 켤 때, D2 결정 4). `chapter_pilot.gd` |
| 이벤트 | `elite_spawned {target_id, kind, zone, affixes:[], guard_uid}`(지키는 정예면 `guard_uid`, 아니면 0), `death`의 `role`이 `"elite"` |
| 받아들이는 기준 | ① 꺼짐에서 골든 불변 ② 단위: 정예를 잡아도 `seals[zone].cleared`가 그대로, 드랍은 `elite` 표, 생존 상한에 막힌 정예가 다음 생성 시각에 나옴, 수호자 등장 뒤에는 생성 안 함(D2 6.1의 단위 검사 그대로) ③ 메모리에서 켠 판 9판: `elites_skipped` 0, 정예 처치 시간 중앙값 기록(목표 3~10초 판정은 J2 뒤) |
| 사상 | `[보]`(잡으면 나온다는 표적), `[쾌]`(큰 처치) |

### 5.2 W5-a — 지키는 자리(사용자 제안 C6)

**규칙** [가설, 값은 N1 뒤 확정]:

| 항목 | 규칙 |
|---|---|
| 수 | 판당 2곳: 1구역 사당 1(승 1), 2구역 상자 1(승 2). 기·전 A에는 두지 않는다(D11 C6) |
| 놓이는 때 | 그 구역의 봉인 진행이 `at_bps`에 닿을 때(1구역 3400 = 승 1의 `from_bps`, 2구역 0 = 구역에 들어선 때). 리듬과 무관하게 봉인 진행으로 정하므로 **리듬이 꺼진 판에서도 같은 규칙으로 돈다** |
| 자리 | 구역마다 후보 점 4개(데이터, 구역 중심 기준 상대 좌표). 놓일 때 주인공에서 12~16m인 후보 가운데 `_extras_rng`로 하나. 없으면 그 거리에 가장 가까운 후보. 후보는 의식 자리에서 6m 이상 떨어져야 한다(검증기) |
| 지키는 정예 | 놓일 때 그 자리에 `_spawn_elite`로 하나(`guard_uid`). 종류는 `elites.kinds[zone]`(1구역은 보행자만, D2 2.1) |
| 지킴 | 정예는 닻(자리)에서 `leash_m`(6m) 안을 벗어나지 않는다. 주인공이 `aggro_m`(4m) 안에 오거나 정예가 맞으면 싸움 상태. 싸움 상태에서도 닻 6m 밖으로는 쫓지 않고 끈 끝에 선다. 주인공이 12m 밖으로 멀어지고 6초 지나면 닻으로 돌아간다 |
| 재배치 | 지키는 정예는 `_cleanup`의 25m 재배치에서 뺀다(`combat_core.gd` 1242행 조건에 `guard_uid` 확인 하나) |
| 잠김 | 정예가 살아 있으면 잠김. 닿아도 아무 일 없음 |
| 풀림 | 정예가 죽는 틱에 `guard_unlocked`. **상자**: 그 자리에서 바로 열려 `guarded_chest` 표(뽑기 2, 마법 이상, 희귀 가중 상자의 두 배)를 굴려 **바닥에** 놓는다(`source:"chest"`, 이벤트에 `site_uid`) + 물약 1. **사당**: 그 자리에 `stay_ticks`(30초) 머문다. 주인공이 1.6m 안에 닿으면 걸린다(지속 `ticks × guarded_ticks_bps`, 45초) |
| 사라짐 | 주인공이 그 구역을 떠나면(관문을 지나 `zone`이 바뀌면) 잠긴 자리와 지키는 정예가 사라진다. 정예는 죽음이 아니라 제거(처치·드랍·봉인 처치 없음). 이벤트 `guard_expired {uid}`. 풀린 사당을 30초 안에 안 쓰면 `shrine_expired` |
| 정예 드랍 | W4-a의 정예 드랍(바닥)은 그대로. 자리의 보상은 그 위에 더한다 |
| 보상 단계 | 올리지 않는다 |
| 자동 조작 | 기본 정책은 가지 않는다. 측정 도구의 `--pilot-extras`만 간다(5.4) |

**사당의 일시 강화 층(같은 걸음에 넣는다 — 지키는 사당이 쓰기 때문).**
- `combat_core.gd`의 `_gear_stats`를 "장비 합 + 버프 합"으로 만든다. `_gear_totals()`(순수, 302행)는 장비만 그대로 둔다. 그래서 `preview_equip`·`compare_item`은 버프를 빼고 계산한다(D11 C3) [본 것: `_recompute_gear` 292~299행, `_gear_totals` 302~311행].
- 버프가 걸리고 끝날 때 `_recompute_gear()`를 다시 부른다.
- 종류와 키(D11 C4, 모두 지금 장비 능력치 키로 표현됨 [본 것: `loot.json` `limits`]):

| 종류 id | 효과(합하는 능력치) | 지속(틱) | 비고 |
|---|---|---|---|
| `luck` | 처치 드랍 확률 ×2, 희귀 ×2, 전설·고유 ×1.5 | 1800 | 능력치가 아니라 드랍 배율. `loot.roll_class`에 선택 인수 `mods`(`drop_bps`, `quality_bps`)를 더한다. 인수가 없으면 지금과 같은 뽑기(같은 난수 소비) — **`loot.gd`를 고치는 유일한 곳** |
| `power` | `cooldown_bps` +4300 | 1800 | |
| `swift` | `move_speed_bps` +2500, `dash_cooldown_bps` +4000 | 1800 | |
| `harvest` | `soul_gain_bps` +5000, `pickup_radius_cm` +300 | 2400 | 다음 은총을 당긴다. 화면 이름은 `narrative-lead`(이 낱말은 장비 글에서 금지어라 쓰지 않는다) |
| `ward` | `damage_reduction_bps` +3000, 걸릴 때 생명 25% 회복 | 1800 | 전 A 앞 |

- 겹침: 다른 종류는 함께, 같은 종류는 시간을 새로 채운다. 버프의 합이 장비 한도(`limits`)를 넘으면 한도에서 자른다.
- 지키는 사당의 종류는 `pool.seung1`(D11 C4: `luck`·`power`·`swift`)에서 `_extras_rng`로. **놓일 때 정해지고 보인다.**
- `resonance`(반응 피해)는 K2 뒤(D12 H-16). 지금 넣지 않는다.

**데이터 꼴** — `combat_tuning.json` 새 선택 블록 `extras`(D11 C4·C6을 한 꼴로 묶음):

```json
"extras": {
  "enabled": false,
  "guarded": {
    "sites": [
      {"id": "guard.z0", "zone": 0, "at_bps": 3400, "kind": "shrine",
       "points": [[12, 10], [-12, 10], [12, -12], [-12, -13]]},
      {"id": "guard.z1", "zone": 1, "at_bps": 0, "kind": "chest",
       "points": [[10, 12], [-10, -12], [12, -10], [-12, 12]]}
    ],
    "distance_m": [12, 16], "leash_m": 6.0, "aggro_m": 4.0, "return_after_ticks": 360,
    "tiers": [{"id": "plain", "weight": 100, "elite_hp_bps": 10000, "chest_class": "guarded_chest"}],
    "potions": 1
  },
  "shrines": {
    "touch_radius_m": 1.6, "stay_ticks": 1800, "guarded_ticks_bps": 15000,
    "kinds": {
      "luck":    {"ticks": 1800, "drop_bps": 20000, "quality_bps": {"rare": 20000, "legendary": 15000, "unique": 15000}},
      "power":   {"ticks": 1800, "stats": {"cooldown_bps": 4300}},
      "swift":   {"ticks": 1800, "stats": {"move_speed_bps": 2500, "dash_cooldown_bps": 4000}},
      "harvest": {"ticks": 2400, "stats": {"soul_gain_bps": 5000, "pickup_radius_cm": 300}},
      "ward":    {"ticks": 1800, "stats": {"damage_reduction_bps": 3000}, "heal_bps": 2500}},
    "pool": {"seung1": ["luck", "power", "swift"], "seung2": ["luck", "power", "harvest", "swift"], "jeon_a": ["ward", "power"]}
  },
  "chests": {"open_radius_m": 1.6, "orb_xp": 5, "class": "chest"},
  "unguarded": {"chests_per_beat": {"gi": 1, "seung1": 1, "seung2": 1, "jeon_a": 1},
                "shrines_per_beat": {"seung1": 0, "seung2": 1, "jeon_a": 1}},
  "rituals": {"reward_class": "ritual_chest", "grade_up": 1},
  "grade": {"max": 4, "boss_classes": ["boss_g1", "boss_g2", "boss_g3", "boss_g4"]}
}
```

- 후보 점은 구역 중심(`ZONES[zone]`) 기준이다. 구역 사각형은 중심 ±19m다 [본 것: `_clamp_point` 460~472행]. 검증기: 점이 ±17 안, 의식 자리에서 6m 이상.
- `unguarded`의 수는 D11 C2·C3에서 지키는 자리로 바꾼 몫(승 1 사당 1, 승 2 상자 1)을 뺀 것이다. W5-c가 읽는다.
- `tiers`가 7.1 U-1의 자리다. 지금은 한 줄.

**`loot.json`에 더할 표**(새 이름만. 지금 표는 바꾸지 않는다) [가설, D11 D2]:

| 표 | 뽑기 | 확정 | 품질 가중(마법·희귀·전설·고유) | 칸 가중 |
|---|---|---|---|---|
| `chest` | 1 | 드랍 100% | 8500·1200·200·100 | `carrier`와 같은 장신구 높은 가중 |
| `guarded_chest` | 2 | 드랍 100% | 7600·2400·0·0의 꼴(희귀를 `chest`의 두 배로) + 전설·고유는 `chest`와 같게 | 같음 |
| `ritual_chest` | 2 | 드랍 100% | 7000·2600·250·150 | 같음 |
| `boss_g1`~`boss_g4` | 3 / 4 / 5 / 6 | 희귀 1 / 1 / 2 / 2 | 지금 `boss`와 같음 | 지금 `boss`와 같음 |

`boss_by_grade` 키(D11 D3)를 `loot.gd`에 새로 가르치는 대신 **표 넷**으로 둔다. 까닭: `loot.gd` 검증이 표 모양만 보므로 고칠 곳이 없고 [본 것: 90~97행], `sim_loot.gd`가 같은 `roll_class`로 그대로 굴릴 수 있다. 지금 `boss` 표는 꺼진 판이 쓰므로 그대로 둔다.

**코어 이벤트**(화면·소리·측정이 읽는다):

| 이벤트 | 필드 | 언제 |
|---|---|---|
| `guard_spawned` | `uid`, `kind`("shrine"/"chest"), `shrine_kind`(사당만), `tier`, `position`, `elite_id` | 자리가 놓일 때(정예 `elite_spawned`의 `guard_uid`와 짝) |
| `guard_engaged` | `uid`, `elite_id` | 정예가 처음 싸움 상태가 될 때(소리 신호) |
| `guard_unlocked` | `uid`, `kind`, `shrine_kind` | 정예가 죽은 틱 |
| `chest_opened` | `uid`, `guarded`, `count` | 상자가 열린 틱(뒤에 `item_drop`이 따른다) |
| `shrine_taken` | `uid`, `kind`, `until_tick`, `guarded` | 사당이 걸린 틱 |
| `shrine_expired` | `uid` 또는 `kind` | 풀린 사당을 안 써서 사라질 때, 버프가 끝날 때(`buff_ended {kind}`로 나눠도 됨) |
| `guard_expired` | `uid` | 구역을 떠나 잠긴 자리가 사라질 때 |

**읽기 함수(새)**: `extras_view() -> {enabled, sites:[{uid, kind, shrine_kind, tier, position, state:"locked"|"open"|"taken"|"gone", elite_id}], buffs:[{kind, until_tick}]}`. 화면 가장자리 표시와 생명 구슬 옆 버프 아이콘이 읽는다.

**스냅숏**: `extras.enabled`일 때만 `snapshot().chapter.extras = {sites, buffs, next_site_index}`. 꺼졌으면 키 없음.

| 항목 | 내용 |
|---|---|
| 담당 | `gameplay-systems` |
| 고칠 파일 | `chapter_core.gd`(자리 상태·놓기·풀기·사라짐·버프 층의 판 쪽·`extras_view`·이벤트), `combat_core.gd`(`_step_enemies`에 지킴 분기 — 지키는 정예만 닻과 끈 규칙, 나머지 적은 지금 그대로 / `_cleanup` 조건 / `_gear_stats`에 버프 합), `loot.gd`(`roll_class`의 선택 인수 `mods` 하나), `combat_tuning.gd`(`extras` 검사), `loot.json`(새 표만) |
| 건드리지 않을 것 | `RITUALS` 상수와 `_step_rituals`(W5-b에서 보상 줄만), 의식의 E 키 입력, `chapter_pilot.gd`, 지금 드랍 표의 값, 화면 파일 |
| 받아들이는 기준 | ① 꺼짐(블록 없음 / `enabled:false`) 골든 불변 ② `loot.json`에 새 표를 더한 상태에서 골든 불변, `sim_loot.gd -- --runs=10000` 출력이 지금과 같음(새 표는 아무도 안 씀) ③ 단위: 놓이는 봉인 진행, 12~16m 후보 고르기, 정예가 끈 밖으로 안 나감, 맞으면 싸움, 정예가 25m 재배치를 안 받음, 정예가 살아 있으면 잠김, 죽는 틱에 풀림과 상자 내용(`guarded_chest` 표, 시드 고정), 사당 45초, 구역을 떠나면 사라짐(드랍·봉인 처치 없음), 버프가 `preview_equip`에 안 들어감, 같은 종류 겹침은 시간만 새로 ④ 메모리에서 켠 판(`--extras-on --pilot-extras`, 9판): 판당 지키는 자리 2곳 놓임 9/9, `events_dropped` 0, 오류 0 |
| 사상 | 5.0 표 |

### 5.3 W5-b — 보상 단계 Ⅰ~Ⅳ와 `run_xp_max`

**규칙**(D11 D3, 사용자 결정 I-1 권고 "고른 위험만 센다"를 따른다 — 결정 대기):

| 항목 | 규칙 |
|---|---|
| 상태 | `reward_grade` 1~4, 판 시작 1. `extras.enabled`일 때만 존재 |
| 오르는 원인 | 의식 완료 +1(`cause:"ritual"`, 둘), 운반자 처치 +1(`"carrier"`, W4-b 뒤), `pact.greed` +1(`"pact"`, K3b 뒤). 최대 Ⅳ. 정예·지키는 자리는 올리지 않는다 |
| 의식 보상(켰을 때만) | 지금 "희귀 1 가방 직행 + 물약"(1053~1054행)을 `ritual_chest` 표(뽑기 2) 가방 직행 + 물약 + 단계 +1로. 꺼졌을 때는 지금 줄 그대로 |
| 우두머리 전리품 | 켰을 때 `_maybe_drop_item`의 `"boss"`를 `grade.boss_classes[reward_grade-1]`로. 첫 처치 고유(`boss_first_kill`)는 그대로 앞에 |
| 영구 경험치 가산 | `character_progression.json` `sources.grade_bonus_bps`(선택 키, 길이 4). **승리한 판만**, 승리 경험치를 준 직후 그 판의 영구 경험치 합(`_progress.xp`)에 `bps[grade-1]/10000`을 곱한 몫을 새 출처 `"grade"`로 준다(`_grant_progress("grade", …)`, `progress_summary().sources.grade`) |
| `run_xp_max` | `xp_bounds()`의 `run_xp_max`를 `기본 합 × (10000 + max(grade_bonus_bps)) / 10000`(내림)으로. 기본 합은 지금 식(봉인 + 수호자 + 우두머리 + 승리). 키가 없으면 지금 값(1000)과 같다. 저장의 판 결과 검사(`chapter_profile.gd` 1369행)는 이 값을 그대로 쓰므로 고칠 곳이 없다 |
| 판 끝 재 | 단계 × 재(D11 D3)는 **이 걸음에 넣지 않는다.** 재 지급 길이 마을(W9)과 함께 정해진다(D11 E5 E-6) |
| 이벤트 | `reward_grade_up {grade, cause}`(전투 기록기가 이미 읽는 이름 [본 것: `run_record.gd` 169행]) |
| 읽기 함수 | `reward_state() -> {enabled, grade, max, causes:{ritual:[done,total], carrier:[done,total], pact:[done,total]}}`(D11 F2 ② 칸이 읽는다) |
| 스냅숏 | 켰을 때만 `chapter.reward_grade` |

**가산 값은 정하지 않는다.** D11 D3의 [0,1000,2000,3000]은 경제 시뮬레이터에서 레벨 20이 너무 빨랐고, E5 E-5의 권고는 [0,500,1000,1500]이다 [모델: D11 E5 인용]. 디렉터 결정(E-5) 전에는 데이터에 키를 넣지 않는다(그러면 `run_xp_max`는 1000 그대로).

| 항목 | 내용 |
|---|---|
| 담당 | `gameplay-systems`(코어·검증), `content-balance`(`sim_loot.gd`·`sim_economy.py` 맞춤) |
| 고칠 파일 | `chapter_core.gd`(`reward_grade`, `_step_rituals` 보상 줄의 켠 갈래, `_maybe_drop_item`의 우두머리 표 이름, `_progress_guardian`의 승리 뒤 가산, `reward_state()`), `character_progression.gd`(선택 키 검증, `xp_bounds`), `chapter1/tests/test_skill_tree.gd`(111행의 1000 확인을 "키 없음이면 1000, 키 있음이면 식대로"로), `test_chapter_run.gd`, `test_chapter_profile.gd`(가산이 있는 판 결과가 받아들여짐) |
| 건드리지 않을 것 | 저장 스키마(5에 `grade` 자리가 이미 있다 [본 것: `LAST_CORE`]), 앱의 판 결과 흐름, 퀘스트 경험치(W9) |
| 받아들이는 기준 | ① 꺼짐 골든 불변 ② 단위: 의식 완료가 단계를 올림(최대 4), 우두머리 전리품 수가 단계별 3/4/5/6, 진 판은 가산 없음, 가산을 받은 판 결과가 저장 검사를 통과하고 `run_xp_max`를 넘는 값은 거부 ③ `sim_loot.gd --grade=1..4`가 단계별 희귀·장신구·전설·고유 기대값을 냄(목표 대조는 D11 I-5 결정 뒤) |
| 사상 | `[보]`(해낸 일이 숫자로 끝에 돌아온다), `[도]`(의식을 지금 할까 — 끝의 판돈), `[성]`(영구 경험치) |

### 5.4 W5-c·W4-b — 지키지 않는 상자·사당, 운반자(뒤)

- **W5-c**: 5.2의 자리 코드를 `guard:none`으로 쓴다. 상자는 마디 시작에 후보 점에서, 닿으면 열린다(`chest` 표, 구슬 경험치 5). 지키지 않는 사당은 **골이 시작될 때**(`lull_started`, 리듬 켜진 판만) 주인공에서 8~12m, 다음 골까지 안 쓰면 사라진다(D11 C3). 리듬이 꺼진 판에서는 지키지 않는 사당이 없다(골이 없으므로). 사상 `[보]`(빈 구간을 메움), `[성]`.
- **W4-b**: D2 3절 그대로(운반자, 25초, 우선 표적 안 B는 디렉터 결정). 잡으면 단계 +1. 사상 `[도]`(쫓을까), `[보]`(장신구).
- 둘 다 이 문서에서는 차례만 정한다. 5.2·5.3이 들어오고 측정을 본 뒤 같은 형식으로 지시서를 낸다.

### 5.5 측정 도구에 더할 것(content-balance)

| 도구 | 더할 것 |
|---|---|
| `measure_rhythm.gd` | `--extras-on`(메모리에서 `extras.enabled`), `--pilot-extras`(도구 안에서만: 잠긴 자리가 20m 안이고 골이거나 리듬 꺼짐이면 그쪽으로 이동 방향을 덮어씀. 사당이 풀리면 닿으러 감. 의식은 `activate_ritual` 호출. 자동 조작 파일은 고치지 않음), 출력: 판당 놓인 자리 수, 지키는 정예 등장→처치 시간, 연 상자·쓴 사당, 단계 분포, 출처별 드랍 |
| `report_run_loot.gd` | `--extras-on --pilot-extras`, 출처별 집계(이미 `item_drop.source`가 있음) |
| `sim_loot.gd` | 새 표 `chest`·`guarded_chest`·`ritual_chest`·`boss_g1~4`, `--grade=1..4`, `--guard-open-rate=0..1`, `--ritual-rate`, 기본값은 지금 출력과 같게 |
| `sim_builds.gd` | `--extras-on --pilot-extras`(D11 C6 맞물림 목표: `synergy` 15판 중 14 이상, `random`의 승률 하락 ≤10%p) |
| `balance_sim.py` | 지키는 자리를 마디에 얹는 선택(`--set extras.guard=...`): 승 1·승 2에 정예 하나의 `T_single`과 사당 45초의 힘 배수. 모델 상수는 시험장 실측으로 맞춘다 |

### 5.6 [N1 뒤 확정] 값

| 값 | 지금 출발 | 무엇으로 정하나 |
|---|---|---|
| 지키는 정예 체력(구역 1·2) | D2 190 / 310 | 시험장의 처치 시간 4~8초(`synergy` 꼴), `narrow`·`random` 꼴의 처치 시간도 기록 |
| 사당 효과 크기 | D11 C4 | `R_synergy`가 45초 동안 0.3~0.6 오름(D11 C6) |
| 지키는 상자 내용 | 뽑기 2, 희귀 ×2 | `sim_loot` 단계 Ⅱ 판에서 QUALITY-TARGETS 4절 안(I-5) |
| 단계별 우두머리 전리품 수 | 3/4/5/6 | 같음 |
| 단계 경험치 가산 | 키 없음 | D11 E5 E-5 |
| 등급 둘(7.1 U-1)의 확률과 정예 강화 | — | 사용자 결정 뒤 시험장 |
| `leash_m`·`aggro_m` | 6 / 4 | 사람 플레이(정예를 끌어내 무리에서 떼는 것이 쉬운지) — [플레이] |

---

## 6. 시뮬레이터로 먼저 볼 것 / 실제 판으로 확인할 것

사용자 지침: 균형은 빠른 시뮬레이터로, 한 판 전체는 확인용. 시뮬레이터 값에는 "모델의 답", 시험장·한 판 값에는 조건과 판 수를 붙인다.

### 6.1 W3+K3

**시뮬레이터로 먼저**
1. `python tools/dev/balance_sim.py --preset spec1 --policies=synergy,narrow,random --seeds=10 --out=_local/k3/base.json` — 지금 첫 문턱의 `grace_times`(판마다 은총 시각, 1688행)로 B1 표를 정책별로 본다. 모델의 답.
2. 같은 명령에 `--set` 으로 `xp_thresholds`와 `evolve_min_level`(모델의 `cal`)을 바꿔 본다. 4.6의 `--xp-fit` 도구가 생기면 그것으로 문턱을 역산한다.
3. 간격 바닥을 쓸지: 바닥 없이 `synergy`의 첫 60초 은총이 3번 이하이고 정책 사이 레벨 차가 1 안이면 쓰지 않는다. 넘으면 모델에 바닥(`min_gap`)을 넣어 본다(모델 쪽에 이 키가 없으면 `content-balance`가 더한다).
4. 마지막 제안 4장의 효과: 우두머리 처치 시각과 승률 차를 모델로(정책 셋).

**실제 판으로 확인**
1. `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/measure_rhythm.gd -- --seeds=11,12,13 --primaries=ember,frost,arc --rhythm-on --grace-on --out=_local/k3/rhythm.json --bin=30` — 9판의 은총 시각과 `events_dropped`.
2. `sim_builds.gd --policies=synergy,narrow,random --no-equip --rhythm-on --grace-on` — 진화에 닿는 레벨(D11 G1 "진화에 닿음": `synergy`가 레벨 8 안 9판 중 8 이상).
3. 골든 둘(꺼짐 불변).
4. 화면: U-26 화면 재설계가 단추를 넣은 뒤 `hud_dump.gd`로 은총 화면 캡처. 이 묶음의 검수에서는 화면을 "보지 않음"으로 적는다.
5. [플레이] D11 G3 4·5번(강해졌다고 느낀 은총, 마지막 은총이 우두머리 앞의 선택으로 느껴졌나), 다시 뽑기·제외를 썼나.

### 6.2 W4+W5

**시뮬레이터로 먼저**
1. 지키는 정예 체력: `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_power.gd -- --witches=ember,frost,arc --beat=seung1 --single-mobs=0,10,30 --single-modes=pilot,stand --elite-hp=190 --builds=<synergy 꼴, narrow 꼴> --seeds=11,12,13 --out=_local/w5/guard_s1.json`(승 2는 `--beat=seung2 --elite-hp=310`). 처치 시간이 4~8초에 들어오는 체력을 찾는다. 시험장 실측(3시드). N1이 정한 빌드 꼴을 쓴다.
2. 드랍: `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_loot.gd -- --runs=10000 --grade=1`(…4), `--guard-open-rate=0.0`과 `1.0`. QUALITY-TARGETS 4절과 대조. 모델의 답이 아니라 표의 기대값이다(같은 `roll_class`).
3. 경제: `python tools/dev/sim_economy.py --preset spec --set ...` 로 단계 가산 [0,500,1000,1500]과 지키는 상자 표를 넣고 레벨 20 도달 판 수(G1 22~30판), 성장 없는 판(E-7). 모델의 답.
4. 위험의 크기: `balance_sim.py`에 지키는 자리 선택을 넣은 뒤(5.5) `synergy`·`random`의 승률 차.

**실제 판으로 확인**
1. 꺼짐 골든 불변(기본·글 뺀).
2. `measure_rhythm.gd -- --seeds=11,12,13 --primaries=ember,frost,arc --rhythm-on --extras-on --pilot-extras --out=_local/w5/rhythm.json` — 판당 자리 2곳, 정예 처치 시간, `events_dropped` 0, 판 길이 변화.
3. `report_run_loot.gd -- --seeds=11,12,13 --extras-on --pilot-extras` — 출처별 드랍, 사건에 묶인 몫(D11 G1: 장비 55% 이상, 희귀 이상 85% 이상 — **K6'에서 일반 적 드랍을 줄인 뒤** 판정).
4. 화면 캡처: `hud_dump.gd`로 잠긴 사당·정예 이름표·가장자리 표시·풀리는 순간(1280×720, 1920×1080). 화면 쪽 지시서가 나온 뒤.
5. 프레임: 1920×1080 3회, p95가 켜기 전보다 0.3ms 넘게 늘지 않음(D2 7절).
6. [플레이] 미평가: 잠긴 자리를 보고 일부러 갔나, 파도 중에 갔다가 후회했나, 상자가 열릴 때 무엇이 나올지 기대했나, 사당의 45초를 다음 파도에 맞춰 썼나, 의식을 보상 단계 때문에 했나(D11 G3 6·7·8).

---

## 7. 정할 것

### 7.1 사용자가 정할 것(권고와 함께)

| # | 정할 것 | 선택지 | 권고 | 키우는 것 |
|---|---|---|---|---|
| U-1 | 지키는 상자에 무엇이 보이나 | 가) 한 모양, 내용 모름(D11 C6) / 나) 상자 테 색으로 **최소 등급만** 보이고, 귀한 상자일수록 지키는 정예가 세다 / 다) 내용이 다 보인다 | **나.** 보이는 판돈과 숨은 내용이 함께 있어야 도박이 된다. 다는 도박을 없애고, 가는 "더 센 것을 지고 갈까"의 고민이 없다. 첫 구현은 등급 하나로 넣고 데이터에 자리만 둔다 | `[도][보]` |
| U-2 | 지키는 정예를 피해 다니면서 상자만 열 수 있나 | 가) 없음 — 정예를 잡아야만 열린다(사용자 원문 그대로) / 나) 오래 머물면 열리는 다른 길 | **가.** 사용자 원문이 "처치해야 작동"이다 | `[쾌][도]` |
| U-3 | 은총 다시 뽑기·제외의 기본 횟수 | 가) 0, 트리·장비로만 생김(D12 B5.3) / 나) 판마다 다시 뽑기 1·제외 1을 기본으로, 트리·장비가 늘림 | **나.** 지금 다시 뽑기는 코어에만 있고 화면 단추가 없어 아무도 본 적이 없다. 기본 1회씩 있어야 단추가 화면에 서고, 트리·장비의 "+1"이 성장으로 읽힌다. 기준작에서 본 단추 셋과 남은 횟수(점검표 2-4)의 자리 | `[도][성]` |
| U-4 | 레벨 12(우두머리 앞) 마지막 제안의 모양 | 가) 3장, 큰 카드 하나 보장 / 나) 4장, 큰 카드 하나 보장 | **나.** 마지막 선택이 다른 선택과 눈에 띄게 달라야 "판돈이 큰 마지막 한 번"이 된다. 힘의 크기는 N1 뒤 확정 | `[성][도][쾌]` |

같이 기다리는 사용자 결정(이 지시서의 값에 걸린다): D11 I-1(보상 단계를 올리는 조건, 권고 고른 위험만), D11 I-5(드랍 목표를 단계별로 나눌지, 권고 나눈다), D12 H-5(위험 카드), H-8(은총 영구 금지), H-9(희귀도 굴림), H-27·D11 E5(경제).

### 7.2 디렉터가 정할 것

| # | 정할 것 | 권고 |
|---|---|---|
| D-1 | W4·W5의 **코드**를 D12 G2 차례(J2 뒤)보다 앞당겨 꺼진 채 넣을지 | 넣는다. 모양은 힘의 크기와 무관하고 골든을 건드리지 않는다. 값과 켜기는 J2·K6' 그대로 |
| D-2 | 차례: G0 → K3a ∥ W4-a → W5-a → W5-b → (W5-c, W4-b) | 이대로. K3a와 W4-a는 고치는 파일이 대부분 다르다(`run_growth.gd` / `chapter_core.gd`의 생성·드랍). 둘 다 `combat_tuning.gd`를 고치므로 G0을 먼저 끝낸다 |
| D-3 | D2 결정 1·2·4(E1부터, 트리 수호자 보정을 정예에 걸지 않음, 정예 드랍 100%) | D2 권고대로. 100%는 켤 때 `loot.json` 값과 함께 |
| D-4 | 새 난수 흐름 `_extras_rng` | 둔다(2절 2) |
| D-5 | 은총 간격 바닥 | 키만 넣고 기본 0. 6.1-3의 조건을 넘을 때만 켠다 |
| D-6 | K3를 K3a(박자·도구)와 K3b(생존·위험·연계·희귀도)로 나눔 | 나눈다(4.10) |
| D-7 | 제외 금지 종류(`passive`·`evolve`) | 금지 |
| D-8 | 단계 가산은 이긴 판만 | 이긴 판만(진 판에 단계 가산이 붙으면 의식만 하고 지는 판이 득이 된다) |
| D-9 | 판 끝 재(단계 × 재)를 W9로 미룸 | 미룬다(D11 E5 E-6과 함께) |
| D-10 | 지키는 정예 이름표의 HUD 가림 예외(D2 결정 5) | D2의 질문 그대로. 화면 재설계에서 |

---

## 8. 확인하지 못한 것

- **N1 결과.** 아직 없다. 지키는 정예 체력·사당 크기·문턱 값·마지막 제안의 힘이 모두 여기에 걸린다. N0는 "3.1 첫 값으로는 시너지 > 하나만 > 막 찍기가 서지 않는다"였다(`_local/tools/n0/REPORT.txt` 1절, KS-3 이전 코어, 3시드). N1이 구조를 다시 짜라고 하면 K3a의 보호 카드 차례(`protect_order`)와 진화 문턱의 의미가 바뀔 수 있다.
- **W1b의 포위 압력·격앙이 코어에 들어왔는지.** `chapter_core.gd`에서 `pressure`·`enrage`가 0건이다. 다른 파일에 있을 수 있다. 이 지시서와 직접 얽히지는 않는다.
- 새 드랍 표를 `loot.json`에 더했을 때 골든이 그대로인지 — 골든은 스냅숏 해시라 그럴 것으로 보지만 돌려 보지 않았다. 5.2 받아들이는 기준 ②로 구현 담당이 확인한다.
- `loot.roll_class`에 선택 인수를 더했을 때 같은 난수 소비가 지켜지는지(구현 담당이 시드 비교로 확인).
- 지키는 정예의 끈 규칙이 밀집 조향(`_approach_crowd`)과 부딪히는지 — 그 함수를 읽지 않았다.
- 원거리 정예가 지키면 I0(기본기가 원거리를 먼저 겨눔, KS-3)가 멀리서 정예를 끌어내는지 — 1구역은 보행자만이라 승 1은 해당 없음, 승 2는 [미확인].
- 경제 시뮬레이터의 상수가 이 지시서의 표와 맞는지(D11 E5: 상수 159개 중 76개가 가정).
- 기준작의 다시 뽑기·제외 단추는 녹화에서 "그렇게 보인다"는 추정이다(사크라타 루프 74행 [추정]).
- 사람의 재미: 5.0의 다섯 순간이 실제로 생기는지, 정예를 끌어내기가 쉬운지, 사당 45초가 느껴지는지, 마지막 큰 제안이 큰 순간으로 읽히는지 — 모두 미평가.
