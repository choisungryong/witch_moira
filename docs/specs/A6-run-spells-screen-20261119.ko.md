# A6-RS — 판 안 스킬 구성(run_spells)을 켜기 전의 화면 지시서

- 작성: art-lead, 2026-11-19. 읽기만 하고 썼다. **Godot는 돌리지 않았다** — 이 문서의 화면 서술은 모두 코드를 읽고 한 것이며 캡처를 보지 않았다.
- 받는 장부 줄: `docs/DIRECTIVES-LEDGER.ko.md` 2절 `run_spells.json enabled`의 남은 일 **④ 화면: 새 주문 셋의 이름·아이콘·효과, 카드 종류, 새 이벤트**. ⑤ 소리는 이 문서의 RS5가 **목록만** 넘긴다.
- 기준 명세: `docs/specs/D12-skill-and-gear-redesign.ko.md` B0.11(시너지가 화면에서 읽힘), B0.13(원형 = 근접 차단, 3.1 값), B0.14(I0·I1·I2), B0.15(축과 카드), B0.17(V-1~V-9). 화면 규칙은 `A6-visual-design-for-redesign-20261119.ko.md` 3.3(L1~L6), 4.1(네 겹), 4.3(계열 = 모양), 4.5(예산), 8.1(카드 문법), 10.4(통과 공통 조건). 에셋 자리는 `T7-asset-swap-structure-20261120.ko.md` 4절.
- 표기: **[코드]** 이 저장소의 파일을 읽어 확인 / **[가설]** 내 판단, 캡처·플레이로 확인할 것 / **[미확인]** 확인하지 못함.
- 이름: 이 문서의 한국어 이름·꼬리표·설명 글은 **모두 임시**다. `narrative-lead` 확인 전에는 ko.po에 "임시" 주석을 달고 넣는다. 표에서 ‹임시›로 표시한다.

---

## 0. 한 장 요약

원형 주문 셋이 들어오면 화면은 지금 **이것들을 모른다**[코드]: 색은 금색(성장·선택의 색)으로 잘못 칠해지고, 번개·냉기 원형은 화염으로 분류되고, 원형 시전은 잔 입자 5개로만 보이며, 주인공은 0.5~0.9초마다 시전 자세를 되풀이하고, 전투 막대에는 원형이 없고, 카드에는 이름 대신 번역 키가 뜨고 "축" 카드의 꼬리표가 비어 있다. 맞물림(I0·I1·I2)과 흔들림의 준비 동작 끊김은 이벤트가 있는데 아무도 읽지 않는다.

| 묶음 | 담당 | 키움(다섯 요소) | 한 줄 |
|---|---|---|---|
| **RS0** 켠 판을 찍는 도구 | `qa-perf` | (검수 수단) | 데이터 파일을 건드리지 않고 시험 도구 안에서만 run_spells를 켜고, 자동 조작이 원형을 고르게 한다 |
| **RS1** 원형의 네 겹과 색 바로잡기 | `vfx-feel` | 쾌감 · 성장 | "가까이 오면 맞는다"가 읽히는 얇은 테와 짧은 맥박. 계열별 모양. 흔들림 끊김 표시 |
| **RS2** 맞물림이 일어난 순간 | `vfx-feel` | 쾌감 · 성장 | I1(제어된 적에게 기본기), I2(원형의 터뜨림), I0(먼 원거리 적 겨눔)이 각자 다르게 보인다 |
| **RS3** 성장 카드의 새 종류 | `ui-hud` | 성장 · 도박 · 보상 | "축" 카드, 원형 열기 카드, 맞물림 줄, 진화까지 줄, 원형 이름·아이콘 자리 |
| **RS4** 전투 막대의 세 주문 | `ui-hud` | 성장 · 쾌감 | 고정 세 원소 칸 대신 가진 주문 셋. 원형 칸은 초를 띄우지 않는다. 축 구슬. 짝 이음 |
| **RS5** 소리 쪽에 넘길 이벤트 목록 | (목록만) → `audio-lead` | 쾌감 | 구현하지 않는다 |
| RS6 피격 출처(선택) | `vfx-feel` | 쾌감 | 원거리 탄에 맞았을 때 "어디서"가 0.25초 보임. 디렉터가 넣을지 정함 |

**섹시**는 이 문서의 어느 묶음도 키우지 않는다. 원형 카드에 후원자 반응을 붙이는 일은 A6-16(인물)에서 다룬다(D12 표 510행의 "희귀 이상 카드가 뜨면 반응 컷"과 같은 줄). 여기서는 미룬다.

**꺼진 경로 불변이 모든 묶음의 첫 통과 조건이다.** `enabled:false`에서 화면·덤프·골든이 바이트 단위로 같아야 한다(10.4 공통 조건에 더함).

---

## 1. 코드에서 확인한 사실

### 1.1 주문 id와 짝 id [코드: `chapter1/data/run_spells.json`, `chapter1/core/run_spells.gd` 12행]

| 주문 id | role | element | owner | 화면이 알아야 할 효과 키(base, 축 4단) |
|---|---|---|---|---|
| `chapter1.skill.ember` | basic | ember | — | `vs_cc`(frozen·stunned·staggered 6000, slowed 2500), `prefer_kinds:["ranged"]`, `applies:{heat:1}` |
| `chapter1.skill.frost` | basic | frost | — | 같은 `vs_cc`·`prefer_kinds`, `applies:{chill:1}`, `slow_bps 2000` |
| `chapter1.skill.arc` | basic | arc | — | 같은 `vs_cc`·`prefer_kinds`, `applies:{shock:1}` |
| `chapter1.skill.ember_ring` | ring | ember | `chapter1.character.ember` | `ring_radius_cm` 220→240→260, `cooldown_ticks` 54→42→30, `damage_raw 8192`(32), `stagger_ticks 60`, `near_cm 120`, `falloff_floor_bps 10000`, `hit_budget 10` |
| `chapter1.skill.frost_ring` | ring | frost | `chapter1.character.frost` | 같은 반경·쿨, `freeze_ticks 80`, `slow_bps 4000`, `slow_ticks 90` |
| `chapter1.skill.arc_ring` | ring | arc | `chapter1.character.arc` | 반경 220→240, 쿨 54→42→30, `ring_targets` 5→7, `stun_ticks 45`, `strong_pct_bps 400`, `strong_floor_bps 4000` |

