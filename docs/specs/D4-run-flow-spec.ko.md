# D4 판 흐름 — 메뉴로 돌아가기, 포기, 종료, 쓰러진 뒤

2026-11-17 · 작성: 기획 책임자(design-lead) · 대상: `gameplay-systems`(코어 한 함수, 앱), `ui-hud`(화면, `hud_dump.gd`) · 판정: 총괄 디렉터
근거: `docs/reviews/PLAN-GAP-AUDIT-20261117.ko.md` 요약 5. 코드를 읽어 썼고 Godot는 실행하지 않았다. 행 번호는 이 문서를 쓸 때의 것이므로 함수 이름으로 찾는다.

## 디렉터용 요약

1. 지금은 판이 끝나면 같은 기술로 다시 도전하거나 보관함을 여는 것만 된다. 다른 마녀를 고르려면 게임을 껐다 켜야 한다. 정지 화면에는 포기·종료가 없고, 메뉴에도 종료 단추가 없다.
2. **메뉴로 돌아가기는 앱만 고치면 된다.** 앱이 코어 객체를 새로 만들면 시작할 때와 똑같은 메뉴 상태가 된다. 코어 수정은 없고 골든과도 무관하다.
3. **포기는 코어에 함수 하나(`abandon()`, 10줄 안팎)를 더하는 쪽을 권한다.** 그러면 쓰러졌을 때의 저장 경로와 결과 창을 그대로 쓴다. 골든이 쓰지 않는 함수이고 `snapshot()`의 키를 늘리지 않으므로 골든 해시는 바뀌지 않아야 한다. 확인은 골든 실행으로 한다.
4. 코어 동결이 풀리지 않으면 대안이 있다. 앱이 직접 쓰러진 판처럼 저장한 뒤 바로 메뉴로 보낸다(결과 창 없음). 디렉터가 고른다.
5. 쓰러진 순간 결과 창이 바로 덮어 죽은 장면이 보이지 않는다. 승리처럼 1.2초 늦추고, 창이 뜨기 전의 R 키를 막는다. 표현만 바꾼다.
6. (선택) "쓰러진 원인" 한 줄은 코어 이벤트에 출처 필드를 더해야 한다. 이벤트 버퍼는 `snapshot()` 밖이라 골든에 영향이 없어야 하지만 확인이 필요하다. 범위에 넣을지는 디렉터가 정한다.
7. 파일: `chapter_one.gd`는 T1 지시서 4(R1·R4)와, `chapter_hud.gd`는 A2 지시서 2-B·3-B·4·5와 T1 지시서 4(R4)와 겹친다. 동시에 돌리지 않는다. 순서는 6절에 있다. 프레임 측정 창은 필요 없다.
8. 사용자 결정은 필요 없다. 포기를 쓰러짐과 같게 저장하는 것(3.2)만 디렉터가 확인한다.

**지난 점검의 정정.** `PLAN-GAP-AUDIT` 2.5절 C3은 "결과 창 문구가 다른 기술로 다시 도전할 수 있다고 한다"고 적었다. 그 문장(`chapter_hud.gd` 260행)은 옛 층 `_build_modal__cloister` 안에 있고, 최종 결과 창은 `_build_result40__q40`(1070행)이 `_clear_modal40()`으로 모달을 비운 뒤 새로 그린다. **화면에는 나오지 않을 가능성이 크다.** 남는 문제는 "다시 도전" 단추가 같은 마녀로만 다시 시작한다는 것을 알려 주지 않는다는 것이다. 화면으로 확인하지는 않았다.

---

## 1. 지금의 동작(코드 근거)

