# 움직이는 초상 겹 그림 출처

만든 날: 2026-11-17. 본 저장소에 들인 날: 2026-11-18(다른 작업 폴더 `.claude/worktrees/agent-ab930f1d7e0f274f0/`에서 복사). 이 파일은 UTF-8(BOM 없음)이다.

| 폴더 | 내용 | 만든 방법 | 원본 |
|---|---|---|---|
| `frost/layers/` | 냉기 마녀 겹 8장(1024x1536 RGBA, 원화와 같은 자리) | 원화 `chapter1/art/characters/frost_witch_v02.png`를 Python(PIL, numpy)으로 부위별 다각형과 밝기 경계에 맞춰 나눔. 가려진 곳은 거울 반사와 번짐으로 채움. 속성 효과(눈꽃 등)는 겹에서 지움 | 원화 `chapter1/art/characters/frost_witch_v02.png`. 쌓는 순서와 회전 중심 후보는 `frost/layers_source.json` |
| `ember/layers/` | 화염 마녀 새 자세(한 걸음 내디딘 자세) 겹 11장 | Python(PIL, numpy, scipy)으로 손으로 잡은 다각형을 윤곽 밝기에 맞춰 나눔. 가려진 곳은 거울 반사와 번짐으로 채움. 불꽃 띠와 불똥은 겹에서 지움 | 자세 시안 `_local/art/drafts/ember_witch_pose/p2-r1.png`(본 저장소 `_local/`, git에 없음). 작업 폴더 `_local/art/drafts/ember_witch_layers_p2/`. `ember/layers_source.json` |
| `storm/layers/` | 번개 마녀 새 자세(정면, 두 팔 벌림) 겹 12장 | 같음. 두 손 사이 번개는 몸통, 팔, 배경에서 지우고 채움(몸통 위 번개 자리는 번진 채움) | 자세 시안 `_local/art/drafts/storm_witch_pose/p3-r1.png`. 작업 폴더 `_local/art/drafts/storm_witch_layers_p3/`(배경 보정 `fix_bg.py`). `storm/layers_source.json` |
| `*/…_eyes_half.png`, `…_eyes_closed.png` | 눈 깜박임 조각(반쯤, 감음). 투명 배경의 눈 둘레 조각 | Codex CLI(그림 생성)의 국소 편집으로 원화의 눈 자리만 다시 그리고, 원화 좌표에 맞춰 잘라 냄 | 작업 폴더 `_local/art/drafts/frost_witch_blink/`, `ember_witch_blink/`, `storm_witch_blink/`(본 저장소 `_local/`). 화염·번개 새 자세용 작업 폴더 `ember_witch_blink_p2/`, `storm_witch_blink_p3/`가 같은 위치에 있으나 이 폴더의 조각이 어느 쪽에서 나왔는지는 확인 못 함 |

- 겹 분리의 가려진 곳 일부는 Codex CLI의 국소 편집을 쓸 수 있게 했으나, 이번 겹 분리에서 쓴 생성 호출은 눈 조각뿐이다(겹 분리 보고서: 생성 0회, 거부 0건). 보고서 파일 자체는 이번에 확인하지 않음.
- 도구: Python 3.10, PIL, numpy, scipy(화염·번개), Codex CLI(눈 조각).
- 라이선스: 프로젝트 원화(`chapter1/art/characters/*_v02.png`)와 자세 시안의 파생물이며 원화와 같은 권리를 따른다. 생성 도구 이용 약관은 원화 생성 때와 같다고 보고 있으나 약관 문서는 이번에 다시 확인하지 않음.
- 눈꽃 조각(`flake_disc.png`, `flake_rings.png`)은 `chapter1/view/hud/living_portrait/`에 있고, 냉기 원화에서 `tools/dev/make_living_portrait_flake.py`로 잘라 낸 것이다.
- 화염·번개의 눈 깜박임 조각은 새 자세용이 아직 없어 붙이지 않았다(2026-11-17).
- 화염·번개 겹은 새 자세 기준이라 옛 원화(`ember_witch_v02.png`, `storm_witch_v02.png`)와 자세가 다르다.
