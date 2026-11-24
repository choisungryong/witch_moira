# 인트로 2판 콘티 검수와 다시 그릴 칸의 지시서 (2026-11-24)

art-lead가 쓴 검수 기록이다. 그림은 뽑지 않았고 코드·데이터는 고치지 않았다. 커밋하지 않았다.

- 사용자 지시 원문(2026-11-24): "콘티의 완성도를 최상으로 끌어올려줘"
- 받을 명세: `docs/story/INTRO-VIDEO-20261124.ko.md`(이하 "연출안") 3절 규칙, 4절 컷표, 5.1절 자막, 6절 장면 목록, 7.1절 새 시작 그림. 지시 장부 U-112, U-117, U-118.
- 본 것(모두 직접 봄): 칸 원본 `_local/art/intro/storyboard_v2/C01.png`~`C27.png` 27장, 시트 `board_1.jpg`·`board_2.jpg`·`board_3.jpg`, 세 마녀 원화 `chapter1/art/characters/{ember,frost,storm}_witch_v02.png`, 아일린 메인 이미지(사본) `_local/art/intro/storyboard_v2/work/C12-r0/frost_main_a_gpt25.png`, 악마 메인 이미지 `_local/art/demon-main/{feronia,marzanna,tacita}_main_a_preview.jpg`, 마수 시트 `_local/art/intro/beasts_sheet.jpg`, 1판 시작 그림 `D:/Project/witch-moira-work/intro/img/{tessa1,eileen1,veronica1}.png`, 3D 시트 `_local/shots/arc-body/sheet.jpg`·`_local/shots/pack-fix/ember_before_after.jpg`, 스케치 요청문 `work/C18-r0.prompt.txt`·`work/C24-r1.prompt.txt`, `REPORT.txt`, `make_boards.py`.
- 보지 않은 것: 1판 영상의 재생(움직임·소리). 1판 칸은 콘티에 박힌 한 프레임만 봤다. `pack-fix/frost_before_after.jpg`는 열지 않았다.

---

## 1. "최상"의 기준

이 콘티는 유료 영상 생성 전에 사용자가 보는 마지막 확인이다. 칸 하나가 통과하려면 그 칸만 보고 다음 다섯이 읽혀야 한다.

1. **무슨 일이 일어나는가**: 칸의 시작 상태가 그려져 있고, 칸 안에서 바뀌는 것(움직임 하나, 카메라 움직임 하나)이 화살표와 글로 적혀 있다.
2. **누구인가**: 인물은 기준 그림과 같은 사람이다. 머리색과 길이, 눈색, 뿔, 힘의 표지가 있는 팔(테사 오른팔, 아일린 왼팔, 베로니카 두 팔), 옷이 원화와 맞는다. 마수는 마수 시트의 네 꼴 가운데 하나다.
3. **규칙**: 3.2절(닿지 않음, 악마가 높음, 시선은 팔, 웃지 않음), 3.3절(약한 티), 3.8절(얼굴 크기, 얼굴 가림)을 어긴 곳이 없다.
4. **이음**: 앞뒤 칸과 화면 방향(위협은 오른쪽), 장소의 틀, 빛과 색이 이어진다.
5. **같은 완성도**: 27칸이 같은 그림 수준이라 "이 칸만 덜 됐다"는 인상이 없다. 사용자가 보는 그림이 곧 영상의 첫 프레임이다.

**판단: 새로 뽑을 16칸은 연필 스케치를 버리고, 영상의 시작 그림으로 바로 쓸 채색 완성 그림으로 올린다.** 까닭은 셋이다.
- 연출안 7.1절이 어차피 시작 그림 14장을 새로 그린다. 스케치를 고쳐 통과시킨 뒤 시작 그림을 또 그리면 같은 구도를 두 번 그리고 두 번 검수한다. 시작 그림 자체를 콘티 칸으로 쓰면 한 번에 끝난다.
- 지금 흠의 대부분(얼굴과 옷이 기준 그림과 들쭉날쭉, 스케치와 영상 프레임의 차이)은 스케치라는 꼴에서 나왔다. 스케치 요청문이 "머리 모양, 뿔, 큰 옷 덩어리만 알아보게"라고 적었다(`work/C18-r0.prompt.txt` 3줄). 얼굴과 색을 요구하지 않았으니 같은 사람이 나오지 않았다. 1판 시작 그림(tessa1·eileen1·veronica1)은 같은 사람이 나왔다. 그 수준이 기준이다.
- 사용자가 "기준에 못 미치면 다음 단계로 넘기지 않는다"고 했다. 스케치로 통과시키면 얼굴의 위험(지2, 3.8절)이 시작 그림 단계로 미뤄진 채 남는다. 시작 그림으로 보이면 얼굴이 무너지는지를 영상 전에 본다.

조건이 하나 있다. **화살표·무음 표시는 그림에 그려 넣지 않는다.** 시작 그림은 깨끗해야 영상 생성에 쓴다. 화살표는 `make_boards.py`가 시트를 만들 때 위에 얹는다(5절).

수: 새 시작 그림은 14장(연출안 7.1절)에 **C26 한 장을 더해 15장**이다. C23은 1판의 eileen1을 그대로 칸에 넣는다(그리지 않는다). C26을 따로 그리는 까닭은 2절 C26 줄에 적었다.

---

## 2. 칸별 판정 (27칸, 모두 직접 봄)

판정: **통과** / **고침**(그리지 않고 프레임을 다시 고르거나 칸을 바꿔 끼움) / **다시 그림**(채색 시작 그림으로 새로 그림). "다시 그림" 칸의 "스케치 구도" 열은 지금 스케치의 배치를 시작 그림에서 살릴지다.

### 박1·박2

