# 적과 우두머리의 생김새 · 원화 프롬프트 바탕 글 (2026-11-20)

세계관·스토리 책임자(narrative-lead). 문서만 썼다. 게임 코드·데이터·에셋은 고치지 않았다. 원화 생성은 하지 않았다.

**받은 지시(원문, 2026-11-20)**: "3d모델을 유료로 사면 우리 만들 대상이 몇개나되지? 다양한 적과 정예몹이나 보스도 만들어볼까?" → 디렉터 "원화부터 무료로 시작하자" → 사용자 "그래 그러자".

**상태 표기**: 확정(기획자) / 채택(디렉터 안, 기획자 승인) / 잠정 / 미정. 장·구역·우두머리 세 이름은 **확정(기획자, 2026-11-20)**. 그 밖의 이름과 생김새는 모두 **잠정**이다.

**근거로 본 것**: 원 20절, 검토서 W2·G3·11절, `WORLD-BIBLE` 1.6·11.3절(껍질 마수, 정예), `FORESHADOW-MAP` 1.2절(적 이름 강도 1, 세 세계 공통)·5번 규칙(어린아이의 유해 금지)·D1 행, `CHAPTER1-TEXT-PLAN` 7.2절, `CAST-APPEARANCE` 1절, `NAMES-V3`, `ELITE-AND-GUARDED-SITES-LOOK`(정예 표식 자홍, 피할 색), D17(위협의 세 종류), 마녀 원화 `storm_witch_v02.png`(직접 봄), 공격 꼴은 `combat_tuning.json` 15~26행·`combat_core.gd` 674~684행·`chapter_core.gd` 989~1004행·1381~1407행.

---

## 0. 한 표

화면 크기는 주인공 키를 1로 둔 키의 비. 모든 자리의 권고안이다(2안은 각 절).

| 자리 | 이름(한 / English) | 한 줄 생김새 | 두 발 | 화면 크기 |
|---|---|---|---|---|
| 포르티쿠스 · 걷는 | 오스티아리우스 / Ostiarius | 두건 쓴 문지기 해골. 허리에 큰 열쇠 꾸러미, 쇠 박은 몽둥이 | 예 | 1.0 |
| 포르티쿠스 · 쏘는 | 발리스타리우스 / Ballistarius | 문루의 쇠뇌꾼 해골. 화살 셋을 나란히 메긴 한 손 쇠뇌를 앞으로 겨눔 | 예 | 1.0 |
| 포르티쿠스 · 돌진 | 파비사리우스 / Pavisarius | 문짝 판자로 만든 큰 방패 뒤에 웅크려 앞으로 쏠린 해골 | 예(웅크림) | 0.8 높이, 넓음 |
| 칸토리아 · 걷는 | 프살미스타 / Psalmista | 무릎 길이 성가대 겉옷, 턱을 벌려 노래하는 해골. 쇠테 두른 시편집을 몽둥이처럼 | 예 | 1.0 |
| 칸토리아 · 쏘는 | 투리페르 / Thurifer | 사슬 향로를 머리 위로 돌리는 해골. 돌리는 고리가 윤곽 | 예 | 1.0 |
| 칸토리아 · 돌진 | 캄파나리우스 / Campanarius | 깨진 종을 등껍질처럼 지고 머리를 숙여 달려드는 해골 | 예(웅크림) | 0.85 높이, 넓음 |
| 상크툼 · 걷는 | 사크리스타 / Sacrista | 짙은 제의의 해골. 한 팔과 등뼈가 검은 광물로 바뀌었고 사슬 성물함을 든다 | 예 | 1.05 |
| 상크툼 · 쏘는 | 엑소르키스타 / Exorcista | 쇠막대를 앞으로 뻗은 구마 사제의 해골. 머리뼈 위로 검은 광물 관 | 예 | 1.05 |
| 상크툼 · 돌진 | 카테나투스 / Catenatus | 쇠목걸이와 사슬에 감긴 채 등이 앞으로 굽은, 짐승에 가까워진 껍질 | 예(웅크림) | 0.9 높이 |
| 정예 1 | 요툰 / Jotunn | 마석이 웃자라 머리·어깨를 뚫고 자홍 결정 뿔이 된 거구 | 예 | 1.75 |
| 정예 2 | 람파스 / Lampas | 자홍 마석불이 든 쇠 등롱을 장대에 매단 키 큰 껍질 | 예 | 1.6(등롱 포함 2.2) |
| 정예 3(선택) | 드라코 / Draco | 속이 빈 쇠 용머리 깃발을 든 껍질. 바람에 우는 깃발 | 예 | 1.6(깃발 포함 2.4) |
| 수호자 1 | 모드구드 / Modgud | 녹슨 내림문을 갈비처럼 두른 여거인. 쇠창살 투구, 한 손에 문 빗장 | 예 | 2.5 |
| 수호자 2 | 칸토르 / Cantor | 등뼈에서 오르간 관 일곱이 부채처럼 솟은 마른 거인. 네 갈래 쇠 지휘장 | 예 | 3.0 |
| 우두머리 | 티폰 / Typhon | 끊어진 쇠목걸이와 사슬을 단 굽은 짐승 거인. 어깨에서 검은 광물 뱀목 일곱 | 예(안1) / 아니오(안2) | 3.5~4.0 |

