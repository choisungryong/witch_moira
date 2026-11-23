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


## 자리표(asset_slots.json)

코드는 에셋을 경로가 아니라 뜻 id(`actor.walker.model`)로 부른다. `asset_slots.json`이 id를 파일과 계약(뼈·클립 이름, 배율, 시간, 크기, 필수 상태)에 잇는다. 해결기는 `chapter1/view/assets/asset_slots.gd`다(`AssetSlots.scene(id)`, `.texture(id)`, `.bone(id, 논리이름)`, `.clip(...)`, `.scale3(id)`, `.timing(id, 키)`, `.contract(id)`, `.meta(id)`, `.missing()`).

- 에셋 하나를 바꾸는 일: 파일을 넣고, 자리표의 그 자리 한 줄(`file`, 필요하면 계약의 이름 대응)을 고치고, `python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_asset_slots.gd -- --strict`를 돌린다.
- `file`·`meta`는 이 폴더(`chapter1/art`) 기준 상대 경로다. `res://`로 시작하면 그대로 쓴다.
- 파일이 없으면 죽지 않고 대체물을 쓴다(그림은 자홍·검정 바둑판, 모델은 `fallback` 파일, 없으면 자홍 캡슐). 쓴 자리는 `missing()`에 기록되고 경고가 한 번 난다. `--strict` 검사는 계획된 자리(`planned: true`)가 아닌 자리에서 대체물이 나오면 실패한다. 배포 빌드 전에 이것이 통과해야 한다.
- `planned: true`는 아직 그림이 없는 새 자리다. 코드는 먼저 id로 들어가고, 그림이 오면 `file`을 채우고 `planned`를 지운다.
- `inherit`는 다른 자리의 종류·파일·계약을 물려받는다(자기 칸이 이긴다). 같은 사슬 악마 파일을 쓰는 역할들이 쓴다.
- 시간은 틱(`timing_ticks`, `tick_hz`)으로 적는다. `float(틱)/hz`가 코드의 `56.0/60.0` 같은 값과 비트까지 같다.
- `source` 칸은 값을 옮겨 적은 코드 위치(파일:행, 2026-11-19 기준)다. `used: "unverified"`는 코드가 부르는 듯하지만 실제로 로드되고 그려지는지는 확인 전이라는 뜻이다.
- 개발 중 시험: 저장소를 고치지 않고 `--chapter1-asset-slots=_local/...json`으로 다른 표를 읽는다(`_local/` 아래만).
- 출처는 `ASSET-LEDGER.json`, 소리는 `chapter1/data/audio_map.json`(예정)이다. 자리표와는 경로로 잇고 합치지 않는다.

### 에셋을 바꿀 때 자리표로 안 되고 함께 고쳐야 하는 것

1. UI 액체 셰이더(`ui_style.gd`): 구슬 조각이 원형 유리, 액체 그림이 가운데에 있다는 가정(반사 위치, 0.88 채움).
2. 초상 셰이더(`rig_body`·`rig_cloth`): 겹 종류의 뜻(천은 아래로 늘어짐, 엉덩이·가슴 높이 기준). 새 초상은 같은 겹 종류로 나눠야 한다.
3. 지면 셰이더(`chapter_ground*.gdshader`): 돌·흙 두 역할의 텍스처를 섞는다. 새 지형도 두 역할을 줘야 한다.
4. 원거리·돌진의 몸은 사슬 악마 몸을 비등방으로 눌러 만든다(`chapter_actors.gd`의 `_create__q21`). 역할마다 다른 모델이 오면 그 경로를 고쳐야 한다(코드).
5. 묶음 재질 `Minion19Batched`: 표면 하나·정점 색 가정. 재질이 여럿인 모델은 묶음이 깨진다.
6. 구운 움직임(VAT, `--chapter1-vat-walker`, 기본 꺼짐): 스킨이 있는 메시 가정. 모델을 바꾸면 다시 굽는다.
7. 글꼴: `project.godot`의 `theme/custom_font`는 프로젝트 설정이라 해결기를 거치지 않는다.
8. `.import` 설정: 같은 이름으로 덮어쓰면 유지, 새 이름이면 옛 `.import`의 필요한 값(밉맵, 필터, 압축, 모델 임포트 배율)을 옮긴다.
9. 도구의 표본 파일: `tools/manager/test_backend.py`가 실제 에셋을 표본으로 쓴다. 표본 파일을 지우거나 이름을 바꾸면 그 검사를 고친다.
10. 원화를 바꾸면 사람이 앵커를 다시 찍고(`tools/art/portrait_slots.json`, `portrait_anchor_table.py`), 자르기를 다시 만들고(`portrait_derive.py`), 계약 `crops`를 고친다. 초상 겹 분해(`layers_source.json`)도 새로 한다.
11. 환경음 반복 끝 `data.size()/2`(`combat_audio.gd`)는 16비트 모노 가정이다.
12. 자리표가 아직 덮지 않는 것(지금 코드가 경로를 직접 가진다): UI 키트, 장비 아이콘, 글꼴, 원화·초상, 소리, 눈송이 그림. T7-3 이후 차례로 옮긴다. (지형·소품은 A12-0에서 옮겼다. 아래 절.)

### 지형·소품과 배치 파일(A12-0)

- `chapter1/view/world/chapter_world.gd`는 그림 경로를 하나도 갖지 않는다. 바닥 두 장은 `world.common.ground.flagstone`·`world.common.ground.soil`, 돌 겉은 `world.common.trim.stone`, 소품 시트는 `world.common.props.cloister`(옆 JSON에 칸·발·높이), 경계의 시트·밑돌은 `world.edge.props`·`world.edge.stone`이다. 구역마다 따로 바꿀 때의 이름은 `world.zone<N>.<항목>`(A12 5.4).
- 무엇이 어디에 서는지는 `world/layout_chapter1.json`(자리 `world.common.layout`)이다. 소품·기초 돌·뒷벽 돌·뒷벽 아치·풀 한도·맵 경계의 줄(`edge`)이 있고, 한 줄이 하나다. 줄을 옮기거나 지우면 그것이 옮겨지거나 사라진다. 좌표는 코어와 같은 세계 좌표(m)이며 코어는 이 파일을 읽지 않는다.
- 배치를 바꾸면 `chapter1/tests/test_world_layout.gd`가 옛 코드의 배치(`tests/fixtures/world_layout_before.json`)와 다르다고 말한다. 의도한 변경이면 그 검사의 `--record`로 기준을 다시 찍는다.
- 풀 시트(`world.common.props.foliage`, 옆 JSON `group: foliage`)는 불러오지 않는다. 풀은 코드 기하다.
- 시트의 옆 JSON `group` 칸이 분류 표지다(파일 이름으로 가르지 않는다).