| 칸 | 연출안이 요구한 것 | 그림에서 본 것 | 판정 | 고칠 점 |
|---|---|---|---|---|
| C01 | 별 아래 성벽 마을, 수도원 종탑, 창마다 불빛. 내려옴 | 강 낀 성벽 마을, 오른쪽 종탑, 은하수, 불빛. 얼굴 없음 | 통과 | — |
| C02 | 자홍 결정 숲, 풀 뜯는 네 발 짐승. 밀기 | 결정 숲, 네 발 짐승 넷, 뒤에 두 발 마수 둘이 서 있음 | 통과 | 뒤의 두 발 마수는 중간계의 것이므로 규칙 안 |
| C04 | 땅이 갈라지고 나무가 기움, 짐승들이 오른쪽을 봄 | C02와 거의 같은 프레임. 짐승은 여전히 풀을 뜯고 고개를 들지 않음. 앞쪽 바닥의 금만 보임 | 고침 | 생02의 4.0~4.7초 근처에서 짐승들이 고개를 들고 오른쪽을 보는 프레임으로 바꾼다. 지금은 C02와 구별이 안 된다 |
| C05 | 두 발 마수 떼가 오른쪽 허공의 빛 틈으로 달림 | 네 발 짐승과 두 발 마수가 오른쪽으로 달림. 빛 틈은 화면 가운데 뒤, 떠 있는 바위들 | 통과 | 칸 글을 "가운데 뒤의 빛 틈 앞을 오른쪽으로 달림"으로 고친다(그림이 아니라 글이 틀림) |
| C06 | 허공의 가는 빛줄이 세로로 찢어져 열림, 종이 흔들림 | 이미 굵게 다 열린 푸른 흰 빛기둥. 아래 끝이 마당의 돌단(우물 같은 받침)에 닿아 "땅에서 솟는 빛기둥"으로 읽힘. 종은 정지 | 고침 | 생04 앞쪽(1.5초 근처)의 빛줄이 가늘 때 프레임으로 바꾼다. 이 칸의 빛(속은 흰빛, 가장자리 푸른 흰빛)을 C07 균열의 색 기준으로 삼는다 |
| C07 | 광장 허공에 선 세로 균열에서 마수가 쏟아짐, 둘레에 결정, 지붕에 불. 떠오르며 물러남 | 높은 곳에서 본 광장, 마수 떼, 자홍 결정, 지붕의 작은 불. 균열은 하늘 위 화면 밖에서 내리꽂힌 번개·빛기둥처럼 생김(위 끝이 화면 밖) | 다시 그림 | 스케치 구도 살림(높이, 떼의 흐름, 결정 고리). 균열은 **위아래 끝이 다 보이고 바닥에서 한 층 높이 떠 있는 문 같은 틈**으로. 색은 C06과 같게. 떼는 앞쪽 크게, 뒤로 작게, 마리 수 줄임(연출안 7.3절) |
| C08 | 등불 골목, 마수가 쏟아지고 덧문 닫히고 등불 꺼짐 | 걷는 마수 셋이 정면으로 달려옴. 등불 둘. 얼굴은 짐승 얼굴로 무너짐 없음 | 통과 | — |
| C03 | 낮은 붉은 하늘, 검은 벌판, 하늘의 흰 가로선 하나, 떠오르는 불티가 선에 닿으면 꺼짐 | 선과 벌판은 있음. 불티가 비처럼 **아래로 비스듬히 떨어짐**(요구와 반대). 선 아래 꺼지는 띠 없음. 벌판에 굵은 길 화살표 | 다시 그림 | 불티는 위로 오르고 선 바로 아래에서 꺼진다. 선 아래에 불티가 없는 맑은 띠가 보여야 "균형"이 읽힌다. 화살표는 그림에서 빼고 시트에 얹는다 |

(C03은 박1이지만 새로 그리는 칸이라 아래 지시서와 이어지게 여기에 모았다.)

### 박3

| 칸 | 요구 | 본 것 | 판정 | 고칠 점 |
|---|---|---|---|---|
| C09 | 첨탑 너머 지평선을 덮은 어둠, 붉은 테두리 한 줄, 한 번 기욺. 벼랑 끝 세 악마 뒷모습, 아주 작게 | 붉은 하늘에 금 간 흰 선, 붉은 테두리의 검은 덩어리, 첨탑, 아래 가운데 작은 셋(주황·푸른·보라 기운). 어둠에서 셋에게 내려오는 큰 화살표 | 다시 그림 | 스케치 구도 살림. 덩어리가 **산맥으로 읽힌다**: 윗변을 연기처럼 무르게, 조금 앞으로 처지게. 화살표가 "무언가 내려온다"로 읽혀 "기운다"와 다름 → 시트의 화살표를 덩어리 윗변의 앞쪽 기울기(호 하나)로 바꾼다. 얼굴·눈·손 없음은 지켜짐 |
| C10 | 세 악마가 뒷모습으로 걸어 나가 떨어짐. 불·서리·번개 세 줄기. 어둠은 화면 위 끝에만 | 벼랑 끝 셋의 등, 위 끝에 어둠, 양옆 하늘에 주황·보라 줄기가 이미 있음 | 다시 그림 | 스케치 구도 살림. **가운데 마르자나가 흰 머리**로 그려졌다. 기준 그림은 짙은 청록 머리에 흰 한 가닥, 올림머리, 뒤로 휜 회색 뿔이다. 페로니아는 검은 머리에 불빛 끝, 타키타는 갈색 숫양 뿔과 보랏빛 검은 긴 물결 머리(맞음). 세 줄기는 뛰어내린 뒤에 생기므로 시작 그림에서 뺀다 |

### 박4

| 칸 | 요구 | 본 것 | 판정 | 고칠 점 |
|---|---|---|---|---|
| C11 | 불탄 집 문턱의 테사. 해진 망토, 작은 보따리, 달아나는 사람들, 일어나 오른쪽 불빛으로 | 갈색 물결 머리의 여인이 돌 위에 다리를 꼬고 앉음. 리본 묶은 보따리, 가는 굽 부츠, 오른쪽 불빛, 왼쪽 뒤 달아나는 셋 | 다시 그림 | **테사가 아니다**: 머리색이 붉은 갈색이 아니고, 오른팔이 검은 돌 팔이 아니라 맨팔에 팔찌. 다리를 꼰 자세와 선물 같은 보따리가 처지가 아니라 화보로 읽힌다(3.3절 위반). 무릎을 모으고 앉아 지친 얼굴로, 돌 팔은 빛이 꺼진 채 보이게. 보따리는 끈으로 묶은 천 |
| C12 | 눈 오는 골목, 아일린이 오른쪽으로 걸음, 곁의 덧문이 안쪽에서 닫힘 | 땋은 흰 머리 여인이 망토를 여미고 오른쪽으로 걸음. 오른쪽 끝 벽의 덧문, 작은 화살표 | 다시 그림 | 스케치 구도 살림. 털 깃, 눈꽃 머리핀, **얼음 왼팔**이 없어 아일린인지 머리 모양으로만 안다. 덧문은 그녀 어깨 높이 바로 옆으로 당긴다(지금은 화면 끝이라 "그녀에게 닫힌다"가 약함) |
| C13 | 성문 처마 밑 젖은 베로니카, 보따리, 오른쪽 울음에 고개를 들고 일어섬 | 짧은 흰 머리, 팔에 보라 번개 무늬(희미함, 맞음), 해진 옷, 보따리, 처마. 고개를 **위로** 듦 | 다시 그림 | 스케치 구도 살림. 시선을 오른쪽(울음이 나는 쪽)으로. 위를 보면 C14의 오른쪽 위협으로 이어지지 않는다 |
| C14 | 테사가 작은 불덩이를 던지지만 마수가 털어 냄 | 높은 내려봄, 왼쪽 아래 테사가 걷고 있음, 오른쪽 위 마수 넷. 불덩이 없음 | 고침 | 생06의 2.5~3.5초 근처, 손에서 불덩이가 떠난 프레임으로 바꾼다(tessa1의 손 뻗은 자세가 그 근처일 것). 팔의 주황 빛은 긴5대로 받아들임 |
| C15 | 눈 덮인 회랑, 아일린이 닫힌 문까지 물러섬 | 높은 내려봄, 왼쪽 문의 아일린, 오른쪽 앞 결정 등의 마수. 얼굴 작고 조금 흐림 | 통과 | 얼음 팔이 푸르게 빛난다. 받아들이기 전이지만 "자기 힘이 먼저"(IV9)로 읽히므로 둔다. 긴5에 C15도 한 줄 더하기를 narrative-lead에 권함 |
| C16 | 빗속 수도원 문 앞, 손끝 불꽃이 꺼지고 빗물을 훔치고 버팀 | 수도원 문(성상 두 개, 촛불, 돌계단) 앞, 이마의 빗물을 훔치는 베로니카, 얼굴 온전 | 통과 | 이 배경(veronica1)을 C24·C26의 장소로 쓴다(3절) |

