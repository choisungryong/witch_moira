# 기술 검수 — 2026-11-19 18:00 이후 main에 들어온 변경, 병렬 실행 실패의 원인 추정

작성: tech-lead, 2026-11-20. 근거는 `git show`로 읽은 diff와 지금 파일이다.
**Godot·회귀·골든은 하나도 돌리지 않았다**(디렉터 지시: 기계 여유 없음). 아래의 "통과"·"불변"은 모두 커밋 메시지나 장부의 주장이며 이 검수가 확인한 것이 아니다.
표시: [봄] 코드에서 확인 · [가설] 추정 · [미확인] 확인하지 않음 · [모델의 답] 손계산.

범위: `git log main --since="2026-11-19 18:00"` 의 커밋 34개 중 코드·데이터·도구를 바꾼 것. 문서만 바꾼 것은 D14(`3ca2832`)만 기술 위험을 본다.

---

## 0. 판정

**조건부 통과.** 코어 결정론이나 사용자 저장을 깨는 발견은 없다 [봄]. 다만 아래 둘은 닫기 전에 해야 한다.

1. `c9dbfb7`(리듬 첫 마디 2차)는 골든을 돌리지 않고 들어갔다. `CLAUDE.md` "수치는 데이터 파일에서 고친다. 고친 뒤 `measure_combat.gd`, `sim_loot.gd`, 골든을 다시 돌린다"를 어겼다. 꺼진 값이라 해시가 바뀔 가능성은 낮지만 [가설], 돌리기 전에는 "골든 불변"이라고 쓸 수 없다. 그리고 이 값은 켠 판에서 첫 성장 선택을 크게 늦출 수 있다(1.9절).
2. 시험판 인수(`e60b8a6`)는 저장은 안전하지만, 켜졌다는 표시가 어디에도 남지 않는다. 시험판으로 찍은 캡처·기록·사용자 소감이 기본 판의 것과 섞인다(1.1절 F-1).

## 1. 발견

심각도: **상**(결정론·저장·출시 빌드를 깸) / **중**(지금은 무해하지만 판정을 흐리거나 다음 작업에서 깨짐) / **하**(정리).
상은 없다.

### 1.1 시험판 인수 — `e60b8a6`, `chapter1/app/chapter_one.gd` `_apply_trial`(330~349행)

본 것 [봄]:
- **저장 안전**: `--chapter1-profile-off`가 없으면 경고만 내고 아무것도 켜지 않는다(337~338행). profile-off면 `_ready`가 `profile.configure()`를 부르지 않는다(355~357행). 두 판단 모두 같은 `_user_args()`에서 나오므로 서로 어긋나지 않는다. 시험판이 사용자 저장에 쓰는 길은 찾지 못했다.
- **내보낸 빌드**: `_user_args()`는 `qa_allowed`(23행, `OS.is_debug_build() or OS.has_feature("qa")`)가 거짓이면 빈 배열을 준다. 멤버 초기화는 `_init`보다 먼저 돌므로 `_init` 안의 `_apply_trial`도 이 판단을 따른다. 스토어 빌드(`export_presets.cfg` "Windows Store", `custom_features=""`)에서는 무시된다. QA 빌드(`custom_features="qa"`)에서는 켜진다. 의도대로다. `run_spells.json`은 `check_build.py`의 `REQUIRED_IN_PCK`에 이번에 들어갔다(`28123ed`).
- **판을 새로 만들 때마다 다시 적용되는가**: `ChapterRun.new()`가 나오는 곳은 `_init`(351행)과 `return_to_menu`(485행) 둘뿐이고 둘 다 `_apply_trial()`을 부른다. `retry()`는 같은 코어 객체로 `start()`를 다시 부르는데, `set_tuning`이 넣은 `tuning`과 `set_run_spells`가 넣은 `_pending_spells`는 `start()`가 지우지 않는다(`chapter_core.gd` 182·158행). 그래서 다시 도전에도 유지된다.
- **수치의 같음**: 시험판은 `JSON.parse_string` + `replace_document`, 기본 판은 `JSON.new().parse` + `replace_document`(`combat_tuning.gd` 268~286행)로 같은 검증·정규화를 지난다. 공유 문서(`_shared_tuning`)는 건드리지 않는다.

