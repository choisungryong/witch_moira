# 장비 비교 판정 v2의 열린 판단 (2026-11-24, design-lead)

읽은 것: `_local/verdict/REPORT.txt`(gameplay-systems, GM-B), `combat_core.gd` 408~421행(`_skill_with`), `report_run_loot.gd` 전체, `sim_loot.gd` 278~340행, D6 7.4 표, D21 1.2 표, D23 2.2-7. 앞 문서는 `DESIGN-REVIEW-20261124-gear-layer2c.ko.md`(이하 layer2c).

## 1. 결정

| # | 결정 | 근거 | 요소 |
|---|---|---|---|
| VO1 | **번개가 `projectiles`를 연쇄로 받는 코어 동작은 의도한 설계다. 판정이 코어를 따르는 지금 구현을 받는다.** 출처는 D12·D23이 아니라 D6 7.4 표 395행이다: "발사체 / 대상 수 \| `projectiles`(번개는 `chain_targets`) \| `projectiles`". D12 69행과 D23 2.2-7은 키 이름만 적는다. T11 63행과 K12(번개는 `chain_targets` +2)도 같은 규칙을 쓴다 | 코어 413~414행은 발사체가 0인 기술에 `else`로 연쇄를 더한다. layer2c 1.3을 쓸 때 내가 이 `else`를 빠뜨리고 읽었다. 연쇄 3(1랭크)에서 +2는 대상이 67% 늘어나므로 피해 −15%를 넘는 이득이다(+1.79, 모델의 답) | 성 · 도 |
| VO2 | **layer2c의 틀린 줄 둘을 바로잡는다(이 문서가 정정본이다. layer2c는 고치지 않는다).** ① 1.3 표 첫 줄: "번개는 발사체를 읽지 않는다 … 순수 손해" → "번개는 발사체를 연쇄 수로 받는다(413~414행). 흠은 계열과 무관한 가중 16이 연쇄 수가 클 때도 같은 점수를 주는 것이다. 연쇄 4 이상에서는 손해다." ② 3절 첫 사례 → "번개 연쇄 4·5 + `splitting` 무기 대 피해 +10% 마법 무기는 더 좋음이 아니고, 연쇄 3에서는 더 좋음이다." GM3의 F2b 해석(번개는 `galvanic` 둘)은 `splitting`과 무관해 그대로 둔다 | 앞 문서의 틀린 전제를 남기면 다음 사람이 loot.json에서 번개의 `projectiles`를 빼서 "표 대 코어" 검사를 깬다 | — |
| VO3 | **판당 알림 수의 자를 바꾼다. 띠 9~14는 옮기지 않는다.** 이번 값이 띠와 비교할 수 없는 까닭은 셋이다. ① D21 1.2의 12.1은 모델의 답이 아니라 **실행값**이다(실제 코어·자동 조작·9판). layer2c 3절의 "[모델의 답으로 판정]"은 내가 잘못 붙였다. ② D21은 **우두머리 처치 전("판 중")**의 판정만 셌다. `report_run_loot`의 `better_yes`는 우두머리 처치 때 쓸어 담는 약 12개까지 센다. ③ 켠 쪽도 자동 조작이 제 가중치로 입었다. 그래서 켠 쪽의 비교 대상(착용)이 판정과 다르다. 새 자: 자동 조작이 켠 때 `upgrade_verdict`로 입게 하고, **우두머리 처치 전의 `better_yes`**를 센다. 판은 3계열 × 시드 11~16(18판). 끈 쪽도 같은 자로 함께 적는다 | 같은 자로 재야 띠와 견줄 수 있다. 띠는 D21이 판정 수의 범위로 정했고, 그 값을 결과에 맞춰 옮기지 않는다 | 보 · 도 |
| VO4 | **`better_min` 1.5는 지금 올리지 않는다.** 판정선을 결과보다 먼저 정한다. 새 자로 켠 쪽 18판 평균이 9~14면 1.5 그대로 통과. 14를 넘으면 `better_min`을 2.0 → 2.5 → 3.0 순으로 올려 처음 띠에 드는 값을 고른다. 3.0(공격 약 +5%)으로도 넘으면 멈추고 보고한다(문턱이 아니라 줍는 수의 문제다). 9 아래면 1.0을 한 번 본다. 어느 경우든 layer2c 3절의 사례 시험이 모두 그대로 통과해야 한다 | `better_min`은 명세에서 "[가설: 알림 수로 맞춘다]"였던 손잡이다. 띠는 고정이고 손잡이만 움직인다 | 보 |
| VO5 | (가) 희귀 +30% 무기가 `splitting` 무기 자리를 바꿔 끼는 경우의 +1.16 → "더 좋음" 아님을 **받는다.** 공격 약 +2%는 바꿔 끼기(옆걸음)다. 희귀의 이름 색·소리는 판정과 따로 나므로 얻는 기쁨은 남는다 | 알림이 잦으면 ▲를 믿지 않게 된다 | 보 |
| VO6 | (나) 샷 수 b·c는 **장비를 뺀 값이 맞다(지금 구현 그대로).** 트리·은총은 포함한다 | Sh = 1 + 0.5 × Σ장비 발사체 ÷ b다. b에 장비를 넣으면 분자와 분모가 같은 장비를 두 번 센다 | — |
| VO7 | (다) 반지: 켜기 전에 **gameplay-systems**가 고친다. 켠 때만 `chapter_core.target_slot`이 반지에 `upgrade_verdict`가 고른 칸(빈 칸 먼저, 다 차면 V가 더 오르는 쪽)을 돌려주고, 장착(코어와 `chapter_one.gd`의 카드 수락)이 그 칸을 쓴다. 꺼진 경로는 지금 그대로 `ring` 고정이다. 시험: 반지 둘을 낀 채 둘보다 센 반지를 주우면 약한 쪽이 바뀐다 | 명세 6번이 함수에만 있고 게임에는 없다 | 보 · 성 |

