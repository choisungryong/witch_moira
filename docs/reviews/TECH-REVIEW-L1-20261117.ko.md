# 기술 검수 — T3-L1 코어가 글을 내지 않게

2026-11-17, 기술 책임자(tech-lead). 검수만 했다(코드·데이터 수정 없음, 커밋 없음). 창이 뜨는 Godot는 띄우지 않았다(모두 `tools/dev/godot.py --headless`). 사용자 폴더(`%APPDATA%\WitchMoira`)는 열어 보지 않았다. 내가 만든 탐침과 사본은 모두 `_local/review-l1/` 아래에 있다.

검수 대상: 저장소 작업 트리(main `16f8be8` 위의 커밋 전 변경). 코어 일곱 파일, 화면 네 파일(`app/chapter_one.gd` 포함), `tools/dev/run_all.py`·`i18n_scan.py`·`i18n_baseline.json`, `tools/manager/catalog.py`, 검사 세 개, 골든 파일, `chapter1/i18n/*.po`·README, 새 파일 `chapter1/view/hud/tree_text.gd`, `chapter1/tests/test_core_text.gd`.

## 판정

**조건부 통과.** S1로 넘어가도 된다. 막는 결함은 없다. 다만 7.2의 C1~C3은 S1 지시서에, 7.3의 C4~C6은 S2 지시서에 적어 넘겨야 하고(특히 C4는 S2에서 놓치면 효과 줄이 말없이 사라진다), 이번 작업 안에서 고칠 작은 것 두 건(R1, R2)이 있다. R1·R2는 S1 시작을 막지 않는다(같은 파일을 S1이 고치지 않는 범위).

| 질문 | 결론 |
|---|---|
| 1. 골든 갱신이 정당한가 | **정당하다.** 갱신 전후 골든에서 글 아닌 값(mode·tick·kills·hp_raw·level·체크포인트 수)은 하나도 바뀌지 않았다. 더 강한 증거로, 지금 코어의 스냅숏에서 `title_key`를 그 키의 한국어 글을 담은 `title`로 되돌려 해시하면 **갱신 전(HEAD) 골든의 체크포인트 140개와 최종 해시 4개가 모두 같다.** 달라진 경로는 `enemies.#.title_key` 하나뿐이다 |
| 2. `run_all.py`의 거짓 통과 | 고침은 옳다(직접 재현). 다만 **HEAD에서 실제로 스크립트 오류로 끊긴 검사는 찾지 못했다**(빠른 Godot 검사 9개를 HEAD 사본에서 하나씩 돌려 모두 스크립트 오류 0, 검사 수도 그간 기록과 같다). "368건으로 0 failures"는 구현 도중 상태에서 난 일로 보이며, HEAD의 보고들은 거짓 통과가 아니었다 |
| 3. 경계 | 코어가 `view`·`Loc`·`TranslationServer`·`tr(`를 부르는 곳 0건(정적 검사와 손 검색). 화면이 코어 상태를 새로 바꾸는 곳은 없다. `error`/`error_code` 어긋남은 "코드 없이 문장만" 한 방향으로만 생기고, 그 경우 화면은 문장을 그대로 보인다 |
| 4. 덤프에 안 잡힌 화면 글 | 실행 중 `Loc.t`가 내는 글 54개를 HEAD의 옛 리터럴·데이터와 글자 단위로 대조해 **모두 같다.** 빠진 키(키 이름이 화면에 그대로 뜸)를 잡는 자동 검사는 아직 없다(L6 몫). 이번 키는 손으로 모두 대조했다 |
| 5. 관리 툴 | 구역·의식 항목 5개가 HEAD와 바이트 같다(출처 줄 번호 제외). 관리 툴 단위 검사 55개 통과(`run_all` 로그) |
| 6. 옛 층의 `def.name` | 실행 경로에 닿지 않는다는 주장이 맞다 |
| 7. S1 전/후 구분 | 아래 "고칠 것" 표 |

---

## 1. 골든 갱신

### 1.1 갱신 전후 비교

