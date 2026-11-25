# T10 — 첫 화면 겸 캐릭터 선택을 「세 문」으로 실제 게임에 적용 (작업 지시서, 2026-11-25)

작성: tech-lead. 문서만 썼다. 게임 코드·데이터를 고치지 않았고 Godot를 실행하지 않았다. `python tools/dev/screen_contract_check.py` 한 번만 돌렸다(지금 상태: 실패 0, `title: no screen file yet`, `title: no adapter file yet`).

- 받는 장부 줄: `docs/DIRECTIVES-LEDGER.ko.md` **U-30**(캐릭 선택창을 세련되게), **U-69**(고른 안: 11-21 원문 "캐릭터 선택은 아래꺼가 낫네 3마녀중 선택하는 게 커보이는 걸로" = 「세 문」), **U-128**(11-25 원문 "지금 메인에 캐리선택창부터 디자인 변경한걸로 적용되었나?" → "디자인 일관화로 전에 지시한건데 반영하고 아직 진행안된부분이 있는지 확인해줘").
- 명세 절: `docs/specs/A10-screen-unification-20261120.ko.md` 3.2 **W9**(캐릭 선택 본체 적용, "판 안 창(설정·종료)을 이 화면에서 뺌"), 같은 문서 1절(공통 겉), `docs/specs/T8-screen-contract-structure-20261120.ko.md` **S2**(첫 화면을 새 구조로)와 1·2·3·4·6·8절, `docs/screens/title/BRIEF-20261120.ko.md` 1절(화면 카드)·3.1·3.2(안 가 세 문), `docs/SCREEN-DESIGN-HARNESS.ko.md` 3.6~3.8.
- T8 S2와의 관계: S2는 "옛 화면을 모습 그대로 새 구조로 옮기고 디자인은 나중"이었다. 사용자가 이미 안을 골랐으므로 **같은 모습으로 한 번 옮기는 단계는 건너뛰고** 새 디자인을 새 구조로 바로 짓는다. 그래서 `equiv.py`의 "완전히 같음"은 메뉴 순간에서는 기준이 아니다(5.1절).
- 파일 번호: `docs/specs/T10-pity-save-key-and-tech-decisions-20261123.ko.md`가 이미 T10을 쓴다. 이 문서의 이름은 디렉터가 정해 준 대로 두었다. 번호를 고칠지는 디렉터가 본다.
- 표기: [봄] 이번에 파일·코드를 읽어 확인 · [가설] 판단, 확인할 것 · [미확인].

---

## 1. 목표와 끝난 모양

### 1.1 사용자가 게임을 켜면 보는 것

1. 검은 화면에서 로고 글 "Witch Moira"가 가운데 뜨고, 세 문(화염·냉기·번개)이 왼쪽부터 켜진다. 처음 초점이 간 마녀의 문이 화면 절반(960)으로 열리고 그 마녀가 발끝까지, 화면 높이보다 크게, 움직이는 초상으로 서 있다. 나머지 둘은 좁은 문(480)에 어둡게(밝기 0.30, 채도 0.20) 서 있다. 2.5초, 아무 입력이나 누르면 다 열린 상태로 건너뛴다.
2. 초점 마녀의 글 묶음: 이름·직업 제목 판과 촛대, 1인칭 한 줄, 시작 기술(아이콘·이름·한 줄 성격) 양피지, 레벨·경험치 띠·남은 포인트 ◆, 가죽 "시작" 단추, 둥근 손잡이 둘(스킬 트리 · 장비 N), 키 안내 한 줄. 좁은 문 아래에는 그 마녀의 이름과 "Lv N ◆N".
3. Q/E·←/→·마우스 올림(0.12초 머묾)·패드 좌우로 초점이 옮겨 가면 문 폭이 0.30초에 바뀌고, 새 마녀가 한 걸음 커지며 밝아지고, 글 묶음이 바뀐다.
4. Enter·시작 단추·패드 A를 누르면 1.2초의 확정 박자: 다른 두 문이 검게 닫히고, 고른 문이 화면 전체로 열리며, 얼굴·가슴 쪽으로 1.08배 다가가고, 계열의 터짐(자리 효과)과 계열색 섬광, 가장자리부터 닫히는 어둠. 두 번째 입력은 1.0초 지점으로 건너뛴다. 끝나면 판이 시작된다.
5. Esc(또는 오른쪽 위 작은 "메뉴" 단추)는 작은 창을 연다: 돌아가기 · 화면 흔들림 똑딱이 · 게임 종료. 이 화면 본문에는 설정·종료 단추가 없다(A10 W9).
6. 저장이 꺼진 판(`--chapter1-profile-off`, "저장 없이 하기")에서는 레벨 띠·◆·스킬 트리·장비 손잡이가 숨고, 왼쪽 위 로고 아래에 "검증 실행" 또는 "저장 꺼짐" 한 낱말과 상태 글이 작게 보인다.

### 1.2 다섯 요소

| 요소 | 이 화면에서 | 근거 |
|---|---|---|
| **섹시** | 세 마녀의 전신이 한 화면에, 초점 마녀는 발끝까지 화면 높이 이상, 움직이는 초상(숨·깜박임·계열 효과) | BRIEF 1.3, 3.2.7 |
| **쾌감** | 마우스만 올려도 문이 열리고 빛이 옮겨 감. 확정 때 두 문이 닫히고 그 마녀의 힘이 터짐 | BRIEF 3.1 확정 박자, 사크라타 은총의 "고른 순간의 터짐" |
| **성장** | 세 마녀 모두의 레벨·◆가 늘 보임. 쓸 포인트가 남은 마녀가 한눈에 | BRIEF 3.2.7 |
| **보상** | 손잡이의 "장비 N" — 약하게 | BRIEF 1.3 |
| 도박 | 키우지 않는다. 시안의 "확정 때 계약 악마가 0.5초"(BRIEF 3.5.3)가 이 화면에서 도박에 닿는 유일한 자리인데, 6절 결정 1의 권고대로 이번에는 넣지 않는다 | — |

---

## 2. 지금 구조와 시안 구조의 차이

### 2.1 지금 [봄]

- 앱 `chapter1/app/chapter_one.gd`: `_ready__chapter`가 인수를 읽고 `--chapter1-start`이면 첫 `hud.sync` **전에** `start_run(primary)`를 부른다(144행). 그래서 바로 시작하는 길에는 메뉴가 한 번도 지어지지 않는다. 메뉴는 `run.mode=="menu"`일 때 HUD가 짓는다.
- HUD `chapter1/view/hud/chapter_hud.gd`(평탄화한 파일, `이름__층` 사슬): `_build_modal` → `_build_modal__q45` → `__q41` → `__q40` → `__q38` → `__chapter` → `__cloister`. 메뉴는 `__cloister`의 `"menu"` 갈래(221~235행: 장 이름·설명·조작 줄·시작 단추 셋·흔들림 `CheckButton`·범위 줄·임시 그림 안내)를 짓고, `__chapter`(374~377행)가 보관함 단추와 `profile_note`를 더하고, `__q41`·`_build_menu41`(1055~1159행)이 **자식 번호 0~6으로 옛 상자를 뜯어** 왼쪽 초상 칸(`PortraitHost41` 안의 `LivingPortrait`)과 오른쪽 단추 열(`StartChoices41`)로 다시 붙이고, 시작 단추를 두 줄 글(`_two_line_choice`, 박힌 수치 줄 1131행)로 바꾸고, 음소거 단추를 더한다. `_add_flow_buttons`(2258행)가 `StartChoices41` 안 흔들림 줄에 `QuitGame` 단추를 붙인다. `_build_witch_summary`·`_refresh_witch_summary`(1807~1850행)가 레벨·경험치·포인트·`SkillTreeButton`을 그린다. `_focus_modal38`(812~833행)이 메뉴 전용 초점 순서를 고친다. `_sync_portrait`(1048행)가 메뉴가 보일 때만 초상을 돌린다.
- 앱이 화면의 사적 값을 읽는다: `menu_character_id()`(541~548행)가 `hud.get("_menu_witch")`.
- 시안 `chapter1/tests/proposals/title/`: `base.gd`(시계·상태·입력) ← `a.gd`(세 문), `parts.gd`(먼 배경·닫힘·터짐 자리 효과·초점 괄호·악마 자리표), `dress.gd`(글 묶음), `c.gd`(고르지 않은 안). 픽스처 `chapter1/tests/fixtures/ui/title_v0.*.json`(9개, 계약 0판), 스키마 `chapter1/tests/contracts/title.contract.json`(0판). 시안은 `tests/proposals/growth_choice/kit.gd`를 preload하고, 먼 배경을 `Image.load_from_file(globalize_path("res://…/L0_background.png"))`로, 악마 그림을 `_local/art/drafts/`에서 실행 중에 읽고, 움직이는 초상의 사적 필드 `_veil`을 `get("_veil")`로 고친다(a.gd 290행).

### 2.2 화면 계약 1판 — 대응표

시안 0판에서 화면이 실제로 그리는 것만 남긴다(T8 2.1: "쓸지 몰라" 넣지 않는다). 화면 파일에는 낱말 `run`·`growth`가 나오면 안 되므로(검사기 6번) 0판의 `growth`를 `level`로 바꾼다.

