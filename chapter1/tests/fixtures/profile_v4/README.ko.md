# v4 저장 고정 묶음 (T6-S0)

만든 날: 2026-11-19. 만든 코드: 커밋 `67b2184`(저장 스키마 4, `chapter_profile.gd`는 `7de9f92` 이후 바뀌지 않음, 작업 트리와 HEAD가 같음). 지시서: `docs/specs/T6-save-schema5-directives-20261119.ko.md` T6-S0.

**다시 만들지 않는다.** 저장 코드가 스키마 5로 바뀐 뒤에는 만들 수 없고, 다시 만들어 검사를 통과시키는 것은 금지다. 바꿔야 하면 디렉터 승인이 먼저다. 생성기는 `expected_v4.json`이 있으면 실행을 거부한다(종료 1).

전부 그 커밋의 실제 코드가 격리 경로(`_local/`)에서 **새로 만들어 낸** 저장이다. 사용자의 실제 저장(`%APPDATA%\WitchMoira`)은 읽거나 복사하지 않았다.

## 만든 명령

```
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/make_profile_v4_fixtures.gd
```

## 확인 명령

```
python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_profile_v4_fixtures.gd
```
마커 `CHAPTER1_PROFILE_V4_FIXTURES_RESULT`. 묶음 바이트(sha256)와, 지금 코드가 각 장면을 `expected_v4.json`대로 읽는지 본다. 읽은 결과는 `chapter1/tests/profile_v4_snapshot.gd`의 `describe`가 만든 값이다. 화면 글(`name`, `description`)을 뺀 전체 비교와 화면 이름 비교를 따로 한다.

## 파일

| 파일 | 대표하는 것 |
|---|---|
| `v4_full.json` | `fixtures/profile_legacy/v3_full.json`을 옮긴 뒤 실제 저장 함수들로 채운 v4 저장. 서리·화염 의상 입음, 서리 `wardrobe.owned` 하나, 서리 `story.seen` 둘·`found` 하나(시험 훅 id `beat.one`, `beat.two`, `item.coin`), `shared_story.seen` 하나, 서리 `tree_reset.granted`에 `d1`, 서리 `depth_cleared` `{"d1":1}`, 도감(고유 3, 전설 3), `locked` 장비 하나·`new` 장비 하나, 마녀마다 다른 `loadout`, 격리 장비 하나(`base_id`를 모르는 id로 바꿈), 격리 마녀 하나(`chapter1.character.ghost`). 리비전 32 |
| `v4_with_journals/` | 본 파일 `chapter-one-profile-v4.json`(두 장비가 같은 `storage_id`라 `incompatible`로 거부됨) + `revisions/…revision-00000N-20261119-0-0.json` 4개(리비전 1~4, 읽힘) + `chapter-one-profile-v4-active.json` + 그것이 가리키는 `chapter-one-profile-v4-r20261119-120000.json`(리비전 4에서 이어 만든 것) |
| `expected_v4.json` | 각 장면을 그 커밋의 코드가 읽은 값과 묶음 파일의 sha256, 기존 `profile_v4_compat.json`의 sha256 |

기록본 이름의 프로세스 번호·마이크로초는 `0-0`으로, 날짜는 `20261119`로 고정했다(내용은 실제 저장 그대로). r-파일의 자기 기록본과 임시 파일은 넣지 않았다. 가리키는 파일의 `created_unix`와 파일 안의 `origin.at_unix`는 만든 시각이다.

장면 넷: `v4_full`, `v4_compat`(기존 `fixtures/profile_v4_compat.json`), `v4_journals_main_only`(가리키는 파일 없이: 거부, 이어 하기 후보 기록본 리비전 4), `v4_journals_with_pointer`(r-파일을 읽음). 정의는 `profile_v4_snapshot.gd`의 `SCENARIOS`다.

컴퓨터 경로와 사용자 이름은 어느 파일에도 없다(생성 뒤 검색으로 확인).