- 원형은 **그 마녀의 것 하나만** 제안된다(`run_growth.gd` 326행). 한 판에 원형은 많아야 하나다.
- 칸 `slots: 3`. 주력 기본기 1 + 둘. 원형은 진화하지 않는다(`run_growth.gd` 311행 `_skills`에 없음, `evolve_progress`가 `{}`).
- 짝 13개(`pairs`): detonate 3(`pair.<el>.basic_ring`), interlock 3(`pair.<el>.interlock`, via `staggered`/`frozen`/`stunned`), 대여 interlock 4(`pair.borrow.frost_ember`·`frost_arc` via frozen·slowed, `pair.borrow.arc_ember`·`arc_frost` via stunned), reaction 3(`pair.react.steam`·`conduct`·`overload`). **reaction은 효과가 없다**(`run_spells.gd` 60행 "Reaction pairs only link; their effect is the next work package").
- 지금 데이터에서 `detonates`가 있는 것은 원형 셋뿐이다. 그래서 **`detonate` 이벤트는 원형의 명중에서만 난다** = I2.

### 1.2 이벤트 [코드]

| 이벤트 | 내는 곳 | 필드(이 문서가 쓰는 것) | 켠 판에서만? |
|---|---|---|---|
| `cast`(원형) | `combat_core.gd` 933~935 | `skill_id`(원형 id), `direction`(=주인공 방향), `effects`(합성 값 전부, `ring_radius_cm`·`near_cm`·`falloff_floor_bps` 포함), `targets`(맞을 적 위치, `ring_targets`까지), `evolved`, **`shape:"ring"`**, **`radius_cm`**, `pulse`(2 이상일 때만) | 예 |
| `cast`(기본기) | `combat_core.gd` 817~825 | I0일 때만 **`prefer:"kind"`**. 화염·서리의 `targets`는 빈 배열, 번개만 위치 목록 | `prefer`는 예 |
| `hit` | `chapter_core.gd` 1242~1258 | I2면 **`detonate:true`**, I1이면 **`vs_cc:"frozen"|"stunned"|"staggered"|"slowed"`**, `frozen`(냉기 원형 빙결 뒤의 값이 실림 — 제어 적용 1236행이 이벤트 1258행보다 먼저), `dealt_raw` | 두 필드는 예 |
| `detonate`(새) | `chapter_core.gd` 1260 | `target_id`, `by_skill`(원형), `status`, `src_skill`, `stacks`, `cast_uid`, `extra_raw`, **`pair`** | 예 |
| `stagger`(새) | `chapter_core.gd` 972 | `target_id`, **`cut`**(준비 동작·돌진을 끊었으면 true) | 예. 일반 적만(964행) |
| `stun` | `chapter_core.gd` 962(원형), 1278(번개 기본기) | `target_id`, `skill_id`, `until_tick`, `duration_ticks`, `elite` | 원형 쪽은 예 |
| `hero_hit` | `combat_core.gd` 728 | **`source_kind`**(walker·ranged·charger·elite·champion·boss·boss_ward·hazard), **`source_id`**, **`hp_after_raw`**, `from`, `graze` | **아니다. 늘 실린다** |
| `death` | `chapter_core.gd` 1281, `combat_core.gd` 1114 | **`role`**(normal·elite·champion·boss) | **아니다. 늘 실린다** |

- D12 B0.11·B0.17이 말한 **`knock` 이벤트는 코드에 없다.** 화염 밀어냄이 3.1에서 빠졌고(B0.13 3.1 표), 대신 `stagger {cut}`이 있다. 이 문서는 `stagger`를 쓴다.
- 냉기 원형의 빙결은 따로 이벤트가 없다. `hit.skill_id == frost_ring` 이고 `hit.frozen == true`로 읽는다.
- 읽기 전용 상태: `run.run_spells_view()`(`chapter_core.gd` 1109, `{enabled, slots, spells:{id:{role,element,axis,pairs_owned,evolve_progress}}, offer:{card id:{pairs_if_taken}}, detonate, ward}`), `growth.snapshot().axes`·`.evolve_partner`(켠 판에만), 제안 카드의 필드, `run.spells`(공개 변수, 검증된 문서), `run.effective_skill(id)`, `run._next_cast`(막대가 이미 읽음).

### 1.3 카드 [코드: `run_growth.gd` 316~349, 198~220]

켠 판의 카드 종류는 `unlock`, **`axis`**, `passive`, `evolve` 넷이다. **`rank`는 나오지 않는다.**

| kind | id 꼴 | 필드 |
|---|---|---|
| unlock | `unlock:<주문 id>` | `skill_id`, `rank:1`, `title_key:"skill.<id>.name"`, `after`(축 0/0의 합성 효과) |
| axis(새) | `axis:<주문 id>:<damage|reach>` | `axis`, `level`(올린 뒤 그 축 값), `rank`(1+축 합+1), `after` |
| passive | `passive:<패시브 id>` | 축 합 1 이상부터(342행) |
| evolve | `evolve:<주문 id>` | **`partner_pair`, `partner_skill`**(새), `after` |

보호 카드: 레벨 2에 그 마녀의 원형 열기(`protect.ring_at_level 2`), 레벨 3·5에 짝을 여는 카드, 그 밖은 진화에 다가가는 카드(354~364행).

### 1.4 지금 표현 쪽이 아는 것과 모르는 것 [코드]