| 1판 필드 | 꼴 | 어디서 오나(어댑터가 읽는 곳) | 0판에서 |
|---|---|---|---|
| `focus_index` | int 0~2 | HUD가 가진 보이는 마녀 번호(지금 `_menu_witch`). 처음 값: 앱이 `--chapter1-primary=`를 받았으면 그 마녀, 아니면 0(화염, 6절 결정 3) | 같음 |
| `save` | enum `on` / `off` / `verify` | HUD `_save_mode()`(2135행: 앱의 `profile.available`, `_profile_off`) | `profile.enabled` + `qa_run`을 합침 |
| `note` | string ≤80 | HUD `profile_note`(앱 `_sync_profile`이 넣음). 가장 긴 실제 값은 `SESSION_NO_SAVE_NOTE`, "회수 장비를 해체해 256개 이하로…" 줄 | `profile.note` |
| `stash_count` | int ≥0, nullable | `profile_state.items.size()`. `save != "on"`이면 null(화면은 손잡이를 숨김) | `profile.stash_count` |
| `motion_on` | bool | HUD `motion_enabled`(흔들림 똑딱이 하나가 움직임 줄이기도 맡는다: 은총 화면이 `reduce_motion=not motion_enabled`) | `settings.{shake,motion}` |
| `witches[i].id` | enum `ember`/`frost`/`storm` | 순서 고정 화염·냉기·번개(`PORTRAIT_KEYS`) — 움직이는 초상의 id | 같음 |
| `witches[i].element` | enum `ember`/`frost`/`arc` | `WITCH_KEYS` | 같음 |
| `witches[i].start_ref` | string | `START_SKILLS[i]`. 신호 `start(skill_ref)`에 그대로 실음 | `start_skill_id` |
| `witches[i].character_ref` | string | `character_progression.json`에서 `signature_skill_id == start_ref`인 캐릭터 id(`chapter_profile.gd` `progression_doc()`, 지금 HUD `_character_for_skill`과 같은 규칙). 신호 `skill_tree(character_ref)`에 실음 | `character_id` |
| `witches[i].title` | string ≤16 | `Loc.t("character.<el>.name")` + " · " + `Loc.t("character.<el>.class")` → "테사 · 화염 소서리스" | 같음 |
| `witches[i].skill_name` | string ≤12 | `Loc.t("skill.<start_ref>.name")` | 같음 |
| `witches[i].skill_summary` | string ≤30 | 새 키 `title.witch.<el>.summary`(값은 0판 픽스처 = `docs/story/GRACE-GRADES-AND-TITLE-VOICES-20261120.ko.md` 7.3 권하는 안) | 같음 |
| `witches[i].line` | string ≤60 | 새 키 `title.witch.<el>.line`(값은 0판 픽스처 = 같은 문서 7.2 두 줄 안, 화염은 대안 2) | 같음(요청 필드였음) |
| `witches[i].traits` | array 0~3 of string ≤6, **requested** | 아직 없음(design-lead). 어댑터는 넣지 않고, 화면은 빈 줄을 숨긴다. 픽스처에만 0판의 자리 값 | 같음 |
| `witches[i].level` | object nullable `{value, bar, capped, points, has_tree}` | HUD `character_views[character_ref]`(= `profile.character_view(id)`): `value=level`, `bar=clamp((xp-xp_level_start)/max(1,xp_for_next-xp_level_start),0,1)`, `capped = xp_to_next<=0`, `points=points_free`, `has_tree`. 뷰가 비었으면 null | `growth`(날 수치 7개 → 그린 꼴 5개) |

0판에서 빼는 것과 까닭: `variant`·`note`(픽스처 설명)·`requested`(시안 메타) · `strings`(고정 문구는 화면이 `Loc` 키로 가진다, T8 2.1) · `build`(앱에 없음, 귀퉁이에 쓰지 않음) · `devil_mode`·`devil`(결정 1) · `confirm_line`·`confirm_line_on`·`title_autoswap`(안 나의 것) · `last_played`(저장에 없음, 결정 3) · `costume`(갈 화면이 없음 — 의상 손잡이를 이번에 빼므로) · `settings.muted`(음소거는 M 키와 알림 띠로 남음).

신호(1판): `start(skill_ref)` · `witch_focused(index)` · `stash()` · `skill_tree(character_ref)` · `menu()` · `ready_for_pick()`. 0판의 `settings()`·`quit()`는 `menu()` 하나로 합친다(Esc 창이 둘을 가진다).

변형(1판, 8개): `normal`(냉기 초점, Lv 8 ◆2, 장비 12) · `long`(가장 긴 실제 글: 제목·기술 이름·요약·`note`, 한 줄 60자 안) · `fresh`(저장 있음, 세 마녀 Lv 1 ◆0, 장비 0) · `profile_off`(`save:"verify"`, level 모두 null, `stash_count` null) · `points_many`(Lv 30 ◆27, 장비 256) · `focus_ember` · `focus_storm` · `reduced`(`motion_on:false`).

### 2.3 스키마 1판 원문 (U1-a가 이 내용으로 `chapter1/tests/contracts/title.contract.json`을 덮어쓴다)

```json
{
 "screen": "title",
 "contract_version": 1,
 "fields": {
  "focus_index": {"type": "int", "min": 0, "max": 2},
  "save": {"type": "enum", "values": ["on", "off", "verify"]},
  "note": {"type": "string", "max_len": 80},
  "stash_count": {"type": "int", "min": 0, "max": 9999, "nullable": true},
  "motion_on": {"type": "bool"},
  "witches": {"type": "array", "min": 3, "max": 3, "item": {"type": "object", "fields": {
   "id": {"type": "enum", "values": ["ember", "frost", "storm"]},
   "element": {"type": "enum", "values": ["ember", "frost", "arc"]},
   "start_ref": {"type": "string", "max_len": 40},
   "character_ref": {"type": "string", "max_len": 40},
   "title": {"type": "string", "max_len": 16},
   "skill_name": {"type": "string", "max_len": 12},
   "skill_summary": {"type": "string", "max_len": 30},
   "line": {"type": "string", "max_len": 60},
   "traits": {"type": "array", "min": 0, "max": 3, "item": {"type": "string", "max_len": 6}, "requested": "T3 낱말 셋(design-lead)"},
   "level": {"type": "object", "nullable": true, "fields": {
    "value": {"type": "int", "min": 1, "max": 99},
    "bar": {"type": "float", "min": 0.0, "max": 1.0},
    "capped": {"type": "bool"},
    "points": {"type": "int", "min": 0, "max": 999},
    "has_tree": {"type": "bool"}
   }}
  }}}
 },
 "variants": ["normal", "long", "fresh", "profile_off", "points_many", "focus_ember", "focus_storm", "reduced"],
 "signals": ["start(skill_ref)", "witch_focused(index)", "stash()", "skill_tree(character_ref)", "menu()", "ready_for_pick()"]
}
```

(`"_note"` 같은 설명 키를 넣고 싶으면 0판 파일처럼 넣어도 된다 — 검사기가 이미 0판에서 받았다. 필드를 하나라도 바꾸면 판 번호를 올린다, T8 2.3.)

### 2.4 시안에 없는데 지금 화면이 하는 일 — 빠지면 안 되는 것

| # | 지금 하는 일 [봄] | 새 화면에서 |
|---|---|---|
| K1 | 시작 → `hud.start.emit(skill_id)` → 앱 `start_run`(보관함 256개 초과면 보관함을 열고 막음, 저장 거부면 안내 창, 빌드·출발 장비 적용) | 확정 박자가 끝난 뒤 `start(start_ref)` → 호스트가 같은 `start.emit`. **앱이 출발을 거절해 메뉴에 남으면 화면은 다 열린 상태로 돌아와 다시 고를 수 있어야 한다**(시안은 `done`에서 멈춘다) |
| K2 | 초점 = 보이는 마녀 = 시작할 마녀(A4 D2), 마우스 올림이 초점을 가져감 | 그대로(시안 base.gd의 머묾 0.12초) |
| K3 | 보관함의 "다음 도전에 장착"은 보이는 마녀에게(`menu_character_id()`) | 호스트가 `witch_focused`로 번호를 받아 둔다. 앱은 호스트의 공개 함수만 읽는다(사적 값 읽기 갈래 삭제) |
| K4 | 스킬 트리를 염(`skill_tree_open(character_id)`), 트리가 없으면 "준비 중"으로 막힘, 저장이 꺼지면 숨김 | 손잡이 "스킬 트리"(◆ 수 배지). `level == null`이면 숨김, `has_tree == false`면 꺼진 손잡이 |
| K5 | 보관함 단추(개수) → `stash_show` | 손잡이 "장비 N". `stash_count == null`이면 숨김 |
| K6 | 흔들림 `CheckButton` → `motion_toggle`(앱: 세계 움직임 줄이기, 강림 효과) | Esc 창의 황동 똑딱이(같은 신호) |
| K7 | 음소거 단추 → `mute_toggle` | 단추는 뺀다. M 키(앱)와 알림 띠 "소리 꺼짐/켜짐"은 그대로 — **띠가 새 화면 위에 보여야 한다** |
| K8 | 게임 종료 단추 → `quit_request`(메뉴에서는 확인 없이 바로, `_dialog_alive("quit")`는 정지 중에만 산다) | Esc 창의 "게임 종료" → 지금과 같이 확인 없이 `quit_request` |
| K9 | `profile_note` 한 줄(저장 상태·오류) | 왼쪽 위 로고 아래 작은 글(`note`) + 저장 낱말(`save`) |
| K10 | 저장 거부면 메뉴 위에 안내 창이 뜨고 키보드를 가짐(`_sync_flow`: `rejected and run.mode=="menu" and not stash_open and overlay.visible and not skill_tree_is_open()`) | **`overlay.visible`이 참으로 남아야 한다**(은총 화면처럼 overlay는 보이게, 색은 투명, `modal`은 숨김). 안내 창이 새 화면 위에 보이고, 열려 있는 동안 새 화면은 키·마우스를 받지 않는다 |
| K11 | 키보드만으로 모든 길(Tab 초점 사슬) | Tab/↓/↑ = 시작 ↔ 트리 ↔ 장비, Enter = 실행, Q/E = 마녀. 패드: `ui_left`/`ui_right` 마녀, `ui_accept` 실행, `ui_cancel` = Esc 창 |
| K12 | 결과 창에서 메뉴로 돌아와도 마지막 마녀를 봄(`_menu_witch` 유지) | 같음. 돌아올 때는 등장을 다시 한다(메뉴에 "들어오는" 순간) |
| K13 | 초상은 메뉴가 보일 때만 돈다(보관함·트리 위에서는 멈춤) | 새 화면 전체(시계·초상 셋)가 덮여 있을 때 멈춘다 |
| K14 | 검증 실행 표시 | `save == "verify"` → "검증 실행" |
| K15 | 메뉴가 지어질 때마다(`invalidate()`가 잦다: `_sync_profile`, 보관함 닫기 등) 초점을 잃지 않음 | **다시 짓기가 등장을 되풀이하거나 초점을 되돌리면 안 된다.** 화면 하나를 메뉴 동안 살려 두고 `apply`로 글만 갈아 끼운다 |