**두 발이 아닌 자리**: 권고안에는 없다. 우두머리 티폰의 안2(뱀 하체)만 두 발이 아니다. 돌진 셋은 두 발 웅크림이라 가진 동작 묶음을 앞으로 기울여 쓸 수 있다(동작 담당 확인 필요). 티폰 안1의 뱀목 일곱은 몸에 붙은 굳은 덩어리로 두어 따로 움직이는 뼈를 넣지 않는다(움직이게 하면 그만큼 비용).

---

## 1. 공통 설정 — 이 적들이 무엇인가 [잠정]

### 1.1 껍질 마수로 짓는다

- 적은 마수다(확정, 원 20절). 지금 해골은 "균열의 침식이 인간계의 유해에 깃든 하급 마수 = 껍질 마수"로 읽는다(잠정(디렉터), 검 W2, `WORLD-BIBLE` 11.3). 이 명단은 **이 해석 위에 섰다.** 기획자가 이 해석을 거두면 일반 아홉 자리는 다시 짓는다(7절 Q1).
- 검토서 G3 "이후 추가하는 적은 처음부터 마수로 만든다"와 맞추는 법: **해골은 껍질이고 안에 든 것이 마수**라는 것을 그림에 넣는다. 뼈 사이로 뻗은 **검은 유리질 광물 결**(중간계의 것)이 안에 든 것의 흔적이다. 내장·살이 아니라 돌과 결정이다(수위 E).
- **구역이 깊을수록 안의 것이 더 드러난다.** 원 3절의 균열 단계(소형 마수 → 영역 침식 → 영역 지배자)를 한 던전 안에서 짧게 보여 준다.

| 구역 | 껍질(인간계) | 안의 것(중간계) | 읽히는 것 |
|---|---|---|---|
| 포르티쿠스 | 뼈, 거친 갈색 모직, 녹슨 쇠 | 눈구멍과 가슴의 작은 점, 관절 틈의 가는 검은 결 | 죽은 이가 일어선 것 같다 |
| 칸토리아 | 뼈, 희끗한 성가대 겉옷 위 검은 옷, 백랍빛 쇠 | 관절마다 검은 결정 덩이, 벌린 턱 안쪽 | 무언가 안에 들어앉았다(수집품 공1과 같은 그림) |
| 상크툼 | 뼈, 짙은 제의, 사슬 | 팔 하나, 등뼈, 머리뼈 위가 검은 광물로 바뀜 | 껍질보다 안의 것이 크다 |

- **세 세계 공통**(`FORESHADOW-MAP` 1.2, N21): 수도원은 세 인간계에 같은 모양으로 있다(화염: 구휼원, 빙결: 이웃 수도원, 번개: 그 수도원). 적의 이름과 생김새는 세계마다 바꾸지 않는다.
- **어른의 유해만**(`WORLD-BIBLE` 11.3, FM 5번). 성가대 적은 키·골격이 분명히 어른이다. 작은 몸, 어린 얼굴형의 머리뼈를 쓰지 않는다. 프롬프트에 매번 "adult"를 넣는다.

### 1.2 색의 규칙 [잠정, art-lead 확인 필요]

- 피할 색(`ELITE-AND-GUARDED-SITES-LOOK` 1절): 진홍(적 전조), 주황(화염·돌진), 청록(냉기·원거리), 연보라파랑(번개), 황동 금(봉인·등급). 정예 표식은 자홍(같은 문서 2절 권고).
- **일반 적은 무채에 가깝게.** 구역은 옷감과 쇠의 빛깔로만 가른다. 몸에서 빛나는 것은 눈구멍의 희미한 점 정도.
- **마석은 자홍으로 통일하는 안**(권고): 정예는 "마석이 웃자란 개체"(`WORLD-BIBLE` 11.3)이므로 정예의 자홍 표식이 곧 웃자란 마석이 된다. 표식색에 이야기의 까닭이 생긴다. 일반 적의 마석은 보이지 않거나 아주 작게 둬서 정예의 한 점을 흐리지 않는다.
- 우두머리 셋은 각자 두 색(3절). 셋이 서로 겹치지 않고 위 피할 색에서 떨어지게 골랐다.

### 1.3 종류는 윤곽으로 갈린다

| 종류 | 코어의 공격 꼴 [본 것] | 윤곽 규칙 |
|---|---|---|
| 걷는 | 제 둘레 원 1.15m | 곧게 선 키 큰 몸, 한 손 몽둥이. 가장 평범한 윤곽 |
| 쏘는 | 3줄 부채꼴, 14.7m | **팔이 몸 밖으로 뻗은 윤곽**(쇠뇌·향로 고리·막대). 멀리서 "겨눈다"가 보인다 |
| 돌진 | 앞으로 4.8m 줄 | **낮고 앞으로 쏠린 몸**, 무게(방패·종·사슬)가 앞이나 등에 있다. 키보다 폭이 넓다 |

- 지금 일반 적의 공격 예고는 바닥 표시 없이 **몸 신호**로 간다(커밋 45c5854, U-62). 돌진의 무게(방패를 내림, 종이 울림, 사슬이 끌림)가 그 신호가 된다. 생김새를 고를 때 이 점을 함께 봤다.
- 뿔은 정예 1의 표식이므로 **일반 적에 뿔을 쓰지 않는다.**

---

## 2. 구역별 일반 적 (C·D)