### 박5 테사

| 칸 | 요구 | 본 것 | 판정 | 고칠 점 |
|---|---|---|---|---|
| C17 | 무너진 벽에 등 붙이고 주저앉은 테사, 한 뼘 앞 발톱, 둘 사이에 불기둥, 얼굴 반쯤 가림. 아주 낮은 올려봄 | 낮은 각, 왼쪽 여인이 팔로 얼굴을 반 가림, 오른쪽 해골 머리의 마른 마수, 가운데 주황 선. 배경은 흰 종이에 성당, 불 없음 | 다시 그림 | 스케치 구도 살림(각, 좌우, 한 뼘). **테사가 아니다**: 버클 달린 가죽 웃옷과 갈색 머리, 돌 팔 없음. **마수가 시트의 "걷는 마수"가 아니다**(시트는 크림색 해골 가면, 어깨의 검은 결정, 두꺼운 몸). **장소가 C14·C20의 불타는 거리가 아니다** |
| C18 | 연기 속 왼쪽 위 페로니아, 손바닥 불꽃, 눈은 테사의 오른팔, 테사는 올려다봄, 팔 하나 빈 곳 | 왼쪽 위 뿔 달린 검은 머리 악마, 손바닥 위 불꽃, 오른쪽 아래 테사가 올려다봄, 금 간 팔, 닿지 않음 | 다시 그림 | 구도 고침. **높이 차가 작다**: 두 머리의 높이 차가 화면 높이의 약 1/7뿐이라 눈높이가 거의 같다(3.2절 "눈높이가 같은 순간은 없다"). 테사 머리를 화면 가운데 아래로. 페로니아의 눈이 테사의 팔이 아니라 **자기 손바닥**을 본다. 머리끝의 불빛과 주황 단이 빠져 메인 이미지와 다르다. 테사 얼굴이 화면 높이의 1/5에 못 미친다(3.8절 1번). 화면 오른쪽 끝에 불타는 거리의 흔적을 두어 C17과 장소를 잇는다 |
| C19 | 테사의 오른팔과 떠 온 불꽃, 오른쪽 뒤 사람들을 한 번 보고 팔을 듦, 틈이 주황으로. 악마 없음 | 화면을 가르는 검은 돌 팔, 왼쪽 위 불꽃, 오른쪽 끝 옆얼굴, 가운데 뒤 달아나는 셋, 시선 화살표 | 다시 그림 | 구도 고침. **손이 짐승 발톱**이다. 원화는 손톱이 보통인 사람 손에 검은 돌 같은 살갗이다(CA 2.1절 4번 "사람의 손"과도 맞춤). 옆얼굴은 오른쪽을 보는데 사람들은 가운데 뒤에 있어 **시선과 사람의 자리가 어긋난다**: 사람들을 그녀가 고개를 돌린 오른쪽 뒤 초점 밖에 둔다. 머리색 붉은 갈색 |
| C20 | C14와 같은 거리, 불의 물결이 왼→오 | tessa1과 같은 틀, 붉은 머리 테사가 오른쪽으로 불을 뿜음 | 통과 | — |

### 박5 아일린

| 칸 | 요구 | 본 것 | 판정 | 고칠 점 |
|---|---|---|---|---|
| C21 | C15에 이어 문에 등이 붙은 아일린, 한 뼘 앞에서 마수가 통째로 얼음, 서리는 왼쪽 뒤에서 | 문 앞 옆얼굴의 아일린(땋은 머리, 털 깃), 얼음덩이 속 공중의 마수, 왼쪽에서 번지는 서리 | 다시 그림 | 스케치 구도 살림(가장 잘 된 위기 칸). 등이 문에 **붙지 않고 똑바로 서 있어** 위기가 약하다. 옷이 해진 망토로 C15·C23(원화 옷)과 다르다. 마수가 시트의 걷는 마수가 아니다. 문은 eileen1의 문(철 장식 나무문, 눈 덮인 기둥)으로 |
| C22 | 눈보라, 왼쪽 위 마르자나가 서리 소용돌이를 내밈, 눈은 아일린의 왼팔, 아일린이 팔을 넣자 무늬가 번짐, 마르자나는 물러남 | 왼쪽 위 뿔 달린 악마, 손바닥 위 소용돌이, 오른쪽 아래 아일린이 팔을 뻗음, 높이 차 충분, 닿지 않음 | 다시 그림 | 스케치 구도 살림. **마르자나가 흰 머리**다(C10과 같은 흠). 아일린 **뺨에 금 같은 자국**이 있다(3.3절 "옛 상처·흉터를 두지 않는다"). 마르자나의 눈이 자기 손바닥을 본다. 손 사이가 팔 반 길이로 짧다. 배경이 먼 성채 언덕이라 C21·C23의 회랑과 끊긴다 |
| C23 | C15와 같은 회랑, 서리 물결이 왼→오 | 문 왼쪽 아일린(원화 옷), 회랑의 난간·기둥, 오른쪽 마수들이 얼고 큰 화살표 | 고침 | 그리지 않는다. 연출안 7.1절대로 시작 그림은 1판 eileen1이므로 칸에 **eileen1을 그대로 넣는다**. 스케치의 틀은 eileen1과 거의 같아 이음은 맞다 |

### 박5 베로니카

