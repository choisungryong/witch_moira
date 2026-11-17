# 기술 검수 — D5 저장 안전 + D4-K 포기 함수

2026-11-17 · 검수: 기술 책임자(tech-lead) · 대상: 기준 커밋 5903e38 대비 작업 트리 `chapter1/` 변경 7개 파일 + `tests/fixtures/loot_compat_items.json`
명세: `docs/specs/D5-save-safety-spec.ko.md`(U-1~U-4 사용자 허락), `docs/specs/D4-run-flow-spec.ko.md` D4-K

## 판정: 조건부 통과

원본 보존은 지켜진다. 거부된 원본, 기록본, 옛 형식 파일을 쓰거나 이름을 바꾸거나 지우는 경로는 찾지 못했다. 직접 만든 조작 사례에서도 원본 바이트가 그대로였다. 골든 4건 불일치는 0이고 `--quick`도 통과했다. 장비 검증에서는 이름과 설명만 빠졌고, 능력치·접사·요구 레벨·id 검증은 그대로다.

조건은 두 가지다. 둘 다 D5-U(안내 화면)가 이 함수들을 화면에 연결하기 **전에** 고쳐야 한다.
- **C-1(M1)**: `profile_reject_info()`가 부를 때마다 기록본 전체를 다시 훑는다. 화면이 갱신할 때마다 이 함수를 부르게 되면 멈춤이 생긴다.
- **C-2(M2)**: `play_without_save()`·`start_fresh_profile()`가 지금 판이 돌고 있는지 확인하지 않는다.

## 직접 실행한 것

| 명령 | 결과 |
|---|---|
| `python tools/dev/run_all.py --quick` | 통과. growth 188, tree 115, combat 75, chapter 437, profile 110, loot 33 검사 실패 0, manager 31. golden·loot-sim은 건너뜀 |
| `godot --headless --path . --script res://chapter1/tests/golden_core.gd` | `GOLDEN_RESULT {"cases":4,"mismatches":[]}`(4분 21초). frost·ember·arc·L20-lance 모두 victory |
| 탐침 `res://_local/review-d5/probe.gd`(검수용, `_local` 안에만 씀) | 아래 "탐침 결과" 참고 |
| 묶음 파일 대조(Python, 읽기만) | 246개. 기본 장비·접사·전설·고유 id를 모두 담았다. 등급×칸 35칸 가운데 빠진 7칸(전설 head·body·feet, 고유 head·body·hands·feet)은 데이터상 나올 수 없는 조합이다(전설 칸은 charm·hands·ring·weapon, 고유 칸은 charm·ring·weapon) |
| 줄바꿈 | 고친 파일 모두 LF가 유지됐다. `--ignore-cr-at-eol`로 비교해도 diff 통계가 같다 |

### 탐침 결과
- 가리키는 파일의 `file`이 `"chapter-one-profile-v3-r1.json\n"`(끝 줄바꿈)이면 정규식은 **통과**하지만 `file_exists`가 거짓이라 본래 경로로 간다. 실제 피해는 없다(L1).
- `file`이 패턴에 맞는 **폴더** 이름이면 무시하고 본래 경로로 간다.
- 가리키는 파일이 가리킨 r-파일이 깨져 있으면 `damaged`로 거부하고, 폴더 전체 sha256이 그대로다.
- 그 상태에서 `start_fresh_after_reject(true)`를 부르면 바뀐 파일은 `active.json`(가리키는 파일, 메타데이터라 바꿔 써도 된다) 하나뿐이다. 새로 생긴 파일은 새 r-파일과 그 기록본 하나다. 거부된 r-파일과 본 파일의 바이트는 그대로다.
- 같은 객체에서 `start_fresh_after_reject`를 두 번째로 부르면 거절한다.
- `_check_text`는 C1 제어 문자(U+0085)와 방향 덮어쓰기(U+202E)를 받아들이고, CR은 거부하며, **이름 안의** 줄바꿈도 받아들인다(L2).