HEAD의 `chapter1/tests/golden/core_runtime.json`을 `_local/review-l1/core_runtime.HEAD.json`으로 풀어 지금 파일과 구조 비교했다.

- 네 사례 모두 `mode`, `tick`, `kills`, `hp_raw`, `level`, `seed`, `primary`, 체크포인트 개수가 같다(차이 0).
- 달라진 것은 체크포인트 해시 34개와 최종 해시 4개뿐이다. 모두 6000틱(첫 수호자 출현) 이후의 몇 묶음이고, 사이의 체크포인트는 그대로다 — 수호자가 살아 있는 동안에만 `title`이 스냅숏에 있다는 것과 맞는다.

| 사례 | mode | tick | kills | hp_raw | level | 체크포인트 |
|---|---|---|---|---|---|---|
| 11:frost | victory | 25005 | 4867 | 53222 | 12 | 41 |
| 11:ember | victory | 22058 | 4828 | 44981 | 12 | 36 |
| 11:arc | victory | 20697 | 4983 | 27316 | 12 | 34 |
| 11:frost:L20-lance | victory | 17992 | 4416 | 45608 | 12 | 29 |

(전후 같음)

### 1.2 되돌려 해시하기(직접 실행)

`_local/review-l1/golden_restore_probe.gd`: 지금 코어로 골든 네 사례를 같은 방식(내장 자동 조작, 600틱마다)으로 돌리고, 스냅숏 안의 모든 `title_key`를 `title = Loc.t(그 키)`(한국어)로 바꾼 뒤 `JSON.stringify(...).sha256_text()`로 해시해 **HEAD 골든**과 비교했다. `JSON.stringify`는 키를 정렬하므로 필드 순서는 결과에 영향이 없다.

```
RESTORE_CASE {"case":"11:chapter1.skill.frost","checkpoints":41,"diffs":0,"final_equal":true,...}
RESTORE_CASE {"case":"11:chapter1.skill.ember","checkpoints":36,"diffs":0,"final_equal":true,...}
RESTORE_CASE {"case":"11:chapter1.skill.arc","checkpoints":34,"diffs":0,"final_equal":true,...}
RESTORE_CASE {"case":"11:chapter1.skill.frost:L20-lance","checkpoints":29,"diffs":0,"final_equal":true,...}
RESTORE_RESULT {"bad":[],"compared":140,"other_key_fields":[],"renamed_paths":[".enemies.1016.title_key", ... 12개]}
```

뜻:
- L1이 스냅숏에 낸 변화는 **수호자 `title` → `title_key` 하나뿐**이고, 그 밖의 어떤 값도(글이든 아니든) 바뀌지 않았다. 글 없는 골든보다 강한 증거다(글 없는 골든은 `name`·`description` 등 지운 필드 안의 변화는 보지 못한다).
- 은총 카드의 `title` → `title_key`는 골든 네 사례의 어느 체크포인트에도 나타나지 않았다(제안 창이 체크포인트 순간에 열려 있지 않음). 구현자 보고("코드로만 확인")와 같다. 카드 쪽은 1.4의 검사로 본다.
- 스냅숏 안에 `title_key` 말고 `*_key`, `unit_id`, `name_key`, `error_code` 필드는 없다(`other_key_fields: []`).

### 1.3 글 없는 골든

- `core_runtime_textless.json`은 작업 트리에서 바뀌지 않았다(`git diff --stat` 0).
- `run_all` 로그: `golden pass 4 cases, 0 mismatches`, `golden-textless pass 4 cases, 0 mismatches`.
- 이것만으로도 "진행이 같다"의 증거는 충분했다고 본다(지시서 기준). 1.2는 그 위에 "글 필드 안에서도 수호자 이름 말고는 바뀐 것이 없다"를 더한다.

### 1.4 앞으로 글 없는 골든을 흔들 위험