| 칸 | 요구 | 본 것 | 판정 | 고칠 점 |
|---|---|---|---|---|
| C24 | 빗속 수도원 돌계단, 돌진하는 마수가 한 뼘 앞, 빗방울과 마수가 허공에 멈춤. 무음 | 왼쪽 반쯤 돌아선 짧은 머리 여인, 공중의 마른 마수, 고딕 건물, 계단, 무음 표시. 비는 **보통 빗줄기** | 다시 그림 | 디렉터가 본 흠이 맞다. 원인은 요청문이 "Droplets drawn as short still streaks"라고 적은 것이다(`work/C24-r1.prompt.txt` 7줄). 줄기는 내리는 비로 읽힌다. **물방울을 하나하나 떨어진 둥근 알**로, 계단 위 물보라의 왕관도 멈춘 채로. 마수는 시트의 **돌진하는 마수**(멧돼지 해골 가면, 엄니, 등의 검은 결정 무더기)로. 장소는 C16의 수도원 문(성상, 촛불, 계단). 옷은 C16의 원화 옷(지금은 해진 긴 웃옷) |
| C25 | 멈춘 빗방울 사이, 왼쪽 위 타키타가 두 손가락 사이 보라 불꽃, 눈은 베로니카의 팔, 팔을 대자 무늬가 타오름, 타키타 사라짐. 무음 | 왼쪽 위 숫양 뿔 타키타, 두 손가락의 보라 불꽃, 오른쪽 아래 베로니카(원화 옷, 짧은 백금 머리, 별 귀걸이, 팔의 보라 무늬), **둥근 물방울이 떠 있음** | 다시 그림 | 스케치 구도 살림(세 거래 칸 가운데 가장 잘 됨, 물방울은 이 칸을 기준으로). 타키타의 **목 옆 금 간 흉터**(메인 이미지)가 없다. 눈이 자기 손가락을 본다. 베로니카 옷이 C24·C26(해진 웃옷)과 달라 세 칸 안에서 옷이 바뀐다. 손 사이를 팔 하나 길이로 |
| C26 | C24와 같은 계단, 번개가 마수들을 쓸고 멈췄던 비가 한꺼번에 떨어짐 | C24와 같은 틀, 같은 자세의 베로니카, 보라 번개가 하늘에서 마수 둘에게, 비가 내림 | 다시 그림 | 틀은 맞다. 베로니카가 **팔을 내린 채 서 있어** 번개가 그녀의 힘이 아니라 하늘에서 온 것으로 읽힌다(3.4절 5 "그녀의 원소가"). 팔을 높이 들고 두 팔의 무늬가 밝게 타오르는 시작 그림을 **따로 그린다**(그15). C24의 시작 그림에서 영상이 그녀를 돌려세우게 하면 얼굴이 움직이는 컷이 되어 3.8절 2번과 부딪친다 |

### 박6

| 칸 | 요구 | 본 것 | 판정 | 고칠 점 |
|---|---|---|---|---|
| C27 | 바닥 높이, 무리의 등 뒤, 불타는 거리 끝 역광 속 한 사람, 끝 2초 제목 | 돌진하는 마수들의 등, 끝에 작은 역광의 한 사람, 위 가운데 빈 하늘 | 통과 | 제목 자리는 위 가운데 성 첨탑 위. 시트에 제목 자리 상자를 얹어 보인다 |

**합계: 통과 8칸(C01·C02·C05·C08·C15·C16·C20·C27), 고침 4칸(C04·C06·C14·C23), 다시 그림 15칸(C03·C07·C09·C10·C11·C12·C13·C17·C18·C19·C21·C22·C24·C25·C26).**

다시 그릴 15칸 가운데 스케치 구도를 살리는 칸은 10(C07·C09·C10·C12·C13·C17·C21·C22·C25, C26은 틀만), 구도까지 고치는 칸은 5(C03·C11·C18·C19·C24)다.

---

## 3. 흐름 검수

### 3.1 화면 방향
- 박2: C04 짐승이 오른쪽을 봄(고친 프레임에서) → C05 오른쪽으로 달림 → C06 고정 → C07·C08 떼가 화면 앞으로. 이어진다.
- 박4: C11 테사 오른쪽을 봄 → C12 아일린 오른쪽으로 걸음 → **C13 베로니카가 위를 봄(끊김)** → C14 위협 오른쪽 위. C13의 시선만 고치면 셋이 모두 오른쪽으로 이어진다.
- 박5: 세 줄기 모두 위기 칸은 소서리스 왼쪽, 마수 오른쪽(C17·C21·C24 맞음). 거래 칸은 악마 왼쪽 위, 소서리스 오른쪽 아래(C18·C22·C25 맞음). 위기에서 거래로 넘어갈 때 소서리스가 화면 왼쪽에서 오른쪽 아래로 옮겨 가는데, 위협이 여전히 그녀의 오른쪽(화면 밖)에 있으므로 축은 넘지 않는다. 다만 C18·C22·C25의 오른쪽 끝에 그 칸의 장소 흔적(불, 회랑 기둥, 계단)을 두어 같은 자리에서 이어진다는 것을 보인다.

### 3.2 같은 장소 칸의 틀
| 짝 | 지금 | 고칠 것 |
|---|---|---|
| C14·C20 | 둘 다 1판 tessa1 틀. 같음 | 없음. C17·C18·C19도 이 거리(불타는 집, 수레, 깃발) 안이어야 하는데 스케치 셋은 흰 바탕의 성당이다 → 시작 그림에서 거리로 |
| C15·C23 | C23을 eileen1로 바꾸면 같음 | C21·C22의 배경도 이 회랑(철 장식 나무문, 눈 덮인 기둥, 난간)으로 |
| C24·C26 | 둘이 같은 틀이나 C16(veronica1: 성상, 촛불, 넓은 돌계단)과 다른 건물 | C24·C25·C26 모두 veronica1의 수도원 문 앞으로. C16이 "문 앞에서 버팀", C24가 "같은 계단에서 덮침"으로 이어진다 |

### 3.3 세 줄기의 차례와 무게
- 차례(위기 → 개입 → 제안 → 받아들임 → 권능)는 셋 다 칸으로 서 있다. 테사 4칸, 아일린·베로니카 3칸은 연출안 IW12의 설계대로다.
- **옷이 세 줄기에서 다르게 흔들린다.** 1판 칸(C14·C15·C16·C20)은 원화 옷이다. 새 칸은 테사가 가죽 웃옷(C17)·끈 조끼(C18), 아일린이 해진 망토(C21)·털 망토(C22), 베로니카가 해진 웃옷(C24·C26)·원화 옷(C25)이다. **정함: 위기~권능 칸(C17~C19, C21·C22, C24~C26)은 원화 옷 그대로, 1판 칸과 같게. 처지 칸(C11~C13)만 원화 옷 위에 해진 여행 망토와 보따리를 더한다.** 망토는 두건을 내려 머리가 보이게 한다.
- **"인간들 쪽을 한 번 봄"이 테사에만 있다.** 아일린과 베로니카는 3·4를 한 칸에 묶었으니 눈길까지 넣으면 얼굴이 움직인다. 눈길 대신 C22·C25의 오른쪽 먼 배경에 달아나거나 웅크린 작은 사람 형체를 두어 "누구를 위해 받는가"가 그림에 남게 한다. 얼굴은 움직이지 않는다.

### 3.4 거리 규칙이 세 사람에게 같은가
| 규칙 | C18 페로니아 | C22 마르자나 | C25 타키타 | 맞출 값 |
|---|---|---|---|---|
| 닿지 않음 | 지킴, 팔 하나 | 지킴, 팔 반 | 지킴, 팔 반 | 셋 다 원소와 팔 사이 팔 하나 길이 |
| 악마가 높음 | **약함**(머리 높이 차 화면의 약 1/7) | 지킴(약 2/5) | 지킴(약 2/5) | 머리 높이 차 화면 높이의 1/3 이상 |
| 시선은 팔 | 자기 손을 봄 | 자기 손을 봄 | 자기 손을 봄 | 셋 다 소서리스의 표지 팔을 봄 |
| 웃지 않음 | 지킴 | 지킴 | 지킴 | 입 다묾, 눈꺼풀 조금 내림 |
| 손 | 손바닥 위 불꽃 | 손바닥 위 소용돌이 | 두 손가락 사이 불꽃 | 그대로(연출안 3.2절) |
| 아래에서 비추는 빛 | 조금 | 조금 | 조금 | 셋 다 원소 빛이 턱 밑에서 얼굴을 비춤 |
| 얼굴 크기 | 악마 맞음, 테사 작음 | 둘 다 조금 작음 | 악마 맞음, 베로니카 작음 | 두 얼굴 모두 화면 높이의 1/5 이상(3.8절 1번) |