| # | 심각도 | 곳 | 문제 | 재현 | 권하는 고침 |
|---|---|---|---|---|---|
| F-1 | 중 | `chapter_one.gd` 332~349, 120·368행 | 시험판이 켜졌다는 사실이 화면·로그·기록 어디에도 남지 않는다. `CHAPTER1_READY`·`FULL_CHAPTER_READY` 줄, `_app_error`("검증 실행 · 저장 비활성"), `recorder.begin(run,"d1")`, `play_recorder` 모두 같다. 시험판 캡처나 사람 플레이 기록이 기본 판의 것으로 읽힌다. 장부 U-35는 이미 시험판을 해 본 사용자 소감에서 나왔다 | `--chapter1-profile-off --chapter1-trial=spells,rhythm`로 띄우고 첫 화면·로그를 보면 기본 판과 구별할 표지가 없다 | `_apply_trial`이 적용한 목록을 `var trial_parts: PackedStringArray`로 남기고, (1) `FULL_CHAPTER_READY` JSON에 `"trial":[...]`, (2) `_app_error`에 "· 시험판: spells, rhythm", (3) `recorder.begin`에 넘겨 기록 요약에 `trial` 필드, (4) `play_recorder` 머리에 같은 필드 |
| F-2 | 하 | 339행 | 모르는 낱말(`spell`, `rhytm`)은 소리 없이 버려진다. 오타가 나면 기본 판을 시험판으로 믿고 본다 | `--chapter1-trial=spell` | 모르는 낱말마다 `push_warning`, 하나도 적용하지 못하면 경고 |
| F-3 | 하 | 341·346행 | 데이터 경로를 문자열로 다시 적었다. 코어에는 `Tuning.DEFAULT_PATH`(`combat_tuning.gd` 6행), `RunSpells.DEFAULT_PATH`(`run_spells.gd` 7행)가 있다(T7의 "경로를 여러 곳에서 직접 부르지 않는다") | — | 두 상수를 쓴다 |
| F-4 | 중 | 커밋 전체 | 검사 없이 들어온 분기다. 제품 코드인데 자동 검사가 없다 | `grep chapter1-trial chapter1/tests` → 0건 | `_apply_trial(args: PackedStringArray)`로 인수를 받게 하고, `test_profile_app_guard.gd`에 넷을 더한다: profile-off 있음 → `run.spells` 비지 않음·`tuning.rhythm.enabled`; profile-off 없음 → 둘 다 꺼짐; `return_to_menu` 뒤에도 유지; `qa_allowed=false`면 무시 |
| F-5 | 하 | `modal_input_check.gd` 30~37, `hud_dump.gd`(`--run-spells=on`), `scene_shot.gd` | "문서를 읽어 `enabled=true`로 `set_run_spells`"가 세 도구와 제품 코드에 따로 있다(`PROCESS-CHECKS`의 되풀이 금지) | — | 도구는 `--chapter1-trial=spells --chapter1-profile-off`를 넘기는 것으로 바꾸고 자기 구현을 지운다(F-4가 먼저) |

### 1.2 KS-3 코어 — `82979ac`

본 것 [봄]: 꺼진 경로에서 새로 도는 것은 (a) `_hero_damage`의 인수 둘(기본값 "hazard"/0), (b) 적 탄마다 `_hostile_src`에 한 칸 넣고 맞거나 사라질 때 지움, (c) 이벤트 `hero_hit`에 `source_kind`·`source_id`·`hp_after_raw`, `death`에 `role`, (d) `_step_enemies`·`_approach_crowd`의 `staggered_until` 읽기(키가 없으면 0)뿐이다. 골든은 `snapshot()`의 해시만 본다(`golden_core.gd` 19행). (a)~(d)는 스냅숏에 들어가지 않으므로 꺼진 판의 골든 해시를 바꾸지 않는다는 주장은 코드와 맞는다. 켠 판에서만 적 사전에 `cc_src`·`staggered_until`이 생긴다.

| # | 심각도 | 곳 | 문제 | 권하는 고침 |
|---|---|---|---|---|
| K-1 | 중 | `golden_core.gd` 19행과 이번 이벤트 변경 | 골든은 이벤트 내용을 보지 않는다. 오늘 `hero_hit`·`death`·`growth`·`detonate`의 꼴이 바뀌었고 이것을 전투 기록기(`run_record.gd`)와 화면이 읽는다. 앞으로 저장 스키마 5의 판 기록도 이것에서 나온다(`chapter_one.gd` 580행 주석). 이벤트 꼴이 깨져도 골든은 통과한다 | qa-perf: 골든 사례에 "이벤트 꼴 해시"(종류별 키 집합과 값의 타입만, 값은 빼고)를 덧붙이는 `--event-shape` 비교. 값이 아니라 꼴이라 수치 조정으로는 바뀌지 않는다 |
| K-2 | 하 | `chapter_core.gd` `_apply_ring_control` 114~118행(diff 기준) | 이미 더 긴 경직이 걸려 있어 늘리지 않은 경우에도 `staggers`를 세고 `cc_src`를 덮어쓴다. 측정값(`metrics.ward.staggers`)이 부푼다 | `if tick+ticks>...` 안으로 셈과 `_set_cc_src`를 넣는다. 켠 판 골든만 바뀐다 |
| K-3 | 하 | `combat_core.gd` `_hostile_src` | 꺼진 판에도 적 탄마다 사전 한 칸을 만들고 지운다. 비용은 작다 [가설]. 스냅숏 밖이라 `restore` 같은 길이 생기면 출처가 `hostile.<kind>`로 떨어진다(지금은 그런 길이 없다 [봄]) | 그대로 두되, 탄 사전에 `src_id`를 넣는 방법은 스냅숏(골든)을 바꾸므로 하지 않는다는 판단을 주석에 남긴다(이미 있음). 조치 없음 |

