# A-element-kit-screen — 번개 키트를 켠 판을 화면이 읽게 한다: 쌓이고, 박히고, 모여서 터진다 (2026-11-25, 0판)

아트 책임자(art-lead)가 썼다. 구현하지 않았고, 이 문서 말고는 아무 파일도 고치지 않았다. Godot는 돌리지 않았고 화면도 보지 않았다. 지금 앱으로는 키트를 켤 수 없어서다(1.3). 모든 내용은 코드를 읽고 쓴 것이다.

받는 사용자 지시(원문, `docs/DIRECTIVES-LEDGER.ko.md`):
- U-127: "스킬은 권고안대로 진행해줘, 2번 구성이 원하는 방향이야. 카드를 여는쪽으로 하고, 수치는 나중에 확장 가능한 구조로 만들어줘."
- U-124: "… 이제 부터는 스킬업 되면서 팡팡 터지는 재미를 느끼고 … 그 안에는 스킬의 발전과 여기에는 카드뽑기라는 운도 있지만 이렇게 되야 해"
- U-126 ④: 한 판에서는 자기 원소만 쓰고, 원소마다 스킬과 카드를 넉넉히 둔다.
- 바탕 사상(CLAUDE.md, 2026-11-19): "한 스킬이 다른 스킬에 영향을 주는 구조도 있어야 하고 … 섹시, 쾌감, 도박, 보상, 성장"

받는 명세 절: `docs/specs/D-element-trees-20261125.ko.md`의 3.3(번개), 4.1·4.4·4.5(카드), 5.1·5.3(영구 트리), 7.2·16.5(이벤트), 9.4(화면이 알아야 할 것), 14절(큰 적 위의 겹은 보인다), 19절 ET-D15·ET-D16(화면이 먼저다). 켜는 장부 `element_kit` 줄의 ③ 화면.

표기: **[본 것]** 코드를 읽어 확인함 · **[가설]** 이 지시서의 제안 · 다섯 요소 `[섹]` 섹시 · `[쾌]` 쾌감 · `[도]` 도박 · `[보]` 보상 · `[성]` 성장.

---

## 0. 목표 한 줄

**사용자가 번개 키트를 켠 판을 칠 때, 정지 화면 한 장을 0.5초만 보고도 다음을 말할 수 있어야 한다: 어느 큰 적에 감전이 얼마나 쌓였나, 피뢰침이 어디 박혔나, 방금 번개가 어디로 모여 터졌나.** "쌓고 터뜨린다"가 글 없이 모양만으로 읽혀야 한다. 효과를 더하되 주인공 위치, 적의 공격 전조, 우두머리 화면(`A-boss-finale-screen`)의 표시를 덮지 않는다.

19절 ET-D15가 이 화면에 숙제를 하나 얹었다. 값으로 보면 "호위가 도체가 되어 번개를 되돌린다"는 그림이 서지 않았고, 지금 줄기는 주로 큰 적 제 몸의 감전에서 나온다. 사용자가 그 둘을 보고 설계의 그림을 고를 수 있어야 한다. 그래서 **도체에서 오는 줄기와 제 겹에서 나오는 줄기가 화면에서 분명히 갈려야 한다.**

### 0.1 켠 판에서 반드시 읽혀야 하는 여덟

| # | 읽혀야 하는 것 | 받는 것 | 키우는 요소 |
|---|---|---|---|
| K1 | **큰 적에 감전이 쌓인다**: 몇 겹이고 다 찼는가. 큰 적과 보통 적은 같은 꼴이 아니다 | `status_stacked`·`status_full`, 읽기 전용 `enemies[id].kst` | `[쾌]` 쌓이는 것이 보여야 터지는 맛이 있다 · `[성]` 순서를 아는 것이 힘이다(ET3) |
| K2 | **어느 졸개가 도체인가**: 감전된 보통 적 | 같음 | `[섹]` 감전이 무리에 번진 화면 · `[쾌]` 무리가 많을수록 세진다(ET5) |
| K3 | **피뢰침이 어디 박혔나**, 언제 빠지나, 우두머리 쉼에 떨어짐 | `rod_planted`·`rod_dropped`, `enemies[id].rod_until`, `kit_view().rods` | `[성]` 깔아 두는 스킬이 무슨 일을 하는지 보인다 · `[쾌]` |
| K4 | **오버로드가 터지는 순간**: 번개가 큰 적으로 모인다. 도체 줄기(졸개 → 큰 적)와 제 겹 줄기(큰 적 몸에서 터짐)가 갈린다 | `bolt_returned{self}`·`detonated` | `[쾌]` 이 키트의 얼굴(명세 7.2 "이 명세의 얼굴") · `[섹]` |
| K5 | **새 스킬 둘이 언제 열리고 언제 나가나**: 스킬 칸 셋(주력·라이트닝 로드·오버로드)과 재사용 시간 | `skill_gate_opened`, `kit_view().skills`·`next_rod`·`next_overload` | `[성]` "아슬아슬할 때 스킬이 온다"(U-124) · `[보]` |
| K6 | **카드의 새 종류**: 변형·생존·채움·룬을 한눈에 가르고, 택일 짝과 요구 스킬을 보인다 | 제안 카드의 `kind`·`requires`·`excludes` [본 것: `run_growth.gd` 1224~1233행] | `[도]` 무엇이 왔나, 무엇을 버리나 · `[성]` 틀린 선택이 있다(ET6) |
| K7 | **트리의 마디가 어떤 카드를 여는가**, 그리고 남는 점수 | `element_trees.json` 마디의 `kind:"card"`·`opens` | `[성]` "카드를 여는 쪽"(U-127) · `[도]` 연 카드도 운으로 온다 |
| K8 | (덧붙임) 썬더스톰(진화), 정전기 막, 되튐 | `kit_storm`·`kit_shell`·`chain_rebound` | `[쾌]` 진화의 한 방 |

다섯 요소 가운데 어느 것도 키우지 않는 것은 이번에 넣지 않는다. 카드 운의 바닥(`offer_floor`, `evolve_floor_opened`)은 명세 16.5와 D-run-curve 4.3 규칙 4에 따라 **화면에 보이지 않는다**. 측정에만 쓴다.

---

## 1. 지금 화면이 하는 것과 못 하는 것 [본 것]

### 1.1 키트 이벤트를 받는 화면이 하나도 없다

`chapter1/view`와 `chapter1/app`에서 `status_stacked`, `bolt_returned`, `rod_planted`, `kit_view`를 찾았는데 하나도 나오지 않았다. 찾을 수 있는 곳은 검사(`test_element_kit.gd`)와 측정(`measure_rhythm.gd`)뿐이다. 그러니 켠 판의 화면은 이렇게 될 것으로 읽힌다(보지는 않았다):

| 자리 | 지금 코드가 하는 것 | 켠 판에서 보일 것 |
|---|---|---|
| 적 | 감전·피뢰침 표시가 없다. 오래 남는 적 위 상태 표시는 `run_spells`에도 없다(`ring_spell_fx.gd`는 터뜨림 순간에 모양만 잠깐 띄운다) | 쌓임이 보이지 않는다 |
| 번개 | 체인은 `cast` 이벤트의 `segments`를 `arc_links`(상한 64)로 그린다(`chapter_effects.gd` 1160~1182행). 오버로드·로드·불꽃은 `cast`를 내지 않는다(`_kit_context`가 이벤트를 만들지 않음, `chapter_core.gd` 3569행) | 오버로드 줄기가 선으로 그려지지 않는다. `_damage_enemy`를 거치므로 맞음 표시와 피해 숫자만 겹쳐 뜰 수 있다(확인하지 않음) |
| 스킬 칸 | `combat_bar.gd` `SKILLS`가 화염·냉기·번개 주력 셋으로 굳어 있다(9행). 랭크는 `growth.ranks`에서, 재사용은 `run._next_cast`에서 읽는다(101~114행) | 번개 마녀는 셋째 칸만 켜지고 첫째·둘째 칸은 흐려진다. 로드와 오버로드 칸은 없다 |
| 카드 화면 | 어댑터 `growth_choice_contract.gd`의 `match kind_core`(87~99행)가 unlock·rank·axis·passive·evolve만 안다. `variant`·`survival`·`filler`·`rune`은 기본값(`kind:"new"`, "새로" 꼬리표)으로 떨어진다. 이름은 `Loc.t("kit.card.A12")`인데 번역 문자열이 없으므로 **키 글자 그대로** 뜬다(`loc.gd` 139행). 설명은 `chapter_hud.gd` `_card_description__cloister`(249행)를 거쳐 `after`가 없는 카드에도 **"기술 기본 피해 0"**이라는 줄이 붙는다 | 깨지지는 않을 것으로 읽힌다. 다만 "kit.card.A19 / 기술 기본 피해 0"이 세 장 나란히 뜬다. 택일·요구는 보이지 않는다 |
| 판 아래 띠(가진 스킬) | `_owned`가 `BASE_SKILLS`와 `run_spells_view`에서만 고른다(186~202행) | 로드와 오버로드가 띠에 없다 |
| 트리 판 | `skill_tree_panel.gd` `COL_W`가 4칸(51행), `BRANCH_COLORS`가 frost·brass뿐(48행)이다. 번개 트리는 갈래가 다섯이고 색이 `arc`다(`element_trees.json`). 마디 설명은 `tree_text.gd` → `SkillTree.describe_keys`(`skill_tree.gd` 670행)가 `nodes[id].ranks`를 읽는데 `card` 마디에는 `ranks`가 없다 | 카드 마디를 고르면 설명을 그리다 오류가 날 수 있다(확인하지 않음). 다섯째 갈래가 넷째 칸 폭을 빌려 쓴다. 다만 **저장이 꺼진 시험 판에서는 트리 판이 열리지 않는다**(`_open_skill_tree`는 프로필을 읽음, `chapter_one.gd` 634행). 사용자가 쳐 볼 길에는 걸리지 않는다 |