## 1. 원본 보존 — 쓰기·이름 바꾸기·삭제 호출 전수

`chapter1/` 전체에서 `remove`, `remove_absolute`를 부르는 곳은 0건이다. `core/`·`app/`의 저장 관련 쓰기는 아래가 전부다.

| 위치 | 호출 | 대상이 될 수 있는 경로 | 막는 장치 |
|---|---|---|---|
| `chapter_profile.gd:401` | `make_dir_recursive_absolute` | `path`의 폴더 | 폴더만 만든다 |
| `chapter_profile.gd:403-406` | `FileAccess.open(WRITE)` ×2 | `<path 바탕>.revision-<rev>-<pid>-<usec>.json`, `<path 바탕>.next-….json` | 400행: 둘 중 하나라도 있으면 쓰지 않는다 |
| `chapter_profile.gd:408` | `rename_absolute(temp, path)` | `path` = ① `PATH_V3`(읽혀서 `available`이거나 없던 파일) ② 가리키는 파일을 따라가 **읽혀서 받아들여진** r-파일 ③ `start_fresh_after_reject`가 고른 새 이름 | 385행 `available` 필수(거부 뒤에는 거짓). 393-395행: 디스크 내용이 `_loaded_text`와 다르면 쓰지 않는다 |
| `chapter_profile.gd:188-190` | `FileAccess.open(WRITE)` | `<pointer 바탕>.next-<usec>.json` | 가리키는 파일 쪽 이름이라 저장 파일과 겹치지 않는다 |
| `chapter_profile.gd:192` | `rename_absolute(temp, pointer_path)` | `user://chapter-one-profile-active.json`(QA에서는 인수로 받은 `res://_local/` 경로) | 상수이거나 QA 인수다. 저장 파일 이름 규칙과 겹치지 않는다 |

따라간 경로:
- **거부 뒤**: `configure`가 `_reject`로 끝나면(90·92·96·99·101행) `available=false`다. 이 상태에서 `_persist`, `select_item`, `salvage`, `commit_tree`, `respec`, `record_run`은 모두 385행이나 416·550·574행에서 멈춘다. `_reject`(197-201행)는 원본을 읽어 해시를 계산하고 로그를 찍을 뿐이다.
- **읽기만 해도 파일이 바뀌는 경로는 없다.** `dress`는 `_normalize_body`의 `result`(깊은 복사본, 268행) 안에서만 쓰인다. `configure`, `latest_readable_revision`, `journal_files`, `_pointed`, `profile_reject_info`는 모두 읽기 전용이다. P-1과 탐침이 폴더 sha256으로 이를 확인한다.
- **새 저장으로 시작**: v3가 거부된 경우 새 이름 `chapter-one-profile-v3-r<시각>[-n].json`을 고를 때 이미 있는 이름은 건너뛴다(167-168행). legacy가 거부된 경우에는 `PATH_V3`가 이미 있으면 거절한다(160행). `_persist` 안에서도 393행의 "있으면 `_loaded_text`(빈 문자열)와 같아야 함" 검사가 한 번 더 막는다. 이 검사의 구멍은 크기가 0바이트인 파일이 이미 있는 경우뿐이다. 그런 파일은 160·167행에서 먼저 걸러진다. 남는 위험은 확인과 쓰기 사이에 다른 프로세스가 같은 이름을 만드는 경쟁뿐이다(L9 참고).
- **기록본에 이름을 붙이는 규칙**: r-파일의 기록본(`…-r<시각>.revision-…json`)과 임시 파일(`.next-`)에는 `.`이 들어가므로 `[0-9-]+\.json$`에 맞지 않는다. 그래서 가리키는 파일이 기록본이나 임시 파일을 가리킬 수 없다.

## 2. 가리키는 파일(`_pointed`, `chapter_profile.gd:107-116`)

