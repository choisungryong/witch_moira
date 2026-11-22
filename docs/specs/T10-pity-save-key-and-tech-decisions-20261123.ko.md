# T10 — 드랍 천장의 저장 키와 지시서, 걸음 측정의 허용치, 새 작업 트리에서 실패하는 검사

작성: tech-lead, 2026-11-23. 기준: main `d263c72` + 본 저장소 작업 트리(디렉터가 T1-B·R1-B·D23 데이터 손질을 얹는 중). 구현하지 않은 지시서다.
번호 주의: 이 문서의 "T10"은 tech-lead 지시서의 차례 번호다. D23 과제표·D25의 "T10(상점·도박)"과는 다른 것이다.

표시: **[봄]** 코드·파일에서 직접 확인 · **[돌림]** 이번에 실행해 확인 · **[짐작]** 확인하지 않은 추정 · **(모델의 답)** 계산 결과.

받는 명세:
- 1절: D23 3.10(천장), 3.14(`pity` 데이터 꼴), 3.15(저장 호환 표의 천장 키), 3.16(천장 지표), 과제표 T9. 사용자 확정 D23 6.1 U2 = (b) "5판 연속이면 다음 우두머리가 전설 보장"(장부 U-81). D25 6절(드랍 천장 키는 tech-lead가 정한다).
- 2절: T9 3.6(허용치 [짐작]), B1-b 보고(`_local/t9-b1b/REPORT.txt`), 디렉터가 전한 작업 트리 실패.

---

## 0. 결정 한눈

| # | 결정 | 다섯 사상 |
|---|---|---|
| 1-1 | 키는 `town.luck.drop_runs_since_legendary`(계정 하나, 정수 0~1,000,000). **스키마 번호 5 그대로**, 이 키는 **선택 키**: 없으면 0으로 읽고, 천장이 켜진 뒤 처음 셀 때 생긴다. 꺼진 동안 저장 꼴은 한 바이트도 바뀌지 않는다 | 보상 |
| 1-2 | 세는 규칙: 판 끝 저장(`record_run`)에서 **새로 얻은 장비 가운데 전설·고유가 있으면 0**, 없고 **승리(우두머리 처치)면 +1**, 패배·포기는 그대로. 시험판·검증 실행(프로필 꺼짐)·"저장 없이 하기"는 건드리지 않는다 | 보상, 도박(조작으로 천장을 사지 못하게) |
| 1-3 | 코어는 저장을 모른다. 앱이 판 시작 전에 숫자 하나 `run.drop_dry_runs`를 넣고, 코어가 `loot.json`의 `pity`로 "이번 판 우두머리 첫 보장 줄을 전설로"를 정한다 | — |
| 1-4 | 결정론: 천장이 걸린 판만, **우두머리 첫 보장 줄부터** `_loot_rng`의 소비가 달라진다. 그 앞의 모든 굴림은 같다. 꺼짐·0이면 골든 불변. 켠 경로 골든 일곱째 건을 더한다 | — |
| 2-1 | 걸음 측정의 미끄러짐은 **화면이 같은 조건에서 잰 값과의 차로만** 판정한다(절대 0.15 m/s). 계산값과는 견주지 않는다(게임 안 측정에 디딤 흔들림 바닥이 있어서). 화면 값이 없으면 미끄러짐은 "판정 안 함"(종료 코드 3). 배율은 2% 그대로 | — |
| 2-2 | `test_motion_verify.py`는 git 밖 파일을 읽지 않게 고친다(작은 고정 보고서 + `--report` 인수). "없으면 건너뜀"은 택하지 않는다 | — |
| 2-3 | `test_audio_tools.py`의 첫 실패는 임시 폴더 겹침이 아니다(폴더는 실행마다 `mkdtemp`). 자식 도구가 실패했는데 종료 코드를 보기 전에 결과 파일을 열어 원인이 `FileNotFoundError`로 가려진 것. 고치는 길: 종료 코드를 먼저 보고 자식의 출력 꼬리를 남긴다 | — |

사용자에게 물을 것: 없음.

---

## 1. 드랍 천장(D23 T9)

### 1.1 코드에서 본 지금 [봄]