### 1.2 코어가 주는 것 [본 것: `chapter_core.gd` 3586~3928행, `combat_core.gd` 1303행, `run_growth.gd` 1224~1283·1386·1455행]

| 이벤트 | 필드 | 위치(`position`) | 알아 둘 것 |
|---|---|---|---|
| `status_stacked` | `target_id, element, stacks, max, big` | 그 적 | 보통 적은 겹이 바뀔 때만 내고, 같은 적에 15틱(0.25초)에 한 번까지다. 큰 적은 늘 낸다. 한 틱에 32개까지. **겹이 사라질 때는 이벤트가 없다**. 지속 시간이 다 되어 꺼지는 것은 상태(`kst.until`)로만 알 수 있다 |
| `status_full` | `target_id, element, kind:"big_full"` | 그 적 | 큰 적의 겹이 상한에 처음 닿을 때 |
| `bolt_returned` | `from_id, to_id, damage_raw, self` (+ `spark:true` 죽음 불꽃, + `merged:n` 넘친 묶음) | **받는 적**(`to_id`) | 한 틱에 16개까지 내고, 넘친 것은 그 틱 끝에 `from_id 0, to_id 0, merged n`을 주인공 자리에 하나로 낸다. `self:true`면 `from_id == to_id`다. 불꽃의 `from_id`는 방금 죽은 적이라 그 틱에 `enemies`에 남아 있지 않을 수 있다 |
| `detonated` | `skill_id, target_id, element, stacks, damage_raw, big, kill` | 그 적 | 오버로드 한 번에 **받은 적마다 하나**씩 나온다. `stacks`는 그 적이 받은 줄기 수, `damage_raw`는 그 합이다 |
| `rod_planted` | `target_id, until` | 그 적 | 동시에 1개, 카드 A19면 2개 |
| `rod_dropped` | `target_id, reason` (`dead`·`break`·`time`·`replaced`) | 그 적 | `break` = 우두머리 쉼이 시작됨(ET16) |
| `chain_rebound` | `target_id, skill_id, cast_uid` | 그 적 | 홀로 선 큰 적에게 체인이 되튐 |
| `kit_storm` | `targets[], skill_id` | **주인공** | 표적의 자리는 `enemies[id].position`에서 읽는다 |
| `kit_shell` | `until, reduce_bps` | 주인공 | 정전기 막(A26) |
| `kit_card_taken` | `card_id, kind, element` | 주인공 | |
| `skill_gate_opened` | `id, card_id, gate` (`S1` 오버로드, `S2` 로드) | 주인공 | 열림 카드를 고른 그 틱 |
| 읽기 전용 `run.kit_view()` | `{on, element, skills{id:{rank, role}}, rods[], taken[], shell_until, next_overload, next_rod}` | — | 꺼진 판은 `{on:false}`다. **재사용 길이, 썬더스톰의 다음 틱, 피뢰침 둘레 반지름, 큰 적 겹 상한, 오버로드 사거리가 없다** → 9절 ① |
| 읽기 전용 적 상태 | `enemies[id].kst {n, until}`, `enemies[id].rod_until`, `elite` | — | 화면은 겹을 이벤트가 아니라 **이 상태를 매 프레임 읽어 그린다**. 이벤트는 반짝임에만 쓴다 |
| 제안 카드 | `{id, kind, skill_id, weight, title_key:"kit.card.<id>", answers, rank?, requires?, excludes?}` (채움은 `effect`) | — | 트리가 연 카드인지(`open`) 알려 주는 필드가 없다 → 9절 ② |

### 1.3 켠 판을 띄우는 길

- 앱 `_apply_trial`(`chapter_one.gd` 383~432행)이 아는 이름은 `spells, rhythm, descent, pace, grace, elites, boss_finale`이다. **`element_kit`은 없다.** 모르는 이름은 경고만 하고 버린다(394행).
- 검사·측정 쪽에는 같은 일이 이미 있다. `chapter1/tests/support/kit_docs.gd` `enable_kit_problem(run, tree, elements)`가 출하 파일의 사본에 `enabled:true`, `enabled_elements:["arc"]`를 넣어 `run.set_element_kit()`에 주고, `run.set_kit_open("none"|"all"|[카드 id…])`로 트리가 연 카드를 정한다. 측정의 켠 경로는 `enable_kit_rhythm_problem(run, tree, with_boss_finale)`이다(리듬·오프닝·성장 속도·우두머리 국면 + 키트).
- **트리를 다 연 상태로 띄우는 데 코어 일은 필요 없다.** `set_element_kit`과 `set_kit_open`은 이미 코어의 공개 함수다. 앱이 부르기만 하면 된다(4절).
- 우두머리 바로가기 `--chapter1-boss-now`가 있다(`chapter_one.gd` 164행 → `debug_skip_to_boss`). 이 함수는 건너뛰는 동안 뜨는 패에서 카드를 점수로 고른다(`chapter_core.gd` 1231~1244행). 주력 랭크 90, 룬 80(`skill_id`가 주력이라서), 열림 65를 주고, 변형·생존은 10이다. 키트 판에서도 로드·오버로드가 열릴 가능성은 높지만, 문(`after_picks`)에 닿을 만큼 패가 뜨는지는 확인하지 않았다 → 9절 ③.
- 앱의 자동 조작(`chapter_pilot.gd` 20~23행)도 같은 점수표를 쓴다. 그래서 캡처 판은 측정의 `link` 정책과 다른 순서로 카드를 고른다. 변형은 거의 고르지 않는다. 캡처는 화면 판독용이고 값은 보지 않으므로 받아들인다.

---

## 2. 이벤트 → 화면 표

모든 표현은 이벤트와 읽기 전용 상태만 쓴다(`run.enemies`의 `kst`·`rod_until`·`elite`·`position`, `run.kit_view()`, `run.tick`, 우두머리 판의 `run.boss_finale_view()`). 코어 값을 바꾸지 않는다. **새 그림 에셋 없이** 셰이더 도형과 선으로 먼저 한다.

**색의 규칙(한 색에 한 뜻, `palette.gd`)**
- 감전·피뢰침·줄기 = `Palette.ARC`(b9caff) 하나다. 가득 참과 줄기가 닿는 끝만 흰빛 쪽으로 밝힌다(셰이더 안에서 ARC를 1.4배, 새 토큰은 없음).
- 빈 겹 칸 = `BRASS_DIM`을 알파 0.35로.
- 전조의 붉은색(`TELE_LINE_RGB`)과 `THREAT`는 **쓰지 않는다**. 리넨(`LINEN`)은 우두머리 화면에서 "막힘·칠 수 없음"의 색이니 쓰지 않는다.
- 새 팔레트 토큰은 만들지 않는다.

**모양의 규칙(흑백에서도 갈리도록)**
- 감전 = **톱니(지그재그)**, 피뢰침 = **세로 못**, 줄기 = **꺾인 선**.
- 냉기의 결정·고리 주문의 원과 섞이지 않게 한다. 바닥에 넓게 칠하는 면(채움)은 쓰지 않는다. 바닥 표시는 선만 쓰고 알파는 0.35 이하로 둔다.
- 우두머리 화면의 꼴(붉은 점선 원, 리넨 고리, 그림자 원)과 겹치지 않게 한다.

