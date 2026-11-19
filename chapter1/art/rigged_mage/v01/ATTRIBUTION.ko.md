# 리깅 mage 연구 후보

원작: thecubber, Rigged textured mage. 원 리그 크레딧 Julius / OpenGameArt.
출처: https://opengameart.org/content/rigged-textured-mage
라이선스: CC BY-SA3.0 https://creativecommons.org/licenses/by-sa/3.0/

변경: 구형 재질 변환, 자체 IK 보행/대기/시전/피격/사망과 베이크, 무가중치 정점2053 보정과4가중치 정규화, 미터 변환. 이 파생 모델/렌더는 같은 CC BY-SA3.0을 따릅니다. 원본 및 파생 .blend는 로컬 연구 source 디렉터리에 보존했습니다. 원작D2/SACRATA 자산을 사용하지 않습니다. 표현 개선 후보11에서 영웅 표현으로 사용합니다. 후보09 실행본은 그대로 보존했습니다. 동작/아트 최종 품질 승인과는 별개입니다.

2026-11-17 변경(Witch Moira): 색 텍스처 mage_animated_color.png에서 망토 등판의 흰색 삼중 매듭 문양을 지우고 주변 천의 색과 결로 메웠고, 노멀 텍스처 mage_animated_normal.png에서 같은 문양의 윤곽 요철을 평평하게 했다. 이유는 종교·신화 상징을 게임에서 쓰지 않는다는 기준이다. 도구는 Python(Pillow, numpy, scipy). 모델 파일 mage_animated.glb는 바꾸지 않았다. 이 변경본도 같은 CC BY-SA 3.0을 따른다(원 라이선스는 변경과 재배포를 허용하며 변경 표시와 동일조건 공유를 요구한다). 변경 전 텍스처는 로컬 _local/art/mage-texture-backup-20261117/에 있다.

## 원본의 위치와 근거(2026-11-19 확인, 읽기 전용으로 봄)
받은 날짜: 2026-11-01(원본 폴더 이름 기준. 이 작품은 받은 zip이 아니라 작품 페이지에서 .blend를 직접 받았다).
원본은 저장소 밖 `C:/Project/game-research/art-sources/oga-mage-20261101-01/`에 있다. 저장소만으로는 재현되지 않는다.
- 원본 `mage_final.blend`: https://opengameart.org/sites/default/files/mage_final.blend, 38,657,376바이트, SHA-256 057c723026392f388e07844787e90e7d90df8c4da1c762013196bad61d1da30c(폴더의 SOURCE.json에 적힌 해시와 파일의 실제 해시가 같다).
- 라이선스 근거: 같은 폴더의 SOURCE.json에 "CC-BY-SA 3.0"과 원문 주소가 적혀 있다. 작품 페이지 사본(HTML)은 이 폴더에 없고, 페이지를 다시 열어 확인하지도 않았다.
- 위의 "원본 및 파생 .blend" 중 파생 .blend와 이 폴더의 `mage_animated.glb`를 만든 중간 산출물의 위치는 찾아 적지 못했다(미확인).
- 이 폴더의 `mage_animated.glb`는 SHA-256 9a37da85a99d2f50e1c122ee3ab36c7028c26512de68c4c98ccb68fecebd0e65. 위에 적힌 대로 2026-11-17에 텍스처를 고쳤고 모델 파일은 그대로다.
