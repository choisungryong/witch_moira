# 은총 화면(성장 선택)의 그림 출처 (A8 G6)

- 제작: **Codex 생성**(gpt-5.6-sol, Codex CLI의 이미지 생성), 2026-11-20. 대기열 id와 프롬프트 전문은 `prompts/<파일 이름>.prompt.txt`.
- 가공: 테·바탕·상징·판·촛대 등 마젠타 바탕 그림은 `tools/art/matte_kit.py`(A8 G1)로 바탕을 알파로 떼고 번짐을 없앴다. 다시 그리지 않았다.
- `demon-ember.png`, `demon-frost.png`, `demon-arc.png`: **임시 인물**. 사용자가 악마의 겉 그림을 아직 고르지 않아 대기열의 `pledge-ember-full-a1`, `pledge-frost-full-c-a1`, `pledge-arc-full-a2`를 가공 없이 넣었다. 자리표(`asset_slots.json`)의 `source`에 "TEMPORARY"로 적혀 있다. 고르면 바꾼다.
- 들이지 않은 것: `emblem-ember-new`(가운데가 까맣게 뚫린 아치)는 쓰지 않는다. 그 카드는 코드 도형으로 떨어진다.
- 약관: 생성 도구 이용 약관은 확인 전이다(원장 license 칸이 "미확인").