### 1.3 카드·기록 필드 — `1533d34`

- [봄] `combat_core.gd` `choose()`가 고른 카드의 꼴을 걸린 제안에서 읽은 뒤 `growth.choose`를 부른다. 읽기만 하고 뽑지 않는다. `run_growth.gd` `card_contract`는 `effective_skill`(읽기 전용, 133~141행)과 `_pair_links`(읽기)만 쓴다.
- [봄] `run_record.gd`의 `_hero_hits` 행이 3칸 → 4칸(`985dfba`) → 5칸(`1533d34`)으로 두 담당이 이어서 늘렸다. 읽는 쪽(`hit[3]`, `hit[4]`)이 `hit.size()`를 확인하므로 어긋나지 않는다.

| # | 심각도 | 곳 | 문제 | 권하는 고침 |
|---|---|---|---|---|
| R-1 | 하 | `combat_record_view.gd` 73행 주석, `chapter_hud.gd` `_add_flow_actions`(`_record_level`) | 요약에 `level`이 생겼는데(`1533d34`) 화면은 여전히 `run.growth.snapshot()`에서 레벨을 따로 읽고, 주석은 "기록에 레벨이 없다"고 한다. 같은 값이 두 곳에서 나온다 | 화면이 `run_record.level`을 읽게 하고 `_record_level`을 지운다(T8 S3에서 함께) |
| R-2 | 하 | `run_record.gd` `_build_summary` | `recent_dps`는 걸친 첫 초를 통째로 넣는다(최대 1초 분량 과대). 표시값으로는 무해 | 주석으로 남긴다 |

### 1.4 전투 기록 화면 — `985dfba`

[봄] 화면은 앱이 넘긴 `run_record_view`의 복사본만 읽는다(`set_run_record`). 결과 창이 아닐 때 닫힌다(`_dialog_alive`). 코어 쓰기 없음. 하네스가 본보기로 든 꼴(계약 Dictionary를 받는 화면)과 같다. 발견은 R-1뿐.

### 1.5 켠 판의 성장 카드 — `433b823`

| # | 심각도 | 곳 | 문제 | 권하는 고침 |
|---|---|---|---|---|
| C-1 | 중 | `chapter_hud.gd` 1186~1193행 | 새 기능(켠 판 카드)을 옛 층 사슬 `_growth_cards38 → _growth_cards38__q38`의 끝에 붙였다. 자식 번호(`cards.get_child(i)`)로 옛 층이 지은 노드를 덧입힌다. 하네스 2.4-5("옛 층 메서드에 층을 더하지 않는다")가 같은 날 늦게 생긴 규칙이라 위반이라기보다 빚이다 | T8 S1이 이 층을 걷어 낸다 |
| C-2 | 하 | `spell_card.gd` 35·68행 | 화면 부품이 `run.spells`, `run.growth.effective_skill`을 직접 읽는다. 읽기만 한다 [봄] | T8 S1에서 어댑터로 옮긴다 |
| C-3 | 중 | `chapter_hud.gd` 144·193·726·1189행, `combat_core.gd` 222행, `run_growth.gd` 172~195행 | **표현이 코어의 뽑기를 일으킨다.** `get_offer()`는 걸린 제안이 없으면 그 자리에서 뽑는다(성장 RNG를 움직이고 `_offer`를 채운다). HUD는 매 프레임 `sync__cloister`에서 `get_offer()`를 부른다. 성장 RNG는 시드가 따로라(`seed ^ 0x47524f57`) 누가 먼저 부르든 같은 카드가 나오고, 골든은 자동 조작이 먼저 부른다 — 그래서 지금은 결과가 같다 [봄]. 그러나 "표현은 읽기 전용 상태만"의 규칙을 문자 그대로는 어긴다. 화면 계약 어댑터가 이 함수를 여러 번 부르게 되면 근거가 더 흐려진다 | gameplay-systems: 레벨업으로 `mode`가 `choice`가 되는 순간 코어가 제안을 뽑아 두고, `get_offer()`는 걸린 것만 돌려주게 한다. 켠·꺼진 판 골든이 바뀌는지 돌려 보고(바뀌지 않아야 한다 [가설]: 뽑는 순서가 같으므로), 바뀌면 의도한 변경으로 밝힌다. T8은 그 전까지 `get_offer()`를 어댑터 한 곳에서만 부르게 한다 |
| C-4 | 하 | `scene_shot.gd` 290행 | 검사 도구가 코어 사적 필드 `run.growth._offer`에 쓴다. 검사 전용이지만 코어 이름이 바뀌면 조용히 깨진다 | T8의 계약 픽스처가 들어오면 이 길을 지운다 |