| 받는 것 | 무엇을 어디에, 얼마나 | 담당 | 고칠 파일 |
|---|---|---|---|
| **보통 적의 감전**(상태 `kst.n ≥ 1`, `tick < kst.until`, `elite` 거짓) | 발밑에 **톱니 고리 조각**을 그린다. 반지름 0.45m 원 위에 짧은 지그재그 셋, 선 굵기 0.04m, ARC, 알파 0.55. 0.6초 주기로 아주 약하게 깜빡인다(알파 0.45~0.6). 꺼지기 0.5초 전부터 알파가 0.25로 내려간다(곧 도체가 아님). **상한 48개**: 오버로드 사거리 안(9절 ①의 `reach_cm`, 들어오기 전에는 주인공에서 가까운 순)부터 그린다. 몸 위에는 아무것도 띄우지 않는다. 무리 위가 아이콘으로 덮이지 않게 하기 위해서다 | vfx-feel | 새 `view/fx/element_kit_fx.gd`, 새 `view/fx/element_kit_mark.gdshader` |
| `status_stacked{big:false}` | 처음 붙는 순간에만 발밑 톱니가 0.12초 동안 반지름 0.3 → 0.45m로 튀어나온다. 한 프레임에 6개까지, 나머지는 바로 정상 꼴 | vfx-feel | 같음 |
| **큰 적의 겹**(상태, `elite` 참) | 머리 위(몸 높이 + 0.4m, 화면을 향함)에 **조각 고리**를 둔다. 반지름 0.55m, 조각 수 = 상한(10, 카드 A18이면 15. 9절 ①의 `cap_big`, 들어오기 전에는 마지막 `status_stacked.max`). 찬 조각은 ARC, 빈 조각은 `BRASS_DIM` 0.35. 조각 사이 틈은 6°. **숫자는 쓰지 않는다**(조각 수가 숫자다). 우두머리 체력 막대 쪽에는 겹을 다시 그리지 않는다(한 곳에만) | vfx-feel | 같음 |
| `status_stacked{big:true}` | 새로 찬 조각만 0.15초 밝아진다. 고리 전체를 흔들지 않는다 | vfx-feel | 같음 |
| `status_full` | 고리가 0.25초 동안 흰빛 쪽으로 한 번 밝아진다. 이어서 **바깥에 가는 둘째 고리**(반지름 +0.08m, 선만)가 겹이 줄 때까지 남는다. 뜻은 "곧 터진다". 카메라는 쓰지 않는다 | vfx-feel | 같음 |
| **피뢰침**(`kit_view().rods` + `enemies[id].rod_until`) | 그 적 머리 위로 **세로 못** 하나를 세운다. 길이 1.4m, 굵기 0.06m, 꼭대기에 작은 마름모, ARC. 큰 적이면 겹 고리를 꿰뚫는 자리에 둔다. 남은 시간은 못의 길이로 보인다(`rod_until − tick`에 비례해 위에서부터 짧아짐, 바닥 0.4m까지). 발밑에는 **둘레 반지름**(9절 ①의 `rod_radius_cm`: 6m, 랭크 3이면 8m)에 짧은 눈금 12개를 원으로 놓는다(선만, 알파 0.22). 점선 원이 아니라 눈금이다. 우두머리의 붉은 점선 원과 모양으로 갈리게 하려는 것이다 | vfx-feel | 같음 |
| `rod_planted` | 못이 3m 위에서 0.12초 만에 내리꽂힌다. 그 자리 발밑 눈금 원이 0.2초 동안 반지름 70% → 100%로 퍼진다 | vfx-feel | 같음 |
| `rod_dropped{reason}` | `break`·`time`·`replaced`: 못이 0.3초 동안 알파가 줄며 0.5m 기울어 사라진다. `dead`: 0.15초 만에 사라진다(죽음 표시가 따로 있으므로). 우두머리 쉼(`break`)에는 우두머리 화면의 흐린 몸·점선 원이 그 자리를 쓴다. 이 키트는 우두머리 자리에 아무것도 남기지 않는다 | vfx-feel | 같음 |
| **`bolt_returned{self:false}`**(도체 줄기) | **졸개에서 큰 적으로 꽂히는 꺾인 선**이다. 출발 = `from_id` 몸 높이 1.0m, 끝 = `to_id` 가슴 높이. 마디 5개로 꺾고 굵기 0.05m. 출발 쪽은 ARC 알파 0.6, 끝 쪽으로 갈수록 밝아져 닿는 자리에서 흰빛 쪽으로 간다. 수명 0.18초. **같은 틱에 온 줄기는 `i × 0.012초`씩 늦춰 띄워** 한 다발이 차례로 모이는 것처럼 보이게 한다(12줄기면 0.13초). 체인(주인공에서 뻗음, `arc_links`)과는 **방향**으로 갈린다. 체인은 주인공에서 나가고, 줄기는 큰 적으로 들어간다. 선은 이 파일의 따로 된 `ImmediateMesh`로 그리고 `arc_links`(상한 64)를 빌리지 않는다. 동시에 32줄까지 | vfx-feel | 같음 |
| **`bolt_returned{self:true}`**(제 겹 줄기) | 큰 적의 **겹 고리 조각이 하나 꺼지며 거기서 몸으로 내리꽂히는 짧은 꺾인 선**이다. 길이 = 고리에서 가슴까지, 굵기 0.04m, 수명 0.15초. 같은 틱의 줄기는 고리를 시계 방향으로 돌며 차례로 띄운다(`i × 0.012초`). 그래서 "쌓인 겹이 터진다"가 고리가 비는 것으로 읽힌다. 도체 줄기와 섞인 시전(16.2)에서는 바깥에서 들어오는 선과 머리 위에서 내리꽂는 선이 함께 보인다 | vfx-feel | 같음 |
| `bolt_returned{spark:true}` | 죽은 자리에서 피뢰침으로 가는 가는 선이다. 굵기 0.03m, 알파 0.5, 수명 0.12초. 출발 자리는 이 파일이 들고 있는 **바로 전 프레임의 적 자리**에서 읽는다(죽은 적은 그 틱에 `enemies`에 없을 수 있다). 자리를 모르면 그리지 않는다 | vfx-feel | 같음 |
| `bolt_returned{merged:n}` | 선을 더 그리지 않는다. 그 틱의 마지막 `detonated{big:true}` 터짐 크기에 n을 더한다 | vfx-feel | 같음 |
| **`detonated{big:true}`** | 받은 큰 적의 가슴 자리에 **한 번의 터짐**을 띄운다. 꺾인 빛살이 사방으로 6~10개(`stacks`에 비례, 8에서 끝), 반지름 0.6m + `stacks × 0.06m`(최대 1.4m), 0.28초. 마지막 줄기가 닿는 프레임에 맞춘다(위의 늦춤 끝). `stacks ≥ 8`이면 카메라 0.25를 시전마다 한 번(`chapter_effects.gd` `_kick`, 같은 틱에 우두머리 화면이 흔들면 큰 쪽 하나만) | vfx-feel | 같음, `chapter_effects.gd`(넘기는 줄) |
| `detonated{big:false}` | 작은 빛 0.12초, 반지름 0.35m. 한 프레임에 8개까지, 나머지는 띄우지 않는다. `kill:true`라도 따로 그리지 않는다(죽음 표시가 이미 있음) | vfx-feel | 같음 |
| 피해 숫자(오버로드·로드·불꽃이 `_damage_enemy`로 내는 맞음) | 줄기마다 숫자를 띄우지 **않는다**. 숫자는 `detonated` 하나에 하나(`damage_raw` 합)만, **큰 적에게만** 띄운다. 큰 적의 숫자는 지금 큰 숫자 결 그대로. 지금 `combat_juice.gd`가 맞음마다 숫자를 띄운다면 위 세 `skill_id`(`chapter1.skill.arc_overload`, `chapter1.skill.arc_rod`, 불꽃)를 거른다. 거르는 기준은 이벤트의 `skill_id`이고, 코드에 숫자를 쓰지 않는다 | vfx-feel | `view/fx/combat_juice.gd` |
| `chain_rebound` | 그 적 둘레에 **되돌아 감기는 갈고리** 하나를 그린다. 반지름 0.5m 반원 + 끝의 짧은 꺾임, 0.15초, ARC. 체인이 그 적에서 한 번 더 튀었다는 뜻이다 | vfx-feel | `element_kit_fx.gd` |
| `kit_storm{targets[]}` | 표적마다 **하늘에서 세로로 떨어지는 꺾인 번개**를 그린다. 높이 6m → 몸, 굵기 0.07m, 0.18초. 피뢰침 박힌 표적은 못 꼭대기에 닿는다. 1초에 한 번 오므로 다른 표시와 겹쳐도 짧다. 화면 전체 번쩍임은 쓰지 않는다 | vfx-feel | 같음 |
| `kit_shell{until}` | 주인공 몸을 **선만 있는 가는 껍질**로 두른다. 지름 = 주인공 높이 × 0.9, ARC 알파 0.35, 톱니 무늬가 천천히 돈다. `until`까지 남는다. 주인공의 몸을 덮지 않는다(채움 없음) | vfx-feel | 같음 |
| 우두머리 쉼(`boss_finale_view().state == "break"`) | 우두머리의 겹 고리는 **남긴다**(ET16: 겹이 남고 시간이 멈춤). 알파는 0.35로 낮추고 깜빡이지 않는다. 피뢰침은 `rod_dropped{break}`로 이미 빠졌다. 로드가 호위에 박히면 그 호위가 위 규칙대로 그려진다 | vfx-feel | 같음 |
| **스킬 칸 셋**(`kit_view().on`) | 전투 띠의 첫 세 칸(`SLOT_SIZES` 60·60·60)을 **주력·라이트닝 로드·오버로드**로 바꾼다. 차례는 명세 2.1(쌓기·깔기·터뜨리기)대로다. 칸 그림은 6절의 임시 기호다. 랭크가 0이면 지금의 흐린 칸(알파 0.22)에 자물쇠 없이 기호만 흐리게 둔다. 재사용 쓸기는 로드는 `next_rod`, 오버로드는 `next_overload`, 주력은 지금처럼 `_next_cast`에서 읽는다. 길이는 9절 ①의 `cooldown_ticks`로 나눈다. 들어오기 전에는 쓸기 없이 준비 됨/안 됨만 그린다. **오버로드가 준비됐는데 감전된 적이 없어 나가지 않을 때**(코어는 이때 쿨을 돌리지 않는다, 명세 2.3 규칙 1)는 칸이 밝게 서 있기만 하고 숨쉬지 않는다. 화염·냉기 마녀와 꺼진 판은 지금 칸 그대로(한 픽셀도 바뀌지 않음) | ui-hud | `view/hud/combat_bar.gd` |
| `skill_gate_opened{id, gate}` | 그 칸이 0.4초 동안 `BRASS_HI` 테두리로 한 번 밝아지고, 기호가 흐림에서 밝음으로 바뀐다("새 힘이 열린다"). 큰 띠는 글이 오기 전에는 띄우지 않는다(자리 KS-T1, 5절) | ui-hud | `combat_bar.gd`, `chapter_hud.gd`(이벤트를 띠에 넘김) |
| 진화(`growth.evolved`에 주력) | 지금의 진화 표시 그대로. 썬더스톰의 다음 틱(9절 ①)이 들어오면 주력 칸 둘레에 1초 쓸기를 가늘게 하나 더 그린다. 그 전에는 그리지 않는다 | ui-hud | `combat_bar.gd` |
| **카드: 깨지지 않고 뜸**(묶음 A) | 어댑터가 키트 카드를 옮긴다. `unlock` → `new`(이름은 스킬 이름 키 `skill.<id>.name`), `rank` → `upgrade`(단계는 `rank`의 로마 숫자, 이미 있는 `_tier`), `rune` → `prep`, `evolve` → `evolve`, `variant`·`survival`·`filler` → 묶음 A에서는 `new`. 이름은 `kit.card.<id>`, 글이 없을 때의 규칙은 디렉터 결정 1. 설명은 **키트 카드에 옛 설명 함수를 부르지 않는다**("기술 기본 피해 0"이 없어야 함). `kit.card.<id>.line` 키 하나를 쓰고, 글이 없으면 빈 줄로 둔다. 판 아래 띠(`_owned`)에 로드·오버로드를 넣는다(`kit_view().skills`에서 랭크 > 0인 것) | ui-hud | `view/contracts/growth_choice_contract.gd`, `view/hud/chapter_hud.gd`(`_card_description`의 키트 갈래 한 줄) |
| **카드: 새 종류의 얼굴**(묶음 B) | 계약 판 2. `kind`에 `variant`·`survival`·`filler`를 더하고 `rune`은 `prep`에 둔다. 얼굴은 기호로 가른다. **변형** = 카드 위 모서리에 갈래 기호(Y자), 이름 위 작은 꼬리표. **생존** = 방패 윤곽 기호. **채움** = 등급 빛 없이 한 단 어두운 바탕(`SURFACE`), 기호만 있고 그림 칸이 빈 패. "빈손은 아니지만 덜한 것"으로 읽혀야 한다. **요구**(`requires`의 스킬): 카드 아래쪽 줄에 그 스킬의 기호 → 이 카드 기호(지금 `combo` 칸의 꼴, `from`/`to`)를 두고, 글은 자리만(5절 KC-3). **택일**(`excludes`): ① 짝이 **같은 패에 함께 있으면** 두 카드 사이 틈에 **갈라진 사슬 고리**(두 고리가 반쯤 벌어진 기호, 24px)를 두고, 한 장에 초점이 가면 다른 장을 알파 0.75로 낮춘다 ② 짝이 패에 없으면 카드 아래쪽에 짝의 기호와 이름(지금 `pair` 칸: `{emblem, name}`)을 두고 그 앞에 "⇄" 꼴 기호를 붙인다. **트리가 연 카드**(9절 ② `open`): 카드 왼쪽 아래에 작은 황동 마디 기호(트리 판의 마디 칸 꼴을 줄인 것). 바닥이 바꾼 카드라는 표시는 **하지 않는다** | ui-hud | `tests/contracts/growth_choice.contract.json`(판 2), `view/contracts/growth_choice_contract.gd`, `view/hud/screens/growth_choice.gd`, `view/hud/grace_parts.gd`·`grace_draw.gd`(기호), `tests/fixtures/contracts/growth_choice.*.json`(새 변형 셋: `kit_variant`, `kit_pair`, `kit_filler`) |
| `kit_card_taken` | 카드 화면의 지금 확정 움직임 그대로. 더하는 것은 없다 | — | — |
| **트리 판: 카드 마디**(묶음 C) | `card` 마디 칸 = 마디 이름 + **여는 카드의 기호 1~2개**(택일 마디는 두 기호 사이에 갈라진 사슬 고리). 고르면 오른쪽 설명 쪽지에 여는 카드의 이름과 한 줄을 보인다. `ranks` 효과 블록을 읽지 않는다(지금 `describe_keys`를 카드 마디에 부르지 않게 화면 쪽에서 가른다). `rule` 마디(다시 뽑기) = 마디 이름 + 규칙 한 줄. 갈래 다섯: `COL_W`를 고정 4칸에서 **갈래 수로 나누는 꼴**로 바꾼다. 공통 갈래는 `brass`, 나머지는 `Palette.ARC`(`BRANCH_COLORS`에 `arc` 추가). **남는 점수**: 열 마디가 다 찍혔는데 점수가 남으면 점수 칸 옆에 "남는 점수 n"과 그 뜻 한 줄(자리 KT-2: 나중에 수치 마디가 들어오면 쓰인다)을 둔다. 겉은 감사(`AUDIT-screen-unification` W10 줄)대로 **이 묶음에서 A10 겉(장면 등급 바탕, 양피지 설명 쪽지, 황동 마디 테, `ui_parts`)을 함께 입힌다**. 따로 먼저 입히지 않는다 | ui-hud | `view/hud/skill_tree_panel.gd`, `view/hud/tree_text.gd`, `tests/skill_tree_preview.gd`(번개 트리를 읽는 갈래 `--element=arc`) |

