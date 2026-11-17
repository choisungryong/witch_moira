# D5 저장 안전 — 장비 이름을 검증에서 떼기, 저장이 거부됐을 때 막히지 않기

2026-11-17 · 작성: 기획 책임자(design-lead) · 대상: `gameplay-systems`(`core/loot.gd`, `core/chapter_profile.gd`, `app/chapter_one.gd`, 검사), `ui-hud`(안내 화면, `hud_dump.gd`) · 판정: 총괄 디렉터
근거: `docs/specs/D3-story-systems-requirements.ko.md` 1.2절, `docs/reviews/DECISIONS-PENDING-20261117.ko.md` 3절(디렉터 결정: 이름 정리보다 검증 분리를 먼저), `docs/reviews/PLAN-GAP-AUDIT-20261117.ko.md` 요약 4. 코드를 읽어 썼고 Godot는 실행하지 않았다.

**절대 조건: 사용자의 저장 파일(거부된 것 포함)을 지우거나, 고치거나, 옮기거나, 이름을 바꾸지 않는다.** 이 명세의 모든 선택지가 이 조건을 지킨다. 검사는 `res://_local/` 아래의 격리 경로만 쓴다.

## 디렉터용 요약

1. 지금은 `loot.json`의 장비 이름 한 글자(기본 이름, 접두·접미, 전설 이름, 고유 이름·설명, 희귀 이름 낱말)만 바꿔도 **사용자 저장 전체가 거부된다.** 거부되면 판을 시작할 수 없고 화면에는 알림 한 줄뿐이다.
2. (가) **이름과 설명은 계속 파일에 쓰되, 읽을 때 검사하지 않고 지금 데이터로 다시 짓는다.** 파일 형식이 그대로라 **스키마 3을 유지**한다(권고). 스키마 4는 D3의 서사 기록을 넣을 때 따로 묶는다.
3. 같은 구조의 위험이 수치에도 있다. 기본 능력치, 접사 범위, 고유·전설 수치, 요구 레벨 공식을 바꿔도 저장이 거부된다. 이 명세는 이름만 고치고, 수치는 "기존 id의 수치는 바꾸지 않는다"는 데이터 규칙과 그 규칙을 지키는 검사로 막는다. 규칙을 받아들일지는 디렉터가 정한다(결정 D-1).
4. 출발 장비 검증이 실패하면 지금은 **게임이 꺼진다**(`chapter_one.gd` 388행 `quit(1)`). 이것도 함께 고친다.
5. (나) 저장이 거부되면 원본은 그대로 두고 세 가지 길을 보여 준다. ① 안내: 파일 위치, 원인 분류, 폴더 열기. ② 이번 실행만 저장 없이 플레이. ③ 새 저장으로 시작: 원본 옆에 새 파일을 만든다. 거부된 파일의 기록본 가운데 가장 최근의 읽히는 것에서 이어 갈 수 있으면 그것부터 쓴다.
6. 권고 순서: (가) → (나)의 ①② → 사용자 결정 뒤 ③. ①②는 저장 파일을 하나도 쓰지 않는다.
7. 코어 전투 코드는 고치지 않는다. `loot.gd`는 드랍 굴림을 바꾸지 않으므로 골든은 그대로여야 한다(확인은 골든 실행). 프레임 측정 창은 필요 없다.
8. 사용자 결정 넷: ③을 넣을지, 기록본에서 이어 하기를 허락할지, 저장 없이 플레이를 허락할지, 안내 문구의 말투. 모두 6절에 모았다.

---

## 1. 지금의 동작(코드 근거)

| 무엇 | 지금 | 근거 |
|---|---|---|
| 고유 장비 | 저장된 이름·설명이 데이터와 글자 하나까지 같아야 한다 | `core/loot.gd` 259행 `item.name != def.name or item.description != def.description` |
| 마법·일반·전설 | 기본 이름 + 접두·접미(+ 전설 이름)로 다시 지은 이름, 설명과 같아야 한다 | `loot.gd` 283·287·288행, 이름 짓기는 131~152행 `_compose` |
| 희귀 | 이름이 두 낱말이고 각 낱말이 `rare_names.first`·`second` 목록에 있어야 한다 | `loot.gd` 284~286행 |
| 판정 결과 | 장비 하나라도 실패하면 `normalize()`가 `{}`를 돌려주고 **파일 전체가 거부된다** | `core/chapter_profile.gd` 179행, 85행 `error="저장 파일 검증 실패 · 원본 보존"` |
| 거부 사유 | 남기지 않는다. 어느 장비의 어느 항목인지 알 수 없다 | `normalize`·`normalize_v3`는 빈 사전만 돌려준다 |
| 거부된 뒤 | `available=false`. 판 시작을 막고 알림 한 줄 | `app/chapter_one.gd` 367행 |
| 옛 형식 파일(v2·v1)이 거부될 때 | 같다. v3 파일이 없고 v2가 거부되면 시작할 수 없다 | `chapter_profile.gd` 87~90·99~106행 |
| 출발 장비 | 코어가 다시 검증하고, 실패하면 앱이 게임을 끈다 | `core/chapter_core.gd` 653행, `chapter_one.gd` 388행 |
| 저장 쓰기 | 새 리비전마다 `chapter-one-profile-v3.revision-<번호>-<pid>-<usec>.json` 기록본을 남기고, 임시 파일을 본 파일로 바꿔 끼운다. 기록본은 지우지 않는다 | `chapter_profile.gd` 270~285행 |
| v1 장비 | 장비 v1 규칙(`chapter_items.gd`)으로 따로 검증한다 | `loot.gd` 240행 |
| 검사 경로 | QA 모드는 `res://_local/` 아래 `.json`만 허용 | `chapter_profile.gd` 69~73행, `tests/test_chapter_profile.gd` 108~116행 |