각 자리 안1이 권고. 이름은 수도원 사람들이 쓰던 교회 라틴(장·구역 이름과 같은 결)이고, 그 유해가 생전에 맡던 직분이다(`CHAPTER1-TEXT-PLAN` 7.2 "생전에 맡던 일"). 안2의 이름은 다른 결을 하나씩 섞었다.

### 2.1 포르티쿠스(문간·주랑) — 문간을 지키던 것들

| 자리 | 안1(권고) | 안2 |
|---|---|---|
| 걷는 | **오스티아리우스** Ostiarius(7) — 교회의 문지기 직분. 무릎 길이 두건 달린 겉옷, 큰 쇠열쇠 꾸러미, 쇠 박은 몽둥이 | **드라우그** Draugr(3) — 북유럽: 무덤에서 일어난 죽은 이. 녹슨 사슬 갑옷 조각과 부러진 창. 다른 유명 게임의 적 이름으로 널리 쓰여 확인 필요 |
| 쏘는 | **발리스타리우스** Ballistarius(7) — 쇠뇌를 다루던 이. 가죽 모자, 화살 셋을 나란히 메긴 무거운 한 손 쇠뇌를 앞으로 겨눔. 세 발이 3줄 부채꼴과 맞는다 | **푼디토르** Funditor(4) — 투석꾼. 돌팔매를 머리 위로 든 팔. 윤곽은 좋으나 "세 줄"이 손에 안 보인다 |
| 돌진 | **파비사리우스** Pavisarius(6) — 큰 방패(파비스)를 들던 이. 수도원 문짝 판자에 쇠띠를 댄 방패 뒤로 웅크림. 방패를 내리면 돌진 | **아리에스** Aries(4) — "숫양, 성벽 부수는 망치". 숫양 머리 쇠투구. **비권고**: 뿔이 정예 1의 표식과 겹친다 |

### 2.2 칸토리아(성가대석) — 노래하던 것들

| 자리 | 안1(권고) | 안2 |
|---|---|---|
| 걷는 | **프살미스타** Psalmista(5) — 시편을 부르던 직분. 무릎 길이 희끗한 겉옷 아래 짧은 검은 옷, 턱을 벌린 노래하는 머리뼈, 쇠테 두른 두꺼운 시편집을 한 손 몽둥이로 | **렉토르** Lector(3) — 읽는 이. 사슬에 매단 책을 늘어뜨림. 걷는 적치고 윤곽이 쏘는 적(늘어진 것)과 헷갈릴 수 있다 |
| 쏘는 | **투리페르** Thurifer(4) — 향로를 들던 이. 사슬 향로를 머리 위로 돌리는 팔이 둥근 윤곽을 만든다. 돌려서 연기 낀 덩이 셋을 내던진다 | **캄파나** Campana(3) — 손종을 든 이. 울릴 때 소리 고리 셋. 윤곽이 작다. 종 겹침(6절 2) |
| 돌진 | **캄파나리우스** Campanarius(6) — 종지기. 금 간 큰 종을 등껍질처럼 지고 머리를 숙인다. 돌진 전에 종이 한 번 울린다(몸 신호 = 소리). 종은 검게 삭은 청동 | **시그니퍼** Signifer(5) — 행렬 장대를 들던 이. 장대를 창처럼 앞으로 낮춘다. 종 겹침이 없으나 "껍질" 그림이 약하다 |

성가대 적에 **넣지 않는 것**: 천으로 묶은 턱이나 입(목소리를 잃은 그림은 번개 어머니의 침묵과 바로 겹친다. 강도 2 이상), 눈을 가린 천(다른 작품의 성가대 적과 비슷해진다), 작은 몸(1.1절).

### 2.3 상크툼(성소) — 성소 안쪽의 것들

| 자리 | 안1(권고) | 안2 |
|---|---|---|
| 걷는 | **사크리스타** Sacrista(5) — 성물지기. 무릎에서 자른 짙은 제의, 한 팔과 등뼈 마루가 검은 광물로 바뀜, 사슬 달린 쇠 성물함을 한 손에 | **아콜리투스** Acolytus(5) — 촛대를 들던 이. 쇠 촛대 몽둥이. 직분의 말이 어린 복사(服事)로도 읽혀 1.1절 규칙과 부딪칠 수 있다 |
| 쏘는 | **엑소르키스타** Exorcista(6) — 구마의 직분. 작은 사슬을 늘어뜨린 쇠막대를 앞으로 뻗음, 가슴을 가로지른 영대, 머리뼈 위로 검은 광물 관 | **아스페르소르** Aspersor(5) — 성수를 뿌리던 이. 뿌리개를 털어 셋을 흩뿌린다. 윤곽이 작다 |
| 돌진 | **카테나투스** Catenatus(5) — "사슬에 묶인 것". 쇠목걸이와 감긴 사슬, 끌리는 사슬 한 줄, 안의 것이 등뼈를 앞으로 굽혀 짐승에 가깝다(두 발 유지) | **바이울루스** Baiulus(5) — 짐꾼. 큰 성물함을 등에 지고 머리를 숙임. 칸토리아의 종 진 돌진과 윤곽이 겹친다 |

- 카테나투스는 장 이름 「카테나」와 뿌리가 같다. 장의 뜻(사슬)이 마지막 구역의 적에서 다시 보이는 것은 장점이고, 이름이 비슷해 헷갈리는 것은 단점이다(7절 Q4).

---

## 3. 우두머리 셋 (A)