### 2.5 지금 화면에 있는데 새 화면에서 빼는 것

| 뺄 것 | 가는 곳 / 까닭 |
|---|---|
| 장 이름 큰 제목·설명(`menu_title`·`menu_description`) | 판 시작 알림(`hud.notify(hud.notice.start)`)이 이미 있다. 장 이름에는 금지 낱말 대기 중(BRIEF 1.5) |
| 조작 안내 두 줄(`menu_scope`, 221~224행의 조작 줄) | 정지 창에 조작 안내가 한 번 있다(A10 W2, `pause_window.gd` 머리 주석). 이 화면에는 키 안내 한 줄만 |
| "첫 기술을 선택하세요" | 고르는 대상은 마녀다 |
| 시작 단추 셋의 박힌 수치 줄("기본 피해 12 · 화염탄 1발" 등, 1131행) | 한 줄 성격(`skill_summary`)으로. 수치는 스킬 트리 몫 |
| 흔들림 `CheckButton`, 음소거 단추, 게임 종료 단추 | Esc 창(A10 W9 "판 안 창(설정·종료)을 이 화면에서 뺌"), 음소거는 M 키 |
| 임시 그림 안내("캐릭터와 음향 일부는 제작 중입니다") | 뺀다. 화면 안 글로 알릴 일이 아니다 |
| 가운데 큰 판(`window_96`)과 초상 칸 | 장면 등급 화면은 틀로 가두지 않는다(A10 1.2) |
| 의상 손잡이(시안 dress.gd) | 의상 화면이 없다. 프로필에 `wardrobe_view()`는 있으니 의상 화면이 생기면 계약 판을 올려 되살린다 |
| 계약 악마(시안 parts.gd `Devil`) | 결정 1 |

---

## 3. 작업 쪼갬

### 3.1 한눈 표

| 묶음 | 담당 | 고치는 파일(이 밖은 건드리지 않음) | 의존 | 병렬 |
|---|---|---|---|---|
| **U1-a** 계약 1판과 시안 정리 | ui-hud | `chapter1/tests/contracts/title.contract.json`(덮어씀), 새 `chapter1/tests/fixtures/contracts/title.<변형>.json` 8개, 지움: `chapter1/tests/proposals/title/` 전부(`.uid` 포함), `chapter1/tests/fixtures/ui/title_v0.*.json` 9개. 고침: `chapter1/tests/proposal_smoke.gd`·`tools/dev/proposal_batch.py`의 title 갈래 삭제, `docs/TOOLS-INDEX.ko.md`·`tools/manager/tools_index.json`의 해당 줄 | 없음. **먼저 기준 캡처(3.2 U1-a 1번)** | 단독, 짧게. 디렉터가 바로 합친다 |
| **U1-b** 화면 본체 | ui-hud | 새 `chapter1/view/hud/screens/title.gd`, 새 `chapter1/view/hud/title_parts.gd`, 새 `chapter1/view/hud/title_block.gd`(+ 각 `.uid`), `chapter1/view/hud/living_portrait/living_portrait.gd`(공개 호출 둘 추가), `chapter1/view/hud/pause_window.gd`(`title` 종류 추가), `chapter1/i18n/ko.po`·`en.po`(새 키), `chapter1/tests/proposal_shot.gd`(`--screen=` 추가), `tools/dev/proposal_batch.py`(`title/screen` 한 줄) | U1-a 합친 뒤 | R1과 함께 |
| **R1** 어댑터 | refactor-architect | 새 `chapter1/view/contracts/title_contract.gd`(+ `.uid`), `chapter1/tests/test_screen_contracts.gd`의 `"title"` 경우 | U1-a 합친 뒤 | U1-b와 함께 |
| **R2** 호스트·앱·검사 도구 | refactor-architect, **`chapter_hud.gd` 점유** | `chapter1/view/hud/chapter_hud.gd`, `chapter1/app/chapter_one.gd`, `chapter1/tests/hud_dump.gd`, `chapter1/tests/portrait_select_shots.gd`, `chapter1/tests/scene_shot.gd`(옛 `title` 장면 삭제), `chapter1/tests/test_profile_app_loadout.gd`, 지움: `chapter1/tests/fixtures/ui/title.normal.json`·`title.long.json` | U1-b, R1 합친 뒤 | 단독(점유) |
| **U2** 실판 캡처 뒤 다듬기 | ui-hud | `screens/title.gd`, `title_parts.gd`, `title_block.gd`만 | R2 합친 뒤(또는 R2 작업 폴더 위에서) | 단독 |

- 같은 파일을 두 묶음이 같은 때에 고치지 않는다: U1-b와 R1은 파일이 겹치지 않는다. `test_screen_contracts.gd`는 R1만, `proposal_shot.gd`·`proposal_batch.py`는 U1만, `chapter_hud.gd`·`chapter_one.gd`·`hud_dump.gd`·`scene_shot.gd`는 R2만.
- R2가 화면 파일에 필요한 것을 찾으면 고치지 말고 보고서에 "화면에 필요한 것"으로 적는다 → U2.
- 점유 표시: R2 시작 때 디렉터가 장부 U-128 줄에 "파일 점유: chapter_hud.gd, chapter_one.gd"를 적고 합친 뒤 지운다(T8 6절). 지금 다른 지시서(D21 장비창, A-boss-finale 등)가 이 두 파일을 쓰는 중이면 R2를 그 뒤로 미룬다.
- 되돌리는 길: R2를 **한 커밋**으로 합친다. 그 커밋만 되돌리면 옛 메뉴가 돌아온다(U1·R1의 새 파일은 쓰이지 않은 채 남아도 검사가 통과한다).
- 작업 폴더: 각 묶음은 디렉터가 정한 작업 폴더(예: `D:/Project/witch-moira-work/t10-<묶음>`)에서 하고 패치와 보고서를 낸다(`PROCESS-CHECKS` 문③).

### 3.2 묶음별 지시서 (그대로 전달)

#### U1-a — ui-hud: 계약 1판과 시안 정리

> 지시서 `docs/specs/T13-title-select-apply-20261125.ko.md`의 2.2~2.3절과 이 단락을 따른다. 작업 폴더에서 하고 패치와 보고서를 낸다.
>
> 1. **먼저 기준 캡처**(지우기 전에, 작업 폴더에서): 시안 「세 문」의 정지·띠를 `_local/shots/t10/before-proposal/`에 남긴다.
>    `python tools/dev/proposal_batch.py --only title/a --res 1920x1080 --kinds still,strip-intro,strip-focus,strip-confirm,strip-reduced` 와 `--res 1280x720 --kinds still`. 도구가 쓰는 출력 폴더가 다르면 보고서에 실제 경로를 적는다. 지금 게임의 메뉴도 남긴다: `python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.frost --profile-fixture=l8 --tree-shots --shots=_local/shots/t10/before-game/l8-1080 --dump=_local/shots/t10/before-game/l8-1080.json`(1280x720도 한 번).
> 2. `chapter1/tests/contracts/title.contract.json`을 2.3절 원문으로 덮어쓴다(판 1).
> 3. `chapter1/tests/fixtures/contracts/`(새 폴더)에 `title.<변형>.json` 8개(2.2절 끝의 변형)를 만든다. 값은 `fixtures/ui/title_v0.<같은 이름>.json`에서 옮기고, 0판에만 있던 필드는 버린다. `long`은 실제로 나올 수 있는 가장 긴 글(T8 2.4, 지어낸 벽글 금지): 제목·기술 이름은 `ko.po`의 가장 긴 것, `note`는 `chapter_one.gd`에서 메뉴에 올 수 있는 가장 긴 문장, `line`은 `title.witch.*.line` 가운데 가장 긴 것. `profile_off`는 `save:"verify"`, `note:"검증 실행 · 저장 비활성"`. `reduced`는 `normal`에 `motion_on:false`.
> 4. 지운다: `chapter1/tests/proposals/title/`의 `a.gd`·`base.gd`·`c.gd`·`dress.gd`·`parts.gd`와 각 `.uid`, `chapter1/tests/fixtures/ui/title_v0.*.json` 9개. (까닭: 0판 픽스처는 `"screen":"title"`을 가져 검사기가 1판 스키마로 읽고 판 번호가 달라 실패한다. 시안 코드는 git 기록 `f3fbd3c`·`4c76e72`에 있고 U1-b가 거기서 옮긴다.) `proposal_smoke.gd`의 title 갈래(7행 preload, 23~24행, `_run_title`)와 `proposal_batch.py`의 `title/a`·`title/c` 줄을 지우고, 성장 선택 시안 갈래는 그대로 돈다. 도구 색인 두 곳에서 title 시안 줄을 고친다.
>
> **끝 기준**(결과 줄을 보고서에 그대로):
> - `python tools/dev/screen_contract_check.py` → `failures []`, notes에 `title: no screen file yet`, `title: no adapter file yet`, 고정 8개가 fixtures 수에 들어감.
> - `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_screen_contracts.gd -- --out=_local/t10/u1a` → `failures []`.
> - `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/proposal_smoke.gd`(인수는 그 파일 머리 주석대로) → 오류 0.
> - `python tools/dev/run_all.py --quick` → 통과.
> - `git status`에 `chapter1/view/`·`chapter1/app/`·`chapter1/core/` 변경 0.
>
> **건드리지 않음**: `chapter1/view/`, `chapter1/app/`, `chapter1/core/`, `chapter1/data/`, `fixtures/ui/title.normal.json`·`title.long.json`(R2가 지운다).

