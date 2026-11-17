# 기술 검수 — D4-U(판 흐름 화면)·D5-U(저장 거부 안내)

2026-11-17 · 검수: 기술 책임자(tech-lead) · 대상: ui-hud 결과(커밋 전 작업 트리) · 판정 요청: 총괄 디렉터

기준: `docs/specs/D4-run-flow-spec.ko.md`(2.1 F1~F11, 3.1~3.3, 4절 D4-A·D4-U, 5.2 H1~H9), `docs/specs/D5-save-safety-spec.ko.md`(3.1, 3.3, 3.4, 4절 D5-U, 5.4 H-1~H-6, 6절 U-1~U-4 — 사용자 결정: 네 길 모두 허락, 원본은 어떤 경우에도 지우거나 고치지 않음), `docs/specs/A4-ui-redesign-direction.ko.md` 8.2절 규칙 다섯.

본 파일: `chapter1/view/hud/chapter_hud.gd`(diff), 새 `chapter1/view/hud/flow_dialog.gd`, `chapter1/app/chapter_one.gd`(diff 가운데 D4·D5 부분만. T4-B의 `qa_allowed`·`_user_args`·F1 가드는 앞선 검수에서 끝나 다시 보지 않음), `chapter1/tests/hud_dump.gd`(diff), `chapter1/i18n/ko.po`·`en.po`, 참고로 `chapter1/core/chapter_profile.gd`(읽기만), `chapter1/view/actors/chapter_actors.gd`(읽기만).

---

## 판정: 조건부 통과

판 흐름(정지 → 포기 → 결과 → 메뉴 → 다른 마녀)과 거부 안내의 네 길은 헤드리스로 끝까지 돌았고, 거부된 원본과 기록본은 모든 실행에서 바이트가 그대로였다. 전체 회귀 13종 통과, 골든 4건 일치.

다만 아래 "반드시 고칠 것" 네 가지가 남는다. 1번은 명세 F6을 어기고, 2번은 사용자에게 틀린 파일 위치를 보여 주며, 3번은 H3(메뉴 복귀 뒤 3D 장면이 처음 메뉴와 같음)을 어기고, 4번은 A4 8.2 규칙 1·2를 어긴다. 넷 다 작고 서로 다른 파일로 나눌 수 있다. 고친 뒤 7절의 재확인을 통과하면 커밋해도 된다.

---

## 1. 반드시 고칠 것

### M1. 판 중 [게임 종료]에서 저장이 실패하면 "저장되지 않은 보상" 물음이 다음 프레임에 사라진다(F6 위반)

- 직접 재현했다(4절 `case-quitfail`). 저장이 늘 실패하는 격리 프로필로 Esc → Tab으로 [게임 종료] → 확인 창 ← → Enter. 결과: 게임은 꺼지지 않고(맞음) 결과 창이 뜨지만, `ask_unsaved("quit")`가 연 물음 창이 **+1프레임에 이미 닫혀 있다**(`dialog_open:false`, +3·+33·+153프레임도 같음). 플레이어가 고른 "종료"는 아무 말 없이 버려진다. 보상은 결과 창에 남아 있어 잃지는 않는다.
- 원인: `chapter1/view/hud/chapter_hud.gd:1819` `_open_dialog`가 창의 유효 모드를 `_flow_mode=_flow_prev_mode`로 잡는다. `_flow_prev_mode`는 `_sync_flow`가 프레임마다 갱신하는 값이라, 같은 입력 처리 안에서 `quit_game → abandon_run`이 코어를 "defeat"로 바꾼 뒤 열린 창은 "paused"로 기록된다. 다음 `_sync_flow`에서 `chapter_hud.gd:1801` `elif run.mode!=_flow_mode:_close_dialog(true)`가 창을 닫는다.
- 고칠 것(ui-hud, `chapter_hud.gd`만): 창 종류마다 살아 있을 모드를 규칙으로 정한다. `abandon`·`quit`은 `paused`일 때만, `unsaved:*`는 `victory`·`defeat`일 때만, `notice`·`fresh`는 지금처럼 `menu`이고 거부 상태일 때만. `_flow_mode` 비교를 이 규칙으로 바꾼다(또는 `_open_dialog`가 앱의 현재 `run.mode`를 읽어 기록한다. 규칙 쪽을 권한다. 의도가 코드에 남는다).

### M2. 옛 형식만 거부된 경우 위치 줄이 실제 거부된 파일이 아니라 없는 v3 경로를 보여 준다(구현자 보고는 사실)

