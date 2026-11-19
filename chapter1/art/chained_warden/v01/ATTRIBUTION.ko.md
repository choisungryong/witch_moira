# 사슬 파수왕 연구 모델

원 모델: Mophs, Chained Demon, https://opengameart.org/content/chained-demon .
제공된 대안 중 CC BY3.0을 선택합니다: https://creativecommons.org/licenses/by/3.0/ .
변경: 구형 재질의 PBR 변환/packed diffuse, smooth shading, 초과 정점 가중치4개 검증/보정,
새 RootMotion, 자체 FK 대기/보행/두 전조/내려치기/부채/피격/사망8클립, 미터 변환.
원본/파생 source는 C:/Project/game-research/art-sources/oga-chained-demon-20261101-01/에 보존했습니다.
원작D2/SACRATA 자산을 사용하지 않습니다. 아직 외형/타이밍 검수 중이며 후보11 실행본은 변경하지 않았습니다.
추가 변경: 원본 diffuse 픽셀을 유지하고 정점 가중치에 따라 피부/가면/사슬 재질을 분리했습니다. 엔진에서는 외형 크기1.15와 부위별 명도를 조정합니다.

## 원본의 위치와 근거(2026-11-19 확인, 읽기 전용으로 봄)
저작자: Mophs(OpenGameArt 사용자 mophs). 받은 zip 안의 readme.txt에는 "Chained Demon / Tor Halle-McIntyre 2015"라고만 적혀 있다. 이 이름이 Mophs와 같은 사람인지는 확인하지 못했다. 표시를 쓸 때는 두 이름을 모두 남긴다.
받은 파일: https://opengameart.org/sites/default/files/Chained_Demon_0.zip (1,916,836바이트, SHA-256 d274de7049e4ac5fd63153b38827a7b829edcbc4e6f22113df0cb5933f38d271)
받은 날짜: 2026-11-01(원본 폴더 이름과 zip 파일의 수정 시각 기준. 내려받은 순간의 기록은 없다)
라이선스 근거: 받을 때 저장한 작품 페이지 사본(source.html, SHA-256 4eea73df2c2df03c78f8ae2ea08d197427e638830b8dfd50b9f0014d24e77796)의 라이선스 칸에 CC-BY 3.0, GPL 3.0, OGA-BY 3.0 세 가지가 함께 적혀 있고, 이 중 CC BY 3.0을 고른 것이 위 기록이다. 페이지를 다시 열어 확인하지는 않았다. CC BY 3.0은 저작자 표시와 변경 표시를 요구한다.

원본은 저장소 밖 `C:/Project/game-research/art-sources/oga-chained-demon-20261101-01/`에 있다. 저장소만으로는 재현되지 않는다.

| 무엇 | 경로(위 폴더 기준) | 확인한 것 |
|---|---|---|
| 받은 zip | `source.zip` | SHA-256이 위 값과 같다 |
| 출처 기록 | `SOURCE.json` | 저자·라이선스·zip 해시·파일 목록 |
| 풀어 둔 원본 | `extracted/Chained_Demon/ChainedDemon.blend` (SHA-256 e653981f918120614d70a4cd3ddc2d976985d8bdde65f3cca5304d1eada151fc), `diffuse.png`, `readme.txt` | |
| 이 폴더의 `chained_demon_animated.glb`의 출처 | `material-05/chained_warden.glb` | SHA-256 1aa069466e8666461f7b1844435167772cec9d2fe4d56196da34c7c0d38d571c로 바이트가 같다. 같은 이름의 `motion-03/`, `motion-04/`의 `chained_demon_animated.glb`는 해시가 다르다(앞 단계 산출물) |
| 파생 .blend | `material-05/chained_warden_source.blend` | SHA-256 5006316bac3c7663dd65d30a7e7941ba021841b14995546047edd938462cbac5 |
| 텍스처 | `extracted/Chained_Demon/diffuse.png` | 이 폴더의 `chained_demon_animated_diffuse.png`와 SHA-256(991ec801e2c1886586ba277ad15c1fa37662ff9e37af11a3c2c2ccbc96c71baf)이 같다 |