| 곳 | 지금 | 켠 판에서 생기는 일 |
|---|---|---|
| `fx/chapter_effects.gd` 37행 `COLORS`, 213행 | 키가 기본기 셋뿐. 모르는 id는 `e0c69d` | 원형의 모든 입자·획이 **금색**. A6 3.1에서 금색 계열은 성장·보상의 뜻이다 → 색 규칙 위반 |
| 같은 파일 246~247행 `_element()` | frost·arc만 알아봄, 나머지는 0.0(화염) | 냉기·번개 원형이 화염 셰이더 번호로 그려짐 |
| 같은 파일 235~244행 `cast` | 번개 기본기만 줄기, 나머지는 잔 입자 5개 | 원형 시전이 **잔 입자 5개**뿐. 반경·테가 없다 |
| 같은 파일 1149~1155행 | 화염 기본기 시전 때 .9m 빈 고리(A6-2 준비 겹, `ring:true` 획, 셰이더 custom.z=1) | 원형 테와 크기로 갈려야 한다(아래 RS1) |
| `fx/combat_juice.gd` 7행 `COLORS`, 305행 | 같은 금색 대체 | 원형 명중 점멸·숫자가 금색 |
| `fx/combat_juice.gd` 361~363행 `cast` | 아무것도 안 함 | — |
| `detonate`, `stagger`, `hit.vs_cc`, `cast.prefer`, `cast.shape` | **표현 어디에서도 읽지 않음**(`chapter1/view/`에서 찾지 못함) | 맞물림이 화면에서 보이지 않음 |
| `actors/chapter_actors.gd` 158~160행 | 모든 `cast`가 주인공 시전 자세 12틱 + 방향 | 원형이 0.5~0.9초마다 쏠 때마다 **주인공이 시전 자세를 되풀이**한다 [가설: 계속 시전하는 것처럼 보일 것] |
| `actors/chapter_actors.gd` 164행 | `skill_id`에 "ember"가 들어 있으면 적을 불붙은 색으로 | 화염 원형은 우연히 맞게 됨 |
| `app/chapter_one.gd` 230행 | 시전 소리 표에 기본기 셋뿐, 모르면 `"fire"` | 냉기·번개 원형도 **화염 시전 소리**가 0.5초마다 |
| `hud/combat_bar.gd` 9행 `SKILLS`, 101~115행 | 칸 셋이 원소 셋에 고정. 구슬은 `growth.ranks` | 원형이 막대에 **없다**. 켠 판에서 `ranks`는 열 때 1로 고정이고 축은 `growth.axes`에 쌓여서 **구슬이 늘 하나**다 |
| `hud/combat_bar.gd` 271~272행 | 0.5초 미만은 쿨로 안 보임 | 원형 쿨 0.5~0.9초가 숫자로 깜박일 수 있음 |
| `hud/chapter_hud.gd` 209행 | 꼬리표 표가 unlock·rank·passive·evolve | `axis` 카드의 꼬리표가 **빈 칸** |
| `hud/chapter_hud.gd` 205행, 731행 | 원소를 `skill_id`의 셋째 마디로 자름 | 원형은 `"ember_ring"` → 문양·색 대체(황동) |
| `hud/chapter_hud.gd` 208행 + `i18n/ko.po` | `skill.chapter1.skill.<기본기>.name`만 있음 | 원형 카드 제목이 **번역 키 그대로**(`Loc.t`는 없으면 키를 돌려줌, `loc.gd` 135행) |
| `hud/chapter_hud.gd` 233~246행, 599~612행 | 설명은 피해·탄 수·연쇄·범위·빙결·파쇄 | 원형 카드는 "기술 기본 피해 32" 한 줄. axis 카드는 전후 비교가 없음. passive 글 "최대 랭크와 이 패시브"와 evolve 글 "최대 랭크와 선행 패시브 달성"은 **켠 판의 규칙(축 합 5 + 결정 + 짝 축 2)과 틀림** |
| `art/asset_slots.json` | `icon.*` 자리가 하나도 없음 | 주문 아이콘 자리를 새로 낸다 |

---

## 2. 공통 규칙(모든 묶음)

1. **표현은 이벤트와 읽기 전용 상태만 읽는다.** `run.spells`, `run_spells_view()`, `growth.snapshot()`, 카드 필드를 읽기만 한다. 코어 파일·데이터 파일(`run_spells.json` 포함)을 고치지 않는다. `enabled`를 켜지 않는다.
2. **원소는 id를 잘라서 얻지 않는다.** `run.spells.spells[id].element`(켠 판) → 없으면 지금의 기본기 표. 판이 시작할 때 한 번 `{주문 id: 원소}` 표를 만들어 `chapter_effects`·`combat_juice`·`chapter_hud`·`combat_bar`가 같은 결과를 쓴다. 공용 함수의 자리는 `view/hud/palette.gd`에 `spell_color(element)`를 두기를 권한다(A6-1 정리와 같은 방향).
3. **색**: 원형은 그 원소의 `FIRE`·`FROST`·`ARC`. 금색·황동(`GROWTH`, `BRASS_HI`, `QUALITY_*`)과 진홍(`THREAT`)을 원형에 쓰지 않는다(A6 3.1).
4. **자리**: 주인공 상자(1080p 905~1015, 400~575)의 흰 포화 1.0% 이하(L1). 2m·0.15초 안에 밝은 겹 하나(L3). 0.95 넘는 화소는 0.3초 안(L4). 효과 조명 3개 이하(L6) — **원형은 조명을 쓰지 않는다.**
5. **글**: 새 글은 모두 `Loc.t(키)`로, 키와 값은 `chapter1/i18n/ko.po`·`en.po`에. `.gd`에 한글 리터럴을 늘리지 않는다(`python tools/dev/i18n_scan.py`가 늘지 않음). 넣기 전 `python tools/dev/wording_lint.py`. 분위기 낱말 금지(`docs/story/wording-rules.json`).
6. **그림**: 새 그림은 만들지 않는다(유료 생성 없음). 아이콘은 `asset_slots.json`의 새 자리 `icon.spell.*`를 거치되 `planned:true`로 두고, **자리가 planned이면 코드가 임시 문양을 그린다**. planned 자리에 `AssetSlots.texture()`를 부르지 않는다(자홍 바둑판이 뜨고 `missing()`에 오른다). 그림이 오면 표의 `file`만 채운다(T7 4절 1·2). 경로 문자열을 코드에 쓰지 않는다.
7. **꺼진 경로**: `run.run_spells_view().enabled == false`이면 모든 새 분기를 타지 않는다. 지금의 표·글·그림이 그대로다.

---

## 3. 묶음

### RS0 켠 판을 찍는 도구 — `qa-perf` (다른 묶음보다 먼저)

**왜**: `run_spells.json`은 `enabled:false`이고 이 문서는 그것을 켜지 않는다. 시험 도구 안에서만 켜야 캡처가 나온다. 또 자동 조작(`chapter_pilot.gd` 15~26행)은 주력의 카드(축 = else 분기 80점)를 열기(65점)보다 먼저 집어 원형을 거의 고르지 않는다 [코드로 미루어 봄, 실행 확인 안 함].

| 할 일 | 고칠 파일 | 건드리지 않음 |
|---|---|---|
| `hud_dump.gd`에 `--run-spells=on`: 판을 시작하기 전에 `run_spells.json`을 읽어 `enabled:true`로 바꾼 사본을 `run.set_run_spells()`(`chapter_core.gd` 134행)에 맡긴다 | `chapter1/tests/hud_dump.gd` (필요하면 `burst_capture.gd`) | `chapter1/data/run_spells.json`, 코어, `chapter_pilot.gd`, 앱 |
| 같은 인수에 시험용 고르기 규칙 `--spells-pick=synergy`: 원형 열기 > 주력 축 damage > 원형 축 reach > 그 밖은 지금 규칙. 도구 안에서 `choose()`를 부른다 | 같음 | 위와 같음 |
| `scene_shot.gd`에 새 장면 `boon_spells`(픽스처 `chapter1/tests/fixtures/ui/boon_spells.normal.json`·`.long.json`): `FixtureRun`이 켠 문서를 맡고 주력 + 원형을 가진 상태에서 RS3의 네 종류 카드를 띄운다. long은 가장 긴 실제 글(짝 줄 둘 + 진화까지 줄) | `chapter1/tests/scene_shot.gd`, 픽스처 둘 | 다른 장면의 픽스처 |
| `--burst`가 `cast:shape=ring`, `stagger:cut=true`, `hit:vs_cc=frozen`, `cast:prefer=kind`, `detonate`를 맞히는지 확인(불·문자열 값 비교) | `burst_capture.gd`(필요할 때만) | — |