#### U1-b — ui-hud: 화면 본체

> 지시서 `docs/specs/T13-title-select-apply-20261125.ko.md` 1절(끝난 모양), 2.2~2.5절, 이 단락을 따른다. 출발점은 git `4c76e72`의 `chapter1/tests/proposals/title/a.gd`·`base.gd`·`parts.gd`·`dress.gd`(`git show 4c76e72:<경로>`). 디자인 값(문 폭·배율·초·글 크기)은 `docs/screens/title/BRIEF-20261120.ko.md` 3.1·3.2와 시안 코드 그대로 두고 바꾸지 않는다. 작업 폴더에서 하고 패치와 보고서를 낸다.
>
> **만들 파일**
> - `chapter1/view/hud/screens/title.gd`: `extends Control`, `class_name` 없음. `base.gd`와 `a.gd`를 **한 파일로 합친다**(상속하지 않는다 — 검사기는 `screens/`의 파일만 읽으므로 상속한 밑바탕은 검사에서 빠진다). `const CONTRACT_VERSION := 1`. 신호는 2.2절의 여섯 개와 이름이 정확히 같다(`start(skill_ref: String)`, `witch_focused(index: int)`, `stash()`, `skill_tree(character_ref: String)`, `menu()`, `ready_for_pick()`). 시안의 `chosen(index)`·`request(action, index)`는 이 여섯으로 바꾼다.
> - `chapter1/view/hud/title_parts.gd`(`parts.gd`에서): 먼 배경, 문 가장자리 덮개 셰이더, `Iris`·`Rise`, `Burst`(자리 효과 — 머리 주석에 "진짜 계열 터짐은 vfx-feel 줄"), `Marker`, `PointsTag`, `SkillIcon`, 초상 만들기. **`Devil` 클래스는 옮기지 않는다**(결정 1).
> - `chapter1/view/hud/title_block.gd`(`dress.gd`에서): 글 묶음(`build_block`), 가죽 단추, 레벨 띠, 손잡이, 키 안내 줄, 탭. **의상 손잡이는 뺀다.**
>
> **공개 호출**(호스트와 캡처 도구가 쓴다. 이름을 바꾸지 않는다)
> - `apply(contract: Dictionary) -> void`: 판이 다르면 `push_error`하고 아무것도 그리지 않는다. **처음 부르면 짓고, 이미 지어진 화면에 다시 부르면 글 묶음·이름표·귀퉁이 글만 다시 짓고 초점·상태·시계·초상은 그대로 둔다.** 계약의 `focus_index`는 처음 apply에서만 초점으로 쓴다.
> - `play_intro()`(2.5초 등장), `show_settled()`(새: 등장 없이 다 열린 `ready` 상태, 지금 초점으로. `confirm`·`done`에서 불려도 `ready`로 돌아온다 — 2.4 K1), `set_interactive(on: bool)`(새: 꺼지면 키·마우스·머묾을 받지 않고 시계와 초상 셋을 멈춘다 — K10·K13), `is_settled() -> bool`, `focused_index() -> int`, `set_focus(i)`(호스트의 `menu_select_skill`이 부른다; `witch_focused`를 낸다).
> - 시안 캡처 도구가 몰던 호출은 그대로 둔다: `static func make(c) -> Control`, `advance_to(t)`, `send(action)`, `set_motion(scale)`, `prepare_still(stage)`, `best_index()`, `try_pick(i)`, `skip_intro()`, `layout_report()`, 그리고 `state`·`events`·`unlock_t`·`capture_mode`·`reduce_motion` 값. 소리 고리 이름은 `events`에 `title_intro`, `witch_focus(<element>)`, `witch_confirm(<element>)`로 남긴다(소리는 붙이지 않는다).
>
> **시안에서 바꿀 것**
> 1. `res://chapter1/tests/`를 preload하지 않는다(내보낸 빌드에는 `chapter1/tests/`가 없다). 시안의 `Kit`(tests/proposals/growth_choice/kit.gd)은 `chapter1/view/hud/grace_draw.gd`(`lbl`, `glow`, `line_height`, `diamond`, `el_color`, `el_text`, `feather_material`, `SIZE`)와 `ui_parts.gd`로 바꾼다. `Kit.Loc`은 `res://chapter1/view/loc.gd`.
> 2. 먼 배경: `Image.load_from_file(ProjectSettings.globalize_path(…png))`를 쓰지 않는다(내보낸 빌드에서는 원본 PNG가 없다). `living_portrait.gd`에 새 정적 공개 함수 `background_image(witch_id: String) -> Image`를 두어, 그 초상의 설정 json이 가리키는 `L0_background` 겹을 `load()`로 읽은 텍스처의 `get_image()`로 돌려준다(경로를 화면에 쓰지 않는다 — "에셋을 바꿔 끼울 때 고칠 곳이 가장 적게"). 화면은 그 Image를 줄이고 채도를 눌러 한 번만 만들어 둔다.
> 3. 초상의 사적 필드 `_veil`을 읽거나 고치지 않는다. `living_portrait.gd`에 공개 `set_veil(on: bool)`(기본 참, 꺼지면 `play_intro`가 막을 그리지 않음)을 둔다. **기본 동작은 바꾸지 않는다** — 스킬 트리 등 다른 곳의 초상과 `living_portrait_demo.tscn`이 지금과 같아야 한다.
> 4. 고정 문구는 `Loc.t` 키로: 새 키(ko·en 둘 다) — `title.logo`("Witch Moira"), `title.start`("시작"), `title.level`("Lv"), `title.tree`("스킬 트리"), `title.stash`("장비 {n}"), `title.save.on`("저장됨"), `title.save.off`("저장 꺼짐"), `title.save.verify`("검증 실행"), `title.keys`("Q/E 소서리스 · Enter 시작 · Esc 메뉴"), `title.menu_button`("메뉴"), `title.witch.<ember|frost|arc>.line`, `title.witch.<ember|frost|arc>.summary`(값은 0판 픽스처의 것), 그리고 Esc 창의 제목·단추 글(`pause_window.gd`가 지금 쓰는 키를 되쓸 수 있으면 되쓴다). 화면 파일에 한글 리터럴을 늘리지 않는다.
> 5. Esc는 `menu()` 신호. 마우스 길로 오른쪽 위에 작은 "메뉴" 단추(44×44, 이름 `TitleMenuButton`)를 둔다 — 같은 `menu()`.
> 6. 처리한 키는 `get_viewport().set_input_as_handled()`로 끝낸다(앱의 Q = 물약, E = 의식 처리로 흘러가지 않게). 패드: InputMap의 `ui_left`·`ui_right`·`ui_accept`·`ui_cancel`도 받는다. Space는 여전히 아무것도 하지 않는다.
> 7. `level == null`이면 레벨 띠·◆·트리 손잡이를 숨기고, `has_tree == false`면 트리 손잡이를 꺼진 꼴로, `stash_count == null`이면 장비 손잡이를 숨긴다. `traits`가 비면 그 줄을 숨기고 위아래를 당긴다. `motion_on == false`면 시안의 움직임 0 경로(BRIEF 3.1 끝).
> 8. 노드 이름을 고정한다(검사 도구가 이름으로 찾는다): 화면 `TitleScreen`, 문 `Door0`~`Door2`, 시작 `TitleStart`, 트리 `TitleTree`, 장비 `TitleStash`, 메뉴 `TitleMenuButton`.
> 9. 화면 파일 규칙(T8 3절, 검사기 6번): 코드 줄에 낱말 `run`·`growth` 0, 다른 객체의 `._필드` 읽기 0, `Color("` 0(색은 `Palette`), `get_child(<숫자>)` 0, `core/`·`app/` preload 0. 부품 파일 둘도 같은 규칙을 지킨다(검사기는 안 읽지만 tech-lead가 읽는다). `_local/` 경로 문자열 0.
> 10. `_process`는 둔다(은총 화면과 같은 시계식. T8 8절의 "화면은 `_process`를 갖지 않는다"는 이 화면과 은총 화면에서 예외로 기록한다). 대신 `set_interactive(false)`이거나 보이지 않으면 `set_process(false)`.
>
> **`pause_window.gd`**: `apply(motion_on: bool, reduce := false, kind := "run")`의 셋째 인수로 `"title"`을 받는다. `"title"`이면 항목은 돌아가기(이름 `TitleResume`, 신호 `resume`) · 화면 흔들림 똑딱이(`MotionToggle`, `motion_changed`) · 게임 종료(`QuitGame`, `quit_game`)뿐이고, 장비·포기 항목과 조작 안내는 그리지 않는다. Esc = 돌아가기. **`"run"`(기본)의 모습·순서·초점은 그대로**(`pause_input_check.gd`의 탭 순서 검사가 돈다).
>
> **`proposal_shot.gd`**: `--screen=<id>` 인수를 더한다 — `res://chapter1/view/hud/screens/<id>.gd`의 `make()`로 짓고, 픽스처는 `chapter1/tests/fixtures/contracts/<id>.<변형>.json`. 나머지(`--strip-kind`, `--reduce-motion`, `--input-test`)는 지금처럼. `proposal_batch.py`에 `title/screen` 한 줄.
>
> **끝 기준**(결과 줄을 보고서에 그대로):
> - `python tools/dev/screen_contract_check.py` → `screens 2`, `failures []`(어댑터가 아직 없으면 note만).
> - `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_screen_contracts.gd -- --out=_local/t10/u1b` → `failures []`, title 픽스처 8개가 화면에 들어간 것이 `checks`에 셈해짐.
> - 정지 캡처 두 해상도: `python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/scene_shot.gd -- --chapter1-profile-off --contract=title --variant=all --shots=_local/shots/t10/fixture-1080`(1280x720도). 이어 `python tools/dev/hud_layout_check.py <그 폴더의 json들>` → 위반 0(허용 목록에 올린 것은 까닭을 적음).
> - 띠: `python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/proposal_shot.gd -- --chapter1-profile-off --screen=title --fixtures=normal,focus_ember,focus_storm --strip-kind=intro --shots=_local/shots/t10/strips`, 같은 것으로 `focus`·`confirm`·`reduced`, 그리고 `--input-test`.
> - `python tools/dev/shot_review.py _local/shots/t10/before-proposal/<…> _local/shots/t10/fixture-1080/<…>`로 시안과 나란히(같은 변형). 보고서에는 "캡처만 있음"으로 쓴다.
> - `rg -n "res://chapter1/tests|_local/" chapter1/view chapter1/app` → 0줄. `rg -n 'Color\("' chapter1/view/hud/screens/title.gd chapter1/view/hud/title_parts.gd chapter1/view/hud/title_block.gd` → 0줄.
> - `python tools/dev/run_all.py --quick` → 통과(`i18n-scan`·`glyphs`·`wording`·`ui-parts`·`screen-contract` 포함).
> - 시안과 바뀐 점(악마 없음, 의상 손잡이 없음, 메뉴 단추, 낱말 셋 빈 줄)을 보고서에 표로.
>
> **건드리지 않음**: `chapter_hud.gd`, `chapter_one.gd`, 코어·데이터, `hud_dump.gd`, `scene_shot.gd`, `test_screen_contracts.gd`, 어댑터.

