# 화면 재질 키트 출처

## 전투 HUD: 2판 시안 (다) 키트 (kit_c, 테 두께 60%)
- 제작: **Codex 생성 시안**, 2026-11-17. 조각을 시안 그림에서 잘라 마젠타 바탕을 떼고 보정(코드).
- 원본 위치(저장소에 올라가지 않음): `_local/art/drafts/ui_kit_v2/kit_c/`(`rim60/` 사용, `rim45`는 쓰지 않음), 프롬프트는 같은 폴더 위의 `rim60-r1.prompt.txt`, `icons-r1.prompt.txt`, `top-r1.prompt.txt`, `misc-r1.prompt.txt`, `ends-r1.prompt.txt` 등.
- `hud_atlas.png`: 쓰는 조각 36개를 한 장에(원본 크기 = 1080p 표시 크기 × 2, 밉맵 켬). 칸 위치는 `view/hud/ui_style.gd`의 `ATLAS`. `build_kit.py`로 다시 만든다.
- 구슬은 `kit_c/orb/`의 그림 조각(빈 유리, 가득 찬 액체 넷, 수면 띠 넷, 하이라이트 v2)을 아주 단순한 셰이더가 수면 높이에서 잘라 겹친다(`ui_style.gd`). 십자 메달도 `orb/medal_cross.png`. 같은 Codex 생성 시안, 2026-11-17.

## 그 밖의 화면(메뉴·창·단추): 1차 키트의 1배 9분할
- `window_96.png`, `panel_small_48.png`, `button_*_64x40.png`: Codex 생성(1차 키트) + 코드, 2026-11-17. 전투 HUD 밖의 화면이 재디자인될 때까지 쓴다.
- 쓰지 않게 된 1차 조각(`panel_32.png`, 옛 아틀라스의 모서리 쇠·구슬 틀·칸 테·봉랍 등)은 지웠다.
