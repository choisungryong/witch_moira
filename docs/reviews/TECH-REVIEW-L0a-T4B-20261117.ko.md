# 기술 검수 — T3-L0a 번역 틀, T4-B 내보내기와 빌드 스크립트

2026-11-17, 기술 책임자(tech-lead). 검수만 했다(코드·데이터 수정 없음, 커밋 없음). 창이 뜨는 Godot는 띄우지 않았다. 사용자 폴더(`%APPDATA%\WitchMoira`)는 열어 보지 않았다.

검수 대상은 저장소 작업 트리(main, 커밋 전)다. 구현자 작업 폴더 `.claude/worktrees/agent-a82c9710c559896d6`의 같은 파일 12개와 바이트가 같음을 `cmp`로 확인했다.

## 판정

| 작업 | 판정 | 요지 |
|---|---|---|
| T3-L0a 번역 틀 | **조건부 통과** | 지시서의 검사와 회귀는 통과. 다만 L1·L2가 `Loc.t`를 처음 쓰기 전에 고칠 것 2건(아래 A1, A2), L4 전에 고칠 것 1건(A3) |
| T4-B 내보내기·빌드 | **통과**(권고 있음) | 판매본이 검증 인수를 무시함을 직접 실행으로 확인. 같은 입력에서 판매본 sha256이 구현자 결과와 같다(재현됨). 되돌림은 예외·Ctrl+C에는 안전하고 강제 종료에는 안전하지 않다(B1, 권고) |

---

## 1. T3-L0a

### 1.1 지시서 대비

| 요구 | 결과 |
|---|---|
| `t`, `tn`, `num`, `dec`, `pct`, 조사(ko만), `set_locale`, `locale`, `font(role)`, 신호 `locale_changed` | 모두 있다. 신호는 정적 모음이라 `Loc.bus().locale_changed`로 둠 — 받아들인다(자동 로드를 쓰지 않아 `project.godot` 등록이 없고, 헤드리스 검사에서 장면 트리 없이 쓸 수 있다) |
| `ko.po`, `en.po`, `locales.json`, `README.ko.md` | 있다. UTF-8, LF. `ko.po`의 `Plural-Forms: nplurals=1` |
| `project.godot` `[internationalization]` | `translations` 두 개, `fallback="en"`. 다른 줄 변화 없음(`git diff`) |
| 건드리지 않을 파일 | `chapter_hud.gd`, `skill_tree_panel.gd`, 코어 — 변화 없음. `chapter_one.gd`의 변화는 T4-B의 것이다 |
| `test_loc.gd`(마커 `CHAPTER1_LOC_RESULT`) | 119건 통과 |
| 코어가 `Loc`을 부르지 않음 | `chapter1/core/`에서 `loc.gd`, `Loc`, `TranslationServer`, `tr(`, `res://chapter1/view|app|presentation` 검색 0건 |

### 1.2 구현자가 지시서와 다르게 정한 것에 대한 판단

| 결정 | 판단 |
|---|---|
| 자동 로드 대신 `extends RefCounted` 정적 함수 + `preload` | 받아들인다. 코어가 자동 로드 이름으로 우연히 닿을 길이 없어지는 장점도 있다 |
| 지원하지 않는 언어 → `en` | 지시서 2.8과 같다. 다만 `zh`, `zh_HK`가 모두 `en`이 된다(A5, L5에서) |
| `{name|을}`은 ko에서만 풀리고, 다른 언어에서는 값만 남김 | 받아들인다. 화면에 중괄호가 그대로 나가지 않고, `lint`가 잡는다 |
| `font()`가 지금의 SystemFont | HUD의 본문(`Malgun Gothic, 맑은 고딕, sans-serif`)·제목(`Batang, 바탕, Georgia`)과 같은 이름 목록이다(`chapter_hud.gd:51-52, 141`). 굵게(`skill_tree_panel.gd:101-103`, weight 700)는 역할이 없다 — L3에서 더한다 |

### 1.3 고칠 것

**A1. [L1 시작 전] `Loc`의 언어와 엔진의 언어가 처음에 어긋난다** — `chapter1/view/loc.gd:38`, `:125-129`

`_locale`은 `"ko"`로 시작하지만 `TranslationServer`에는 아무도 알려 주지 않는다. 엔진은 OS 언어로 시작한다(탐침 출력: `ts_locale_at_start = "ko_KR"`, `loc_locale_at_start = "ko"`). 엔진 언어를 `en_US`로 두고 `Loc`을 처음 쓰면 `{"loc_locale":"ko","plain":"Example text","kills":"3 kills"}` — `Loc`은 한국어라고 하면서 영어를 낸다. 개발 컴퓨터가 한국어라 지금은 드러나지 않지만, 영어 OS(스팀 덱 포함)에서는 `Loc.init()`이 불리기 전까지 `Loc.locale()`은 `ko`라고 하면서 `Loc.t()`는 영어(또는 en이 비면 키)를 낸다. 조사 처리도 `_locale`을 보고 켜지므로 언어와 어긋날 수 있다. L5(첫 실행 순서와 `Loc.init`)는 L2보다 늦게 올 수 있으므로 틀 쪽에서 막아야 한다.