## 2. 배정문

### VO-B gameplay-systems — 자동 조작과 반지 칸, 알림 수 측정(VO3·VO4·VO7)

본 저장소 HEAD(16ca1ec 이후)에서 작업 폴더를 연다. 게임 수치는 고치지 않는다. `better_min`은 VO4의 차례로만 바꾸고, 바꿀 때 값과 판정을 보고한다.
1. `chapter1/core/chapter_pilot.gd`: `upgrade_verdict.enabled`가 참일 때만 `loot.upgrade_verdict`가 "더 좋음"이라 한 것을 그 칸에 입는다. 꺼지면 지금 가중치 그대로다.
2. `chapter1/core/chapter_core.gd`·`chapter1/app/chapter_one.gd`: VO7.
3. `chapter1/tests/report_run_loot.gd`: 인수가 있을 때 `counts`를 우두머리 처치 전과 후로 나눈다. 인수가 없으면 출력은 글자 단위로 그대로다.
4. `chapter1/tests/test_loot.gd`: 번개 연쇄 3 사례(+1.79)를 단언으로 바꾼다. 반지 사례를 더한다.
5. 명령: `python tools/dev/run_all.py --quick`, `golden_core.gd -- --both`(바뀌면 안 된다), `report_run_loot.gd -- --seeds=11,12,13,14,15,16 --primary=chapter1.skill.{ember,frost,arc} --upgrade-verdict=on`과 `=off`.
6. 보고: 계열 × 켬/끔의 처치 전 `better_yes` 평균과 범위(18판씩), VO4의 판정, 고른 `better_min`.

### GM-C(layer2c 4절)에서 바뀐 줄

- 머리: "GM-B 뒤" → "VO-B의 `better_min` 판정 뒤". `sim_loot`의 verdict 착용은 `better_min`을 넘는 것만 입으므로 문턱이 바뀌면 묶음도 바뀐다.
- 1번 명령: 묶음 이름의 머리는 `kit.f2v.`다(`sim_loot.gd` 340행). 3·4번의 `kit.f2c.@.r15`는 `kit.f2v.@.r15`로 읽는다.
- 2번에 더한다: 번개 묶음의 `splitting` 수(VO1로 번개도 연쇄가 적을 때 `splitting`을 입는다).

## 3. 미평가

번개 1랭크에서 `splitting`을 끼고 연쇄가 늘어나는 것이 기쁜지, ▲가 드물어진 판(문턱을 올린 경우)이 덜 신나는지. 사용자 플레이로만 채운다.

## 4. 켜는 장부에 넣을 문안(디렉터가 `DIRECTIVES-LEDGER.ko.md` 2절에 넣는다)

`upgrade_verdict.enabled`(loot.json, 16ca1ec, 꺼짐) — 남은 일: ① 자동 조작이 켠 때 같은 함수로 입기(VO-B) ② 반지 칸 연결(VO7, VO-B) ③ 처치 전 알림 수 18판이 띠 9~14 안, 필요하면 `better_min`을 VO4 차례로(VO-B) ④ 득템 패의 글 두 줄("빈 칸 · 이 계열에는 효과 없음", "전설 · 이 계열에는 약함")과 `hud.offer_upgrade`가 `note`를 읽기(narrative-lead 낱말 검사 → ui-hud) ⑤ 켠 경로의 골든 ⑥ 사용자 플레이. 근거: `docs/reviews/DESIGN-REVIEW-20261124c-verdict-open.ko.md`.