| 무엇 | 지금 | 근거 |
|---|---|---|
| 코어의 메뉴 상태 | `mode`가 "menu"인 것은 객체를 만들 때뿐이다. 다시 "menu"로 돌아가는 함수가 없다 | `core/combat_core.gd` 46행 `var mode := "menu"`, 116행 `start()`가 "playing"으로. 192행 `_refresh_mode()`는 "menu"에서 아무것도 하지 않는다 |
| 다시 도전 | 같은 객체에서 `start()`를 다시 부르고, 시드는 +1, 기술은 그대로 | `app/chapter_one.gd` 127~129행 `retry()` → `start_run(primary)` |
| 결과 창 | 승리: 제목, 시간·처치·레벨, 착용 8칸, 보상과 저장 상태, [보관함에서 다음 장비 선택][이번 도전 장비 확인][다시 도전], 영구 성장 상자. 패배: [이번 도전 장비 확인]이 없다 | `view/hud/chapter_hud.gd` 1070~1104행(`_build_result40__q40`), 1306~1314행(`_build_result40`, 저장 비활성 때 단추 숨김) |
| 결과 창이 뜨는 때 | 승리는 1.3초 뒤, 패배는 바로 | `chapter_hud.gd` 457~462행(`sync__q17`, `_victory_age`) |
| R 키 | 승리·패배면 바로 다시 도전. 승리 창이 뜨기 전 1.3초 동안에도 먹힌다 | `chapter_one.gd` 182~183행 |
| 정지 | Esc, 창이 포커스를 잃으면 자동. 정지 창: "잠시 멈춤", 설명, [계속하기], 흔들림 토글, 그리고 q45 층이 끼우는 조작 안내 두 줄 | `chapter_one.gd` 77~78·147~150·171~173행, `chapter_hud.gd` 252~256행, 1237~1251행(`_build_modal__q45`는 상자의 자식 수가 정확히 4일 때만 배치를 고친다) |
| 게임 종료 | QA 종료 경로에만 `get_tree().quit()` | `chapter_one.gd` 303행 |
| 쓰러짐 | 생명 0이면 코어가 `_terminal_mode="defeat"`, "defeat" 이벤트. 앱이 그 이벤트에서 저장한다(`record_run`, 승리 플래그 거짓: 주운 장비·경험치는 저장, 완료 수는 그대로) | `combat_core.gd` 549~552행, `chapter_one.gd` 493행 → 447~460행 `_save_terminal()`, `core/chapter_profile.gd` 289~312행 |
| 뷰가 코어를 읽는 방식 | 액터·효과·HUD는 프레임마다 `view.run`이나 인수로 받은 `run`을 읽는다. 따로 붙잡아 두는 것은 자동 조작(`full_pilot.run`)뿐이다 | `chapter_one.gd` 272~277·347~348행, `view/actors/chapter_actors.gd` 133행 `view.get("run")` |
| 골든이 해시하는 것 | `run.snapshot()`. 이벤트 버퍼는 들어가지 않는다 | `tests/golden_core.gd` 22행, `combat_core.gd` 934~939행, `chapter_core.gd` 769~780행 |
| 카메라 | 주인공이 없으면 카메라를 옮기지 않는다. 판이 끝난 자리에 남는다 | `chapter_one.gd` 272~273행 |

---

## 2. 바뀐 뒤의 흐름

```
메뉴 ──시작──▶ 판 ──Esc──▶ 정지 ─┬─ 계속하기 ─▶ 판
  ▲  │                          ├─ 이번 판 포기 ─▶ 확인 ─▶ 결과 창(포기)
  │  └─ 게임 종료                └─ 게임 종료 ─▶ 확인 ─▶ (포기로 저장) ─▶ 종료
  │
  │   판 ──쓰러짐──(1.2초)──▶ 결과 창(패배) ┐
  │   판 ──승리────(1.3초)──▶ 결과 창(승리) ┤
  │                                        ├─ 같은 마녀로 다시 도전 [R]
  └──────────────── 메뉴로 · 마녀 바꾸기 ◀─┤
                                           ├─ 보관함 / 이번 도전 장비 확인(승리) / 스킬 트리(영구 성장 상자)
                                           └─ 게임 종료
```

### 2.1 규칙