### 2.1 겹침과 뿌옇게 됨을 막는 규칙

- 이 지시서가 더하는 **면(채움)은 하나도 없다.** 바닥 표시(톱니 고리, 둘레 눈금)는 선이고 알파 0.55 이하다. 터짐은 빛살이고 0.28초 이하다.
- 그리는 층: 바닥 표시는 우두머리 화면 표시(render priority 9) **아래** 8에 둔다. 머리 위 고리·못·줄기·터짐은 몸 위에 그리되 전조(10~12)보다 아래다. 주인공 둘레 1.5m 안의 적 표시는 고리 주문의 규칙(`ring_spell_fx.gd` 704행)처럼 알파를 30%로 낮춘다. 주인공 상자를 비워 두기 위해서다(QUALITY 2절 1번).
- 상한: 보통 적 톱니 48, 큰 적 고리 6, 못 2, 줄기 선 32, 작은 터짐 8/프레임, 큰 터짐 4, 썬더스톰 번개 6. 모두 MultiMesh 하나와 ImmediateMesh 하나로 그린다. 적 180, 투사체 384의 기준에서 노드를 더 만들지 않는다.
- 체인(주인공 → 적)과 줄기(적 → 큰 적)와 썬더스톰(하늘 → 적)은 **방향**으로 갈린다. 같은 색이어도 정지 화면에서 출발점이 보인다.
- 우두머리 화면과 같은 자리: 쉼에는 우두머리 자리에 이 키트의 바닥 표시가 없다(피뢰침이 빠짐). 착지 전조(붉은 쓸기)와 폭풍 다섯(두 겹 테) 위에는 바닥 눈금 원이 겹칠 수 있다. 눈금은 알파 0.22의 짧은 선이라 전조의 채움을 바꾸지 않는다. 검수에서 확인한다(7.3).

---

## 3. 묶음과 차례

| 묶음 | 내용 | 담당 | 만드는 양 [어림] | 이것이 끝나면 |
|---|---|---|---|---|
| **A0** 켜는 길 | `--chapter1-trial=element_kit`, `--chapter1-kit-tree=` (4절). `TRIAL_NAMES`. `hud_dump` 덤프에 `kit` 키(켠 판만) | ui-hud | 소(앱 30줄 안팎 + 도구 10줄) | art-lead가 켠 판의 "전" 캡처를 뜬다(지금 화면이 무엇을 못 하는지 그림으로 남김) |
| **A1** 전투 중 표시 | 2절 표의 vfx-feel 줄 전부: 톱니·겹 고리·가득 참·못·눈금 원·줄기 둘·불꽃·터짐·숫자 거름·되튐·썬더스톰·막 | vfx-feel | 중~대(새 효과 파일 350~450줄 + 셰이더 1 + `chapter_effects.gd` 두 줄 + `combat_juice.gd` 거름) | — |
| **A2** 스킬 칸 | 칸 셋, 쿨, 열림 반짝 | ui-hud | 중(`combat_bar.gd` 120줄 안팎) | — |
| **A3** 카드가 깨지지 않음 | 어댑터의 종류 옮김, 옛 설명을 부르지 않음, 이름 글의 규칙(결정 1), 판 아래 띠 | ui-hud | 소~중(어댑터 60줄 + `chapter_hud.gd` 몇 줄) | **최소 묶음 = A0~A3.** 사용자가 쳐 볼 수 있다 |
| **B** 카드의 새 종류 | 계약 판 2, 얼굴 셋, 요구·택일·트리 표시, 픽스처 셋 | ui-hud | 중 | 사용자가 카드를 고르는 맛을 판정할 수 있다 |
| **C** 트리 판 | 카드 마디, 다섯 갈래, 남는 점수, A10 겉 | ui-hud(+ narrative-lead 글) | 대 | 트리 화면은 미리보기 캡처로 본다(시험 판에서는 트리가 열리지 않음, 1.1). 사용자 플레이 길은 키트를 출하에서 켜는 날 생긴다 |

- A1과 A2·A3은 **동시에** 간다. 파일이 겹치지 않는다(8절 표).
- A0은 **먼저 따로** 합친다. 우두머리 화면 지시서 7.2처럼 "전" 캡처를 뜨기 위해서다.
- B는 A3을 바탕으로 한다(같은 어댑터). C는 B의 카드 기호를 빌린다. 그래서 차례는 A0 → (A1 ∥ A2·A3) → B → C다.
- 9절의 코어 일(gameplay-systems)은 A1·A2와 나란히 간다. 들어오기 전에도 A1·A2는 2절 표의 "들어오기 전" 규칙으로 돈다.