- 지우는 목록(`golden_core.gd:16` `TEXT_FIELDS`)은 `name, title, description, rare_words, legacy_name, title_key`다. 지금 스냅숏에 들어가는 새 필드는 `title_key` 하나이고 목록에 있다. `name_key`(`effective_skill`), `unit_id`(`stat_sheet`), `objective()`, `error_code`(프로필)는 스냅숏에 들어가지 않는다(1.2의 `other_key_fields: []`가 실행으로 보인다).
- 위험은 낮다. 키 문자열은 언어와 무관하므로, 키 이름을 바꾸지 않는 한 해시는 고정된다. 남는 위험은 "누가 스냅숏에 새 `*_key`를 넣고 목록에 안 넣는 것"이다 → 권고 P1.

---

## 2. `run_all.py`의 거짓 통과

### 2.1 고침이 옳은가 — 직접 재현

`_local/review-l1/fake_error_test.gd`: 검사 함수 중간에서 없는 키를 읽어 런타임 오류를 내고, 그 뒤 깨끗한 결과 줄(`{"checks":1,"failures":[]}`)을 찍는 가짜 검사. 같은 `check` 사전을 HEAD의 `run_godot`과 지금의 `run_godot`에 넣었다.

```
NEW  (False, "1 checks, 0 failures · SCRIPT ERROR: Invalid access to property or key 'missing_field' on a base object of type 'Dictionary'.")
HEAD (True, '1 checks, 0 failures')
```

- Godot 4.5.1은 함수 안의 런타임 오류에서 그 함수만 멈추고 호출자는 계속 돈다. 그래서 결과 줄은 찍히고 검사 수만 준다. HEAD의 `run_all`은 이것을 통과로 셌다. **고침은 옳다**(`tools/dev/run_all.py:81~85`).
- 일반 `ERROR:` 줄(엔진 경고, `push_error`)은 여전히 실패로 보지 않는다. 알맞다고 본다.

### 2.2 HEAD에서 실제로 끊긴 검사가 있었나

`git archive HEAD project.godot chapter1 combat export_presets.cfg`를 `_local/review-l1/head/`에 풀고(`.godot` 가져오기 캐시는 지금 것을 복사), `run_all`의 빠른 Godot 검사를 하나씩 돌려 원시 출력을 모두 남겼다(`_local/review-l1/out-head/*.log`). 같은 일을 지금 트리에도 했다(`out-cur/`).

| 검사 | HEAD 사본 | 지금 트리 |
|---|---|---|
| growth | 188건, SCRIPT ERROR 0, ERROR 0 | 188건, 0, 0 |
| tree | 115건, 0, 0 | 118건, 0, 0 |
| combat | 75건, 0, 0 | 75건, 0, 0 |
| chapter | **474건**, 0, 0 | 474건, 0, 0 |
| profile | 117건, 0, 0 | 117건, 0, 0 |
| loot | 36건, 0, 0 | 36건, 0, 0 |
| loc | 376건, 0, 0 | 876건, 0, 0 |
| app-guard | 5건, 0, 0(두 번째 실행. 첫 실행은 아래 주) | 5건, 0, 0 |
| profile-legacy | 41건, 0, 0 | 41건, 0, 0 |
| core-text | 없음(새 검사) | 21건, 0, 0 |

- **HEAD에서 스크립트 오류로 끊긴 검사는 찾지 못했다.** `chapter`는 HEAD에서도 474건이다. 그간의 `run_all` 기록(`_local/run_all-t21·l0b·d4u·m23·commit3-20261117.log`)도 모두 `chapter 474`다. 구현자가 본 "368건으로 0 failures"는 L1 작업 도중의 코드에서 생긴 것으로 보인다. 그러니 **지금까지의 "통과" 보고가 거짓이었다는 증거는 없다.** 구멍은 실제로 있었고(2.1), 이번에 막혔다.
- 주: HEAD 사본의 `app-guard` 첫 실행은 `res://combat/combat_resolver.gd`를 "Can't open file"로 열지 못해 스크립트 오류 6줄을 내고 `quit()`에 닿지 못해 끝나지 않았다(내 실행 도구가 `godot.py`를 거쳐 띄운 탓에 시간 초과 뒤에도 남아 있어 내가 멈춤). 파일은 사본에 있고 HEAD에 추적돼 있으며, 바로 다시 돌리자 5건 통과·오류 0이었다. 막 풀어 놓은 사본에서 생긴 일시적 파일 열기 실패로 판단한다(저장소 문제 아님). 이런 경우 `run_all`은 시간 초과로 실패를 낸다(통과로 세지 않는다).
- 검사 수 변화의 이유: `tree` 115→118은 `test_skill_tree.gd`에 L1이 더한 세 건, `loc` 376→876은 `ko.po`·`en.po`에 키가 100개 늘어(53→153, 내가 셈) 키별 검사가 는 것으로 보인다(검사 하나하나를 맞춰 보지는 않았다).
- 느린 검사(golden, golden-textless, loot-sim)는 HEAD 사본에서 따로 돌리지 않았다. HEAD 기록에서 모두 불일치 0이었고, 끊겼다면 불일치나 "no result line"으로 드러났을 가능성이 높지만 확인은 하지 않았다.