---

## 4. 다시 그릴 칸의 지시서 (codex-operator용)

### 4.1 공통

- **크기**: 16:9 가로, 2560×1440(1판 시작 그림과 같은 크기).
- **그림의 수준 기준**: 1판 시작 그림 `D:/Project/witch-moira-work/intro/img/tessa1.png`·`eileen1.png`·`veronica1.png`. 칸마다 이 가운데 하나를 그림 결의 기준으로 함께 붙인다.
- **인물 기준 그림**(같은 사람으로):
  - 테사: `chapter1/art/characters/ember_witch_v02.png` — 어깨 길이의 붉은 갈색 물결 머리, 호박색 눈, 늘어지는 귀걸이, 오른팔(그녀의 오른쪽)은 손끝까지 검은 돌 같은 살갗에 주황 틈, 손은 사람 손.
  - 아일린: `_local/art/intro/storyboard_v2/work/C12-r0/frost_main_a_gpt25.png`(원본 위치를 찾지 못해 사본 경로를 적음), 보조 `chapter1/art/characters/frost_witch_v02.png` — 긴 은백색 머리, 오른쪽 어깨로 늘어진 굵은 땋은 머리, 눈꽃 머리핀, 옅은 푸른 눈, 흰 털 깃, 왼팔은 반투명한 얼음빛에 서리 그물 무늬.
  - 베로니카: `chapter1/art/characters/storm_witch_v02.png` — 짧고 흐트러진 백금 머리, 보라 눈, 별 귀걸이, 높은 깃의 가슴 조끼, 두 팔의 가는 보라 번개 무늬, 허리띠의 방울.
  - 페로니아: `_local/art/intro/storyboard_v2/work/C09-r0/feronia_main_a.png`(미리보기 `_local/art/demon-main/feronia_main_a_preview.jpg`) — 위로 솟은 검은 뿔, 끝이 불빛으로 타는 긴 검은 머리, 호박빛 눈, 높은 깃의 검은 웃옷에 주황 단.
  - 마르자나: `.../work/C22-r1/marzanna_main_a.png`(미리보기 `_local/art/demon-main/marzanna_main_a_preview.jpg`) — 짙은 청록빛 검은 머리를 높이 올리고 흰 한 가닥이 흘러내림, 뒤로 휜 회색 마디 뿔, 얼음빛 눈, 얼음 결정 깃의 짙은 청록 웃옷.
  - 타키타: `.../work/C25-r1/tacita_main_a.png`(미리보기 `_local/art/demon-main/tacita_main_a_preview.jpg`) — 크게 말린 갈색 숫양 뿔, 보랏빛 검은 긴 물결 머리, 옅은 보라 눈, 목 옆의 금 간 흉터 줄, 번개 무늬 수놓은 짙은 보라 웃옷.
  - 마수: `_local/art/intro/beasts_sheet.jpg`(왼쪽 위 걷는 것, 오른쪽 위 쏘는 것, 왼쪽 아래 돌진하는 것, 오른쪽 아래 네 발 짐승). 1판 낱장 `D:/Project/witch-moira-work/intro/img/beast_walk.png`·`beast_rush.png`·`beast_shoot.png`.
- **옷 색**: 원화와 1판 그림대로 검정 바탕(3D의 보라는 따르지 않음, 6절).
- **노출**: 원화 수준까지. 가슴과 골반을 가리는 천은 불투명하다. 처지 칸은 망토로 더 가린다. 다리를 꼬거나 몸을 드러내는 자세를 주지 않는다.

**모든 요청문 앞에 붙이는 머리말(영어, 그대로)**

```
Single still frame, 16:9 landscape, 2560x1440. It will be used as the first frame of an image-to-video shot in the intro film of a medieval European dark fantasy game. Match the rendering of the attached style reference exactly: cinematic painterly-realistic CG, low-key dramatic light, wet stone, volumetric haze.
No text, letters, numbers, symbols, arrows, icons, UI, watermark or logo anywhere in the image.
No ink wash, no brush calligraphy, no East Asian painting look.
All characters are adults. Each named character must be the same person as her attached reference: same face, hair colour and cut, eye colour, horns, element-marked arm, and costume. Do not redesign or restyle them. Exposure no more than in the reference; cloth over chest and hips is opaque.
Faces are complete and calm: mouth closed, no strong expression, so they stay stable when animated.
Colour rule: fire orange, frost pale blue-white, lightning violet. Magenta only on Between-realm crystals and on beast crystals. Demon realm sky dim red.
Two-legged beasts stand and move upright on two legs and match the attached beast sheet.
```

### 4.2 그리는 차례

인물이 같은 사람으로 서는 칸부터, 그 결과를 다음 칸의 기준 그림으로 붙인다.

1. **인물 고정(한 사람 칸)**: C11 → C12 → C13 → C10. 처지 옷(망토)과 새 각도의 얼굴을 먼저 세운다. C10은 세 악마의 뒷모습 실루엣을 세운다.
2. **위기**: C17 → C21 → C24. 장소를 1판 그림(tessa1·eileen1·veronica1)에 묶는다. C24에서 멈춘 물방울의 꼴을 세운다.
3. **거래**: C18 → (디렉터 확인) → C22 → C25. C18이 세 거래 칸의 틀이다. C18이 통과하기 전에 C22·C25를 돌리지 않는다.
4. **받아들임·권능**: C19 → C26.
5. **인물 없는 칸(언제든 따로)**: C03 → C09(C03의 벌판과 C10의 실루엣을 붙임) → C07.

한 칸에 두 번까지 뽑는다. 두 번 다 얼굴이 기준 그림과 다르면 멈추고 디렉터에게 올린다.

### 4.3 칸별 요청문

각 칸: 붙일 그림 / 요청문(머리말 뒤에 붙임) / 통과 조건.

**C03 (그01)**
- 붙일 그림: 결 기준 `D:/Project/witch-moira-work/intro/img/realm1.png`.
```
The Demon Realm. Very wide view from a low camera just above a flat plain of black cracked ash that runs to a flat horizon at the lower third of the frame. Above: a low, dim-red sky of heavy, slow clouds. High in the sky one thin, perfectly straight horizontal line of white light crosses the whole frame from edge to edge like a taut thread. Small orange embers rise slowly upward from the plain; just below the white line they go dark, so a narrow clean band free of embers runs under the line. No figures, no dark mass, no buildings except a few very small black spires on the far horizon.
```
- 통과: 불티가 위로 오른다(아래로 떨어지는 줄기가 하나도 없음). 선 아래의 맑은 띠가 보인다. 5초 동안 앞으로 나아갈 빈 벌판이 화면의 아래 1/3을 채운다.