| # | 규칙 | 이유 |
|---|---|---|
| F1 | 결과 창에 "메뉴로 · 마녀 바꾸기"를 더한다. 누르면 시작할 때의 메뉴와 같은 상태가 된다(빈 회랑, 세 마녀, 마녀 요약은 방금 저장한 값) | 다른 마녀를 고를 길 |
| F2 | "다시 도전"은 "같은 마녀로 다시 도전 [R]"으로 바꾼다. 동작은 그대로(시드 +1, 같은 기술) | 동작을 이름에 드러낸다 |
| F3 | 메뉴에서 새로 시작할 때 시드는 직전 판의 시드 +1. 처음 실행의 첫 판만 지금 시드(`seed_`) | 메뉴를 거쳐도 같은 판이 되풀이되지 않게 |
| F4 | 정지 화면에 "이번 판 포기"와 "게임 종료"를 더한다. 둘 다 확인을 한 번 거친다. 확인 창에서 Esc는 취소 | 실수 방지 |
| F5 | 포기 = 쓰러짐과 같은 저장. 그 판에서 주운 장비와 영구 경험치는 저장되고, 완료 수는 늘지 않는다. 결과 창 제목은 "이번 도전을 포기했습니다" | 3.2절 |
| F6 | 정지 화면의 "게임 종료"는 포기로 저장한 뒤 끈다. 저장이 실패하면 끄지 않고 "저장하지 못했습니다 · 그래도 종료 / 취소"를 묻는다 | 보상을 말없이 잃지 않게 |
| F7 | 메뉴와 결과 창에 "게임 종료"를 둔다. 확인 없이 끈다(저장할 판이 없다). 결과 창에서 저장이 실패한 채라면 F6과 같이 묻는다 | — |
| F8 | 결과 창에서 저장이 실패한 상태(`_saved_receipt != _receipt`이고 저장이 켜져 있음)로 "메뉴로"나 "다시 도전"을 누르면 묻는다: "저장되지 않은 보상이 있습니다" [저장 다시 시도] [그래도 계속] [취소] | 지금은 말없이 잃는다 |
| F9 | 패배 결과 창은 쓰러진 뒤 1.2초에 뜬다. 그동안 화면은 쓰러진 장면을 보여 준다(코어는 이미 멈춰 있다) | 왜 죽었는지 볼 시간 |
| F10 | 결과 창이 화면에 뜨기 전에는 R 키와 결과 창 단추가 먹지 않는다(승리 1.3초, 패배 1.2초) | 창을 보지 못한 채 다음 판으로 넘어가는 실수 방지 |
| F11 | 창 닫기(×)는 지금처럼 바로 꺼진다. 판 중의 × 처리(포기로 저장하고 끄기)는 이 명세에 넣지 않는다(7절 선택 항목) | 엔진 종료 요청을 가로채면 QA 종료 경로까지 살펴야 한다 |

### 2.2 문구(자리표. 서사 말투는 narrative-lead가 고칠 수 있다. 글자 수는 지금 글꼴 기준)

| 자리 | 문구 |
|---|---|
| 결과 단추 | "같은 마녀로 다시 도전 [R]", "메뉴로 · 마녀 바꾸기", "게임 종료" |
| 정지 단추 | "계속하기 [Esc]", "이번 판 포기", "게임 종료" |
| 포기 확인 | 제목 "이번 판을 포기할까요?" / 본문 "지금까지 주운 장비와 경험치는 쓰러졌을 때처럼 저장됩니다." / [포기] [취소] |
| 종료 확인(판 중) | 제목 "게임을 끌까요?" / 본문 "이번 판은 포기로 저장됩니다." / [저장하고 종료] [취소] |
| 포기 결과 제목 | "이번 도전을 포기했습니다" |
| 저장 실패 물음 | "저장되지 않은 보상이 있습니다" / [저장 다시 시도] [그래도 계속] [취소] |
| 저장 비활성(검증 실행) | 포기 본문을 "검증 실행에서는 저장하지 않습니다."로 바꾼다(지금의 `_rewrite_diagnostic46` 방식) |

---

## 3. 코어를 건드리는가

### 3.1 메뉴로 돌아가기 — 앱만(코어 수정 없음)

앱이 코어 객체를 새로 만든다. `ChapterRun.new()`의 상태는 처음 실행한 메뉴와 같다(`mode="menu"`, `hero={}`). 뷰는 `view.run`을 프레임마다 읽으므로 참조를 바꾸면 따라온다.

할 일(앱, `chapter_one.gd`에 새 함수 `return_to_menu()`):
1. 결과 창 상태(`run.mode in ["victory","defeat"]`)에서만 동작한다. 그 밖에서는 아무것도 하지 않는다.
2. `run = ChapterRun.new()`, `full_pilot.run = run`.
3. `actors.reset()`, `effects.reset()`, `juice.reset()`(있으면), `hud.reset()`, `audio.reset()`, `audio.set_paused(true)`. 이벤트 커서(`_chapter_last_event`, `_last_audio_event`)를 -1로, `_has_move_target=false`.
4. 카메라를 처음 메뉴의 자리로 되돌린다. `world.update_camera(Vector2.ZERO, 큰 delta)`로 한 번에 맞는지 먼저 본다. 맞지 않으면 `chapter_world.gd`에 `reset_camera()`를 더해야 하는데, 이 파일은 T2-4와 T1 지시서 4 R2가 고치는 파일이라 디렉터 확인 뒤에 한다. 같은 프레임의 3D 덤프에서 카메라 변환이 처음 메뉴와 ±0.01 안이면 된다.
5. 시드: `seed_ += 1`(F3). `run_character_id`, `run_progress`, `view_before`, `view_after`를 비운다. `hud.stash_open=false`, 열린 스킬 트리를 닫는다.
6. `_sync_profile(...)`로 마녀 요약을 새 저장값으로 다시 그리고, `hud.invalidate()`.

