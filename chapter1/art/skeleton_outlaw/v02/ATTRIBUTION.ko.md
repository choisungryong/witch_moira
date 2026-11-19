# Skeleton Outlaw 병합 시안

원 모델: Skeleton Outlaw, 저작자 KevDev(OpenGameArt 사용자 kevdev).
출처: https://opengameart.org/node/89457
받은 파일: https://opengameart.org/sites/default/files/SkeletonOutlaw_0.zip (4,875,182바이트, SHA-256 dfd455f7613e4e80636dc35af9244a61747d91d4872b11815a3cc07243efd297)
받은 날짜: 2026-11-01(원본 폴더 이름과 zip 파일의 수정 시각 기준. 내려받은 순간의 기록은 없다)
라이선스: CC0. 근거는 내려받을 때 저장한 작품 페이지 사본(source.html, SHA-256 af63828244635ad8828994032371090f48bcba62d1fdcf3a9a16018cbc1ca696)의 라이선스 칸과 원본 폴더의 SOURCE.json이다. 2026-11-19에 페이지를 다시 열어 확인하지는 않았다. 저작자 표시 의무는 없다(CC0).

## 변경 내용(옛 기록 원문 유지)
8mesh/6skin을같은bind공간으로변환해1mesh/2surface/1skin으로묶었다. 원본삼각형·UV·스킨가중치·저작9클립·texture이미지는유지했다. 몸금속.03/도끼.1/거칠기.79로재질정리. DERIVATION.json은수학적bind검사이며실제엔진/움직임/제품품질승인이아니다. 현재제품33과미연결이다.

## 원본의 위치(2026-11-19 확인, 읽기 전용으로 봄)
저장소 밖 `C:/Project/game-research/art-sources/oga-skeleton-outlaw-20261101-01/`에 있다. 이 폴더는 저장소에 없으므로 다른 PC나 이 저장소만으로는 재현되지 않는다.

| 무엇 | 경로(위 폴더 기준) | 확인한 것 |
|---|---|---|
| 받은 zip | `source.zip` | SHA-256이 위 값과 같다 |
| 풀어 둔 원본(FBX 모델, 애니메이션 FBX 14개, 텍스처 2장) | `extracted/SkeletonOutlaw/` | 파일 크기가 `SOURCE.json`의 목록과 같다 |
| 출처 기록 | `SOURCE.json` | SHA-256 b2b8d6c2d94c28484cab97d83718bed108754319a16bc24ed64c619c48b8732d. 옛 저장소 파일 목록(`C:/Project/game-research/implementation-backups/chapter1-before47-20261113-01/ROOT46-BEFORE.json`)에 적힌, 이 저장소에서 사라진 `v01/SOURCE.json`의 해시와 같다. 같은 내용으로 본다 |
| 작품 페이지 사본 | `source.html` | 라이선스 칸이 CC0 |
| 병합 직전 모델로 보이는 파일 | `godot-convert02/derived/skeleton_outlaw.glb` | SHA-256 64439769210dcb46c39878dff66aba9d86d675b1a5eb632f84b9f07477399e3b. 메시 8, 스킨 6, 삼각형 6,594, 정점 5,375, 클립 9로 위 변경 내용의 "8mesh/6skin"과 숫자가 맞는다. 병합 과정을 적은 기록이 없어 이 파일이 실제 입력이었는지는 확인하지 못했다 |

## 이 저장소에서 사라진 기록
이 기록이 처음 가리키던 `../v01/ATTRIBUTION.ko.md`, `v01/SOURCE.json`, `DERIVATION.json`은 현재 저장소에 없다. 첫 커밋(옛 저장소에서 옮길 때)에도 들어 있지 않았고 git 기록에서도 찾지 못했다.
- `SOURCE.json`: 위 원본 폴더에서 같은 내용을 찾았다(해시 일치).
- `v01/ATTRIBUTION.ko.md`(옛 해시 c2b324a48c687f22d11f64afa621c6c21a4b8ba931535ec10d272b1d79916b13)와 `v02/DERIVATION.json`(옛 해시 912521dde494e1787d1bd612f458be511c229a3b9b0dabee4a58b9f83a223195): 어디에서도 찾지 못했다. 내용은 미확인이다. 위 변경 내용 문장은 이 기록에 남아 있던 설명이고, "수학적 bind 검사"의 결과값은 확인할 수 없다.

## 이 저장소의 파일
- `skeleton_outlaw_merged.glb`: SHA-256 d18afc044b043eef4933d38603d05973fd7fa2eb76e210728734b2a1736e1ab4(옛 파일 목록에 적힌 해시와 같다).
- `skeleton_outlaw_merged_0.png`, `skeleton_outlaw_merged_1.png`: 모델에서 꺼낸 텍스처. 원본 `SkeletonOutlaw00.png`(2,746,121바이트), `Axe00.png`(443,937바이트)와 바이트가 다르다(다시 저장된 것으로 보이며 원본과의 화소 동일 여부는 확인하지 않았다).