고칠 방향: `loc.gd`에 "엔진 언어를 아직 맞추지 않았으면 `_locale`로 맞춘다"는 한 번짜리 처리를 두고 `t`·`tn`·`locale`·`_resolve_josa`가 먼저 부르게 한다. L5 전까지 화면은 OS와 무관하게 한국어. 검사: `test_loc.gd` 맨 앞에서 `TranslationServer.set_locale("en")`으로 OS가 영어인 상황을 흉내 낸 뒤 `Loc.t("ui.example.plain") == "예시 글"`, `Loc.locale() == "ko"`.

**A2. [L1 시작 전] 조사 처리가 값을 넣은 뒤 한 번 더 `format`한다** — `loc.gd:142-147`, `:222-231`

`_resolve_josa`가 `{name|을}`을 값+조사로 바꾼 뒤 `text.format(args)`가 다시 돈다. 그래서 (1) 값 안에 `{rank}` 같은 글이 있으면 두 번째 치환에 걸린다(탐침: 이름 `"{rank}"` → `"3로 시작 (랭크 3)"`, 조사는 바뀌기 전 글자로 골랐다). (2) 인자가 빠지면 조용히 `"를 처치하세요"`가 된다. 데이터 이름에 중괄호가 들어갈 일은 드물지만, 조사 판단이 실제로 보이는 글과 다른 글을 보고 내려질 수 있는 구조다.

고칠 방향: 한 번의 정규식 순회로 `{이름}`과 `{이름|조사}`를 함께 바꾼다(값은 한 번만 넣는다). 빠진 인자는 자리 표시자를 그대로 두고 `push_warning`(디버그 빌드만). 검사 두 줄 추가.

**A3. [L4 시작 전] 가짜 언어를 켜면 자리 표시자가 깨진다** — `loc.gd:125-129`

`TranslationServer.pseudolocalization_enabled = true`에서 `Loc.t("ui.example.greeting", {"name": "Moira"})` → `"[Ŵéłćôm̀é, {ήám̀é}]"`. 엔진이 번역 글에 악센트를 붙이면서 `{name}`까지 바꿔 `format`이 못 찾는다. 빠진 키도 가짜 언어로 바뀌어 돌아온다(`"[üí.éx́ám̀ṕłé.ήôḱéý]"`) — 이것은 L4가 "Loc을 거치지 않은 글"을 세는 데는 문제없지만, `t()`의 `text == key` 판정은 가짜 언어에서는 맞지 않는다.

고칠 방향(L4 지시서에 넣는다): 엔진의 가짜 언어 설정은 끈 채로 두고 `Loc`에 가짜 언어 스위치를 둔다. `Loc.t`가 번역 → 채우기를 마친 뒤 `TranslationServer.pseudolocalize()`를 부른다(4.5.1에 이 함수가 있는지, 자리 표시자를 건너뛰는 설정이 `{}`를 아는지는 구현자가 확인).

### 1.4 빈틈(지금 고치지 않아도 된다, 해당 지시서에 넣는다)