- 직접 확인했다(4절 `case-legacy`). v3 없음 + 깨진 v2 → `CHAPTER1_PROFILE_REJECTED {"file":"legacy-v2.json","kind":"legacy",...}`인데 `profile_reject_info()`는 `"file":"legacy-v3.json"`, `"path":".../legacy-v3.json"`, 그 파일은 `v3_exists:false`.
- 원인: `chapter1/core/chapter_profile.gd:93` `path=_pointed(destination)`로 v3 경로가 정해진 뒤, v2·v1 거부는 `_reject("legacy",…,legacy_v2)`(105·107행)로 가는데 `_reject`(212행)는 `source`를 로그에만 쓰고 저장하지 않는다. 앱 `chapter1/app/chapter_one.gd:436-437`은 `profile.path`를 그대로 보여 준다.
- 고칠 것(gameplay-systems, 두 파일): `chapter_profile.gd`에 `var reject_source := ""`를 두고 `configure` 첫 줄에서 비우며 `_reject`에서 `reject_source=source`. `start_fresh_after_reject`는 바꾸지 않는다(legacy의 새 파일은 여전히 `path`=본래 v3 경로에 만든다). `chapter_one.gd:433-437` `profile_reject_info()`의 `file`·`path`·`folder`를 `reject_source`(비었으면 `profile.path`)에서 만든다. `test_chapter_profile.gd` P-4의 legacy 경우에 `reject_source`가 v2 경로인지 한 줄 더한다. 화면 쪽(`_open_notice`)은 고칠 것이 없다.

### M3. 메뉴로 돌아온 뒤 주인공 모델이 마지막 자리·방향·자세로 남는다(H3 위반, 구현자가 찾은 결함 4)

- 직접 확인했다(4절 `abandon` 3D 덤프 비교). 카메라 변환은 처음 메뉴와 **완전히 같다**(`world.update_camera(Vector2.ZERO,10.0)`로 충분). 그러나 주인공 묶음(노드 `@Node3D@86`과 자식: 모델, 발밑 표시, 소유 표시 `◇`, 원소 원판·고리)이 처음 메뉴의 원점·단위 회전 대신 `(-5.649, 0, 5.876)`, 약 23도 돌아간 채로 남고, 지팡이(`@Node3D@92`)는 `(-6.3, 1.78, 6.12)`에 기울어진 채 남는다. 모두 보이는 상태다. 뼈 자세와 원소 색은 덤프에 없어 숫자로는 못 봤지만 같은 이유로 남는다(아래).
- 원인: 새 코어의 `hero`는 `{}`이고, `chapter_one.gd:287-291`은 `run.hero`가 비면 `actors.sync`를 부르지 않는다. 그런데 `actors.reset()`(`chapter_actors.gd:1759` → `reset__q25b` → … → `reset__rigged` 608행 → `reset__cloister` 387행)은 적 풀·타이머·`motion_sample` 메타만 비우고 `hero.transform`, `rig_skeleton`의 뼈 자세, `_staff`의 변환, `_apply_hero_element`가 바꾼 재질 색(`_hero_materials`, `_hero_disc_material`, `_hero_ring_material`, `_hero_element_key`)은 건드리지 않는다. 판 시작·다시 도전에서는 첫 `sync`가 이것들을 덮어써서 드러나지 않았다.
- 수정 지시는 6절(담당 gameplay-systems, M2와 같은 담당이 차례로 — 둘 다 `chapter_one.gd`를 고친다).

### M4. A4 8.2 규칙 1·2 위반: 새 창 코드가 틀 값과 색을 직접 쓴다

- `chapter1/view/hud/flow_dialog.gd:21` `dim.color=Color(.01,.015,.02,.72)` — 팔레트 토큰이 아닌 색(규칙 2).
- `chapter1/view/hud/flow_dialog.gd:28` `frame.set_content_margin_all(26);frame.border_width_top=3` — `_style()` 결과에 여백·테두리 두께를 새로 씀(규칙 1: "테두리 두께·모서리 값을 새 화면 코드에 쓰지 않는다. `_style()`·`_button()`만").
- 고칠 것(ui-hud): 21행은 `palette.gd`에 막 색 토큰(예: `SCRIM`) 하나를 더하고 그것을 쓴다(지금 결과·정지 창 뒤 막이 쓰는 값이 있으면 같은 값으로). 28행은 지운다(`_style()` 그대로 쓴다). 창 모양이 조금 달라지면 그것이 맞다(나중에 US·U1이 `ui_style.gd` 한 곳에서 바꾼다).

---

## 2. 고치면 좋은 것(커밋을 막지 않음)