공통 [잠정]:
- 셋 다 마수다. **계약 악마·세 모녀와 잇지 않는다.** 마수는 악마신과 지휘 관계가 없고(원 20절), 우두머리가 목소리를 내는 형식도 쓰지 않는다(FM 4번). 지시서가 든 네 고리 가운데 이 명단이 잇는 것은 **수도원 폐허와 사슬** 둘이다. 계약 악마·세 모녀와 잇는 안은 원 20절과 부딪쳐 내지 않았다.
- 셋 다 **사람에 가까운 얼굴을 갖지 않는다.** 이 던전의 깊은 곳은 뒤에 번개 어머니와의 결전 자리(P3 = D1 심부)가 된다(`ACT-STRUCTURE`). 어머니·본래 악마와 닮은 우두머리를 두면 반전 뒤 엉뚱한 읽기가 생긴다. 뿔 한 쌍, 왕관, 사람 피부를 쓰지 않는다.
- 셋의 윤곽을 서로 다르게: 모드구드 = **넓고 네모난**(문), 칸토르 = **좁고 높고 위로 퍼지는**(오르간 관), 티폰 = **크고 굽고 머리 위가 넓은**(뱀목).
- 이름의 신화를 그 세계 안에서 어떻게 부르게 되었나: 수도원 기록이 그것을 그 이름으로 적었다. 이 세계에 북유럽·그리스 신화가 있느냐는 정하지 않는다(6절 1).

### 3.1 모드구드 Modgud — 수호자 1, 포르티쿠스 끝 [이름 확정 / 생김새 잠정]

**한 줄 설정**: 수도원 문간에서 들어오는 이의 이름을 명부에 적던 문지기의 유해, 그리고 그 문 자체를 껍질로 삼아 자란 마수. 수도사들은 "이름을 묻는 문지기"라 하여 그것을 모드구드라 적었다.
(신화: 저승으로 가는 울리는 다리를 지키며 건너는 이에게 이름과 까닭을 묻는 여거인.)

**공격 꼴** [본 것: 체력 1,400, 준비 54틱]: 제 둘레 원 3.4m와 7줄 부채꼴(17.5m)을 번갈아.

| | 안1(권고) 문을 두른 여거인 | 안2 문설주를 진 거인 |
|---|---|---|
| 윤곽 | 길쭉한 팔다리의 여자 거인 꼴. 가슴과 배를 녹슨 내림문(쇠창살 문)이 갈비처럼 감쌌다. 머리는 좁은 틈이 난 쇠창살 투구 | 등이 굽은 거인이 돌 문설주를 멍에처럼 어깨에 졌다. 양끝에 사슬이 늘어짐 |
| 재료 | 뼈, 녹슨 쇠(창살·리벳), 낡은 문지기 모직, 허리에 사슬로 단 두꺼운 명부 | 뼈, 돌, 쇠사슬 |
| 무기·공격 | 한 손에 문의 큰 쇠 빗장. 원 = 빗장을 바닥에 내리찍음. 부채꼴 = 빗장을 휘둘러 문짝의 쇠못 일곱을 흩뿌림 | 원 = 문설주를 내려놓듯 찍음. 부채꼴 = 돌 조각이 튐. 무기가 두 손(어깨)이라 지시 규칙(한 손 무기)에서 벗어난다 |
| 색 두 가지 | **녹슨 쇠 갈색** + **뼈 상아**. 투구 틈 안에 희미한 흰빛 | 회색 돌 + 검은 쇠 |
| 두 발 | 예 | 예 |
| 화면 | 2.5 | 2.5 |

- 안1 권고 까닭: 신화의 "여거인·문지기·이름을 묻는다"가 모두 그림에 들어간다(투구의 틈, 명부). 내림문이 몸이 되어 "문 자체가 적"이 한눈에 읽힌다.
- **섹시는 넣지 않는다.** 여자 꼴은 키와 팔다리의 비율로만. 마녀의 매력과 경쟁시키지 않는다(다섯 사상 가운데 이 자리가 키우는 것은 `[쾌]`·`[보]`).
- 명부는 글자 없는 덩어리로 둔다. 번개 수집품 "성가대 명부의 빈칸"과 같은 물건으로 읽히지 않게 성가대가 아니라 문간의 것이다(강도 1).

### 3.2 칸토르 Cantor — 수호자 2, 칸토리아 끝 [이름 확정 / 생김새 잠정]

**한 줄 설정**: 성가대를 이끌던 선창자의 유해에 든 마수. 선창자가 먼저 부르면 성가대가 받는다 — 그것이 깨어나면 칸토리아의 껍질들이 따라 노래한다.
(라틴어: 선창자. 성가의 첫 줄을 홀로 부르는 이.)

**공격 꼴** [본 것: 체력 2,200, 준비 48틱, `chapter_core.gd` 989~1004행]: 짝수 차례 = **네 갈래 십자 줄**(앞뒤좌우 각 4.8m, 폭 1.8m), 홀수 차례 = 7줄 부채꼴. 지금 코드 이름 `frost_cross`(옛 이름 "서리의 성가대장").