- 스키마 번호는 **5**다: `chapter_profile.gd` 2행 머리글, 21행 `PATH_V5 := "user://chapter-one-profile-v5.json"`, 189행 `default_state`의 `"schema_version":5`, 796행 검증 `Catalog.integer(value.schema_version,5,5)`. 4·3·2·1은 읽기만 한다(10행). **`CLAUDE.md`의 "스키마 3, `chapter-one-profile-v3.json`"은 낡았다**(디렉터가 고칠 것, 5절).
- `town.luck`은 이미 있다: 50행 `TOWN_KEYS`, 52행 `LUCK_KEYS := ["gamble_since_legendary","forge_fails_in_row"]`, 195행 `default_town()`.
- 읽기는 **키 집합이 정확히 같아야** 통과한다: 1127~1128행 `Catalog.keys_match(luck,LUCK_KEYS)`(`growth_catalog.gd:17`, 크기와 키가 모두 같아야 참). 그러므로 `LUCK_KEYS`에 키를 그냥 더하면 **지금 사용자의 스키마 5 파일이 모두 "town luck"으로 거절된다**. D25 6절이 "꼴 변경"이라 적은 것이 이것이다.
- 판 끝 저장은 `record_run`(1392행) 한 곳이다. 승패와 상관없이(`_save_terminal`, `chapter_one.gd:653`) 불리고, 포기는 패배와 같은 길(`abandon_run` → `run.abandon()` → mode "defeat", `combat_core.gd:220`)이다. 새 장비는 `storage_id`가 없는 것(1427~1438행)이다.
- 판 시작 전에 앱이 코어에 값을 넣는 선례: `run.first_boss_kill`(`chapter_one.gd:478~480`), `run.opening_first_visit`(460행). 둘 다 `start()`가 지우지 않는다.
- 시험판 인수(`--chapter1-trial=`)는 `--chapter1-profile-off`와 함께일 때만 켜진다(`chapter_one.gd:386`). 그러므로 시험판은 저장 자체가 없다.
- 우두머리 전리품: `chapter_core.gd:1094~1096` — 첫 처치면 `boss_first_kill`(고유 보장)을 먼저, 그다음 `roll_class(_loot_rng,"boss",level,primary_)`. `boss` 등급은 `guaranteed:["rare"]`, 5개, 우두머리 레벨 = 12+3 = 15. 전설 정의 셋은 모두 레벨 4(`loot.json` `legendaries`) → 우두머리에서 전설이 비는 일은 없다.
- `loot.gd:roll_item`에서 `quality=="legendary"`는 전설 하나를 `randi_range`로 고르고 칸도 그 전설의 칸에서 고른다(396~403행). 희귀는 칸을 가중으로 고른다. 그래서 **등급을 올리면 그 뒤 난수 소비가 달라진다**.
- `sim_loot.gd`는 이미 가뭄 지표(`legend_unique_drought.longest_dry_runs`)와 D23 3.16의 "≤5" 줄을 갖고 있고, 지금은 "no pity in the core"로 적는다.

### 1.2 키 — 이름, 자리, 기본값, 옛 저장

| 항목 | 결정 | 까닭 |
|---|---|---|
| 이름·자리 | `town.luck.drop_runs_since_legendary` | D23 3.10·3.15, D25 6절이 이미 이 이름으로 적었다. 도박 천장(`gamble_since_legendary`)과 나란히, 계정 하나 |
| 값 | 정수 0~1,000,000 | 다른 셈과 같은 꼴(`records.runs`의 상한 1e9보다 작게, 넘치면 상한에서 멈춤) |
| 기본값 | **키 없음 = 0** | 꺼진 동안 꼴 불변 |
| 읽기 | `luck`의 키가 `LUCK_KEYS`(둘) 또는 `LUCK_KEYS` + `drop_runs_since_legendary`(셋)이면 통과. 셋째 키는 0~1,000,000 정수. 다른 키가 있거나 범위 밖이면 지금처럼 "town luck" 거절 | 지금 파일(둘)과 새 파일(셋) 모두 읽힘 |
| 쓰기 | 읽은 그대로 돌려 쓴다(키가 없던 파일은 없는 채로). 키는 1.3의 규칙이 **처음 값을 정할 때** 생기고, 그 뒤로는 0이어도 남는다 | 천장을 켜기 전에는 어떤 쓰기도 꼴을 바꾸지 않음 |
| `default_town()` | 바꾸지 않는다(둘) | 새 파일·4→5 이전 결과도 꼴 불변 |
| 스키마 번호 | **5 그대로**. 올리지 않는다 | 더하는 선택 키 하나다. 6으로 올리면 이름(`-v6.json`)·포인터·일지·옛 파일 읽기 사슬이 한 벌 더 생긴다. D23 3.15의 "앞으로만 호환" 원칙 안 |
| 옛 실행 파일 | 셋째 키가 생긴 파일을 이 변경 전의 실행 파일이 열면 "town luck"으로 거절한다(파일은 지우지 않고 거절 창이 뜸). 앞으로만 호환하면 된다는 D23 3.15의 결정을 따른다. 천장을 켜기 전까지 이 일은 생기지 않는다 | — |
| 일지 사본(`revisions/`) | 같은 꼴. 따로 할 일 없음 | — |

### 1.3 언제 세고 언제 0으로

`record_run`에 선택 인수 `drop_pity: bool = false`를 아홉째로 더한다. `false`면 지금과 한 글자도 다르지 않다(키를 읽지도 쓰지도 않음).
`true`일 때, 같은 원자적 쓰기(`_persist`) 안에서:

1. 이 판에서 **새로 받은 장비**(1427행 고리의 `not is_stored`, 가방과 `pending` 모두) 가운데 `quality`가 `legendary` 또는 `unique`가 하나라도 있으면 → **0**.
2. 아니고 `victory`이면 → **+1**(1,000,000에서 멈춤).
3. 아니면(패배·포기) → **그대로**.