**C07 (그02)**
- 붙일 그림: 결 기준 `D:/.../img/town1.png`, 균열 색 기준 `_local/art/intro/storyboard_v2/C06.png`, 마수 `beasts_sheet.jpg`.
```
Night. A medieval town square seen from high above, rooftop height, looking down about 35 degrees. In the centre a tall vertical rift stands in the air like a door of light: a narrow jagged slit about four times a person's height, white-hot inside with a cold blue-white rim (same light as the C06 reference), hovering one storey above the paving, with BOTH its top end and its bottom end visible in the frame. Mist of another world spills from its edges and rolls down onto the stones. Around it, clusters of black crystal and a few magenta crystals have grown out of the paving in a ring. Two-legged beasts from the beast sheet (walking, shooting and charging kinds) pour out of the lower end of the rift in a dense stream and spread across the square toward the bottom of the frame: front beasts large and clearly separated, rear ones smaller; about twenty-five visible. Market stalls overturned, small orange fires starting on the roofs at the square's edges. No people.
```
- 통과: 균열이 하늘에서 내리꽂힌 빛이 아니라 떠 있는 문으로 읽힌다(위아래 끝이 다 보임). 마수가 한 마리씩 갈린다(녹아 엉킨 곳 없음). 결정 고리가 보인다.

**C09 (그03)**
- 붙일 그림: 결 기준 `D:/.../img/realm2.png`, C03 결과, C10 결과, 악마 미리보기 셋.
```
The Demon Realm, extremely wide, low locked camera. The same black plain as the attached C03 image; far ahead, a row of thin black spires. Beyond the spires an immense dark mass covers the whole horizon and the lower sky. It has no shape: its top edge is soft like heavy smoke and slightly overhangs toward the viewer, so it is not read as a mountain range. Its only visible edge is one thin red-lit rim line. The white line in the sky is broken: a gap in the middle, loose ends. In the near foreground at the bottom centre, on the edge of a black cliff, three small female figures stand upright side by side with their backs to the camera, not kneeling, about one tenth of the frame height: left with tall upward black horns and long black hair glowing ember-orange at the ends; centre with grey back-swept horns and dark teal hair in a high updo with one white lock; right with large curled brown ram horns and long wavy dark-violet hair. Faint embers, frost glitter and violet sparks around each. The dark mass has no face, eyes, mouth, hands, horns, wings, throne, human shape or glowing points.
```
- 통과: 어둠에 생김새가 하나도 없다. 산이 아니라 덮쳐 오는 연기 덩어리로 읽힌다. 세 형체가 뿔 꼴과 색으로 갈린다.

**C10 (그04)**
- 붙일 그림: 악마 원본 셋(feronia·marzanna·tacita_main_a.png), C09 결과.
```
Close behind three female demons at the very edge of a black cliff, camera slightly low behind them, framing from the knees to above the horns. Backs to the camera; no face visible. Left: Feronia (reference) - tall upward black horns, long black hair in a high mass with ember-orange glowing ends, high-collared black coat with orange trim, a few embers lifting off her. Centre: Marzanna (reference) - grey ridged horns curving back, dark teal-black hair in a high updo with one white lock falling down the back (her hair is NOT white), dark teal brocade coat with a collar of ice crystals, frost glitter around her. Right: Tacita (reference) - large curled brown ram horns, long wavy dark-violet hair, dark purple brocade coat with lightning embroidery, faint violet sparks along her fingers. Wind blows their hair and coats forward toward the drop. They stand upright side by side, one foot slightly forward at the edge. Below the cliff, a sea of dark clouds lit dim red from beneath. At the very top edge of the frame only the underside of the dark mass hangs in, a dark band with a thin red rim. No streaks of fire or lightning in the sky yet.
```
- 통과: 뒷모습만으로 셋이 메인 이미지와 같은 사람이다(특히 마르자나의 짙은 청록 머리와 흰 한 가닥). 얼굴이 보이지 않는다. 무릎 꿇지 않는다.

**C11 (그05)**
- 붙일 그림: `ember_witch_v02.png`, 결·옷 기준 `D:/.../img/tessa1.png`.
```
Night, a burned-out house at the edge of a town street, eye-level locked camera. Tessa (reference) sits alone on the charred stone threshold in the left third of the frame, full body, knees together, feet on the ground, body facing right. She wears her own costume from the reference under a plain worn brown travelling cloak with a frayed, patched hem, damp with soot; hood down so her auburn-red wavy shoulder-length hair shows. Her right forearm and hand are the dark cracked black-stone arm from the reference, with a normal human hand; the cracks are almost unlit, only a faint ember deep inside. A small plain cloth bundle tied with cord sits beside her. Her face in three-quarter profile, tired, looking right toward a distant orange fire glow at the far end of the street. In the left background, small dark silhouettes of townspeople run away to the left, backs to the camera, no faces. Smoke, a few embers in the air.
```
- 통과: 붉은 갈색 머리와 검은 돌 오른팔로 테사임이 읽힌다. 망토와 보따리가 가난하게 읽힌다(꾸민 자세가 아님). 시선이 오른쪽 불빛.

**C12 (그06)**
- 붙일 그림: `frost_main_a_gpt25.png`, 결·옷 기준 `D:/.../img/eileen1.png`, C11 결과(망토의 결).
```
A narrow alley at night in falling snow, eye level, the camera beside her tracking right. Aileen (reference) walks from left to right in the left-centre of the frame, full body, in profile facing right. Long silver-white hair in a thick braid over her right shoulder, snowflake hair pin, white fur collar, her own costume under a thin worn grey-blue travelling cloak with a frayed hem that she holds closed at her chest with her right hand. Her left forearm and hand are translucent pale ice with a net of frost lines, dull and barely glowing. Directly beside her at shoulder height, a wooden window shutter in the stone wall is swinging shut from the inside; a thin gap of warm light is still visible. Snow on barrels and cobbles, a wall lantern, a dark arch at the end of the alley.
```
- 통과: 땋은 머리가 그녀의 오른쪽 어깨, 얼음 왼팔이 보인다. 덧문이 그녀 바로 곁에서 닫힌다. 걷는 방향이 오른쪽.

**C13 (그07)**
- 붙일 그림: `storm_witch_v02.png`, 결·옷 기준 `D:/.../img/veronica1.png`, C11 결과.
```
Rainy night under the small roof of a closed city gate, camera slightly high, locked. Veronica (reference) sits alone on the stone step against the closed iron-studded gate in the left half of the frame, full body, knees drawn up, soaked. Short tousled platinum hair, violet eyes, small star earrings. Her own costume under a dark worn hooded cloak with a torn hem, hood down. The thin violet lightning-vein patterns on her arms are faint, almost invisible. A small cloth bundle beside her. She has just lifted her head and looks to the RIGHT, toward something off-screen, alert. The right half of the frame: the empty wet road along the city wall disappearing into rain, a faint glow far to the right.
```
- 통과: 시선이 위가 아니라 오른쪽. 짧은 백금 머리와 팔의 희미한 무늬로 베로니카임이 읽힌다.