| 조작 | 결과 | 근거 |
|---|---|---|
| `../x.json`, `chapter-one-profile-v3-r1/../x.json` | 무시 | 문자 집합 `[0-9-]`에 `/`·`\`·`.`이 없다. P-8과 탐침 |
| 절대 경로 `C:/x.json`, `/abs.json` | 무시 | 정규식 불일치. P-8 |
| 다른 이름 규칙(`other.json`, 대문자, 전각 숫자) | 무시 | 정규식이 대소문자를 구분하고 `[0-9]`는 ASCII만 받는다. 탐침 |
| 패턴은 맞는데 없는 파일 | 무시 | 116행 `file_exists`. P-8 |
| 패턴에 맞는 폴더 | 무시 | `file_exists`가 거짓. 탐침 |
| 깨진 JSON, `file`이 문자열이 아님, 사전이 아님 | 무시 | 112행 |
| 4096자 초과 | 무시. 다만 **파일 전체를 먼저 읽는다** | 109-110행(L3) |
| 끝 줄바꿈 `"…r1.json\n"` | 정규식은 통과, `file_exists`가 거짓이라 무시 | PCRE의 `$`가 마지막 줄바꿈 앞에서도 맞는다(L1) |
| 가리킨 파일이 거부됨 | 그 파일을 대상으로 거부 흐름. 본 파일과 가리키는 파일은 그대로 | 탐침 |

따라가는 것은 한 단계뿐이고, 형제 경로는 늘 `destination`의 폴더를 기준으로 만든다(115행). 정규식과 "같은 폴더에 실제로 있다"는 확인을 합치면 충분하다.

## 3. 검증 완화의 범위(`loot.gd`)

- 뺀 것: 고유의 `name`·`description` 비교(259행), 희귀 이름 낱말 검사, 일반·마법·전설의 이름 비교, `description` 비교(285-286행). 그 밖의 것은 남았다.
- 남은 것(5903e38과 대조): 키 존재, grammar, 칸, 등급, 모양, item_level 범위, `required_level` 공식(251행), 능력치 키와 범위, 고유의 칸·`stats`·접사 없음·레벨(259행), 기본 장비의 칸과 레벨(265행), 접사 수·그룹 중복·종류 상한·적격성·범위(267-278행), 전설 id·칸·레벨(281-282행), 다시 계산한 `stats` 비교(286행). 286행은 `_compose(…, "")`를 쓰는데, 희귀 이름은 `stats`에 영향이 없으므로 같은 비교다.
- `_check_text`(291-303행): 이름은 문자열 1~160자, 설명은 문자열 0~300자, C0 제어 문자(LF 제외)와 DEL을 막는다. 한계는 L2에 적었다.
- `dress`(307-321행): 깊은 복사본의 `name`·`description`만 바꾼다. 희귀는 이름을 그대로 두고 설명만 다시 짓는다. v1 장비는 바꾸지 않는다. 부르는 곳은 `chapter_profile.gd:300` 한 곳뿐이다. 그래서 `_persist`의 `normalize` 때 새 이름으로 바뀌어 다음 정상 저장에서 파일에 쓰인다(N5에 맞다).
- 출발 장비(`chapter_core.gd:649-665`)는 모든 항목을 검증한 뒤에 넣으므로 실패해도 일부만 들어가지 않는다. 앱은 `quit(1)` 대신 알림을 띄우고 장비 없이 시작한다(`chapter_one.gd:390-396`). N7에 맞다.

## 4. 새 저장으로 시작(`start_fresh_after_reject`, 155-182행)

- 읽히는 프로필, 미리보기, `--chapter1-profile-off` 상태에서는 거절한다(156행: `available`이거나 `reject_kind`가 비어 있으면). 끝 검사와 탐침 5번에서 확인했다.
- 이름이 겹치면 `-2`, `-3`을 붙인다(P-9가 덮어쓰지 않음을 확인).
- **중간 실패**:
  - 기록본 생성 실패 → 파일이 생기지 않는다.
  - 임시 파일 실패 → 새 기록본 하나가 남는다.
  - 바꿔 끼우기 실패 → 새 기록본과 `.next-` 파일이 남는다.
  - `_persist`는 성공했는데 가리키는 파일 쓰기가 실패 → 새 r-파일과 그 기록본이 남지만, 가리키는 파일이 없으므로 쓰이지 않는다.
  - 어느 경우든 메모리 상태는 거부 상태로 돌아가고(177-180행) 다시 시도할 수 있다. 원본은 어느 경우에도 그대로다. 남는 것은 새 파일뿐이라 "기록본은 지우지 않는다"는 지금 정책과 같은 성격이다(L9).
- ③-가: 기록본은 읽기만 한다. `revision`은 기록본 값에서 이어 간다(P-6: 3 → 4).

## 5. `abandon()`(`combat_core.gd:193-199`)

- `snapshot()`의 키를 바꾸지 않았다. K-6이 확인하고, 골든 4건이 불일치 0이다.
- 메뉴 상태(`mode=="menu"`)와 끝난 판(`_terminal_mode`가 비어 있지 않음)에서는 상태를 바꾸지 않고 거짓을 돌려준다. K-3이 메뉴·패배 뒤·승리 뒤를 모두 확인한다.
- 정지 상태: `_paused`는 남지만 `_refresh_mode`가 끝난 판을 먼저 보므로 `mode`는 `defeat`다. 다음 `start()`가 `_paused`, `_inventory_open`, `_terminal_mode`, `_event_sequence`를 초기화한다(`combat_core.gd:133-139`). K-5가 600틱 해시가 같음을 확인한다.
- 결정론: 난수를 쓰지 않고, `_record()`(chapter의 history)를 부르지 않는다. 이벤트 순번만 하나 늘어나는데, 이것은 `snapshot()` 밖이다.

## 6. 검사가 실제로 그 성질을 검사하는가

- 사용자 폴더에 손대는 검사는 없다. `chapter1/tests`에서 `user://`가 나오는 곳은 `test_chapter_profile.gd:256`의 상수 비교 하나뿐이다. 프로필 검사는 모두 `configure(…, true, …)`로 `res://_local/` 아래만 쓴다. L-7의 데이터 사본은 `res://_local/d5/`에 쓴다.
- `assert()`는 새로 쓰지 않았다.
- 탄탄한 검사: P-1·P-3·P-4는 폴더 전체 sha256 사전을 `==`로 비교하므로 새 파일이 생기는 것까지 잡는다. P-6·P-9는 `same_files`로 원래 있던 파일의 바이트를 확인한다(새 파일은 생기는 것이 정상이다).
- 헐거운 곳:
  - **L5** `test_chapter_profile.gd:224-228`(P-9): 현재 초와 다음 초의 이름을 미리 차지해 두고, `-2.json`이 나오리라 예측한다. 차지한 시점과 `start_fresh` 사이에 2초 넘게 걸리면(느린 기계, 백신 검사) 예측한 이름이 없어 거짓 실패가 난다. 안전 문제는 아니고 검사가 흔들릴 수 있다는 문제다.
  - **L6** `test_loot.gd:171`(L-4 전설): 굴린 장비가 전설 대신 희귀로 떨어지면 "Unexpected legendary effect"로 거부되어, 원래 노린 이유와 다른 이유로 통과한다. `legendary.quality=="legendary"`를 먼저 확인해야 한다.
  - **L7** `test_loot.gd:218`: `FileAccess.open` 결과가 null인지 보지 않는다. 고정 경로 `res://_local/d5/`라 실행할 때마다 덮어쓴다(격리 위반은 아니다).
  - **L8** `test_chapter_profile.gd:251`: `--fixture-dir`이 `res://_local/` 아래인지 검사가 직접 확인하지 않는다. `write_text`·`mutate_file`은 `configure` 검증을 거치지 않고 바로 쓴다. 원래 있던 방식이고 `run_all.py`는 격리 경로를 넘긴다. 그래도 `begins_with("res://_local/")`가 아니면 `quit(1)` 한 줄을 넣기를 권한다.
  - K-2: 명세의 "선택(choice) 상태"를 검사하지 않는다. 정지와 인벤토리만 본다(`test_chapter_run.gd:750-756`).
  - L-1: 960개 + 고유 장비. 명세는 1,000개였지만 등급 넷 × 칸 전부를 덮으므로 받아들인다.