---

## 2. (가) 장비 이름을 저장 검증에서 떼기

### 2.1 규칙

| # | 규칙 |
|---|---|
| N1 | 장비의 **정체**는 id와 수치로만 정한다: `grammar`, `base_id`, `slot`, `quality`, `item_level`, `required_level`, `affixes`의 `id`·`group`·`stat`·`value`, `legendary_id`, `stats`. 이것들은 지금처럼 엄격하게 검증한다(위조 방지) |
| N2 | `name`과 `description`은 **겉모습**이다. 읽을 때 형식만 본다: 문자열, 이름 1~160자, 설명 0~300자(지금 `normalize` 165행의 길이 제한 그대로). 내용은 검사하지 않는다 |
| N3 | 검증을 통과한 장비는 **지금 데이터로 이름과 설명을 다시 짓는다**(새 함수 `loot.dress(item)`). 고유는 정의의 이름·설명, 일반·마법·전설은 `_compose`의 결과. 희귀는 저장된 이름을 그대로 둔다(아래 N4) |
| N4 | 희귀 이름은 굴린 낱말 두 개다. 데이터에 낱말의 id가 없어서 다시 지을 수 없다. 저장된 글을 그대로 쓴다. 낱말 목록이 바뀌어도 이미 얻은 희귀는 옛 이름을 지닌다(이름 붙은 물건으로 본다). 목록 소속 검사(284~286행)는 없앤다. 낱말 수 검사도 없앤다(세 낱말 이름이 생길 수 있다) |
| N5 | 다시 지은 이름은 메모리에만 반영한다. **파일은 다음 정상 저장 때 새 이름으로 쓰인다.** 읽기만 해서 파일을 고치지 않는다 |
| N6 | 판 안에서 새로 떨어지는 장비는 지금처럼 굴릴 때 이름을 짓는다. 저장할 때(`record_run` 304행)도 N1·N2만 본다 |
| N7 | 출발 장비 검증(`chapter_core.gd` 653행)도 같은 `validate`를 쓰므로 함께 느슨해진다. 출발 장비가 그래도 거부되면 게임을 끄지 않고 "출발 장비를 불러오지 못했습니다 · 장비 없이 출발합니다"라고 알리고 장비 없이 시작한다. 저장된 선택은 바꾸지 않는다 |
| N8 | v1 장비(`grammar` 없음)는 건드리지 않는다. `chapter_items.gd`는 옛 저장 검증용이라 데이터가 바뀌지 않는다 |
| N9 | 트리 노드 이름은 저장에 들어가지 않는다(노드 id만). 다만 **이름만 바꿀 때 `tree_revision`을 올리면 사용자의 투자가 초기화된다**(`normalize_v3` 228~231행). 데이터 규칙: 이름·문구만 바꿀 때는 revision을 올리지 않는다. 이 규칙을 `skill_trees.json`을 고치는 사람(content-balance, narrative-lead의 이름 교체 지시를 받는 사람)에게 알린다 |

### 2.2 함수(gameplay-systems, `core/loot.gd`)

```gdscript
## Identity check only: ids, slot, quality, levels, affix values, stats. Name and description are
## presentation; only their type and length are checked here. v1 items keep their own rules.
func validate(item: Dictionary) -> Array[String]

## A copy of `item` with name and description rebuilt from the current data (rare names are kept).
## Call only on an item that passed validate(). Never changes stats or ids.
func dress(item: Dictionary) -> Dictionary
```

- `validate`에서 지울 것: 259행의 `item.name != def.name or item.description != def.description`, 284~287행의 희귀 이름·이름 비교, 288행의 `item.description != expected.description`. 남길 것: 259행의 칸·수치·접사 없음·레벨, 288행의 `item.stats != expected.stats`.
- 새로 넣을 것: `name`이 문자열 1~160자, `description`이 문자열 0~300자. 제어 문자(줄바꿈 제외) 금지.
- `chapter_profile.gd` `normalize`(179행 부근): `validate` 통과 뒤 `record.item = tables.dress(item)`. v1 장비(`grammar` 없음)는 `dress`하지 않는다.
- `chapter_core.gd` `import_starting_gear`: 입력은 이미 프로필에서 다시 지은 것이다. 코어에서 다시 `dress`하지 않는다.