- 받아들이는 기준: (1) 인수 없이 돌린 `hud_dump` 덤프가 이전과 바이트 같음. (2) `--run-spells=on --spells-pick=synergy`로 시드 11 세 주력에서 원형이 레벨 2에 들어간다(`HUD_BURST_SUMMARY`에 `cast:shape=ring`이 "만남"). (3) `scene_shot --scenes=boon_spells`가 두 해상도에서 찍힌다.
- [미확인] `hud_dump`가 앱이 판을 만들기 **전에** 그 판 객체에 닿을 수 있는지. 닿지 못하면 앱에 개발 인수(`--chapter1-run-spells=<_local/ 아래 경로>`, 자리표 덮어쓰기 `asset_slots.gd` 10~11행과 같은 꼴)를 두는 길이 있다 — 제품 코드라 `tech-lead` 검토와 디렉터 결정(5절 D-1).

### RS1 원형의 네 겹과 색 바로잡기 — `vfx-feel` · 쾌감·성장

**무엇이 읽혀야 하나**: "이 원 안에 들어오면 맞는다"(V-1), "가까울수록 세다"(V-2, 지금 데이터는 감쇠 없음), "쉬는 것은 정상이다"(V-8), "붙던 적이 멈췄다"(V-3·V-4). 0.5~0.9초마다 도는 원형이 **큰 폭발이 아니라 짧은 맥박**이어야 한다(B0.13 재미 위험 1). 쾌감 = "막았다"의 순간, 성장 = 차단 축을 올리면 테가 커지고 맥박이 잦아지는 것이 보임.

| 겹 | 모양(크기 m, 1m ≈ 1080p 55px) | 읽는 것 | 예산 |
|---|---|---|---|
| ① 준비 = **경계 테**(늘 있음) | 주인공 발밑, 반지름 = 지금 원형의 `ring_radius_cm`(2.2~2.6m), 테 폭 .05m. 알파: 쿨이 찼을 때 .30, 쏜 직후 .10에서 쿨에 맞춰 .30까지 **매끄럽게** 오름(켜짐/꺼짐 깜박임 금지). 계열 모양: **화염 = 끊김 없는 띠**, **냉기 = 가는 테 + 안쪽으로 짧은 가시 12개(.12m)**, **번개 = 가는 테 둘(.07m 간격)**. 주인공 원소 고리(`chapter_actors.gd` 509행 반지름 .62m, 알파 .85, 깊이 무시)보다 훨씬 크고 흐리다. 깊이 검사는 **켠다**(적 몸 아래로 숨어도 됨, 주인공 고리와 갈리게) | `run.effective_skill(id).effects.ring_radius_cm`, `cooldown_ticks`, `run._next_cast[id]` | 메시 하나(원형은 판에 하나), 그리기 +1 |
| ② 날아감 = **맥박** | `cast.shape=="ring"`에서. `near_cm`(1.2m)부터 `radius_cm`까지 0.08초에 퍼지는 띠, 0.12초에 사라짐(합 0.2초). 띠의 밝기는 안쪽 1.0 → 테두리 `falloff_floor_bps/10000`(지금 1.0이라 고름 — 데이터가 바뀌면 그림이 따라감, V-2). **반지름 .7m 안은 비운다**(L1). 가장 밝은 곳 0.85 이하, 흰 심 없음. `pulse ≥ 2`는 폭 70%. 기존 `impact` 획의 `ring:true` 경로(1154행, 셰이더 custom.z=1)를 써서 그리기 호출을 늘리지 않는다 | `cast.radius_cm`, `cast.effects.near_cm`·`falloff_floor_bps`, `cast.pulse` | 시전당 획 1. 원형 쿨 최소 30틱이라 초당 2개 이하 |
| ③ 맞음 | **화염**: `stagger`에서 적 머리 위 짧은 주황 호 둘(.3m) 0.3초. **`cut:true`면** A6-5 전조(진홍)가 사라지는 자리에 0.15초 동안 금 간 조각 셋이 `LINEN`으로 바래며 흩어짐 — "막았다"(V-4). 진홍을 밝히지 않는다. **냉기**: `hit.skill_id==frost_ring && frozen` → 지금의 얼음 표시(발밑 결정·몸 파랑, `chapter_actors.gd` 923행)를 그대로 쓰고 새로 더하지 않음. 감속 띠(B0.13 3판 "바깥 띠")는 지금 코어에 따로 없어 그리지 않는다. **번개**: `cast.targets`의 각 위치로 주인공에서 .6m 떨어진 점부터 꺾은 줄기(굵기 .035, 0.12초, 밝기 0.8 이하). `stun.skill_id==arc_ring`의 경련 표시는 `ARC` 꺾은 선(지금의 노랑 `ffe08a`는 A6 4.2에서 색 규칙 위반 — 원형 쪽부터 `ARC`로) | `stagger`, `hit`, `cast.targets`, `stun` | 경련 표시 프레임당 4, 끊김 조각 프레임당 2 |
| ④ 흔적 | **없다.** 0.5초마다 바닥에 자국을 남기면 바닥이 칠해진다(A6 4.5 ④ 16개 상한) | — | 0 |
| 강한 적(V-7) | 원형이 정예·수호자·우두머리를 맞힐 때(`hit`의 대상이 `elite`, 스냅숏에서 읽음) 테의 그 방향 ±12° 조각이 0.15초 회색(`INK_DIM`)으로 둔하게 — "튕겨 나지 않는다" [가설, 플레이로 볼 것] | `hit.target_id` → `run.enemies[id].elite` | 맥박당 1 |