---

## 4. 앱에서 켜는 길 (ui-hud, 묶음 A0)

### 4.1 `--chapter1-trial=element_kit`

- `app/chapter_one.gd` `_apply_trial`의 이름 목록(393·394행)에 `element_kit`을 더한다. `--chapter1-profile-off`와 함께일 때만 먹는 것은 지금 규칙 그대로다.
- 하는 일은 `kit_docs.gd` `enable_kit_problem`과 같다. 출하 `element_kit.json`의 사본에 `enabled:true`, `enabled_elements:["arc"]`를 넣어 `run.set_element_kit()`에 주고, `run.set_kit_open(<4.2의 값>)`을 부른다. 같은 구현을 두 곳에 쓰지 않는다. 우두머리 때와 같이, 앱 쪽에 함수 하나를 두고 `kit_docs.gd`가 그것을 부르게 할지 그 반대일지는 담당이 정하고 보고에 적는다(앱이 `tests/`를 preload하지 않는 쪽이 맞다).
- **무엇을 함께 켜나**(디렉터 결정 2): `element_kit`은 **키트만** 켠다. 측정과 같은 판은 `boss_finale,element_kit`이다(`boss_finale`이 리듬·오프닝·성장 속도를 함께 켬, 393~402행). 이 조합이 측정의 켠 경로 `enable_kit_rhythm_problem(run, "all", true)`와 같은 게임이어야 한다. 사용자에게 알리는 실행 줄은 이 조합으로 쓴다.
- **거절되는 짝**: 코어는 키트 + `run_spells`, 키트 + `grace.enabled`를 거절하고 판을 시작하지 못한다(`chapter_core.gd` 3481·3482행). 앱은 `element_kit`이 `spells` 또는 `grace`와 함께 오면 **`element_kit`을 버리고 경고 한 줄**을 낸다. 판이 시작조차 안 되는 일이 없게 하기 위해서다.
- 번개가 아닌 마녀로 시작하면 키트는 저절로 꺼진다(`is_on_for`). 앱은 `CHAPTER1_TRIAL` 줄 옆에 "element_kit: arc만" 한 줄만 찍는다.
- `chapter1/tests/support/trial_docs.gd` 16행 `TRIAL_NAMES`에 `element_kit`을 더한다(캡처 머리가 `trial:?element_kit`로 찍히지 않게).
- 창 제목의 시험 태그는 지금 그대로다(456행).

### 4.2 트리를 다 연 상태 — `--chapter1-kit-tree=all|none|<카드 id,…>`

- `--chapter1-profile-off`와 `element_kit`이 함께일 때만 먹는다. 기본값은 `all`이다. 택일 짝(A19/A20, A21/A22)과 큰 적 변형은 모두 트리가 여는 카드라서(`element_kit.json` `open`), `none`으로는 택일 화면을 볼 수 없다.
- `none` = 새 계정(17장), 목록 = 그 카드만. 측정의 `--kit-tree`와 같은 세 꼴이다.
- **코어 일은 없다**(`set_kit_open`은 이미 공개). 저장이 켜진 판(사용자 본인 플레이)에서는 이 인수를 무시한다.

### 4.3 사용자 실행 줄(문서에 적을 것)

```
python tools/dev/run_dev.py -- --chapter1-start --chapter1-profile-off --chapter1-trial=boss_finale,element_kit --chapter1-kit-tree=all --chapter1-primary=chapter1.skill.arc
```
우두머리만 되풀이해 볼 때는 `--chapter1-boss-now`를 더한다(9절 ③이 들어오기 전에는 로드·오버로드가 다 열려 있는지 보장되지 않는다).

### 4.4 덤프

`chapter1/tests/hud_dump.gd`의 상태 덤프에 `kit_view().on`일 때만 `kit` 키(`kit_view()` 그대로와 화면에 그린 수: 톱니·고리·못·줄기 선)를 더한다. **꺼진 판의 덤프는 바이트까지 같아야 한다.**

---

## 5. 화면에 들어갈 글 — 자리만 (narrative-lead에 넘김)

글귀는 narrative-lead가 쓴다. 화면 담당은 키와 자리만 만든다. 새 글귀를 짓지 않는다. 분위기 낱말을 쓰지 않는다. 이름은 널리 쓰이는 게임 스킬 이름의 결이고 풀어 쓰지 않는다(메모리의 이름 방향). 명세의 이름은 모두 임시다.

| 자리 | 키(제안) | 길이 | 뜻 |
|---|---|---|---|
| KS-1 깔아 두는 스킬 이름 | `skill.chapter1.skill.arc_rod.name` | 스킬 칸·카드 이름, 12자 안 | 큰 적에 못을 박아 감전을 붙들어 둠(임시 "라이트닝 로드") |
| KS-2 터뜨리는 스킬 이름 | `skill.chapter1.skill.arc_overload.name` | 같음 | 감전된 졸개와 큰 적 제 겹에서 번개를 큰 적으로 모음(임시 "오버로드") |
| KS-T1 새 스킬 열림 띠 | `hud.band.skill_gate` | 큰 띠 부제, 14자 안팎, `{name}` 하나 | 결정 2에서 띠를 쓰기로 하면. 글이 오기 전에는 띠 없이 칸 반짝임만 |
| KC-1 카드 이름 30 | `kit.card.A01`~`A28`, `X01`, `X02` | 24자 안(계약 `name`) | 명세 4.4·4.5 표의 "바꾸는 것". 열림 카드(A01·A02)는 스킬 이름을 그대로 쓸지 |
| KC-2 카드 한 줄 30 | `kit.card.<id>.line` | 60자 안 | 같은 표. 수치는 글에 박지 않고 `{n}`으로(카드 `change.vals`에서 화면이 채움) |
| KC-3 요구 줄 | `grace.screen.kit.requires` | 16자 안, `{skill}` | "이 카드는 ‹스킬›을 바꾼다"의 뜻. 요구가 서야만 패에 들므로 "있어야"보다 "‹스킬›에 붙는다"에 가깝다 |
| KC-4 택일 줄 | `grace.screen.kit.excludes` | 24자 안, `{card}` | 고르면 짝이 이 판에서 사라짐 |
| KC-5 종류 꼬리표 셋 | `grace.screen.kind.variant`, `.survival`, `.filler` | 8자 안 | 변형·생존·채움. 룬은 지금의 `grace.screen.kind.prep`을 쓴다 |
| KC-6 트리 마디 표 | (글 없음 — 기호만) | — | 결정할 것이 없다. 기호로만 |
| KT-1 트리 이름들 | `element_trees.json`의 `branches[].name`·`tiers[].name`·`nodes[].name`·`lore` | 지금 데이터의 임시 한국어 | 갈래 다섯, 단 넷, 마디 열. 이것은 데이터 파일을 고치는 일이다(content-balance 또는 narrative-lead가 데이터를 넘김) |
| KT-2 남는 점수 | `hud.tree.points_left` + 한 줄 `hud.tree.points_left_note` | 20자 / 40자 | 나중에 수치 마디가 들어오면 쓰이는 점수 |
| 상태 이름(감전·피뢰침) | — | — | **전투 화면에는 글로 쓰지 않는다**(모양만). 카드·트리 글 안에서 부를 이름은 narrative-lead가 정한다(명세 14절, 11절 결정 4의 "한기/냉각"과 같은 물음) |

모두 약 70줄이다. narrative-lead 9.3 배정의 "약 25개"(이름)에 카드 한 줄 30과 화면 낱말 여섯이 더해진 것이다.

---

## 6. 그림 — 새 에셋 없이 먼저, 꼭 필요한 것은 목록으로

| 무엇 | 묶음 A의 임시 | 진짜가 필요한가 | 만드는 길 |
|---|---|---|---|
| 라이트닝 로드 칸·카드 기호 | `combat_bar.gd`·`grace_draw.gd`가 선으로 그린다: 세로 못 + 꼭대기 마름모 + 바닥 짧은 가로 줄 | **예**(스킬 아이콘 1) | ui_style 아틀라스와 같은 결의 칸 그림. `asset_slots.gd` 자리 `ui.skill.arc_rod`, 원장에 올림 |
| 오버로드 칸·카드 기호 | 짧은 꺾인 선 셋이 가운데 점으로 모임 | **예**(스킬 아이콘 1) | 자리 `ui.skill.arc_overload` |
| 카드 종류 기호 셋(변형 Y자·생존 방패·채움 빈 패), 갈라진 사슬 고리, 트리 마디 표 | 선으로 그림 | 아니오. 선 기호가 이 화면 문법(은총 화면의 기호)과 맞으면 그대로 둔다 | — |
| 카드 그림 칸(카드 30장) | 지금 은총 카드의 기호 그림(`emblem`)을 원소 기호 `bolt`로 | 뒤로. 카드마다 그림을 따로 둘지는 B를 사용자가 본 뒤에 정한다 | (정하면 asset-producer 견적) |
| 적 위 톱니·겹 고리·못·줄기·터짐 | 셰이더 도형 | 아니오 | — |

- 그림 파일 경로를 코드에 쓰지 않는다. 자리 이름으로 부르고, 자리가 비어 있으면 위의 선 기호로 떨어진다(T7). 바꿔 끼울 곳이 한 곳이 되게 하기 위해서다(CLAUDE.md "에셋은 모두 바뀔 것이다").
- 유료 생성은 없다. 아이콘 둘을 만들 때 비용 제시는 디렉터를 거친다.