| # | 파일:행 | 내용 | 권고 |
|---|---|---|---|
| S1 | `chapter_hud.gd:1283` | `setup`에서 `Loc.set_locale("ko")`. 지금은 해가 없다(`loc.gd`의 기본 `_locale`이 이미 "ko"이고 엔진도 첫 `t()`에서 맞춘다). 그러나 T3-L5가 앱 `_ready`에서 `Loc.init()`(저장된 선택 → 스팀 → OS)을 부르면, 그 뒤에 도는 `hud.setup`이 플레이어의 언어 선택을 "ko"로 덮는다. 테스트가 같은 프로세스에서 다른 언어를 고른 뒤 HUD를 만들 때도 덮는다 | 이 줄을 지운다(기본값이 같으므로 화면은 변하지 않는다). 언어 결정은 앱 한 곳(L5)에서만 한다. 지우지 않으려면 앱 `_ready`로 옮기고 "L5가 `Loc.init()`으로 바꾼다" 주석 |
| S2 | `chapter_hud.gd:1907-1923` `_add_flow_actions` | 결과 단추 줄의 **마지막 자식을 옛 [다시 도전]으로 보고 지운다.** 확인 없이 지우므로, 앞 층(`_build_result40__q40` 1110-1114행)이나 A2 지시서 5가 단추를 하나 더 붙이면 다른 단추가 말없이 사라진다 | 7절 참고. 지금은 구조를 확인하고 어긋나면 `push_error` 후 손대지 않는다: 줄의 자식 수가 승리 3·패배 2이고 마지막이 `Button`이며 앞 단추와 다른 것. `hud_dump`의 모든 결과 시점에서 `RetrySameWitch`·`ReturnToMenu`·`QuitGame`이 정확히 하나씩이고 옛 "다시 도전" 글의 단추가 0개인지 찍는다 |
| S3 | `chapter_hud.gd:1929-1933` | 정지 창의 "첫 `Button` 자식"을 [계속하기]로 본다. `CheckButton`(흔들림 토글)도 `Button`이라, 앞 층이 토글을 앞으로 옮기면 토글 뒤에 단추가 붙는다 | `child is Button and not child is CheckButton`, 그리고 `_build_modal__q45`가 배치를 고친 경우(상자 자식 6)만 붙이고 아니면 `push_error` |
| S4 | `chapter_hud.gd:1940` | `modal.offset_top=-280;offset_bottom=280` 고정 높이. 1600×900 기준 170~730으로 들어가지만 A4 7.3 "절대 y 금지"와 어긋나고, q45가 배치를 건너뛴 경우에도 적용된다 | U7(정지 재설계)에서 컨테이너 크기에 맡긴다. 지금은 S3의 같은 조건 안으로 옮긴다 |
| S5 | `chapter_hud.gd:1318-1327` | 저장 없이 플레이(②) 판의 결과 창에 [보상 저장 다시 확인]·[보관함에서 다음 장비 선택]이 보인다(덤프 `profile-rejected-result`). 숨김 조건이 문구 `"검증 실행 · 저장 비활성"` 비교라 ② 문구에는 걸리지 않는다. 눌러도 쓰는 파일은 없다(프로필이 `available=false`) | 숨김 조건을 문구가 아니라 `_save_mode()!="on"`으로 |
| S6 | `ko.po` `result.button.retry` | 글 안에 `[R]`를 박았다. A4 7.3은 `{key_*}` 자리 표시자 | T3-L2·T4 패드 표기 때 같이 바꾼다 |
| S7 | `flow_dialog.gd:25` | 창 폭을 `custom_minimum_size.x`(720~900)로 고정. 글은 자동 줄바꿈이라 지금 잘리지 않지만 A4 7.5 "화면 설계의 폭은 최대 폭" | U1 때 `ui_style.gd`로 |
| S8 | `chapter_one.gd:469` | 앱이 `hud.skill_panel.visible=false`로 화면 노드를 직접 끈다 | `hud`에 `close_skill_tree()` 하나 |
| S9 | `chapter_hud.gd` `_open_notice` | 원인 키를 `"profile.reject.cause."+kind`로 이어 붙인다. 네 키는 모두 있다(확인함). 키 검사 도구가 정적으로 못 찾는다 | 키 네 개를 사전으로 |
| S10 | A4 4.9 | 안내 창 단추가 가로 줄이고, 파일을 만드는 [새 저장으로 시작…] 아래 `WARN` 한 줄이 없다. 8.2의 다섯 규칙 밖(4.9는 U 단계 설계)이라 지금 위반은 아니다 | U1·U3 때 |