| 경우 | 셈 | 까닭 |
|---|---|---|
| 우두머리를 잡고 전설·고유 없음 | +1 | 가뭄의 정의. 판 수는 "우두머리까지 간 판"만 센다 |
| 패배·포기, 전설·고유 없음 | 그대로 | **빨리 죽거나 포기해서 천장을 채우는 길을 막는다**(30초짜리 판 다섯으로 전설 하나를 사지 못하게). 도박이 진짜 도박이게 |
| 패배·포기인데 전설·고유를 주워 왔음 | 0 | 본 것이다 |
| 첫 처치 고유(`boss_first_kill`) | 0 | 고유다 |
| 바닥에 두고 온 전설 | 셈에 안 들어감 | "본 것" = 저장에 들어온 것. 코어 이벤트가 아니라 결과로 센다 |
| 도박으로 산 전설(D25) | 이 셈과 무관 | 도박은 `gamble_since_legendary`가 따로 센다 |
| 같은 영수증 두 번(`receipt in state.receipts`) | 아무것도 안 함 | 지금의 이중 지급 막기(1394행)가 그대로 막는다 |
| `record_run`이 실패(보관함 가득 등) | 안 바뀜 | 같은 원자적 쓰기 |
| 프로필 꺼짐(`--chapter1-profile-off`), "저장 없이 하기"(`_profile_session_off`), 시험판 | 읽지도 쓰지도 않음 | 저장이 없다. 시험판은 프로필 꺼짐에서만 켜진다 |
| `pity.enabled:false`(데이터) | 앱이 `drop_pity=false`로 부름 | 꼴 불변 |

천장이 걸린 판(1.4)에서 우두머리를 잡으면 보장 줄이 전설이므로 1번에 걸려 0이 된다. 천장이 걸린 판에서 우두머리 전에 지면 셈은 그대로라 다음 판도 걸린다.
천장을 켜기 전에 쌓인 가뭄은 세지 않는다(켠 뒤부터 0에서 센다). 이것은 받아들인다.

### 1.4 판 시작에 코어로 가는 길

- 코어(`chapter_core.gd`)에 공개 필드 `var drop_dry_runs := 0`. 앱이 `start()` 전에 넣는다(`first_boss_kill`과 같은 자리, `chapter_one.gd:478` 근처). `start()`는 지우지 않는다(새 판마다 앱이 `ChapterRun.new()`를 만든다, `return_to_menu`).
- 앱: `profile.available and not _profile_session_off and run.loot.pity_on()`일 때만 `run.drop_dry_runs = int(profile.town_view().luck.get("drop_runs_since_legendary",0))`, 그리고 판 끝의 `record_run(..., drop_pity=true)`. 그 밖에는 0과 `false`.
- 걸림 판정은 **코어가** 한다: `loot.pity_on() and drop_dry_runs >= loot.pity_runs()`(`pity.runs_without_legendary`, 지금 5). 판 시작 때 한 번 정해 `_pity_armed`에 둔다. 판 중간에 바뀌지 않는다(판 시작 스냅숏).
- `loot.gd`: `pity` 블록(D23 3.14의 꼴 `{"enabled":false,"runs_without_legendary":5,"upgrade":"first_guaranteed_to_legendary"}`)을 선택 블록으로 읽고 검사한다(`enabled` bool, `runs_without_legendary` 정수 1~50, `upgrade`는 그 한 낱말만). 없으면 꺼짐. 읽기 함수 `pity_on() -> bool`, `pity_runs() -> int`. 시험용 `set_pity(enabled: bool) -> bool`(`set_affix_rolls`와 같은 꼴, 데이터 파일은 쓰지 않음).
- `roll_class`에 선택 인수 `first_quality: String = ""`를 **맨 끝에** 더한다. 비어 있으면 지금과 같다. `"legendary"`이고 `pick == 0`이고 `guaranteed[0] == "rare"`이면 그 줄의 등급을 `legendary`로 굴린다(`roll_item(rng,level,"legendary","",weights,lines_profile)`). 결과가 전설이 아니면(전설 정의가 그 레벨에 없을 때) 그대로 두고 아래 이벤트를 내지 않는다.
- 코어 `_maybe_drop_item`(1096행): `boss`일 때만 `first_quality = "legendary" if _pity_armed else ""`. 수호자에는 걸지 않는다. 결과의 그 줄이 전설이면 `_pity_fired = true`와 이벤트 `drop_pity {uid, item_id}`(위치는 우두머리 자리). 화면은 이 이벤트로 한 줄을 띄운다(말은 narrative-lead, D23 3.10).
- 스냅숏: `_pity_armed`가 참인 판에서만 `result.chapter.pity = {"armed":true,"fired":<bool>}`. 걸리지 않은 판은 키가 없다(골든 불변).
- `boss_g1~g4`는 지금 코어가 굴리지 않는다 [봄: `grep boss_g chapter1/core` 없음]. 나중에 쓰게 되면 같은 인수를 넘긴다(이 지시서의 범위 밖, 메모만).

