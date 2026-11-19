# 3D 캐릭터 제작 길 — 쓰는 법 한 쪽

작성 2026-11-20, character-artist. 근거: `docs/reviews/3D-CHARACTER-PIPELINE-PROOF-20261120.ko.md`(된 것·모자란 것), `docs/reviews/3D-GEN-TOOLS-20261117.ko.md`(게임이 모델에 기대는 것). 도구는 모두 `tools/art/`.

차례: **생성 도구가 준 메시 한 덩어리 → mesh_reduce → rig_build → rig_clips → rig_parts → rig_check → 게임**

전제: Blender 5.3(`D:/Blender Foundation/Blender 5.3/blender.exe`, 환경변수 `BLENDER_EXE`로 바꿈). 파이썬 도구를 그냥 부르면 스스로 `blender --background --python`으로 다시 부른다. 큰 중간 파일(.blend, 큰 glb)은 `D:/Project/witch-moira-work/char3d/` 아래에 둔다. 결과 확인용 캡처·보고서는 `_local/` 아래.
좌표 약속: Blender 안에서 Z가 위, 정면이 `-Y`, 캐릭터 왼쪽(`_l`)이 `+X`(glb로 내보내면 정면 `+Z`, 게임이 기대하는 방향). 정면이 다른 모델은 `--facing`/설정 `mesh.facing`으로 돌린다.

## 한 번에 보는 명령

```powershell
$PY = "C:/Users/twins/AppData/Local/Programs/Python/Python310/python.exe"; $W = "D:/Project/witch-moira-work/char3d/hero1"
# 1) 줄이기: 고폴리 -> 약 1만2천 삼각형 + 새 UV 색·노멀 텍스처. (크게 보일 때용은 --profile showcase = 약 5만)
& $PY tools/art/mesh_reduce.py --in HIGH.glb --out-glb $W/low.glb --profile game --height 2.0 --work $W --report $W/reduce.json
# 2) 뼈대·가중치: 뼈 24개, 무가중치 0, 정점당 4개 이하
& $PY tools/art/rig_build.py --in $W/low.glb --out-blend $W/rigged.blend --report $W/build.json [--config my_rig.json]
# 3) 동작 6개(60fps): idle 1.2, run 0.6, cast 0.6, hit 0.3, death 0.9, dodge 0.5초
& $PY tools/art/rig_clips.py --blend $W/rigged.blend --out-glb $W/clips.glb --out-blend $W/clips.blend --report $W/clips.json [--preview $W/prev]
# 4) 뼈에 붙는 소품 묶기(선택)
& $PY tools/art/rig_parts.py --blend $W/clips.blend --parts parts.json --out-glb $W/final.glb --report $W/parts.json
# 5) 계약 검사(자리표 대조 포함). 종료 코드 1이면 차이가 있다
& $PY tools/art/rig_check.py $W/final.glb --slot actor.hero.model
```

## 걸음마다

| 걸음 | 하는 일 | 알아 둘 것 |
|---|---|---|
| mesh_reduce | 가져오기 → 한 덩어리 → 축·키 맞춤(높이 `--height`, 기본 2.0 m) → 겹친 정점·떨어진 작은 조각 정리 → 데시메이트(얼굴·손은 덜 줄임, UV 이음매·재질 경계 보존) → 새 UV → 고폴리의 색과 굴곡을 저폴리의 색·노멀 텍스처로 굽기(Cycles CPU) → glb | 단계는 `tools/art/rig_configs/reduce_profiles.json`: `game` 약 12,000(범위 1만~1만5천, 지금 주인공 11,014), `showcase` 약 50,000(미정: 선택 화면·컷인에서 3D를 쓸 때만). `--cull-interior`는 안 보이는 안쪽 면 지우기(느림, 보수적). `--compare-original`은 원래 모델과 실루엣 대조. 보고서에 전후 삼각형, 실루엣 IoU(8방향+위), 텍스처 크기, 게임 배율(2.67÷키). 키 2.0 m면 `scale` 1.335(지금 모델 1.32) |
| rig_build | 메시 치수(키, 양손 끝, 장화 바닥, 몸통 앞면)와 키 대비 비율로 뼈 24개 자리 계산 → 거리 기반 가중치 + 메시·공간 평활화 | 정면이 -Y, A자세(팔을 몸에서 35~45도)가 전제. 비율·예외는 `--config` JSON(`rig_configs/default.json`이 기본값과 설명): `proportions`, `bone_overrides`(뼈 하나의 머리·꼬리 직접 지정), `weights.bias/radius`. 보고서에 뼈 수·무가중치·최대 영향 수 |
| rig_clips | 절차식 동작 6개. 2-뼈 IK 다리, 달리기 한 주기 이동거리는 게임 `HERO_STRIDE 2.15`÷배율에 맞춤 | 보고서에 클립별 변 늘어남 비율, 발 미끄러짐, 바닥 아래 깊이, 다리 과신장 프레임. 팔이 T자세(수평)이면 자동으로 40도 내려 시작. `--retarget-from 원본.glb [--retarget-map 대응표.json]`은 기존 glb의 동작을 새 뼈대로 옮긴다(같은 이름의 뼈만). **원본이 CC BY-SA면 파생물도 그 조건**이라 출시용에는 권하지 않는다. 읽히는 수준의 자리표시자다. 손맛은 사람이 다듬는다 |
| rig_parts | 같은 뼈대에 별도 메시를 뼈 하나에 가중치 1로 단단히 묶음, 단색 텍스처 재질 | `parts.json` 예: `rig_configs/parts_demo.json`. 몸 위에 맞춰 늘어지는 옷은 안 된다(달릴 때 밑 옷과 어긋남). 게임의 재질 처리가 `albedo_color`를 덮어쓰므로 질감 없는 재질은 색을 잃는다: 이 도구가 8×8 단색 텍스처를 입힌다 |
| rig_check | glb가 계약을 지키는지: 뼈 이름 24, 클립 이름·길이, 재질 종류, 삼각형 예산(15,000 권고 / 20,000 상한), 가중치, 방향, 키×배율 | Blender 필요 없음. 자리표 대조(`--slot`)는 `asset_intake.py`의 `compare_slot`을 그대로 부른다. 뼈대가 아직 없는 mesh_reduce 결과는 `--mesh-only` |
| 게임 | 자리표(`chapter1/art/asset_slots.json`)의 `actor.hero.model` 교체 | 아래 "게임에 끼울 때" |

