# 기술 지시서 T1 — 화면 작업 동안 준비하는 기술 과제

2026-11-16, 기술 책임자(tech-lead) 작성. 총괄 디렉터 배정. 기준 커밋 `c75d3d3`.

이 문서의 지시서 1~4는 디렉터가 개발 에이전트에게 그대로 전달한다. 받는 쪽은 이 문서만 보고 일할 수 있게 썼다. 5절은 지시서가 아니라 기술 검토다.

## 0. 지금 상황과 공통 규칙

### 0.1 상황(2026-11-16 밤)

- 화면 에이전트 셋(ui-hud, vfx-feel, character-artist)이 `chapter1/view/hud/**`, `chapter1/view/fx/combat_juice.gd`와 셰이더 둘, `chapter1/view/actors/chapter_actors.gd`의 주인공 부분을 고치는 중이다. 같은 시드의 전후 캡처로 검수한다.
- 그래서 화면 작업이 끝날 때까지 **코어(`chapter1/core/**`)와 데이터(`chapter1/data/**`)는 동결**이다.
- 이 문서를 쓰는 시점에 Godot 프로세스가 열댓 개 돌고 있었다(1080p·720p `hud_dump.gd` 캡처 5개와 `sim_progression.gd` 4개). **프레임 시간과 틱 시간은 지금 재지 않는다.**

### 0.2 모든 지시서에 공통

| 항목 | 내용 |
|---|---|
| Godot | `C:/Project/rea-tools/godot-4.5.1/Godot_v4.5.1-stable_win64_console.exe`(아래에서 `$G`) |
| Python | `C:/Users/twins/AppData/Local/Programs/Python/Python310/python.exe` |
| 저장소 | `C:/Project/witch-moira`(저장소 루트가 Godot 프로젝트) |
| 임시·원시 파일 | `_local/` 아래에만 둔다. **`_local/shots/base-20261116/`은 디렉터의 기준 캡처라 읽기만 한다.** `_local/perf/20261115-*`는 옛 측정 원시라 읽기만 한다 |
| `_local`의 스크립트 | `_local/`에 `.gdignore`가 있어도 `--script res://_local/...`와 `load("res://_local/...")`는 동작한다(2026-11-16 tech-lead 확인). 측정용 보조 스크립트는 `_local/` 아래에 두고 저장소에 넣지 않는다 |
| 저장 | 모든 실행에 `--chapter1-profile-off`를 붙인다. `%APPDATA%\WitchMoira`의 저장을 읽거나 고치지 않는다 |
| 줄바꿈 | `.gitattributes`가 `* -text`다. `sed -i`처럼 줄바꿈을 바꾸는 도구로 기존 파일을 고치지 않는다 |
| git | 커밋·푸시하지 않는다. `git add .` 금지. 코드 사본은 `git archive`로만 만든다(`git worktree`·`checkout` 금지: 작업 트리를 바꾸지 않는다) |
| 보고 | 실행한 명령, 원시 파일 경로, 숫자, 하지 못한 것. 실행하지 않은 검사를 통과로 적지 않는다 |

### 0.3 "다른 Godot가 없다"의 정의와 확인

시간을 재는 실행(지시서 1, 2의 측정 단계)은 아래 조건을 **실행 직전과 직후에 모두** 확인하고, 하나라도 어기면 그 실행을 버리고 다시 한다.

```powershell
# 0이어야 한다(편집기 포함 모든 Godot). 결과를 실행 로그 옆에 남긴다.
(Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue | Measure-Object).Count
```

- 측정 중에는 다른 에이전트의 Godot 실행이 없어야 한다. 디렉터에게 "측정 창"을 받아서 시작한다(측정 창 = 다른 에이전트가 Godot를 돌리지 않기로 한 시간).
- 측정 순서는 직렬이다. 측정끼리도 동시에 돌리지 않는다.

### 0.4 기준 사본 만들기(지시서 1·2·3이 같이 쓴다)

화면 작업 전의 코드는 작업 트리에 남지 않는다. 기준 커밋을 `_local` 아래에 풀어 두고 따로 임포트한다.

```powershell
New-Item -ItemType Directory -Force C:/Project/witch-moira/_local/snap/c75d3d3
git -C C:/Project/witch-moira archive c75d3d3 -o C:/Project/witch-moira/_local/snap/c75d3d3.tar
tar -xf C:/Project/witch-moira/_local/snap/c75d3d3.tar -C C:/Project/witch-moira/_local/snap/c75d3d3
& $G --headless --path C:/Project/witch-moira/_local/snap/c75d3d3 --import   # 두 번 돌린다(GLB에서 나온 자원은 두 번째에 임포트된다)
& $G --headless --path C:/Project/witch-moira/_local/snap/c75d3d3 --import
```

화면 작업이 끝나면 디렉터가 "후" 커밋(아래 `<AFTER>`)을 정해 준다. 같은 방법으로 `_local/snap/<AFTER>/`를 만든다. 전후 모두 사본에서 재야 임포트 캐시 조건이 같다.

사본도 같은 사용자 폴더(`WitchMoira`)를 쓰도록 설정돼 있다. `--chapter1-profile-off`를 빼먹지 않는다.

---

## 지시서 1 — 프레임 시간 재측정(qa-perf)

### 목표

전투 수치 2차 확정(판 길이 5~6분, 적·탄 증가) 뒤로 프레임 시간을 잰 적이 없다. 화면 작업 **전(`c75d3d3`)과 후(`<AFTER>`)**를 같은 조건으로 재서, 품질 기준(`docs/QUALITY-TARGETS.ko.md` 1절: 1920×1080에서 p95 16.6ms 이하, 50ms 넘는 끊김 0회)에 대한 현재 값과 화면 작업이 더한 비용을 숫자로 낸다. **고치지 않는다. 재기만 한다.**

### 시작 조건

1. 화면 작업이 끝나고 디렉터가 `<AFTER>` 커밋을 정했다.
2. 디렉터가 측정 창을 줬다(0.3절).
3. (선택) 측정 창이 화면 작업보다 먼저 나면 "전" 쪽 예열과 측정만 먼저 해도 된다. 단 전후 비교 판정은 같은 날 같은 기계 상태에서 잰 값으로만 한다.

### 고칠 수 있는 파일

- `_local/snap/**`(사본), `_local/perf/t1-frame/**`(실행 스크립트, 원시, 분석 스크립트, 요약).

### 건드리면 안 되는 파일

- 저장소의 모든 추적 파일. `chapter1/tests/frame_probe.gd`도 고치지 않는다(전후가 같은 측정기를 써야 한다).
- `chapter1/presentation/frame_probe.gd`(게임 안의 `--chapter1-frame-probe-dir` 측정기)는 쓰지 않는다. 2026-11-15 값과 비교하려면 `chapter1/tests/frame_probe.gd`를 써야 한다.

### 측정기 사용법(`chapter1/tests/frame_probe.gd`를 읽고 정리)

- 실제 렌더러로 돌린다. `--headless`와 `--fixed-fps`를 붙이지 않는다.
- 수직 동기화는 `--probe-vsync=on`이 없으면 꺼진다. 끈 채로 잰다(2026-11-15 측정과 같은 조건).
- 시계는 첫 `playing` 프레임에서 시작한다. 프레임마다 `dt_us`(`Time.get_ticks_usec` 차), `modes`, `ticks`(코어 틱), `enemies`, `draw_calls`, `proc_ms`를 기록한다.
- 판이 끝나면(`victory`/`defeat`) `view.retry()`로 시드+1 새 판을 시작하고 계속 잰다. 그래서 분석은 **첫 판 구간만** 쓴다(아래).
- 끝나면 `FRAME_PROBE_RESULT {...}`를 출력하고 `--probe-out` 파일에 원시를 쓴다. `info.window_size`, `vsync_mode`, `unfocused_frames`, `restarts`, `final_tick`, `kills`가 들어 있다.

### 실행 행렬

