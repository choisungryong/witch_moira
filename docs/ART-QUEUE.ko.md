# 그림 대기열 운용 (ART-QUEUE)

1판 · 2026-11-20 · 사용자 지시(원문): "코덱스에게도 생성도구를 통한 이미지 생성 요청을 해 토큰한도가 이제 너무 널널하네 체크하면서 필요한 이미지는 미리 생성해 놓는 도구를 만들어 놓고 에이전트한테 지속적으로 지시를 할 수 있게"

Codex CLI의 그림 생성(ChatGPT 로그인, 추가 과금 없음)을 놀리지 않도록, 앞으로 필요한 그림을 **목록(대기열)으로 관리하며 미리** 만들어 둔다. 도구는 `tools/art/gen_queue.py`, 목록은 `tools/art/gen_queue.json`, 항목의 프롬프트는 `tools/art/gen_queue_prompts/<id>.prompt.txt`, 결과는 `_local/art/queue/<id>/`다. 결과는 **`chapter1/art/`에 넣지 않는다**(채택은 디렉터와 사용자가 정한다).

## 1. 상태와 길

`후보(candidate)` → `프롬프트 준비(prompt_ready)` → `생성됨(generated)` → `검수 대기(review_pending)` → `채택(adopted)` / `버림(dropped)`.

- 자동으로 밟는 길은 **무료 길(Codex CLI)** 하나다. 항목의 `route`가 `codex-free`가 아니면(`paid-api`, `sunra`) 도구는 "승인 필요 · 예상 비용"으로 표시만 하고 실행하지 않는다. 비용을 제시하고 사용자 승인을 받은 뒤 별도로 한다(건별).
- `needs_user`가 적힌 항목은 사람의 선택·결정을 기다린다. 도구는 거르고, `--only <id>`로 id를 직접 부르면(사람의 허락으로 본다) 돌린다.
- 프롬프트는 `next`/`run`이 조립한다: 표준 머리말(저장 이름, 코드 금지) + 항목 문단 + 바탕 문장(자홍 / 검정 가산 / 불투명) + 공통 금지 문장. 프롬프트 검사(`lint`)는 매번 자동으로 걸린다: 금지 낱말(`wording-rules.json`), 사용자·프로젝트 이름, 다른 작품·작가 이름, "~의 화풍으로" 따위, 노출 낱말(부정문 밖), 미성년으로 읽히는 낱말, 인물 항목의 `adult`·`opaque` 명시.

## 2. 디렉터의 절차

1. **언제 scan** — 새 명세·조사 문서가 들어온 날, 화면 재설계의 새 차례가 시작될 때, 그리고 주마다 한 번(전체 점검 때). `python tools/art/gen_queue.py scan`으로 미리 보고 `--write`로 올린다. 긁는 곳: `asset_slots.json`의 planned 자리, 원장의 "임시/교체 예정" 글, 문서의 **`needs:` 한 줄**.
   - 문서 표식(코드 울타리 밖, 줄 처음): `needs: <id> | <무엇에 쓰나> | <크기> | <바탕 투명·검정·불투명> | <수량> | <우선순위 1~5>`. 명세·조사에서 "새 그림이 필요"할 때 이 줄을 한 줄 더하면 대기열로 온다.
   - 새로 올라온 후보는 프롬프트가 없다. 디렉터가 `art-lead`(또는 손)로 프롬프트 문단을 쓰고 `prompt_file`을 적은 뒤 `python tools/art/gen_queue.py set <id> prompt_ready`로 올린다.