### 2.3 스키마 — 3 유지 대 4로 묶기

| 안 | 내용 | 장점 | 단점 |
|---|---|---|---|
| **가. 스키마 3 유지(권고)** | 파일에 이름·설명을 계속 쓴다. 읽는 쪽만 느슨해진다 | 파일 형식이 같다. 이관 경로가 늘지 않는다. 지금의 사용자 저장을 그대로 읽는다. 지금 바로 할 수 있다 | 새 이름으로 저장한 파일을 **옛 실행본**이 읽으면 거부한다. 옛 실행본은 배포하지 않고, 개발 사본(`git archive`)은 `--chapter1-profile-off`로 돈다(T1 0.2절)라 실제 위험은 작다 |
| 나. 스키마 4로 묶기 | D3 1.1의 서사 기록(수집품, 본 사건, 결전 완료)과 함께 새 파일 `chapter-one-profile-v4.json`. v3은 읽기만 | 파일 이름이 바뀌어 옛 실행본과 섞이지 않는다 | D3 저장 설계(수집품 등)가 끝날 때까지 이 수정이 기다린다. 그동안 이름 정리(CHAPTER1-TEXT-PLAN 7.3)도 멈춘다 |
| 다. 이름을 파일에서 빼기 | id만 저장하고 이름은 항상 다시 짓는다. 희귀는 낱말 id를 새로 저장 | 파일에 낡은 글이 남지 않는다 | 장비 키가 바뀌어 스키마 4가 필요하다. 희귀 낱말 id라는 새 필드가 생긴다. 얻는 것이 작다 |

권고는 **가**다. 스키마 4는 D3 서사 기록을 넣을 때 연다. 그때 다의 "이름을 파일에서 빼기"를 다시 볼 수 있다.

### 2.4 수치에도 같은 위험이 있다(이 명세는 규칙과 검사만)

`validate`는 `stats`를 데이터로 다시 계산해 비교한다(259·288행). 그래서 다음을 바꾸면 그 장비를 가진 저장이 거부된다.
- 기본 장비의 `stats`, `level`, `slot`
- 접사의 `stat`, `low`·`high`(범위를 좁힐 때), `level`·`max_level`, `slots`, `group`, `kind`
- 고유의 `stats`·`slot`·`level`, 전설의 `stats`·`slots`·`level`
- `limits`(최소·최대를 좁힐 때), 요구 레벨 공식(`required_level`, 251행)

수치 조정(D1·D2·G1 P5)이 `loot.json`을 건드릴 수 있으므로 지금 막아야 한다.

**규칙(권고, 결정 D-1).** 저장된 장비에 영향을 주는 기존 id의 수치는 바꾸지 않는다. 바꿔야 하면 새 id를 만들고 옛 id는 "더 떨어지지 않음"(드랍 가중 0)으로 남긴다. 범위는 넓히기만 한다.

**지키는 검사.** 고정 장비 묶음 파일 `chapter1/tests/fixtures/loot_compat_items.json`을 만든다. 지금 데이터로 굴린 장비를 등급·칸·접사·전설·고유별로 빠짐없이 담는다(대략 수백 개, 고정 시드). `test_loot.gd`가 그 묶음 전부를 `validate`로 통과시켜야 한다. 데이터를 바꿔 이 검사가 깨지면 그 변경은 사용자 저장을 깨는 변경이다. 묶음 파일을 새로 만들어 검사를 통과시키는 것은 금지한다(목표를 결과에 맞추는 것과 같다). 바꾸려면 디렉터 승인과 이관 설계가 먼저다.

다른 안(규칙 대신 읽을 때 옛 수치를 받아 주는 "기존 장비 보존")은 위조 검사를 약하게 하므로 지금은 권하지 않는다. 6절 D-1에 두었다.

### 2.5 골든과 회귀

- `loot.gd`의 `roll_*`·`_compose`는 바꾸지 않는다. 드랍 결과가 같으므로 **골든 4건과 `sim_loot.gd`의 결과가 그대로여야 한다.** `core/`를 고쳤으므로 골든을 돌려 확인한다(CLAUDE.md 규칙).
- `validate`가 더 많이 받아들이게 되는 것이므로 지금 읽히는 저장은 모두 계속 읽힌다.

---

## 3. (나) 저장이 거부됐을 때

### 3.1 선택지