| # | 내용 | 근거 | 넣을 곳 |
|---|---|---|---|
| A4 | 받침 판단이 기호를 건너뛴다. `13%` → `13%을`(읽기는 "퍼센트를"). 라틴 끝 글자는 L·M·N·R만 받침으로 보아 `Ring를`, `Book가`가 나온다 | `loc.gd:189-203`, 탐침 출력 | `README.ko.md`의 1순위 규칙("자리 표시자 뒤에 조사를 두지 않는다")을 L2 검수 항목으로. `{x|을}`은 한글 이름에만 쓴다고 README에 한 줄. `%`·단위로 끝나는 값에 조사 표기를 쓰면 `lint`가 경고하게 하는 것은 L6 |
| A5 | OS 언어를 `get_locale_language()`로만 본다. 중국어 OS는 `zh`가 되어 `zh_CN`/`zh_TW`로 가지 못하고 `en`이 된다(탐침: `set_locale("zh")`, `"zh_HK"`, `"zh_Hant_TW"` 모두 `en`) | `loc.gd:67-86`, `:105` | L5. `OS.get_locale()` 전체를 보고 `zh`·`zh_Hans`→`zh_CN`, `zh_Hant`·`zh_HK`·`zh_MO`→`zh_TW` 대응표 |
| A6 | `in_progress` 언어가 `OS.is_debug_build()`에서만 보인다. QA 빌드(릴리스 템플릿 + `qa`)에서는 안 보인다 | `loc.gd:62` | L5. `or OS.has_feature("qa")` |
| A7 | 설정 파일 기본 경로가 `user://settings.cfg`다. 지금은 부르는 곳이 없어 문제없지만, L5가 `Loc.init()`을 앱 시작에 넣으면 `--chapter1-profile-off` 실행(캡처·측정)도 사용자 폴더의 설정을 읽고 메뉴 선택 시 쓴다 | `loc.gd:12`, `:39`, `:96-120` | L5 통과 기준에 "`--chapter1-profile-off`이면 `Loc.configure`로 `_local/` 경로를 주거나 저장을 끈다"를 넣는다 |
| A8 | `tn`에 음수를 주면 엔진이 `ERROR: N passed into translation to get a plural message should not be negative`를 찍고 키를 돌려준다 | `loc.gd:132-140`, 탐침 | L2 전에 `absi(n)`으로 고르게 하는 한 줄(작다. A1·A2와 같이 고쳐도 된다) |
| A9 | `test_loc.gd`의 자리 표시자 비교가 복수형의 첫 형태만 본다. en의 `msgstr[1]`에서 `{n}`이 빠져도 통과한다 | `test_loc.gd:123` | A1·A2와 같이(검사만) |
| A10 | `test_loc.gd`가 en의 모든 `msgstr`이 비어 있지 않기를 요구한다. 지시서 L0a는 "en은 비워 둠 가능"이었고 L1은 "`ko.po`에 원문을 넣어"만 적었다. 이대로면 L1·L2가 키를 넣을 때마다 영어 초벌을 함께 써야 검사가 통과한다. 탐침으로 보면 엔진은 빈 `msgstr`을 번역 없음으로 다루고 대체 언어(en)로 넘어가는데, en 자체가 비면 키가 화면에 보인다 | `test_loc.gd:125`, 탐침(`fr_empty_msgstr_gives = "Example text"`) | 디렉터 결정(2.2절). 내 권고는 "L1·L2가 en 초벌을 함께 넣는다" |
| A11 | 글꼴 캐시가 언어가 바뀌어도 그대로다 | `loc.gd:263-272` | L3에서 `locale_changed` 때 캐시를 비운다. 굵게 역할도 L3 |
| A12 | 코어가 `Loc`을 부르지 못하게 막는 검사가 없다(지금은 0건이지만 규칙으로만 지킨다) | 검색 결과 | L0b의 `i18n_scan.py`에 "`chapter1/core/`에 `res://chapter1/view`, `Loc.`, `TranslationServer`, `tr(` 0건" 한 줄. L0b가 이미 진행 중이므로 L0b 검수 때 요구하거나 L6에 넣는다 |

정적 상태 누수: `run_all.py`는 검사마다 Godot 프로세스를 새로 띄우므로 검사 사이로는 새지 않는다. 한 프로세스 안에서는 `_settings_path`, `_locale`, 신호 연결, 그리고 엔진 전역인 `TranslationServer`의 언어가 남는다. `test_loc.gd`는 시작할 때 격리 설정 파일을 지우고(`:22`) 끝에 `ko`로 돌려 둔다(`:166`). 지금 한 프로세스에서 여러 검사를 도는 도구가 없으므로 문제 삼지 않는다. 그런 도구가 생기면 `Loc`에 검사용 초기화 함수를 둔다.

설정 경로 격리: `test_loc.gd`는 `res://_local/test-loc/settings.cfg`만 쓴다(`:4`, `:23`, `:153`). 내가 돈 실행에서 격리 `APPDATA` 아래에 `settings.cfg`가 생기지 않았다(로그만 생김).

### 1.5 L1~L7을 막는가

| 지시서 | 막는 것 |
|---|---|
| L1(코어 글 빼기, 화면 최소 수정) | A1, A2를 먼저. A10 결정 |
| L2(기존 화면 옮기기) | A1, A2, A8. HUD 뿌리의 `auto_translate_mode` 끄기는 L2 몫이다 — 이번에 `project.godot`에 번역이 등록되어 자동 번역이 실제로 켜졌다. 지금 화면 글 중 키와 같은 글이 없어 영향은 없다 |
| L3(글꼴) | 없음. `font(role)` 한 곳이 진입점이라 바꾸기 쉽다. A11 |
| L4(가짜 언어) | A3 |
| L5(언어 설정) | A5, A6, A7. `choose_locale`·`resolve_initial`·`STEAM_LANGUAGES`가 이미 있어 화면과 저장 연결만 남는다 |
| L6(검사 도구) | 없음. `Loc.lint`, `Loc.placeholders`를 Python으로 옮겨 쓰면 된다 |
| L7(영어) | 없음 |

---

## 2. T4-B

### 2.1 지시서 대비