### 1.5 결정론과 골든

- 천장이 걸리지 않은 판(꺼짐, 프로필 꺼짐, 셈 < 5): `roll_class`의 새 인수가 비어 있어 난수 소비가 한 번도 달라지지 않는다 → **기존 골든 여섯 건 불변**이 끝난 기준이다.
- 걸린 판: `boss_first_kill`까지와 그 앞의 모든 굴림은 같다. 우두머리 첫 보장 줄에서 희귀 대신 전설을 굴리므로(전설 고르기 1회 + 칸 고르기 1회, 줄 수가 다름) 그 뒤 `_loot_rng`가 달라진다. 우두머리 처치는 판의 끝이므로 실제로 달라지는 것은 우두머리 전리품 다섯과 그 뒤 몇 틱이다.
- 굴림을 "희귀로 굴린 뒤 등급만 바꾸기"로 하지 않는다(전설 정의와 칸이 맞지 않는 장비가 나와 `validate`의 "Legendary identity"에 걸린다).
- **켠 경로 골든 일곱째 건**: `[11,"chapter1.skill.frost","pity-armed","","pity-armed"]`. 준비: 그 판 전용 loot 표에서 `set_pity(true)`(affix-on 건과 같은 방식, `tests/support/trial_docs.gd`에 `enable_pity_problem(run)`), `run.drop_dry_runs = 5`. 그 건의 끝 스냅숏에 `chapter.pity.fired == true`이고 가방에 전설이 있는지를 골든 도구가 아니라 `test_chapter_run.gd`의 검사로 본다(골든은 해시만).

### 1.6 지시서 — gameplay-systems (그대로 전달)

**목표**: D23 3.10의 드랍 천장을 꺼진 스위치로 넣는다. 사용자 결정(D23 6.1 U2, 장부 U-81): "전설·고유를 못 본 판이 5판 이어지면 다음 판 우두머리의 보장 첫 줄이 전설". 키우는 것: **보상**(긴 가뭄의 끝을 보장), **도박**(가뭄을 사는 꼼수를 막아 굴림이 진짜이게).

**먼저 읽을 것**: 이 문서 1.1~1.5. `docs/specs/D23-d2r-lessons-and-affix-probability-20261122.ko.md` 3.10, 3.14(`pity` 꼴), 3.15, 3.16. `chapter1/core/chapter_profile.gd` 1~60행, 186~196행, 1105~1131행(`_read_town`), 1380~1450행(`record_run`), 1690~1702행. `chapter1/core/loot.gd` `roll_item`·`roll_class`·`set_affix_rolls`. `chapter1/core/chapter_core.gd` 1087~1100행. `chapter1/app/chapter_one.gd` 450~500행, 653~670행. `chapter1/tests/golden_core.gd` 머리와 `CASES`, `chapter1/tests/support/trial_docs.gd`의 `enable_affix_rolls_problem`. `chapter1/tests/sim_loot.gd`의 가뭄 지표.

**고칠 파일(이 밖은 건드리지 않음)**:
- `chapter1/core/chapter_profile.gd`: `LUCK_KEYS`는 그대로 두고 선택 키 상수 하나(`LUCK_OPTIONAL := ["drop_runs_since_legendary"]`), `_read_town`의 luck 검사(둘 또는 셋), 돌려주는 사전에 셋째 키를 **읽은 파일에 있을 때만** 넣기, `record_run`의 아홉째 인수 `drop_pity`와 1.3의 규칙, 머리글 주석 한 줄.
- `chapter1/core/loot.gd`: `pity` 블록 읽기·검사, `pity_on()`, `pity_runs()`, `set_pity()`, `roll_class`의 `first_quality` 인수.
- `chapter1/core/chapter_core.gd`: `drop_dry_runs`, `_pity_armed`(start에서 정함), `_pity_fired`, `_maybe_drop_item`의 우두머리 줄, 이벤트 `drop_pity`, 스냅숏의 `chapter.pity`(걸린 판만).
- `chapter1/app/chapter_one.gd`: `start_run`에서 `drop_dry_runs` 넣기(1.4의 조건), `_save_terminal`에서 `record_run(..., carry, {}, drop_pity)`(지금 여덟째 인수 `outcome`을 넘기지 않으므로 `{}`를 명시해 자리를 맞춤).
- `chapter1/data/loot.json`: 맨 끝에 `"pity": {"enabled": false, "runs_without_legendary": 5, "upgrade": "first_guaranteed_to_legendary"}` 한 블록만(다른 줄 바이트 불변).
- `chapter1/tests/test_chapter_profile.gd` 또는 `test_profile_v5.gd`(이미 town을 보는 쪽), `chapter1/tests/test_loot.gd`, `chapter1/tests/test_chapter_run.gd`, `chapter1/tests/golden_core.gd`(일곱째 건), `chapter1/tests/support/trial_docs.gd`(`enable_pity_problem`), `chapter1/tests/sim_loot.gd`(`--pity=on`), 골든 json 둘(일곱째 건만 더함).