## 7. 명세와 다르게 한 다섯 가지

| 다른 점 | 판단 |
|---|---|
| 일반 사유 문구(장비 아닌 실패는 `"profile fields"`, `"schema 3 document"`) | 받아들인다. P-3이 요구하는 장비 위치는 정확하다. 캐릭터 표 실패도 `characters.<id>: <항목>`으로 남기면 버그 보고에 도움이 된다(다음 손질 때) |
| v3 크기 초과를 `damaged`로 | 받아들인다. 명세 3.2의 정의(파싱 실패·크기 초과)와 같다 |
| 묶음 246개 | 받아들인다. 데이터상 나올 수 있는 등급×칸, 모든 기본·접사·전설·고유 id를 덮는다. 기준 커밋 이후 `loot.json`은 바뀌지 않았다 |
| 파일 이름에 로컬 시각 | 받아들인다. 사용자가 폴더에서 알아보기 쉽다. 서머타임 때문에 같은 시각이 두 번 와도 `-n` 루프가 덮어쓰기를 막는다. 검사 쪽 시각 예측만 L5처럼 흔들릴 수 있다 |
| `dress`는 `normalize`에서만 | 받아들인다. 명세 2.2와 같고, 읽기 경로에서 파일을 쓰지 않음을 확인했다 |