뷰가 따로 붙잡은 참조가 더 있는지 구현자가 `grep -n "run" chapter1/view` 결과로 확인해 보고서에 적는다(지금 확인한 것은 자동 조작 하나).

**골든 영향 없음.** 코어 파일을 고치지 않는다. 다만 "메뉴를 거친 뒤 시작한 판"이 "처음 실행에서 시작한 판"과 같은 판인지는 앱 수준에서 확인한다(5.2절 H3).

### 3.2 포기 — 코어 함수 하나(권고)

**`combat_core.gd`에 `abandon() -> bool`를 더한다.**

```gdscript
## The player gives up. Same terminal path as a defeat: the app saves the run as a defeat.
## Only from a live run; never from the menu or after the end. Not used by the golden replay.
func abandon() -> bool:
	if mode == "menu" or not _terminal_mode.is_empty(): return false
	_inventory_open = false
	_terminal_mode = "defeat"
	_refresh_mode()
	_emit("defeat", hero.position, {"abandoned": true})
	return true
```

- `snapshot()`에 키를 더하지 않는다. 포기했다는 사실은 앱이 `_abandoned` 플래그로 들고 HUD에 넘긴다(결과 제목). `snapshot()`에 키를 더하면 모든 골든 해시가 바뀐다.
- `_record()`(chapter_core의 `history`, 스냅숏 안)를 부르지 않는다.
- 이 함수는 골든과 측정 도구가 부르지 않는다. **골든 해시 4건이 그대로여야 한다.** 바뀌면 다른 결함이다. 갱신(`--update`)하지 않는다.
- 저장: 앱의 "defeat" 이벤트 처리(`chapter_one.gd` 493행)가 그대로 `_save_terminal()`을 부른다. 승리 플래그는 거짓이다.
- 뷰: "defeat" 이벤트를 소비하는 곳은 HUD 결과 창뿐이다(`grep "\"defeat\"" chapter1/view` 결과). 주인공 쓰러짐 자세는 생명 0에 걸려 있어(`chapter_actors.gd` 233행 `_update_pose(..., run.hero.hp_raw...)`) 포기 때는 서 있는다. 그대로 둔다.

**포기를 쓰러짐과 같게 저장하는 이유.** 쓰러지면 이미 장비와 경험치를 저장한다. 포기에서 보상을 빼면 플레이어는 포기 대신 가만히 서서 죽는 쪽을 고르게 된다(선택이 사실상 하나뿐). 포기에 더 주면 판을 쉽게 끊는 반복이 생긴다. 같게 두면 둘 다 생기지 않는다. 다만 우두머리 직전에 포기해 그때까지의 경험치를 챙기는 반복이 지금 쓰러짐보다 빨라지는지는 사람만 안다(재미 위험, 8절).

**대안(코어 동결이 풀리지 않을 때).** 앱이 직접 `profile.record_run(_receipt, run.inventory, run.pending_rewards, false, run.tick, run.progress_summary())`를 부른 뒤 3.1의 메뉴 복귀로 간다. 결과 창 없이 메뉴에 알림 한 줄("포기한 판 저장 완료 · 장비 n개")만 남는다. 코어 수정이 없다. 판 중의 `progress_summary()`가 쓰러짐 때와 같은 계산인지(`chapter_core.gd` 237~244행, 상태만 읽음)는 같은 시드에서 "포기 시점 값 = 같은 틱에 쓰러진 판의 값"으로 확인한다.

### 3.3 쓰러진 뒤 — 표현만

- F9: `chapter_hud.gd`의 `sync__q17`에 있는 승리 지연(`_victory_age`, 1.3초)과 같은 방식으로 패배에 1.2초 지연을 둔다. 새 상수 `DEFEAT_REVEAL := 1.2`. 포기는 지연 없이 바로 뜬다(플레이어가 고른 끝).
- F10: 앱의 R 키 처리(`chapter_one.gd` 182~183행)와 결과 창 단추는 `hud.result_revealed()`(새 읽기 함수, `overlay.visible` 기준)가 참일 때만 동작한다.

### 3.4 (선택) 쓰러진 원인 한 줄 — 코어 이벤트 필드