| 안 | 하는 일 | 쓰는 파일 | 크기 | 장점 | 단점 |
|---|---|---|---|---|---|
| ① 안내 | 무엇이 일어났는지, 원본이 어디 있고 그대로라는 것, 원인 분류 한 줄, [폴더 열기], [게임 종료] | 없음 | S | 무조건 필요하다. 다른 안의 바탕 | 혼자서는 여전히 플레이할 수 없다 |
| ② 저장 없이 플레이 | 이번 실행 동안은 빈 프로필로 플레이하고 아무것도 쓰지 않는다. 결과 창에 "이번 실행은 저장하지 않습니다" | 없음 | S | 원본에 손대지 않으면서 바로 놀 수 있다. 지금의 `--chapter1-profile-off`와 같은 경로라 새 위험이 작다 | 얻은 것이 사라진다. 실수로 이 길로 여러 판을 하면 허탈하다(결과 창마다 알린다) |
| ③ 새 저장으로 시작 | 원본 옆에 새 파일을 만들고 다음 실행부터 그 파일을 쓴다. 원본은 그대로 남는다 | 새 파일 + 가리키는 파일(3.3) | M | 계속 저장하며 놀 수 있다 | 플레이어에게는 진행이 사라진 것처럼 보인다. 파일이 둘이 된다 |
| ③-가 기록본에서 이어 하기 | ③을 고를 때, 거부된 파일 옆의 기록본(`.revision-*.json`) 가운데 **지금 규칙으로 읽히는 가장 최근 것**의 내용을 새 파일의 시작으로 쓴다. 없으면 빈 프로필 | 위와 같음. 기록본은 읽기만 | M(③에 더해 S) | 잃는 것이 가장 적다. 이미 매 저장마다 기록본이 쌓이고 있다 | 기록본도 같은 이유(데이터 변경)로 모두 거부될 수 있다. 몇 판 전으로 돌아간다는 것을 알려야 한다 |
| ③-나 옛 형식만 거부된 경우 | v3 파일이 없고 v2·v1만 거부됐으면 새 v3 파일을 본래 경로(`PATH_V3`)에 만든다. 가리키는 파일이 필요 없다 | `PATH_V3` 새로 만듦. v2·v1은 그대로 | S | 단순하다 | — |

**권고**: 1단계로 ①과 ②를 넣는다(저장 파일을 하나도 쓰지 않는다). 사용자 결정 뒤 2단계로 ③과 ③-가, ③-나를 넣는다.

화면(①의 내용, 자리표 문구. 말투는 결정 D-5):

```
저장 파일을 읽지 못했습니다
원본은 지우거나 고치지 않고 그대로 두었습니다.

위치   C:\Users\…\AppData\Roaming\WitchMoira\chapter-one-profile-v3.json
원인   이 버전의 게임과 맞지 않는 장비 기록이 있습니다   (분류: 3.2)

[ 폴더 열기 ]  [ 저장 없이 플레이 ]  [ 새 저장으로 시작… ]  [ 게임 종료 ]
                                     (2단계, 결정 뒤)
```

- 위치는 `ProjectSettings.globalize_path(path)`. [폴더 열기]는 `OS.shell_open(globalize_path("user://"))`. 열기만 한다.
- 메뉴에서 이 안내가 시작 단추보다 먼저 보인다. 안내를 닫으면 메뉴로 가되 시작 단추는 ②나 ③을 고르기 전까지 같은 안내를 다시 연다(지금처럼 말없이 막지 않는다).
- [새 저장으로 시작…]은 두 번 묻는다. 두 번째 화면에 "원본은 그대로 남습니다 · 지금까지의 진행은 새 저장에 없습니다"(③-가가 기록본을 찾았으면 "N번째 저장(날짜) 상태에서 이어 갑니다").

### 3.2 거부 사유 남기기

지금은 어느 장비의 어느 항목에서 거부됐는지 알 수 없다. 안내와 버그 보고에 필요하다.

- `normalize`·`normalize_v3`에 선택 인수 `reasons_out: Array`를 더한다. 첫 실패의 짧은 사유를 넣는다(예: `"items[12].item: Affix eligibility/range"`, `"characters.chapter1.character.frost: ranks"`, `"json"`, `"size"`). 동작(반환값)은 바꾸지 않는다.
- 프로필에 `reject_reason`(문자열), `reject_kind`(`"damaged"` = JSON 파싱 실패·크기 초과, `"incompatible"` = 형식은 맞는데 검증 실패, `"legacy"` = v2·v1 거부)를 둔다.
- 로그 한 줄: `CHAPTER1_PROFILE_REJECTED {"file":"<파일 이름만>","kind":…,"reason":…,"bytes":…,"sha256_16":…}`. 장비 이름이나 사용자 경로 전체는 찍지 않는다.
- 화면의 원인 한 줄은 `reject_kind`로 고른다: damaged → "파일이 손상됐습니다", incompatible → "이 버전의 게임과 맞지 않는 기록이 있습니다", legacy → "이전 형식의 저장을 옮겨 오지 못했습니다".

### 3.3 ③의 파일 규칙(2단계)

