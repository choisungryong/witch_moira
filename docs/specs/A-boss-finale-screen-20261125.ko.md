# A-boss-finale-screen — 우두머리 싸움의 화면이 새 이벤트를 받게 한다 (2026-11-25, 0판)

아트 책임자(art-lead) 작성. 구현하지 않는다. 이 문서 말고는 아무 파일도 고치지 않았다. Godot는 돌리지 않았고 화면은 보지 않았다(이 지시서는 코드를 읽은 것만으로 썼다).

받는 사용자 지시(원문, `docs/DIRECTIVES-LEDGER.ko.md`):
- U-124: "보스를 만나고, 그런데 보스는 만만치 않고 물약은 초반에 너무 딸리고 힘들게 보스를 깨고"
- U-126: "1. 우두머리 버티는 구간에서 필살기는 통하도록"

받는 명세 절: `docs/specs/D-boss-finale-20261124.ko.md` 2.1절(국면 표), 3절(위험), 5.2절(이벤트), 7절 ③, 12·13절(디렉터 판정. 13절 "다음 ①"이 이 지시서). 켜는 장부 `boss_finale` 줄의 ②(화면이 알아야 할 이벤트)·④(앱 `_apply_trial`에 시험 이름).

표기: **[본 것]** 코드를 읽어 확인 · **[가설]** 이 지시서의 제안 · 다섯 요소 `[섹]` 섹시 · `[쾌]` 쾌감 · `[도]` 도박 · `[보]` 보상 · `[성]` 성장.

---

## 0. 목표 한 줄

**사용자가 `boss_finale`을 켠 판을 쳤을 때, 정지 화면 한 장을 0.5초 보고 "어디가 곧 터지는지, 지금 우두머리를 칠 수 있는지, 몇 국면째인지"를 말할 수 있다.** 효과는 더하되 주인공 위치와 세 계열(화염·냉기·번개)의 구분을 덮지 않는다.

### 0.1 반드시 읽혀야 하는 여섯

| # | 읽혀야 하는 것 | 받는 이벤트 | 키우는 요소 |
|---|---|---|---|
| R1 | **내리찍기 줄 전조**: 우두머리에서 10m 뻗는 폭 2m 줄, 1.2초 동안 뿌리에서 끝으로 차오름, 옆으로 비키면 산다 | `boss_telegraph{attack_id:"slam", shape:"line"}` + 엘리트의 `telegraph` 레코드 | `[쾌]` 읽고 피하는 맛. "왜 죽었는지 안다"(QUALITY 2절 사람 물음 4) |
| R2 | **착지 원**: 반지름 3m, 1.2초, "우두머리가 여기로 떨어진다" | `boss_telegraph{attack_id:"land"}`, `chapter_warning/burst{kind:"land"}` | `[쾌]` 고조 — 쉼이 끝나고 다시 붙는 순간 |
| R3 | **폭풍 다섯 자리**: 반지름 1.8m 원 다섯이 한꺼번에, 1초. 다섯이 한 묶음으로 보이고 그 사이 빈 길이 보인다 | `boss_telegraph{attack_id:"storm"}` ×5, `chapter_warning/burst{kind:"storm"}` | `[쾌]` 사이로 빠져나가기 · `[보]` 쉼 2의 물약이 숨통(물약은 지금의 물약 표시 그대로) |
| R4 | **"지금은 칠 수 없다"**: 우두머리가 뛰어올라 떠났고, 어디로 내려올지가 쉼 내내 보인다. 남은 시간이 보인다 | `boss_break_started{index, ticks, to, target_id}`, `boss_hit_blocked`, `boss_break_ended` | `[도]` 셋째 필살기를 쉼에 쓸까 국면에 쓸까 · `[쾌]` 호위를 쓸어버리는 시간으로 읽힘(답답함이 아니라) |
| R5 | **국면이 바뀜**: 1→2→3국면, 체력 막대의 어느 칸에 있는지, 3국면은 끝내기 | `boss_phase{phase, id}`, 체력 막대(`hp_raw`) | `[성]` 진척이 보임 · `[보]` "힘들게 깬다"의 끝이 다가옴 |
| R6 | **쉼에서 필살기가 들어감**: 칠 수 없던 몸에 강림만은 닿았다는 것이 몸과 막대 양쪽에서 보임 | `boss_break_struck`(gameplay-systems 작업 중, 필드 미정) | `[도]` 아껴 둔 한 방의 값 · `[쾌]` · `[섹]` 서약한 악마가 우두머리와 마주하는 장면(D-boss-finale BF7) |

어느 요소도 키우지 않는 것은 이번에 넣지 않는다: 호위 방향 표시(코어가 `boss_escort`를 내지 않음, 4절), 사슬 깎기 누계 숫자, 우두머리의 새 애니메이션 클립.

---

## 1. 지금 화면이 하는 것과 못 하는 것 [본 것]

코드를 읽은 그대로다. 켠 판의 화면은 보지 않았다(지금 앱으로는 켤 수 없다 — 1.3).

### 1.1 이미 되는 것

| 무엇 | 어디서 | 켠 판에서 |
|---|---|---|
| 우두머리 몸의 전조(원·부채꼴·줄) | `view/fx/chapter_effects.gd` `_sync_telegraphs` 314~361행. 엘리트(`e.elite`)는 바닥 전조를 그린다(`TELE_FLOOR_MIN_RANK` 1) | **내리찍기 줄이 이미 그려진다.** 코어가 `e.telegraph`를 `shape:"line"`, `rays:[]`로 덮어쓰므로(코어 `chapter_core.gd` 1946행) 350~357행의 캡슐 갈래(kind 1)로 간다 |
| 바닥 위험(`run.chapter_hazards`) | 같은 함수 362~369행. 모든 위험을 같은 꼴(원, 스타일 2 = 바닥 공격, 방사형 차오름)로 그린다 | **착지·폭풍·바닥 공격이 모두 그려지지만 셋이 똑같이 보인다.** 위험 레코드의 `kind`(ward/land/storm)를 읽지 않는다 |
| 전조의 색과 결 | `telegraph_look.gdshaderinc`(선 `TELE_LINE_RGB` 0.80,0.18,0.17, 바닥 `TELE_FILL_RGB`, 마지막 3틱 밝아짐), `telegraph_fill/edge.gdshader`(스텐실로 겹친 곳 한 번만 칠함) | 그대로 쓴다 |
| 물약 떨어짐 | `chapter_effects.gd` `_sync_potions` 634행(`run.potion_pickups`를 읽음) | 쉼 2의 물약(`boss_potion`)이 지금 물약 꼴로 보인다 |
| 우두머리 체력 막대 | `view/hud/chapter_hud.gd` 344~352행(막대·이름), 1385~1389행(값), 1601행(틀 그림). 채움 `Palette.THREAT_DEEP` | 체력 15,000이 그대로 찬다. **국면 눈금 없음, 쉼 표시 없음** |
| 큰 띠 | `chapter_hud.gd` `announce()` 185행. `kind=="boss"`면 위협색으로 한 번 밝힘 | — |
| 띠를 올리는 곳 | `app/chapter_one.gd` 727행 `chapter_champion` → "출현", 728행 `boss_phase` → "격노 · 낙인을 피하세요"(`hud.band.enraged`) + 카메라 0.6 | **문제**: 켠 판은 등장 2초 뒤 `boss_phase{phase:1,id:"p1"}`이 나오므로 싸움이 시작하자마자 "격노" 띠가 뜨고, 2·3국면에도 같은 "격노"가 뜬다(3절) |
| 우두머리 몸의 국면 색 | `view/actors/chapter_actors.gd` 864행이 `boss_phase`의 `phase`를 `_warden_phase`에 담고, 1171행이 2 이상이면 붉게 기움 | 켠 판은 2국면부터 붉다. 3국면의 따로 된 표시는 없다 |
| 우두머리 몸의 전조 동작 | 같은 파일 908~915행. 전조 진행을 `definition.windup`(54틱)으로 나눔 | 내리찍기(72틱)의 첫 18틱 동안 동작이 0에 머문다(1.2) |