#### R1 — refactor-architect: 어댑터

> 지시서 `docs/specs/T13-title-select-apply-20261125.ko.md` 2.2~2.3절과 T8 3절(어댑터 규칙)을 따른다. 작업 폴더에서 하고 패치와 보고서를 낸다.
>
> 1. `chapter1/view/contracts/title_contract.gd`: `extends RefCounted`, `class_name` 없음, `const CONTRACT_VERSION := 1`, `static func build(run: RefCounted, app_state: Dictionary = {}) -> Dictionary`. 2.2절 표대로 만든다. `run`은 읽지 않는다(첫 화면에는 판이 없다 — 서명만 다른 어댑터와 맞춘다).
> 2. `app_state`의 꼴을 여기서 고정한다(R2의 호스트가 이 꼴로 넘긴다): `{"focus_index": int, "save": "on"|"off"|"verify", "note": String, "items": int, "motion_on": bool, "character_views": Dictionary}`. 키가 없으면 기본값(초점 0, `save "off"`, `note ""`, `stash_count null`, `motion_on true`, `level null`). `app_state`를 고치지 않는다(필요하면 복사).
> 3. 읽어도 되는 것: `res://chapter1/view/loc.gd`, `res://chapter1/core/chapter_profile.gd`의 정적 `progression_doc()`(캐릭터 id와 시작 기술의 짝), 넘겨받은 `app_state`. 저장 파일·`profile` 객체·HUD를 읽지 않는다.
> 4. `chapter1/tests/test_screen_contracts.gd`의 `"title"` 경우를 셋으로: `no_profile`(`{}`), `saved`(냉기 Lv 8·◆2 꼴의 `character_views`와 `items 12`, `save "on"`), `verify`(`save "verify"`, 뷰 없음). 각 출력이 스키마를 따르는지와 `app_state`가 그대로인지 본다.
>
> **끝 기준**:
> - `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_screen_contracts.gd -- --out=_local/t10/r1` → `failures []`, dumps에 `title.no_profile`·`title.saved`·`title.verify`.
> - `python tools/dev/screen_contract_check.py --dumps=_local/t10/r1` → `failures []`.
> - `python tools/dev/run_all.py --quick` → 통과.
>
> **건드리지 않음**: `chapter_hud.gd`, `chapter_one.gd`, 화면 파일(U1-b), 스키마·픽스처(U1-a), 코어·데이터.

#### R2 — refactor-architect: 호스트·앱·검사 도구 (`chapter_hud.gd`·`chapter_one.gd` 점유)