| 요구 | 결과 |
|---|---|
| 세 프리셋, 컴퓨터 경로 없음 | `export_presets.cfg`의 `custom_template/*`가 모두 `""`. 경로는 `build.py`가 빌드 중에만 써 넣는다 |
| `qa` 기능 태그 | `Windows QA`(`:53`)와 `Windows Debug`(`:98`)에만 있다. `Windows Store`는 `custom_features=""`(`:8`) |
| 판매본 검증 인수 무시, F1 | `chapter_one.gd:27`의 `qa_allowed`, `:59-60`의 `_user_args()`. 인수를 읽는 세 곳(`:66`, `:88`, `:358`)이 모두 이것을 거친다. F1은 `:186-187` |
| `build.json`, pck 목록 | 크기, sha256, 커밋, 작업 트리 변경 여부, 템플릿 sha256과 기록 일치 여부, pck 파일 수, 금지 파일, 내보내기 오류 줄 |
| 사용자 폴더 | Godot 자식 프로세스(가져오기·내보내기)의 `APPDATA`를 `_local/build/<stamp>/appdata_godot/`로 돌린다(`build.py:34-41`). 그 폴더에 `Godot/`(편집기 설정)과 빈 `WitchMoira/`가 생긴 것을 확인 — 격리하지 않았다면 실제 사용자 폴더에 만들어졌을 것들이다 |

### 2.2 판매본에서 검증 인수를 읽는 다른 길

저장소 전체(`*.gd`, `*.tscn`, `*.tres`, `*.cfg`, `*.godot`, 옛 층과 `combat/` 포함)에서 `get_cmdline_user_args`, `get_cmdline_args`, `chapter1-`를 찾았다.

- 실행에 들어가는 파일 중 인수를 읽는 곳은 `chapter1/app/chapter_one.gd`(모두 `_user_args()` 경유)와 `chapter1/presentation/frame_probe.gd:38,56`뿐이다. 후자는 `configure()` 안에서 기록용으로만 읽고, `configure()`는 `chapter_one.gd:110-111`에서 `--chapter1-frame-probe-dir=`가 있을 때만 불린다 — 판매본에서는 닿지 않는다.
- 나머지(`golden_core.gd`, `hud_dump.gd`, `measure_combat.gd` 등 11개)는 `chapter1/tests/`에 있고 pck에 들어가지 않는다(pck 목록에 `tests` 0건).
- 옛 층(`cloister_*.gd`, `chapter_world_quality*.gd`)에는 인수 읽기가 없다. `hud.debug`를 켜는 곳도 F1 하나다(`cloister_hud.gd:108`, `chapter_hud.gd:113`은 끄기만).
- 엔진 자체의 인수(`--script`, `--write-movie` 등)와 실행 파일 옆의 `override.cfg`는 이 지시서 범위 밖이다. 플레이어가 자기 컴퓨터에서 쓰는 것이라 위험으로 보지 않는다(참고로만 적는다).
- 덧붙임: `--chapter1-no-juice`도 판매본에서 꺼진다. 지시서 2.4절대로다. 접근성 설정이 생기면 그쪽으로 옮긴다.

### 2.3 제외 필터

- `chapter1/tests/*`: 실행 코드가 `res://chapter1/tests/`를 참조하는 곳이 없다(검색 0건, 테스트 파일 자신 제외). pck에서 `tests` 0건.
- 실행에 필요한 것이 빠지지 않았다: `chapter1/data/*.json` 7개, `chapter1/i18n/{ko,en}.po`, `locales.json`, `loc.gdc`, `chapter_items.gdc`, `combat_run.gdc`, 옛 층 `cloister_*.gdc`, `frame_probe.gdc`가 있다. 헤드리스로 QA 빌드를 띄워 판이 시작되고(`"mode":"playing"`) 스크립트 오류 0.
- 권고(B3): `chapter1/art/quality03/`의 제작 기록 JSON(`ASSET-LEDGER-v0*.json`, `GENERATION-PROMPTS.json`, `*-INSPECTION.json`, `GENERATED-*.json`, `ART-METADATA-RECOVERY.json`, `AUDIO-LEDGER.json`)이 pck에 들어간다. 실행 코드는 읽지 않는다(`AUDIO-LEDGER.json`은 경로 문자열을 로그에 찍을 뿐 `combat_audio.gd:38`). 판매본에 원화 생성 프롬프트를 실을 이유가 없다. 제외 목록에 더하는 것을 권한다(급하지 않음).
- 참고: `.txt` 같은 자원이 아닌 파일은 `all_resources`에서 빠진다. 소리 라이선스 원문(`LICENSE-Kenney-*.txt`)도 pck에 없다. 고지 화면(3.2의 10번)을 만들 때 배포 폴더에 따로 넣는다.

### 2.4 되돌림의 안전

`build.py:96-119`. 원본 바이트를 메모리에 두고 `try/finally`에서 되써 넣은 뒤 다시 읽어 비교한다.