- `_hero_damage(raw, from)`에 출처 꼬리표를 더한다. 예: `"melee:walker"`, `"charge:charger"`, `"bolt:ranged"`, `"heavy:<수호자 id>"`, `"hazard:ash_brand"`. 부르는 곳은 다섯 곳이다(`combat_core.gd` 400·421·709·805행, `chapter_core.gd` 478·738행). "hero_hit" 이벤트의 상세에 `source`로 싣는다.
- 이벤트는 `snapshot()` 밖이라 골든 해시에 들어가지 않는다(1절). 함수 인수만 늘고 계산·난수는 그대로여야 한다. **골든 4건 불변**으로 확인한다.
- 화면: 패배 결과 창의 부제 아래에 "쓰러뜨린 것: 돌격자의 돌진"(자리표) 한 줄. 마지막 "hero_hit" 이벤트에서 읽는다.
- 이것은 "이해할 수 없는 죽음"을 덜 수 있는 장치다. 하지만 D1·D2·T1 지시서 2-2와 같은 코어 파일을 고치므로 디렉터가 범위에 넣을지 정한다. 넣지 않으면 F9의 1.2초만 간다.

---

## 4. 지시서

### D4-K — 코어의 포기 함수(gameplay-systems)

| 항목 | 내용 |
|---|---|
| 시작 조건 | 디렉터가 코어 동결의 예외로 허락했다. 같은 때에 `combat_core.gd`·`chapter_core.gd`를 고치는 다른 작업(D1 3-2, D2 K1~K3, T1 지시서 2-2)이 돌지 않는다 |
| 고칠 파일 | `chapter1/core/combat_core.gd`(`abandon()`만), `chapter1/tests/test_chapter_run.gd`(검사 추가). 3.4를 넣으면 `combat_core.gd`·`chapter_core.gd`의 `_hero_damage` 호출부 |
| 건드리지 않을 파일 | `snapshot()`, `tests/golden/core_runtime.json`, 데이터 전부 |
| 검사(`test_chapter_run.gd`) | K-1 판 중 `abandon()` → 참, `mode=="defeat"`, 마지막 이벤트가 `{"type":"defeat","abandoned":true}`. K-2 정지·선택·인벤토리 상태에서도 참, 인벤토리는 닫힌다. K-3 메뉴·승리·패배 뒤에는 거짓이고 상태가 바뀌지 않는다. K-4 포기 뒤 `step()`이 틱을 늘리지 않는다(패배와 같음). K-5 포기 뒤 `start(시드)` → 같은 객체에서 그 시드로 처음 시작한 판과 600틱 상태 해시가 같다(같은 epoch 수로 맞춰 비교: 비교 대상도 `start` 두 번). K-6 `snapshot().keys()`가 포기 전후로 같다. (3.4를 넣으면) K-7 "hero_hit" 이벤트마다 `source`가 있고 알려진 꼬리표 목록 안에 있다 |
| 통과 기준 | `python tools/dev/run_all.py --only chapter,golden` 통과, 골든 4건 불일치 0(갱신 없이). `python tools/dev/run_all.py --quick` 통과 |

### D4-A — 앱(gameplay-systems)

| 항목 | 내용 |
|---|---|
| 시작 조건 | D4-K가 끝났거나, 디렉터가 3.2의 대안을 골랐다. T1 지시서 4의 R1·R4(`chapter_one.gd`)가 같은 때에 돌지 않는다 |
| 고칠 파일 | `chapter1/app/chapter_one.gd` |
| 할 일 | (1) `return_to_menu()`(3.1). (2) `abandon_run()`: `_abandoned=true` → `run.abandon()` → `_consume_events()`(저장은 기존 경로) → `hud.set_result_reason("abandoned")`. 대안이면 3.2의 직접 저장 + `return_to_menu()`. (3) `quit_game()`: 판 중이면 `abandon_run()` 뒤 저장 성공 때만 `get_tree().quit()`, 실패면 HUD에 물음(F6). 메뉴·결과 창에서는 F7·F8. (4) R 키를 `hud.result_revealed()`로 막음(F10). (5) 시드 규칙(F3): 처음 실행의 첫 판 이후의 모든 시작은 `seed_+1`. (6) HUD 신호 연결: `menu_return`, `abandon_request`, `quit_request`, `save_retry`(기존) |
| 하지 말 것 | 저장 경로·저장 형식·`record_run` 인수 변경. QA 종료 경로(295~303행) 변경. 창 닫기(×) 가로채기 |
| 통과 기준 | 5절 H1~H6, `run_all.py --quick` 통과, 실행 로그 스크립트 오류 0 |

### D4-U — 화면(ui-hud)