### 1.2 안 되는 것

1. **착지·폭풍·바닥 공격이 같은 꼴이다.** 폭풍 다섯과 2국면 바닥 공격 셋을 정지 화면에서 가를 수 없다. 착지 원은 크기만 다르다.
2. **내리찍기 줄의 차오름이 틀린다.** `_sync_telegraphs` 322~324행은 진행을 `1 − remaining/definition.windup(54)`로 셈하는데 내리찍기의 전조는 72틱이다. 첫 18틱(0.3초) 동안 차오름이 0에 붙어 있다가 나머지 0.9초에 다 찬다. 전조가 실제보다 짧게 읽힌다. 몸 동작(`chapter_actors.gd` 913행)도 같은 셈이다.
3. **쉼이 화면에 없다.** 코어는 `boss_break_started`에서 우두머리를 착지 자리(`to`)로 **바로 옮긴다**(코어 1804행, 이벤트의 `position`도 `to`). 화면은 같은 틱에 몸이 9~12m 떨어진 곳으로 순간 이동하는 것으로 그린다(`chapter_actors.gd` 321~323행: 한 틱 0.85m 넘게 움직이면 미끄러지지 않고 튄다). 그리고 10초 동안 그 자리에 **멀쩡히 서 있다.** 플레이어는 칠 수 없는 몸을 계속 친다. 쏜 탄은 그 몸에 닿는 순간 사라진다(`combat_core.gd` 1350~1355행 `_shield_stops`).
4. **막힘이 화면에 없다.** `boss_hit_blocked`를 받는 곳이 없다(코어는 30틱에 한 번까지만 냄, `combat_core.gd` 139·1359행).
5. **터지는 순간이 없다.** `chapter_burst`는 소리만 받는다(`chapter_one.gd` 729행). 효과는 마지막 3틱의 선 밝아짐뿐이고 위험이 목록에서 빠지면 그냥 사라진다. 착지가 "쿵"이 아니다.
6. **등장 2초가 없다.** `boss_entrance`를 받는 곳이 없다. 무적인 2초 동안 몸이 평소처럼 보인다.
7. **국면 눈금·쉼 남은 시간·사슬 깎기 표시가 없다.**
8. **쉼의 필살기**(`boss_break_struck`)는 아직 코어에 없다. 지금 강림은 쉼의 우두머리를 고르지 않는다(코어 2694·2703행이 `_shield_id`를 뺀다). gameplay-systems가 U-126대로 바꾸는 중이다.

### 1.3 켠 판을 띄우는 길

- 앱 `_apply_trial`(`chapter_one.gd` 381~425행)이 아는 이름은 `spells, rhythm, descent, pace, grace, elites`다. **`boss_finale`은 없다.** 모르는 이름은 경고만 하고 버린다(392행).
- 인수 이름은 `--chapter1-trial=<이름,...>`이고 `--chapter1-profile-off`와 함께일 때만 먹는다(387행).
- 검사 도구 쪽에는 같은 일이 이미 있다: `chapter1/tests/support/trial_docs.gd` 49~57행 `enable_boss_finale_problem` — 리듬·오프닝·성장 속도(`TrialPace.apply`)·`boss_finale`을 **한 문서로** 켠다(측정의 켠 경로, 골든 사례 `boss-finale`과 같은 조합). 같은 파일 16행 `TRIAL_NAMES`가 앱의 이름 목록을 베껴 들고 있다.
- **우두머리 구간으로 바로 가는 검증용 인수는 없다.** 앱·코어·도구의 `--chapter1-*` 인수를 모두 훑었다(asset-slots, capture-dir, descent-*, frame-probe-*, fx-*, hero-models, no-juice, no-meteor-fx, opening, pilot, playlog, pool-*, primary, profile-off, qa-*, quit-after, seed, sfx-gain-db, start, trial, vat-walker). 비슷한 것은 검사 안의 무대뿐이다: `chapter1/tests/test_boss_finale.gd` 41~61행 `boss_run()`(구역 2로 옮기고 봉인 처치 수를 채워 우두머리를 바로 부름). 앱 인수로는 없다 → 4절.

---

## 2. 이벤트 → 화면 표

모든 표현은 이벤트와 읽기 전용 상태만 쓴다(`run.enemies`, `run.chapter_hazards`, `run.tick`, `run._champion_id`, 켠 판만 있는 `run._bf_state`·`run._bf_until`·`run._bf_to`·`run._bf`(데이터 블록)·`run._bf_chip`). 코어의 값을 쓰지 않는다. 새 그림 에셋 없이 도형·셰이더·지금 있는 키트 조각으로 먼저 한다.

**색의 규칙(한 색 한 뜻, `view/hud/palette.gd`)**: 곧 아픈 곳 = 지금의 전조 붉은색(`telegraph_look.gdshaderinc` 값, 팔레트 `THREAT` 계열) 하나뿐이다. "칠 수 없음·막힘"은 `Palette.LINEN`(실, 연결 — 고리 주문의 "막힘"이 이미 리넨으로 바램, `ring_spell_fx.gd` 220행)으로 한다. 국면 눈금은 `Palette.BRASS`/`BRASS_DIM`. 필살기가 들어간 순간만 주인공 원소색(`Palette.element_color`). 화염 주황은 적의 것에 쓰지 않는다(`chapter_effects.gd` 40행 규칙). 새 팔레트 토큰은 만들지 않는다.

**모양의 규칙**: 전조 넷은 **색을 지워도 모양으로** 갈린다(QUALITY 2절 정지 화면 3번의 뜻을 전조에도 건다).