| | 안1(권고) 오르간을 등에 진 선창자 | 안2 세 머리의 합창 |
|---|---|---|
| 윤곽 | 아주 길고 마른 어른 해골 거인. 등뼈에서 쇠 오르간 관 **일곱**이 부채처럼 위로 솟는다. 턱을 크게 벌림 | 한 몸통에 어른 머리뼈 셋이 나란히 붙어 함께 노래함 |
| 재료 | 뼈에 서리가 낌, 검은 쇠(관·지휘장), 어깨까지만 오는 찢긴 성가대 어깨옷 | 뼈, 성가대 겉옷 |
| 무기·공격 | 한 손에 키 높이의 쇠 지휘장, 머리가 **네 갈래 쇠틀**. 십자 = 지휘장을 내리찍으면 네 팔 방향으로 서리가 뻗음. 부채꼴 = 일곱 관에서 소리가 일곱 줄로 터짐 | 십자 = 세 입이 같이 외침. 공격과 그림이 약하게 이어진다 |
| 색 두 가지 | **서리 흰색** + **검은 쇠**. 청록 대신 흰빛으로 서리를 낸다(청록은 냉기 주인공의 색) | 뼈 흰색 + 검정 |
| 두 발 | 예 | 예 |
| 화면 | 3.0(관 포함) | 2.5 |

- 안1 권고 까닭: 일곱 관 = 7줄, 네 갈래 지휘장 = 십자. **공격의 꼴이 몸에 그려져 있어** 예고를 배우기 쉽다(`[쾌]`·`[성]`). 위로 퍼지는 윤곽이 모드구드(네모), 티폰(굽음)과 갈린다.
- 안2 비권고: 머리 셋이 "세 모녀"의 셋으로 읽힐 수 있고, 몸이 붙은 그림은 수위 경계에 가깝다.
- 번개 복선과의 거리: 성가대·노래는 번개의 목소리와 같은 갈래다(번-5 "목이 왜 이러지"). 칸토르는 **노래한다**(목소리가 있다). 입을 막거나 목을 다친 그림을 쓰지 않는다. 그러면 강도 1에 머문다.

### 3.3 티폰 Typhon — 우두머리, 상크툼 [이름 확정 / 생김새 잠정]

**한 줄 설정**: 성소 밑에 수도원이 옛 사슬로 묶어 두었던 중간계의 영역 지배자. 묶은 이들은 그것을 "신들과 싸운 괴물"의 이름으로 적었다. 누가 왜 묶었는지는 말하지 않는다(수집품 공2 "끊어진 사슬").
(신화: 어깨에서 백 개의 뱀머리가 솟은, 신들과 싸우다 져서 땅 밑에 갇힌 괴물.)

**공격 꼴** [본 것: 체력 4,500, `chapter_core.gd` 1381~1407행]: 원 3.4m와 7줄 부채꼴을 번갈아 + **바닥 공격**(주인공 발밑 반지름 1.8m, 1.2초 뒤 터짐, 4초마다) + 부하 부름. 체력 절반에서 2단계: 바닥 공격이 셋(주인공 좌우 3.8m에 더), 3초마다, 회복이 빨라짐.

| | 안1(권고) 사슬 끊은 짐승 거인 | 안2 뱀 하체의 거인 |
|---|---|---|
| 윤곽 | 크게 굽은 두 발 짐승 거인. 어깨와 등에서 **굳은 검은 광물 뱀목 일곱**이 왕관처럼 솟음. 짐승 머리(사람 얼굴 아님, 뿔 없음) | 위는 굽은 거인, 아래는 똬리 튼 굵은 뱀 꼬리. 신화에 더 가깝다 |
| 재료 | 검은 유리질 광물 판과 짙은 거죽, 부서진 쇠목걸이, 양 손목의 쇠고랑과 끊긴 사슬 | 같음 + 비늘 |
| 무기·공격 | 한 손에 자기를 묶었던 **쇠 말뚝**(끊긴 사슬이 달림). 원 = 말뚝 내리찍기. 부채꼴 = 뱀목 일곱이 한꺼번에 토함. 바닥 공격 = 주인공 발밑이 갈라지고 검은 결정이 솟음(영역 지배자에게 땅이 답한다). 부하 = 상크툼의 껍질들이 일어섬 | 같음. 꼬리 휩쓸기를 더할 수 있으나 코어에 없는 공격 |
| 색 두 가지 | **흑요 검정** + **유황 노랑**(뱀목의 입과 갈라진 틈). 신화에서 티폰은 불의 산 밑에 깔렸다 | 같음 |
| 2단계 | 남은 쇠고랑이 끊어지고 뱀목 일곱이 모두 빛난다(1단계는 셋만 빛남) | 같음 |
| 두 발 | **예** | **아니오**(뱀 하체: 걷기·사망 동작을 따로 구해야 함) |
| 화면 | 3.5~4.0(뱀목 포함) | 4.0 |

- 안1 권고 까닭: 두 발이라 가진 동작 묶음을 쓸 수 있다. 일곱 뱀목 = 7줄 부채꼴로 칸토르의 일곱 관과 "일곱"이 이어진다(던전 안의 수의 운율). 뱀목은 굳은 덩어리라 리깅 없이 몸에 붙는다. 3D 생성에서 가는 돌기는 잘 깨지므로 **뱀목은 굵게** 그린다.
- 안2를 고르면 신화에 가깝고 충격이 크지만 동작 비용이 든다(지시 D, 우두머리 예외 가능).
- 지금 우두머리 모델(사슬에 묶인 악마)은 "악마가 아닌 마수"와 긴장했다(`WORLD-BIBLE` 395행). 티폰은 **사람 꼴 악마로 보이지 않는 짐승**으로 짓는다. 사슬은 이어받는다.
- 처치 뒤 남은 껍질들이 1초 고개를 숙이는 연출(공-3, 선택)과 맞물린다: 영역 지배자가 쓰러지면 그 영역의 것들이 고개를 숙인다.
- "유황 노랑"이 장비 등급의 희귀 노랑과 가까울 수 있다. 우두머리 몸의 빛이라 바닥의 장비와는 자리가 갈리지만 art-lead가 `palette.gd`와 대 본다(6절 5).