**C17 (그08)**
- 붙일 그림: `ember_witch_v02.png`, 장소·옷 기준 `D:/.../img/tessa1.png`, 마수 `D:/.../img/beast_walk.png`.
```
The same burning street as the tessa1 reference (burning houses, cart, banner), but the camera is now very low near the cobbles, looking up, locked, waist-up framing. Left: Tessa (reference, same costume and translucent red cape as tessa1) has slid down with her back against a collapsed burning wall. Her left forearm is raised across her face so her face is half hidden behind it; one amber eye and her brow are visible, mouth closed. Her right arm, the cracked black-stone arm, is braced on the ground, cracks dim. Right: a two-legged walking beast (beast_walk reference: pale skull mask, black crystal spikes on the shoulder, heavy body) lunges at her; one clawed hand is a hand's width from her raised arm. On the cobbles exactly between them, the first thin bright line of fire is just breaking out of the ground. Sparks, smoke.
```
- 통과: 손과 발톱 사이가 한 뼘이다. 마수가 시트의 걷는 마수다. 장소가 tessa1의 거리다. 테사의 얼굴은 반쯤 가려져 있다.

**C18 (그09) — 세 거래 칸의 틀**
- 붙일 그림: `ember_witch_v02.png`, `feronia_main_a.png`, C17 결과.
```
Two-person shot in rolling smoke, low camera looking up, locked. A deal being offered, not tenderness. Upper left: Feronia (reference) stands high in the smoke, body turned three-quarters toward the lower right; her head is in the upper-left third and her face is at least one fifth of the frame height. Her right hand is held out palm up at chest height with one small flame floating above the palm; her other hand hangs at her side. Her eyelids are half lowered and her eyes look down at Tessa's right ARM, not at Tessa's face and not at her own hand. Mouth closed, no smile, cool and unhurried. The flame lights her face from below. Lower right: Tessa (same costume as C17) sits on the ground, her head below the middle of the frame, her face at least one fifth of the frame height, looking up at Feronia. Her cracked black-stone right arm rests on her knee in the flame light. The difference in height between their heads is at least one third of the frame height. Between the flame and Tessa's arm there is an empty gap of one full arm's length; nothing touches, no hand reaches toward her shoulder or face. The two faces do not overlap. At the right edge, dim fire and the debris of the burning street.
```
- 통과: 높이 차가 화면의 1/3 이상. 페로니아의 눈이 테사의 팔. 웃지 않는다. 팔 하나의 빈 곳. 두 얼굴 모두 1/5 이상이고 기준 그림의 얼굴이다(페로니아 머리끝의 불빛 포함).

**C19 (그10)**
- 붙일 그림: `ember_witch_v02.png`(팔과 손), C18 결과.
```
Close shot, eye level, locked, shallow depth of field. Tessa's right arm, the cracked black-stone arm from the reference, is held up in the centre of the frame, fingers slightly open. It is a HUMAN hand with normal fingernails, not claws; the cracks are still dark with a faint inner ember. Upper left: the same small free-floating flame as C18 drifts toward the hand, about a forearm's length away, not touching. Right edge: Tessa's face in profile, partly cut by the frame edge, turned back over her shoulder toward the right background, where small blurred silhouettes of townspeople run away through the smoke, out of focus. Auburn-red hair. No demon in the frame.
```
- 통과: 손이 사람 손. 그녀가 보는 쪽에 사람들이 있다. 불꽃이 아직 닿지 않았다. 악마가 없다.

**C21 (그11)**
- 붙일 그림: `frost_main_a_gpt25.png`, 장소·옷 기준 `D:/.../img/eileen1.png`, 마수 `D:/.../img/beast_walk.png`.
```
The same snowy cloister door as the eileen1 reference (iron-strapped wooden door, snow-covered stone pillars), but an eye-level camera, waist-up framing, locked. Left: Aileen (reference, same costume as eileen1) is pressed flat with her back against the closed door, shoulders touching the wood, face in profile turned right, braid over her right shoulder, eyes wide, mouth closed. Her ice left arm is pressed against the door, dull. Right: a two-legged walking beast (beast_walk reference) in mid-leap toward her; its claw is a hand's width from her face. The first ice is already forming over its claw and arm; white frost spreads in branching lines over the door and the floor from behind her left side toward the beast. Falling snow.
```
- 통과: 등이 문에 붙어 있다. 한 뼘. 서리가 그녀의 왼쪽 뒤에서 번진다. 장소가 eileen1의 문이다.

**C22 (그12)** — C18이 통과한 뒤
- 붙일 그림: `frost_main_a_gpt25.png`, `marzanna_main_a.png`, C18 결과(구도 틀), C21 결과.
```
Same composition rules as the attached C18 frame, in a blizzard inside the same cloister as C21. Upper left: Marzanna (reference: dark teal-black hair in a high updo with one white lock, grey back-swept horns, ice-crystal collar, dark teal coat; her hair is NOT white) stands high in the blowing snow, body turned toward the lower right, face at least one fifth of the frame height. Her right hand is held out palm up with a small swirl of frost spinning above it; her eyes look down at Aileen's left ARM. Mouth closed, no smile. The frost light lights her face from below. Lower right: Aileen (same costume as C21), head below the middle of the frame, face at least one fifth of the frame height, looking up at Marzanna; her translucent ice left arm is lifted halfway, palm up, still dull. Her face is clean, no marks or scars. Height difference between their heads at least one third of the frame height. One full arm's length of empty space between the swirl and her hand; nothing touches. Far right background, small figures of townspeople huddling under the cloister arches. At the right edge, a snow-covered pillar of the cloister.
```
- 통과: 마르자나 머리가 짙은 청록. 아일린 얼굴에 자국이 없다. 팔 하나의 빈 곳, 높이 차, 시선이 팔.

**C24 (그13)**
- 붙일 그림: `storm_witch_v02.png`, 장소·옷 기준 `D:/.../img/veronica1.png`, 마수 `D:/.../img/beast_rush.png`.
```
The same monastery portal and stone steps as the veronica1 reference (statues in niches, candles, tall door), rain at night, eye level, wide enough to show both full bodies, locked. Left third: Veronica (reference, same costume as veronica1) half-turned away from the beast, one arm raised across her body, face in three-quarter profile toward the right, partly shadowed. Right: a charging beast (beast_rush reference: bulky, pale boar-like skull mask with tusks, a ridge of black crystals on its back) in mid-leap toward her; its tusks are a hand's width from her. EVERYTHING IS STOPPED IN TIME: the raindrops hang in the air as separate round glossy beads with small highlights, clearly spaced, with no streaks and no motion blur; splash crowns stand frozen on the steps; a spray of water hangs behind the beast. No lightning.
```
- 통과: 빗방울이 줄이 아니라 떠 있는 알로 읽힌다(C25의 물방울과 같은 꼴). 마수가 돌진하는 마수다. 장소가 C16과 같다.

