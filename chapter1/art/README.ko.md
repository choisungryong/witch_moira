# 1장 아트 후보 — 2026-10-31

현재 아트는 독립 생성한 **2.5D PNG 스프라이트**이며, 리깅된 3D 모델이 아닙니다. 성인 비율의 다크 판타지 방향은 첫 플레이 후보로 승인받았으며 최종 C2 품질 승인은 남아 있습니다. 원본 GLB 제작 브리프는 대안 경로로 유지합니다.

- 바닥 알베도 후보는 `quality03/ground_flagstone_v01.png`, `quality03/ground_soil_v01.png`다(옛 README가 말한 `terrain/cloister_ground_v01.png`는 이 저장소에 없다). 실제 카메라에서 반복 이음새 확인 필요.
- `actors/{hero,walker,ranged,charger,elite}.png`: 각 4방향 × 4 이동 키프레임.
- `actors/{hero,walker,ranged,charger,elite}_actions.png`: 남쪽 기준 시전/공격 4, 피격 4, 사망 4프레임.
- 각 동명 JSON의 `frames[].region`은 가변 소스 사각형입니다. 단순 균일 셀 자르기를 사용하지 마세요. `frames[].feet`는 사각형 안의 발 기준점이며, `pixels_per_meter`와 프레임별 `texture`를 함께 적용합니다.
- `frames_by_direction`: south/east/north/west. `states`: idle/move/cast/hit/death, 적은 attack 별칭도 제공합니다.
- Godot Sprite3D의 양수 offset.y는 위쪽입니다. 뷰 담당자가 확인한 기준은 `(width/2 - feet.x, feet.y - height/2)`입니다.
- 전용 idle 클립은 아직 없습니다. idle은 이동 키프레임 하나를 유지합니다. 남쪽 외의 시전/공격/피격/사망 동작은 미제작입니다.
- `battle_mage_walk_4x4_v01.png`는 초기 레이아웃 증거로 보존했으며 런타임 대상은 `hero.png`입니다.

## 출처 원장

출처 원장은 [ASSET-LEDGER.json](ASSET-LEDGER.json) 하나다(2026-11-19, `python tools/art/asset_ledger.py migrate`로 합침). `chapter1/art/` 아래 에셋 파일(그림·SVG·모델·글꼴·소리) 104개가 한 항목씩이고, 항목에 경로·sha256·크기·출처 종류·라이선스·날짜·후처리·(생성물은) 모델·프롬프트가 있다. 지금 모르는 값은 지어내지 않고 "미확인"으로 적었다.

- 점검: `python tools/art/asset_ledger.py check`(원장에 없는 파일, 필수 칸 빈 항목, 해시 어긋남, 파일 없는 항목은 오류로 종료 코드 1. "미확인"과 배포 불가는 구멍 목록으로 나오고 `--strict`면 종료 코드 2). 새 파일은 `add`로 올린다. 도구 설명은 `tools/art/asset_ledger.py` 머리말.
- "배포 가능"은 원장에 적지 않고 check가 계산한다. 출처 기록이 갖춰지고(생성물은 모델·프롬프트·약관 확인까지) 사람이 `release_cleared`를 true로 표시한 것만 배포 가능이다. 지금은 0개다. 2026-11-19 기준 "미확인"이 있는 항목이 많다(대부분 `actors/`, `characters/`, `portraits/`, `ui/kit/`의 생성물).
- `quality03/`의 옛 기록(`ASSET-LEDGER-v01/v03/v04.json`, `GENERATED-*.json`, `GENERATION-PROMPTS.json`, `*-INSPECTION.json`, `ART-METADATA-RECOVERY.json`)은 지우지 않고 원본으로 보존한다. 원장은 v04를 기준으로 하고, 다른 기록의 다른 프롬프트 문장은 항목의 `prompt_other_records`에, 검사 결과는 `inspection`에 보존했으며 `records`에 해시와 함께 가리킨다.
- 폴더별 `ATTRIBUTION.ko.md`는 원장 항목의 근거 기록(`record_files`)으로 남는다. 그 안의 말이 실제 파일과 어긋난 곳(없는 v01 파일 등)은 원장 항목의 `notes`에 적었다.
- 이 저장소 이전의 출처 기록(옛 `plans/chapter1-c2-20261031-01/art/`)은 가져오지 않았다. `actors/`의 프롬프트·모델·날짜가 "미확인"인 까닭이다. 생성 결과를 CC0 또는 제3자 라이선스 모델로 표기하지 않는다는 서술은 옛 README 그대로 남기되, 근거 기록은 없다.

검사: 모든 채택 이동 시트에서 큰 알파 연결 요소 16개, 행동 시트에서 12개를 찾았고, 선택 사각형 안에 이웃의 큰 연결 요소가 들어오는 픽셀은 0개입니다. 이 검사는 리깅·시간적 일관성·실제 카메라 접지 품질의 승인을 대신하지 않습니다.

세부 검사와 제작 보고서가 있던 `plans/chapter1-c2-20261031-01/art/`는 옛 저장소의 것이며 이 저장소에 없습니다(`quality03/`의 `*-INSPECTION.json`은 있음).