| 항목 | 내용 |
|---|---|
| 시작 조건 | A2 지시서 1이 커밋됐다(2.8절 기록상 끝남). A2 지시서 2-B·3-B·4·5와 T1 지시서 4의 R4(hud 단계)가 같은 때에 돌지 않는다 |
| 고칠 파일 | `chapter1/view/hud/chapter_hud.gd`, `chapter1/tests/hud_dump.gd`(선택 인수 추가만) |
| 할 일 | (1) 신호 `menu_return`, `abandon_request`, `quit_request`. (2) 결과 창 단추 F1·F2·F7(최종 진입점 `_build_result40`, 1306행에서 덧붙인다. 옛 층 `_build_result40__q40`과 `_build_modal__cloister`는 고치지 않는다). 저장 비활성 때 숨기는 단추 목록(1312행)에 영향이 없어야 한다. (3) 정지 창 단추 F4: **최종 진입점 `_build_modal`(1337행)에서 덧붙인다.** `_build_modal__q45`가 상자 자식 수 4를 전제로 배치를 고치므로(1239행) 그보다 앞 층에 넣으면 배치 코드가 건너뛰어진다. (4) 확인 창(포기, 판 중 종료, 저장 실패 물음). 같은 모달 위에 겹치는 작은 창. Esc = 취소, Enter = 기본 단추. 기본 초점은 [취소]. (5) 메뉴에 "게임 종료"(`_build_menu41` 결과 위에 최종 진입점에서). (6) F9 패배 지연, `result_revealed()`, `set_result_reason()`과 포기 제목. (7) 2.2절 문구. (8) 키보드 초점이 새 단추를 모두 지나간다(`_focus_modal38` 목록에 들어감) |
| 하지 말 것 | 코어 상태 쓰기. 저장 호출. 색 상수 직접 쓰기(A2 지시서 1의 `palette.gd` 토큰만). 글자 크기 14 미만 |
| 통과 기준 | 5절 H1~H8 |

### `hud_dump.gd`에 더할 선택 인수(ui-hud)

기본 시점 목록과 순서는 바꾸지 않는다(지금 규칙과 같다).

| 인수 | 하는 일 | 덤프 시점(이 순서) |
|---|---|---|
| `--flow-shots=abandon` | 메뉴 → 첫 시작 → 600틱에 정지 → [이번 판 포기] 누름 → 확인 → 결과 → [메뉴로] → 메뉴에서 다른 계열 시작(첫 계열이 ember면 frost, 아니면 ember) → 120틱 | `menu`, `flow-paused`, `flow-abandon-confirm`, `flow-end-abandon-result`, `flow-menu-returned`, `flow-playing-after-return-120` |
| `--flow-shots=defeat` | `--defeat-at=<틱>`(기본 1200)에 검사 도구가 `run.hero.hp_raw=1`로 둔다(검사 도구만 하는 일, `_mock_result`와 같은 성격). 다음 피격으로 쓰러진 뒤 | `flow-defeat-0.5s`(창 없어야 함), `flow-defeat-result`(2.0초), 그리고 `flow-defeat-r-blocked`(쓰러진 뒤 0.3초에 R 키를 넣고 0.5초 뒤의 상태) |
| `--flow-shots=quit` | 메뉴에서 [게임 종료]를 누른다 | 덤프 없음. 프로세스가 0으로 끝나고 `CHAPTER1_QUIT {"from":"menu"}`를 찍는다(앱이 종료 직전에 찍는 줄, D4-A가 더함) |

각 시점에 `HUD_DUMP` 줄과 함께 `FLOW {"mode", "primary", "seed", "abandoned"}`를 찍는다. 3D 덤프(`--scene`)를 함께 쓰면 `menu`와 `flow-menu-returned`를 비교할 수 있다.

---

## 5. 검증

모든 실행에 `--chapter1-profile-off`를 붙인다. 저장을 보는 실행은 `--profile-fixture=empty --profile-tag=d4-<이름>`으로 `res://_local/shots/ui-g1p4/profiles/` 아래의 격리 파일만 쓴다. 사용자 폴더(`%APPDATA%\WitchMoira`)는 열지 않는다.

### 5.1 명령