### 1.6 울타리 효과 — `c4d4d24`

[봄] 꺼진 판: `ring_spell_fx.sync`가 `run.spells.is_empty()`면 메시를 만들지 않는다. 색 함수를 `Palette.spell_color`로 바꿨지만 기본 세 기술의 색 값이 예전 `COLORS`와 같다(`palette.gd` 38~40행 = `combat_juice.gd` `COLORS`). 꺼진 판 화면 불변 주장과 맞다(픽셀은 보지 않음). 표현이 코어에 쓰는 줄은 없다(diff에서 `run.… =`·`erase`·`append` 0건).

| # | 심각도 | 곳 | 문제 | 권하는 고침 |
|---|---|---|---|---|
| V-1 | 중 | `ring_spell_fx.gd` 153행 | 코어 사적 필드 `run._next_cast`를 읽는다. 전투 막대(`combat_bar.gd`)의 사적 필드 넷과 같은 문제(하네스 2.3). 이름이 바뀌면 준비 테가 조용히 늘 찬 것으로 그려진다 | gameplay-systems가 읽기 전용 `cooldown_view() -> {skill id: {next_tick, cooldown_ticks}}`를 코어에 두고 막대와 이 효과가 함께 쓴다(T8 S4와 묶음) |
| V-2 | 하 | `chapter1/view/ring_spell.gdshader` | 새 셰이더를 `chapter1/view/` 바로 아래(옛 층 자리)에 두었다. 같은 날 전조 셰이더는 `view/fx/`에 들어갔다 | `view/fx/`로 옮긴다(`.uid` 함께, preload 한 곳) |
| V-3 | 하 | `palette.gd` 62행 | 표현 공통 파일이 코어 `run_spells.gd`를 preload해 `RING_IDS`를 읽는다. 읽기만 하므로 허용 범위 | 조치 없음. 기록만 |

### 1.7 리듬 첫 마디 — `657c4b1`, `c9dbfb7`

| # | 심각도 | 곳 | 문제 | 권하는 고침 |
|---|---|---|---|---|
| D-1 | **중** | `c9dbfb7` | 데이터 수치를 바꾸고 골든을 돌리지 않았다(커밋 메시지에 직접 적음). 리듬은 꺼져 있어 해시가 바뀔 가능성은 낮다 [가설: 꺼진 판은 `rhythm.*`를 읽지 않고 스냅숏에 튜닝이 들어가지 않는다]. 그래도 규칙상 "골든 불변"은 아직 확인되지 않은 상태다 | 기계가 빌 때 `python tools/dev/run_all.py --only golden-all,rhythm`. 장부 U-35의 상태 칸에 "골든 미확인"을 적어 둔다 |
| D-2 | 중 | `combat_tuning.json` `rhythm.beats[0]` | 켠 판의 첫 성장 선택이 크게 늦어질 수 있다. [모델의 답, 1판] 레벨 2는 경험치 10(`xp_thresholds`), 보통 적 경험치 1(`combat_core.gd` 35행 `ENEMY_DEFS.walker.xp`)이면 처치 10번이 필요하다. 시작 1마리 + 2.5초에 1마리면 생성만으로 10마리째가 약 22.5초에 나온다. D9·하네스 8.1의 "첫 선택은 판 시작 4~6초"와 4배 차이다. 장 코어가 경험치를 다르게 줄 수 있어 [미확인] 실측이 필요하다 | content-balance: 켠 판의 첫 레벨업 시각을 `sim_power.gd` 또는 balance_sim으로 재고, 첫 마디의 경험치(오브)나 첫 레벨 문턱으로 4~6초를 지킬지 디렉터가 정한다. "멀리서 하나 둘 다가오는 공포"(사용자)와 "첫 은총 4~6초"(D9)가 지금 수치에서 부딪친다 |
| D-3 | 중 | 같은 곳 `taste_crest` | 2400틱의 맛보기 무리(8마리)는 마디 한도로 잘린다(`_spawn_crest`의 `if count>=cap:break`, `chapter_core.gd` 624행). 한도가 6이 되어 맛보기 무리는 많아야 "6 − 살아 있는 수"마리다. 설계한 장면(부채꼴 8마리)이 사라졌을 수 있다 | content-balance가 `taste_crest.count`와 첫 마디 한도를 함께 본다 |
| D-4 | 하 | `docs/specs/D11-run-rhythm-and-reward-loop.ko.md` 204·211행 | 명세는 아직 `initial_pack 6`. 데이터는 1 | design-lead가 D11 표를 고친다(값은 데이터가 기준이라는 한 줄과 함께) |
| D-5 | 정보 | — | 사용자가 시험판 없이 하는 기본 판은 여전히 시작 12마리다(`_initial_pack_count`, 448~449행). "시작부터 몹이 너무 많다"는 기본 판에서는 그대로다 | 디렉터가 사용자에게 "시험판에서만 바뀜"을 분명히 한다 |