### 2.3 회귀가 불안정해질 위험

- 지금 트리의 모든 빠른 검사에서 `SCRIPT ERROR` 0건이다(위 표). `run_all` 로그에서도 그 규칙을 지난 뒤 모두 통과다. 알려진 무해한 `SCRIPT ERROR` 줄은 없다.
- 앞으로 일부러 스크립트 오류를 내는 검사(예: 파싱 실패를 시험)를 만들면 이 규칙에 걸린다. 그때는 검사별 허용 목록이 필요하다 → 권고 P2. 지금은 해당 없음.
- 덧붙여, 결과 줄은 있는데 검사 수가 크게 준 경우를 잡는 장치는 여전히 없다(스크립트 오류 없이 반복문이 일찍 끝나는 경우 등) → 권고 P3.

---

## 3. 경계

### 3.1 코어가 표현을 부르는가

- `python tools/dev/i18n_scan.py` → `I18N_SCAN {"files": 13, "total": 578, "baseline_total": 578, "grown": [], "shrunk": [], "core_references": 0}`, exit 0.
- 손 검색: `chapter1/core`, `combat`에서 `Loc`, `TranslationServer`, `res://chapter1/view`, `res://chapter1/app`, `tr(` 0건.
- 정적 검사의 정규식을 표본 11줄로 시험했다: `Loc.t(...)`, `TranslationServer.translate`, `tr("x")`, `x.tr(`, `atr(`, view·app·i18n 경로의 `preload`/`load`는 잡고, 문자열 안의 `"Loc"`, 주석 안의 `Loc.t`, `str(b)`는 놓아 준다. A12(앞선 검수)는 닫는다.

### 3.2 화면이 코어 상태를 바꾸는가

- `chapter_hud.gd`·`chapter_world.gd`·`skill_tree_panel.gd`·`tree_text.gd`의 변경은 모두 읽기와 `Loc.t` 호출이다. `objective()`, `effective_skill()`, `enemies[...]`, `RITUALS`를 읽기만 한다.
- `chapter_one.gd:369`(`profile.error="검증 실행 · 저장 비활성"`)과 `:454`(`profile.error=SESSION_NO_SAVE_NOTE`)는 앱이 프로필 객체의 필드에 쓰는 곳이다. HEAD에도 있던 것이고 L1이 새로 만든 것은 아니다. 이제 이 대입은 세터 때문에 `error_code`를 비운다 → 3.3.

### 3.3 `error`와 `error_code`가 어긋나는 경로

- `chapter_profile.gd:37~41`: `error`에 세터가 있어 대입하면 `error_code`·`error_args`가 비워진다. `_err()`(`:177`)만 셋을 함께 쓴다(세터가 먼저 비우고 그 뒤 코드를 넣는 순서라 맞다). `start_fresh_after_reject` 실패 경로(`:205~206`)는 셋을 함께 되돌린다. 성공 경로(`:200`, `:439`)와 `configure` 처음(`:90`)은 `error=""`로 셋을 모두 비운다.
- 그러므로 어긋남은 "코드 없이 문장만 있는" 한 방향뿐이고, 그것은 앱이 직접 대입한 두 곳(3.2)에서만 생긴다. 이때 `_profile_error_text()`(`chapter_one.gd:441~444`)는 문장을 그대로 보인다. 지금은 문장이 한국어라 화면이 같다.
- 거꾸로(코드는 있는데 문장이 다른 실패의 것) 되는 경로는 찾지 못했다.
- `start_run`의 분기(`chapter_one.gd:385`)가 `error_code!="preview_only"`로 바뀐 것은 HEAD의 문장 비교와 같은 뜻이다(`preview_only`는 `configure`의 그 한 곳에서만 나온다).