---

## 3. 범위를 넘은 부분: 앱의 D4-A를 ui-hud가 넣은 것

ui-hud에 허락한 것은 신호 연결뿐이었다. `chapter_one.gd`에 들어간 `return_to_menu`·`abandon_run`·`quit_game`, 저장 실패 분기, 거부 때 시작 단추 분기, Esc·R 가드를 D4-A 명세에 대어 하나씩 봤다. **내용은 명세와 맞아 되돌릴 필요는 없다.** 다만 앞으로 `chapter_one.gd`는 gameplay-systems의 파일로 두고, 이 부분의 유지도 그쪽이 맡는다(M2·M3을 같은 담당에게 주는 이유).

| 항목 | 명세 | 확인 | 근거 |
|---|---|---|---|
| 포기의 저장이 쓰러짐과 같은 경로인가 | 3.2, F5 | **맞음.** `abandon_run`(479-485행) → `run.abandon()` → `_consume_events()` → "defeat" 이벤트 → `_save_terminal()`(549행) → `record_run(…, run.mode=="victory"(거짓), …)`. 새 저장 호출 없음 | 덤프: 포기 뒤 `receipts 1, completed_runs 0, items 2 = 가방 2, xp_gained 3`(H4) |
| 저장 실패 때 조용히 꺼지지 않는가 | F6 | **앱은 맞음**(494-495행: 저장 안 됐으면 `ask_unsaved("quit")` 뒤 return, `get_tree().quit()` 안 감). **화면이 물음을 바로 닫음 → M1** | `case-quitfail`: `CHAPTER1_QUIT` 안 찍힘, 물음 창 +1프레임에 닫힘 |
| 메뉴 복귀 때 판 상태·시드·자동 조작·프로브 초기화 | 3.1 | 코어 새로 만듦, `full_pilot.run` 교체, 이벤트 커서 둘·`_last_result`·`_has_move_target`·영수증·성장 보기 비움, `stash_open=false`, 스킬 트리 닫음, `seed_+=1`, 카메라 원위치, `_sync_profile`. 프레임 프로브는 `run`을 붙잡지 않는다(`frame_probe.gd:67` 인수로만 받음). 자동 조작의 `selections` 같은 진단 누적은 다시 도전 때와 같이 남는다(동작에 영향 없음). **주인공 표시가 남음 → M3.** 월드의 의식 표지 두 개(`[E] 의식 시작` Label3D)와 바닥 이름 줄(`GroundNameLeaders26`)은 처음 메뉴에서 보이고 복귀 뒤 숨는다(월드 상태가 초기화되지 않음, 아래 "관찰") | `FLOW` 시드 11 → 12, 복귀 뒤 `hero_empty:true`, 카메라 변환 동일 |
| 종료가 저장 완료를 기다리는가 | F6, H6 | **맞음.** 저장은 `_consume_events()` 안에서 동기로 끝나고(`_persist`가 임시 파일 → 바꿔 끼우기 → 다시 읽어 비교), 그 결과(`_saved_receipt==_receipt`)를 본 뒤에만 `quit()` | 코드 경로 489-498행. 저장 성공 경우의 판 중 종료는 실행하지 않음(아래) |
| 표현이 코어 상태를 직접 바꾸는가 | 규칙 | **없음.** HUD의 새 코드는 `run.mode` 읽기, 앱의 읽기 함수(`profile_rejected`, `profile_reject_info`, `profile.available`, `_profile_off`) 호출, 신호 발신뿐. 코어 호출은 모두 앱 함수(`abandon_run`, `return_to_menu`, `quit_game`, `play_without_save`, `start_fresh_profile`)에서 | diff 전체 검색 |
| 거부 때 시작 단추 | D5 3.1 | 맞음. `start_run` 385-389행이 거부 상태면 안내를 다시 연다 | `rej-play`: Esc로 닫은 뒤 시작 → `dialog_open:true, kind:notice` |
| Esc·R 가드 | F4, F10 | R: `result_revealed()` 뒤에만, 저장 실패면 묻기(198행) — 패배 뒤 0.3초 R이 막힘을 확인. Esc: 창의 단추가 `ui_cancel`을 먼저 받아 처리하고, 179행 가드가 뒤의 정지 토글을 막는다. 다만 가드는 `_unhandled_key_input__chapter`에만 있어 그 앞의 `_unhandled_key_input__chapterx`(564-580행)의 Q·F·E가 창 위에서도 코어에 닿는다. 코어가 `mode!="playing"`이면 모두 거절하므로(`chapter_core.gd:690·698`, `combat_core.gd:270`) 해는 없다(코드로만 확인) | `defeat`: `tick_at_fall 1278 = tick_now 1278, mode defeat` |
| 하지 말 것 | D4-A | 저장 경로·형식·`record_run` 인수 그대로. QA 종료 경로(310-318행) 그대로. 창 닫기(×) 가로채기 없음 | diff |