- 빌드 2개(`c75d3d3`, `<AFTER>`) × 주력 3개(`chapter1.skill.ember`, `frost`, `arc`) × 반복 3회 = **18회**. 전투 효과는 켠 상태(`--chapter1-no-juice` 없음).
- 순서는 끼워 넣기: `for rep in 1..3: for primary in ember, frost, arc: base, after`. 같은 빌드를 몰아서 재지 않는다.
- **예열**: 행렬을 시작하기 전에 빌드×주력마다 한 판씩(6회) 같은 명령으로 돌리고 버린다. 셰이더·파이프라인 첫 컴파일이 끊김으로 잡히는 것을 막기 위해서다. 예열 원시도 `warmup/`에 남긴다.
- 한 회는 `--probe-seconds=400`(판 길이 304~356초 + 여유). 행렬 전체는 예열 포함 약 24회 × 7분 ≈ **2시간 50분**.

명령(빌드 경로 `$ROOT`, 출력 이름 `$NAME`):

```powershell
& $G --path $ROOT --resolution 1920x1080 --script res://chapter1/tests/frame_probe.gd -- `
  --chapter1-start --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus `
  --chapter1-seed=11 --chapter1-primary=$PRIMARY --probe-seconds=400 `
  --probe-out=C:/Project/witch-moira/_local/perf/t1-frame/$NAME.json *> C:/Project/witch-moira/_local/perf/t1-frame/$NAME.log