---

## 4. 정예 2~3종 (B) [잠정]

공통: 정예는 "마석이 유난히 크게 자란 개체, 껍질이 그 힘을 못 이겨 부풀고 금이 갔다"(`WORLD-BIBLE` 11.3). 그래서 **표식 = 웃자란 마석 = 자홍 결정**이다. 공격은 지금 코어 그대로 원 3.4m와 7줄 부채꼴의 번갈음. 몸은 구역에 매이지 않는 한 벌(구역 옷감 입히기는 선택, 비용 3배).

| 자리 | 안1(권고) | 안2 | 표식 | 쓰는 곳(권고) |
|---|---|---|---|---|
| 정예 1 거구 | **요툰** Jotunn(3) — 북유럽: 거인. 어깨가 부풀어 오른 큰 껍질, 머리뼈와 어깨를 뚫고 자홍 마석 결정이 뿔처럼 솟음, 수도원 쇠붙이를 덧댄 갑옷 조각, 한 손 쇠망치 | **콜로수스** Colossus(4) — 큰 상. 이름이 널리 쓰여 무게가 덜하다 | 뿔(결정) | 승 1 사당을 지키는 정예(D13). 모드구드(북유럽 이름)를 앞서 예고 |
| 정예 2 등불 | **람파스** Lampas(3) — 그리스: 저승의 횃불 든 님프들(람파데스)의 홑이름. 키 큰 껍질이 장대 끝 쇠 등롱을 듦, 등롱 안에 자홍 마석불 | **라테르나리우스** Laternarius(7) — 등롱을 들던 이(라틴). 일반 적 이름과 결이 같아 정예로 덜 튄다 | 등롱(빛) | 승 2 상자를 지키는 정예. 등롱이 어두운 곳의 상자를 밝힌다. art-lead의 "가는 빛기둥"과 같은 자리에서 나는 빛 |
| 정예 3 깃발(선택) | **드라코** Draco(3) — 로마 기병의 용머리 깃발. 속 빈 쇠 용머리에 천 자루가 달려 바람에 운다. 깃대는 한 손 | **시그니퍼** Signifer(5) — 일반 적 안2와 겹침 | 깃발(높이) | 곁의 적을 북돋는 접사가 생길 때(design-lead). 없으면 만들지 않는다 |

- 표식을 뿔·등불·깃발로 나눈 까닭: 셋 다 **머리 위로 솟는다** — 무리에 가려도 보인다(art-lead 판정 "기둥은 무리 위로 읽힘"과 같은 이치).
- 요툰은 북유럽, 람파스는 그리스, 드라코는 로마. 우두머리 벌(북유럽·라틴·그리스)과 같이 섞인 결이다.

---

## 5. 원화 프롬프트 바탕 글 (영어)

쓰는 법: 각 자리의 글 뒤에 **공통 꼬리**를 붙인다. 자리 글 3~4문장 + 꼬리가 한 장의 프롬프트다. 세 마녀 원화(`chapter1/art/characters/*_witch_v02.png`)와 같은 세계: 반실사 다크 판타지 회화, 무너진 고딕 수도원.

**공통 꼬리 (모든 자리에 붙임)**

> Semi-realistic dark fantasy painting, the same world as a ruined gothic monastery, muted desaturated palette, crisp readable silhouette. Single full-body figure, near-frontal three-quarter view, standing in a relaxed A-pose with both arms held clear of the torso and legs slightly apart, the weapon held in one hand, no long cloak or robe hiding the legs. Plain flat neutral grey background, even studio lighting, no text, no logo, no watermark, no frame. Bone, iron, stone and cloth only: no blood, no gore, no exposed organs, no cut flesh.

**일반 적에 더 붙이는 줄**: `An adult human skeleton used as a shell by something else: thin veins of black glassy mineral run through the joints.` (상크툼은 2.3절대로 더 많이.)

### 5.1 포르티쿠스

**오스티아리우스 Ostiarius** — An adult skeleton of a monastery doorkeeper, wearing a knee-length hooded tunic of coarse undyed brown wool belted with rope. A heavy ring of large iron keys hangs at the hip, and one hand holds a short iron-shod wooden cudgel. Upright, plain, slightly forward-leaning stance. Faint pale points of light in the eye sockets.

**발리스타리우스 Ballistarius** — An adult skeleton of a gatehouse crossbowman in a battered leather cap and a short padded jerkin over the bones. One arm is extended straight forward aiming a heavy one-handed crossbow loaded with three bolts side by side; a bolt case hangs at the belt. The extended aiming arm must read clearly in silhouette. Rusted iron fittings, brown leather.

**파비사리우스 Pavisarius** — An adult skeleton crouched low and leaning forward behind a tall pavise shield made from old monastery door planks bound with rusted iron straps, held in one hand. The body is compact and wider than it is tall, head lowered behind the shield rim, legs bent ready to rush. Coarse brown wool scraps, iron, weathered wood.