**관찰(고칠지는 디렉터).** 월드 표지 차이는 `chapter_world.gd`(T2-4·T1 R2가 고치는 파일)의 일이라 이번 수정에 넣지 않았다. 메뉴 뒤 배경에서 의식 표지 두 개가 처음 실행과 달리 안 보이는 정도다. 넣으려면 디렉터가 그 파일의 차례를 정한다.

---

## 4. 저장 안전(D5-U)

| 확인 | 결과 | 근거 |
|---|---|---|
| 네 길이 원본을 쓰기로 여는가 | **열지 않는다.** [폴더 열기]는 `OS.shell_open(폴더)`만(440-441행). [저장 없이 플레이]는 세션 플래그만(444-449행). [새 저장으로 시작…]은 `start_fresh_after_reject`가 새 이름(`chapter-one-profile-v3-r<시각>[-n].json`, 있는 이름은 건너뜀)과 가리키는 파일(임시 → 바꿔 끼우기)만 쓰고, `_persist`는 새 경로에만 쓴다(본래 경로는 `refused_path`로 되돌릴 때만 기억). 기록본은 `latest_readable_revision`이 읽기만. [게임 종료]는 저장 없음 | `chapter_profile.gd:169-208, 400-427` 읽음 |
| 실행으로 본 원본 바이트 | 세 실행 모두 `originals_unchanged:true`. play·mock은 `new_files:[]`. fresh는 새 파일 3개(새 저장, 그 기록본, `active.json`)만 생김 | `HUD_DUMP_FILES` |
| [폴더 열기]가 여는 경로 | 제품: `globalize_path("user://")` = `%APPDATA%\WitchMoira`(사용자 지정 폴더 설정 확인). 가리키는 파일을 따라간 경우도 같은 폴더(형제 파일만 허용). 검증 실행은 `_local/` 아래 격리 폴더. **실제로 눌러 보지 않았다**(탐색기가 뜬다) | 코드 |
| 두 번째 확인 창 | 있음. 기본 초점 [뒤로], Esc = 뒤로. 기록본이 있으면 [기록본에서 이어 하기][빈 저장으로 시작][뒤로], 없으면 [새 저장으로 시작][뒤로], 옛 형식은 빈 저장 문구 | `rej-*`: `Flow_back|뒤로` 초점 |
| 기록본에서 이어 하기가 만드는 파일 | `chapter-one-profile-v3-r20261117-132247.json`(리비전 3의 기록본에서 이어 리비전 4), 그 기록본 하나, `active.json`. 본 파일·기록본 셋 그대로 | `rej-fresh` |
| 옛 형식 위치 줄 | **틀림 → M2** | `case-legacy` |
| 기본 초점·키보드 | 안내 기본 초점 [저장 없이 플레이], Tab으로 네 단추가 돌고 창 밖으로 안 나감, Esc로 닫으면 시작 단추가 다시 엶 | `rej-play` |
| H-3 저장 없음 문구 + `--result-mock` | 결과 창 저장 줄과 성장 상자 줄이 "이번 실행은 저장하지 않습니다 · 저장 파일을 읽지 못했습니다" | `rej-mock`, 결과 시점 덤프 |
| 첫 처치 유니크 | ②에서 `first_boss_kill:false`, ③ 뒤에는 `true`(새 저장의 첫 판) | `rej-play`, `rej-fresh` |

---

## 5. A4 8.2 다섯 규칙, 번역 키, 언어 설정

| 규칙 | 결과 |
|---|---|
| 1 틀을 직접 만들지 않음 | **위반 1건 → M4**(`flow_dialog.gd:28`). `chapter_hud.gd`의 새 코드에는 `StyleBoxFlat.new()`·테두리 값 없음 |
| 2 색은 팔레트 토큰만 | **위반 1건 → M4**(`flow_dialog.gd:21`). 나머지는 `Palette.INK·INK_DIM·INK_FAINT·SURFACE·BRASS` |
| 3 글은 `Loc.t`, 폭 고정 금지, 한 줄은 말줄임+툴팁 | 새 화면 글은 모두 키. 위치·원인 줄은 툴팁+줄바꿈(경로는 어디서나 끊김). 창 최소 폭 고정은 S7 |
| 4 초점은 `ui_*`, 새 단추 모두 초점 목록 | 창은 `ui_cancel`로 Esc를 읽고 단추마다 이웃·다음을 서로 이어 창 안에 가둔다. 정지·결과·메뉴의 새 단추는 모달 안이라 `_focus_modal38` 목록에 든다(Tab으로 닿음을 실행 확인). 확인 창 기본 [취소], 거부 안내 기본 [저장 없이 플레이] |
| 5 휴대폰식 토글·선택 상자 새로 안 씀 | 지킴 |

