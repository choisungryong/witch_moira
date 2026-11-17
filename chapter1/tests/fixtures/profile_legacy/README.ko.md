# 옛 저장 고정 묶음 (T5-S0)

만든 날: 2026-11-17. 만든 코드: 커밋 `208112d`(저장 스키마 3, `chapter_profile.gd` 변경 전). 지시서: `docs/specs/T5-schema4-directives-20261117.ko.md` S0.

**다시 만들지 않는다.** 저장 코드가 바뀐 뒤에는 만들 수 없고, 다시 만들어 검사를 통과시키는 것은 금지다. 바꿔야 하면 디렉터 승인이 먼저다. 생성기는 `expected_v3.json`이 있으면 실행을 거부한다.

전부 그 커밋의 실제 코드가 격리 경로(`_local/`)에서 **새로 만들어 낸** 저장이다. 사용자의 실제 저장(`%APPDATA%\WitchMoira`)은 읽거나 복사하지 않았다.

## 만든 명령

```
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/make_profile_legacy_fixtures.gd
```

## 확인 명령

```
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_profile_legacy_fixtures.gd
```
마커 `CHAPTER1_PROFILE_LEGACY_RESULT`. 묶음 바이트(sha256), 그리고 지금 코드가 각 묶음을 `expected_v3.json`대로 읽는지 본다. 읽은 결과는 `chapter1/tests/profile_legacy_snapshot.gd`의 `describe`가 만든 값이다.

## 파일

| 파일 | 대표하는 것 |
|---|---|
| `v3_full.json` | 정상 스키마 3 저장. 문법 2 장비 36개(칸 7 × 등급 4 + 희귀 6 + 고유 3, 해체 1개로 번호가 비어 있음), 옛 v1 장비 2개, 8칸 착용(반지 둘). 서리: 경험치 3000·첫 처치 셋·투자 있음·전체 초기화 1회, 화염: 경험치 700만, 번개: 항목 없음 |
| `v3_rare_oldword.json` | 위 파일에서 희귀 이름 하나의 첫 낱말을 목록에 없는 낱말로 바꾼 것(글자 편집이라 숫자 모양은 그대로) |
| `v3_rare_threeword.json` | 위 파일에서 희귀 이름 하나를 세 낱말로 바꾼 것 |
| `v3_with_journals/` | 본 파일(장비 수치를 바꿔 `incompatible`로 거부됨) + 기록본 4개(리비전 1~4, 읽힘) + v3 가리키는 파일 + 그것이 가리키는 r-파일(기록본 리비전 4에서 이어 만든 것) |
| `v2_sample.json` | 스키마 2(장비 14개 = 착용 8칸 + 6개, 리비전 11, 완주 7, `characters` 없음) |
| `v1_sample.json` | 스키마 1(옛 4칸, v1 장비 5개) |
| `expected_v3.json` | 각 묶음을 그 커밋의 코드가 읽은 값: `configure` 결과·거부 종류, `state`, `characters`, 세 마녀 각각의 레벨·`starting_gear`·`blocked_gear`, 장비 번호별 화면 이름, 이어 하기 후보, 읽기가 파일을 건드리지 않았다는 확인, 파일 sha256 |

`v3_with_journals/`의 기록본 이름은 `…revision-<rev6>-0-0.json`이다. 실제 저장이 붙이는 프로세스 번호·마이크로초를 지워 이름을 고정했다(내용은 실제 저장 그대로). r-파일의 자기 기록본과 임시 파일은 넣지 않았다. 가리키는 파일의 `created_unix`는 만든 시각이다.

장면(scenario) 일곱 개: `v3_full`, `v3_rare_oldword`, `v3_rare_threeword`, `v3_journals_main_only`(가리키는 파일 없이: 거부, 이어 하기 후보 리비전 4), `v3_journals_with_pointer`(r-파일을 읽음), `v2_sample`, `v1_sample`. 장면 정의는 `profile_legacy_snapshot.gd`의 `SCENARIOS`다.

컴퓨터 경로와 사용자 이름은 어느 파일에도 없다(생성 뒤 검색으로 확인).