> 지시서 `docs/specs/T13-title-select-apply-20261125.ko.md` 2.4·2.5절, 4절, 이 단락을 따른다. CLAUDE.md "알아 둘 흔적": `이름__층` 사슬은 고치는 부분부터 정리하고, `chapter1/view/` 바로 아래의 `cloister_*.gd`·`chapter_world_quality*.gd`는 건드리지 않는다. 작업 폴더에서 하고 **한 커밋으로 묶을 수 있는 패치** 하나와 보고서를 낸다.
>
> **호스트(`chapter_hud.gd`)** — 은총 화면의 호스트(1266~1310행)와 같은 꼴:
> 1. `_build_modal(run)`: `run.mode=="menu" and not stash_open`이면 `_build_title_screen()` 하고 끝(옛 메뉴 사슬로 가지 않는다). 메뉴를 떠나면(`run.mode != "menu"`) 화면을 지운다. 메뉴에서 보관함이 열리면 화면을 숨기고 `set_interactive(false)`, 닫히면 다시 보이고 켠다.
> 2. 화면은 메뉴 동안 **하나만 살려 둔다.** 처음 만들 때(게임 시작, 결과 창에서 메뉴로 돌아옴)만 `play_intro()`. 그 밖의 다시 짓기(`invalidate()` 등)는 어댑터를 다시 불러 `apply`만. 계약은 이 순간에만 만든다(프레임마다 아님, T8 8절 — 보고서에 시험 중 어댑터 호출 수를 세어 적는다).
> 3. `app_state`는 R1이 고정한 꼴: `focus_index=_menu_witch`, `save=_save_mode()`, `note=profile_note`, `items=profile_state.items.size()`, `motion_on=motion_enabled`, `character_views`.
> 4. 신호: `start(ref)` → `start.emit(ref)`, 그 뒤 여전히 메뉴면(출발 거절) 화면 `show_settled()`(K1). `witch_focused(i)` → `_menu_witch=i`. `stash()` → `stash_show.emit()`. `skill_tree(ref)` → `_request_tree(ref)`. `menu()` → `PauseWindow`를 `kind "title"`로 열고, `resume` = 닫기, `motion_changed` = 지금 흔들림 똑딱이와 같은 처리(`motion_enabled`, `motion_toggle`), `quit_game` = `quit_request.emit()`(메뉴에서는 지금처럼 확인 없이, K8).
> 5. overlay: 화면이 있는 동안 `overlay.visible=true`, 색 투명, `modal.visible=false`(은총과 같은 `_overlay_base` 규칙). `_sync_flow`의 저장 거부 안내 조건(`overlay.visible`)이 그대로 서야 한다(K10).
> 6. 겹 순서: 알림 띠(`toast`)·큰 띠·흐름 창(`FlowDialog`)·스킬 트리(`z_index 20`)·Esc 창이 **새 화면 위**에 보인다. 흐름 창·스킬 트리·Esc 창이 열려 있으면 화면 `set_interactive(false)`(K10·K13).
> 7. 공개 함수: `menu_character_id() -> String`, `menu_witch_index() -> int`, `menu_select_skill(skill_id)`(남김 — 화면 `set_focus`를 부른다), `title_settle()`(화면이 있으면 `show_settled()`; 캡처·검사용), `title_screen() -> Control`.
> 8. 지운다(다른 모드가 쓰지 않는 것만, 지우기 전에 `chapter1/`·`tools/` 전체를 Grep): `__cloister`의 `"menu"` 갈래, `_motion_control`(다른 곳에서 안 쓰면), `__chapter`의 메뉴 몫(보관함 단추·`profile_note` 줄 — **결과 창 몫은 남긴다**), `_build_modal__q41`의 메뉴 몫과 `_build_menu41`·`_two_line_choice`, `__q45`의 메뉴 갈래, `_add_flow_buttons`의 메뉴 갈래, `_focus_modal38`의 메뉴 전용 줄(821~823, 829~832행), `_sync_portrait`·`_fit_menu_portrait`·`_portrait_motion_scale`과 `LivingPortrait`·`WITCH_IDS` 상수(안 쓰이면), `_build_witch_summary`·`_refresh_witch_summary`, 메뉴 변수(`_menu_starts`, `_menu_portrait`, `_living_portrait`, `_portrait_witch`, `_menu_tree_button`, `_menu_badge`, `_menu_name`, `_menu_xp`, `_menu_class`, `_menu_bar`, `_menu_points`), `menu_title`·`menu_description`·`menu_scope`와 `_init`의 그 대입. 남긴다: `START_SKILLS`, `WITCH_KEYS`, `PORTRAIT_KEYS`, `_witch_name`/`_witch_class`(다른 곳에서 쓰면), `_character_for_skill`, 보관함 창(A10 W8은 따로), 스킬 트리 호스트, 흐름 창, 결과 창. 지운 것과 남긴 것의 목록을 보고서에.
>
> **앱(`chapter_one.gd`)**:
> 9. `menu_character_id()`는 `hud.menu_character_id()`만 부른다. `hud.get("_menu_witch")` 갈래를 지운다(T8 S2). HUD에 그 함수가 없으면 `""`.
> 10. `_unhandled_key_input__chapterx`의 Q(물약)·E(의식)는 `run.mode=="menu"`이면 아무것도 하지 않고 넘긴다(화면이 먼저 받지만 막아 둔다).
> 11. `--chapter1-start`가 없고 `--chapter1-primary=`가 있으면, 첫 `hud.sync` 전에 `hud.menu_select_skill(primary)`로 처음 초점을 그 마녀로. `--chapter1-start`가 있으면 지금과 똑같이 첫 sync 전에 `start_run(primary)` — **이 순서를 바꾸지 않는다.**
> 12. 그 밖의 앱 흐름(출발 검사, 저장, 돌아오기, 종료)은 바꾸지 않는다.
>
> **검사 도구** — 옛 화면의 사적 값·노드 대신 7번의 공개 함수와 3.2 U1-b 8번의 노드 이름을 쓴다. **`equiv.py`는 이 폴더의 `hud_dump.gd`를 기준 커밋 쪽에도 복사해 돌리므로, 새 함수는 `has_method`로 확인하고 없으면 옛 길로 가게 쓴다.**
> 13. `hud_dump.gd`: 기본 순간 — 5프레임에 `title_settle()`(있으면)을 부르고 8프레임에 `menu`, 그다음 `stash`, 그다음 `start_run`(프레임 수를 늘려도 코어는 시작 뒤 틱으로만 움직이므로 판은 같다). `--menu-tour`·`--tree-shots`: `hud._menu_tree_button` 대신 `TitleTree` 누름, `hud._menu_starts[2]`에 올림 대신 `Door2` 자리로 마우스를 옮겨 머묾 확인(`menu_witch_index()==2`). 저장 거부 흐름(875행 근처)·돌아온 뒤 다른 마녀(997행 근처): `hud._menu_starts[i]` 누름 대신 `menu_select_skill` + `TitleStart` 누름, 그 뒤 **확정 박자(1.2초)를 기다려** `flow_dialog_open()` 또는 `run.mode=="playing"`이 될 때까지(상한 120프레임). `--flow-shots=quit`: 화면이 다 열린 뒤 Esc → `title-menu` 덤프 → `QuitGame` 누름.
> 14. `portrait_select_shots.gd`: `_menu_starts[index].grab_focus()` 대신 실제 입력(Q/E 키 이벤트)으로 초점을 옮기고, `hud_ref`는 `title_screen()`. 초상 노드 수는 셋이 정상.
> 15. `scene_shot.gd`: 코어 씨앗 `title` 장면과 `SCENES`의 `"title"`을 지우고 `fixtures/ui/title.normal.json`·`title.long.json`을 지운다(새 화면은 `--contract=title`이 찍는다). `skill_tree` 장면은 그대로 돈다.
> 16. `test_profile_app_loadout.gd` 80~89행: `menu.hud._menu_witch = 2` 대신 `menu.hud.menu_select_skill("chapter1.skill.arc")`(화면이 없어도 번호가 바뀌게 호스트가 받는다), "카드 번호가 없는 화면" 검사는 "공개 함수가 없는 화면이면 빈 값"으로 문장만 고친다.
>
> **끝 기준**(본 저장소가 아니라 작업 폴더에서, 결과 줄을 보고서에 그대로):
> - `python tools/dev/run_all.py --quick` → 통과. `python tools/dev/run_all.py --only golden,golden-textless` → 불일치 0(코어 무수정).
> - `python tools/dev/equiv.py --base <R2 직전 커밋> --primary frost,ember,arc --until 2400` → 결과가 DIFFERENT여도 된다. **다른 줄이 모두 `menu`·`stash` 순간 안에 있고**, 판이 시작된 뒤의 순간(`playing-120`, `choice-*`, `inventory`, `end-*`)은 다른 줄 0. 다른 줄의 순간별 수를 보고서에.
> - `hud_dump.gd`를 아래 4절 표의 경우마다 두 해상도로 돌려 모두 `HUD_DUMP_RESULT`까지 끝남(시간 초과 0). 저장 거부 흐름의 `HUD_DUMP_FILES`에서 `originals_unchanged: true`.
> - `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_screen_contracts.gd -- --out=_local/t10/r2` → `failures []`. `python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --profile-fixture=l8 --tree-shots --dump-contracts=_local/t10/r2-live --dump=_local/t10/r2-live.json` 뒤 `python tools/dev/screen_contract_check.py --dumps=_local/t10/r2-live` → `failures []`.
> - `pause_input_check.gd`(정지 창 탭 순서) 통과.
> - 바로 시작 길: `python tools/dev/godot.py --headless --fixed-fps 60 --path . -- --chapter1-start --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --chapter1-primary=chapter1.skill.frost --chapter1-quit-after=20` → `CHAPTER1_READY`의 뒤로 오류 없이 끝남, 첫 로그에 메뉴 화면을 지은 흔적 없음(보고서에 근거 줄).
> - 내보낸 빌드: `python tools/dev/build.py --preset qa`(이 작업 폴더에서만) → 실행 파일을 **`--chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-quit-after=12`와 APPDATA를 `_local/appdata/t10-build/`로 바꾼 환경에서만** 띄워 메뉴에 12초 → 표준 오류에 `SCRIPT ERROR`·`L0_background`·`res://chapter1/tests` 0. 사용자 저장 폴더를 열지 않는다.
> - 성능: `perf_probe.gd`의 `--x-delay-start`(메뉴 120프레임을 잰다, 머리 주석의 실행 줄)로 R2 전후의 `menu_dts` 평균·최대를 1920x1080에서 적는다. 기준(가설): 평균 16.7ms 이하, 첫 1초 뒤 33ms 넘는 프레임 0. 넘으면 멈추고 원인(초상 셋, 뒤의 3D 세계)을 보고한다.
> - `git log -- chapter1/view/hud/chapter_hud.gd chapter1/app/chapter_one.gd`에 작업 중 다른 커밋이 없음.
>
> **건드리지 않음**: 코어·데이터·저장 형식, 화면 파일 셋(U1-b — 필요한 것은 보고서에), `pause_window.gd`(U1-b), 결과·보관함·장비·정지 창의 모습.

#### U2 — ui-hud: 실판 캡처 뒤 다듬기

> R2가 합쳐진 뒤, 5절의 실판 캡처(두 해상도, 네 계정 상태)를 직접 보고 어긋난 것(글 넘침, 겹침, 초점 괄호의 자리, 저장 꺼진 판의 빈 자리, 1280×720의 좁은 문)을 `screens/title.gd`·`title_parts.gd`·`title_block.gd` 안에서만 고친다. R2 보고서의 "화면에 필요한 것"도 여기서. 디자인 값을 바꾸면 무엇을 왜 바꿨는지 표로. 끝 기준은 U1-b와 같고, 5절의 캡처를 다시 찍어 전후를 나란히 둔다.

---

## 4. 지킬 것과 검사

### 4.1 지킬 것

| 규칙 | 이 일에서 |
|---|---|
| 코어·저장 형식 무수정 | `chapter1/core/`·`chapter1/data/` 변경 0. "마지막 마녀" 저장 필드는 넣지 않는다(결정 3). 골든 `golden`·`golden-textless` 불일치 0 |
| 표현은 읽기만 | 화면은 계약만, 어댑터는 `app_state`와 정적 데이터만 읽는다. 화면·어댑터가 저장·코어를 부르지 않는다 |
| 사용자 저장 | 모든 검사는 `--chapter1-profile-off`나 `--profile-fixture=`(격리 경로 `res://_local/…`)로. 실행 파일 확인은 APPDATA를 `_local/appdata/…`로 바꾼 환경에서만. `%APPDATA%\WitchMoira`를 읽거나 쓰는 실행 0 |
| 검증용 실행 인수 | `--chapter1-start`(첫 sync 전에 출발 — 메뉴를 짓지 않음), `--chapter1-primary=`(바로 시작이면 그 기술, 아니면 처음 초점), `--chapter1-pilot`, `--chapter1-seed=`, `--chapter1-profile-off`, `--chapter1-qa-ignore-focus`, `--chapter1-quit-after=`, `--chapter1-capture-dir=`가 지금처럼 돈다. `measure_combat.gd`·`sim_loot.gd`·골든은 앱을 거치지 않으므로 영향 없음 [봄: 코어만 읽음] |
| 해상도 | 1920×1080과 1280×720 둘 다(프로젝트는 1600×900 `canvas_items` 늘이기 [봄: `project.godot`]) |
| 조작 | 키보드만, 마우스만, 패드(`ui_*` 액션)로 각각 시작·트리·장비·Esc 창·종료까지 |
| 내보낸 빌드 | 화면·부품이 `res://chapter1/tests/`·`_local/`·원본 PNG 경로를 읽지 않는다 |
| 옛 층 | `cloister_*.gd`·`chapter_world_quality*.gd`를 건드리지 않는다. 새 기능은 `hud/`의 새 파일에 |
| 커밋 | 담당은 커밋하지 않는다. 디렉터가 R2를 한 커밋으로 |

### 4.2 검사가 옛 화면에 묶인 곳과 고칠 방법 [봄]