| 상황 | 결과 | 근거 |
|---|---|---|
| 정상 종료, 내보내기 실패(종료 코드≠0) | 되돌림 | 내가 돈 빌드 2회 뒤 `cmp`로 원본과 같음 |
| Python 예외, Ctrl+C(`KeyboardInterrupt`) | 되돌림 | 자식 실행 자리에서 `KeyboardInterrupt`를 일으키는 탐침: 실행 중에는 경로가 들어가 있었고(`patched_during_child True`), 끝난 뒤 원본과 같음(`restored_identical True`) |
| 강제 종료(작업 관리자, 창 닫기, 전원) | **되돌리지 못한다** | `finally`가 돌지 않는다. 다음 실행은 `custom_template/release=""` 줄이 없다며 `BUILD_FAIL`로 멈추므로 조용히 넘어가지는 않는다. 다만 저장소 파일에 컴퓨터 경로가 남은 채로 있다 |
| 되써 넣기 자체가 실패(파일 잠김) | 예외가 그대로 올라와 빌드 실패. 파일은 경로가 든 채 남는다 | 코드 읽기 |

**B1(권고, T4-Q 때 함께)**: 덮어쓰기 전에 원본을 `_local/build/<stamp>/export_presets.cfg.orig`로 복사하고, 시작할 때 저장소 파일에 템플릿 경로가 들어 있으면 가장 최근 `.orig`와 비교해 되돌리고 알린다. `export_presets.cfg`가 아직 git에 없으므로 `git checkout`으로 되살릴 수도 없다.

**B2(운용 규칙)**: `build.py`는 작업 트리의 파일을 잠깐 바꾼다. 다른 에이전트가 같은 트리에서 일하거나 사용자가 편집기를 열어 둔 상태에서 돌리지 않는다. 별도 작업 폴더에서 돌린다.

### 2.5 그 밖

- `build.py:204`의 `godot --version`만 격리 환경을 받지 않는다. 판 번호만 찍고 끝나 사용자 폴더를 만들지 않는 것으로 보이나 확인하지 않았다. `env=env`를 주는 한 줄을 권한다.
- `LOCALAPPDATA`는 돌리지 않는다. 편집기 캐시가 그쪽에 갈 수 있으나 게임 저장 폴더는 아니다.
- `application/modify_resources=false`(`export_presets.cfg:31,76,121`): 실행 파일의 아이콘·판 정보·제품 이름이 Godot 기본값으로 남는다. 아이콘(`chapter1/art/brand/icon.ico`)이 들어올 때 `true`로 바꾸고, 4.5.1에서 외부 도구(rcedit) 없이 되는지 확인한다(확인 필요). `build.py`가 아이콘이 없다고 경고하는 것은 확인했다.
- 판매본 sha256이 구현자의 것(`31c77f4a…159e`)과 내 빌드가 같다. 같은 트리, 같은 템플릿에서 결과가 재현된다.

---

## 3. 구현자가 올린 발견에 대한 판단

### 3.1 엔진이 사용자 폴더에 캐시와 로그를 쓴다

판단: **사실이고, 보고보다 넓다.** 창 실행의 셰이더·vulkan 캐시뿐 아니라 **헤드리스 검사도 `logs/godot.log`를 사용자 폴더에 쓴다.** `APPDATA`를 `_local/` 아래로 돌려 `test_loc.gd`와 탐침을 돈 결과 격리 폴더에 `WitchMoira/logs/godot.log`와 날짜 붙은 기록본이 생겼다. 곧 지금의 `run_all.py`, 골든, `measure_combat.gd`, `hud_dump.gd`는 돌 때마다 `%APPDATA%\WitchMoira\logs\`에 쓰고 있다고 본다(실제 사용자 폴더는 열어 보지 않았다). 내보낸 판매본·QA 빌드도 헤드리스로 돌리자 격리 폴더에 `logs/godot.log`를 남겼다. 저장 파일은 건드리지 않지만 "검사가 사용자 폴더를 읽거나 쓰지 않는다"는 원칙과 어긋난다.

길 비교:

| 길 | 장점 | 단점 |
|---|---|---|
| (가) 실행 도구가 자식 Godot의 `APPDATA`를 `_local/appdata/<도구>/`로 돌린다 | 엔진이 쓰는 모든 것(로그, 셰이더·파이프라인 캐시, `user://` 전체)이 한 번에 격리된다. 프로젝트 설정을 바꾸지 않는다. `build.py`에서 이미 동작 확인 | 도구를 거치지 않고 `godot`를 직접 부르는 명령(CLAUDE.md의 골든·측정·캡처 줄)은 따로 감싸야 한다 |
| (나) 프로젝트 설정으로 끈다(`debug/file_logging/enable_file_logging`, 셰이더 캐시) | 명령을 바꾸지 않는다 | 플레이어의 로그·캐시도 함께 꺼지거나 기능 태그 덮어쓰기를 정밀하게 맞춰야 한다. 셰이더 캐시를 끄면 측정이 플레이어 조건과 달라진다. 권하지 않는다 |
| (다) 사용자 폴더 이름을 검사 때만 바꾼다 | — | 실행 인수로 `user://` 위치를 바꾸는 엔진 기능은 없는 것으로 안다(확인 필요). `override.cfg`를 쓰면 저장소 파일을 바꿔야 한다 |