---

## 7. 검수 방법

### 7.1 캡처 명령 (저장소 루트에서, art-lead가 직접 돌린다)

1920×1080, 전투 장면:
```
python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.arc --chapter1-trial=boss_finale,element_kit --chapter1-kit-tree=all --wall-limit=2400 --shots=_local/shots/ek-screen-<전|후>-1080 --dump=_local/shots/ek-screen-<전|후>-1080.json --burst=skill_gate_opened:gate=S1,status_stacked:big=true,status_full,detonated:big=true,skill_gate_opened:gate=S2,rod_planted,bolt_returned:self=true,chain_rebound,kit_storm,rod_dropped:reason=break,boss_break_started:index=1 --burst-frames=12 --burst-step=6
```
1280×720: 같은 줄에서 `--resolution 1280x720`, 폴더 이름 `-720`.

- `--burst`는 이름마다 **첫** 맞는 이벤트 뒤 12장(0.1초 간격)을 뜬다. `status_stacked:big=true`의 첫 장은 첫 수호자일 가능성이 높다. 만나지 못한 이름은 `HUD_BURST_SUMMARY`에 남고, 그 장면은 "보지 않음"으로 적는다. `self=true`처럼 참거짓 값이 맞춤 규칙(`burst_capture.gd` 4~7행, 필드 값을 글로 견줌)에 걸리는지는 확인하지 않았다. 걸리지 않으면 `bolt_returned`로 뜨고 장마다 덤프의 줄기 종류를 본다.
- 카드 화면: 같은 실행의 `choice-1`·`choice-2` 장면. 새 종류(묶음 B)는 픽스처 `growth_choice.kit_variant`·`kit_pair`·`kit_filler`를 `scene_shot.gd`로 1080·720에서 뜬다(자동 조작은 변형을 거의 고르지 않아 실판에서 택일 짝이 같은 패에 뜨는 장면이 드물다, 1.3).
- 트리 판(묶음 C): `tests/skill_tree_preview.gd --element=arc --shots=_local/shots/ek-tree-<전|후>`를 1080·720으로.
- 우두머리 장면을 되풀이할 때는 같은 줄에 `--chapter1-boss-now`(9절 ③ 뒤).

### 7.2 "전"과 "후"

A0만 합친 상태에서 "전"을 뜬다. 이것이 1.1 표의 그림 증거다(지금은 코드로만 읽었다). A1~A3을 합친 뒤 같은 시드·같은 인수로 "후"를 뜬다. 코어와 자동 조작이 같으므로 버스트 장의 틱이 전후에 같다. 같은 틱의 장을 나란히 놓는다. 그리고 꺼진 판(위 줄에서 `--chapter1-trial`·`--chapter1-kit-tree`·`--burst`를 빼고 `--primary=chapter1.skill.frost`)의 덤프를 고치기 전후로 떠서 **바이트 비교**한다.

### 7.3 볼 장면과 통과 기준

정지 화면 한 장을 **0.5초 보고** 아래를 말할 수 있으면 통과다. 1080·720 둘 다 직접 본다. 같은 장을 흑백으로 바꿔 한 번 더 본다.

| 장면(버스트) | 볼 장 | 0.5초에 말할 것 | 반려 조건 |
|---|---|---|---|
| 오버로드 열림 `skill_gate_opened:gate=S1` | 1·4장 | 둘째 칸(셋째 자리)이 새로 켜졌다 | 칸이 그대로 흐림, 화염·냉기 칸이 남아 있음 |
| 큰 적 쌓임 `status_stacked:big=true` | 1·6·12장 | 어느 적이 큰 적이고 몇 겹인가(조각을 세지 않고 "반쯤"·"거의"를 말할 수 있으면 됨). 도체 졸개가 어디 있는가 | 고리가 몸이나 체력 막대에 가림, 보통 적의 톱니가 무리 위를 덮어 바닥이 안 보임 |
| 가득 참 `status_full` | 1·3장 | 곧 터진다(둘째 고리) | 화면 번쩍임, 둘째 고리가 없음 |
| **큰 적 터짐 `detonated:big=true`** | 1·2·3·4장 | 번개가 **어디서 와서** 큰 적으로 모였나. 도체 줄기와 제 겹 줄기가 섞였으면 둘을 손으로 짚을 수 있음 | 줄기가 체인과 같아 보임(방향이 안 읽힘), 숫자가 여러 개 겹침, 주인공이 빛에 묻힘 |
| 로드 열림·박힘 `skill_gate_opened:gate=S2`, `rod_planted` | 1·6·12장 | 셋째 칸(둘째 자리)이 켜짐, 못이 어느 적에 박혔나, 둘레 눈금 | 눈금 원이 우두머리의 점선 원처럼 보임(흑백에서 갈리지 않음) |
| 제 겹 줄기 `bolt_returned:self=true` | 1·2·3장 | 고리가 비며 몸으로 내리꽂힘 | 도체 줄기와 같은 꼴 |
| 되튐 `chain_rebound` | 1·2장 | 체인이 그 적에서 한 번 더 튀었다 | — (작게 보이면 통과) |
| 썬더스톰 `kit_storm` | 1·2장 | 하늘에서 떨어지는 번개, 피뢰침 꼭대기 | 화면 전체가 밝아짐 |
| 우두머리 쉼 `rod_dropped:reason=break`, `boss_break_started:index=1` | 1·6·12장 | 피뢰침이 빠짐, 흐린 우두머리 위의 겹 고리는 남아 있음(흐리게), 로드가 호위로 옮김, 폭풍 다섯의 두 겹 테가 그대로 읽힘 | 키트 표시가 착지·폭풍 전조를 가림 |
| 카드 `choice-1`·`choice-2` | 각 1장 | 묶음 A: 키 글자("kit.card.")와 "기술 기본 피해 0"이 0. 묶음 B: 종류 셋이 기호로 갈림, 택일 짝이 함께 있으면 사슬 고리, 트리가 연 카드 표 | 글이 계약 길이를 넘어 잘림, 720에서 겹침 |
| 트리 판(미리보기) | 기본·카드 마디 고름·다 찍음 | 마디가 여는 카드, 다섯 갈래가 한 판에 들어감, 남는 점수 | 설명 오류·빈 쪽지, 갈래 칸이 틀 밖으로 나감 |

모든 장에 공통: 주인공을 1초 안에 짚는다(QUALITY 2절 1번). 적의 전조가 주문 효과에 가려지지 않는다(2번). 번개 계열이 흑백에서도 화염·냉기와 모양으로 갈린다(3번). 우두머리를 일반 적과 가른다(5번). HUD가 720에서 겹치거나 잘리지 않고 가운데 60%×60%를 가리지 않는다(3절). 스킬 칸은 글 없이 기호와 쓸기만으로 상태가 읽힌다(3절 "읽기").

### 7.4 성능

- `frame_probe.gd`를 켠 판(위 조합, 번개 시드 11, 1080)으로 효과를 켜고 끈 두 번 돌린다. 우두머리 앞 무리(적 수가 가장 많은 구간)의 프레임 시간 p95를 견주어 **+0.5ms 이내**여야 한다. HUD 동기화는 T8 규칙대로 **+0.1ms 이내**다. `kit_view()`는 사전을 새로 만드므로 HUD가 프레임에 한 번만 받아 전투 띠와 나눠 쓴다.
- 이 지시서의 상한(2.1)을 넘는 노드·인스턴스가 생기지 않았는지 덤프의 그린 수로 확인한다.

### 7.5 정지 화면으로 판단할 수 없는 것

다음은 사용자가 켠 판을 칠 때만 판정한다(켜는 장부 ⑨):
- 줄기 다발이 모이는 0.13초가 "팡팡"으로 느껴지는가
- 톱니 깜빡임이 거슬리는가
- 오버로드가 3초마다 터지는 박자가 읽히는가
- 도체 줄기와 제 겹 줄기 가운데 어느 쪽이 이 키트의 얼굴로 맞는가(ET-D15의 선택)
- 카메라의 세기, 소리와 맞는가

### 7.6 돌릴 검사 (구현 담당이, 그리고 검수 때 art-lead가 본 저장소에서 다시)

- 골든 `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd`는 **해시 불변**이어야 한다(표현만 고침). 9절의 코어 일은 따로 합친다.
- `python tools/dev/run_all.py --quick`. 여기에 `screen-contract`가 들어 있다. 묶음 B는 판 2의 넷(스키마·어댑터·화면·픽스처)이 맞아야 한다.
- 시험 이름: `trial_state_probe.gd`에 `--chapter1-trial=element_kit --chapter1-profile-off --chapter1-primary=chapter1.skill.arc`를 줘서 `kit_view().on`이 참인지, `spells`·`grace`와 함께면 키트가 꺼지고 경고가 나는지 본다.
- 꺼진 판 덤프의 바이트 불변(7.2).
- 셰이더 컴파일 오류 0(캡처 실행 출력).
- `test_element_kit.gd`는 그대로 통과해야 한다(코어를 건드리지 않음).

---

## 8. 배정문 초안

두 담당이 고치는 파일은 겹치지 않는다. `app/chapter_one.gd`와 `view/hud/` 아래는 ui-hud만, `view/fx/` 아래는 vfx-feel만 고친다. `view/actors/chapter_actors.gd`는 이번에 **아무도 고치지 않는다**(적 위 표시는 효과 파일이 적 자리를 읽어 그림. 우두머리 화면의 몸 일과 부딪히지 않게). 카메라 흔들림은 `detonated{big}`의 것 하나만 있고 vfx-feel의 `_kick`으로 한다.