| 받는 이벤트·필드 | 무엇을 어디에 그리나 | 담당 | 고칠 파일 |
|---|---|---|---|
| **`boss_telegraph{attack_id:"slam", shape:"line", position, direction, length, width, windup_ticks}`** + 엘리트 `telegraph` 레코드(`attack_kind=="slam"`) | 바닥: 지금의 캡슐(kind 1)을 쓰되 ① 차오름의 분모를 **이 이벤트의 `windup_ticks`(72)**로 고친다 — 우두머리가 하나뿐이므로 `attack_kind=="slam"`인 엘리트의 전조 길이를 이벤트에서 받아 둔다 ② 캡슐 안에 뿌리→끝 방향의 **꺾쇠(>) 셋**을 선 굵기로 새긴다(스타일 5 "돌진"). 꺾쇠는 차오름 앞쪽에서 끝쪽으로 흐르지 않고 제자리(정지 화면에서 방향이 읽혀야 함). 채움 알파는 `TELE_FILL_STRIKE` 0.28을 넘지 않는다. 몸: 전조 동작 진행도 같은 분모로(`chapter_actors.gd` 913행) | vfx-feel | `view/fx/chapter_effects.gd`(`_sync_telegraphs`), `view/fx/telegraph_common.gdshaderinc`, `telegraph_look.gdshaderinc`, `telegraph_fill.gdshader`, `telegraph_edge.gdshader`, `view/actors/chapter_actors.gd`(908~915행) |
| **`boss_telegraph{attack_id:"land", shape:"circle", radius 3.0, windup_ticks 72}`** · 위험 레코드 `kind:"land"` | 바닥: 원(반지름 3m). 차오름을 방사형이 아니라 **시계 방향으로 쓸어 도는 부채꼴**로(스타일 4 "착지": 12시에서 시작해 1.2초에 한 바퀴). 테두리 안쪽에 짧은 눈금 8개(사슬 고리 자리). 가운데에 우두머리의 **그림자 원**(어두운 반투명, 반지름 0 → 1.2m로 커짐)이 같이 자란다 — 위에서 떨어진다는 뜻 | vfx-feel | 위와 같음 + 새 파일 `view/fx/boss_finale_fx.gd`(그림자 원) |
| **`chapter_burst{kind:"land"}`** | 착지 자리에 먼지 고리 한 번(지금 `burst()`·`strokes`의 "ring" 결, 회색·리넨, 반지름 3m까지 0.35초) + 카메라 0.6(`_kick`) + 몸을 다시 보이게(아래 쉼 줄) | vfx-feel | `view/fx/boss_finale_fx.gd`, `chapter_effects.gd`(consume에 한 줄로 넘김) |
| **`boss_telegraph{attack_id:"storm"}` ×5** · 위험 레코드 `kind:"storm"` | 바닥: 원(반지름 1.8m), 방사형 차오름은 지금 바닥 공격과 같게, 대신 **테두리를 두 겹**(바깥 0.12m 띄운 가는 둘째 선, 스타일 3 "폭풍"). 다섯이 같은 틱에 뜨므로 묶음으로 읽힌다. 2국면 바닥 공격(한 겹 원 셋)과 정지 화면에서 갈린다. 원 안에 번개 갈래를 그리지 않는다(번개 계열의 꼴과 섞임) | vfx-feel | 바닥 전조 파일들(위와 같음) |
| **`chapter_burst{kind:"storm"}`** | 자리마다 작은 바닥 섬광 0.12초(지금 `hit` 강조의 크기), 카메라는 다섯 중 첫 하나만 0.15. 화면 전체 번쩍임 없음 | vfx-feel | `boss_finale_fx.gd` |
| `chapter_warning{kind:"ward"}`/`chapter_burst{kind:"ward"}` | 지금 그대로(한 겹 원, 방사형). 바뀌는 것 없음 | — | — |
| **`boss_entrance{ticks:120, target_id}`** | 몸: 등장 2초 동안 **흐린 몸**(알파 0.55, 채도 낮춤, 리넨 테두리 빛) — "아직 칠 수 없음"의 문법을 쉼과 같게. 발밑에 리넨 고리 하나가 2초에 걸쳐 닫힘(반지름 1.6m, 선만, 채움 없음). HUD: 체력 막대가 이때 뜨되(지금 `chapter_champion`에서 뜸) 쉼 표시(아래)를 같은 꼴로 2초 | vfx-feel(몸·고리) / ui-hud(막대) | `chapter_actors.gd`(1159~1172행 rig 알파·색), `boss_finale_fx.gd` / `chapter_hud.gd` |
| **`boss_break_started{index, ticks, to, target_id}`**, 위치 = `to` | **떠남**: 몸이 바로 전에 그려지던 자리(화면이 들고 있는 자리 — 코어는 이미 `to`로 옮겼다)에 먼지 고리 + 위로 솟는 짧은 줄기 0.3초, 카메라 0.45. **쉼 동안의 몸**: `to`에 흐린 몸(알파 0.25, 등장과 같은 결, 디렉터 결정 1) — 쏜 탄이 사라지는 자리가 허공이 되지 않게. **내려올 자리**: `to`에 **점선 원**(반지름 3m = 착지 반지름, 전조 붉은색 선만, 알파 0.35, 채움 없음)을 쉼 내내. 착지 전조(`boss_telegraph land`)가 뜨면 점선 원은 그 전조에 자리를 넘기고 사라진다. 점선 = "아직 아니다", 실선 + 채움 = "곧 아프다" | vfx-feel | `boss_finale_fx.gd`(먼지·점선 원 — 점선은 지금 전조 배치에 새 스타일로 넣거나 이 파일의 따로 된 쿼드로), `chapter_actors.gd`(쉼 동안 알파) |
| 같은 이벤트 | HUD: 체력 막대를 **잠긴 꼴**로 — 채움을 `THREAT_DEEP`에서 회색 쪽(`THREAT_DEEP`와 `SURFACE_RAISED`의 반반)으로 0.2초에 바꾸고 막대 왼끝에 리넨 사슬 고리 표(도형 두 개를 겹친 꼴, 12px). 막대 바로 아래에 **남은 시간 띠**(높이 4px, 리넨, `ticks`에서 0으로 줄어듦, 오른끝에 남은 초 정수 14px `INK_DIM`). 남은 시간은 `run._bf_until − run.tick`로 매 프레임 읽는다. 큰 띠: `index` 0 → 띠 자리 BF-T1(글귀 narrative-lead), `index` 1 → **지금의 `hud.band.enraged`를 여기로 옮긴다**("격노 · 낙인을 피하세요"는 폭풍의 쉼과 뜻이 맞는다) | ui-hud | `view/hud/chapter_hud.gd`, `app/chapter_one.gd`(띠) |
| **`boss_break_ended{index, target_id}`** | 몸: 흐린 몸 → 보통 몸으로 0.15초(착지 터짐과 같은 틱). HUD: 잠긴 꼴을 풀고 남은 시간 띠를 거둠 | vfx-feel / ui-hud | `chapter_actors.gd` / `chapter_hud.gd` |
| **`boss_hit_blocked{skill_id, target_id}`**(30틱에 한 번까지) | 몸: 맞은 자리(이벤트 위치 = 몸 위치)에 **리넨 고리 하나**(반지름 0.9m → 1.3m, 0.25초, 선만). 피해 숫자 없음, 붉은 번쩍임 없음, 카메라 없음. 화면이 받는 간격은 코어의 30틱 그대로 두되 **고리가 살아 있는 동안 새 고리를 겹치지 않는다**(같은 자리 0.25초에 하나). HUD: 막대 왼끝 사슬 고리 표가 0.15초 밝아짐(크기 그대로) | vfx-feel / ui-hud | `boss_finale_fx.gd` / `chapter_hud.gd` |
| **`boss_phase{phase, id}`** | 3절의 규칙. 몸: `phase` 3이면 2국면의 붉은 기울기(`chapter_actors.gd` 1171행)에 더해 리넨이 아니라 전조 붉은색의 가장자리 빛(rim)을 조금 올림 — "끝내기". HUD: 막대의 지금 칸 바탕이 살짝 밝아짐(아래 막대 줄) | vfx-feel(몸) / ui-hud(띠·막대) | `chapter_actors.gd` / `chapter_one.gd`, `chapter_hud.gd` |
| 체력 막대(매 프레임, `run._bf.phases[].to_hp_bps`) | **국면 눈금**: 막대 위에 세로 눈금 2개(65%·30% 자리 — 숫자를 코드에 적지 않고 데이터 블록에서 읽는다). 두께 2px, 막대 높이보다 위아래로 3px 더 나옴, 아직 안 지난 눈금 `BRASS`, 지난 눈금 `BRASS_DIM`. 지금 칸의 바탕만 한 단계 밝게. 켠 판(`run._bf_on`)에서만 그린다 — 꺼진 판의 막대는 한 픽셀도 바뀌지 않는다 | ui-hud | `chapter_hud.gd`(막대 그리기 — 키트 틀을 그리는 `_draw_boss_caps` 1601행 옆에 같은 방식으로) |
| **`boss_chip{bps, total_bps}`** | HUD: 채움 끝에 리넨 반짝 0.3초(폭 = `bps` 만큼의 픽셀, 최소 2px). 숫자 없음 | ui-hud | `chapter_hud.gd` |
| **`boss_potion{position, index}`** | 지금의 물약 꼴이 그대로 보인다(`_sync_potions`). 더하는 것: 떨어지는 순간 물약 자리에 작은 빛 고리 한 번 0.3초(물약 색 `c1494e` 결 — 지금 물약 쿼드와 같은 색) | vfx-feel | `boss_finale_fx.gd` |
| **`boss_break_struck`**(필드 미정, gameplay-systems 작업 중) | 몸: 흐린 몸이 0.5초 동안 보통 몸으로 돌아오며 **주인공 원소색**의 테두리 빛 + 비틀거림(지금 맞음 흔들림, `chapter_actors.gd` 934~940행 결을 두 배로) + 카메라 0.5. 리넨 막힘 고리는 이 틱에 띄우지 않는다. HUD: 체력 막대가 깎이는 것은 `hp_raw`로 저절로 보인다. 더해서 사슬 고리 표가 0.4초 갈라짐(두 고리가 벌어짐) — "막힌 몸에 들어갔다". 큰 띠는 없다(강림의 컷인이 이미 그 자리를 씀) | vfx-feel / ui-hud | `boss_finale_fx.gd`, `chapter_actors.gd` / `chapter_hud.gd` |