**지킬 계약**:
1. `pity.enabled:false`(배포 값)에서: 골든 여섯 건 해시 불변, `sim_loot --runs=10000`의 `LOOT_SIM` 줄이 바꾸기 전과 글자 단위로 같음, **저장 파일의 바이트 꼴 불변**(키가 생기지 않음), `record_run`을 `drop_pity` 없이 부르는 모든 호출이 지금과 같은 결과.
2. 지금의 스키마 5 파일(luck 키 둘)과 셋째 키가 있는 파일이 모두 읽힌다. 셋째 키가 범위 밖·정수 아님·다른 이름이면 거절(지금의 "town luck"과 같은 길). 스키마 번호와 파일 이름은 바꾸지 않는다.
3. 코어는 저장 파일·프로필 객체를 읽지 않는다. 숫자 하나(`drop_dry_runs`)만 받는다.
4. 천장이 걸리지 않은 판에서 `_loot_rng`·`_spawn_rng`·다른 난수 흐름의 소비가 바뀌지 않는다. 걸린 판에서 바뀌는 곳은 우두머리 첫 보장 줄부터다.
5. `assert()` 안에 부작용 금지. 표현 파일은 건드리지 않는다(화면 한 줄은 ui-hud가 이벤트를 받아 나중에).
6. 사용자 저장(`%APPDATA%\WitchMoira`)을 읽거나 쓰는 검사 금지. 저장 검사는 `_local/` 격리 경로와 기존 고정 파일만.

**검사(새로 더할 것)**:
- 프로필: (가) luck 키 둘인 파일 읽기 → 꼴 그대로 다시 쓰기(바이트 비교) (나) 셋째 키 3인 파일 읽기 (다) 셋째 키 −1, 1,000,001, `"3"`, 모르는 넷째 키 → 각각 거절 (라) `drop_pity=false`면 키가 생기지 않음 (마) `drop_pity=true`: 승리·전설 없음 → 1, 다시 → 2 / 패배·전설 없음 → 그대로 / 패배·고유 있음 → 0 / 승리·전설 있음 → 0 / 이미 가방에 있던(저장된) 전설만 있는 판 → 0이 아니라 규칙대로(새 것이 아니므로 세지 않음) / 같은 영수증 두 번 → 한 번만 / 1,000,000에서 멈춤 (바) 4→5 이전 결과에 키 없음.
- loot: `pity` 블록 없음·꺼짐·잘못된 꼴(거절), `roll_class(...,"legendary")`가 `boss`의 첫 줄을 전설로, 다른 줄과 `champion`은 그대로, `first_quality` 빈 값의 굴림이 인수 없는 굴림과 같은 시드에서 같은 결과(배열 비교).
- 코어: 걸림 판정(4 → 안 걸림, 5 → 걸림, 꺼짐이면 9여도 안 걸림), 걸린 판의 우두머리 첫 줄이 전설·`drop_pity` 이벤트·스냅숏 `chapter.pity`, 안 걸린 판의 스냅숏에 `pity` 키 없음, 걸린 판에서 우두머리 전까지의 스냅숏 해시가 안 걸린 판과 같음(같은 시드, 우두머리 처치 직전 틱).
- `sim_loot --pity=on`: 판마다 셈을 이어 가며(시뮬레이터의 판은 모두 승리로 본다, 그렇게 출력에 적음) 5판 가뭄 뒤 판의 우두머리 굴림에 `first_quality="legendary"`. 출력에 `pity_fired_runs`(판 비율)와 `longest_dry_runs`. 켬이면 `d23_misses`의 가뭄 줄이 "no pity in the core" 대신 실제 판정.

**끝난 모양과 돌릴 명령**(직접 돌려 결과를 보고서에 붙임):
```powershell
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/golden_core.gd -- --both
#  → 기존 여섯 건 불일치 0. 일곱째 건은 처음이므로 그 건만 --both --update(여섯 건 줄이 diff에 없어야 함)
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_loot.gd -- --runs=10000
#  → LOOT_SIM 줄이 바꾸기 전과 글자 단위로 같음(앞뒤 파일을 cmp)
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_loot.gd -- --runs=10000 --pity=on
#  → longest_dry_runs <= 5 (D23 3.16 "천장 켬에서 전설·고유 없는 판의 최장 연속 ≤5"), pity_fired_runs 값(모델의 답, 10000판)
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_loot.gd -- --runs=10000 --affix-rolls=on --pity=on
#  → 같은 지표(켠 굴림에서도 ≤5)
python tools/dev/run_all.py --only loot,chapter,profile-all,golden,golden-textless,loot-sim
python tools/dev/run_all.py --quick
git diff --stat -- chapter1/view
#  → 비어 있음
```