- `tools/dev/i18n_scan.py`: `{"files": 15, "total": 627, "baseline_total": 627, "grown": [], "shrunk": []}`, 종료 0. diff의 `+` 줄에 있는 한글 글자 둘은 기존 줄을 고치며 다시 나온 옛 문구다(새 문구 아님). 코드의 `Loc.t` 키는 전부 `ko.po`에 있고 `ko.po`·`en.po`의 키 목록은 같다.
- 글자 크기: 새 코드의 최소 15(`profile.reject.detail`). 14 미만 없음.
- `Loc.set_locale("ko")`: 지금은 무해, L5와 부딪친다 → S1.

---

## 6. 결함 4(메뉴 복귀 뒤 주인공이 남음) 수정 지시서

**담당**: gameplay-systems(M2와 같은 담당이 차례로. 둘 다 `chapter_one.gd`).
**시작 조건**: 다른 에이전트가 `chapter1/view/actors/chapter_actors.gd`를 고치지 않는다(T2-2·T2-4는 아직 시작 전이어야 한다. T2-0b는 사본만 고치므로 겹치지 않는다). `chapter_one.gd`는 이 담당만.

**고칠 파일**
1. `chapter1/view/actors/chapter_actors.gd` — 맨 아래(최종 `reset()` 다음)에 새 함수 하나와, 최종 `setup()`(1530행) 끝에 기준값을 적어 두는 줄.
2. `chapter1/app/chapter_one.gd` — `return_to_menu()`(463행)에서 `actors.reset()` 바로 뒤에 새 함수 호출 한 줄.

**할 일**
- `setup()` 끝에서 "처음 메뉴의 주인공"을 적어 둔다: `hero.transform`, `_staff.transform`, `rig_skeleton`의 모든 뼈 자세(`get_bone_pose`), `_hero_materials` 각각의 `albedo_color·rim_enabled·rim·rim_tint·emission·emission_energy_multiplier`, `_hero_disc_material`·`_hero_ring_material`의 `albedo_color`, `owner_mark.visible`, `_hero_element_key`.
- 새 함수 `rest_for_menu() -> void`(이름은 담당이 정해도 됨): 위 값을 그대로 되돌린다(뼈 자세는 `_write_pose`로). `_hero_rim.visible=false`. 앞 층 메서드(`__q*`, `__cloister`)는 고치지 않고 최종 층에만 더한다.
- **`reset()`에 넣지 않는다.** `reset()`은 판 시작·다시 도전마다 불리고, 그 경로의 화면(T2-1 보조 덤프·골든과 무관한 표현 해시)을 바꾸지 않기 위해서다. 새 함수는 `return_to_menu()`에서만 부른다.
- 표현만 바꾼다. 코어·`run`을 읽지도 쓰지도 않는다.

**건드리지 않을 것**: 적 풀·적 자세·`sync` 경로, `chapter_world.gd`, 골든 파일, 데이터.

**끝났다는 기준(실행할 명령과 기대 결과)**
1. 같음 확인용 임시 스크립트를 `_local/` 아래에 만든다(저장소에 올리지 않음): 장면을 띄우고 메뉴에서 기준값(위 목록 + 뼈 자세 전체의 해시)을 찍은 뒤, 판 시작 → 300틱 → `abandon_run()` → `return_to_menu()` → 2프레임 뒤 같은 값을 찍는다. 기대: 모든 값이 같다(변환 ±0.001, 색 ±0.001, 뼈 해시 일치). 세 계열(ember·frost·arc)로 각각.
2. `godot --headless --fixed-fps 60 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.ember --flow-shots=abandon --profile-fixture=empty --profile-tag=d4-hero --dump=_local/d4/hero.json --scene=_local/d4/hero-scene.json` → `--scene` 출력에서 `menu`와 `flow-menu-returned`의 주인공 묶음(이름 `mage_animated`의 부모와 그 형제·자식, `HeroElementDisc`, `HeroElementRing`, 지팡이 노드)의 `t`·`visible`이 같다. 카메라도 같다(지금도 같음).
3. 기본 `hud_dump.gd`(옵션 없이, 세 계열)의 `HUD_DUMP`·`SCENE_DUMP` 해시가 고치기 전과 모두 같다(새 함수가 그 경로에서 불리지 않음을 보임). 고치기 전 값은 시작 직전에 새로 뜬다.
4. `python tools/dev/run_all.py --quick` 통과. 코어를 안 고쳤으므로 골든은 필수 아님(돌리면 4건 일치여야 함).
5. 창 캡처(1920×1080, 디렉터 또는 창 실행이 허락된 때): `--flow-shots=abandon --shots=_local/d4/hero-shots`의 `menu`와 `flow-menu-returned` 두 장을 나란히 보고서에 붙인다. 화면 비교는 사람이 본다.