### 2.1 겹침과 뿌옇게 됨을 막는 규칙

- 바닥 전조의 채움은 지금처럼 스텐실로 한 번만 칠한다. 새 스타일 셋(3 폭풍, 4 착지, 5 돌진)도 같은 배치(`_tele_mm`, 최대 96)에 들어간다. 쉼 2에서 한 번에 나오는 것은 폭풍 다섯 + 착지 하나 + 점선 원 하나가 가장 많다.
- 점선 원·그림자 원·리넨 고리는 **채움 없음** 또는 알파 0.35 이하. 착지 전조가 뜬 뒤에는 점선 원이 없다(둘이 같은 자리에 겹치지 않는다).
- 터짐 효과는 모두 0.35초 이하. 화면 전체 색 덮기·화면 번쩍임은 이 지시서에서 하나도 쓰지 않는다.
- 전조는 주문 효과 위에 그려진다(지금 `render_priority` 10~12, 강림 바닥 표시는 -4 — `descent_fx.gd` 544행). 새 것도 이 순서를 지킨다: 점선 원·그림자 원은 전조와 같은 층(10 근처), 리넨 고리·먼지는 그 아래.

---

## 3. `boss_phase`가 1국면에도 나오는 문제, 막힘의 간격

### 3.1 띠 규칙 [가설, ui-hud가 `app/chapter_one.gd` 728행을 바꿈]

| 이벤트 | 지금 | 바꾼 뒤 |
|---|---|---|
| `chapter_champion`(구역 2) | "출현" 띠 + 카메라 0.45 | 그대로 |
| `boss_phase{phase:1, id:"p1"}`(켠 판, 등장 2초 뒤) | "격노" 띠 + 카메라 0.6 | **띠 없음, 카메라 없음.** 등장 띠가 막 지나간 뒤라 또 띠를 올리지 않는다 |
| `boss_break_started{index:0}` | 없음 | 띠 자리 BF-T1(글귀 narrative-lead. 글이 오기 전에는 띠 없음 — 화면의 잠긴 막대·점선 원이 대신 읽힘) |
| `boss_phase{phase:2, id:"p2"}` | "격노" | 띠 자리 BF-T2(글귀 narrative-lead. 오기 전에는 띠 없음) + 카메라 0.4 |
| `boss_break_started{index:1}` | 없음 | **"격노 · 낙인을 피하세요"(`hud.band.enraged`, 지금 있는 글)** + 카메라 0.6 |
| `boss_phase{phase:3, id:"p3"}` | "격노" | 띠 자리 BF-T3(narrative-lead. 오기 전에는 띠 없음) + 카메라 0.4 |
| `boss_phase{phase:2}`, `id` 없음(꺼진 판, 옛 50% 전환) | "격노" | **그대로**(꺼진 판의 화면은 바꾸지 않는다) |

가르는 기준은 `event.has("id")`다(꺼진 판의 이벤트에는 `id`가 없다 — 코어 1731행과 1793행을 견줘 확인).

띠의 자리(위치·크기)는 지금 `announce()` 그대로다. 체력 막대가 떠 있으면 이름판 아래로 내려간다(193행). 띠는 하나씩만 뜬다(새 띠가 옛 띠를 치움).

### 3.2 막힘(`boss_hit_blocked`)

- 코어는 30틱(0.5초)에 한 번까지만 낸다. 화면은 이것을 더 걸러 **0.25초짜리 리넨 고리 하나**와 HUD 사슬 고리 표의 0.15초 밝아짐만 한다. 쉼 10초 동안 최대 20번이다.
- 하지 않는 것: 피해 숫자 "0"이나 "막힘" 글자, 붉은색, 몸 흔들림, 카메라, 화면 번쩍임, 매번 다른 크기. 막힘은 "왜 안 깎이지"를 막는 작은 대답이지 사건이 아니다.
- 소리는 audio-lead(6절). 화면이 소리를 대신해 크게 만들지 않는다.

