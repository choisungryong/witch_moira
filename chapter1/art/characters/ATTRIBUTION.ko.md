# 인물 일러스트 출처

2026-11-14. 사용자가 이미지 생성 도구로 직접 만들어 제공한 원화다. 프롬프트의 바탕은 `plans/director-redesign-20261114/ART-PROMPTS.ko.md`이며, 대화 중 여러 차례 고쳐 썼기 때문에 각 장에 쓰인 최종 프롬프트 문장은 정확히 기록되지 않았다. 생성 모델의 이름과 버전도 확인하지 못했다.

| 파일 | 인물 | 원래 파일명 | 비고 |
|---|---|---|---|
| `ember_witch/ember_witch_v01.png` | 잿불 계열. 사용자 지정: "잿불의 마녀"로 사용 | 마그마빛 베일의 뿔난 여인.png | 뿔이 있어 설계서의 구분으로는 후원자(여악마) 외형이다. 역할 배정은 사용자 결정을 따른다 |
| `frost_witch/frost_witch_v01.png` | 서리의 마녀(주인공) | 눈보라 속 얼음빛 사제전사.png | |
| `frost_patron/frost_patron_v01.png` | 서리의 여악마(후원자) | 서리 마법을 부리는 여왕 마녀.png | |
| `storm_patron/storm_patron_v01.png` | 뇌우의 여악마(후원자) | 폭풍의 번개 창을 든 전사 여왕.png | |

## v02 — 세 주인공 (2026-11-16)

사용자가 이미지 생성 도구로 직접 만들어 제공했다. 프롬프트의 바탕은 `plans/director-redesign-20261114/ART-PROMPTS-v2.ko.md`이고, 생성 뒤 대화로 고친 것(얼굴 나이, 숯 팔, 시선)이 있어 최종 문장은 정확히 기록되지 않았다. 생성 모델의 이름과 버전은 확인하지 못했다. 세 장 모두 PNG 1024×1536, 배경 포함.

| 파일 | 인물 | 표식 | 색 |
|---|---|---|---|
| `frost_witch_v02.png` | 서리 마녀(주인공, 인간) | 얼음으로 덮인 왼팔, 빛나는 왼눈 | 남색·은색·청록 |
| `ember_witch_v02.png` | 잿불 마녀(주인공, 인간) | 갈라진 숯 같은 오른팔, 빛나는 눈 | 검정·진홍·황동·주황 |
| `storm_witch_v02.png` | 뇌우 마녀(주인공, 인간) | 양 팔과 목의 번개 흉터 문양, 보랏빛 눈 | 청회색·보라 |

v02가 세 주인공의 기준 원화다. v01은 지우지 않고 남긴다(`ember_witch_v01`은 뿔이 있어 주인공 설정과 맞지 않았고, v02로 대체됐다). 노출 기준: 상의와 골반 가리개는 불투명, 망토와 늘어지는 자락만 반투명(사용자 결정, 15세 등급 게임 수준).

상태: 원화 보관만 했다. 게임 화면에 연결하지 않았고 배경 제거·크기 조정 같은 후처리도 하지 않았다. 배포에 쓰기 전에 생성 도구의 이용 약관과 수위 기준을 확인한다.

## 3D 몸 — 화염(테사) (2026-11-23~24)

`chapter1/art/actors/hero/ember/model.glb`(저장소에 올리지 않는다: `.gitignore`의 `chapter1/art/actors/hero/`, 이용 약관 확인 전. 냉기 `hero/frost/`도 같은 처지).

| 단계 | 내용 |
|---|---|
| 메시 | Tripo(웹, 구독)로 사용자가 손으로 만든 몸을 15k 삼각형으로 줄임. 눈 색은 묶음에 든 그대로 둠(사용자, 2026-11-24) |
| 뼈대·동작 | Mixamo(웹)에서 사용자가 손으로 뽑음, 2026-11-23: Standing Idle, Fast Run, Walking, Standing 1H Magic Attack 01, Standing 2H Magic Area Attack 01, Standing React Small From Front, Standing React Death Backward, Dodging Right |
| 묶기 | `tools/art/gen3d_mixamo_pack.py`, 설정 `tools/art/gen3d_mixamo_configs/ember.json`(동작 8개, `dodge_back` 없음) |
| 자리표 | `chapter1/art/asset_slots.json`의 `actor.hero.ember.model` |
| 도구·날짜 | Blender 5.3 묶기 2026-11-24 |

라이선스: Tripo 구독 약관과 Mixamo(Adobe) 약관. 배포에 쓰기 전에 두 약관의 상업 이용 조건을 확인한다.