---

## 4. 화면 글

### 4.1 실행 중 `Loc.t`의 글 대조(직접 실행)

`_local/review-l1/loc_text_probe.gd`를 헤드리스로 돌려 L1이 화면에 새로 쓰는 키의 실제 번역 결과를 받았고(`Loc.locale()` = `ko`), 그것을 HEAD의 옛 리터럴과 데이터에서 뽑은 글과 Python으로 글자 단위 비교했다.

```
locale ko compared 54 mismatch [] missing_key_probe zone.9.name
profile texts not in HEAD: []
```

대조한 것: 구역 이름 3, 의식 이름 2, 수호자 이름 3, 목표 줄 2(`hud.objective.move`, `hud.objective.seal_kills`에 2·3을 넣은 결과 = HEAD의 `"봉인 주변 처치 %d / %d"%[2,3]`), 저장 오류 35(`level_required`에 12, `tree_rejected_detail`에 상세 하나를 넣은 결과 포함), 기술·진화 이름 6, 결정 은총 이름 3(HEAD `growth_quality37.json` 기준).

이로써 덤프에 안 잡힌 줄의 **바뀐 부분**(알림의 구역·수호자·의식 이름, 의식 3D 글의 이름, 은총 카드 제목, 저장 오류 문장)은 글자가 같다. 알림·3D 글의 나머지 부분(`"봉인 해제 · 동쪽 회랑으로 "`, `" 출현"`, `"\n[E] 의식 시작"` 등)은 diff에서 리터럴이 그대로임을 눈으로 확인했다. 화면에 실제로 그려진 모습은 보지 않았다.

참고: `growth_quality36.json`의 번개 진화 이름은 `두 갈래 폭풍`이고 `ko.po`는 `세 갈래 폭풍`이다. 실행에 쓰는 것은 37판(후속 문서)이므로 맞다.

### 4.2 기술 트리 설명

`test_skill_tree.gd`가 모든 노드·모든 랭크에서 `describe()`(옛 한국어)와 `TreeText.lines(describe_keys())`가 같음을 본다. 지금 트리에서 118건 통과(내 실행). 조사 오류 `"서리창 랭크 {rank}으로 시작"`은 바이트를 맞추려고 그대로 옮겼다 — 지시서 L1의 "바이트 같게"에 맞고, 고치는 것은 L2다.

### 4.3 빠진 키를 잡는 검사

- `Loc.t`는 키가 없으면 키 이름을 그대로 돌려준다(탐침의 `zone.9.name`). 지금 코드에서 이 경우를 잡는 검사는 **없다.** `test_loc.gd`는 `ko.po`와 `en.po`의 키 집합이 같은지만 본다.
- 이번 변경의 동적 키(`zone.%d`, `ritual.%s`, `enemy.champion.%d`, `title_key`, `name_key`, `profile.error.<code>`)는 내가 모두 손으로 대조했다(코드 35개 모두 `ko.po`에 있음, 위 54개 실행 대조). 정적 리터럴 키도 Python으로 훑어 빠진 것이 없다.
- 동적 키를 검사로 지키는 것은 L6(`i18n` 검사 1번)의 몫이다. L6 지시서에 "동적 키 목록(구역 수, 의식 id, 은총 id, 프로필 코드)을 데이터·코어에서 만들어 `ko.po`에 있는지 본다"를 넣으라고 권한다 → P4.

---

## 5. 관리 툴(`tools/manager/catalog.py`)