---

## 4. 앱에서 켜는 길, 우두머리 바로가기

### 4.1 `--chapter1-trial=boss_finale` (ui-hud, 첫 단계로 먼저)

- `app/chapter_one.gd` `_apply_trial`의 이름 목록(391·392행)에 `boss_finale`을 더한다. 켜는 것은 **`trial_docs.gd` `enable_boss_finale_problem`과 같은 조합**: 리듬 + 오프닝 + 성장 속도(`TrialPace.apply`) + `boss_finale.enabled`. 측정(BF-B)과 골든 사례 `boss-finale`이 쓴 경로와 같아야 사용자가 친 판과 잰 판이 같은 게임이다.
  - 지금 397~411행의 "한 문서를 한 번 읽고 한 번 넘긴다" 흐름 안에 넣는다(리듬·엘리트·속도·은총과 같은 문서). `boss_finale`이 있으면 `rhythm`과 `pace`를 함께 켠 것으로 본다.
  - 구현을 두 번 쓰지 않는다: 가능하면 앱이 `TrialDocs`의 같은 함수를 부르게 하되, 앱이 `tests/` 파일을 preload하는 것이 맞지 않으면 앱 쪽에 함수 하나를 두고 `trial_docs.gd`가 그것을 부르게 한다(어느 쪽인지는 refactor 판단, ui-hud가 보고에 적는다).
- `chapter1/tests/support/trial_docs.gd` 16행 `TRIAL_NAMES`에 `boss_finale`을 더한다(캡처 머리의 스위치 목록이 `trial:?boss_finale`로 찍히지 않게).
- 창 제목에 이미 시험 이름이 붙는다(449행). 그대로.
- 사용자 실행 예(문서에 적을 줄):
  `python tools/dev/run_dev.py -- --chapter1-start --chapter1-profile-off --chapter1-trial=boss_finale --chapter1-primary=chapter1.skill.ember`

### 4.2 우두머리 바로가기 — **없다. 필요하다**

사용자가 우두머리까지 약 6분 반(판 길이 431~457초, BF-D1)을 쳐야 한 번 볼 수 있다. 쉼·폭풍을 되풀이해 보려면 바로가기가 필요하다. 코어를 건드리는 일이라 이 지시서는 **gameplay-systems에 넘길 일로만 적는다**:

- 바라는 것: `--chapter1-profile-off`와 함께일 때만 먹는 검증용 인수(이름은 gameplay-systems가 정함, 예 `--chapter1-qa-boss`). 판을 시작하자마자 구역 2·마지막 봉인 처치 수 채움·우두머리 등장 상태로 둔다. 레벨·카드는 자동 조작이 한 판을 친 것과 비슷한 꼴로(아니면 맨몸이 바로 우두머리를 만나 사용자가 "너무 아프다"를 잘못 읽는다 — 이 차이를 사용자에게 알리는 글을 창 제목 태그에 붙임).
- 출발점: `tests/test_boss_finale.gd` 41~61행 `boss_run()`의 무대.
- 문: 인수가 없으면 아무것도 바뀌지 않음, 골든 9사례 해시 불변.
- 이것이 없어도 이 지시서의 화면 일과 검수는 돌아간다(자동 조작 한 판 + `--burst`).

---

## 5. 화면에 들어갈 글 — 자리만

글귀는 narrative-lead가 쓴다. 화면 담당은 키와 자리만 만들고, 글이 오기 전에는 그 띠를 띄우지 않는다(빈 글 띠나 임시 글을 화면에 내지 않는다).

| 자리 | 키(제안) | 길이 | 뜻(narrative-lead에게) |
|---|---|---|---|
| BF-T1 쉼 1 시작 | `hud.band.boss_break1` | 큰 띠 부제 한 줄, 한국어 14자 안팎 | 우두머리가 사슬 하나를 끊고 뛰어 물러남. "지금은 칠 수 없고 곧 내려온다"가 읽혀야 함(D-boss-finale 4절, `ENEMY-ROSTER` 3.3 "쇠고랑이 끊어짐") |
| BF-T2 2국면 시작 | `hud.band.boss_phase2` | 같음 | 다시 붙음, 돌진이 섞이기 시작 |
| BF-T3 3국면 시작 | `hud.band.boss_phase3` | 같음 | 일대일, 끝내기 |
| 쉼 2 시작 | `hud.band.enraged`(있음) | — | 지금 글 "격노 · 낙인을 피하세요"를 그대로 쓴다. 바꿀지는 narrative-lead가 판단 |

띠의 제목(윗줄)은 지금처럼 우두머리 이름(`enemy.champion.2.name`)이다. 새 이름·새 대사를 짓지 않는다. 분위기 낱말("잿빛" 등)을 쓰지 않는다.

---

## 6. 소리 — audio-lead에 넘길 이벤트 목록만

화면 담당은 소리를 만들지 않는다. audio-lead가 `docs/AUDIO-PLAN.ko.md` 기준으로 정한다. 지금 `chapter_burst`만 `audio_routes.late`로 소리를 낸다(`chapter_one.gd` 729행).

| 이벤트 | 화면이 하는 것(소리와 맞출 자리) |
|---|---|
| `boss_entrance` | 흐린 몸, 리넨 고리가 2초에 닫힘 |
| `boss_phase{id:p2/p3}` | 띠·카메라 0.4 |
| `boss_break_started{index:0/1}` | 떠나는 먼지·솟는 줄기, 막대 잠김. index 1은 "격노" 띠 |
| `boss_break_ended` | 착지 터짐과 같은 틱 |
| `boss_telegraph{attack_id:slam/land/storm}` | 줄·착지 원·폭풍 다섯의 전조 시작(소리로 셋이 갈려야 함 — 특히 폭풍과 바닥 공격) |
| `chapter_burst{kind:land/storm/ward}` | 착지 쿵·폭풍 섬광·바닥 공격 |
| `boss_hit_blocked` | 리넨 고리(작게) |
| `boss_chip` | 막대 끝 반짝 |
| `boss_potion` | 물약 빛 고리 |
| `boss_break_struck` | 몸이 원소색으로 드러남·비틀거림 |

---

## 7. 검수 방법

### 7.1 캡처 명령 (저장소 루트에서, art-lead가 직접 돌린다)

1920×1080:
```
python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.ember --chapter1-trial=boss_finale --wall-limit=2400 --shots=_local/shots/bf-screen-<전|후>-1080 --dump=_local/shots/bf-screen-<전|후>-1080.json --burst=boss_entrance,boss_telegraph:attack_id=slam,boss_break_started:index=0,boss_telegraph:attack_id=land,chapter_burst:kind=land,boss_phase:id=p2,boss_break_started:index=1,boss_telegraph:attack_id=storm,boss_hit_blocked,boss_phase:id=p3,boss_break_struck --burst-frames=12 --burst-step=6
```
1280×720: 같은 줄에서 `--resolution 1280x720`, 폴더 이름 `-720`.