**색·분류 바로잡기(같은 묶음)**: `chapter_effects.gd` 37·213·246행과 `combat_juice.gd` 7·305행을 2절 2번의 표로. **주인공 시전 자세**: `chapter_actors.gd` 158행에서 `cast.shape=="ring"`이면 자세·방향을 건드리지 않는다(한 줄. 이 파일의 다른 곳은 고치지 않는다 — A6-6이 같은 파일을 쓰므로 그 묶음과 차례를 맞춘다). **피해 숫자**: 원형 명중은 10대상 × 초당 2번까지 숫자를 낸다. 5절 U-1이 정해지기 전에는 **원형의 일반 적 명중 숫자를 같은 맥박(`cast_uid`) 안에서 하나로 합쳐** 테 바깥에 하나만 띄운다(정예는 따로).

- 고칠 파일: `chapter1/view/fx/chapter_effects.gd`, `chapter1/view/fx/combat_juice.gd`, `chapter1/view/actors/chapter_actors.gd`(158행 한 곳), 필요하면 `view/impact_quality14.gdshader`(띠 밝기 경사). 새 메시는 `fx/` 안에.
- 건드리지 않음: 코어·데이터, A6-5 전조의 그리기(사라짐 조각은 덧붙이기만), 화염 기본기의 .9m 준비 고리(1149~1155행).
- 받아들이는 기준(캡처는 4절):
  1. 정지 화면에서 주인공 둘레의 원형 테가 **주인공 고리(.62m)·화염 준비 고리(.9m)·정예 발밑 고리와 크기·굵기로 갈린다** — 아트 책임자가 1080p·720p에서 직접 봄.
  2. 흑백 한 장에서 세 원형의 테가 모양(띠/가시/겹)으로 갈린다.
  3. 연속 캡처(0.1초 × 8칸)에서 맥박이 1~2칸에 보이고 3칸째에 사라진다.
  4. `shot_review.py`의 주인공 상자 흰 포화가 원형을 가진 판의 모든 칸에서 1.0% 이하. 같은 시드의 원형 없는 판과 나란히.
  5. 원형의 어떤 화소도 금색·진홍으로 칠해지지 않는다(그림으로 확인).
  6. 주인공이 시전 자세를 0.5초마다 되풀이하지 않는다 — 정지 화면으로는 판단 못함, 연속 캡처에서 자세 프레임만 보고 나머지는 사용자 플레이.
  7. 꺼진 판: 시드 11 서리 기존 캡처와 `shot_review.py` 전·후 비교에서 바뀐 화소 0(같은 빌드 두 번 찍은 흔들림 범위 안).
  8. 프레임: 후반 `f_fx` 평균 +0.3ms 이하, 그리기 +2 이하(A6 10.3의 방법). 기계 여유가 있을 때 잰다.

### RS2 맞물림이 일어난 순간 — `vfx-feel` · 쾌감·성장

**왜**: "스킬 구조를 이해하고 시너지가 나는 쪽을 고르는 것이 효율이 좋아야 한다"(사용자 지시, D12 B0.13 첫 단락)가 성립하려면 시너지가 **보여야** 한다(B0.11). 쾌감 = 내 조합이 터지는 순간, 성장 = 고른 짝이 일하는 것이 보임. A6 4.4의 권고대로 **색을 섞지 않고 주는 쪽 계열의 모양 하나를 빌린다.**

| 순간 | 이벤트 | 모양 | 예산 |
|---|---|---|---|
| **I1** 원형(또는 대여)이 멈춘 적을 기본기가 침 | `hit.vs_cc` | 그 명중의 보통 점멸을 **대신하여**(더하지 않음, L3) 1.3배 점멸 + 제어한 쪽 모양 하나: `frozen` → 얼음 가시 6개가 박힌 작은 테 .4m, `stunned` → `ARC` 꺾은 선 둘, `staggered` → 주황 짧은 호 둘, `slowed` → 서리 가는 테. 0.15초. 색은 **맞힌 기본기의 색**, 모양만 빌림 | 프레임당 4, 넘으면 보통 점멸로 |
| **I2** 원형이 기본기의 표시를 터뜨림 | `detonate`(같은 틱에 `hit.detonate`) | 원형 테의 그 적 방향 ±15° 조각이 0.15초 **두 배 굵기**(V-6 "테가 한 번 굵어짐") + 적 자리에 표시한 기본기 모양의 작은 흔적(화염 = 숯 점 3개, 냉기 = 가시 테, 번개 = 꺾은 선) 0.2초. `detonate.status`로 모양을 고른다 | 맥박당 조각 3까지 |
| **I0** 기본기가 먼 원거리 적을 먼저 겨눔 | `cast.prefer=="kind"` | **작게**(V-9): 지팡이 앞 .5m에 겨눈 방향으로 `LINEN` 짧은 눈금 하나 0.1초. 번개는 `cast.targets[0]` 위치에 `LINEN` 가는 고리 .4m 0.2초. 진홍 금지(적이 아니라 내 겨눔) | 시전당 1 |

- [코드] 화염·서리 기본기의 `cast`에는 맞힐 위치가 없다(`targets: []`). I0의 대상 위치를 그리려면 코어가 `prefer:"kind"`일 때만 `aim_at`(위치)을 싣는 작은 변경이 필요하다 — 꺼진 판에는 필드가 생기지 않아 골든 불변일 것으로 본다 [가설]. 넣을지는 디렉터(5절 D-2). 그 전에는 방향 눈금만.
- reaction 짝(`react.*`)은 효과가 없어 **아무것도 그리지 않는다.**
- 고칠 파일: `chapter_effects.gd`, `combat_juice.gd`(I1의 점멸 교체). RS1과 같은 파일이라 **RS1 다음에 한 사람이 이어서** 한다.
- 받아들이는 기준: (1) 세 주력 각각 `--burst=hit:vs_cc=<그 원소의 제어>,detonate,cast:prefer=kind` 연속 캡처에서 표시가 1~2칸에 그 적 위에 있음(좌표로 짚음). (2) 흑백에서 I1 점멸이 보통 점멸과 모양으로 갈림. (3) 같은 자리 겹침 없음(L3, 그림으로 확인). (4) 주인공 상자 흰 포화 1.0% 이하. (5) 꺼진 판 화소 불변. (6) [플레이] P7 질문 12 "멀리 있는 원거리 적을 먼저 치는 것을 알아봤나" — 사용자.

### RS3 성장 카드의 새 종류 — `ui-hud` · 성장·도박·보상

**왜**: 카드가 고민의 자리다. 성장 = 축이 무엇을 바꾸는지 숫자로, 도박 = "이걸 고르면 무엇과 맞물리나"가 고르기 전에 보여 걸 수 있음, 보상 = 원형이 열리는 레벨 2가 눈에 띄는 선물. 카드 문법은 A6 8.1(줄 순서: 이름 → 종류 → 설명 → 수치 → 맨 아래). A6-10의 `GAIN`·`LOSS` 토큰이 아직 `palette.gd`에 없다[코드] — A6-10이 먼저 들어오면 쓰고, 아니면 `INK`로 두고 A6-10이 바꾼다.