권고: **(가)**. 지시서 하나로 묶는다(새 번호 **T1-ENV**, 담당 `qa-perf`, 파일 범위 `tools/dev/` — T4-Q와 같은 담당이라 T4-Q 앞이나 함께).
- 공용 함수 `tools/dev/isolated_env.py`(`isolated_env(name) -> dict`, `_local/appdata/<name>/`, 폴더는 지우지 않고 다시 써서 셰이더 캐시가 데워진 상태로 측정이 되게 한다).
- `run_all.py`는 모든 Godot 자식에 적용. `build.py`는 이 함수로 바꾼다.
- `run_dev.py`는 **`--chapter1-profile-off`가 있을 때만** 격리한다. 그 인수 없이 띄우는 것은 사용자가 직접 하는 플레이이고 저장이 사용자 폴더에 가야 한다.
- 직접 부르던 명령(골든, `measure_combat`, `hud_dump`, `sim_loot`, `report_run_loot`)을 감싸는 `tools/dev/godot.py -- <godot 인수>`를 두고, 디렉터가 CLAUDE.md의 명령 표를 그것으로 바꾼다.
- 통과 기준: `run_all.py` 전체와 `hud_dump.gd` 한 번을 돈 뒤 `_local/appdata/...` 아래에 `WitchMoira/logs`(창 실행이면 `shader_cache`)가 생긴 것을 보이고, 실행 전후 `%APPDATA%\WitchMoira`의 파일 목록·수정 시각이 같음을 보인다(이 확인은 디렉터 허락 아래 목록만 읽는다. 내용은 열지 않는다).

### 3.2 디버그 내보내기의 `MALGUNBD.TTF` 오류

판단: **게임 실행 파일의 문제로 보지 않는다. 다만 원인은 같은 뿌리(시스템 글꼴 의존)이고 해결은 T3-L3이다.**

- 내가 같은 작업 폴더에서 디버그 프리셋을 다시 내보냈을 때 오류가 나오지 않았다(`review-techlead/debug/export.log`에 `MALGUN` 0건). 구현자의 첫 디버그 내보내기(`t4b/debug/export.log:298`)에만 있다. 재현되지 않으므로 원인을 단정할 수 없다.
- 내보내기는 게임 스크립트를 실행하지 않는다. 프로젝트 자원(`.tscn`, `.tres`)에 `SystemFont`가 없다(검색 결과 `SystemFont`는 `.gd` 안에만). 그래서 내보내는 편집기 프로세스 쪽(편집기 화면 글꼴, 격리 `APPDATA`에 새로 만든 편집기 설정)의 일로 추정한다. 내보내기 종료 코드는 0이었다.
- 실제 위험은 실행 중이다: 게임이 `SystemFont`로 맑은 고딕·바탕을 이름으로 찾는다(`chapter_hud.gd:51,141,1355`, `skill_tree_panel.gd:99-105`, `chapter_effects.gd:861`, 옛 층 `cloister_hud.gd:46,136`, 이번 `loc.gd:266-270`). 맑은 고딕이 없는 환경(스팀 덱의 Proton, 리눅스, 한국어 글꼴을 뺀 Windows 설치 — 마지막은 확인 필요)에서는 한글이 다른 글꼴로 바뀌거나 빈칸으로 나온다.

다음 지시: (1) T3-L3 통과 기준에 "내보내기 로그와 실행 로그에 `C:/WINDOWS/FONTS` 경로 0건"을 더한다. (2) T4-Q의 `check_build.py`는 내보내기 로그의 `ERROR` 줄을 `build.json`에 남기되(이미 `export_error_lines`로 남긴다), 알려진 줄 목록(이 글꼴 줄, 사유 "L3 전, 편집기 쪽 추정")을 두고 새 줄만 실패로 본다. (3) 데모의 조건(T4 5절)에 L3이 이미 있으므로 순서는 바꾸지 않는다.

### 3.3 에이전트 작업 폴더가 옛 커밋에서 만들어진다

판단: **원격 추적 브랜치(`origin/main`)를 기준으로 만들어진다.** 근거:

- `git branch -vv`: `main fb20966 [origin/main: ahead 4]`, `origin/main`은 `c75d3d3`.
- `git reflog show --date=iso refs/remotes/origin/main`: 마지막 갱신은 `2026-11-16 22:29:08 update by push`(`c75d3d3`).
- 작업 폴더 브랜치의 reflog: `worktree-agent-ad8862a9fadf0e81b@{2026-11-17 12:39:20}: branch: Created from c75d3d3…`, `worktree-agent-a727bc3c0fa82a77b@{2026-11-17 12:09:38}: branch: Created from c75d3d3…`. 이 시각에 로컬 `main`은 이미 `fb20966`(11:23 커밋)이었다. 여섯 작업 폴더 모두 `c75d3d3`에서 만들어졌고, 그중 셋은 나중에 `merge … Fast-forward`로 `5903e38`·`fb20966`까지 올라갔다.
- 곧 "로컬 HEAD"가 아니라 "마지막으로 푸시한 원격 기본 브랜치"에서 갈라진다. 푸시하지 않은 로컬 커밋 넷이 작업 폴더에 없는 이유다.