### 5.2 칸토리아

**프살미스타 Psalmista** — An adult skeleton of a monastery choir singer, wearing a knee-length off-white surplice over a short black tunic, jaw wide open as if mid-chant. One hand holds a thick iron-bound psalter like a club. Clusters of black glassy crystal sit at the elbows, knees and inside the open jaw. Pewter-grey metal, no gold.

**투리페르 Thurifer** — An adult skeleton of a censer bearer in an off-white knee-length surplice. One arm is raised high, swinging a heavy iron censer on a long chain in a wide circle above the head, the chain arc forming the silhouette; thin pale smoke trails from the censer. Black crystal clusters at the joints. Pewter-grey metal, no gold.

**캄파나리우스 Campanarius** — An adult skeleton of a bell ringer bent far forward, carrying a cracked bronze bell on its back like a shell, the bell mouth facing backward. Head lowered, one hand gripping a short length of bell rope, legs bent in a running crouch. The bronze is dark and blackened with dull green patina, not shiny. Black crystal clusters at the joints.

### 5.3 상크툼

**사크리스타 Sacrista** — An adult skeleton of a sacristan in heavy dark vestments cut at the knee, faded ochre embroidery. One forearm and the ridge of the spine have been replaced by black glassy mineral, as if the thing inside is pushing out. One hand carries a small iron reliquary box on a short chain. Slow, heavy, upright stance.

**엑소르키스타 Exorcista** — An adult skeleton of an exorcist priest in dark vestments with a long stole crossed over the ribs. One arm is extended straight forward holding an iron rod hung with small chains, the aiming arm clear in silhouette. A crown of jagged black mineral grows from the top of the skull. Faded ochre and black.

**카테나투스 Catenatus** — A hunched adult skeleton bound in a heavy iron collar and coils of chain, spine bent forward by black mineral growth so it looks more beast than man, still standing on two legs. One length of chain drags from the collar to the floor; one hand is clawed with mineral. Low, forward-leaning, wider than tall.

### 5.4 정예

**요툰 Jotunn** — A swollen giant-sized adult skeleton shell, shoulders and ribcage bulging and cracked, with large magenta crystals bursting out of the skull and shoulders like horns. Patchwork armour of monastery iron plates strapped to the chest and forearms, a heavy iron maul in one hand. Bone and dark iron, the magenta crystal is the only saturated colour.

**람파스 Lampas** — A tall thin adult skeleton shell with cracked bones, holding in one hand a long iron pole with a caged iron lantern hanging at the top, high above its head. Inside the lantern burns a magenta crystal flame that lights the figure from above. Dark tattered vestments to the knee. The magenta light is the only saturated colour.

**드라코 Draco** — A tall adult skeleton shell holding in one hand a standard pole topped by a hollow iron dragon head with a long tattered cloth tail, the dragon head raised high above the figure. Small magenta crystals grow through cracks in the ribs. Bone, dark iron, faded cloth.

### 5.5 우두머리

**모드구드 Modgud** — A towering, long-limbed giantess built from a monastery gatehouse, her ribcage and belly caged by a rusted iron portcullis, her head enclosed in a barred iron gate-helm with a narrow slit through which a faint white light shows. One hand holds the gate's huge iron crossbar as a club; a thick closed ledger hangs from her belt on a chain. No face visible, no horns, not sensual. Colours: rusted iron brown and bone ivory.

**칸토르 Cantor** — A very tall, gaunt adult skeleton giant, the choir master, with seven black iron organ pipes rising from its spine and fanning upward behind its shoulders. Its jaw hangs wide open in song, white hoarfrost coats the bones, and a torn short choir mantle covers only the shoulders. One hand holds a staff as tall as the figure, topped with a four-armed black iron frame. Colours: frost white and black iron, no teal.

**티폰 Typhon** — A massive hunched beast-giant standing on two thick legs, its body of black glassy mineral plates over dark hide, with a beast head that is not human and has no horns. Seven thick, stiff serpent necks of black mineral rise from its shoulders and back like a crown, their open mouths glowing sulphur yellow. A broken iron collar hangs at its neck, iron shackles with snapped chains on both wrists, and one hand grips the heavy iron stake it was once chained to. Colours: obsidian black and sulphur yellow.

(안2를 고르면 그 자리의 2안 칸을 같은 꼴로 옮겨 쓴다. 티폰 안2는 A자세가 성립하지 않으므로 "upper body in A-pose, serpent tail coiled behind"로 바꾼다.)

---

## 6. 원천 기획안·결정 기록·다른 문서와의 긴장