## 게임에 끼울 때(모델 교체의 주의)

1. **텍스처 함정**: `*.glb.import`의 `gltf/embedded_image_handling=1`(텍스처 추출) 때문에 Godot가 glb 안의 이미지를 `<glb 이름>_<이미지 이름>.png`로 풀어 놓고, **그 파일이 이미 있으면 덮어쓰지 않고 그것을 쓴다.** 지금 `mage_animated_color.png`·`_normal.png`가 그렇게 생긴 파일이고, 글 안의 매듭 문양을 지운 변경본이다(2026-11-17). 그래서 glb 안에는 매듭이 남아 있어도 게임 안에서는 안 보인다. 새 모델을 같은 파일 이름으로 덮으면서 이미지 이름이 `color`면 **옛 텍스처가 그대로 쓰인다.** 새 파일 이름을 쓰거나 풀린 PNG를 함께 교체한다.
2. 게임은 `chapter_actors.gd`에서 `load(MODEL)`로 경로를 직접 부르고 배율 `HERO_MODEL_SCALE`(1.32)을 코드에 가진다. 자리표 `scale`은 문서일 뿐 코드가 읽지 않는다. 자리표로 옮기는 일(tech-lead 몫)이 끝나기 전에는 시험을 `chapter1/tests/rig_game_probe.gd`로 한다(제품 파일을 고치지 않고 `Resource.take_over_path`로 모델을 끼움).
3. 상체 규칙(`spine_`, `neck_`, `head_`, `shoulder_`, `hand_`, `finger_`, `thumb.` 접두 또는 `arm_` 포함)은 이 뼈 이름이 그대로 걸린다. 손가락 뼈가 없으니 `thumb.`는 0개이고 이는 문제가 아니다(`rig_check`는 주의로 표시).
4. 지팡이는 `hand_cr_r`와 `finger_middle.01.r`의 가운데에 붙는다. 이 도구는 손 뼈의 자식으로 빈 뼈를 하나 둔다.

## 게임 안에서 보기(창을 띄우는 실행이라 화면이 켜진 상태에서)

```powershell
python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/rig_game_probe.gd -- `
  --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.frost `
  --model-glb=D:/Project/witch-moira-work/char3d/hero1/final.glb --shots=_local/char3d/shots/hero1 --until=900
# 회피·사망 같은 동작을 강제로 틀어 캡처:  ... --force-clip=dodge --force-times=0.1,0.2,0.25,0.3,0.4 --force-start=240
python tools/dev/godot_ps.py     # 끝난 뒤 자기 프로세스가 남지 않았는지
```
한 번에 하나만, `--chapter1-profile-off`로. 프로브는 `hud_dump.gd`를 상속하므로 `--shots`, `--until`, `--primary`가 그대로 듣는다.

## 아는 한계

- 몸·옷·얼굴의 조형은 이 도구가 하지 않는다(생성 도구나 모델러의 몫). 동작의 손맛과 미감은 사람이 평가한다.
- 가중치는 겹옷에서 달릴 때·팔을 크게 올릴 때 일부 변이 늘어난다(보고서 수치).
- 입력 모델 라이선스를 판단하지 않는다. CC BY-SA 3.0인 지금 주인공 모델의 파생물은 시험용이다.