| 카드 | 이름 줄 | 종류 꼬리표 ‹임시› | 설명·수치 줄(값은 모두 카드의 `after`와 지금 `effective_skill`에서) |
|---|---|---|---|
| 원형 열기 | `skill.chapter1.skill.<el>_ring.name` ‹임시: 화염 고리 / 냉기 고리 / 번개 고리› | "새 기술 · 원형" | 반경 `ring_radius_cm/100`m · `cooldown_ticks/60`초마다 · 한 번 `damage_raw/256`. 원소 줄: 화염 "흔들림 `stagger_ticks/60`초, 준비 동작을 끊음" / 냉기 "빙결 `freeze_ticks/60`초 · 감속 `slow_bps/100`%" / 번개 "경련 `stun_ticks/60`초 · 최대 `ring_targets`대상 · 강한 적에게 현재 생명 `strong_pct_bps/100`%". 마지막 줄 `INK_DIM`: ‹임시› "멀리 선 적과 날아오는 탄은 막지 못합니다"(D12 B0.13 "원형의 말") |
| 대여 기본기 열기 | 지금 이름 | "새 기술 · 빌림" ‹임시› | 지금 설명 |
| axis | 주문 이름 | 기본기: "강화 · 피해" / "강화 · 넓이", 원형: "강화 · 위력" / "강화 · 차단" ‹임시›(B0.15 "화면의 꼬리표는 역할마다 다르게") | **바뀌는 값만** "지금 → 다음 ▲". 예: 원형 차단 1점 "반경 2.2 → 2.4m ▲", 2점 "간격 0.9 → 0.7초 ▲". 축 단계 "피해 ●●○○ · 넓이 ●○○○" |
| passive | 지금 | 지금 | 글을 켠 판의 규칙으로: ‹임시› "진화에 필요합니다: 축 합 5 + 이 결정 + 짝 주문의 축 합 2" (값은 `run.spells.evolve`에서) |
| evolve | 진화 이름 | 지금 | "짝: [`partner_skill` 아이콘] `partner_skill` 이름" 한 줄. 지금의 "최대 랭크와 선행 패시브 달성"은 켠 판에서 내보내지 않는다 |

**맞물림 줄**(모든 카드, ⑤ 맨 아래 위 — A6 8.1이 예약한 자리): `run_spells_view().offer[card.id].pairs_if_taken`의 짝마다 한 줄, 최대 2줄.
- interlock(`a`가 제어, `b`가 끝냄): ‹임시› "[a 아이콘]이 멈춘 적에게 [b 아이콘] 피해 +`vs_cc[via]/100`%" (via가 둘이면 큰 값).
- detonate(`a`가 표시, `b` 원형이 터뜨림): ‹임시› "[a]의 표시를 [b]가 터뜨림: 피해 +`bonus_bps/100`% · 제어 ×`block_bps/10000`" (번개는 "대상 +`block_targets`").
- reaction: **보이지 않는다**(효과 없음).
- 짝이 없으면 ‹임시› "지금 맞물리는 것 없음"을 `INK_FAINT`로.
**진화까지 줄**(기본기의 axis·passive 카드): `run_spells_view().spells[id].evolve_progress` → ‹임시› "진화까지: 축 3/5 · 결정 ✓ · 짝 1/2". 원형 카드에는 없음(원형은 진화하지 않음).

**아이콘**: 카드의 원소 문양(`ElementSeal38`, 731~741행)을 원소 표(2절 2번)로 고르고, 원형이면 문양 둘레에 그 원소 색의 가는 테 하나를 코드로 더 그린다(임시). 자리는 `icon.spell.<짧은 이름>`(RS4와 같은 자리).

- 고칠 파일: `chapter1/view/hud/chapter_hud.gd`(카드 쪽: 205·209·233~246·599~612·722~747·1165~1185행 부근), `chapter1/i18n/ko.po`·`en.po`(새 키, 값 옆에 "임시 — narrative-lead 확인" 주석), `chapter1/art/asset_slots.json`(RS4와 함께 한 번).
- **주의**: 카드 꾸미기 사슬이 자식 순번(`get_child(2)`·`(3)`·`(4)`, 742~746행, 1177~1183행)에 기댄다. 새 줄은 순번 3의 설명 라벨 안(스크롤 `CardText`)에 넣거나 마지막 단추 바로 앞에 넣어 **순번을 바꾸지 않는다.**
- 건드리지 않음: 꺼진 판의 카드 글(지금 글 그대로), `choice` 신호와 토큰 흐름, 코어.
- 받아들이는 기준: (1) `scene_shot --scenes=boon_spells`(RS0) 1280×720·1920×1080 normal·long에서 카드 네 종류가 이름(키가 아님)·꼬리표·원소 색·맞물림 줄·진화까지 줄을 보임 — 직접 봄. (2) `hud_layout_check.py` 위반 0(`text_overflow`, `font_small` 720p 11.2 이상, `offscreen`). (3) `scene_shot --scenes=boon`(꺼진 판) 덤프가 이전과 같음. (4) `wording_lint.py` 통과, `i18n_scan.py` 한글 리터럴 늘지 않음. (5) 실제 판(`hud_dump --run-spells=on`)에서 레벨 2 카드 캡처에 원형 열기 카드가 보임.

### RS4 전투 막대의 세 주문 — `ui-hud` · 성장·쾌감

**왜**: 성장 = 가진 셋과 각 축이 늘 보임, 짝이 이어진 것이 막대에서 보임(B0.11 "기술 줄"). 쾌감은 원형 칸의 짧은 "일했다" 빛 정도로만.