| 검사 | 묶인 곳 | 고침(담당) |
|---|---|---|
| `hud_dump.gd` | `hud._menu_starts`(744·747·750·875·997행 근처), `hud._menu_tree_button`(713·753·789행), `hud._menu_witch`(747행), `_find_button("QuitGame")`(922행, 메뉴의 종료 단추), 5프레임의 `menu` 덤프(등장 중이라 검게 찍힘 — A10 W-C) | R2 13번 |
| `portrait_select_shots.gd` | `_menu_starts[index].grab_focus()`(30행), `_living_portrait`(43행) | R2 14번 |
| `scene_shot.gd` | 코어 씨앗 `title` 장면(262~274행), `fixtures/ui/title.*.json` | R2 15번 |
| `test_profile_app_loadout.gd` | `hud._menu_witch = 2`(80행), 사적 값 갈래 검사(85~89행) | R2 16번 |
| `test_screen_contracts.gd` | `title` 경우가 빈 `app_state` 하나 | R1 4번 |
| `screen-contract`(검사기) | 0판 픽스처 9개가 1판 스키마와 판이 달라 실패하게 됨 | U1-a 4번 |
| `proposal_smoke.gd`·`proposal_batch.py` | 시안 title 파일을 preload·목록에 둠 | U1-a 4번 |
| `pause_input_check.gd` | 정지 창의 `QuitGame` 탭 순서 | 영향 없게 U1-b가 `"run"` 종류를 그대로 둠 |
| `equiv.py` | 메뉴 순간의 노드가 통째로 바뀜 | 5.1절의 판정 방식 |

### 4.3 돌릴 검사 목록(검수 때 tech-lead가 본 저장소에서 다시 돌린다)

1. `python tools/dev/run_all.py --quick`
2. `python tools/dev/run_all.py --only golden,golden-textless`
3. `python tools/dev/screen_contract_check.py` + `test_screen_contracts.gd --out=…` + 실판 `--dump-contracts`
4. `python tools/dev/equiv.py --base <R2 직전> --primary frost,ember,arc --until 2400`
5. `hud_dump.gd` 네 계정 상태 × 두 해상도(5절 표)
6. `scene_shot.gd --contract=title --variant=all` 두 해상도 + `hud_layout_check.py`
7. `proposal_shot.gd --screen=title` 띠 넷 + `--input-test`
8. `pause_input_check.gd`, `portrait_select_shots.gd`
9. `perf_probe.gd --x-delay-start` 전후
10. 마지막에 디렉터가 `python tools/dev/run_all.py`(전체, 약 11분)

---

## 5. 검수 방법

### 5.1 판정의 꼴

- **동작 불변 쪽**: 판이 시작된 뒤의 모든 덤프 순간이 R2 전후로 같다(`equiv.py`의 다른 줄이 `menu`·`stash` 순간에만). 골든 불변.
- **새 화면 쪽**: 아래 장면을 art-lead와 디렉터가 **직접 본다.** 보고서의 "통과"는 실제로 돌린 것에만, 화면은 "직접 봄 / 캡처만 있음 / 보지 않음" 가운데 하나로 적는다. 미감·움직임의 맛은 사용자 플레이로만.

### 5.2 볼 장면과 캡처 명령

| 장면 | 명령(모두 `python tools/dev/godot.py --fixed-fps 60 --resolution <1920x1080 \| 1280x720> --path . --script res://chapter1/tests/<도구> -- …`) | 볼 것 |
|---|---|---|
| 첫 진입 | `proposal_shot.gd --chapter1-profile-off --screen=title --fixtures=normal --strip-kind=intro --shots=_local/shots/t10/review/strip` | 0.4초까지 검정, 로고, 문이 왼쪽부터, 초점 문이 열리고 초상의 어둠이 걷힘, 글이 2.2~2.5초에. 건너뛰기(아무 키) 뒤 0.15초에 다 열림 |
| 세 문의 초점 이동 | 같은 도구 `--fixtures=normal,focus_ember --strip-kind=focus` | 0.30초에 폭 960↔480, 새 마녀가 커지고 밝아짐(발끝 고정), 글 묶음이 0.20~0.40초에. 이 안이 "포스터 석 장"으로 읽히지 않는가(BRIEF 3.2.9) |
| 확정의 한 박자 | `--strip-kind=confirm`, 움직임 0은 `--strip-kind=reduced` | 0.15초에 글이 사라짐, 두 문 검정, 문이 화면 전체로, 1.08배 다가감(얼굴·가슴 중심, 골반 쪽 아님), 섬광이 흰색에 가깝게 덮는 장 2장 이하, 1.2초에 닫힘. 움직임 0: 섬광·다가감 없이 0.4초 어둡게 |
| 저장이 있는 계정 | `hud_dump.gd --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.frost --profile-fixture=l8 --tree-shots --dump-extra --shots=_local/shots/t10/review/l8-<해상도> --dump=_local/shots/t10/review/l8-<해상도>.json` | `menu`(다 열린 상태), 냉기 Lv 8 ◆2, 다른 문의 "Lv N ◆N", `menu-frost`, `tree-open`(트리가 화면 위에, 뒤 화면이 키를 먹지 않음), `menu-after`(초점 그대로) |
| 새 계정 | 같은 명령에 `--profile-fixture=empty` | 세 마녀 Lv 1, ◆ 없음, 장비 0 |
| 저장이 꺼진 판 | `hud_dump.gd --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --dump-extra --shots=_local/shots/t10/review/off-<해상도> --dump=…`(기본 순간) | 레벨 띠·◆·트리·장비 손잡이 숨김, "검증 실행" 낱말, 빈 자리가 어색하지 않음 |
| 저장 거부 | `hud_dump.gd … --profile-fixture=rejected --shots=…` | 안내 창이 새 화면 **위**에, 탭이 창 안에서만 돎, 닫은 뒤 시작 → 안내 창 다시(확정 박자 뒤), "저장 없이 하기" 뒤 출발. 원본 파일 불변 |
| 보관함·트리·Esc 창으로 가는 길 | 기본 순간의 `stash`, `--tree-shots`의 `tree-open`, `--flow-shots=quit --profile-fixture=empty`의 `title-menu` | 보관함이 열리면 새 화면이 숨고 닫으면 같은 초점으로 돌아옴(등장 다시 없음). Esc 창은 돌아가기·흔들림·종료 셋 |
| 돌아오기 | `hud_dump.gd … --flow-shots=abandon --profile-fixture=empty --shots=…` | `flow-menu-returned`: 등장이 다시, 초점은 방금 한 마녀, 다른 마녀로 출발까지 |
| 알림 띠 | 메뉴에서 M(사람이 직접 또는 `--input-test`) | "소리 꺼짐" 띠가 새 화면 위에 보임 |
| 시안과 나란히 | `python tools/dev/shot_review.py _local/shots/t10/before-proposal/<…> _local/shots/t10/review/<…>` | 시안 대비 달라진 것이 U1-b 보고서의 표와 같은가 |

### 5.3 통과 기준

1. 4.3절 1~9가 모두 기준대로(결과 줄이 보고서와 검수 기록에 있음).
2. 정지 캡처(두 해상도, 모든 변형): 초점 마녀의 얼굴이 다 보이고 y 324(720p 216) 위, 골반이 x 840~1080(720p 560~720) 밖(BRIEF 1.8 선 ③④ — 화면의 `layout_report()`가 숫자로도 낸다), 판의 월드·HUD가 비치지 않음, `hud_layout_check.py` 위반 0, 본문 대비 4.5:1.
3. 화염·번개가 새 자세(p2·p3)다(BRIEF 4.4-4).
4. 좁은 문이 1280×720에서 "검은 기둥"이 아니라 그림으로 보인다(BRIEF 3.2.8-4) — art-lead 직접 봄.
5. 키보드만·마우스만·패드로 시작·트리·장비·Esc 창·종료가 된다(`--input-test` 결과 + R2의 `hud_dump` 흐름).
6. 메뉴에서의 성능이 R2 전보다 크게 나빠지지 않음(4.3-9의 수, 기준은 가설값이라 디렉터가 본다).
7. 사람: art-lead와 디렉터가 대표 캡처를 직접 봄. 사용자가 실행 파일로 켜서 본다(결정 2).

---

## 6. 위험과 되돌리는 길

### 6.1 가장 큰 위험 셋

1. **입력과 창의 겹침이 실판에서만 드러난다.** 새 화면은 불투명하고 메뉴 동안 계속 살아 있다. (가) Q/E가 앱의 물약·의식 키와 같다 — 화면이 키를 "처리함"으로 끝내지 않으면 앱으로 흐른다(지금 `_unhandled_key_input__chapterx`는 메뉴에서도 Q를 처리함으로 막는다). (나) 스킬 트리·보관함·흐름 창·Esc 창이 위에 있을 때 뒤 화면이 Q/E·마우스 머묾으로 초점을 바꾸면 보관함 장착 대상(`menu_character_id`)이 몰래 바뀐다. (다) 알림 띠가 `overlay` 앞 형제라 불투명 화면 뒤로 숨는다. (라) `_sync_flow`가 `overlay.visible`에 기대 저장 거부 안내를 연다 — overlay를 숨기면 안내가 안 뜬다. (마) 출발이 거절되면 화면이 확정 박자 뒤 `done`에서 멈춘다. → 2.4절 K1·K7·K10·K13·K15, R2 4~6·10번, U1-b 6번, 5.2절의 저장 거부·알림 띠 장면.
2. **편집기에서는 되고 내보낸 빌드에서만 깨진다.** 시안은 `res://chapter1/tests/`의 `kit.gd`를 preload하고(내보내기 제외 폴더), 원본 PNG를 `Image.load_from_file`로 읽고(PCK에는 가져온 텍스처만 있다 [가설: Godot 4의 내보내기 규칙, 이 저장소에서 확인하지 않음]), 악마 그림을 `_local/`에서 읽는다. `run_all.py`는 편집기 실행이라 이것을 못 잡는다. → U1-b 1·2번, 결정 1(악마 뺌), R2의 qa 빌드 확인, 4.1 "내보낸 빌드" 줄.
3. **검사·측정 도구가 옛 화면 내부와 "누르면 바로 출발"에 묶여 있다.** `hud_dump.gd` 다섯 곳 이상, `portrait_select_shots.gd`, `scene_shot.gd`, `test_profile_app_loadout.gd`가 사적 값·옛 노드를 쓰고, 흐름 검사는 시작을 누른 뒤 4프레임 안에 판이 시작된다고 가정한다(확정 박자 1.2초 = 72프레임). 고치지 않으면 회귀가 실패가 아니라 **시간 초과**로 멈춘다. 또 `equiv.py`는 이 폴더의 덤프 스크립트를 기준 쪽에 복사하므로 새 함수를 무조건 부르면 기준 쪽이 깨진다. → 4.2절 표, R2 13~16번(`has_method` 갈래).