- `--burst`는 이름마다 **첫** 이벤트 뒤 12장(0.1초 간격, 1.2초)을 뜬다(`tests/burst_capture.gd`). 전조 하나의 차오름 전체가 들어간다. 만나지 못한 이름은 마지막 줄 `HUD_BURST_SUMMARY`에 나온다 — 거기 있는 이름은 "보지 않음"으로 적는다.
- `boss_break_struck`은 강림이 켜져야 나온다. 그 장면은 `--chapter1-trial=boss_finale,descent --descent=now`(도구의 강림 누름 규칙, `hud_dump.gd` 109~111행)로 따로 한 번 더 뜬다. 강림 컷인 동안은 버스트가 기다린다(`burst_capture.gd` 145행).
- 계열은 화염 시드 11(골든 `boss-finale`과 같음)을 기준으로, 냉기·번개는 시드 11로 1080만 한 번씩(세 계열의 주문 효과 위에서 전조가 읽히는지).
- 한 판이 약 7~8분이라 `--wall-limit=2400`. 4.2절의 바로가기가 들어오면 그것으로 바꾼다.

### 7.2 "전"과 "후"

지금 앱은 `boss_finale`을 켤 수 없으므로 지금 main에서 뜬 "전"은 꺼진 판이라 견줄 수 없다. 그래서 **ui-hud의 4.1(시험 이름)만 먼저 합치고**, 그 상태에서 위 명령으로 "전"을 뜬다. 그 뒤 두 담당의 화면 일을 합친 상태에서 같은 시드·같은 인수로 "후"를 뜬다. 자동 조작과 코어가 같으므로 버스트 장면의 틱이 전후에 같다(같은 틱의 장을 나란히 놓는다).

### 7.3 볼 장면과 통과 기준

정지 화면 한 장을 **0.5초 보고** 아래를 말할 수 있으면 통과. art-lead가 1080·720 둘 다 직접 본다. 같은 장을 흑백으로 바꿔 한 번 더 본다(모양만으로 갈리는지).

| 장면(버스트 이름) | 볼 장 | 0.5초에 말할 것 | 반려 조건 |
|---|---|---|---|
| 등장 `boss_entrance` | 1·6·12장 | 우두머리가 어디 있고 아직 칠 수 없다 | 몸이 평소와 같음 |
| 내리찍기 `boss_telegraph:attack_id=slam` | 1·4·8·12장 | 줄의 방향과 끝, 얼마나 찼는지. 첫 장(0.0초)에도 줄이 있고, 4장(0.3초)에 차오름이 4분의 1쯤 | 4장에서 차오름이 0(분모 틀림이 남음), 줄이 주문 효과에 덮임 |
| 쉼 시작 `boss_break_started:index=0` | 1·3·12장 | 우두머리가 떠났다(옛 자리의 먼지), 어디로 내려올지(점선 원), 칠 수 없다(흐린 몸·잠긴 막대), 남은 시간 | 몸이 `to`에 보통 몸으로 서 있음, 점선 원이 실선 전조처럼 보임 |
| 착지 전조 `boss_telegraph:attack_id=land` | 1·6·12장 | 3m 원, 쓸어 도는 차오름, 그림자 원 | 폭풍·바닥 공격과 모양이 같음 |
| 착지 터짐 `chapter_burst:kind=land` | 1·3장 | 우두머리가 돌아왔다, 막대가 풀렸다 | 화면 전체가 흐려짐 |
| 2국면 `boss_phase:id=p2` | 1·6장 | 눈금 하나를 지났다, 띠(글이 있으면) | 1국면 시작에 띠가 뜸(전 캡처의 `boss_phase` 첫 이벤트를 따로 확인) |
| 쉼 2·폭풍 `boss_break_started:index=1`, `boss_telegraph:attack_id=storm` | 1·6·12장 | "격노" 띠, 다섯 자리가 한 묶음, 사이의 빈 길, 물약 자리 | 2국면 바닥 공격 셋과 흑백에서 같은 꼴, 다섯 원이 겹친 곳이 진해짐 |
| 막힘 `boss_hit_blocked` | 1·3장 | 쏜 것이 튕겼다(작은 리넨 고리) | 붉은 번쩍임, 숫자, 고리가 몸보다 큼 |
| 3국면 `boss_phase:id=p3` | 1·6장 | 마지막 칸이다 | — |
| 쉼의 필살기 `boss_break_struck` | 1·4·8장 | 칠 수 없던 몸에 들어갔다(원소색 테두리, 막대가 깎임, 사슬 표 갈라짐) | 막힘 고리가 같이 뜸 |

모든 장에 공통: 주인공을 1초 안에 짚는다(QUALITY 2절 1번), 전조가 주문 효과에 가려지지 않는다(2번), HUD가 720에서 겹치거나 잘리지 않고 화면 가운데 60%×60%를 가리지 않는다(3절 해상도·가림). 막대의 눈금·남은 시간 띠·사슬 표가 키트 틀(`boss_frame`) 밖으로 비어져 나오지 않는다.

### 7.4 정지 화면으로 판단할 수 없는 것

착지 그림자가 "떨어진다"로 느껴지는지, 막힘 고리 20번이 거슬리는지, 폭풍 다섯의 차오름 속도가 피할 만해 보이는지, 카메라 흔들림의 세기, 소리와의 맞음. 이것은 사용자가 켠 판을 칠 때만 판정한다(켜는 장부 ⑧).

### 7.5 돌릴 검사(구현 담당이, 그리고 검수 때 art-lead가 본 저장소에서 다시)

- 골든: `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd` — **해시 불변**(표현만 고침. 바뀌면 반려).
- 회귀: `python tools/dev/run_all.py --quick`.
- 시험 이름: `chapter1/tests/trial_state_probe.gd`에 `--chapter1-trial=boss_finale --chapter1-profile-off`로 돌려 코어의 `boss_finale`·`rhythm`이 켜졌는지(ui-hud).
- 꺼진 판의 화면 불변: 위 7.1 명령에서 `--chapter1-trial`과 `--burst`를 뺀 기본 덤프(냉기 시드 11, 1080)를 고치기 전과 뒤에 떠서 JSON이 바이트까지 같아야 한다(막대 눈금·쉼 표시가 켠 판에서만 생기는지).
- 셰이더 컴파일: 위 캡처 실행의 출력에 셰이더 오류가 없어야 한다.

---

## 8. 배정문 초안

두 담당이 고치는 파일은 겹치지 않는다(아래 표). `app/chapter_one.gd`는 ui-hud만, `view/actors/chapter_actors.gd`는 vfx-feel만 고친다. 카메라 흔들림: `boss_phase`의 것은 `chapter_one.gd`(ui-hud, 3.1표의 값), 나머지 새 이벤트의 것은 `chapter_effects.gd`의 `_kick`(vfx-feel). 같은 이벤트에 둘이 함께 흔들지 않는다.