2. **한 번에 몇 건** — 화면 시안이 기다리는 우선순위 0~1은 한 묶음 10~18건(한 건 약 2.5분, 한 묶음 30~50분). 나머지는 한 묶음 10건 안팎. 한 번에 하나씩만 돌고(`gen.py`가 순차 실행), 같은 대기열 도구를 두 곳에서 동시에 돌리지 못한다(`_local/art/queue/.run.lock`). 3D 시트 작업의 Codex와는 동시 실행이 되는 것을 확인했다(2026-11-20).
3. **지시** — `python tools/art/gen_queue.py next --n 10`이 찍는 **작업 지시문**(프롬프트·참고 그림·저장 자리·검수 기준)을 `codex-operator`에게 주거나, 디렉터가 바로 `python tools/art/gen_queue.py run --n 10 --execute --yes`로 돌린다. `run`은 `--execute --yes` 없이는 만들기만 하고(마른 실행) 아무것도 부르지 않는다.
4. **검수** — `run`이 끝나면 `python tools/art/gen_queue.py record <id> ... --bundle <묶음 이름>`: 결과를 받아 상태를 올리고, 검수 시트(`review_sheet.py`: 원본·가공·128/64/40px·실루엣)와 관리 툴 「원화 시안」의 묶음 "대기열 · <묶음 이름>"을 만든다. **그림은 직접 열어 본다**(크기·바탕이 평평한가·읽히는가·글자·금지 요소). 기계 점검(`checks`)은 크기·알파·자홍 비율·모서리 색일 뿐 판정이 아니다.
5. **사용자 선택** — 검수 대기 항목은 사용자가 「원화 시안」에서 고른다. 고른 것만 `set <id> adopted`, 아닌 것은 `set <id> dropped`. 채택 뒤에야 `chapter1/art/`에 넣고(`asset_intake.py`로 자리 계약 대조) 출처 원장에 올린다(`set ... adopted`가 `asset_ledger.py add` 명령 꼴을 알려 준다). 원장은 `chapter1/art/` 안의 파일만 받으므로, 시안 단계의 출처(도구·모델·날짜·프롬프트 해시·"시안"·약관 미확인)는 대기열 항목의 `provenance`에 적힌다. 약관 확인과 `release_cleared`가 없으면 배포 가능으로 표기하지 않는다.
6. **정리** — 버린 시도는 `prune --yes`로 그림과 작업 폴더를 지우고 프롬프트 기록만 남긴다(C 드라이브가 좁다). 생성이 끝난 작업 폴더(`work/`)는 도구가 바로 지운다.
7. **한도에 걸렸을 때** — Codex 실행 로그에 사용 한도·속도 제한 글이 보이면 도구가 그 묶음을 멈추고 항목의 `last_error`에 "limit hit"를 적는다(시도 수는 올라가지만 상태는 그대로). 우회하지 않는다. 한도가 풀린 뒤 같은 명령을 다시 부르면 남은 것부터 이어진다. 한 항목이 시도 3번(`MAX_ATTEMPTS`)을 채우면 도구가 거른다. 다시 하려면 프롬프트를 고친 뒤 `set <id> prompt_ready --note "reset"`.
8. **실행 뒤 확인** — 매 실행의 `outside check`(작업 폴더 밖 변경, `AGENTS.md` 해시, `.codex*`)가 비어 있어야 한다. 아니면 되돌리지 말고 보고한다.

## 3. 한눈에 보기

`python tools/art/gen_queue.py status`는 상태별 수, 지금 Codex에 줄 수 있는 것, 프롬프트 없는 후보, 사람을 기다리는 것, 승인이 필요한 것(예상 비용), 막힌 것을 한 장에 낸다. `status --json [파일]`은 같은 내용을 관리 툴이 읽을 수 있는 JSON으로 낸다.

## 4. 항목 필드

`id`, `title`, `use`(무엇에 쓰나), `source`(어느 지시·명세), `canvas`(Codex에 요청하는 크기), `target`(게임에 쓸 크기), `background`(`magenta` | `black` | `opaque` | 직접 쓴 문장), `count`, `priority`(0 최우선 ~ 5), `status`, `route`, `est_cost_usd`, `prompt_file`, `refs`(참고 그림), `ref_role`(`style`: 화풍만 | `same`: 같은 인물의 이전 판), `kind`(`icon`: 자홍 배경 제거 검수 | `image`), `has_person`, `slot`(자리표 id), `needs_user`, `depends_on`, `blocked`, `attempts`, `results`, `checks`, `provenance`, `history`.

## 5. 지켜야 할 것

- 프롬프트에 사용자·프로젝트 이름, 실존 인물·다른 작품·작가 이름을 쓰지 않는다. 인물은 성인으로 명시하고 노출은 확정 원화 수준을 넘지 않는다. 다른 작품의 그림을 따라 그리라는 말도 쓰지 않는다(결의 묘사: 어둡고 무게 있는 금속·돌·양피지, 절제된 색 위의 강한 한 점).
- 게임 코드·데이터를 고치지 않는다. 대기열 도구는 대기열 파일과 프롬프트 파일, `_local/`만 쓴다.
- 이름 규칙: "잿빛" 같은 분위기 낱말을 프롬프트와 글에 쓰지 않는다(`lint`가 금지 낱말 목록으로 걸러 준다).