| 항목 | 켠 판 | 꺼진 판 |
|---|---|---|
| 칸 셋의 주인 | 가진 주문(`run_spells_view().spells`)을 **주력 기본기 → 원형 → 빌린 기본기** 차례로 [가설: 짝이 이웃하게 하려는 차례. 디렉터가 다른 차례를 원하면 바꿈]. 빈 칸은 지금의 "안 배운 칸"처럼 흐리게 | 지금 그대로(`SKILLS` 고정 셋) |
| 아이콘 | `icon.spell.ember` 등 자리. planned면 기본기는 지금 아틀라스 조각(`icon_fire`·`icon_frost`·`icon_arc`), 원형은 같은 조각 .7배 + 원소 색 가는 테(코드로) | 지금 그대로 |
| 쿨 | 기본기: 지금 규칙. **원형: 초 숫자를 띄우지 않는다**(V-8). 어두운 부채꼴 대신 칸 테두리의 원소 색 호가 쿨에 맞춰 참. 원형이 쏜 틱에 칸 테가 0.1초 밝음 | 지금 그대로 |
| 구슬 | 축: 왼쪽에 피해(위력) 칠한 구슬, 오른쪽에 넓이(차단) 빈 고리 구슬, 합 6까지. 진화하면 지금의 금 고리 | 지금 그대로(`ranks`) |
| 짝 이음 | 이웃한 두 칸이 `pairs_owned`로 이어져 있으면 칸 사이 14px 틈에 `LINEN` 가는 줄(2px) 하나. reaction 짝은 그리지 않음. `BRASS_HI`(선택의 색) 금지 | 없음 |

- 고칠 파일: `chapter1/view/hud/combat_bar.gd`(9·101~115·137~140·252~293행 부근), `chapter1/art/asset_slots.json`(아래 6자리 추가, `planned_families`에 `icon.spell.<spell>` 추가).
- 새 자리(모두 `kind:"texture"`, `file:""`, `planned:true`, `source:"A6-RS RS3·RS4"`, `contract:{"size":[128,128],"square":true,"alpha":true}`): `icon.spell.ember`, `icon.spell.frost`, `icon.spell.arc`, `icon.spell.ember_ring`, `icon.spell.frost_ring`, `icon.spell.arc_ring`. 지금 파일이 없으므로 원장(`asset_ledger.py`)에는 올리지 않는다 — 그림이 오는 날 올린다(T7 4절 2).
- 건드리지 않음: 칸 크기·자리(`BOUND_SLOT_X`), 궁극기·회피·물약 칸, 생명·영혼 구슬, A 배치.
- 받아들이는 기준: (1) `hud_dump --run-spells=on --spells-pick=synergy` 세 주력 시드 11의 레벨 2 이후 순간(2400·9000) 1080p·720p 캡처에서 원형이 둘째 칸에, 원형 칸에 초 숫자가 없음, 구슬이 축 수와 맞음 — 직접 봄(막대는 `_draw` 하나라 `hud_layout_check`로는 칸을 볼 수 없다). (2) 실행 로그 `CHAPTER1_ASSETS`의 `missing`에 `icon.spell.*`가 없음(planned 자리를 부르지 않았다는 뜻). (3) `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_asset_slots.gd` 통과. (4) 꺼진 판 막대 영역 `shot_review.py` 바뀐 화소 0.

### RS5 소리 쪽에 넘길 이벤트 목록 — 목록만, 구현은 `audio-lead` 배정

지금 소리는 `app/chapter_one.gd` 230~237행의 이벤트 → 소리 표 하나에서 정해진다[코드]. 원형은 원소 구분 없이 `"fire"`, 0.5초마다. 아래는 화면 쪽이 아는 사실과 바람이다. 소리의 모양·크기는 `audio-lead`가 `docs/AUDIO-PLAN.ko.md`로 정한다.

| 이벤트(조건) | 빈도 [미루어 본 것] | 화면이 바라는 뜻 | 쾌감과의 관계 |
|---|---|---|---|
| `cast` + `shape:"ring"`(원소는 `skill_id`의 데이터) | 원형 하나, 초당 1.1~2회(쿨 54~30틱) | 짧고 낮은 맥박. 기본기 시전보다 작게. 지금 `"fire"` 대체를 끊는다 | 낮음 — 잦아서 크면 피곤 |
| `stagger` + `cut:true` | 드묾 | **"막았다"**(V-4). 가장 또렷해야 할 새 소리 | 높음 |
| `stagger`(cut 아님) | 맥박당 여러 | 소리 없음 또는 아주 작게 | — |
| `stun` + `skill_id == arc_ring` | 맥박당 5~7 | 한 맥박에 한 번만 | 중간 |
| `hit` + `skill_id == frost_ring` + `frozen` | 맥박당 여러 | 한 맥박에 한 번만 | 중간 |
| `detonate`(`pair`, `status`) | 원형 명중 중 일부 | I2 터뜨림: 보통 명중과 다른 소리(B0.11 "터뜨림의 순간") | 높음 |
| `hit` + `vs_cc` | 기본기 명중 중 일부 | I1: 보통 명중과 다른 소리. `vs_cc` 값(얼림·경련·흔들림·감속)으로 갈래 | 높음 |
| `cast` + `prefer:"kind"` | 기본기 시전 중 일부 | 소리 없음 권고(겨눔 표시는 작게, V-9) | — |
| `hero_hit` + `source_kind` | 지금과 같음 | 탄(`ranged`)과 몸(그 밖)을 다른 피격음으로 — P7 질문 11 "왜 죽었는지 알았나" | 중간(읽히는 죽음) |
| `death` + `role` | 지금과 같음 | `champion`·`boss` 처치의 따로 된 소리 후보(지금 `elite` 불만 있음) | 보상 |

### RS6 피격 출처(선택) — `vfx-feel` · 쾌감

`hero_hit.source_kind == "ranged"`이고 `source_id`의 적이 살아 있으면 그 적에서 주인공 쪽으로 `THREAT_DEEP` 가는 선 0.25초(A6 3.1 "위험이 오는 쪽"). 몸 공격은 지금 그대로. D12 P7 질문 11("붙은 적이 없는데 탄에 맞아 죽었을 때 왜 죽었는지 알았나")을 돕는다. A6-5(전조)와 같은 진홍 계열이라 **A6-5 담당과 색 확인 뒤**. 넣을지 디렉터가 정한다(5절 D-4). 고칠 파일: `combat_juice.gd`의 `hero_hit` 갈래(367~374행). 기준: 원거리 판 연속 캡처에서 선이 맞은 칸에 보이고 0.3초 안에 사라짐, 주인공 상자 L1.

---

## 4. 캡처·검사 방법

모두 저장소 루트에서, **기계 여유가 있을 때** 돈다. 출력은 `_local/shots/` 아래만.