| 파일 | vfx-feel | ui-hud |
|---|---|---|
| `chapter1/view/fx/chapter_effects.gd` | 고침(`_sync_telegraphs`의 위험 `kind`·돌진 분모, consume/sync에서 새 파일로 넘김) | — |
| `chapter1/view/fx/boss_finale_fx.gd`(새 파일) | 새로 씀 | — |
| `chapter1/view/fx/telegraph_common.gdshaderinc`, `telegraph_look.gdshaderinc`, `telegraph_fill.gdshader`, `telegraph_edge.gdshader` | 고침(스타일 3·4·5, 점선) | — |
| `chapter1/view/actors/chapter_actors.gd` | 고침(흐린 몸, 3국면 빛, 돌진 동작 분모, 필살기 드러남) | — |
| `chapter1/view/hud/chapter_hud.gd` | — | 고침(막대 눈금·잠김·남은 시간·사슬 표·깎임 반짝) |
| `chapter1/app/chapter_one.gd` | — | 고침(`_apply_trial`에 `boss_finale`, 띠 규칙, HUD에 이벤트 넘김) |
| `chapter1/tests/support/trial_docs.gd` | — | 고침(`TRIAL_NAMES`) |
| `chapter1/i18n/ko.po`, `en.po` | — | narrative-lead의 글이 온 뒤에만 키 셋 더함 |
| `chapter1/view/hud/palette.gd` | 읽기만 | 읽기만(새 토큰 없음) |

HUD가 받는 이벤트(`boss_break_started` 등)는 `chapter_one.gd`의 `_consume_events`에서 `hud`의 새 함수 하나(예 `hud.boss_event(event)`)로 넘긴다. 효과는 이미 `effects.consume(run.events)`로 모든 이벤트를 받으므로(`chapter_one.gd` 268행) `chapter_one.gd`를 건드릴 필요가 없다.

### 8.1 vfx-feel

> 지시서 `docs/specs/A-boss-finale-screen-20261125.ko.md` 2절 표의 vfx-feel 줄, 2.1절, 3.2절을 구현한다. 작업 폴더에서 하고 패치와 보고서를 낸다.
>
> 고칠 파일: `chapter1/view/fx/chapter_effects.gd`, 새 파일 `chapter1/view/fx/boss_finale_fx.gd`(고리 주문 `ring_spell_fx.gd`·`meteor_fx.gd`처럼 `chapter_effects.gd`의 `consume()`·`sync()` 끝에서 부른다), `chapter1/view/fx/telegraph_common.gdshaderinc`·`telegraph_look.gdshaderinc`·`telegraph_fill.gdshader`·`telegraph_edge.gdshader`, `chapter1/view/actors/chapter_actors.gd`. 다른 파일은 고치지 않는다(`chapter_one.gd`·`chapter_hud.gd`는 ui-hud). `view/` 바로 아래의 옛 층(`cloister_*.gd`, `chapter_world_quality*.gd`)에 넣지 않는다.
>
> 할 일: ① 바닥 위험을 `kind`로 가름 — ward 그대로, storm 두 겹 테두리(스타일 3), land 쓸어 도는 차오름 + 테두리 눈금 8(스타일 4) ② 내리찍기 줄: 차오름·몸 동작의 분모를 `boss_telegraph.windup_ticks`로, 캡슐 안 꺾쇠 셋(스타일 5) ③ 등장·쉼의 흐린 몸(등장 알파 0.55, 쉼 0.25), 떠남의 먼지·솟는 줄기, `to`의 점선 원(착지 전조가 뜨면 사라짐), 착지 그림자 원, 착지 터짐의 먼지 고리 ④ 막힘의 리넨 고리(0.25초, 겹치지 않음) ⑤ 3국면의 몸 가장자리 빛 ⑥ 폭풍 터짐의 작은 섬광, 물약 빛 고리 ⑦ `boss_break_struck`(필드는 gameplay-systems의 합침을 보고 맞춘다. 합치기 전이면 이 항목만 비워 두고 보고에 적는다).
>
> 지킬 것: 표현은 이벤트와 읽기 전용 상태만 쓴다(코어의 값을 쓰지 않음). 꺼진 판(`run._bf_on` 거짓)에서는 그림이 하나도 바뀌지 않는다 — 착지·폭풍 스타일 갈래도 위험 레코드에 `kind`가 있을 때만 탄다(꺼진 판의 바닥 공격에는 `kind`가 없다, 코어 1746행). 전조 붉은색 외의 붉은색을 쓰지 않고, 화면 전체 번쩍임을 쓰지 않는다. 새 그림 에셋 없음. 수치(반지름·전조 길이)는 이벤트·위험 레코드에서 읽고 코드에 적지 않는다.
>
> 검사: 골든 불변, `run_all.py --quick`. 보고에 지시서 7.1의 명령으로 뜬 1080 캡처 폴더 경로를 적는다(판정은 art-lead가 한다).
>
> 다섯 요소: `[쾌]` 읽고 피하는 맛과 착지의 고조, `[도]` 쉼의 필살기, `[섹]` 악마가 우두머리에게 닿는 순간.

### 8.2 ui-hud

> 지시서 `docs/specs/A-boss-finale-screen-20261125.ko.md` 4.1절을 **먼저 따로** 내고(art-lead가 이것으로 "전" 캡처를 뜬다), 이어서 2절 표의 ui-hud 줄과 3.1절을 구현한다. 작업 폴더에서 하고 패치와 보고서를 낸다.
>
> 고칠 파일: `chapter1/app/chapter_one.gd`(`_apply_trial`, `_consume_events`의 띠 규칙과 HUD로 넘김), `chapter1/view/hud/chapter_hud.gd`, `chapter1/tests/support/trial_docs.gd`(`TRIAL_NAMES`만). `chapter1/i18n/*.po`는 narrative-lead의 글이 온 뒤에만. 효과·몸 파일(`view/fx/`, `view/actors/`)은 고치지 않는다(vfx-feel).
>
> 할 일: ① `--chapter1-trial=boss_finale` — `trial_docs.gd` `enable_boss_finale_problem`과 같은 조합(리듬·오프닝·속도·우두머리)을 한 문서로. 같은 구현을 두 곳에 쓰지 않는 방법을 보고에 적는다 ② 3.1절 띠 규칙(`event.has("id")`로 켠 판을 가름, 꺼진 판은 그대로, 글이 없는 자리는 띠를 띄우지 않음) ③ 체력 막대: 국면 눈금(데이터 `to_hp_bps`에서 읽음), 지금 칸 바탕, 쉼의 잠긴 꼴과 사슬 고리 표, 남은 시간 띠와 초, 막힘·깎임·필살기 때 표의 반응 ④ 등장 2초도 잠긴 꼴.
>
> 지킬 것: 켠 판에서만 그린다 — 꺼진 판의 `hud_dump` 기본 덤프가 바이트까지 같아야 한다(지시서 7.5). 색은 `palette.gd`의 지금 토큰만(새 토큰 없음). 1280×720에서 막대·띠·남은 시간이 키트 틀 밖으로 나가거나 경로판(`_route40`)과 겹치지 않는다. 큰 띠는 지금 `announce()`의 자리·크기 그대로.
>
> 검사: 골든 불변, `run_all.py --quick`, `trial_state_probe.gd`로 시험 이름 확인, 꺼진 판 덤프 비교. 보고에 1080·720 캡처 폴더 경로.
>
> 다섯 요소: `[성]` 국면 진척이 보임, `[보]` 힘들게 깨는 끝이 다가옴, `[도]` 쉼 남은 시간을 보고 필살기를 고름.

