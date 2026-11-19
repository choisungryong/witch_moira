# 디스크 사용 관리와 D 드라이브 이전 계획 (2026-11-20)

상태: 도구는 패치로 올라와 있고, 이전은 **실행하지 않았다**(계획만). 지금 `_local`과 worktree에 여러 작업이 쓰고 있어 옮기면 깨진다.
사용자 지시: "하드가 부족해. 불필요한 사이즈가 큰 파일들을 삭제해줘", "필요하면 D:project 에 사용해줘"(D 여유 약 147GB).

## 1. 지금 상태(2026-11-20 00:52, `tools/dev/disk_report.py` 목록 모드, 파일 크기 합)

| 위치 | 크기 | 비고 |
|---|---|---|
| main `_local` | 14.1 GB | art 3.30, ref 2.67(보존), shots 2.23, perf 2.23, sfx 1.28(recheck 567MB 보존), snap 0.54, measure 0.45, run-all-fixtures 0.32 |
| main `.godot` / `.git` | 111 MB / 196 MB | |
| worktree 14개 | 합계 약 5 GB | 각자 추적 파일 약 200MB(chapter1/art 193MB) + `.godot` 111MB. `_local`이 큰 것: a3c45(shots/rs2 1.07GB), aa31b(char3d 0.5GB) |
| 전체 | 19.1 GB | |

되찾을 수 있는 것(도구 규칙 통과 = 재생성 가능·24시간 이상 안 쓰임·프로세스 없음): **지금은 0 B**. 격리 APPDATA 캐시와 픽스처 약 1.0GB는 최근 24시간 안에 쓰였거나(871MB) 본 저장소에서 Godot가 돌고 있어(157MB) 제외된다. 큰 공간은 사람이 정해야 하는 산출물이다. 2일 넘게 손대지 않은 목록 후보: snap 535MB, measure 449MB, review-l1 134MB 등 합 1.11GB. shots(2.2GB, 3일 된 것 다수)·perf(2.2GB)·art/drafts(2.15GB)는 최근 갱신이 섞여 디렉터가 폴더 단위로 판단한다. 구조적 낭비는 worktree마다 반복되는 약 300MB(추적 파일 + `.godot`)다.

## 2. 도구

- `python tools/dev/disk_report.py` — 큰 폴더 표(폴더/크기/파일 수/마지막 수정/종류/지워도 되는가). `--worktrees`는 worktree별 프로세스·마지막 수정·git 등록 여부. `--dups`는 중복처럼 보이는 큰 파일(목록만).
- `--clean` — 계획만. `--clean --apply`로 지움. 지우는 것은 규칙표(`RULES`)에서 clean=참인 세 종류뿐: 격리 APPDATA의 `shader_cache`·`logs`, `_local/run-all-fixtures/*`, **worktree**의 `.godot`(main의 `.godot`은 임포트가 느려 계획에 넣지 않음).
- 절대 지우지 않음(검사 `tools/dev/test_disk_report.py` 25건으로 고정): 사용자 폴더, git 추적 파일, `_local/HANDOVER*`, `_local/sfx/recheck-*`, `_local/ref/`, 24시간 내 사용(`--idle-hours`는 24 미만 불가), 살아 있는 프로세스의 cwd·명령줄이 안에 있는 폴더, 같은 checkout에서 Godot가 도는 동안의 main 캐시, 링크·읽지 못한 부분·시간 제한으로 덜 센 폴더, 프로세스 목록을 못 읽을 때 전부. 지우기 직전에 폴더를 다시 세고 프로세스를 다시 읽는다.
- 프로세스를 종료하지 않고 `git worktree remove`도 부르지 않는다. 중복 파일은 목록만(지우지 않음).
- 한계: 크기는 파일 크기(클러스터 아님). cwd가 아닌 다른 프로그램의 파일 핸들은 알 수 없다(삭제 실패는 보고하고 계속, 종료 코드 3).

## 3. 이전 방법과 위험

시험은 임시 저장소(C 임시 폴더 ↔ `D:\Project\_junctest*`, 시험 후 지움)에서 git 2.52로 했다. 본 저장소에서는 아무것도 옮기지 않았다.

### 3.1 `_local/`을 D로 (권장, 효과 14GB)
대상은 `D:\Project\witch-moira-local\_local` (끝 폴더 이름을 `_local`로 둔다: `audit.py`·`audio_recheck_20261120.py`가 `out.resolve().parts`에 `_local`이 있는지 보는데, 정션을 따라 해석하면 D 경로가 되므로 이름이 남아야 통과한다).
관측(시험): 정션 뒤에도 `git status` 깨끗, `git ls-files _local`은 추적되는 `_local/.gdignore`를 그대로 봄, 새 파일은 무시됨. 게임의 `res://_local/` 검사는 `globalize_path` 문자열이라 정션 이름 그대로.
위험: ① `Path.resolve()`·`realpath`가 D 경로를 줌(위 이름 규칙으로 완화, 나머지는 이전 후 `run_all --only tools-selftest`로 확인) ② **정션 안쪽을 따라가는 삭제**: 시험에서 `git worktree remove --force`가 worktree 안 정션의 대상 파일까지 지웠다. 정션을 지울 때는 `rmdir <정션>`(cmd)만 쓰고 정션 위에서 `Remove-Item -Recurse`·`git clean -fdx`는 금지 ③ 복사 중 쓰는 프로세스가 있으면 어긋남 ④ 상대 경로 도구는 정션 이름으로 그대로 동작.