| # | 어디 | 무엇 | 처리 |
|---|---|---|---|
| 1 | `NAMES-V3` 4절 긴장 3·5, 원 20절 | 모드구드(북유럽)·티폰(그리스)이 라틴 수도원에 붙은 까닭이 세계 안에 없다. "수도원 기록이 그 이름으로 적었다"로 두었으나, 그러면 그 세계에 그 신화가 있어야 한다. 특히 티폰의 "신들과 싸운 괴물"은 시즌 2의 중간계의 신을 떠올리게 할 수 있다(강도 1, 시즌 2 씨앗으로는 해가 없다) | 세계 안의 까닭은 정하지 않았다. 화면 글에 신화 설명을 싣지 않는 것으로 막는다 |
| 2 | 마녀 원화 `storm_witch_v02.png`(직접 봄: 치마의 종 세 개, 뒤의 종탑) | 칸토리아의 종지기(돌진)가 번개 마녀의 종과 같은 물건이다. "그녀가 죽은 수도원의 종"으로 이어지면 적 이름 강도 1을 넘는다 | 권고는 유지(몸 신호로 가장 좋음). 피하려면 안2 시그니퍼 |
| 3 | 검토서 G3 | "이후 추가하는 적은 처음부터 마수로 만든다". 일반 아홉은 여전히 해골이다 | 껍질 안의 검은 광물 결로 "안에 든 마수"를 그림에 넣어 맞췄다. 해골을 버리고 중간계 짐승으로 짓는 길은 7절 Q1 |
| 4 | `CHAPTER1-TEXT-PLAN` 7.2 | "노래 없는 성가대장"(권고였음) — 노래를 잃은 그림 | 사용자의 이름 확정(칸토르)으로 거둔다. 이 명단은 칸토르가 **노래한다** |
| 5 | `ELITE-AND-GUARDED-SITES-LOOK` 2절 | art-lead 권고 "안 1 몸 + 가는 기둥 + 자홍". 이 명단은 자홍을 웃자란 마석으로 읽고 정예를 뿔·등불·깃발 셋으로 나눴다 | 어긋남 없음. 둘째·셋째는 새 몸이 든다 |
| 6 | 코어 | 정예는 한 종(공격 같음)뿐이다. 세 정예의 차이는 지금 생김새뿐 | 접사·역할은 design-lead |
| 7 | `CAST-APPEARANCE` 1절 | 어머니·본래 악마와 닮지 않게 | 우두머리 셋에 사람 얼굴·뿔 한 쌍·왕관을 쓰지 않았다 |

---

## 7. 디렉터·사용자가 정할 것

| # | 물음 | 안 | 권고 |
|---|---|---|---|
| Q1 | 일반 적을 "해골 껍질 + 안의 마수"로 갈까, 해골을 버리고 처음부터 중간계 짐승으로 갈까 | (가) 껍질 마수(이 문서) / (나) 중간계 짐승(대부분 네 발·날개가 되어 동작 비용) | **(가).** 두 발 동작을 그대로 쓰고, 수도원이라는 장소가 적의 모습으로 읽힌다. 껍질 마수 해석(잠정, W2)도 이것으로 기획자 확정을 받는다 |
| Q2 | 우두머리 생김새 | 모드구드 안1/안2, 칸토르 안1/안2, 티폰 안1(두 발)/안2(뱀 하체) | 모두 안1. 티폰은 비용을 들여도 신화에 가깝게 가고 싶으면 안2 |
| Q3 | 정예 몇 종 | 둘(요툰·람파스) / 셋(+드라코) | **둘.** 셋째는 곁을 북돋는 접사가 설계될 때 |
| Q4 | 일반 적 이름의 결 | (가) 교회 라틴 직분(권고 아홉) / (나) 신화의 죽은 이 이름(드라우그 등, 아홉을 채우기 어렵다) | **(가).** 장·구역 이름과 같은 결이고, 이름이 곧 "문간·성가대·성소의 것"을 말한다. 대신 길다(5~7자) |
| Q5 | 칸토리아 돌진: 종지기 / 장대 든 이 | 2절 표 | 종지기. 번개 마녀의 종과 겹치는 것을 받아들일 때 |
| Q6 | 원화를 몇 장부터 | (가) 우두머리 셋 + 정예 둘 = 5장 먼저 / (나) 구역 하나의 일반 셋 먼저 | **(가).** 지금 가장 비어 있는 자리이고 플레이어가 가장 오래 본다. 일반 적은 해골이 이미 있다 |

---

## 8. 확인하지 못한 것

- 동작 묶음: 웅크린 돌진(파비사리우스·캄파나리우스·카테나투스)이 가진 달리기 동작을 앞으로 기울여 쓸 수 있는지 보지 않았다. 티폰 안1의 무게(굽은 거구)에 가진 걷기가 어울리는지도.
- 화면 크기: 주인공과 해골의 실제 픽셀 비를 재지 않았다(art-lead 문서의 해골 약 55px만 봤다). 표의 크기는 목표 비다.
- 색: 유황 노랑과 희귀 등급 노랑, 서리 흰색과 냉기 효과, 녹슨 갈색과 진홍 전조의 거리를 `palette.gd`·캡처로 대 보지 않았다.
- 이름 겹침: 드라우그(다른 게임의 적), 람파스·드라코·요툰의 다른 작품 쓰임, 라틴 직분 이름의 우리말 표기(외래어 표기법 용례 대조 안 함), 새 글자(프살·쿠스)가 글꼴에 있는지 보지 않았다.
- 정예 부채꼴 7줄이 탄인지 즉시 판정인지(그림의 "던진다/토한다"와 맞는지)는 코드의 예고 부분만 봤다.
- 원화 생성은 하지 않았다. 프롬프트가 A자세·한 손 무기·평평한 바탕을 실제로 지키는지는 첫 생성에서 본다.
- 사람의 판정(미평가): 구역이 바뀌면 "다른 곳에 왔다"가 적으로 읽히는지, 세 종류가 윤곽으로 갈리는지, 우두머리 셋이 멋있는지.