- 새 파일 이름: `chapter-one-profile-v3-r<YYYYMMDD-HHMMSS>.json`. 같은 이름이 있으면 `-2`, `-3`을 붙인다. **이미 있는 파일은 절대 덮어쓰지 않는다.**
- 가리키는 파일: `user://chapter-one-profile-active.json`, 내용 `{"schema":1,"file":"<새 파일 이름>","replaces":"<거부된 파일 이름>","kind":…,"reason":…,"created_unix":…,"from_revision":"<기록본 파일 이름 또는 빈 문자열>"}`. 임시 파일 → 바꿔 끼우기로 쓴다. 이 파일은 게임의 메타데이터라 다음 ③ 때 새로 바꿔 쓸 수 있다. 저장 파일은 아니다.
- `configure`: 가리키는 파일이 있고, `file`이 위 이름 규칙(`^chapter-one-profile-v3-r[0-9-]+\.json$`)에 맞고 `user://` 바로 아래면 그 파일을 쓴다. 규칙에 맞지 않으면 무시하고 본래 경로를 쓴다(경로를 따라가지 않는다: `..`, 절대 경로, 다른 폴더 금지). 지금 `configure`의 "본래 경로만 허용" 검사(75행)는 이 규칙으로 넓힌다.
- 새 파일이 다시 거부되면 같은 흐름(안내 → ②·③)이 그 파일에 대해 다시 돈다. 앞의 파일들은 모두 남는다.
- 기록본에서 이어 하기(③-가): 거부된 파일과 같은 폴더의 `<거부된 파일 이름 바탕>.revision-*.json`을 이름의 리비전 번호 순으로 내림차순 읽고, `normalize_v3(…, false)`를 처음 통과하는 것을 쓴다. 새 파일의 `revision`은 그 값에서 이어 간다. 기록본은 읽기만 한다. 읽은 기록본의 이름을 가리키는 파일의 `from_revision`에 남긴다.
- 옛 형식(v2·v1)은 새 파일로 옮겨 오지 않는다. ③-나의 경우에만 빈 v3을 본래 경로에 만든다.
- QA 모드: `configure(destination, qa=true, …)`에 가리키는 파일 경로 인수를 더하고, 이것도 `res://_local/` 아래만 허용한다.

### 3.4 ②의 동작(1단계)

- 앱의 세션 플래그 `_profile_session_off=true`. 효과는 `--chapter1-profile-off`와 같다: `profile.available`은 거짓으로 남고, 판은 빌드 없이 돈다(`chapter_one.gd` 372~386행의 "프로필 없음" 경로), 결과 창은 저장 비활성 문구를 쓴다(`chapter_hud.gd` 1309~1319행).
- 다른 점: 결과 창과 메뉴의 저장 줄에 "이번 실행은 저장하지 않습니다 · 저장 파일을 읽지 못했습니다"를 쓴다. 검증 실행 문구("검증 실행 · 저장 비활성")와 갈라 쓴다.
- 이 플래그는 실행이 끝나면 사라진다. 다음 실행에서 다시 안내가 뜬다.
- 첫 처치 유니크: 지금 "프로필 없음"일 때는 `first_boss_kill`이 참이 된다(385행). ②에서는 매 판 첫 처치 유니크가 나온다. 저장하지 않으니 해는 없지만, 거짓으로 두는 쪽이 오해가 적다. 구현자가 거짓으로 두고 이유를 적는다.

---

## 4. 지시서

### D5-L — 장비 검증과 프로필(gameplay-systems)

| 항목 | 내용 |
|---|---|
| 시작 조건 | 디렉터가 코어 동결의 예외로 허락했다(전투 코드는 건드리지 않는다). `loot.gd`·`chapter_profile.gd`를 고치는 다른 작업(D3 스키마 4 설계, D2 K2의 드랍 경로)이 돌지 않는다 |
| 고칠 파일 | `chapter1/core/loot.gd`(`validate`, 새 `dress`), `chapter1/core/chapter_profile.gd`(`normalize`의 `dress`, 사유 기록, 1단계에서는 3.3을 넣지 않음), `chapter1/tests/test_loot.gd`, `chapter1/tests/test_chapter_profile.gd`, 새 `chapter1/tests/fixtures/loot_compat_items.json` |
| 건드리지 않을 파일 | `chapter1/data/loot.json`, `chapter1/core/chapter_items.gd`, `roll_*`·`_compose`, 전투 코어 |
| 통과 기준 | 5절 검사 L·P 전부, `run_all.py` 전체 통과(골든 4건 불일치 0, loot-sim 결과 불변) |

### D5-A — 앱(gameplay-systems, D4-A와 같은 담당이 차례로)

| 항목 | 내용 |
|---|---|
| 시작 조건 | D5-L 끝. D4-A와 동시에 하지 않는다(둘 다 `start_run` 부근). T1 지시서 4 R1·R4와 동시에 하지 않는다 |
| 고칠 파일 | `chapter1/app/chapter_one.gd` |
| 할 일 | (1) 367행의 말없는 막힘을 안내 열기로 바꾼다. (2) ② 세션 플래그(3.4). (3) 388행의 `quit(1)`을 N7 처리로. (4) 거부 로그 한 줄(3.2). (2단계) ③ 흐름과 `configure`의 가리키는 파일 읽기 연결 |
| 통과 기준 | 5절 H 전부 |