**알려진 남는 차이**: 월드 의식 표지 두 개와 바닥 이름 줄(3절 관찰)은 이 지시의 범위 밖이다. 고칠 때 비교에서 그 노드들만 빼고 본다.

---

## 7. 단추를 찾는 방식(질문 6)

지금 방식은 글자 비교보다는 낫다(번역에 흔들리지 않는다). 그러나 "단추 줄의 마지막", "정지 창의 첫 `Button`"은 **앞 층의 배치 순서**에 기대고, 어긋나도 오류 없이 다른 단추를 지우거나 엉뚱한 자리에 붙인다. 그래서 깨지기 쉽다. 특히 A2 지시서 5(결과 재설계)와 U7(정지·결과)이 이 앞 층을 손볼 예정이다.

권하는 순서:
1. **지금(S2·S3)**: 같은 방식을 두되 구조를 확인하고, 어긋나면 `push_error`만 하고 손대지 않는다. `hud_dump`의 결과·정지 시점마다 이름 붙은 새 단추가 정확히 하나씩인지와 옛 [다시 도전] 단추 수(0)를 찍어, 회귀에서 바로 드러나게 한다.
2. **A2 지시서 5 / U7 때(근본)**: 결과·정지 창을 새 파일에서 최종 진입점이 직접 짓고, 단추는 **만드는 자리에서 이름을 준다**(`RetrySameWitch`, `ReturnToMenu`, `QuitGame`, `ResumeRun`, `AbandonRun`). 그러면 찾기 자체가 없어진다. 평탄화 파일의 `_build_result40__q40`를 그때 최종 진입점으로 접는다(CLAUDE.md "고치는 부분부터 정리"). 지금 앞 층을 고치지 말라는 D4-U의 제한은 그 작업에서 풀어 준다(디렉터 결정).
- 연결된 콜백으로 단추를 알아내는 방법(`pressed.get_connections()`)은 람다라 대상이 드러나지 않아 권하지 않는다.

---

## 8. 직접 실행한 명령과 결과

모든 Godot 실행은 헤드리스, 그 프로세스의 `APPDATA`를 `C:\Project\witch-moira\_local\appdata-review`로 돌렸다. 창 실행 없음. 원시 기록은 `_local/review-d4u/`.