그 밖: 움직이는 초상 셋 + 뒤에서 계속 그려지는 3D 세계의 그리기 부담은 잰 적이 없다(BRIEF 6절) — R2의 `perf_probe`. 결과가 나쁘면 메뉴 동안 3D 세계를 그리지 않는 일을 따로 뗀다(이번 범위 밖).

### 6.2 한 번에 갈아 끼울지, 인수로 먼저 켜 볼지 — 권고

**권고: 실행 인수로 옛 화면과 새 화면을 함께 두지 않는다. 한 번에 갈아 끼우되, 본 저장소에 합치는 것을 사용자 확인 뒤로 미룬다.**

까닭:
- 옛 메뉴는 `__q41`이 자식 번호로 옛 상자를 뜯어 붙이는 층이라, 두 길을 함께 두면 `_build_modal` 사슬·`_focus_modal38`·`_add_flow_buttons`·검사 도구가 모두 두 갈래가 된다. 쓰지 않는 갈래는 아무도 검사하지 않아 곧 깨진다.
- 되돌리기는 R2 한 커밋의 revert로 충분하다(새 파일은 쓰이지 않은 채 남아도 검사가 통과).
- 사용자가 "적용했나"를 물었다(U-128). 기억 메모 "기준에 못 미치면 먼저 확인"은 합치기 전 확인으로 지킨다: R2 작업 폴더의 qa 실행 파일과 5.2절 캡처를 사용자에게 보이고, 사용자가 본 뒤 합친다(결정 2).
- 사용자가 고른 것은 시안의 정지·띠 캡처다. 실제 데이터(레벨·◆·저장 꺼짐)와 실제 움직임은 이번이 처음이라, 사용자 확인을 건너뛰면 "고른 것과 다르다"가 합친 뒤에 나온다.

---

## 7. 디렉터가 정할 것

| # | 정할 것 | 권고와 까닭 |
|---|---|---|
| 1 | **확정 박자의 계약 악마**(시안 BRIEF 3.5.3: 0.5초, 눈·손끝만 계열색) | **이번에는 뺀다.** narrative-lead 판정(`docs/story/GRACE-GRADES-AND-TITLE-VOICES-20261120.ko.md` 7.6, 잠정)이 "선택 화면에 서약 악마를 그림·윤곽·존재 신호 모두 보이지 않는다"이고, 시안이 쓰는 그림은 `_local/art/drafts/`의 옛 시안(`ember-demon-v02.png`, `storm-demon-v02.png`, 냉기는 코드로 그린 손)이다. 확정 시트(`_local/art/intro/v3/refs/`의 feronia·marzanna·tacita) 가운데 **페로니아는 11-25에 새 얼굴로 바뀌었고**, 게임 안의 강림 그림(`illustration.cutin.descent.ember` = `feronia_main_a.png`, 11-23)도 옛 얼굴이다. 넣기로 하면 그림은 자리표 `illustration.cutin.descent.<원소>`로만 읽고(경로 직접 읽기 금지), 페로니아 그림 교체는 따로 떼어 character-artist 줄로 |
| 2 | **본 저장소에 합치는 때** | **사용자가 R2 작업 폴더의 qa 실행 파일(또는 5.2절 캡처)을 본 뒤 합친다.** 다른 길: tech-lead·art-lead 검수 통과 즉시 합치고, 마음에 안 들면 R2 커밋을 되돌림 |
| 3 | **처음 켤 때의 초점과 "마지막 마녀" 저장** | 처음 초점 = **화염**(BRIEF 5.2-1, 왼쪽 첫 자리, 내딛는 자세). 한 실행 안에서는 마지막 마녀를 기억(지금과 같음). 실행을 넘는 기억은 저장 필드가 필요하므로 **이번에 넣지 않고** 시스템 줄(gameplay-systems, 저장 형식 판 올림과 골든·프로필 검사)로 장부에 올린다 |

## 8. 필요한 그림

**없음.** 겹(`chapter1/art/portraits/<마녀>/layers/`)과 움직이는 초상, 공용 겉 그림(`ui.kit.*`: 단추·판·촛대·손잡이)이 이미 있다 [봄: `chapter1/art/asset_slots.json`]. 로고는 시안처럼 제목 글꼴 글자(워드마크 그림 U-A5 없음). 나중에 더할 수 있는 것(이번 범위 밖): 문 사이 앞 겹(기둥 윤곽, BRIEF 3.4-5), 결정 1을 "넣는다"로 하면 악마 상반신 오려낸 그림 셋(BRIEF 3.5.6), 계열별 진짜 터짐(vfx-feel).

## 9. 만드는 양의 어림

| 묶음 | 양(어림) |
|---|---|
| U1-a | 스키마 1개, 픽스처 8개, 파일 지움 14개, 도구 두 곳 줄 삭제 — 작음 |
| U1-b | 화면 약 750줄(시안 base 377 + a 486에서 악마·안 나 몫을 뺌), 부품 둘 약 650줄(parts 490 + dress 314에서 `Devil`·의상 뺌), `living_portrait.gd` +30줄, `pause_window.gd` +40줄, po 키 약 20개 × 2언어, `proposal_shot.gd` +40줄. 대부분 옮기기 |
| R1 | 어댑터 약 120줄, 검사 +40줄 |
| R2 | `chapter_hud.gd` 약 +150 / −350줄, `chapter_one.gd` 약 ±20줄, 검사 도구 넷 약 +120 / −60줄 |
| U2 | 캡처 결과에 따라 작음 |

순서: U1-a(반나절 안) → U1-b ∥ R1 → R2(점유) → 사용자 확인(결정 2) → 합침 → U2 → 디렉터 전체 회귀·커밋. 그 뒤 하네스 ⑧: 장부 U-30·U-69·U-128 상태, 하네스 4절 표의 단계 "적용", 남은 일(소리 고리 셋 → audio-lead, 계열별 터짐 → vfx-feel, 낱말 셋 → design-lead, 마지막 마녀 저장 → 시스템 줄, 악마 → 결정 1).

## 10. 확인하지 못한 것

- Godot를 돌리지 않았다. 시안이 지금 저장소에서 그대로 도는지(`proposal_smoke.gd`), 시안 캡처(`_local/shots/title-proposals/`)는 지워져 있어 보지 못했다 — U1-a 1번이 다시 찍는다.
- `Image.load_from_file`로 읽는 원본 PNG가 내보낸 PCK에 없다는 것은 Godot 4의 일반 규칙에 기댄 판단이다 [가설]. R2의 qa 빌드 확인이 답한다.
- Godot 4.5에서 `_unhandled_key_input`이 HUD의 화면과 앱 노드 가운데 어느 쪽에 먼저 오는지 이 저장소에서 확인하지 않았다 [가설: 자식이 먼저]. 그래서 화면의 "처리함"과 앱의 메뉴 갈래 막기를 둘 다 지시했다.
- `pause_window.gd`의 지금 항목 구성은 머리 주석과 신호만 읽었다(본문 미독).
- `docs/reviews/BENCHMARK-CHARACTER-SELECT-20261119.ko.md`는 절 제목과 BRIEF 2절의 대조만 읽었다. A10·T8·BRIEF·하네스 3.6~3.9는 해당 절을 읽었다.
- `docs/reviews/AUDIT-screen-unification-20261125.ko.md`(U-128의 감사)는 아직 없다. 감사가 이 화면에 다른 지적을 내면 U2에 더한다.
- `equiv.py`가 순간별 다른 줄 수를 결과에 나눠 적는지 확인하지 않았다. 안 나뉘면 R2가 `result.json`에서 세어 적는다.
- 페로니아의 새 얼굴 그림이 원장·자리표에 올라갔는지는 보지 않았다(결정 1을 "뺀다"로 하면 이 일에 걸리지 않는다).

---

## 디렉터 판정 (2026-11-25, 총괄 디렉터. 담당의 보고로 읽음 — 구현을 배정하기 전에 묶음별 절을 직접 읽는다)

지시서를 받는다. 문서 이름은 T13으로 바꿨다(T10은 `T10-pity-save-key-and-tech-decisions-20261123`이 이미 쓴다. 본문에 "T10"이라고 적힌 곳은 이 문서를 가리킨다).

1. 확정 박자에 계약 악마를 넣지 않는다(이번에는). 시안이 쓰는 악마 그림은 옛 얼굴이고, 게임 안 강림 그림의 페로니아도 옛 얼굴이다 — 그림 교체는 따로 연다(U-125의 남은 일).
2. 본 저장소에 합치는 때: R2는 사용자가 캡처(또는 qa 실행 파일)를 본 뒤에 합친다. 옛 화면과 새 화면을 실행 인수로 함께 두지 않는다. 되돌리는 길은 R2 한 커밋의 되돌림이다.
3. 처음 켤 때의 초점은 화염. "마지막에 고른 마녀"를 기억하는 저장 필드는 이번에 넣지 않는다.

순서: U1-a(ui-hud) → U1-b(ui-hud)와 R1(refactor-architect) 나란히 → R2(refactor-architect, 단독) → U2(ui-hud).