## 지적 목록

| # | 파일:행 | 재현 조건 | 심각도 | 고칠 방향 |
|---|---|---|---|---|
| M1 | `chapter_one.gd:415`, `chapter_profile.gd:139-148` | 기록본이 수백~수천 개(저장할 때마다 하나씩 쌓임)이고 대부분 거부되는 프로필에서 `profile_reject_info()`를 부를 때마다 2MB짜리 JSON을 최대 N개 파싱·검증한다. D5-U가 이것을 메뉴 갱신마다 부르면 화면이 멈춘다 | 중 | `configure`가 거부했을 때 한 번만 계산해 프로필에 담아 두거나(`_latest_cache`), 앱이 한 번 받은 값을 들고 있는다. 훑는 기록본 수에 상한(예: 최근 64개)을 두는 것도 검토한다. **D5-U 연결 전 조건(C-1)** |
| M2 | `chapter_one.gd:426-440` | 판이 돌고 있거나 결과 창에 있을 때 `start_fresh_profile()`을 부르면, 저장 없이 시작한 판의 결과가 `_save_terminal`/`save_retry`로 새 프로필에 저장되려 한다(빌드 없이 시작한 판, `run_character_id` 빈 값). `play_without_save()`도 판 중에 부를 수 있다 | 중하 | 두 함수 머리에 `if run.mode!="menu":return false`를 넣는다. 화면이 메뉴에서만 띄운다는 가정을 코드로 막는다. **D5-U 연결 전 조건(C-2)** |
| L1 | `chapter_profile.gd:18, 114` | `file="chapter-one-profile-v3-r1.json\n"`이면 정규식은 맞고 `file_exists`가 막는다 | 하 | `$` 대신 `\z`를 쓰거나 `file==file.strip_edges() and file.get_file()==file`을 함께 확인한다 |
| L2 | `loot.gd:296-302` | 희귀 이름(다시 짓지 않아 남는 유일한 글)에 C1 제어 문자, U+202A-202E·U+2066-2069 방향 문자, U+2028/2029, 이름 안 줄바꿈이 들어가도 통과한다. 결과는 HUD 한 줄이 깨지는 정도의 겉모습 문제다 | 하 | 이름에서는 줄바꿈도 막고, U+0080-009F, U+2028-2029, U+202A-202E, U+2066-2069를 막는다. 설명만 LF를 허용한다 |
| L3 | `chapter_profile.gd:109-110`(그리고 원래 있던 89-90행) | 아주 큰 가리키는 파일이나 프로필이면 길이를 보기 전에 전부 메모리로 읽는다 | 하 | `FileAccess.open(...).get_length()`로 먼저 크기를 본다 |
| L4 | `chapter_profile.gd:258, 320` | 장비가 아닌 실패의 사유가 일반 문구다 | 하 | 캐릭터 표와 상위 키 실패에도 짧은 사유를 남긴다 |
| L5 | `test_chapter_profile.gd:224-228` | 차지와 `start_fresh` 사이가 2초를 넘으면 P-9가 거짓 실패한다 | 하 | 이름 짓기에 시각 주입용 시험 훅(`stamp_override`)을 두거나, 어떤 이름이든 "이미 있던 파일과 다르고 바이트가 그대로"인지만 확인한다 |
| L6 | `test_loot.gd:171-177` | 전설이 희귀로 떨어지면 다른 이유로 통과한다 | 하 | `legendary.quality=="legendary"`를 먼저 확인한다 |
| L7 | `test_loot.gd:218` | 쓰기에 실패하면 null을 호출한다 | 하 | null이면 `check(false)` |
| L8 | `test_chapter_profile.gd:251` | `--fixture-dir`을 `_local` 밖으로 주면 `write_text`가 그 경로에 쓴다 | 하 | `res://_local/`로 시작하지 않으면 `quit(1)` |
| L9 | `chapter_profile.gd:175-180` | 가리키는 파일 쓰기가 실패하면 쓰이지 않는 새 r-파일이 남고, 다시 시도하면 또 하나 생긴다. 확인과 쓰기 사이의 경쟁도 남아 있다 | 하(정보) | 받아들일 만하다. 안내 문구에 "새 파일이 남았을 수 있음"을 넣거나, 다시 시도할 때 남은 r-파일을 재사용하는 것은 다음 단계에서 본다 |
| L10 | `chapter_profile.gd:146, 172-173` | ③-가로 이어 갈 때 기록본의 `tree_revision`이 다르면 투자가 0으로 돌아가는데, `notices`를 넘기지 않아 "포인트 반환" 안내가 뜨지 않는다 | 하 | `latest_readable_revision`에서 `notices_out`을 받아 새 프로필의 `notices`로 옮긴다 |
| L11 | `test_chapter_run.gd:750-756` | K-2의 선택(choice) 상태를 검사하지 않는다 | 하 | 레벨업 대기 상태를 만들어 `abandon()`이 참이고 `mode=="defeat"`인지 본다 |