### D5-U — 안내 화면(ui-hud)

| 항목 | 내용 |
|---|---|
| 시작 조건 | D4-U와 동시에 하지 않는다. A2 지시서 2-B·3-B·4·5, T1 지시서 4 R4와 동시에 하지 않는다 |
| 고칠 파일 | `chapter1/view/hud/chapter_hud.gd`(안내 패널, 신호 `profile_open_folder`, `profile_play_without_save`, `profile_start_fresh`), `chapter1/tests/hud_dump.gd`(선택 인수 추가만) |
| 할 일 | 3.1의 화면. 메뉴 위에 뜨는 창, A2 지시서 1의 색·글자 토큰, 키보드 초점, 기본 초점은 [저장 없이 플레이](파일을 쓰지 않는 쪽). 2단계의 두 번 묻기 |
| 통과 기준 | 5절 H-4·H-5, 1080p·720p 겹침·잘림 없음, 글자 14 이상 |

---

## 5. 검사

**격리 규칙(모든 검사).** `Profile.configure(path, true, …)`만 쓰고 `path`는 `res://_local/` 아래다. `run_all.py`는 `--fixture-dir=res://_local/run-all-fixtures/<시각>`을 넘기고 검사는 그 폴더가 새것인지 먼저 본다(`test_chapter_profile.gd` 111~113행). 검사는 `configure()`를 인수 없이(제품 경로로) 부르지 않는다. 지금 있는 "제품 경로는 `user://`" 확인(115행)을 그대로 둔다. `hud_dump.gd`는 늘 `--chapter1-profile-off`와 함께 돌고, 프로필은 `res://_local/shots/ui-g1p4/profiles/` 아래 격리 파일만 쓴다.

### 5.1 `test_loot.gd`에 더할 것

| # | 검사 |
|---|---|
| L-1 | 고정 시드로 등급 다섯 × 칸 여덟을 1,000개 굴린 모든 장비에서 `dress(item).name == item.name`, `dress(item).description == item.description`(희귀 포함). 다시 짓기가 굴림과 같은 이름을 만든다 |
| L-2 | 굴린 장비의 이름·설명을 아무 글(빈 설명, 160자 이름, 한 낱말 희귀 이름, 세 낱말 희귀 이름)로 바꿔도 `validate`가 빈 배열 |
| L-3 | 이름이 문자열이 아님, 161자, 빈 이름, 설명 301자, 제어 문자 → 거부 |
| L-4 | 수치 위조는 여전히 거부: 접사 값 범위 밖, 모르는 접사 id, 고유의 `stats` 하나 변경, 전설 id를 다른 칸의 것으로, `required_level` 변경 |
| L-5 | 고유 장비의 이름을 바꿔 넣은 것을 `dress`하면 데이터의 이름·설명으로 돌아온다 |
| L-6 | `fixtures/loot_compat_items.json`의 모든 장비가 `validate` 통과(2.4) |
| L-7 | 데이터 사본의 이름을 바꾸면 그것이 반영된다: `loot.json`을 읽어 접두 하나·기본 하나·고유 하나의 `name`을 바꾼 사본을 `res://_local/<검사 폴더>/loot-renamed.json`에 쓰고 `load_file(그 경로)`로 읽은 테이블에서, 원래 데이터로 굴린 장비가 `validate`를 통과하고 `dress`가 새 이름을 돌려준다. 사본은 `_local`에만 쓴다 |

### 5.2 `test_chapter_profile.gd`에 더할 것(`--fixture-dir` 아래 하위 폴더 `d5/`)