**건드리지 말 것**: `chapter1/view/**`, `default_town()`의 값, `LUCK_KEYS`의 두 이름, 스키마 번호·파일 이름·포인터·일지 규칙, `loot.json`의 `pity` 밖 줄, `boss_first_kill`·`champion` 굴림, 사용자 저장.

**보고**: 고친 파일, 위 명령의 결과 줄(원문), 프로필 검사의 바이트 비교 결과, `--pity=on`의 두 지표와 판 수, 명세에 없어 정한 것.

### 1.7 천장을 켜기 전에 남은 일(`pity.enabled` → true)

| 남은 일 | 담당 |
|---|---|
| 1.6 병합과 tech-lead 검수 | gameplay-systems → tech-lead |
| `drop_pity` 이벤트의 한 줄("운이 돌아왔다" 꼴, 말은 narrative-lead)과 도감의 셈 표시(D23 3.10 "몇 판째인지는 도감에서만") | narrative-lead · ui-hud |
| 켠 판 측정: `sim_loot --pity=on`의 두 지표, 그리고 실제 코어 한 판(`report_run_loot.gd`에 `--dry-runs=5` 같은 인수를 더할지 qa-perf와) | content-balance · qa-perf |
| 실행 파일에서 저장 실측: 승리 판 다섯 → 셈 5 → 여섯째 판 우두머리 전설 → 0. 끄고 다시 열어 셈이 남는지(격리 경로) | qa-perf |
| 사용자 플레이 | 사용자 |

---

## 2. 걸음 측정의 허용치와 새 작업 트리에서 실패하는 검사

### 2.1 허용치 — 결정

B1-b의 숫자 [봄: `_local/t9-b1b/REPORT.txt`, 시드 11, 840틱, 곧은 창 8/13, 헤드리스]:

| 경우 | 배율 차 | 미끄러짐 계산 | 화면 | 게임 안 RMS | 게임 − 화면 | 게임 − 계산 |
|---|---|---|---|---|---|---|
| 달리기(지금 계약) | +0.01% | 0.023 | 0.38 | 0.420 | +0.040 | +0.397 |
| 걷기 1.3배 | +0.00% | 2.003 | 1.95 | 1.941 | −0.009 | −0.062 |
| 걷기 1.99배 | +0.00% | −0.012 | 없음 | 0.209 | — | +0.221 |

- 미끄러짐 RMS는 디딤 구간의 발 흔들림을 품는 **바닥**이 있고 그 크기는 클립마다 다르다(달리기 약 0.4, 걷기 약 0.2). 계산식(`slip = v − r·g·s`)은 평균이라 이 바닥이 없다. 그러므로 **계산값과의 비교는 판정에 쓰지 않는다**. 바닥을 상수로 빼는 식(예: 계산 + 0.2)은 클립이 바뀌면 틀리므로 택하지 않는다.
- 화면과 게임은 같은 정의(디딤 = 최저 + 3 cm, 앞뒤 성분 RMS)로 같은 클립을 재므로 바닥이 함께 들어간다. 두 실측 차 +0.040, −0.009.

**정한 규칙**(`motion_verify.py`):
1. 배율: `|게임 − 계산| / 계산 ≤ 2%`. 그대로. 비교의 v는 측정 구간에서 게임이 쓴 속도(장비 보정 전, `--until 840`).
2. 미끄러짐: `|게임 − 화면| ≤ 0.15 m/s`. 화면 = 캐릭터 화면이 **같은 몸·같은 클립·같은 배율·같은 이동 속도**에서 잰 `slip_measured_mps`(고름 기록 또는 `--screen-slip`). [짐작] 표시를 떼고 "B1-b 두 경우의 실측 차(최대 0.040)에서 정함"으로 적는다.
3. 화면 값이 없으면 미끄러짐은 **판정하지 않는다**. 표에 계산값을 "참고(바닥 없음)"로 찍고 종료 코드 **3 = 배율만 판정**(배율이 어긋나면 1이 먼저). 0은 둘 다 판정해 같을 때만.
4. 코드 안의 `SCREEN_REPORTED`(B1-a의 옛 몸 숫자 표)는 지운다. 몸이 바뀌면(Tripo 냉기, 아래 T9 개정) 그 숫자는 다른 몸의 것이다. 화면 값은 고름 기록이나 인수로만 들어온다.
5. 몸 보고서 경로는 `--report <pack-report.json>`(기본 = 자리표가 가리키는 몸 곁의 보고서). 새 몸을 게임에 넣기 전에 `pipeline/<id>/pack/model.pack-report.json`으로 견줄 수 있게.

### 2.2 `test_motion_verify.py`가 새 작업 트리에서 실패하는 까닭 [돌림]