### 3.2 격리 APPDATA(셰이더 캐시)만 D로
`tools/dev/isolated_env.py`에 환경 변수 `MOIRA_LOCAL_ROOT`를 넣었다(기본 불변, 검사 포함). 설정하면 격리 폴더가 `<MOIRA_LOCAL_ROOT>\_local\appdata\<용도>\`가 된다. `\_local\appdata\` 꼬리를 일부러 남겼다: `chapter1/tests/test_profile_*.gd` 등 11개 검사가 사용자 데이터 경로에 `/_local/appdata/`가 없으면 중단하기 때문이다(chapter1은 고치지 않음). 절대 경로만, `%APPDATA%\WitchMoira` 안쪽은 거부. 3.1을 하면 필요 없다. 3.1 없이 캐시만 옮길 때: 도구를 띄우는 셸에서 `$env:MOIRA_LOCAL_ROOT='D:\Project\witch-moira-local'`.

### 3.3 worktree를 D에 만들기 (비권장)
`.claude/worktrees` 자리는 하네스가 정한다. 그 폴더를 D로 가는 정션으로 바꾸면 `git worktree add`가 **풀린 D 경로**(`D:/Project/.../agent-x`)를 기록했다(시험). 그러면 `godot_ps.main_root()`가 경로에서 `.claude/worktrees`를 못 찾아 worktree를 main으로 착각하고 하네스의 경로 가정도 깨질 수 있다. 대신 worktree 안의 무거운 두 폴더만 정션: `<worktree>\.godot` → `D:\Project\witch-moira-wt\<이름>\.godot`, `<worktree>\_local` → `...\<이름>\_local`(시험: git status 깨끗, worktree remove가 D 쪽도 함께 지움). 코드가 worktree 안에 있어 `ROOT`는 변하지 않는다. 추적 파일 약 200MB는 C에 남는다. 이 정션을 자동으로 만드는 작업 시작 도구는 아직 없다(필요하면 별도 작업).

## 4. 조용한 때의 실행 차례 (3.1)
조건: `python tools/dev/godot_ps.py`에 프로세스가 없고, `disk_report.py --worktrees`에 main 관련 사용 중 프로세스가 없음. 디렉터가 모든 에이전트 정지를 확인.
1. (선택) `python tools/dev/disk_report.py --clean`으로 먼저 줄임.
2. `robocopy C:\Project\witch-moira\_local D:\Project\witch-moira-local\_local /E /COPY:DAT /R:1 /W:1 /XJ` (복사, 원본 유지, 종료 코드 8 미만이 성공).
3. 파일 수·바이트가 원본과 같은지 robocopy 요약으로 확인.
4. `ren C:\Project\witch-moira\_local _local.old`
5. `cmd /c mklink /J C:\Project\witch-moira\_local D:\Project\witch-moira-local\_local`
6. 확인: `git status`(변화 없음), `python tools/dev/run_all.py --only tools-selftest,manager`, `python tools/dev/run_dev.py --import-only`(D의 `_local\appdata\dev` 갱신 시각), 짧은 캡처 하나.
7. 이틀쯤 문제가 없으면 `_local.old`를 지운다(정션이 아님을 확인한 뒤) → C에서 14GB 회수.
되돌리기: `rmdir C:\Project\witch-moira\_local`(정션만 제거) → `ren _local.old _local`. 6 이후 D에서 새로 생긴 파일은 `robocopy D쪽 C쪽 /E`로 역복사. 7 전에는 C가 추가로 필요하지 않다(이름만 바꿈). 복사 전 C 여유 27GB, D 147GB.

## 5. 지우다 실패한 worktree 폴더 넷(관측, 삭제는 하지 않음)
| 폴더 | 지금 상태 | 원인 | 안전한 처리 |
|---|---|---|---|
| a149fff39fad87ecb, a34ace40058a515c9, ae27ae55822f9a985 (`agent-` 접두) | 내용 없는 빈 폴더, git에는 locked 등록 | 살아 있는 `bash.exe`(하네스가 남긴 셸, 각 2~4개)의 **현재 폴더**가 그 안이라 "Device or resource busy" | 에이전트가 끝났음을 확인한 뒤 그 `bash.exe`들을 디렉터가 종료 → `git worktree unlock <경로>` → `git worktree remove --force <경로>` → `git worktree prune`. 종료 없이는 지워지지 않는다 |
| agent-a05e101972a055a8c | `_local\appdata\exe-new\WitchMoira\shader_cache\SsaoInterleaveShaderRD\<해시>`의 빈 폴더 사슬뿐. 크기 0, git 미등록 | 셰이더 캐시가 디스크가 가득 찼을 때 파일이 아닌 폴더로 남은 항목으로 보임(원인 확정 못 함. 지금은 목록 정상, 잠근 프로세스 없음) | `cmd /c rd /s /q "\\?\C:\Project\witch-moira\.claude\worktrees\agent-a05e101972a055a8c"`. 그래도 "File too large"면 NTFS 손상 의심: 관리자 `chkdsk C: /scan`(읽기 전용) 결과를 본 뒤 결정 |

## 6. 사상
저장·보상(사용자 기록 보호)을 지키는 운영 도구다. 섹시·쾌감·도박·성장은 직접 키우지 않으므로 기능을 더 넓히지 않는다(디스크 부족이 작업 전체를 멈추는 것을 막는 용도).