| # | 검사 |
|---|---|
| P-1 | 정상 프로필을 저장한 뒤 파일 안의 고유 장비 이름·설명, 마법 장비 이름, 희귀 이름을 다른 글로 바꿔 쓴 파일 → `configure` 성공. 메모리의 고유·마법 이름은 지금 데이터 값, 희귀는 바꾼 글 그대로. **파일 바이트는 읽기 전후 같다** |
| P-2 | P-1 뒤 한 번 저장(`unselect` 등) → 본 파일의 고유·마법 이름이 지금 데이터 값. 새 기록본이 생기고, 그 전의 기록본들은 바이트가 그대로 |
| P-3 | P-1의 파일에서 장비 하나의 `stats`를 바꾸면 거부. 원본 바이트 그대로, `available` 거짓, `reject_kind=="incompatible"`, `reject_reason`이 그 장비의 위치를 가리킨다 |
| P-4 | JSON이 깨진 파일 → `reject_kind=="damaged"`. 200만 자 초과 → `"damaged"`. v3 없음 + v2 거부 → `"legacy"`. 모두 원본 바이트 그대로, 폴더에 새 파일이 생기지 않는다(폴더 목록 전후 비교) |
| P-5 | 출발 장비에 옛 이름이 붙은 프로필 → `starting_gear()`가 새 이름의 장비를 주고 `import_starting_gear`가 참 |
| P-6(2단계) | 거부된 본 파일 + 기록본 셋(가장 최근 것은 거부, 그 앞은 통과, 더 앞도 통과) → `start_fresh_after_reject(true)`가 두 번째로 최근 것의 상태로 새 파일을 만든다. revision이 이어진다. 가리키는 파일이 새 이름을 가리킨다. 본 파일과 기록본 셋의 바이트 그대로 |
| P-7(2단계) | 같은 폴더를 새 `Profile`로 다시 `configure` → 가리키는 파일을 따라 새 파일을 읽는다. 본래 경로는 여전히 거부 상태 그대로 |
| P-8(2단계) | 가리키는 파일의 `file`이 `../x.json`, 절대 경로, 다른 이름 규칙 → 무시하고 본래 경로를 읽는다. 가리키는 파일은 바뀌지 않는다 |
| P-9(2단계) | 기록본이 모두 거부 → 빈 프로필로 새 파일. 이미 같은 이름의 새 파일이 있으면 `-2`로 만들고 있던 파일은 그대로 |
| P-10(2단계) | v3 없음 + v2 거부 → 새 빈 v3이 본래 경로에 생기고 v2 바이트 그대로, 가리키는 파일 없음 |

### 5.3 앱·화면(`hud_dump.gd` 선택 인수, ui-hud가 더함)

| 인수 | 하는 일 | 덤프 시점 |
|---|---|---|
| `--profile-fixture=rejected` | `res://_local/shots/ui-g1p4/profiles/<태그>.json`에 검증에 실패하는 v3 파일(장비 `stats` 변조)을 쓰고 `view.profile.configure(그 경로, true)`로 읽힌 뒤, 검사 도구가 `view._profile_off=false`로 바꿔 앱이 "거부됨" 경로를 타게 한다(격리 파일이므로 안전). 그 뒤 [저장 없이 플레이]를 누르고 판을 120틱 돈다 | `profile-rejected-menu`, `profile-rejected-nosave-playing-120` |
| `--profile-fixture=renamed` | 정상 저장 뒤 장비 이름만 바꾼 파일(P-1과 같은 것) | `menu`(시작이 막히지 않음), `stash`(새 이름) |

### 5.4 통과 기준(앱·화면)

| # | 기준 |
|---|---|
| H-1 | `renamed`: 메뉴에서 시작이 된다. 보관함 덤프의 고유 장비 이름이 지금 데이터 값이다 |
| H-2 | `rejected`: 첫 덤프에 안내 창이 있고 위치·원인 줄이 보인다. [저장 없이 플레이] 뒤 판이 돈다. 실행 전후로 격리 폴더의 파일 목록과 각 파일의 sha256이 같다(검사 도구가 시작과 끝에 찍는다) |
| H-3 | `rejected` 실행에서 결과 창까지 가는 짧은 판(`--result-mock`과 함께)의 저장 줄이 "이번 실행은 저장하지 않습니다…"다 |
| H-4 | 1080p·720p 캡처에서 안내 창의 겹침·잘림이 없고 긴 경로가 말줄임 또는 줄바꿈으로 창 안에 든다 |
| H-5 | 키보드만으로 안내 창의 모든 단추를 고를 수 있다. 기본 초점은 [저장 없이 플레이] |
| H-6 | 출발 장비 불러오기 실패를 흉내 낸 실행(검사 도구가 `starting_gear` 결과를 깨뜨림)에서 게임이 꺼지지 않고 알림 뒤 장비 없이 시작한다 |
| H-7 | `python tools/dev/run_all.py` 전체 통과(골든 4건 불일치 0, loot-sim 결과 불변), 실행 로그 스크립트 오류 0 |

명령(저장소 루트, `godot`는 CLAUDE.md의 경로):

```powershell
python tools/dev/run_all.py --only loot,profile
python tools/dev/run_all.py
godot --headless --fixed-fps 60 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --profile-fixture=renamed --profile-tag=d5-renamed --dump=_local/d5/renamed.json
godot --headless --fixed-fps 60 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --profile-fixture=rejected --profile-tag=d5-rejected --dump=_local/d5/rejected.json
godot --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/hud_dump.gd -- --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --profile-fixture=rejected --profile-tag=d5-cap720 --shots=_local/d5/shots-720 --dump=_local/d5/cap-720.json
```

---

## 6. 결정할 것

### 사용자가 정할 것