- 재현: 저장소의 `motion_verify.py`·`motion_math.py`·`test_motion_verify.py`와 `asset_slots.json`만 담은 빈 폴더에서 돌림 → 8개 중 `test_no_run_exit_codes` 하나 실패(`AssertionError: 2 != 0`, 출력 "입력을 읽지 못함: FileNotFoundError"). `main(["--current", "--no-run", ...])`이 `clip_numbers()`로 `chapter1/art/actors/hero/frost/model.pack-report.json`을 읽는데, 이 폴더는 `.gitignore` 18행(`chapter1/art/actors/hero/`)이라 새 작업 트리·깨끗한 내려받기에 없다.
- 디렉터가 전한 `WinError 1450`은 이 재현에서 나오지 않았다. 어느 작업 트리에서 났는지 모르고(주인공 폴더를 연결 고리로 걸어 둔 트리일 수 있음) [미확인].
- **결정: 작은 고정 보고서로 바꾼다**("없으면 건너뜀"이 아니라). 까닭: 이 시험은 비교 규칙의 시험이라 진짜 몸이 필요 없다. 건너뜀으로 두면 새 작업 트리에서 돌린 회귀가 그 규칙을 한 번도 시험하지 않는다.
- 같은 꼴의 의존이 다른 도구 시험에 있는지 찾았다: `tools/*/test_*.py`에서 `actors/hero`·작업 뿌리를 읽는 것은 이것 하나. `test_characters.py`는 자리표 사본을 고정으로 만든다 [봄].

### 2.3 `test_audio_tools.py`의 "첫 실행 실패, 혼자 다시 돌려 통과" [봄]

- 임시 폴더는 실행마다 `tempfile.mkdtemp()`(43행)라 겹치지 않는다. `run_all.py`의 `tools-selftest`는 네 파일을 함께 돌리지만(326행) 파일끼리 같은 경로를 쓰는 곳이 없다. `audio_scene_audition.py`도 정해진 공용 경로를 쓰지 않는다(출력은 인수로 받은 `_local` 아래). → **임시 폴더 겹침은 아니다.**
- `FileNotFoundError`의 자리: 63~65행이 `audio_scene_audition.py`를 자식으로 돌린 뒤 `check('scene tool runs', code == 0, ...)`를 찍고 **종료 코드와 상관없이** `o1/measure.json`을 연다. 자식이 실패하면(부하로 ffmpeg·numpy 자식이 늦거나 죽음 [짐작]) 결과 파일이 없어 시험 전체가 예외로 끝나고, 첫 실행의 마지막 줄(`run_all.py`가 남기는 꼬리)은 자식의 진짜 이유가 아니라 이 `FileNotFoundError`가 된다. 같은 꼴이 85·99·104·108·165행에 있다.
- 작은 흠: 43행이 `mkdtemp()/_local/selftest`를 만들고 183행이 `tmp.parent`(= `…/_local`)만 지워 `mkdtemp()`의 빈 폴더가 매번 남는다.
- **결정**: 자식을 부른 뒤 결과 파일을 열기 전에 종료 코드를 보고, 0이 아니면 자식의 표준 출력·오류의 마지막 20줄을 찍고 그 묶음을 실패로 세고 다음 묶음으로 간다. 자식 호출에 시간 제한(180초)을 둔다. 지우기는 `mkdtemp()`의 뿌리를 지운다. 이렇게 하면 다음에 부하에서 실패할 때 진짜 이유가 `run_all`의 결과 줄에 남는다.

### 2.4 지시서 — qa-perf (그대로 전달)

**목표**: (가) 걸음 측정 비교 규칙을 T10 2.1대로 고정한다. (나) `test_motion_verify.py`가 git 밖 파일 없이 돈다. (다) `test_audio_tools.py`가 자식의 실패 이유를 가리지 않는다. 다섯 사상과는 직접 닿지 않는 바탕 일(회귀가 새 작업 트리에서 믿을 만해야 담당 여섯이 같은 실패에 멈추지 않음).

**먼저 읽을 것**: 이 문서 2.1~2.3. `tools/art/motion_verify.py`(머리, `compare`, `main`), `tools/art/test_motion_verify.py`, `tools/dev/test_audio_tools.py`, `tools/dev/run_all.py` 320~350행(`run_tools_selftest`), `_local/t9-b1b/REPORT.txt`.

**고칠 파일(이 밖은 건드리지 않음)**: `tools/art/motion_verify.py`, `tools/art/test_motion_verify.py`, 새 `tools/art/fixtures/motion_pack_report.json`(클립 `run`: `length_s` 0.53333, `ground_speed_toe_mps` 7.2215 / `walk`: 0.96667, 2.2125 — T9 2.2절의 값, 그 밖의 키 없음), `tools/dev/test_audio_tools.py`, `tools/manager/tools_index.json`의 `motion_verify` 줄 설명(허용치 문장)과 다시 만든 `docs/TOOLS-INDEX.ko.md`(`python tools/manager/catalog.py --tools-index`).