```powershell
# 전(지금 main, 꺼진 판) — 꺼진 경로 불변의 기준
python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.frost --until=16000 --shots=_local/shots/rs-off-before --dump=_local/shots/rs-off-before.json --dump-extra

# 후(같은 인수, 묶음 반영 뒤) → 바이트·화소 비교
python tools/dev/shot_review.py _local/shots/rs-off-before _local/shots/rs-off-after --out=_local/shots/rs-off-review

# 켠 판(RS0 뒤) — 세 주력 × 두 해상도, 원형·맞물림 연속 캡처
python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.ember --run-spells=on --spells-pick=synergy --until=16000 --burst=cast:shape=ring,stagger:cut=true,detonate,hit:vs_cc=staggered,cast:prefer=kind --shots=_local/shots/rs-ember-1080 --dump=_local/shots/rs-ember-1080.json --dump-extra
#   서리: hit:vs_cc=frozen / 번개: hit:vs_cc=stunned,stun 로 바꾼다. 같은 것을 --resolution 1280x720 으로.

# 카드 화면(RS0의 새 장면)
python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/scene_shot.gd -- --chapter1-profile-off --scenes=boon_spells,boon --shots=_local/shots/rs-cards-720
python tools/dev/hud_layout_check.py _local/shots/rs-cards-720/boon_spells.normal.1280x720.json _local/shots/rs-cards-720/boon_spells.long.1280x720.json

# 측정
python tools/dev/shot_review.py _local/shots/rs-frost-1080 --out=_local/shots/rs-frost-1080-review   # 주인공 상자 흰 포화
python tools/dev/wording_lint.py
python tools/dev/i18n_scan.py
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_asset_slots.gd
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_run_spells.gd       # 표현만 고쳤어도 확인
python tools/dev/run_all.py --quick
```

- 시점: 2400(원형 열린 직후 열린 마디), 9000(가운데), 16000(뒤 마디). 같은 시드·시점의 전후를 나란히.
- 흑백 판정: 연속 캡처 한 칸을 회색조로 바꿔 본다(`shot_review.py`의 그림 출력 또는 아트 책임자가 직접).
- 골든: 묶음들은 표현만 고치므로 `golden_core.gd`는 바뀌지 않아야 한다. RS0의 도구 변경도 같다. 5절 D-2(`aim_at`)를 하면 코어 변경이라 꺼진 값 골든 불변을 따로 확인한다.

---

## 5. 정할 것

### 사용자가 정할 것

| # | 질문 | 선택지 | 권고 |
|---|---|---|---|
| U-1 | 원형 명중의 피해 숫자(A6 11.1-2와 같은 질문의 원형 판) | 가) 맥박마다 하나로 합쳐 하나 / 나) 정예만 / 다) 보이지 않음 | **가**. 초당 20개까지 뜨면 전조와 자리를 다툰다 [가설]. 숫자가 주는 쾌감은 사용자만 판단 |
| U-2 | 원형의 경계 테를 늘 보일지 | 가) 늘 흐리게(이 문서) / 나) 반경 1.5배 안에 적이 있을 때만 | **가**. "들어오면 맞는다"를 미리 알려 원형의 값이 보인다. 화면이 시끄러우면 나 |

### 디렉터가 정할 것

| # | 질문 | 권고 |
|---|---|---|
| D-1 | RS0을 시험 도구 안에서만 할지, 앱에 개발 인수를 둘지 | 도구 안에서만. 닿지 못하면 그때 `tech-lead` 검토로 개발 인수 |
| D-2 | I0 겨눔 대상 위치 `cast.aim_at`을 코어에 실을지(`gameplay-systems`, 켠 판에만 생기는 필드) | 싣는다. 작고, V-9가 방향 눈금만으로는 "멀리 선 저것"을 짚지 못한다 [가설] |
| D-3 | 같은 파일의 차례: `chapter_effects.gd`·`combat_juice.gd`는 A6 10.2의 effects 줄과 겹친다 | **A6-3(서리·번개 네 겹) 전에 RS1 → RS2.** A6-3은 "〔D12〕 기술 목록"을 기다렸고 이 문서가 그 목록을 준다. RS1이 원소 표를 바로잡아 A6-3이 그 위에서 시작한다 |
| D-4 | RS6(피격 출처)을 넣을지 | 원거리 대책(B0.18)의 플레이 질문 11을 볼 수 있게 넣기 권고. A6-5 담당과 색 확인 뒤 |
| D-5 | `chapter_actors.gd` 158행 한 줄을 `vfx-feel`이 고칠지 | 예. A6-6 묶음이 같은 파일에 들어가기 전에 |
| D-6 | 이름·꼬리표·설명 글(‹임시› 전부)과 원형 셋의 이름을 `narrative-lead`에 언제 넘길지 | RS3 시작과 동시에. 화면은 임시 값으로 먼저 간다 |

`narrative-lead` 확인 필요 목록: 원형 셋의 이름, 대여 꼬리표 "빌림", 축 꼬리표 넷(피해·넓이·위력·차단), "새 기술 · 원형", 원형의 말 한 문장, 맞물림 줄 두 꼴, "지금 맞물리는 것 없음", 진화까지 줄, passive 카드의 켠 판 글.

---

## 6. 켜기 장부에 남는 것

이 문서의 묶음이 다 끝나도 ④가 닫히려면: RS1~RS4의 아트 책임자 검수(직접 본 캡처) + U-1·U-2 결정 + 이름 확정(`narrative-lead`) + **사용자 플레이**(P7 질문 10 "0.5~0.9초마다 도는 원형이 막는 벽으로 읽혔나 연타로 읽혔나", 12 "원거리 먼저 겨눔을 알아봤나"). 정지 화면으로 판단할 수 없는 것: 맥박의 리듬이 "연타"로 느껴지는지, 끊김 조각의 손맛, 테의 알파 오름이 깜박임으로 보이는지, 모든 소리.

## 7. 확인하지 못한 것

- **화면을 하나도 보지 않았다.** Godot를 돌리지 않아 모든 모양·크기·밝기는 [가설]이다. 1.4절의 "생기는 일"은 코드를 읽고 미루어 본 것이다(예: 금색, 시전 자세 되풀이, 번역 키 노출).
- 자동 조작이 원형을 고르지 않는다는 판단은 점수 표(`chapter_pilot.gd` 20~23행)에서 미루어 본 것이다.
- `hud_dump`가 판 시작 전에 판 객체에 닿는지, `--burst`가 `cut=true`·`shape=ring` 같은 값을 맞히는지.
- 프레임 비용(그리기 +1~2, `f_fx` +0.3ms 안)은 코드 읽기의 추정이다.
- 원형 테 2.6m가 1280×720 화면 안에 다 들어오는지(카메라 19.5 기준 1m ≈ 1080p 55px로 셈하면 반지름 약 143px — 들어올 것으로 본다).
- D12의 `knock` 이벤트와 "냉기 바깥 감속 띠"는 지금 코어에 없다. 코어가 나중에 넣으면 RS1 ③을 다시 맞춘다.