| 파일 | vfx-feel | ui-hud |
|---|---|---|
| `chapter1/view/fx/element_kit_fx.gd`(새) · `element_kit_mark.gdshader`(새) | 새로 씀(A1) | — |
| `chapter1/view/fx/chapter_effects.gd` | `consume()`·`sync()` 끝에서 새 파일로 넘기는 두 줄(우두머리 효과 `_boss_fx`와 같은 꼴, 1255~1257·1309~1311행 옆) | — |
| `chapter1/view/fx/combat_juice.gd` | 키트 스킬의 맞음 숫자 거름, `detonated{big}` 숫자 하나 | — |
| `chapter1/app/chapter_one.gd` | — | A0(`_apply_trial`, `--chapter1-kit-tree`), `skill_gate_opened`를 HUD에 넘김 |
| `chapter1/tests/support/trial_docs.gd`, `kit_docs.gd` | — | A0(이름 목록, 같은 구현을 한 곳에) |
| `chapter1/tests/hud_dump.gd` | — | A0(`kit` 덤프 키, 켠 판만) |
| `chapter1/view/hud/combat_bar.gd` | — | A2 |
| `chapter1/view/hud/chapter_hud.gd` | — | A3(`_card_description` 키트 갈래, `kit_view` 한 번 받기) |
| `chapter1/view/contracts/growth_choice_contract.gd` | — | A3·B |
| `chapter1/view/hud/screens/growth_choice.gd`, `grace_parts.gd`, `grace_draw.gd` | — | B |
| `chapter1/tests/contracts/growth_choice.contract.json`, `tests/fixtures/contracts/growth_choice.kit_*.json` | — | B |
| `chapter1/view/hud/skill_tree_panel.gd`, `tree_text.gd`, `chapter1/tests/skill_tree_preview.gd` | — | C |
| `chapter1/i18n/ko.po`, `en.po` | — | narrative-lead의 글이 온 뒤(또는 결정 1의 임시) |
| `chapter1/view/hud/palette.gd` | 읽기만 | 읽기만(새 토큰 없음) |

### 8.1 vfx-feel (묶음 A1)

> 지시서 `docs/specs/A-element-kit-screen-20261125.ko.md`의 2절 표에서 vfx-feel 줄, 2.1절을 구현한다. 작업 폴더에서 하고 패치와 보고서를 낸다.
>
> 고칠 파일: 새 `chapter1/view/fx/element_kit_fx.gd`와 `element_kit_mark.gdshader`(우두머리 효과 `boss_finale_fx.gd`처럼 `chapter_effects.gd`의 `consume()`·`sync()` 끝에서 부른다), `chapter1/view/fx/chapter_effects.gd`(넘기는 두 줄과 `_kick` 한 곳), `chapter1/view/fx/combat_juice.gd`(키트 스킬 숫자). 다른 파일은 고치지 않는다. `chapter_actors.gd`도 고치지 않는다. `view/` 바로 아래 옛 층에 넣지 않는다.
>
> 할 일:
> 1. 보통 적 발밑 톱니(상한 48, 사거리 안 먼저)와 붙는 순간
> 2. 큰 적 머리 위 조각 고리(조각 수 = 상한), 새 조각 반짝, 가득 참의 둘째 고리
> 3. 피뢰침 못(남은 시간 = 길이), 둘레 눈금 12, 박힘·빠짐
> 4. 도체 줄기(졸개 → 큰 적, 다발 늦춤 0.012초씩)와 제 겹 줄기(고리 조각에서 몸으로)를 다른 꼴로, 불꽃, 넘친 묶음
> 5. 큰 적 터짐(겹 수 비례), 작은 터짐, 숫자 거름
> 6. 되튐 갈고리, 썬더스톰 하늘 번개, 정전기 막
> 7. 우두머리 쉼의 흐린 고리
>
> 지킬 것:
> - 표현은 이벤트와 읽기 전용 상태(`run.enemies[*].kst`·`rod_until`·`elite`, `run.kit_view()`, `run.boss_finale_view()`)만 쓴다.
> - 꺼진 판(`kit_view().on` 거짓)에서는 아무것도 만들지도 그리지도 않는다.
> - 반지름·상한·재사용은 이벤트·`kit_view()`에서 읽고 코드에 숫자로 쓰지 않는다. 9절 ①이 오기 전에는 2절 표의 "들어오기 전" 규칙을 따른다.
> - 면(채움) 없음, 전조 붉은색·리넨 쓰지 않음, 화면 전체 번쩍임 없음, 새 그림 에셋 없음.
> - 2.1절의 상한과 층을 지킨다.
>
> 검사: 골든 불변, `run_all.py --quick`, 지시서 7.4의 `frame_probe` 전후. 보고에 7.1 명령으로 뜬 1080 캡처 폴더 경로를 적는다(판정은 art-lead).
>
> 다섯 요소: `[쾌]` 쌓인 것이 모여 터지는 맛, `[섹]` 감전이 무리에 번지고 번개가 큰 적에게 꽂히는 화면, `[성]` 로드·오버로드가 무엇을 하는지 눈으로 배움.

### 8.2 ui-hud (묶음 A0 → A2·A3 → B → C)

> 지시서 `docs/specs/A-element-kit-screen-20261125.ko.md`의 4절(A0)을 **먼저 따로** 낸다(art-lead가 이것으로 "전" 캡처를 뜬다). 이어서 2절 표의 ui-hud 줄 중 스킬 칸(A2)과 카드가 깨지지 않음(A3)을 낸다. 묶음 B(카드의 새 종류)와 C(트리 판)는 디렉터가 차례를 정하면 그때 한다. 작업 폴더에서 하고, 묶음마다 패치와 보고서를 낸다.
>
> 고칠 파일: 8절 표의 ui-hud 열. `view/fx/`·`view/actors/`는 고치지 않는다(vfx-feel).
>
> 할 일:
> - A0: `--chapter1-trial=element_kit`(키트만, `spells`·`grace`와 함께면 버리고 경고), `--chapter1-kit-tree=all|none|<id,…>`(기본 all, 저장이 켜진 판에서는 무시), `TRIAL_NAMES`, 같은 구현을 한 곳에, `hud_dump` `kit` 키(켠 판만).
> - A2: 켠 판의 전투 띠 첫 세 칸을 주력·로드·오버로드로(임시 선 기호), 쿨 쓸기, 열림 반짝. 화염·냉기 마녀와 꺼진 판은 바뀌지 않음.
> - A3: 어댑터의 키트 종류 옮김, 키트 카드에는 옛 설명을 부르지 않음, 이름 글의 규칙(디렉터 결정 1), 판 아래 띠에 로드·오버로드.
> - B: 계약 판 2(`kind` 셋 추가, 요구·택일·트리 표시), 얼굴 셋, 픽스처 셋.
> - C: 카드 마디, 다섯 갈래, 남는 점수, A10 겉, 미리보기에 번개 트리.
>
> 지킬 것:
> - 꺼진 판의 `hud_dump` 기본 덤프가 바이트까지 같다.
> - 색은 `palette.gd`의 지금 토큰만 쓴다.
> - 1280×720에서 칸·카드·트리가 틀 밖으로 나가지 않는다.
> - 글이 없는 자리에 빈 띠나 지은 글을 내지 않는다(5절).
> - 그림은 자리 이름으로 부르고, 비면 선 기호로 떨어진다(6절).
> - `kit_view()`는 HUD가 프레임에 한 번만 받는다.
>
> 검사: 골든 불변, `run_all.py --quick`(`screen-contract` 포함), `trial_state_probe.gd`, 꺼진 판 덤프 비교, 7.4의 HUD +0.1ms. 보고에 1080·720 캡처 폴더 경로를 적는다.
>
> 다섯 요소: `[성]` 새 스킬이 언제 열리고 언제 나가는지 보임, 트리가 연 카드가 패에 보임 · `[도]` 택일 짝을 보고 버릴 것을 고름 · `[보]` 채움 카드도 빈손이 아님.

### 8.3 소리 — audio-lead에 넘길 이벤트 목록만

화면 담당은 소리를 만들지 않는다. audio-lead가 `docs/AUDIO-PLAN.ko.md` 기준으로 정한다. 명세 7.2·9.4의 "소리 6~7개"와 맞춘다.

| 이벤트 | 화면이 하는 것(소리와 맞출 자리) | 명세가 바란 것 |
|---|---|---|
| `status_full` | 큰 적 고리 밝아짐 + 둘째 고리 | 큰 적 겹 가득일 때만("곧 터진다") |
| `detonated` + 같은 틱의 `bolt_returned` 다발 | 줄기가 0.012초씩 늦춰 모이고 마지막에 큰 터짐 | 줄기 수에 따라 굵어지는 **한 소리**. 시전마다 하나, 큰 적은 따로 |
| `bolt_returned{self:true}`만 있는 시전 | 고리가 비며 내리꽂힘 | 도체 줄기와 갈리는지는 audio-lead가 판단(ET-D15의 선택에 걸림) |
| `rod_planted` / `rod_dropped` | 못이 내리꽂힘 / 기울어 사라짐 | 박힘·떨어짐 |
| `skill_gate_opened` | 칸 반짝 | 새 힘이 열림 |
| `kit_card_taken{kind}` | 카드 확정(지금 움직임) | 카드의 택일·변형(종류마다 다를지) |
| `kit_storm` | 하늘 번개 | (진화 소리, 지금 체인 진화 소리와의 관계) |
| `kit_shell` | 껍질 | (생존 카드) |
| `chain_rebound` | 갈고리 | 작게 또는 없음 |