### 1.8 Godot 시간 제한 — `9d1c812`

[봄] `godot_guard.run_guarded`가 넘치면 `taskkill /T /F`로 트리째 끝내고 124를 돌려준다. Ctrl-C도 트리째. `hud_dump.gd`는 임포트 없는 폴더와 프로필 없는 판 포기 흐름을 바로 거절한다.

| # | 심각도 | 곳 | 문제 | 권하는 고침 |
|---|---|---|---|---|
| G-1 | 하 | `hud_dump.gd` `wall_limit_s := 1500`, `godot_guard.py` `DEFAULT_WINDOW_S = 1200` | 창 실행(`--shots`)에서는 감싸개가 20분에 먼저 끊어 hud_dump의 정돈된 `HUD_DUMP_RESULT {"error":"wall_limit"}`가 나오지 않는다 | hud_dump 기본을 1100초로 낮춘다 |
| G-2 | 중 | `run_dev.py` `import_project` | 임포트는 시간 제한도, 다른 프로세스와의 잠금도 없다. 병렬 실패의 한 원인 후보(2절 H2) | 2절 M2 |
| G-3 | 하 | `run_all.py` 269행 주석 | 날짜가 "2026-11-21"(미래) | 고친다 |

### 1.9 도구 정리 — `28123ed`

| # | 심각도 | 곳 | 문제 | 권하는 고침 |
|---|---|---|---|---|
| T-1 | 중 | `tools/manager/test_backend.py` `test_stale_server_report` 끝(`/api/server`가 stale이 아니어야 함) | 진짜 `tools/manager/*.py`의 수정 시각을 서버 시작 때와 비교한다. 같은 작업 트리에서 다른 담당이 그 사이 `tools/manager/*.py`를 고치면 실패하고, 혼자 다시 돌리면 통과한다. **"manager 검사가 번갈아 실패" 증상과 맞는다**(2절 H3) | 진짜 서버 대신 임시 폴더를 `APP`로 한 서버를 띄우거나, 단언 직전에 `server.code_started = server.code_snapshot()`로 다시 잡는다 |
| T-2 | 하 | `check_build.py` self_test, `tools/dev/test_check_build.py` 15~22행 | "chapter1/data/*.json이 모두 목록에 있다"를 진짜 폴더로 단언한다. 누가 데이터 파일을 새로 만들면 목록을 고치기 전까지 도구 자체 검사가 빨갛다. 의도된 경보이지만 "도구가 고장"처럼 보인다 | 이 단언을 `tools-selftest`에서 빼고 `run_all`의 `records` 묶음 검사(이름: `data-list`)로 옮긴다 |
| T-3 | 하 | `tools/manager/catalog.py` 366행 | `chapter_one.gd` 본문에서 `--chapter1-trial=` 글자를 찾는다. 글자 맞춤이라 이름을 바꾸면 조용히 "찾지 못함" | 그대로 두되 `test_backend`에 이 줄이 "찾지 못함"이 아님을 확인하는 검사 하나 |

### 1.10 D14 디렉터 기획 — `3ca2832`(문서만, 기술 위험만 본다)

구현 전에 design-lead의 수치 명세(D14 5절 걸음 4)에 들어가야 할 기술 조건이다.