- `world_entities`가 `ZONE_NAMES` 대신 `ko.po`에서 이름을 읽는다. HEAD의 `catalog.py`를 HEAD 사본 위에서, 지금의 `catalog.py`를 지금 트리 위에서 돌려 구역·의식 항목을 비교했다: 5개, **출처(줄 번호) 말고 바이트 같음**, 경고 0.
- `parse_po`는 기존 함수(번역 화면용)를 그대로 쓴다. 다른 화면에 닿는 변경은 없다.
- 관리 툴 단위 검사: `run_all`의 `manager` 55개 통과(9절).
- `catalog.py:139` `describe_block`은 코어의 옛 한국어 `describe_block`을 옮긴 것이다. 옛 함수를 L2 끝에 지울 때 관리 툴도 같이 `ko.po`의 `tree.effect.*`로 바꿔야 한다 → L2/L6 지시서에 한 줄.

## 6. 옛 층의 `def.name`

- `chapter1/view/chapter_world.gd:27`, `:79`가 `def.name`을 읽는다(이제 없는 필드).
- 이 파일은 `chapter_world_quality37b.gd`까지 이어진 상속 체인의 뿌리다. 실행 중 이 체인의 객체는 `view/world/chapter_world.gd:734`의 `_stone_geometry37=Geometry37b.new()` 하나뿐이고, 쓰는 것은 `_voussoir22()`(`:736`)와 `_chamfer37()`(`:744`) 둘이다. `setup`·`sync`는 부르지 않는다.
- `app/chapter_one.gd:15~21`이 `cloister_world.gd`(다른 체인, `def.name` 없음)와 `cloister_hud.gd`(`card.title`을 읽음, `:239`)를 필드 초기화로 만들지만 `_init`(`:365`)에서 곧바로 평탄화한 객체로 바꾼다. 트리에 넣지 않으므로 `_ready`·`sync`가 돌지 않는다.
- 따라서 **주장이 맞다.** GDScript는 사전 필드 접근을 실행 때 판정하므로 파싱 오류도 없다(`app-guard`가 앱 스크립트를 실제로 만들고 오류 0).

---

## 7. 고칠 것

### 7.1 이번 작업 안에서(S1 시작을 막지 않음)

| # | 파일:행 | 내용 | 할 일 |
|---|---|---|---|
| R1 | `chapter1/tests/test_core_text.gd:66~69` | 은총 카드 제목(`growth.offer.cards[].title_key`)이 실제로 검사되지 않는다. 600틱마다 스냅숏을 보는데 그 순간 제안 창이 열려 있지 않다(1.2에서 골든 네 사례 모두 카드 경로 0) | 제안이 열린 틱(`run.growth.snapshot().offer`가 비지 않은 때)에도 스냅숏을 걷거나, `run.growth._eligible_cards()` 결과를 직접 걷는다. 검사 한 줄: "카드 경로를 적어도 한 번 보았다" |
| R2 | `chapter1/core/run_growth_quality37.gd:19~27` | 앞선 문서의 번개 진화 이름을 더는 확인하지 않는다(지시서대로). 그러나 "이름 말고 다른 필드가 다르면 거부"(`:34~36`)를 지키는 검사가 HEAD에도 지금도 없다 | `test_growth.gd`에 두 줄: 진화 이름만 다른 후보는 받아들임, 이름 밖의 필드 하나가 다르면 `configure` 거부 |

### 7.2 S1 지시서에 넣을 것(S1 담당이 고침)