영향(지금 확인된 것): `agent-a727bc3c0fa82a77b`(T3-L0b로 보이는 작업: `golden_core.gd`, `chapter_core.gd`, `i18n_scan.py`, `core_runtime_textless.json`)가 `c75d3d3` 위에 있다. 이 위에서 만든 textless 골든과 한글 개수 기준선은 지금 main의 코어(`1ee60cf`의 수치 시트 등)와 다를 수 있다. **L0b 검수 때 main에 옮긴 뒤 다시 돌린 결과로 판정해야 한다.**

고치는 길(실행은 디렉터·사용자 몫): (가) 사용자가 `main`을 푸시한다(커밋·푸시는 사용자 요청 때만). (나) 지시서 공통 규칙에 "작업 시작 때 `git merge --ff-only main` 뒤 `git log -1 --oneline`을 보고서 첫 줄에 적는다"를 넣는다. (나)는 당장 할 수 있다.

---

## 4. 직접 실행한 명령과 출력

모든 Godot 실행은 `APPDATA`를 `_local/tech-lead-probe/l0a-t4b/` 아래로 돌려서 했다(첫 회귀 1회는 예외, 아래 4.6).

### 4.1 번역 검사
```
godot --headless --path . --script res://chapter1/tests/test_loc.gd
CHAPTER1_LOC_RESULT {"checks":119,"failures":[]}   exit=0
```

### 4.2 `Loc` 탐침(스크래치 경로의 스크립트, 저장소에 두지 않음)
```
LOC_PROBE {"defeat_before_init":"모이라를 처치하세요","empty_po_loaded":true,
 "fr_empty_msgstr_gives":"Example text","fr_greeting":"Salut {name}",
 "inject":"3로 시작 (랭크 3)","josa_10":"10으로","josa_13pct":"13%을","josa_book":"Book가",
 "josa_int_arg":"3을 처치하세요","josa_missing_arg":"를 처치하세요","josa_ring":"Ring를",
 "loc_locale_at_start":"ko","os_locale":"ko_KR","os_locale_language":"ko",
 "pseudo_greeting":"[Ŵéłćôm̀é, {ήám̀é}]","pseudo_missing":"[üí.éx́ám̀ṕłé.ήôḱéý]",
 "set_pt_BR":"en","set_zh":"en","set_zh_HK":"en","set_zh_Hant_TW":"en",
 "t_plain_before_init":"예시 글","tn_neg1":"ui.example.kills","ts_locale_at_start":"ko_KR"}
ERROR: N passed into translation to get a plural message should not be negative. (2회)
```
격리 `APPDATA`에 생긴 것: `WitchMoira/logs/godot.log`, `WitchMoira/logs/godot2026-11-17T12.43.47.log`.

### 4.3 게임 헤드리스 5초(L0a 통과 기준 3의 대체 — 창을 띄우지 않으려고 헤드리스로)
```
godot --headless --path . -- --chapter1-start --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-quit-after=5
exit=0, SCRIPT ERROR 0건, 그 밖의 ERROR 0건, FULL_CHAPTER_READY, "mode":"playing"
```
`loc.gd`는 아직 게임 코드가 부르지 않으므로 이 실행은 "번역 등록이 기존 실행을 깨지 않는다"만 보인다.

### 4.4 빌드(구현자 작업 폴더에서, `--skip-import`)
```
python tools/dev/build.py --preset store --stamp review-techlead --skip-import
BUILD_TEMPLATE …windows_release_x86_64.exe sha256=78ccc576…4065 verified=True
BUILD_WARN chapter1/art/brand/icon.ico is missing: the executable keeps the Godot default icon
BUILD_EXPORT exit=0
BUILD_RESULT …\review-techlead\store\WitchMoira.exe bytes=142814016 sha256=31c77f4a680dac80a502b10762ba31c97ca33ee2ae56c469b727cd2de1f3159e pck_files=279 forbidden=0
(이후 cmp: export_presets.cfg가 main의 것과 같음)

python tools/dev/build.py --preset debug --stamp review-techlead --skip-import
BUILD_TEMPLATE …windows_debug_x86_64.exe sha256=30a3e543…3a16a43 verified=True
BUILD_EXPORT exit=0
BUILD_RESULT …\debug\WitchMoira.exe bytes=140632928 sha256=bd69c8aa…f939 pck_files=279 forbidden=0
export.log의 MALGUN 0건. export_presets.cfg 원본과 같음.
```
QA 프리셋은 다시 만들지 않았다. 구현자의 `final/qa`(`59a62a3d…b7dc`)를 썼다.