| # | 결정 | 선택지 | 권고 |
|---|---|---|---|
| U-1 | ③ 새 저장으로 시작을 게임에 넣을지 | 넣는다 / 넣지 않는다(①②만, 복구는 사람이 파일을 보고 한다) | 넣는다. 남에게 보여 줄 판에서 플레이어가 파일을 만질 수는 없다 |
| U-2 | ③-가 기록본에서 이어 하기를 허락할지 | 허락 / 늘 빈 프로필로 시작 | 허락. 이미 쌓이고 있는 기록본을 읽기만 한다. 몇 판 전으로 돌아간다는 것을 확인 화면에서 알린다 |
| U-3 | ② 저장 없이 플레이를 허락할지 | 허락 / 안내만 하고 막음 | 허락. 원본을 건드리지 않으면서 막힘을 없애는 가장 작은 길이다 |
| U-4 | 안내 문구의 말투와 어디까지 보여 줄지(파일 전체 경로를 보여도 되는지) | 전체 경로 / 폴더 이름만 | 전체 경로. 사용자가 직접 찾을 수 있어야 한다. 경로에 사용자 이름이 들어간다는 점만 알아 둔다 |

### 디렉터가 정할 것

| # | 결정 | 권고 |
|---|---|---|
| D-1 | 수치의 데이터 규칙(2.4: 기존 id의 수치는 바꾸지 않고 새 id로. 범위는 넓히기만)과 호환 고정 묶음 검사를 받아들일지. 다른 안은 읽을 때 옛 수치를 받아 주는 것(위조 검사가 약해짐) | 규칙 + 검사 |
| D-2 | 스키마 3 유지(2.3 가) | 유지. 스키마 4는 D3 서사 기록 때 |
| D-3 | `loot.gd`·`chapter_profile.gd`·`chapter_one.gd` 수정을 코어 동결의 예외로 둘지. 전투 코드는 건드리지 않는다 | 예외로 둔다. 이름 정리(CHAPTER1-TEXT-PLAN 7.3)와 수치 조정(D1·D2·G1 P5)이 모두 이것을 기다린다 |
| D-4 | 트리 이름만 바꿀 때 revision을 올리지 않는다는 규칙(N9)을 데이터 담당에게 지시할지 | 지시한다 |
| D-5 | 1단계(①②, N7)와 2단계(③)를 나눌지 | 나눈다. 1단계는 사용자 결정 없이 진행할 수 있다(U-3이 "막음"으로 나오면 ②만 뺀다) |

---

## 7. 순서와 다른 지시서와의 관계

| 파일 | 이 명세 | 겹치는 것 | 규칙 |
|---|---|---|---|
| `core/loot.gd` | D5-L | D2(드랍 경로 K2는 `chapter_core.gd`, `loot.json`의 `elite` 표), 이름 정리(CHAPTER1-TEXT-PLAN 7.3, `loot.json`) | **이름 정리는 D5-L이 끝난 뒤에만.** D2의 `loot.json` 수정은 D-1 규칙을 따른다 |
| `core/chapter_profile.gd` | D5-L(2단계 ③) | D3 1.1 스키마 4, (제안) 설정 저장 | D5가 먼저. 스키마 4 설계는 D5의 사유 기록·가리키는 파일 규칙 위에서 한다 |
| `app/chapter_one.gd` | D5-A | D4-A, T1 지시서 4 R1·R4 | 같은 담당이 D4-A → D5-A(또는 반대) 차례로. 동시 금지 |
| `view/hud/chapter_hud.gd` | D5-U | D4-U, A2 2-B·3-B·4·5, T1 지시서 4 R4 | 동시 금지. D4-U와 같은 묶음으로 ui-hud가 차례로 하는 것을 권한다 |
| `tests/test_chapter_profile.gd`, `tests/test_loot.gd` | D5-L | D2 K5(`report_run_loot.gd`는 다른 파일), D3 | 동시 금지 |

권하는 순서: **D5-L → (D4-A·D5-A, 같은 담당이 차례로) ∥ (D4-U·D5-U, ui-hud가 차례로) → 사용자 결정 U-1·U-2 → 2단계 ③.** 성능 작업(T2)과 파일·측정 창이 겹치지 않는다.

## 8. 확인하지 못한 것

- Godot를 실행하지 않았다. `loot.json`에 지금 고유·전설·희귀 이름이 몇 개인지, 사용자 저장에 장비가 몇 개 있는지 보지 않았다(사용자 폴더는 열지 않는다).
- `_compose`가 일반 장비에 설명을 빈 문자열로 주는 것을 코드로 읽었다(141행). 지금 저장의 일반·마법 장비 설명이 모두 빈 문자열인지는 L-1이 확인한다.
- 사용자 폴더에 기록본이 실제로 몇 개 쌓여 있는지 모른다. 많다면 ③-가의 읽기 시간과 기록본 정리 정책(지우지 않는 규칙 아래에서의 용량)이 따로 문제가 된다. 정리는 이 명세에 넣지 않았다. 지우는 일은 사용자 승인 없이는 하지 않는다.
- `OS.shell_open`이 Windows 탐색기를 여는 것은 엔진 문서에 기대어 적었다. 실제로 열어 보지 않았다.