| # | 파일:행 | 내용 |
|---|---|---|
| C1 | `chapter1/core/chapter_profile.gd` 전반(`_err` 호출 35곳, `apply_progress` `:396~404`) | `error` 문장이 아직 한국어다. 지시서는 "옛 `error`는 개발용 영어 문장"이었는데, 옛 저장 표본 검사(`chapter1/tests/profile_legacy_snapshot.gd:95`가 `profile.error`를 기록, 기준 `fixtures/profile_legacy/expected_v3.json`) 때문에 남겼다. 이유는 받아들인다. S1이 이 파일과 표본 검사를 어차피 고치므로 **S1에서**: 표본에 `error_code`를 기록하게 바꾸고(기준 갱신은 S0 묶음 규칙에 따라), 그다음 `error`를 영어 개발 문장으로 바꾼다. 그때 `i18n_baseline.json`의 `chapter_profile.gd`가 0에 가까워져야 한다 |
| C2 | `chapter1/app/chapter_one.gd:369`, `:454` | 앱이 `profile.error`에 한국어 문장을 직접 넣는다(코드 없음). S1b가 이 파일을 고칠 때 앱 자신의 변수나 코드(`profile_off`, `session_no_save`)로 바꾼다. 이것을 하지 않으면 C1 뒤에도 화면은 같지만, 앱이 프로필 객체의 필드를 쓰는 모양이 남는다 |
| C3 | `chapter1/tests/hud_dump.gd:167`, `:476` | 덤프가 `profile.error`를 그대로 화면에 넣는다(앱의 `_profile_error_text()`를 거치지 않음). C1로 `error`가 영어가 되면 덤프만 게임과 달라진다. S1의 `hud_dump.gd` 수정 범위에 `_profile_error_text()` 사용을 더한다 |

### 7.3 S2(= T3-S 코어) 지시서에 넣을 것

| # | 파일:행 | 내용 |
|---|---|---|
| C4 | `chapter1/core/combat_core.gd:375` | `_effects_of`가 효과가 있는지를 장비의 `description` 글이 비었는지로 정한다. S2가 장비 사전에서 `description`을 빼면 **효과 줄이 말없이 모두 사라진다.** S2에서 `legendary_id`·고유 `base_id`의 데이터 유무로 바꾸고, `test_chapter_run.gd`의 A1 효과 검사(`:870~871`)가 그것을 지키게 한다 |
| C5 | `chapter1/core/combat_core.gd:41~44` | `STARTER` 장비 네 개의 `name`·`description`이 한국어 그대로다. L1 지시서의 "고칠 파일"에 있었지만 같은 지시서의 "하지 않을 것(장비 사전 글)"과 겹친다. 구현자가 장비 쪽으로 판단해 남긴 것을 받아들인다. S2의 대상에 명시한다 |
| C6 | `chapter1/core/combat_core.gd:377` | 고유 장비의 효과 `id`가 `base_id`(`chapter1.full.unique.<id>`) 전체다. 키 규칙(2.2절 `item.unique.<id>.desc`)과 잇는 법을 `item_names.gd`에서 정한다(접두어를 떼는지) |

### 7.4 L2로 넘길 것

- `chapter_hud.gd:1341` `"%s를 처치하세요"`(받침 있는 수호자 이름 두 개에서 틀림), `ko.po` `tree.effect.start_rank` `"{rank}으로"` — 바이트 같음을 위해 일부러 남긴 조사 오류.
- `chapter_hud.gd`의 `SKILL_NAMES`, 은총 카드 종류 글, `chapter_one.gd`의 알림 앞뒤 리터럴 등 남은 한글 578개.
- 옛 `describe_block`(`skill_tree.gd:544`)과 관리 툴의 사본(`catalog.py:139`) 제거.
- `en.po`에 이번에 100개 키의 영어 글이 들어갔다(파일 머리 "Machine first pass, to be reviewed"). 지시서 L1은 비워 둬도 된다고 했으니 잘못은 아니지만, 검토 전 초안이다. L7에서 narrative-lead 검토 대상에 포함한다.

---

## 8. 권고(막지 않음)

| # | 내용 |
|---|---|
| P1 | `golden_core.gd`의 `strip_text`가 `_key`로 끝나는 필드를 모두 지우게 하거나, `test_core_text.gd`가 "스냅숏의 `*_key` 필드는 `TEXT_FIELDS`에 있어야 한다"를 본다. 지금 해당 필드는 `title_key` 하나라 급하지 않다 |
| P2 | `run_all.py`에 검사별 "예상한 스크립트 오류" 허용 목록 자리를 두는 것. 지금은 필요 없다 |
| P3 | `run_all.py`가 검사별 최소 검사 수(예: 직전 통과 값의 90%)를 기록해 크게 줄면 실패로 보는 것. 스크립트 오류 없이 검사가 일찍 끝나는 경우를 잡는다 |
| P4 | L6의 `i18n` 검사에 동적 키 대조(구역 수·의식 id·은총 id·프로필 코드 → `ko.po`)를 넣는 것 |