```

실행마다 직전·직후의 Godot 프로세스 수(0.3절)를 `$NAME.env.txt`에 남긴다. 창을 건드리지 않는다(마우스·키 입력 금지).

### 유효한 실행의 조건(하나라도 어기면 버리고 다시)

| 조건 | 값 |
|---|---|
| `info.window_size` | `[1920, 1080]` |
| `info.vsync_mode` | `0`(꺼짐) |
| 직전·직후 다른 Godot | 0개 |
| 첫 판이 끝났는가 | 첫 판 구간에 `victory` 또는 `defeat`가 있다 |
| 포커스 | `unfocused_frames / frames`가 같은 행렬 안에서 모두 0.95 이상이거나 모두 0.05 이하(섞이면 무효). 2026-11-15 측정은 거의 전부 비포커스였다 |

### 분석

`_local/perf/t1-frame/analyze.py`를 새로 쓴다. 분위수 정의는 2026-11-15 분석(`_local/perf/20261115-juice/analyze.py`의 `q()`: 정렬 후 `ceil(n*p)-1`번째)과 **같게** 한다. 그래야 옛 값과 비교된다.

- **첫 판 구간**: 첫 프레임부터 `ticks[k] < ticks[k-1]`이 처음 나오기 직전까지(재시작 전).
- 구간 세 개를 각각 낸다.
  - `W`(판 전체): 첫 판 구간에서 `t_us >= 10초`인 프레임. **판정은 이 구간으로 한다.**
  - `A`(초반): `60초 <= t_us <= 180초`. 2026-11-15 값(같은 창)과 비교용.
  - `B`(후반): `t_us > 180초`부터 첫 판 끝까지. 3구역과 우두머리 교전이 들어간다.
- 구간마다: 프레임 수, 평균, p50, p95, p99, 최댓값, 50ms 초과 횟수, 16.6ms 초과 횟수, 적 수 평균·최대, 그리기 호출 평균, `proc_ms` 평균.
- 50ms 초과 프레임은 하나하나 `t_us`, `ticks`, `modes`, `enemies`를 표로 남긴다(원인 추적용).
- 빌드×주력마다 3회의 중앙값을 내고, `<AFTER> − c75d3d3`의 차를 낸다.

### 끝났다는 기준

1. 유효한 실행 18회(+예열 6회)의 원시와 로그가 `_local/perf/t1-frame/`에 있다.
2. `summary.json`과 아래 표가 보고서에 있다.

| 빌드 | 주력 | W p95 중앙값 | W p99 | 50ms 초과(3회 각각) | A p95 | B p95 | 적 수 평균 |
|---|---|---|---|---|---|---|---|

3. 품질 판정을 숫자로 적는다: 빌드×주력마다 **W p95 중앙값 ≤ 16.6ms** 그리고 **3회 모두 50ms 초과 0회**이면 통과, 아니면 미달. 미달이면 미달이라고 적는다.
4. 화면 작업의 비용: 주력마다 `<AFTER>`의 W p95 중앙값 − `c75d3d3`의 값. **디렉터 제안 허용폭(확정 전): +0.5ms 이하이고 50ms 초과가 늘지 않을 것.**

### 보고에 넣지 말 것

- 원인 추정을 측정값처럼 쓰지 않는다. 50ms 끊김의 원인은 "그 프레임의 상태가 이랬다"까지만 적는다.

---

## 지시서 2 — 번개 코어 틱 약 1.4배(qa-perf → gameplay-systems)

### 배경

`docs/QUALITY-TARGETS.ko.md` 2절 마지막 행: 2차 수치 확정 뒤 코어 1틱 p95가 번개 3.3~3.6ms(이전 2.0~2.6ms)로 기준(이전의 1.3배 이내)을 넘었다. 다만 그 측정은 다른 Godot가 동시에 돌던 값이다. 화염 4.3~4.9ms, 냉기 3.7~4.3ms는 기준 안이다.

tech-lead가 코드를 읽고 본 것(측정 전 가설):

- 2차 수치에서 번개 주력은 진화 때 재사용 66틱 → 16틱, 갈래 4 × 연쇄 12로 바뀌었다(`docs/specs/M2-combat-pressure-spec-round2.ko.md` 128~133행, `chapter1/data/combat_tuning.json`의 `primary_bonus["chapter1.skill.arc"]`). 시전 수가 약 4배, 시전당 연쇄 마디가 최대 48개다. 화염·냉기는 투사체가 늘었지만 투사체 한 발의 검색 반경은 작다. 번개만 반경 7~12m 검색을 마디마다 한다.
- 이전 값(2.0~2.6ms)을 낸 코어와 수치는 이 저장소에 없다(옛 저장소에서 옮기지 않음). **이전 값을 같은 조건으로 다시 낼 수는 없다.** 그래서 이 과제는 "지금 값을 단독으로 다시 재고, 비용이 어디서 나는지 나눠 보는 것"이다.

### 2-1. 단독 재측정과 원인 좁히기(qa-perf)

#### 시작 조건

- 코드 읽기와 보조 스크립트 작성: **지금 시작 가능**(헤드리스 동등성 확인 포함).
- 시간 측정: 디렉터가 측정 창을 줬을 때. 지시서 1과 같은 창을 쓰면 지시서 1이 끝난 뒤 직렬로 한다.

#### 고칠 수 있는 파일

- `_local/perf/t2-tick/**`만. 측정용 코어 서브클래스, 구동 스크립트, 수치 변형 파일, 원시.

#### 건드리면 안 되는 파일

- `chapter1/core/**`, `chapter1/data/**`(동결), `chapter1/tests/**`(측정기 `measure_combat.gd`·`golden_core.gd`는 그대로 쓴다), 그 밖의 추적 파일 전부.

#### 단계 A — 단독 재측정

측정 창 안에서, 작업 트리(코어 동결 중이라 `c75d3d3`과 같은 코어)로 3회 반복한다.

```powershell
& $G --headless --path C:/Project/witch-moira --script res://chapter1/tests/measure_combat.gd -- `
  --arc-combined --out=C:/Project/witch-moira/_local/perf/t2-tick/A-rep$REP.json *> C:/Project/witch-moira/_local/perf/t2-tick/A-rep$REP.log
```

- `--secondary-off`는 붙이지 않는다(틱 비용 측정에는 필요 없고 시간이 두 배다).
- 행마다 `step_usec_p50_p95_p99`를 읽는다(`measure_combat.gd:266-268`이 `run.step()`만 잰다. 자동 조작 판단 시간은 들어가지 않는다).
- 주력×시드마다 3회의 p95 중앙값, 그리고 같은 시드끼리의 비 `번개 / 화염`, `번개 / 냉기`.
- 판의 진행이 같았는지 확인: 3회의 `ticks`, `kills`가 회차마다 같아야 한다(결정론). 다르면 멈추고 보고한다.

#### 단계 B — 측정용 코어 서브클래스로 비용 나누기

`_local/perf/t2-tick/timed_core.gd`를 쓴다: `extends "res://chapter1/core/chapter_core.gd"`. 아래 메서드를 덮어써서 `super`를 부르고 시간과 횟수만 센다. **동작을 바꾸지 않는다.**

- 틱 단계(포함 시간): `_spawn_wave`, `_step_enemies`, `_rebuild_grid`, `_auto_casts`, `_step_projectiles`, `_collect_pickups`, `_cleanup`, `_refresh_mode`, `_update_metrics`, `_step_chapter_hazards`, `_step_fields`, `_step_rituals`.
- 번개 경로: `_chain`의 포함 시간과 호출 수, 시전당 마디 수(`context.arc_segments.size()`).
- `_near`: 호출 수와 반환 개수 합만 센다(시간은 재지 않는다: 호출이 많아 계측 자체가 비용이 된다). 호출한 쪽을 "지금 실행 중인 단계" 변수로 나눈다(`_chain` 안 / `_auto_casts` 안 / `_step_projectiles` 안 / 그 밖).
- `_emit`: 종류별 개수. 판 끝의 `metrics.events_dropped` 값.
- **누적값은 스크립트 변수에만 둔다. `metrics`나 적·투사체 사전에 쓰지 않는다.** `snapshot()`이 `metrics`를 포함하므로(`combat_core.gd:934-939`) 거기에 쓰면 골든이 깨진다.

동등성 확인(헤드리스, 시간 무관이라 지금 해도 된다):

```powershell
& $G --headless --path C:/Project/witch-moira --script res://chapter1/tests/golden_core.gd -- --core=res://_local/perf/t2-tick/timed_core.gd
```

`GOLDEN_RESULT`의 4건 모두 불일치 0이어야 한다. 하나라도 다르면 계측이 동작을 바꾼 것이니 고친다.

구동은 `_local/perf/t2-tick/tick_profile.gd`(SceneTree)로 한다. `measure_combat.gd`의 `play()` 루프(198~269행)처럼 `chapter_pilot.gd`로 한 판을 돌리고, 틱마다 `(step_usec, 생존 적 수, 이번 틱 시전 수, 이번 틱 연쇄 마디 수)`를 기록한다. `measure_combat.gd -- --core=...`로 대신해도 되지만 그 경우 틱별 부하는 남지 않는다.

측정 창 안에서: 세 주력 × 시드 11·12·13 × 2회. 산출:

1. 단계별 시간 비중(주력별). 번개에서 `_chain`(+그 안의 `_near`)이 틱 시간의 몇 %인가.
2. 틱 비용을 생존 적 수 구간(0~19, 20~39, …)별 평균으로. 같은 적 수에서도 번개가 비싼가, 번개 판에 적이 더 많아서인가.
3. 진화 전후로 나눈 번개의 틱 p95(진화 시점은 `growth` 이벤트의 `evolve:` 카드, `measure_combat.gd:263-265`와 같은 방법).

#### 단계 C — 수치 변형으로 원인 확인(측정 전용, 데이터 파일은 그대로)

`chapter1/data/combat_tuning.json`을 `_local/perf/t2-tick/`로 복사한 변형을 `--tuning=`으로 넘긴다(`measure_combat.gd:73`, `chapter_core.gd:98`의 `load_tuning`). 원본은 고치지 않는다.

| 변형 | 바꾸는 것 | 보는 것 |
|---|---|---|
| V0 | 그대로 | 기준 |
| V1 | `primary_bonus.chapter1.skill.arc`의 모든 단계 `cooldown_bps`를 10000 | 시전 빈도의 몫 |
| V2 | 같은 곳의 `r4`·`evo`의 `add.chain_targets`, `add.branches`를 0 | 마디 수의 몫 |
| V3 | `marks.mark_bps` 0 | 표식 공명의 몫 |
| V4 | `seal_kills`를 `[812,1262,1117]`(2차 전 값, 2차 명세 200행) | 판이 길어진 몫 |

번개 주력 × 시드 11·12·13 × 2회. 변형은 게임 진행 자체를 바꾸므로 p95만이 아니라 단계 B의 "적 수 구간별 틱 비용"을 함께 비교한다.

#### 의심 지점(코드 읽기, 측정으로 확인할 것)

| # | 위치 | 내용 | 번개에만 해당하는 이유 |
|---|---|---|---|
| S1 | `chapter1/core/combat_core.gd:635-642` (`_chain`) | 연쇄 마디마다 `_near(at, radius_cm/100)`를 부른다. 반경 7~12m면 2m 격자 64~169칸을 훑고, 찾은 적 **전부**를 람다 비교로 정렬한(`combat_core.gd:587-590`) 뒤 맨 앞의 "아직 안 맞은" 하나만 쓴다. 그 확인도 `id_ in context.hit_ids` 배열 선형 검색(640행) | 진화 번개: 시전 16틱마다 최대 48마디 |
| S2 | `chapter1/core/chapter_core.gd:788-790` (`_damage_enemy`) | 번개 명중마다 `id_ in context.hit_ids` 선형 검색 후 추가. 진화 예산 +80으로 배열이 100개 넘게 자란다 | 번개만 시전 단위 중복 방지를 한다 |
| S3 | `chapter1/core/chapter_core.gd:835`, `:841-845`, `chapter1/core/combat_core.gd:611`, `:922-932` | 번개 명중 한 번에 `hit`와 `stun` 이벤트 두 개, 시전마다 `cast` 이벤트에 `effects` 깊은 복사와 마디 사전 최대 48개. `_emit`은 매번 `details.duplicate(true)` | `stun`과 마디 목록은 번개만 |
| S4 | `chapter1/core/combat_core.gd:929-931` | 한 틱 이벤트가 `MAX_EVENTS`(1024)를 넘으면 `events.pop_front()`(배열 앞 삭제, O(n))를 이벤트마다 한다 | 이벤트가 많은 번개에서 먼저 닿을 수 있다. `metrics.events_dropped`가 0이면 기각 |
| S5 | `chapter1/core/chapter_core.gd:852-855` | 처치 폭발(`death_burst`)이 있는 단계에서 반경 3m `_area_hit` → `_near` 재귀 | 번개 단계 데이터에 `death_burst`가 켜진 경우만 |
| S6 | `chapter1/core/combat_core.gd:599` (`_auto_casts`) | 시전 준비된 기술마다 `_near(hero.position, 13.0)` — 주인공 둘레 13m 적 전부 정렬 | 모든 계열 공통이지만, 번개 주력의 재사용이 16틱이라 호출이 가장 잦다 |

#### 끝났다는 기준(2-1)

1. 동등성: `timed_core.gd`로 돌린 골든 4건 불일치 0.
2. 단계 A 표: 주력 3 × 시드 3의 단독 p95(3회 중앙값)와 계열 간 비. 결정론 확인(회차 간 `ticks`·`kills` 동일).
3. 단계 B 표: 주력별 단계 시간 비중(%), `_near` 호출 수의 호출처별 분포, 적 수 구간별 평균 틱 비용, 번개 진화 전후 p95.
4. 단계 C 표: V0~V4의 번개 p95와 적 수 구간별 틱 비용.
5. S1~S6 각각에 대해 "확인 / 기각 / 판단 불가"와 그 근거가 된 숫자. 예: "S1 확인 — 번개 진화 후 틱 시간의 N%가 `_chain`".
6. 결론 한 줄: 번개 틱 증가가 (가) 설계대로 늘어난 일의 양인가, (나) 특정 경로의 비효율인가, (다) 둘 다인가.

### 2-2. 고치기(gameplay-systems) — 2-1이 S1·S2·S3 가운데 하나 이상을 "확인"했을 때만

#### 시작 조건

1. 2-1 보고가 끝났고 tech-lead가 검수했다.
2. 화면 작업이 끝나 디렉터가 **코어 동결을 풀었다**.
3. 디렉터가 아래 "디렉터가 정할 것"의 판정 기준을 정했다.

#### 목표

판정 결과를 바꾸지 않고 번개 연쇄의 비용만 줄인다. **골든이 그대로여야 한다(`--update` 금지).** 골든이 바뀌면 그 변경은 실패다.

#### 고칠 수 있는 파일

- `chapter1/core/combat_core.gd`: `_chain`(627~649행), 필요하면 `_near` 옆에 새 보조 함수 추가(기존 `_near`의 동작은 그대로).
- `chapter1/core/chapter_core.gd`: `_damage_enemy`의 번개 중복 확인(788~790행).

#### 건드리면 안 되는 파일

- `chapter1/data/**`(수치는 바꾸지 않는다), `chapter1/view/**`, `chapter1/app/**`, `chapter1/tests/golden/**`, 그 밖의 코어 파일.
- 이벤트의 모양(`cast`의 `segments`, `hit`, `stun`의 키와 값). 표현이 읽는다.

#### 방향(구현자가 바꿔도 되지만 동등성은 반드시 지킨다)

- `_chain`: 마디마다 "정렬 후 첫 미명중" 대신, 같은 격자 범위를 한 번 훑으며 **같은 비교 규칙**(거리 제곱, 거의 같으면 작은 id)으로 미명중 최솟값 하나를 고른다.
- 주의: `_near`의 비교는 `is_equal_approx`를 쓰므로 엄밀한 전순서가 아니다. 최솟값 훑기가 정렬의 첫 원소와 다른 적을 고르는 경우가 이론상 있다. 골든과 아래 9판 비교가 이를 잡는다. 다르게 나오면 이 방법은 포기하고 보고한다.
- 명중 확인: `context.hit_ids`(배열)는 그대로 두고, 같은 내용의 사전(`context.hit_set`)을 함께 유지해 `in` 검사를 사전으로 한다. `context`는 `snapshot()`에 들어가지 않는다(`combat_core.gd:934-939`). 투사체의 `hit_ids`는 스냅숏에 들어가므로 손대지 않는다.

#### 끝났다는 기준(2-2)

1. `& $G --headless --path . --script res://chapter1/tests/golden_core.gd` → 4건 불일치 0(갱신 없이).
2. `python tools/dev/run_all.py` 전부 통과.
3. `measure_combat.gd -- --arc-combined` 9판의 결과 JSON이 변경 전과 `step_usec_p50_p95_p99`를 뺀 모든 필드에서 같다(비교 스크립트로 확인하고 출력 첨부).
4. 측정 창에서 단독으로: 번개 3시드의 틱 p95가 디렉터가 정한 기준 이하. 화염·냉기 p95가 변경 전보다 늘지 않음(3회 중앙값, ±0.1ms 이내).

---

## 지시서 3 — 스크립트 로드 실패 "Could not resolve class" 재현(qa-perf)

### 배경

`docs/DIRECTOR-PLAN.ko.md` 2.8절 "스크립트 로드 실패" 행: 옛 저장소에서 깊은 상속 체인의 스크립트가 드물게 "Could not resolve class"로 로드에 실패하고 게임이 멈춘 채 떴다(20여 회 중 1회). 원인 미확인.

tech-lead가 지금 저장소에서 확인한 것:

- 프로젝트에 `class_name`이 없다(`.godot/global_script_class_cache.cfg`의 `list=[]`). 실패는 `extends "res://..."` 경로 상속에서 부모 스크립트를 못 불러온 경우로 보인다.
- **깊은 체인은 아직 실행 경로에 있다.** `chapter1/view/world/chapter_world.gd:733-734`가 `chapter_world_quality37b.gd`를 미리 불러와 인스턴스를 만든다. 이 파일은 `37b → 37 → 31d → 31c → 31b → 31 → 22 → 18 → 17 → 10 → view/chapter_world.gd → cloister_world_quality03.gd`의 12단 체인이다. 또 `chapter1/app/chapter_one.gd:7-11, 14-17, 21`이 옛 층(`combat_run.gd`, `cloister_world/actors/effects/hud.gd`)을 불러와 만든 뒤 `_init`(346-347행)에서 바로 버린다. 게임을 띄우면 옛 층 스크립트 17개가 전부 로드된다(tech-lead 확인: 아래 지시서 4의 검사 스크립트로 17/17).
- 옛 저장소는 실행 전에 코드를 스테이지 폴더로 복사했다. 지금은 저장소에서 바로 돈다. 대신 `tools/dev/run_dev.py:39`가 **실행할 때마다 `--import`를 먼저 돌린다.** 다른 Godot가 같은 프로젝트로 돌고 있으면 `.godot/` 캐시를 동시에 쓰게 된다.
- 지금은 다른 에이전트가 작업 트리의 `.gd` 파일을 고치는 중이다. 작업 트리로 재현하면 반쯤 저장된 파일 때문에 나는 오류와 섞인다. **재현은 사본(0.4절)으로 한다.**

가설:

| # | 가설 | 재현 변수 |
|---|---|---|
| H1 | 다른 Godot의 `--import`가 `.godot/`(`uid_cache.bin`, 임포트 캐시)를 쓰는 동안 로드 | 동시 임포트 |
| H2 | 스크립트 파일을 다른 프로세스가 쓰는 중에 읽음(옛 스테이지 복사, 지금은 에이전트의 편집) | 로드 중 파일 교체 |
| H3 | 깊은 경로 상속 체인의 로드 순서 문제(엔진 쪽 간헐 오류) | 반복 횟수, 동시 실행 수 |

### 시작 조건

- 묶음 B1~B4(헤드리스, 사본 사용): **지금 시작 가능.** 시간 측정이 아니다. 단 디렉터가 측정 창을 연 동안에는 돌리지 않는다.
- 묶음 B5(창 모드): 화면 작업이 끝난 뒤(창이 뜨면 다른 에이전트의 캡처에 끼어들 수 있다).
- 묶음 B6(정리 후 비교): 지시서 4의 R1·R2가 끝난 뒤.

### 고칠 수 있는 파일

- `_local/snap/**`, `_local/repro/t3-load/**`만(실행 스크립트, 로그, 요약).

### 건드리면 안 되는 파일

- 저장소의 추적 파일 전부. 작업 트리의 `.godot/`도 지우거나 건드리지 않는다(사본의 `.godot/`만 지워도 된다). `tools/dev/run_dev.py`의 수정은 제안만 한다.

### 실행기

`_local/repro/t3-load/repro.py`를 쓴다. 인수: `--root`(사본 경로), `--runs N`, `--concurrency C`, `--import-during`(묶음 동안 같은 `--root`에 `--import`를 10회마다 하나씩 띄움), `--touch-during`(아래 B4), `--windowed`, `--fresh-cache-every K`(K회마다 사본의 `.godot/`를 지우고 임포트 두 번), `--tag`.

한 회의 명령(약 12초, tech-lead가 작업 트리에서 한 번 확인: 종료 코드 0, 준비 표지 두 개 출력):

```powershell
& $G --headless --path $ROOT res://chapter1/ChapterOne.tscn -- --chapter1-start --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-quit-after=5
```

- 회마다 제한 시간 60초. 넘으면 프로세스를 끝내고 HANG으로 센다(옛 증상은 "멈춘 상태로 뜸").
- 표준 출력과 오류를 회마다 `runs/<tag>-<i>.log`로 남긴다.
- 실패한 회는 같은 조건으로 `--verbose`를 붙여 5회 더 돌려 로더 기록을 얻는다.

판정(회마다 하나):

| 분류 | 조건 |
|---|---|
| OK | 종료 코드 0, `CHAPTER1_READY`와 `FULL_CHAPTER_READY`가 있음, 아래 오류 문구 없음 |
| RESOLVE | `Could not resolve class` 포함 |
| PARSE | `Parse Error` 또는 `Failed to load script` 또는 `Failed loading resource` 포함 |
| HANG | 60초 초과 |
| OTHER | 그 밖에 `SCRIPT ERROR`, `ERROR:` 또는 준비 표지 없음 |

### 묶음

| 묶음 | 조건 | 회수 | 시간(어림) |
|---|---|---|---|
| B1 | 사본 `c75d3d3`, 동시 1, 캐시 데움 | 100 | 20분 |
| B2 | 같은 사본, 동시 4 | 100(25파) | 10분 |
| B3 | 동시 4 + `--import-during`(H1) | 100 | 15분 |
| B4 | 동시 1 + `--touch-during`: 다른 스레드가 체인 파일(`chapter_world_quality31.gd`, `cloister_world_quality03.gd`)을 같은 내용으로 **비원자적으로** 다시 쓴다(열어서 잘라 내고 다시 씀, 0.2초 간격). 사본에서만(H2) | 50 | 10분 |
| B4b | `--fresh-cache-every 10`(임포트 직후 첫 실행) | 50 | 25분 |
| B5 | 창 모드(`--headless` 없음), 동시 1. 화면 작업 뒤 | 30 | 10분 |
| B6 | 지시서 4의 R1·R2를 적용한 커밋의 사본으로, B1~B4b 중 실패가 난 묶음만 다시 | 같은 회수 | — |

### 로그에서 볼 것

- 실패 문구의 전체 줄과 그 안의 스크립트 경로. 그 스크립트가 12단 체인(위 배경) 안인가, `chapter_one.gd`의 옛 층 미리 불러오기 안인가, 그 밖인가.
- 실패 직전 줄들: `Parse Error`, `Cannot open file`, `Resource file not found`, `Failed loading resource`, `File modified` 류.
- 실패 시각과 같은 시각에 돈 다른 회의 번호, `--import` 프로세스가 돌고 있었는지(B3), 파일 교체 중이었는지(B4).
- 사본의 `.godot/uid_cache.bin`, `.godot/global_script_class_cache.cfg`의 수정 시각이 묶음 중에 바뀌었는지(묶음 전후 기록).
- 종료 코드, HANG 여부, 준비 표지 중 어디까지 찍혔는지.

### 끝났다는 기준

1. B1~B4b, 합계 400회의 분류 표(묶음 × 분류 개수)와 원시 로그.
2. 실패가 있으면: 실패마다 로그 경로, 문구, 스크립트 경로, 맞는 가설(H1~H3 또는 없음), `--verbose` 재실행 5회의 결과.
3. 실패가 0이면: 묶음별 실패율의 95% 상한(0/N이면 약 3/N. 예: 0/100 → 3% 미만)을 적고, "옛 저장소의 약 5%(20여 회 중 1회)보다 낮다고 볼 수 있는가"를 숫자로 답한다. 0/100이면 실제 실패율이 5%일 확률은 0.95^100 ≈ 0.6%다.
4. B5는 화면 작업 뒤, B6은 지시서 4 뒤에 따로 보고한다.
5. 재발 방지 제안(예: `run_dev.py`가 다른 Godot가 돌고 있으면 `--import`를 건너뛰기)은 제안으로만 적는다.

---

## 지시서 4 — 옛 층 정리(refactor-architect)

### 근거(2026-11-16 tech-lead가 실제 파일에서 셈)

**`이름__층` 메서드: 5개 파일에 172개.** 이 가운데 22개는 파일 안에서 호출하는 곳이 없다(문자열 호출·`Callable`도 없음 확인).

| 파일 | 층 메서드 | 층 표지(`# ----`) | 체인이 긴 메서드(층 수) | 호출 없는 층 메서드 |
|---|---|---|---|---|
| `chapter1/view/actors/chapter_actors.gd`(1,710줄) | 60 | 20 | `_update_pose`(12), `_create`(9), `sync`(8), `setup`(8), `reset`(7), `_overlaps_hero`(5) | 5: `_overlaps_hero__cloister`, `_sync_hero_rim__cloister`, `_demon19_materials__chapterx`, `_sample_actor42__chapterx`, `_set_color42__chapterx` |
| `chapter1/view/hud/chapter_hud.gd`(1,420줄) | 40 | 19 | `sync`(10), `_build_modal`(7), `setup`(6), `_card_description`(3) | 8: `_style__cloister`, `_label__cloister`, `_button__cloister`, `_stats__cloister`, `_inventory__cloister`, `_build_stash__chapter`, `_show_discovery__q17`, `_sigil__q17` |
| `chapter1/view/fx/chapter_effects.gd`(1,050줄) | 36 | 14 | `setup`(12), `sync`(9), `reset`(7), `consume`(5) | 0 |
| `chapter1/view/world/chapter_world.gd`(771줄) | 25 | 12 | `setup`(10), `_prop`(3) | 6: `_ground_material__q03`, `_compose_cloister__q03`, `_compose_verges__q03`, `_ground_material__chapter`, `_voussoir22__q22`, `set_columns31__q31` |
| `chapter1/app/chapter_one.gd`(510줄) | 11 | 5 | — | 3: `_unhandled_input__chapter`, `_pilot_input__chapter`, `_print_result__chapter` |

**옛 층 파일: 17개.** `chapter1/view/` 바로 아래 16개(`cloister_world.gd`, `cloister_world_quality03.gd`, `cloister_actors.gd`, `cloister_effects.gd`, `cloister_hud.gd`, `chapter_world.gd`, `chapter_world_quality10/17/18/22/31/31b/31c/31d/37/37b.gd`)와 `chapter1/core/combat_run.gd`.

**CLAUDE.md의 설명과 실제가 다르다.** CLAUDE.md는 "평탄화한 파일들이 옛 층을 밑바탕으로 상속한다"고 쓰지만, 평탄화한 다섯 파일은 모두 `extends RefCounted`(진입은 `Node3D`)다. 옛 층이 실행 중에 로드되는 길은 두 곳뿐이다.

1. `chapter1/app/chapter_one.gd:7-11`이 옛 층 5개를 `preload`하고 14~17·21행에서 인스턴스를 만든다. 346~347행의 `_init`이 곧바로 새 본체로 바꾼다. 만든 뒤 버리는 낭비다.
2. `chapter1/view/world/chapter_world.gd:733-734`가 12단 체인의 끝(`chapter_world_quality37b.gd`)을 만들어 `_voussoir22()`와 `_chamfer37()` 두 함수만 빌려 쓴다(735~745행).

이 두 곳을 끊으면 게임 실행 중에 옛 층 17개가 하나도 로드되지 않는다(`combat_run.gd`는 `chapter1/tests/test_combat_run.gd`가 계속 쓴다). 지금은 17/17이 로드된다(tech-lead가 아래 검사 스크립트로 확인).

옛 층이 아니라 지금도 쓰이는 부품(정리 대상 아님, 그대로 둔다): `element_emblem.gd`, `ember_staff_visual.gd`, `equipment_sigil_quality17.gd`, `equipment_sigil_quality35.gd`, `ui38/element_seal.gd`, `ui38/life_seal.gd`, `ui51/chapter_route51.gd`, `chapter1/view/` 바로 아래의 셰이더들.

### 시작 조건

1. 화면 작업(ui-hud, vfx-feel, character-artist)이 끝나 디렉터가 그 결과를 커밋했다. 그 커밋을 `<START>`라 한다.
2. 지시서 1의 "후" 측정이 끝났다(정리 전의 화면 코드로 재야 한다).
3. 다른 에이전트가 `chapter1/app/**`, `chapter1/view/**`를 고치지 않는다(디렉터가 확인).
4. 단계 R4의 파일 하나를 시작할 때마다 그 파일을 다른 사람이 고치지 않는지 디렉터에게 확인받는다.

### 고칠 수 있는 파일

- R1: `chapter1/app/chapter_one.gd`
- R2: `chapter1/view/world/chapter_world.gd`, 새 파일 `chapter1/view/world/stone_geometry.gd`
- R3: 없음(확인만)
- R4: 한 번에 한 파일씩 `world/chapter_world.gd` → `app/chapter_one.gd` → `fx/chapter_effects.gd` → `hud/chapter_hud.gd` → `actors/chapter_actors.gd`
- `_local/refactor/t4/**`(덤프, 비교 스크립트, 기록)

### 건드리면 안 되는 파일

- `chapter1/core/**`, `chapter1/data/**`, `chapter1/tests/**`, `tools/**`.
- 옛 층 파일 17개: **지우지도 고치지도 않는다.** 지우는 것은 R3 뒤에 디렉터가 따로 정한다.
- 위 "쓰이는 부품" 목록, `view/fx/combat_juice.gd`, `view/hud/combat_bar.gd`, `view/hud/skill_tree_panel.gd`, `view/hud/palette.gd`, 셰이더, 아트.
- `tools/dev/flatten_chain.py`.

### 동등성 확인 방법(모든 단계에 공통)

**기준 덤프**(`<START>`에서, 고치기 전에): 주력 셋, 각 두 번(흔들림을 알기 위해).

```powershell
& $G --headless --fixed-fps 60 --path C:/Project/witch-moira --script res://chapter1/tests/hud_dump.gd -- `
  --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=$PRIMARY `
  --dump=C:/Project/witch-moira/_local/refactor/t4/base-$PRIMARY-$N.json --scene=C:/Project/witch-moira/_local/refactor/t4/base-$PRIMARY-$N-scene.json
```

- 출력의 `HUD_DUMP {label, hash}`와 `SCENE_DUMP {label, hash}` 줄이 비교의 1차 기준이다. 시점은 메뉴·보관함·성장 선택·120틱·인벤토리·정지·더 좋은 장비 알림·2400/9000/16000틱·끝(`hud_dump.gd:120-182`).
- 알려진 흔들림: ✓ 글자 라벨 폭 82/83px, 측정 중 키 입력이 들어간 "소리" 알림 문구(`docs/DIRECTOR-PLAN.ko.md` 2.8절). 기준 두 번 사이에 다른 해시가 나오면 그 차이를 JSON에서 찾아 "허용 차이 목록"으로 적고, 그 밖의 차이는 허용하지 않는다.

**단계마다 끝에 돌릴 것:**

1. 위 덤프를 주력 셋으로 다시 → 모든 시점의 해시가 기준과 같거나, 다른 것이 허용 차이 목록 안이다.
2. `& $G --headless --path . --script res://chapter1/tests/golden_core.gd` → 4건 불일치 0(코어를 건드리지 않았다는 확인).
3. `python tools/dev/run_all.py --quick` → 전부 통과.
4. 창 실행 20초: `& $G --path . res://chapter1/ChapterOne.tscn -- --chapter1-start --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-quit-after=20` → 로그에 `SCRIPT ERROR`, `Parse Error`, `Could not resolve` 0건.

**옛 층 로드 수 검사**: `_local/refactor/t4/old_cached.gd`를 아래처럼 쓴다(tech-lead가 같은 내용으로 지금 17/17을 확인했다).

```gdscript
extends SceneTree
const OLD := ["res://chapter1/core/combat_run.gd","res://chapter1/view/cloister_world.gd","res://chapter1/view/cloister_world_quality03.gd","res://chapter1/view/cloister_actors.gd","res://chapter1/view/cloister_effects.gd","res://chapter1/view/cloister_hud.gd","res://chapter1/view/chapter_world.gd","res://chapter1/view/chapter_world_quality10.gd","res://chapter1/view/chapter_world_quality17.gd","res://chapter1/view/chapter_world_quality18.gd","res://chapter1/view/chapter_world_quality22.gd","res://chapter1/view/chapter_world_quality31.gd","res://chapter1/view/chapter_world_quality31b.gd","res://chapter1/view/chapter_world_quality31c.gd","res://chapter1/view/chapter_world_quality31d.gd","res://chapter1/view/chapter_world_quality37.gd","res://chapter1/view/chapter_world_quality37b.gd"]
func _initialize() -> void:
	var view: Node = load("res://chapter1/ChapterOne.tscn").instantiate()
	root.add_child(view)
	var n := 0
	for p in OLD:
		if ResourceLoader.has_cached(p): n += 1
	print("OLD_CACHED ", n, "/", OLD.size())
	view.queue_free()
	quit(0)
```

### 단계

**R1 — 진입의 버리는 인스턴스 없애기(`chapter1/app/chapter_one.gd`)**

- 7~11행의 옛 층 `preload` 다섯 개(`CombatRun`, `World`, `Actors`, `Effects`, `HUD`)를 없애고, 14~17·21행의 `var run=CombatRun.new()` 등을 초기값 없는 선언으로 바꾼다. 실제 인스턴스는 지금처럼 346~347행 `_init`에서 만든다.
- `_init` 이전에 이 변수를 읽는 곳이 없는지 확인한다(필드 초기화식, `_init` 앞의 코드).
- `Audio`, `FrameProbe`(`chapter1/presentation/*`), `CombatJuice`는 그대로 둔다.
- 기준: 공통 확인 1~4 + 옛 층 로드 수가 17 → **12 이하**(남는 것은 12단 체인).

**R2 — 돌 기하 함수 옮기기(`chapter1/view/world/`)**

- 새 파일 `chapter1/view/world/stone_geometry.gd`(`extends RefCounted`)에 `chapter_world_quality37.gd`의 `FACES37`, `_chamfer37`, `_polygon37`, 그리고 `_voussoir22`(37b의 것: 37의 `_voussoir22` 결과에 띠 두 개를 덧붙이는 형태)를 옮긴다. 두 층의 `_voussoir22`는 이름을 나눠(예: `_voussoir_base`, `voussoir`) 한 파일 안에서 같은 순서로 계산한다. **실수 상수, 연산 순서, 반복 순서를 그대로 둔다.**
- 옛 파일의 들여쓰기는 공백 한 칸이다. 새 파일은 탭으로 쓴다.
- `chapter1/view/world/chapter_world.gd:733-745`의 `Geometry37b` 참조를 새 파일로 바꾼다.
- 메시 동등성 검사 `_local/refactor/t4/mesh_check.gd`: 옛 `chapter_world_quality37b.gd`의 인스턴스와 새 `stone_geometry.gd`로 각각 (가) `_voussoir22()`, (나) `RearMasonry22`용 점 8개(`chapter_world.gd:740-744`)의 `_chamfer37(points,.07)`, (다) 37b가 덧붙이는 띠의 `_chamfer37(points,.12)`를 만들어 `surface_get_arrays(0)`의 정점·법선·색인 배열 해시를 비교한다. 참고값(tech-lead 측정, `<START>` 전 코드): 옛 `_voussoir22()`는 정점 396개, `var_to_str(arrays[Mesh.ARRAY_VERTEX]).sha256_text().left(16)` = `5abf17baaea672ab`.
- 기준: 메시 해시 세 쌍 모두 같음 + 공통 확인 1~4 + 옛 층 로드 수 **0/17**.

**R3 — 확인과 보고(파일 변경 없음)**

- 옛 층 17개를 참조하는 곳이 `chapter1/tests/test_combat_run.gd`(→ `combat_run.gd`)와 옛 층끼리뿐임을 검색으로 보인다.
- 디렉터에게: (가) 옛 층 16개 삭제 여부, (나) CLAUDE.md "알아 둘 흔적"의 문장 수정안(실제와 다른 "상속한다" 표현)을 올린다. 결정 전에는 지우지 않는다.

**R4 — 층 메서드 정리(파일 하나씩, 순서: world → app → effects → hud → actors)**

파일마다:

1. 호출 없는 층 메서드(위 표의 22개 중 그 파일 몫)를 다시 검색해 확인하고 지운다. 문자열 호출(`call`, `Callable`, `connect`의 이름 문자열)이 없음을 함께 확인한다.
2. 체인 `x__a → x__b → … → x`가 앞층을 맨 앞이나 맨 뒤에서 한 번 부르는 단순한 형태면, 문장 순서를 그대로 유지하며 한 메서드로 합친다. 중간에서 부르거나 조건부로 부르는 체인은 합치지 말고 뜻이 드러나는 이름으로만 바꾼다(예: `setup__q14` → `_setup_element_meshes`).
3. 파일 머리의 "Flattened by …" 설명과 `# ---- 층 ----` 표지는 그 층의 메서드가 다 사라졌을 때만 지운다.
4. 한 파일을 끝낼 때마다 공통 확인 1~4를 돌리고 기록한 뒤 다음 파일로 간다. 파일 하나가 끝나면 디렉터가 그 상태를 커밋할 수 있게 보고한다(커밋은 디렉터가 한다).

### 끝났다는 기준

| 단계 | 숫자 기준 |
|---|---|
| R1 | 덤프 해시 전 시점 일치(허용 목록 밖 차이 0), 골든 불일치 0, `run_all --quick` 통과, 스크립트 오류 0, 옛 층 로드 17 → 12 이하 |
| R2 | 메시 해시 3쌍 일치, 위 공통 기준, 옛 층 로드 0/17 |
| R3 | 참조 검색 결과 첨부, 디렉터 결정 요청 |
| R4 | 파일마다 공통 기준 통과. 층 메서드 172 → 파일별 감소 수 보고. 호출 없는 22개는 0으로 |

---

## 5. 기술 검토 — 1대1 보스전("어머니와의 결전")이 코어에 요구하는 것

지시서가 아니다. 근거는 `chapter1/core/combat_core.gd`, `chapter1/core/chapter_core.gd`, `chapter1/data/combat_tuning.json`, `docs/reviews/STORY-REVIEW-20261116.ko.md` 3절·5.2절·5.3절.

### 5.1 지금 코어의 우두머리 처리

| 무엇 | 어디 | 내용 |
|---|---|---|
| 구역 우두머리·최종 보스의 등장 | `chapter_core.gd:416-428` | 봉인 처치 수를 채우면 `"elite"` 종류 적 하나를 만들고 `tuning.champions[zone]`으로 생명·전조·회복·피해를 덮어쓴다. 3구역이면 `chapter_boss=true`, 이름 "회랑의 파수왕" |
| 공격 상태 기계 | `combat_core.gd:394-452` | 이동 → `windup`(전조 사전 `telegraph`: 모양·방향·반경·길이·폭·광선, 남은 틱) → 판정 → `recover`. 우두머리는 `attack_index`에 따라 원형과 부채꼴을 번갈아 쓴다(442행) |
| 우두머리별 특수 패턴의 선례 | `chapter_core.gd:465-478` | 2구역 우두머리가 원형 대신 "서리 십자"(캡슐 4개, 전조와 판정이 같은 도형)를 쓴다. `super._step_enemies()` 앞에서 상태를 바꿔 끼우는 방식 |
| 바닥 공격(`boss_ward`) | `chapter_core.gd:712-741` | 최종 보스가 살아 있는 동안 3~4초마다 주인공 자리에 반경 1.8m 원을 72틱 전조 뒤 터뜨린다. 2단계에서는 원 셋. `chapter_warning`/`chapter_burst` 이벤트 |
| 단계 전환 | `chapter_core.gd:716-718` | 생명 50% 이하에서 `_boss_phase` 1 → 2, 회복 65틱으로 단축, `boss_phase` 이벤트 |
| 큰 한 방 간격 | `combat_core.gd:530-552`, `chapter_core.gd:450-462`, `:720-724` | 최대 생명 20% 이상 피해는 120틱 안에 연달아 오면 10%로 깎인다. 보스는 바닥 공격 직후 60틱 안에 끝나는 전조를 시작하지 않는다 |
| 적 탄 | `combat_core.gd:554-565`, `:707-710` | 직선 등속, 반경 0.16, 수명 210틱, 적 탄 상한 192, 전체 탄 상한 384. 주인공과의 판정은 이동 선분 거리 |
| 군중 | `combat_tuning.json` `spawn.boss_phase` | 최종 보스전 동안에도 60틱마다 4마리씩 나온다 |
| 패배와 재도전 | `chapter_core.gd`/`combat_core.gd:549-552`, `chapter1/app/chapter_one.gd:127-129` | 생명 0이면 `defeat`. 재도전은 시드+1로 **판 전체를 처음부터** 다시 한다. 코어에는 `snapshot()`은 있지만 되돌리기(`restore`)가 없다 |
| 주인공 상태 이상 | 없음 | 주인공에게 느려짐·빙결·기절이 없다. 회피(`_dash_until`, 12틱)와 피격 무적 틱만 있다 |

### 5.2 재사용할 수 있는 것과 새로 필요한 것

| 결전에 필요한 것 | 재사용 | 새로 필요 |
|---|---|---|
| 단일 보스 개체 | 적 사전, 생명·반경·판정, 자동 시전의 대상 선택(`_near`로 13m 안), 빙결·기절 저항 규칙(우두머리는 기절 6틱·빙결 12틱) | 이동·군중 밀치기를 건너뛰는 보스 전용 상태 기계(서리 십자처럼 `_step_enemies` 앞에 끼우는 방식으로 가능) |
| 패턴과 전조 | `telegraph` 사전과 그것을 그리는 표현, 서리 십자의 "전조 도형 = 판정 도형" 원칙, 바닥 원 | 패턴 목록을 데이터로 읽어 순서대로(또는 정해진 난수로) 고르는 순서기. 모양 추가(고리, 나선, 조준 연사, 지연 폭발, 선 장판) |
| 주인공 기술의 원형을 쓰는 공격 | 기술 데이터(`growth_quality36.json`의 투사체 수·퍼짐·반경·연쇄·갈래·빙결)를 숫자 원천으로 쓸 수 있다 | **적 → 주인공 방향의 판정기.** 지금 기술 판정(`_damage_enemy`, `_chain`)은 적을 때리는 쪽만 있다. 화염 = 탄 + 착탄 폭발 장판, 냉기 = 부채꼴 + 느려짐 장판 + 파쇄, 번개 = 즉시 연쇄는 피할 수 없으므로 **전조가 있는 선 장판**으로 바꿔야 한다(서리 십자의 캡슐 판정 재사용) |
| 탄막 | 적 탄 배열·이동·주인공 판정, 상한 | 탄마다 반경·속도·수명·회전·가속·지연 출발을 갖게 하는 확장. 적 탄 상한(192)과 전체 상한(384)을 보스전에서 따로 잡는 규칙 |
| 단계 전환 | `_boss_phase`와 생명 비율 판정, `boss_phase` 이벤트 | 단계마다 패턴 묶음을 바꾸는 데이터, 단계 전환 중 무적·정지 시간 |
| 공정한 큰 한 방 | 큰 한 방 간격 규칙, 바닥 공격 간격 | 패턴끼리 겹침 규칙(전조 끝 시각 간격)을 일반화 |
| 지면 재도전 | 패배 판정, 첫 처치 영수증(저장의 `first_rewards`) | **결전만 따로 시작하는 진입.** 지금은 재도전이 판 전체(5~6분)다. 아래 5.4 참조 |
| 주인공 상태 이상(냉기·번개 어머니가 쓴다면) | 없음 | 주인공 느려짐·기절과 그 표현, 자동 조작의 대응 |
| 자동 조작 | `chapter_pilot.gd`(72줄, 군중 전투용) | 전조를 피하는 보스전 조작. 이것 없이는 골든·측정을 만들 수 없다 |
| 측정 | `measure_combat.gd`의 위협·큰 한 방 지표 | 보스전 지표: 교전 시간, 패턴별 피격률, 전조 최소 틱, 단계별 피해 창 |

### 5.3 결정론과 골든에 주는 영향

- **지금 골든 4건은 결전 코드가 꺼져 있으면 바뀌지 않게 만들 수 있다.** 조건 두 가지:
  1. 결전 코드가 기존 난수(`_spawn_rng`, `_loot_rng`)를 소비하지 않는다. 패턴 선택에는 시드에서 따로 만든 별도 난수 흐름을 쓴다.
  2. 결전이 아닐 때 `snapshot()`에 새 키를 넣지 않는다. 골든은 600틱마다 `JSON.stringify(run.snapshot())`의 해시를 비교한다(`chapter1/tests/golden_core.gd:20-21`). 영구 성장의 `build` 키가 "빌드가 있을 때만" 들어가는 것(`chapter_core.gd:774-780`)과 같은 방식으로 한다.
- 위 두 조건을 지키면 결전은 **새 골든 사례**(어머니별 1건 이상)로 따로 고정한다. 보스전 자동 조작이 먼저 있어야 한다.
- 지금의 최종 보스(파수왕)에 새 패턴을 먼저 붙여 시험하는 안도 있다. 그러면 골든 4건 중 3건(파수왕까지 가는 사례)이 의도적으로 바뀌고 `--update`가 필요하다. 드랍 시뮬레이션·측정도 다시 돌린다.
- 탄막 탄 수가 늘면 투사체가 `snapshot()`에 들어가므로 골든 해시 계산 시간이 늘어난다(골든은 이미 회귀에서 가장 오래 걸리는 검사 가운데 하나다). 체크포인트 간격은 그대로 두고 지켜본다.
- 코어 틱 비용: 적 탄의 주인공 판정은 탄 수에 비례하는 선형 비용이라 200발 정도는 작다. 문제는 표현 쪽(프레임 시간이 이미 CPU 병목, 지시서 1)이다.

### 5.4 지면 재도전 — 진입 방식에 따라 코어 작업이 크게 달라진다

| 안 | 내용 | 코어 작업 |
|---|---|---|
| 가 | 결전은 던전 한 판의 끝. 지면 판 전체를 다시 | 작다. 하지만 재도전마다 5~6분이라 1대1 보스전의 반복 학습과 맞지 않는다 |
| 나 | 결전에 들어간 순간의 판 상태(레벨, 은총, 장비)를 저장해 두고, 지면 그 상태로 결전만 다시 | 중간~크다. 한 판 성장 상태의 직렬화·검증·복원이 새로 필요하고, 저장 스키마 3에 필드가 는다(v1·v2 읽기 호환은 유지해야 한다) |
| 다 | 결전은 독립 무대. 영구 성장(트리·장비)만 가져오고 판 안 성장은 정해진 묶음(예: 레벨 상한, 은총은 결전 전 고르기)으로 시작 | 작다~중간. `configure_build`와 장비 가져오기(`import_starting_gear`)는 이미 있다. 판 안 성장을 정해진 상태로 시작하는 진입만 새로 |

코어 쪽 권고는 **다**다. 결정론과 골든 관리가 가장 단순하고, 재도전이 빠르다. 이것은 기획 판단(design-lead)이 필요하다.

### 5.5 코드를 어디에 둘 것인가

- `chapter_core.gd`(865줄)에 더 넣지 않는다. 결전 규칙은 새 모듈(예: `chapter1/core/boss_encounter.gd`, `RefCounted`)로 두고, 코어의 `step`이 지금의 `_step_chapter_hazards`처럼 한 줄로 부른다. 수치와 패턴은 새 데이터 파일(예: `chapter1/data/bosses.json`)에 둔다.
- 새 상속 층(`chapter_core`를 상속하는 결전 코어)은 만들지 않는다. 이 프로젝트는 상속 체인을 막 펴냈다.

### 5.6 작업 크기 어림

| 범위 | 크기 | 이유 |
|---|---|---|
| 세로 단면: 어머니 하나, 패턴 4~6개, 2단계, 진입 안 "다", 보스전 자동 조작, 새 골든 1건, 측정 지표 | **중간~크다** | 패턴 순서기와 적 → 주인공 판정기가 새 하위 체계다. 자동 조작의 회피는 지금 조작에 없는 능력이다. 이 셋이 없으면 검증할 수 없다 |
| 어머니 셋 전부와 단계 셋, 주인공 상태 이상 | **크다** | 계열마다 판정기가 다르다(특히 번개의 피할 수 있는 연쇄). 주인공 상태 이상은 이동·조작·표현을 함께 건드린다 |
| 진입 안 "나"(판 상태 저장 후 재도전) | 위에 **중간** 추가 | 저장 스키마와 복원 검증 |

표현 쪽(전조·탄막 그리기, 보스 생명 막대, 컷인)은 이 어림에 넣지 않았다.

### 5.7 3D 모델 없이 2D 일러스트 + 탄막으로 싸우는 안

- **코어 쪽 비용은 거의 같다.** 코어는 모델을 모른다. 보스는 위치·반경·상태를 가진 개체일 뿐이다.
- 코어가 조금 싸지는 경우는 하나다. 보스를 **움직이지 않는 발사원**(무대 한쪽에 고정된 그림 + 고정된 피격 범위)으로 두면 접근·군중 밀치기·근접 판정이 빠지고, 공격이 전부 탄과 장판이 된다. 이 부분은 5.2 표에서 "보스 전용 상태 기계" 한 줄의 크기를 줄일 뿐이다. 패턴 순서기, 적 → 주인공 판정기, 탄막 확장, 자동 조작의 회피, 측정은 그대로 필요하다. 그래서 코어 작업은 위 어림에서 한 단계 내려가지 않는다(세로 단면은 여전히 중간~크다).
- 단 고정 발사원이면 주인공의 자동 시전이 닿아야 한다. 자동 시전은 주인공 둘레 13m 안의 적만 노린다(`combat_core.gd:599`). 그림이 멀리 있더라도 피격 범위 개체는 무대 안 13m 안쪽에 둬야 한다.
- 절약은 아트·애니메이션 쪽에서 크다(3D 생성·리깅·Blender 공정이 빠진다). 대신 탄막은 표현 쪽 부담이 크다. 프레임 시간이 이미 CPU 병목이고(지시서 1), 아트 검수에서 "적 전조가 주인공 효과에 묻힌다"가 큰 문제로 남아 있다. 탄막을 하려면 결전 동안 주인공 효과의 양을 줄이는 규칙(표현 쪽)이 먼저 필요하다.

---

## 6. 순서와 병렬

| 묶음 | 과제 | 언제 | 같이 돌려도 되나 |
|---|---|---|---|
| 지금 | 지시서 3의 B1~B4b(헤드리스·사본) | 측정 창이 아닐 때 | 화면 작업과 병렬 가능(작업 트리를 건드리지 않는다) |
| 지금 | 지시서 2-1의 보조 스크립트 작성과 골든 동등성 확인(헤드리스) | 측정 창이 아닐 때 | 위와 같은 qa-perf라 직렬 |
| 측정 창 | 지시서 1(약 2시간 50분) → 지시서 2-1의 측정(A·B·C, 약 1시간) | 화면 작업 뒤, 다른 Godot 0 | **직렬만.** 측정 창 안에서는 다른 무엇도 돌리지 않는다 |
| 화면 작업 뒤 | 지시서 3의 B5 | 측정 창 밖 | — |
| 지시서 1 뒤 | 지시서 4 R1·R2·R3 | 화면 결과 커밋 뒤 | 지시서 2-2와 병렬 가능(파일이 겹치지 않음: app·view 대 core) |
| R2 뒤 | 지시서 3의 B6 | — | — |
| 코어 동결 해제 뒤 | 지시서 2-2(2-1이 확인했을 때만) | — | 지시서 4와 병렬 가능 |
| R3 결정 뒤 | 지시서 4 R4(파일 하나씩) | 그 파일을 다른 에이전트가 안 고칠 때 | 화면 에이전트의 다음 작업과는 파일 단위로 나눈다 |

담당이 qa-perf에 몰려 있다(지시서 1·2-1·3). 측정 창이 짧으면 지시서 1을 먼저 한다.