| # | 명령(저장소 루트) | 결과 |
|---|---|---|
| 1 | (디렉터가 돌린 회귀) `_local/run_all-d4u-20261117.log` 읽음 | `RUN_ALL {"passed": 13, "failed": [], "skipped": []}`, `exit=0`. golden 4건 0 불일치, golden-textless 4건 0, loot-sim 3,000판 0, chapter 474·profile 115·loc 376 검사 0 실패, i18n-scan 627(기준 627) |
| 2 | `python tools/dev/i18n_scan.py` | `grown: []`, 종료 0 |
| 3 | `hud_dump.gd … --primary=chapter1.skill.ember --flow-shots=abandon --profile-fixture=empty --profile-tag=review-d4-abandon --dump=… --scene=…` | 종료 0, 오류 0. H1: menu(시드 11) → paused → (Esc로 확인 취소 확인) → defeat abandoned → menu(시드 12) → playing frost(시드 12). 확인 창 기본 초점 `Flow_cancel`, ←로 `Flow_go`. 결과 제목 "이번 도전을 포기했습니다". H4: `receipts 1, completed_runs 0, items 2, bag 2, xp_gained 3`. H2: 보이는 HUD 행 41 대 41(아래 한 줄 뺌), 글 차이는 `경험치 0/250 → 3/250`, `장비 보관함 · 0개 → 2개`뿐. 다른 점: `HeroLocator46`이 처음 메뉴에서 보임, 복귀 뒤 숨음(주인공이 없어 그리는 것이 없을 것으로 보이나 화면으로 보지 않음). 숨은 행 13개(첫 장비 알림·업그레이드 알림의 지난 내용)는 보이지 않으므로 문제 아님. H3: 카메라 같음, 주인공 묶음 다름(M3), 월드 표지 3개 다름(관찰) |
| 4 | `hud_dump.gd … --primary=chapter1.skill.frost --flow-shots=defeat --defeat-at=1200 …` | 종료 0. H5: 쓰러짐 틱 1278, 0.5초 `overlay_visible:false`, 0.3초에 넣은 R 뒤 0.8초에도 `mode defeat, tick 1278`, 2.0초 `revealed:true`. 결과 창에 옛 260행 문장 없음, 새 단추 넷이 두 줄로 들어감 |
| 5 | `hud_dump.gd -- --chapter1-profile-off --chapter1-qa-ignore-focus --flow-shots=quit` | 종료 0, `CHAPTER1_QUIT {"from":"menu"}`, 오류·경고 0(H6의 자동 부분) |
| 6 | `hud_dump.gd … --profile-fixture=rejected --profile-tag=review-d5-play` | 종료 0. 4절 표. 원본·기록본 해시 전후 같음, 새 파일 0 |
| 7 | 같은 것 + `--result-mock`(`review-d5-mock`) | 종료 0. 결과 창 저장 줄이 ② 문구(H-3). 새 파일 0. S5 관찰 |
| 8 | 같은 것 + `--reject-choice=fresh`(`review-d5-fresh`) | 종료 0. 새 저장·기록본·`active.json` 3개만 생김, 원본 넷 그대로 |
| 9 | `--script res://_local/review-d4u/review_flow.gd -- --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --case=legacy` | M2 재현: 로그 `file legacy-v2.json`, 앱 정보 `legacy-v3.json`(없음). v2 해시 그대로 |
| 10 | 같은 스크립트 `--case=quitfail`(저장이 늘 실패하는 격리 프로필 하위 클래스 `_local/review-d4u/failing_profile.gd`) | M1 재현: 키보드 Esc → Tab×2 → Enter → ← → Enter 뒤 `mode defeat, unsaved true`, 물음 창 없음(+1·+3·+33·+153프레임), 종료 안 됨. 그 뒤 결과 창에서 `request_leave("quit")`는 물음을 제대로 엶 |
| 11 | 같은 스크립트 `--case=keyboard` | **키보드만으로** Esc → Tab으로 [이번 판 포기] → Enter → ← → Enter → 결과 → Tab으로 [메뉴로] → Enter → 메뉴 → Tab으로 시작 단추 → Enter → `mode playing`. H8의 키보드 부분 통과(헤드리스 입력 주입) |

`_local/review-d4u/` 아래 파일(`review_flow.gd`, `failing_profile.gd`, 비교 스크립트, 덤프, 로그)은 검수용 임시 파일이다.

## 9. 확인하지 못한 것

- **창 캡처(H7, H-4)**: 1080p·720p 겹침·잘림·대비, 긴 경로 줄바꿈의 실제 모습, 확인 창이 정지 창 위에 겹친 모습. 창 Godot를 띄우지 말라는 지시에 따라 하지 않았다. 덤프의 좌표로는 1600×900 기준 화면 안에 들고 겹침이 없다.
- **기본 `hud_dump` 시점 해시의 전후 비교(H8 뒷부분)**: 고치기 전 코드로 돌릴 수 없어(작업 트리를 바꾸지 않음) 하지 않았다.
- **[폴더 열기]의 실제 동작**: 탐색기가 떠서 누르지 않았다. 코드로만 확인.
- **판 중 종료가 저장에 성공하는 경우**: 코드 경로로만 확인(저장 → 확인 → `quit()`). 실패 경우는 실행했다(M1).
- **창 위에서 마우스로 막 바깥을 눌러 초점을 잃은 뒤의 Esc**: 단추에 초점이 없으면 Esc를 아무도 받지 않아 창이 닫히지 않을 수 있다. 실행하지 않았다.
- 효과 풀의 입자 노드 16개가 복귀 뒤 지난 자리에 남는다(덤프상 보임 상태). 방출 중이 아니면 화면에 안 나오지만 보지 않았다.
- 가짜 언어 1.4배(T3-L4)에서의 창 배치. 도구가 아직 없다.
- 사람의 판단이 필요한 것(1.2초 지연의 답답함, 확인 창 수, 포기로 경험치 챙기기)은 평가하지 않았다.