---

## 9. 코어 쪽에 더 필요한 것 (gameplay-systems에 넘김. 이 지시서를 막지는 않는다)

모두 **읽기 전용**을 더하는 일이다. 꺼진 판의 골든 10사례는 불변이어야 한다.

1. **`kit_view()`에 화면이 읽을 값 넷을 더한다.**
   - `skills[id].cooldown_ticks`: 카드 A21·A22의 `overload_cd_bps`까지 들어간 지금 값. 주력은 지금 경로가 있으니 로드·오버로드만 있으면 된다.
   - `next_storm`
   - `cap_big`: 지금 큰 적 겹 상한(A18 포함)
   - `rod_radius_cm`(로드 랭크 3 포함)과 `reach_cm`(오버로드 사거리)

   상태를 바꾸지 않는 함수라 골든에 닿지 않는다. 이것이 없으면 쓸기 없는 칸, 이벤트로 짐작한 조각 수, 눈금 원 없음, 사거리 없는 톱니 순서로 떨어진다.
2. **제안 카드에 `open`(`"base"` 또는 트리 마디 id)을 더한다**(`run_growth.gd` `_kit_card_view`). 묶음 B의 "트리가 연 카드" 표에 쓴다. 제안이 켠 경로 골든 `element-arc`의 해시에 들어가면 그 사례만 바뀐다. 그러면 의도한 변경임을 밝히고 `--update`한다.
3. (선택) **`debug_skip_to_boss`를 키트 판에서 쓸 때** 건너뛰는 동안 뜨는 패에서 열림 카드 둘(A01·A02)을 먼저 고르게 하고, 문(`after_picks`)에 닿을 만큼 패를 돌게 한다. 그래야 `--chapter1-boss-now`로 우두머리를 되풀이해 볼 때 칸 셋이 다 열려 있다. 지금 점수표로도 열릴 가능성은 높지만 확인하지 않았다.
4. (선택, 화면이 먼저 해 본 뒤) `bolt_returned`의 불꽃(`spark`)에 출발 자리 `from_position`. 화면이 바로 전 프레임의 적 자리로 버티지 못할 때만 한다.

---

## 10. 디렉터가 정할 것

1. **글이 오기 전, 카드 이름과 한 줄을 무엇으로 띄우나.**
   - (가) 명세 4.4·4.5 표의 임시 이름과 "바꾸는 것"을 그대로 옮겨 `ko.po`에 임시 표시를 붙여 넣는다(권고). 사용자가 바로 쳐 볼 수 있고, narrative-lead의 글이 오면 바꾼다. 다만 임시 이름은 풀어 쓴 것이 많다("되돌아오는 번개 한 줄 더"). 사용자에게 "이름은 임시"라고 한 줄 알린다.
   - (나) narrative-lead의 이름(약 70줄, 5절)을 먼저 받고 묶음 A3을 그 뒤에 닫는다.
2. **시험 이름의 묶음.**
   - (가) `element_kit`은 키트만 켜고, 측정과 같은 판은 `boss_finale,element_kit`로 친다(권고. 이름 하나가 한 가지만 켬). 사용자 실행 줄은 4.3대로.
   - (나) `element_kit`이 리듬·속도·우두머리를 함께 켠다.

   그리고 트리 기본값 `all`(택일 짝이 보이는 판)을 받는가.
3. **트리 판(묶음 C)을 언제 하나.**
   - (가) 사용자가 A·B를 친 뒤에 A10 겉과 한 번에(권고. 시험 판에서는 트리가 열리지 않아 사용자의 첫 플레이를 막지 않는다. 겉을 두 번 입히지 않는다).
   - (나) 지금 B와 나란히.

사용자에게 새로 여쭐 것은 없다. 명세 16.4의 물음("새 마녀의 첫 판은 배우는 판으로 두어도 될까요?")이 아직 남아 있다면 이 화면이 들어간 판을 사용자가 친 뒤에 함께 여쭙는 것이 좋다. `--chapter1-kit-tree=none`으로 그 판을 직접 볼 수 있기 때문이다.

---

## 11. 읽은 것, 읽지 못한 것

**읽은 것**
- 장부 U-124·U-126·U-127 줄과 켜는 장부 `element_kit` 줄
- 명세 `D-element-trees`: 0~10절과 14~19절(11~13절은 제목만)
- `A-boss-finale-screen` 전부
- `QUALITY-TARGETS` 2·3절
- `A10` 3절
- `T8` 1~4절
- `AUDIT-screen-unification`의 스킬 트리 줄
- `chapter_core.gd`: 1219~1246행(우두머리 건너뛰기), 3470~3928행(키트 전부: 상태·로드·줄기·오버로드·썬더스톰·카드 받음·`kit_view`)
- `run_growth.gd`: 1195~1294행(키트 카드 보기·준비·문·마지막 보호·채움)
- `element_kit.json`(번개 카드 30장과 키), `element_trees.json`(마디 열)
- `kit_docs.gd`, `trial_docs.gd`, `chapter_one.gd`: 376~460·634~643행
- `combat_bar.gd`: 1~200행
- `growth_choice_contract.gd` 전부, `growth_choice.contract.json`의 카드 필드
- `growth_choice.gd`·`grace_parts.gd`(함수 목록과 몇 줄)
- `chapter_hud.gd`: 249~262행(옛 카드 설명)
- `skill_tree_panel.gd`: 1~60·196~275행, `tree_text.gd`, `skill_tree.gd`의 `describe_keys`
- `chapter_effects.gd`: 체인 그리기(730~845·1160~1182행)와 consume/sync 진입점
- `boss_finale_fx.gd` 머리, `ring_spell_fx.gd` 함수 목록
- `palette.gd` 색 토큰, `burst_capture.gd` 머리, `chapter_pilot.gd` 카드 점수

**읽지 못했거나 확인하지 못한 것**
- **화면은 보지 않았다.** 지금 앱으로는 키트를 켤 수 없고, 이번에 Godot를 돌리지 않았다. 1.1 표의 "켠 판에서 보일 것"은 모두 코드를 읽고 짐작한 것이다. 특히 카드 화면이 깨지지 않는다는 것, 트리 판의 카드 마디가 설명에서 오류를 낸다는 것은 확인하지 않았다.
- `combat_juice.gd`가 맞음마다 피해 숫자를 띄우는지, 키트 스킬의 맞음 이벤트가 지금 어떤 맞음 표시를 일으키는지는 읽지 않았다(2절 표의 숫자 줄은 "그렇다면"으로 썼다).
- `chapter_actors.gd`의 적 몸 높이 값(머리 위 고리 높이)은 종류별 키(1.35~2.75m, 210행)만 봤고, 실제 모델의 머리 높이는 재지 않았다.
- `burst_capture.gd`가 `self=true` 같은 참거짓 값을 맞추는지는 확인하지 않았다.
- `debug_skip_to_boss`가 키트 판에서 문에 닿을 만큼 패를 돌리는지는 확인하지 않았다.
- `grace_draw.gd`의 기호 목록과 `scene_shot.gd`가 계약 픽스처를 찍는 길의 세부는 읽지 않았다.
- `AUDIO-PLAN.ko.md`는 읽지 않았다(소리는 이벤트 목록만 넘김).
- 기준작(디아블로 2·패스 오브 엑자일·사크라타)의 상태 표시와 연쇄 번개는 이번에 녹화로 다시 보지 않았다. 조각 고리(겹 수), 바닥 표식, 표적으로 모이는 줄기는 이 장르에서 흔한 짜임을 출발점으로 삼았다. 겉(톱니·못·갈라진 고리)은 이 지시서가 정했다. 나란히 견주는 일은 "후" 캡처를 본 뒤에 녹화 도구로 한다.

---

## 디렉터 판정 (2026-11-25, 총괄 디렉터. 담당의 보고로 읽음 — 구현을 배정할 때 묶음별 단락을 직접 읽는다)

지시서를 받는다.

1. **글**: 명세의 임시 이름을 화면에 옮기지 않는다. 사용자는 풀어 쓴 설명형 이름을 싫어한다(메모리 `naming-style-cool-not-literal`). narrative-lead가 이름과 한 줄을 먼저 짓고, 그것이 오면 ui-hud가 `ko.po`에 넣는다. 그때까지 A3은 키 글자가 보이지 않게 종류 낱말과 기호만으로 깨지지 않게 한다.
2. **시험 이름**: `element_kit`은 키트만 켠다. 측정과 같은 판은 `boss_finale,element_kit`. 트리의 기본은 `all`.
3. **트리 판(C)**: 사용자 플레이 뒤에 A10의 겉과 한 번에.
4. **차례**: ui-hud의 묶음(A0·A2·A3)은 `app/chapter_one.gd`·`chapter_hud.gd`·`hud_dump.gd`·`trial_docs.gd`를 고친다 — 캐릭터 선택의 R2(T13, 아직 main에 합치지 않음)와 같은 파일이다. **R2가 합쳐진 뒤에 배정한다.** 그 전에 갈 수 있는 것: vfx-feel의 A1(전투 중 표시), gameplay-systems의 `kit_view()` 더하기와 카드의 `open` 필드, narrative-lead의 이름.