```powershell
# 헤드리스 회귀
python tools/dev/run_all.py --only chapter,golden
python tools/dev/run_all.py --quick

# 흐름 덤프(헤드리스, 고정 프레임)
godot --headless --fixed-fps 60 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.ember --flow-shots=abandon --profile-fixture=empty --profile-tag=d4-abandon --dump=_local/d4/abandon.json --scene=_local/d4/abandon-scene.json
godot --headless --fixed-fps 60 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.frost --flow-shots=defeat --defeat-at=1200 --profile-fixture=empty --profile-tag=d4-defeat --dump=_local/d4/defeat.json
godot --headless --fixed-fps 60 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-profile-off --chapter1-qa-ignore-focus --flow-shots=quit

# 캡처(창, 두 해상도. 다른 Godot가 없을 때 차례로)
godot --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.ember --flow-shots=abandon --profile-fixture=empty --profile-tag=d4-cap1080 --shots=_local/d4/shots-1080 --dump=_local/d4/cap-1080.json
godot --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.ember --flow-shots=abandon --profile-fixture=empty --profile-tag=d4-cap720 --shots=_local/d4/shots-720 --dump=_local/d4/cap-720.json
```

(`godot`는 `C:/Project/rea-tools/godot-4.5.1/Godot_v4.5.1-stable_win64_console.exe`. 저장소 루트에서.)

### 5.2 통과 기준

| # | 기준 | 어디서 보나 |
|---|---|---|
| H1 | `FLOW` 줄의 모드 순서가 menu → playing → paused → defeat(abandoned 참) → menu → playing이다. 메뉴를 거친 뒤의 `primary`가 다른 계열이고 `seed`가 첫 판 +1이다 | abandon 덤프 출력 |
| H2 | `flow-menu-returned`의 HUD 덤프가 첫 `menu` 덤프와 Control 이름·보임 여부가 같다. 글자 차이는 저장 상태 줄과 마녀 요약 숫자로만 제한되고, 그 차이 목록을 보고서에 붙인다 | 두 덤프 비교 |
| H3 | `flow-menu-returned`의 3D 덤프에서 보이는 주인공·적 액터가 0개(첫 `menu`와 같은 수), 카메라 변환이 첫 `menu`와 ±0.01 | `--scene` 출력 |
| H4 | 격리 프로필 파일: 포기 뒤 영수증 +1, `completed_runs` 그대로, 장비 수 = 포기 전 저장 수 + 그 판 가방 수(보관 대기 포함), 서리·화염 등 그 마녀의 경험치 += 그 판의 `progress_summary().xp_gained`(저장이 켜진 판일 때). 숫자를 보고서에 적는다 | 프로필 파일을 다시 읽는 `HUD_DUMP_PROFILE` 줄 |
| H5 | `flow-defeat-0.5s`에서 결과 창이 보이지 않고 `flow-defeat-result`에서 보인다. `flow-defeat-r-blocked`에서 모드가 여전히 defeat이고 틱이 그대로다(다시 시작하지 않음) | defeat 덤프 |
| H6 | quit 실행이 종료 코드 0과 `CHAPTER1_QUIT` 줄로 끝난다. 정지 화면의 [게임 종료]는 저장 성공 뒤에만 끈다는 것을 D4-A 보고서에 코드 경로로 적는다(창 실행은 자동 검사가 어렵다) | 프로세스 종료 코드 |
| H7 | 1080p·720p 캡처에서 새 단추·확인 창의 겹침·잘림이 없고, 글자 14 이상, 대비 4.5:1 이상(A2 지시서 1 기준). 정지 창과 결과 창의 네 귀 좌표를 적는다 | `_local/d4/shots-*` |
| H8 | 키보드만으로 정지 → 포기 → 확인 → 결과 → 메뉴로 → 시작이 된다(Tab·방향키·Enter). 기존 메뉴·결과 검사(`hud_dump` 기본 시점의 해시)가 바뀌지 않는다. 바뀌면 바뀐 시점과 이유를 적는다 | 기본 `hud_dump` 실행의 `HUD_DUMP` 해시 전후 비교 |
| H9 | 골든 4건 불일치 0, 갱신 없음 | `run_all.py --only golden` |

프레임 측정은 필요 없다. 화면이 멈춘 상태의 창만 바꾸고 판 중의 그리기는 늘리지 않는다.

---

## 6. 순서와 다른 지시서와의 관계