| # | 위험 | 조건 |
|---|---|---|
| D14-1 | "화면에 보이는 적을 쓸어버린다"(4.1) — 코어는 카메라를 모른다. 표현의 화면 크기를 코어가 읽으면 해상도마다 판 결과가 달라진다(결정론 깨짐) | 범위는 코어 상수(주인공 둘레 반경 또는 고정 직사각형, 데이터 파일)로 정한다 |
| D14-2 | "컷인 동안 전투는 멈춘다", "짧게만" 설정(4.4) — 설정이 틱 수를 바꾸면 같은 시드의 판이 설정마다 달라진다 | 코어는 `mode="descent"`로 들어가 앱이 `resume()`을 부를 때까지 틱을 진행하지 않는다(성장 선택과 같은 실시간 정지). 컷인 길이는 표현과 앱의 일이고 틱에 영향이 없다. 자동 조작은 즉시 `resume`한다 |
| D14-3 | 입력 하나가 늘고 사용 시점이 선택이 된다(4.2) | 자동 조작(`chapter_pilot.gd`)의 사용 규칙을 명세에 적는다. 없으면 골든·측정이 강림 없는 판만 본다 |
| D14-4 | 탄 지우기·경험치 빨아들이기·무적(4.3) | 모두 코어. 표현이 탄을 지우거나 오브를 끌어오면 안 된다 |
| D14-5 | 게이지가 "조합이 먹힌 타격"으로 찬다 | KS-3의 이벤트(`detonate`, `hit.vs_cc`)가 이미 있다. 게이지는 코어 안에서 같은 판정으로 센다(이벤트를 읽는 표현 쪽에서 세지 않는다) |
| D14-6 | `crown` 노드(4.5)가 강림을 바꾼다 | 스킬 트리 데이터 개정 = 저장의 `tree_revision`과 빌드 검증(`_normalize_build`)에 걸린다. 트리 개정은 T6 스키마 5의 옮기기 규칙을 따른다 |
| D14-7 | 컷인 화면 | 하네스 단계를 지난다. 계약은 T8의 규칙(전투 HUD와 같은 "한 객체 덮어쓰기"가 아니라 사건 계약: 강림 이벤트 하나에 계약 하나) |

## 2. 병렬 실행의 간헐 실패 — 원인 추정

### 2.1 증거(디렉터 전달)와 이번에 본 것

- 전달: `WinError 1450`(시스템 자원 부족) 여러 번 / C 드라이브 2.4GB까지 줄어듦 / `tools-selftest`의 한 파일과 `manager`의 한 검사가 번갈아 실패, 혼자 돌리면 통과 / 예전의 `chapter`·`app-guard` 일회성 SCRIPT ERROR / 임포트 중 종료 코드 3221225477(0xC0000005, 접근 위반).
- 본 것 [봄]:
  - 작업 트리 21개(`git worktree list`), 그중 14개가 `.claude/worktrees/` 아래(본 저장소와 같은 C 드라이브). 6개에 자기 `.godot` 임포트 캐시가 있다(본 저장소의 `.godot`은 112MB). 8개에 자기 `_local/appdata`가 있다.
  - `godot.py`로 띄우는 모든 실행이 **하나의** APPDATA(`_local/appdata/godot/`)를 쓴다. 그 안에 `WitchMoira/logs`(godot.log와 시각 이름의 돌린 로그), `shader_cache`, `vulkan`이 있다. 같은 트리의 검사·캡처·측정이 동시에 돌면 로그 돌리기와 셰이더 캐시를 함께 쓴다.
  - `run_all.py`는 검사마다 APPDATA를 나누지만(`run_all_<검사>`), 같은 트리에서 `run_all`이 둘 돌면 같은 이름의 폴더를 함께 쓴다. 픽스처 폴더 이름은 초 단위 시각이다(115~122행).
  - `run_dev.py --import-only`(그리고 `run_dev.py`로 게임을 띄울 때마다)가 잠금 없이 `.godot`에 임포트한다. `run_all --jobs N`도 시작 때 이것을 부른다(598행). 같은 트리에서 다른 Godot가 `.godot/imported`·`uid_cache.bin`·`global_script_class_cache.cfg`를 읽는 중이어도 막지 않는다.
  - `tools-selftest`는 파일 넷을 동시에 돌리고(266행), 그중 `test_audio_tools.py`는 ffmpeg와 파이썬 자식 프로세스를 여럿, `test_godot_ps.py`는 120초 자는 프로세스 트리를 실제로 만들고 끝낸다(67~76행). 실패한 파일은 혼자 한 번 더 돌린다(05a97d7).
  - `test_backend.py`의 `test_stale_server_report`는 진짜 `tools/manager/*.py`의 수정 시각에 기댄다(1.9 T-1).
  - Godot 콘솔 실행 파일은 실행마다 콘솔 부모 + 엔진 자식 + conhost 셋을 만든다(`godot_guard.py` 머리 주석).
- 재지 못한 것 [미확인]: `.claude/worktrees` 전체와 `_local/` 전체의 크기(`du`가 90초 안에 끝나지 않아 멈췄다 — 그 자체가 파일 수가 매우 많다는 뜻일 수 있다), 페이지 파일 설정, 1450이 어느 호출에서 났는지(파이썬 `CreateProcess`인지 파이프 읽기인지).

### 2.2 가설(그럴듯한 순서)