**C25 (그14)** — C18이 통과한 뒤
- 붙일 그림: `storm_witch_v02.png`, `tacita_main_a.png`, C18 결과(구도 틀), C24 결과(물방울과 장소).
```
Same composition rules as the attached C18 frame, among the suspended round raindrops of C24, the monastery portal behind, slightly out of focus. Upper left: Tacita (reference: large curled brown ram horns, long wavy dark-violet hair, pale violet eyes, thin crack-like scar lines on the side of her neck, dark purple brocade coat with a high collar) stands high, body turned toward the lower right, face at least one fifth of the frame height, mouth closed, no smile. She holds up two fingers of her right hand at chest height with one tiny violet spark between them; her eyes look down at Veronica's ARM. The violet light lights her face from below. Lower right: Veronica (same costume as C24), head below the middle of the frame, face at least one fifth of the frame height, looking up at Tacita; one arm lifted halfway, palm up, its lightning veins faint. Height difference between their heads at least one third of the frame height. One full arm's length of empty space between the spark and her hand; nothing touches. Far right at the foot of the steps, a few small figures sheltering.
```
- 통과: 목의 흉터, 두 손가락, 시선이 팔. 베로니카 옷이 C24와 같다. 물방울이 C24와 같은 꼴.

**C26 (그15, 새로 더함)**
- 붙일 그림: C24 결과(틀을 그대로), `storm_witch_v02.png`(팔을 든 자세와 번개 무늬).
```
Exactly the same camera, framing and background as the attached C24 frame. Veronica now stands facing the beasts on the right, her right arm raised high with fingers spread as in her reference; the lightning veins on both arms glow bright violet. The first thin violet bolt is coming down from the dark sky onto the lead charging beast. The raindrops are still hanging as round beads, about to fall. Two more charging beasts behind the first. Her face in three-quarter profile toward the right, calm, mouth closed.
```
- 통과: 틀이 C24와 같다. 번개가 그녀의 팔에서 이어진 힘으로 읽힌다. 얼굴이 기준 그림과 같다.

**C23**: 그리지 않는다. `D:/Project/witch-moira-work/intro/img/eileen1.png`를 `_local/art/intro/storyboard_v2/C23.png` 자리에 넣는다(지금의 스케치는 `C23_sketch.png`로 이름을 바꿔 남김).

### 4.4 고침 칸(프레임 다시 고르기, 디렉터 또는 영상 담당)
| 칸 | 영상 | 고를 프레임 |
|---|---|---|
| C04 | `D:/Project/witch-moira-work/intro/vid/g02.mp4` | 쓸 구간(2.2~4.7초)의 끝 쪽, 짐승들이 고개를 들고 오른쪽을 보는 프레임 |
| C06 | `.../vid/g04.mp4` | 쓸 구간(1.5~4.5초)의 앞쪽, 빛줄이 가늘게 열리기 시작한 프레임 |
| C14 | `.../vid/g06.mp4` | 쓸 구간(1.5~3.9초) 안에서 손을 떠난 불덩이가 보이는 프레임 |

영상을 재생해 보지 않았으므로 그 프레임이 실제로 있는지는 확인하지 못했다. 없으면 이 칸의 쓸 구간을 바꾸는지 디렉터가 정한다.

---

## 5. 시트 꼴의 고침 (`make_boards.py`에 줄 것)

목표: 사용자가 시트만 보고 영상 전체를 머릿속에서 돌릴 수 있게.

1. **한 장 요약(board_0.jpg)을 새로 만든다.** 27칸을 길이에 비례한 폭의 작은 그림으로 한 줄(두 줄로 접어도 됨)에 늘어놓고, 그 위에 박 띠(박 제목, 시작~끝 초), 아래에 자막 띠(자막 번호가 걸치는 구간), 맨 아래에 소리 띠(연출안 3.7절 4번의 음악 곡선: 낮은 현 → 북 → 빠짐 → 독주 → 한 음 → 터짐 셋, 무음 두 곳을 빈칸으로)를 그린다.
2. **칸 아래 글을 다섯 줄로 고정한다**: ① `C07 · 3.5초 · 0:20.2~0:23.7` + 재료 꼬리표(예: C06은 "1판 g04 1.5~4.5초", C07은 "새02·그02") ② 보이는 것 ③ 카메라(크기·각·움직임) ④ 소리 ⑤ 이음(→ 다음 칸). 자막은 그 아래 파란 글씨로 따로. 글은 연출안 4절 컷표에서 옮기고, 컷표의 옛 낱말(사람)은 5.1절 낱말(인간)로 맞춘다.
3. **시간 눈금**: 칸마다 누적 시작~끝 초를 적고, 칸 그림 아래에 길이 막대(1초 = 일정한 폭)를 둔다.
4. **박 제목**: 박이 바뀌는 칸에만 작게 달던 것을, 시트 위에 박마다 칸 폭 전체를 덮는 띠로 바꾼다.
5. **글자 크기**: 칸 번호 28, 본문 22, 자막 22로 키운다(지금 20·18은 시트를 한 화면에 띄우면 읽히지 않는다). 칸 글 높이(`CAPH`)를 250에서 약 330으로.
6. **화살표와 표시는 겹쳐 그린다**: `ARROWS = {"C03": [((x1,y1),(x2,y2), "카메라 앞으로")], ...}`처럼 칸마다 화살표와 짧은 이름을 적어 두고 그림 위에 그린다. 시작 그림에는 아무것도 그리지 않는다. 무음 표시와 제목 자리(C27) 상자도 이 층에 둔다.
7. **꼬리표 더하기**: "같은 틀=C14"(C20), "같은 틀=C15"(C23), "같은 틀=C24"(C26), "무음은 멈추는 순간부터"(C24). 재사용 칸에는 1판 영상 번호와 쓸 구간.
8. 칸 글의 고침: C05 "가운데 뒤의 빛 틈 앞을 오른쪽으로 달림".

---

## 6. 사용자에게 물을 것

- 인트로의 옷 색은 원화와 1판 그림의 **검정**으로 간다(게임 3D는 보라). 3D를 원화에 맞출지는 미정이고, 권고는 "원화 검정에 맞춘다"이다. 인트로는 이 권고로 진행해도 되는지만 확인한다.

나머지(채색 완성 그림으로 올림, C26 한 장 더함, 처지 칸만 망토, 그리는 차례)는 art-lead가 정했다. 유료 생성 여부와 비용은 디렉터가 사용자에게 올린다.

---

## 7. 정지 그림으로는 판단할 수 없는 것

- 1판 재사용 11칸의 움직임과 소리. 프레임 한 장만 봤다.
- C09의 "한 번 기욺", C24의 "멈춤"이 영상에서 지켜지는지, C18·C22·C25의 얼굴이 움직임 속에서 무너지지 않는지. 시작 그림이 통과한 뒤 영상에서 본다.
- 4.4절의 다시 고를 프레임이 실제로 있는지.