| 파일 | 이 명세 | 겹치는 지시서 | 규칙 |
|---|---|---|---|
| `core/combat_core.gd` | D4-K | D1 3-2, D2 K1~K3, T1 지시서 2-2 | 동시에 하지 않는다. D4-K는 작으니 동결 예외로 먼저 끝내는 쪽을 권한다. 동결을 지키면 3.2 대안으로 간다 |
| `app/chapter_one.gd` | D4-A | T1 지시서 4 R1(옛 층 preload 제거), R4(층 메서드 정리), D5-A(저장 거부 흐름) | 동시에 하지 않는다. R1과는 고치는 줄이 다르다. 먼저 끝난 쪽 위에 뒤의 것이 함수 이름으로 다시 맞춘다. **D5-A와는 같은 담당이 차례로 한다**(둘 다 `start_run` 부근) |
| `view/hud/chapter_hud.gd` | D4-U | A2 지시서 2-B(재질), 3-B(타이틀), 4(은총), 5(결과), T1 지시서 4 R4(hud), D5-U(저장 거부 안내) | 동시에 하지 않는다. **D4-U는 A2 지시서 5보다 먼저 한다.** A2 지시서 5의 "콜백이 그대로" 목록에 "메뉴로·게임 종료"를 더해 달라고 art-lead에 알린다. A2 2-B가 먼저 끝났으면 새 단추가 그 재질을 따르고, 나중이면 2-B가 새 단추도 함께 칠한다 |
| `tests/hud_dump.gd` | D4-U | A2 지시서 3(`--menu-focus`), D5-U(`--profile-fixture=rejected`) | 인수만 더하므로 겹쳐도 되지만 같은 때에 같은 파일을 두 사람이 고치지 않는다 |
| `view/world/chapter_world.gd` | (3.1-4에서 필요할 때만) | T2-4, T1 지시서 4 R2 | 필요해지면 디렉터에게 먼저 묻는다 |

권하는 순서: **D4-K(또는 대안 결정) → D4-A ∥ D4-U(파일이 다르다. 신호 이름은 4절대로) → 디렉터의 흐름 캡처 확인.** T2(성능)와는 파일이 겹치지 않고 측정 창도 쓰지 않으니 함께 진행할 수 있다.

---

## 7. 이 명세에 넣지 않은 것

- 창 닫기(×)를 가로채 판 중이면 포기로 저장하는 것(`get_tree().set_auto_accept_quit(false)` + `NOTIFICATION_WM_CLOSE_REQUEST`). QA 종료 경로와 프레임 측정기의 종료(`frame_probe`)와 엮이는지 먼저 봐야 한다. 필요하면 따로 쓴다.
- 결과 창에서 바로 다른 마녀를 고르는 것. 메뉴를 거친다.
- 설정 화면(음량, 화면 모드, 키). 요약 8의 별도 명세다. 정지 화면에는 지금의 흔들림 토글만 둔다.
- 메뉴의 마녀 요약과 결과 창의 서사 문구(narrative-lead의 CHAPTER1-TEXT-PLAN 2.3).

## 8. 재미 위험(사람 평가 없음, 미평가)

- **포기로 경험치를 챙기는 반복.** 수호자 직전까지 봉인 몫 경험치를 모은 뒤 포기하고 다시 시작하는 것이 끝까지 하는 것보다 시간당 경험치가 높을 수 있다. 쓰러짐도 지금 같은 구조라 새로 생긴 문제는 아니지만 포기는 더 빠르다. `sim_progression.gd`의 판당 경험치(승리 1,000)와 구역별 몫을 보면 숫자로 비교할 수 있다. 문제가 되면 "포기는 경험치 절반" 같은 규칙이 필요하다. 지금은 넣지 않는다.
- **1.2초 지연이 답답할 수 있다.** 같은 판을 빨리 다시 하고 싶은 사람에게는 기다림이다. 길이는 사람 플레이로만 정할 수 있다.
- **확인 창이 너무 많을 수 있다.** 포기와 판 중 종료에만 둔다. 메뉴·결과 창의 종료는 묻지 않는다.

## 9. 확인하지 못한 것

- Godot를 실행하지 않았다. 새 코어 객체로 바꾸는 방식이 뷰의 내부 캐시(액터 풀, 효과 풀, HUD의 `_seen_gear` 등)와 충돌하지 않는지는 `reset()`들을 읽어 추정했다. H2·H3이 그 확인이다.
- `world.update_camera`가 한 번에 제자리로 가는지(부드럽게 따라가는 계수, `update_camera__q10`) 읽지 않았다.
- 결과 창 옛 층 문장(260행)이 정말 화면에 안 나오는지 덤프로 보지 않았다. `end-defeat-result` 덤프에서 그 글자가 없는지 D4-U가 확인한다.
- 포기 직후 결과 창에서 영구 성장 상자(`_add_growth_box`)가 쓰러짐과 같게 그려지는지는 저장 경로가 같다는 것에서 추정했다.