### 4.5 판매본·QA 빌드에 검증 인수(헤드리스)
```
store: timeout 25 WitchMoira.exe --headless -- --chapter1-start --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-quit-after=8
  → exit 124(8초에 끝나지 않아 25초에 강제 종료), "pilot":false, FULL_CHAPTER_RUNTIME_RESULT 없음, SCRIPT ERROR 0
    (강제 종료로 생긴 "BUG: Unreferenced static string" 줄만 있음)
qa:    같은 인수 → exit 0(8초에 스스로 종료), "pilot":true, "mode":"playing", FULL_CHAPTER_RUNTIME_RESULT, 오류 0
```
판매본은 프로필을 끌 수 없으므로 격리 `APPDATA`에서 돌렸다. 메뉴에 머문 동안 저장 파일은 생기지 않았고 `logs/godot.log`만 생겼다.

### 4.6 되돌림 탐침
```
python -I restore_probe.py   (build.export()의 자식 실행 자리에서 KeyboardInterrupt)
KeyboardInterrupt propagated / patched_during_child True / restored_identical True
```

### 4.7 회귀 전체
```
APPDATA=_local/tech-lead-probe/l0a-t4b/appdata-runall python tools/dev/run_all.py --json _local/tech-lead-probe/l0a-t4b/run_all.json
growth   pass       0.6s  188 checks, 0 failures
tree     pass       0.6s  115 checks, 0 failures
combat   pass       0.6s  75 checks, 0 failures
chapter  pass      15.2s  474 checks, 0 failures
profile  pass       6.0s  115 checks, 0 failures
loot     pass       4.9s  36 checks, 0 failures
loc      pass       0.8s  119 checks, 0 failures
app-guard pass       3.1s  5 checks, 0 failures
golden   pass     280.3s  4 cases, 0 mismatches
loot-sim pass      66.7s  3000 runs, 0 mismatches · per run rare 4.66, jewelry 1.43, legendary 0.37, unique 0.24
manager  pass       7.9s  31 tests
RUN_ALL {"passed": 11, "failed": [], "skipped": []}
```
격리 폴더에 `WitchMoira/logs/`가 생겼다 — 헤드리스 회귀도 사용자 폴더에 로그를 쓴다는 3.1절의 근거다. 골든 4건 불일치 0이므로 두 작업 모두 코어를 바꾸지 않았다.

처음에 `APPDATA`를 돌리지 않고 `run_all.py`를 시작했다가, 4.2에서 헤드리스 실행도 로그를 쓴다는 것을 알고 골든 도중에 멈췄다. 그때까지 돈 8개 검사(growth~app-guard, 모두 통과)는 실제 `%APPDATA%\WitchMoira\logs\`에 로그를 썼을 것이다(열어 보지 않았다). 저장 파일은 건드리지 않는다. 다시 격리해서 처음부터 돌린 결과가 위다.

### 4.8 검색
- `chapter1/core/`에서 `loc\.gd|\bLoc\b|TranslationServer|[^s]tr\(|tr_n\(|\bview/` → 0건, `res://chapter1/(view|app|presentation)` → 0건.
- 저장소 전체 `*.{gd,tscn,tres,cfg,godot}`에서 `get_cmdline_user_args|get_cmdline_args|chapter1-` → 2.2절.
- `chapter1/`에서 `SystemFont|font_names` → 3.2절의 목록.
- `chapter1/`에서 `res://chapter1/tests` 참조 → 테스트 파일 자신뿐.

## 5. 확인하지 못한 것

- 창 실행. L0a 통과 기준 3(`--chapter1-start --chapter1-quit-after=5`)과 T4-B 통과 기준 3·4는 헤드리스로 대신했다. 창 캡처는 없다.
- QA 프리셋 재빌드(구현자 결과물 사용). 가져오기(`--import`)를 포함한 빌드 전체 흐름(`--skip-import`로만 돌림).
- 강제 종료 때의 되돌림 실패는 코드로만 판단했다(실험하면 작업 폴더 파일이 바뀐 채로 남으므로 하지 않았다).
- `MALGUNBD.TTF` 오류의 원인. 재현되지 않았다.
- `godot --version`이 사용자 폴더를 만드는지, 편집기가 `LOCALAPPDATA`에 무엇을 쓰는지.
- 4.5.1의 `TranslationServer.pseudolocalize()`와 자리 표시자 건너뛰기 설정의 정확한 동작(A3).
- 영어 OS에서의 실제 동작(A1은 엔진 언어를 보고 추론했다. 영어 OS 컴퓨터로 돌린 것은 아니다).
- `application/modify_resources=true`가 4.5.1에서 외부 도구 없이 되는지.