**H1. 메모리 커밋 한도·커널 자원의 고갈, 그리고 디스크 부족이 그것을 앞당김** [가설]
- 열 개가 넘는 담당이 각자 `run_all --jobs N`, `tools-selftest`(넷 동시), 캡처를 돌리면 Godot 프로세스 트리(셋씩)와 파이썬 자식이 수십 개 동시에 뜬다. 1450(ERROR_NO_SYSTEM_RESOURCES)은 페이지·비페이지 풀, 데스크톱 힙, 커밋 한도가 모자랄 때 `CreateProcess`·파이프 I/O에서 나는 전형이다.
- C 드라이브가 2.4GB면 시스템 관리 페이지 파일이 커지지 못해 커밋 한도가 낮게 묶인다. 할당 실패를 확인하지 않는 코드(임포트 중의 Godot)는 널 포인터를 밟아 0xC0000005로 죽을 수 있다. 세 증거(1450, 디스크, 3221225477)를 하나로 설명한다.
- 디스크를 먹는 것: 작업 트리마다의 `.godot` 임포트(본 저장소 기준 112MB × 트리 수), 작업 트리 자체의 원화·모델 사본, `_local/` 아래 캡처·빌드(`builds`, `builds2`)·`equiv`의 임시 체크아웃.

**H2. 같은 작업 트리 안에서 임포트와 실행이 겹침** [가설]
- `run_dev.py`의 임포트는 잠금이 없다. 한 담당이 임포트하는 동안 다른 담당의 검사가 같은 `.godot`의 캐시 파일을 읽으면, 반쯤 쓰인 `global_script_class_cache.cfg`나 `.ctex`를 읽어 SCRIPT ERROR가 나거나, 두 임포트가 같은 파일을 쓰다 엔진이 죽는다. `app-guard`(장면 전체를 읽음)와 `chapter`의 일회성 SCRIPT ERROR, 임포트 중 3221225477과 맞는다.
- 같은 결의 원인: 디렉터가 본 저장소에 병합·커밋하는 순간 그 트리에서 돌던 검사가 반쯤 바뀐 `.gd`를 읽는 경우.

**H3. 검사가 진짜 저장소 상태에 기대어, 동시에 고치는 다른 담당의 변경에 흔들림** [가설, 한 건은 코드로 확인]
- `manager`: `test_stale_server_report`가 진짜 `tools/manager/*.py` 수정 시각을 본다 [봄]. 그 사이 누가 그 파일을 고치면 실패한다. 오늘 `28123ed`·`c4d770c`가 그 폴더를 고쳤다.
- `tools-selftest`: `test_check_build.py`가 진짜 `chapter1/data/*.json` 목록을 본다 [봄]. `test_audio_tools.py`·`test_godot_ps.py`는 자식 프로세스를 실제로 만들어 H1에 가장 먼저 걸린다.

부수: 같은 APPDATA(`_local/appdata/godot/`)의 로그 돌리기·셰이더 캐시 공유(H4)는 창 캡처에서 이상한 오류를 낼 수 있으나, 오늘 증거와 직접 이어지는 것은 찾지 못했다.

### 2.3 가려 낼 실험(qa-perf, 다른 작업이 없는 조용한 때)

모두 **버려도 되는 작업 트리 하나**에서 한다. 본 저장소와 사용자 폴더는 건드리지 않는다. 결과 원시는 `_local/flake/`에.

| # | 가를 가설 | 방법 | 판정 |
|---|---|---|---|
| E1 | H1 | 같은 헤드리스 검사(`test_chapter_run.gd`)를 동시에 N=4, 8, 12, 16개 띄우며 `typeperf "\Memory\Committed Bytes" "\Memory\Commit Limit" "\Memory\Pool Paged Bytes" "\Memory\Pool Nonpaged Bytes" -si 1`을 함께 기록. 각 N에서 3번. 시작 전에 `Get-CimInstance Win32_PageFileUsage`, `Get-PSDrive C`를 적는다 | 1450·0xC0000005가 커밋이 한도의 95%를 넘을 때만 나면 H1. N과 상관없이 드물게 나면 H1 아님 |
| E2 | H2 | 한 셸에서 `run_dev.py --import-only`를 30번 되풀이하며 매번 `chapter1/art/` 아래 그림 하나의 수정 시각을 바꾼다(`os.utime`, 내용은 그대로). 다른 셸에서 `run_all --only app-guard,chapter`를 30번 | SCRIPT ERROR·3221225477이 겹친 때에만 나면 H2. 대조군: 임포트 없이 같은 30번 |
| E3 | H3 | `manager` unittest를 20번 돌리는 동안 2초마다 `tools/manager/catalog.py`의 수정 시각만 바꾼다 | `test_stale_server_report`만 실패하면 H3 확정. 이어 같은 방식으로 `chapter1/data/`에 빈 json을 넣었다 지우며 `test_check_build.py` |
| E4 | H4 | 창 캡처(`hud_dump --shots`) 넷을 같은 APPDATA로 동시에, 그리고 각자 다른 APPDATA로 동시에 | 로그·셰이더 캐시 오류가 공유 때만 나면 H4 |