---

## 9. 직접 실행한 것

| 명령 | 결과 |
|---|---|
| `git show HEAD:chapter1/tests/golden/core_runtime.json` → 구조 비교(Python) | 글 아닌 값 차이 0, 해시만 38개 다름 |
| `python tools/dev/godot.py --headless --path . --script res://_local/review-l1/golden_restore_probe.gd` | 140 체크포인트 + 최종 4 모두 HEAD 골든과 같음, `other_key_fields: []`, exit 0 |
| `python tools/dev/godot.py --headless --path . --script res://_local/review-l1/loc_text_probe.gd` + Python 대조 | 54개 글 HEAD와 같음, 스크립트 오류 0 |
| `run_all.run_godot`(지금)과 HEAD의 `run_godot`에 `_local/review-l1/fake_error_test.gd` | 지금 실패 / HEAD 통과(거짓 통과 재현) |
| `git archive HEAD ...` → `_local/review-l1/head/`, 빠른 Godot 검사 9개를 HEAD 사본과 지금 트리에서 하나씩 | 2.2 표 |
| `python tools/dev/i18n_scan.py` | `total 578, baseline 578, grown [], core_references 0`, exit 0 |
| `i18n_scan.CORE_FORBIDDEN`·`blank_strings` 표본 11줄 | 잡을 것 8, 놓을 것 3 모두 맞음 |
| HEAD·지금 `catalog.world_entities` 비교 | 5개 같음, 경고 0 |
| 바뀐 파일의 CRLF 수(Python) | 모두 0, HEAD와 같음(줄바꿈 변화 없음) |
| `_local/run_all-l1-20261117.log`(디렉터가 돌린 전체 회귀, 읽기만) | 6절 아래 표 |

`run_all` 전체(디렉터 실행, 로그 읽기):

| 검사 | 결과 |
|---|---|
| growth | 188건 통과 |
| tree | 118건 통과 |
| combat | 75건 통과 |
| chapter | 474건 통과 |
| profile | 117건 통과 |
| loot | 36건 통과 |
| loc | 876건 통과 |
| app-guard | 5건 통과 |
| profile-legacy | 41건 통과 |
| golden | 4사례 불일치 0 |
| golden-textless | 4사례 불일치 0 |
| core-text | 21건 통과(나도 따로 돌려 21건 통과, 허용된 장비 글 경로 6개만 나옴, 스크립트 오류 0) |
| loot-sim | 3,000판 불일치 0, 한 판 평균 희귀 4.66 · 장신구 1.43 · 전설 0.37 · 고유 0.24(이전 기록과 같음) |
| manager | 55개 통과 |
| i18n-scan | 13파일, 한글 리터럴 578(기준 578) |
| 합계 | `RUN_ALL {"passed": 15, "failed": [], "skipped": []}`, `exit=0` |

## 10. 확인하지 못한 것

- 화면에 실제로 그려진 글(알림 토스트, 의식 3D 글, 은총 카드, 저장 오류 줄). 글자 대조(4.1)만 했고 화면은 보지 않았다.
- 구현자의 `hud_dump.gd` 전후 덤프(바이트 동일 주장). 덤프 파일을 저장소 작업 트리에서 찾지 못했고 다시 돌리지 않았다.
- HEAD의 느린 검사(golden, golden-textless, loot-sim)를 HEAD 사본에서 스크립트 오류 여부까지 따로 본 것.
- `measure_combat.gd`·`sim_loot.gd` 전후 비교. 수치·데이터 변경이 없어 지시서 기준상 필요 없다고 보고 돌리지 않았다(`run_all`의 loot-sim 결과로 대신).