**지킬 계약**:
1. `motion_verify.py`: 2.1의 규칙 1~5. 종료 코드 0 = 배율·미끄러짐 모두 같음, 1 = 어긋남, 2 = 측정 못 함·입력 없음, 3 = 배율만 판정(화면 값 없음). 머리글의 [짐작] 문장을 2.1의 근거 문장으로. `SCREEN_REPORTED` 삭제. `--report` 인수.
2. 시험은 저장소 안의 추적 파일과 임시 폴더만 읽는다. `chapter1/art/actors/hero/` 아래와 작업 뿌리(`D:/…`)를 읽지 않는다.
3. `test_motion_verify.py`에 더할 시험: 화면 값 없이 → 종료 3, 화면 값과 0.14 차 → 0, 0.16 차 → 1, 계산값과 0.4 차·화면과 0.04 차(달리기 꼴) → 0, `--report`로 고정 보고서를 읽음.
4. `test_audio_tools.py`: 결과 파일을 여는 모든 자리 앞에서 종료 코드 확인, 실패면 꼬리 20줄을 찍고 그 묶음 실패, 자식 호출 시간 제한 180초, `mkdtemp()` 뿌리 지우기. 검사하는 내용(현재 `check` 줄들)은 바꾸지 않는다.
5. `run_all.py`는 고치지 않는다.

**끝났다는 기준**:
1. 빈 폴더 재현: 임시 폴더에 `tools/art/{motion_verify,motion_math,test_motion_verify}.py`, `tools/art/fixtures/motion_pack_report.json`, `chapter1/art/asset_slots.json`만 복사하고 `python tools/art/test_motion_verify.py` → 모두 통과.
2. 새 작업 트리(`git worktree add`, 주인공 폴더 없음)에서 `python tools/dev/run_all.py --only tools-selftest` 통과.
3. 본 저장소에서 `python tools/art/motion_verify.py --current --no-run _local/t9-b1b/raw/current.json --screen-slip 0.38` → 0, 같은 것을 `--screen-slip` 없이 → 3. `--clip walk --rate 1.99 --no-run _local/t9-b1b/raw/walk-1p99.json` → 3(화면 값 없음). (원시 파일 이름은 B1-b 보고의 raw 폴더에서 확인)
4. `test_audio_tools.py`에서 `audio_scene_audition.py` 경로를 일부러 틀린 이름으로 바꾼 임시 사본으로 한 번 돌려, 출력에 자식의 오류 꼬리가 찍히고 `FileNotFoundError`로 죽지 않음을 보인다(사본은 `_local/` 아래, 저장소 파일은 원래대로).
5. `python tools/dev/run_all.py --quick` 통과.

**건드리지 말 것**: `chapter1/` 전부, `hero_motion_probe.gd`, `motion_math.py`의 식, `audio_scene_audition.py`, `run_all.py`.

**보고**: 고친 파일, 위 다섯의 명령과 결과 줄, 2번을 돌린 작업 트리 경로.

---

## 3. 순서와 병렬

- 1.6(gameplay-systems)과 2.4(qa-perf)는 파일이 겹치지 않는다 → **동시에**.
- 1.6은 D23 T1-B·R1-B·데이터 손질이 본 저장소에 커밋된 뒤의 main에서 시작한다(`chapter_core.gd`·`loot.gd`·`loot.json`·골든 json을 같이 잡는다). 같은 동안 이 파일들을 잡는 다른 지시서(D25 T10-a의 `chapter_profile.gd`, D24 강림의 `chapter_core.gd`)는 디렉터가 차례를 정한다 — **`chapter_profile.gd`는 D25 T10-a와 겹친다**. 1.6을 먼저 하고 T10-a를 그 위에서 하기를 권한다(T10-a의 도박 천장도 `town.luck`을 쓰므로 1.2의 선택 키 읽기를 그대로 물려받음).
- T9 개정(별도 문서)의 B2-a·B2-b는 이 두 지시서와 겹치지 않는다.

## 4. 검수 때 tech-lead가 돌릴 것

1.6: 1.6의 명령 전부를 본 저장소에서 다시. 지금 사용자 저장과 같은 꼴의 고정 파일(luck 키 둘)을 읽고 다시 쓴 바이트 비교. `git diff -- chapter1/data/loot.json`이 `pity` 블록뿐인지.
2.4: 2.4 기준 1·2를 직접(새 작업 트리 하나를 만들어).

## 5. 디렉터가 알 것

- `CLAUDE.md`의 "저장" 절이 낡았다: 지금 코드는 **스키마 5, `user://chapter-one-profile-v5.json`**, 4·3·2·1을 읽기만 한다(`chapter_profile.gd` 2·10·21행). 내가 고칠 수 없는 파일이라 디렉터가 고친다.
- 이 문서에서 사용자에게 물을 것은 없다.

## 6. 이번에 직접 실행한 것과 하지 않은 것

- 돌림: `git log`, `git show`, `git apply --check`(임시 폴더), `test_motion_verify.py`의 빈 폴더 재현(위 2.2), 데이터 파일을 파이썬으로 읽어 본 것.
- 하지 않음: Godot 실행(본 저장소에서 전체 회귀가 도는 중이라 지시대로 띄우지 않음), `sim_loot`, 골든. 1.5의 "걸린 판의 난수 차이" 서술은 코드 읽기에서 낸 것이다.