E1은 기계를 일부러 바닥까지 몬다. 사용자 작업이 없는 때에만, 디스크 여유를 20GB 이상 만든 뒤 한다(디스크 부족 상태에서 몰면 다른 프로그램도 죽는다).

### 2.4 당장 넣을 수 있는 완화책(실험을 기다리지 않음)

| # | 무엇 | 누가 | 효과 |
|---|---|---|---|
| M1 | **디스크 비우기**: 끝난 작업 트리를 `git worktree remove`(디렉터가 목록을 보고), `_local/builds*`·`_local/equiv/*`·오래된 `_local/shots/*` 정리. C에 20GB 이상 여유 | 디렉터 | H1의 가장 싼 대책 |
| M2 | **임포트 잠금**: `tools/dev/` 에 작은 모듈 `repo_lock.py`(`os.open(..., O_CREAT|O_EXCL)`로 `_local/locks/import.lock`, pid와 시각을 적고 프로세스가 없으면 오래된 잠금으로 본다). `run_dev.import_project`가 잡고, `godot.py`·`run_all.run_process`는 잠금이 있으면 풀릴 때까지(최대 10분) 기다린 뒤 띄운다. 임포트에도 `godot_guard` 시간 제한(헤드리스 기본) | manager-tools | H2 |
| M3 | **기계 전체의 동시 Godot 수 상한**: 본 저장소의 `_local/locks/godot-slot-<k>` 파일 K개(작업 트리들이 `godot_ps.main_root()`로 같은 곳을 본다)를 좌석으로 쓴다. `godot.py`와 `run_all.run_process`가 좌석 하나를 잡고 띄운다. K 기본 6, `MOIRA_GODOT_SLOTS`로 바꿈. 사람의 플레이(`run_dev`의 비격리 실행)는 좌석을 잡지 않는다 | manager-tools | H1. 느려지는 대신 실패하지 않는다 |
| M4 | **검사의 격리**: 1.9 T-1(`test_backend`), T-2(`test_check_build` 단언을 records 묶음으로) | manager-tools | H3 |
| M5 | **환경 실패를 따로 적기**: `run_all`이 결과 글에서 `WinError 1450`·종료 코드 3221225477·`0xC0000142`를 보면 그 검사를 혼자 한 번 다시 돌리고, 행 상태를 `pass`가 아니라 `pass(env-retry)`로, 다시 실패하면 `FAIL(env)`로 적는다. 통과로 숨기지 않는다 | manager-tools | 판정을 흐리지 않게 |
| M6 | **운용 규칙**(디렉터): 다른 담당이 돌고 있으면 `--jobs`는 2까지. 병합·커밋은 본 저장소에서 `run_all`이 도는 동안 하지 않는다. 작업 트리에서 처음 Godot를 띄우기 전에 `run_dev.py --import-only` 한 번 | 디렉터 | H1·H2 |
| M7 | `godot.py`의 APPDATA를 용도별로 나눔: `isolated_env('godot-' + 스크립트 이름)`. 셰이더 캐시는 용도마다 한 번 데워진다 | manager-tools | H4(값싼 예방) |

M2·M3·M5·M7은 `tools/dev/godot.py`, `run_all.py`, `run_dev.py`, `isolated_env.py`를 함께 고치므로 **한 담당(manager-tools)의 한 묶음**으로 준다. M4는 `tools/manager/`·`tools/dev/test_check_build.py`라 같은 담당의 둘째 묶음으로 이어서 한다.

## 3. 실행하지 못한 확인

- Godot·회귀·골든·`equiv.py`·측정 모두 돌리지 않았다. 커밋 메시지의 "골든 불변"·"검사 통과"는 검수가 다시 확인하지 않았다.
- 화면은 하나도 보지 않았다(울타리 효과, 켠 판 카드, 전투 기록 화면 모두 "보지 않음").
- `c9dbfb7`의 첫 레벨업 시각은 손계산(모델의 답)이고, 장 코어의 실제 경험치는 확인하지 않았다.
- 디스크 사용량(작업 트리 전체, `_local/` 전체), 페이지 파일 설정, 1450이 난 호출 지점은 재지 못했다.
- `run_spells.json`이 QA 빌드의 pck에 실제로 들어가는지는 빌드를 돌리지 않아 보지 않았다(목록에 오른 것만 봄).