---

## 9. 코어 쪽에 더 필요한 것 (gameplay-systems에 넘김, 이 지시서는 막지 않음)

1. **우두머리 바로가기 인수**(4.2). 없으면 사용자 플레이가 매번 6분 반.
2. **`boss_break_struck`의 필드 확정**. 화면이 바라는 것: `{target_id, skill_id 또는 element, damage(또는 bps), position}`. 원소색을 고르려면 원소를 알 수 있어야 한다.
3. (선택) `boss_escort {index, count}` — 명세 5.2절 표에 있으나 코어가 내지 않는다(`_emit("boss_escort"` 없음). 호위 방향 표시는 이번에 하지 않으므로 급하지 않다.
4. (선택) 켠 판의 읽기 전용 상태를 한 함수로(예 `boss_finale_view()` → `{state, phase_index, break_until, to, chip_bps, thresholds}`). 지금은 HUD가 `run._bf_state` 같은 밑줄 이름을 직접 읽어야 한다(지금도 `run._champion_id`를 그렇게 읽고 있어 막지는 않음). 상태를 바꾸지 않는 함수라 골든에 닿지 않는다.
5. 내리찍기의 `e.telegraph`에 전조 길이가 없다. 화면은 이벤트의 `windup_ticks`로 맞추므로 코어를 바꾸지 않아도 된다(바꾸면 켠 경로 골든의 스냅숏이 바뀔 수 있어 권하지 않음).

---

## 10. 디렉터가 정할 것

1. **쉼 동안 우두머리의 몸**: 흐린 몸(알파 0.25)으로 `to`에 보인다(권고 — 쏜 탄이 허공에서 사라지지 않고, 내려올 자리가 몸으로도 읽힘) / 아예 숨긴다(떠났다는 느낌은 더 강하나 탄이 보이지 않는 벽에 사라짐).
2. **글이 오기 전의 띠**: 쉼 1·2국면·3국면은 글이 올 때까지 띠 없이 내보내고 쉼 2만 지금의 "격노" 글을 쓴다(권고) / narrative-lead의 글을 기다렸다가 함께 낸다.
3. **우두머리 바로가기를 사용자 플레이 전에 둘지**: gameplay-systems에 이 화면 일과 나란히 배정(권고) / 사용자가 처음은 한 판 전체를 치고 그 뒤에.

---

## 11. 읽은 것, 읽지 못한 것

**읽은 것**: `DIRECTIVES-LEDGER` U-124·U-126 줄과 켜는 장부 `boss_finale` 줄, `D-boss-finale-20261124` 전부, `QUALITY-TARGETS` 2·3·5절, `chapter_core.gd` 640~667행(우두머리 생성)·1710~1956행(우두머리 국면 전체)·3126~3132행(스냅숏), `combat_core.gd` 1349~1375행(막힘), `chapter_one.gd` 370~449행(`_apply_trial`)·711~732행(이벤트), `chapter_effects.gd` 30~75·230~256·295~404·625~650행과 consume/sync 진입점, `telegraph_look.gdshaderinc` 전부·`telegraph_common.gdshaderinc` 앞부분, `chapter_actors.gd` 310~328·810~942·1144~1175행, `chapter_hud.gd` 178~207·1365~1458·1590~1633행, `palette.gd` 전부, `hud_dump.gd` 1~300행, `burst_capture.gd`의 이름 맞춤 규칙, `trial_docs.gd` 전부, `test_boss_finale.gd` 40~75행, `i18n/ko.po`의 띠 글.

**읽지 못했거나 확인하지 못한 것**:
- 화면은 보지 않았다(지금 앱으로 켠 판을 띄울 수 없고, 이번에 Godot를 돌리지 않았다). 1.1·1.2는 코드를 읽은 것이다. 특히 "쉼 동안 몸이 `to`에 그대로 서 있음"은 코드로 읽은 것이고 캡처로 확인하지 않았다.
- `telegraph_fill.gdshader`·`telegraph_edge.gdshader`의 본문(스타일 값이 어떻게 갈리는지)은 앞부분만 읽었다. 새 스타일 셋을 넣을 자리는 vfx-feel이 본다.
- `combat_juice.gd`가 우두머리에게 무엇을 하는지(피해 숫자 외)는 확인하지 않았다. 막힘에는 피해 이벤트가 없으므로 숫자는 뜨지 않을 것으로 읽는다.
- `presentation/combat_audio.gd`·`audio_routes`가 `chapter_burst`의 `kind`를 가르는지는 보지 않았다(소리는 audio-lead).
- `boss_break_struck`은 아직 코어에 없어 필드를 모른다.
- `SEASON1_WORLD_STORY_MASTER.md`, `ENEMY-ROSTER` 3.3절 본문은 읽지 않았다(띠 글의 뜻은 D-boss-finale 4절의 인용만).

---

## 12. 디렉터 판정 (2026-11-25, 총괄 디렉터. 8~10절을 직접 읽고 나머지는 담당의 보고로 읽음)

지시서를 받는다. 10절의 셋은 모두 권고대로 정한다.

1. 쉼 동안 우두머리의 몸은 내려올 자리(`to`)에 흐린 몸(알파 0.25)으로 보인다.
2. 글이 오기 전에는 쉼 1·2국면·3국면에 띠를 띄우지 않고, 쉼 2에만 지금의 "격노" 글을 쓴다. 글 자리 셋은 narrative-lead에 넘긴다.
3. 우두머리 바로가기는 화면 일과 나란히 간다. **파일이 겹치지 않게 나눈다**: 코어 쪽 길(저장이 꺼진 판에서만 먹는 건너뛰기 함수와 읽기 전용 상태 함수 `boss_finale_view()`, `boss_break_struck`의 필드)은 gameplay-systems가 `chapter1/core/`와 `tests/`에서 만들고 `app/chapter_one.gd`는 건드리지 않는다. 실행 인수를 그 함수에 잇는 일은 ui-hud가 `app/chapter_one.gd`에서 한다(함수가 아직 없으면 `has_method`로 건너뛰게).

사용자 지시(U-126) 반영: 쉼에서 필살기가 우두머리에게 들어간다. 2절 표의 `boss_break_struck` 줄이 그 순간이다.