## 실행하지 못한 확인

- `python tools/dev/run_all.py` 전체(loot-sim 포함)는 돌리지 않았다. 지시대로 `--quick`과 골든만 돌렸다. `loot.gd`의 `roll_*`·`_compose`는 diff상 바뀌지 않았지만 loot-sim 결과가 그대로인지는 실행으로 확인하지 않았다.
- H-1~H-7(앱·화면, `hud_dump.gd`)은 D5-U가 끝나지 않아 볼 수 없다.
  - D5-A의 (1) "말없는 막힘을 안내 열기로"는 아직 화면에 연결되지 않았다. 지금도 `chapter_one.gd:369`은 `hud.notify`로 막는다.
  - 결과 창의 세션 문구도 결과 요약에 실리지 않는다. 570행은 `profile_off`만 넘긴다.
  - N7의 "알림 뒤 장비 없이 시작"은 코드로만 읽었다.
- Windows에서 `rename_absolute`로 이미 있는 가리키는 파일을 덮어쓰는 동작은 탐침에서 성공했다. 디스크 쓰기 실패(권한, 꽉 찬 디스크)는 흉내 내지 않았고 코드로만 따라갔다.
- `OS.shell_open`(폴더 열기)은 실행하지 않았다.
- 검수 탐침의 임시 파일이 `res://_local/review-d5/`에 남아 있다. 언제 지워도 된다.
