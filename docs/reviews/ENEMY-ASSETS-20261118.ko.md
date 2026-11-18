# 적 3D 모델 에셋 조사

작성 2026-11-18. 조사와 권고만 한다. **아무것도 내려받지 않았고, 가입·구매·약관 동의를 하지 않았다.** 코드와 데이터를 고치지 않았다. 외부 검색어와 주소에 프로젝트 이름이나 사용자 정보를 넣지 않았다.

읽는 법
- [페이지] = 그 페이지의 글을 직접 읽었다. [검색] = 검색 요약으로만 봤다(틀릴 수 있다). "미확인" = 근거를 찾지 못했다.
- **후보 모델의 미리보기 그림은 하나도 보지 못했다.** 페이지를 글로만 읽는 도구를 썼기 때문이다. 그래서 이 문서는 어떤 후보도 "보기 좋다"고 적지 않는다. 화풍 칸은 페이지의 낱말(로우폴리, 카툰, 그라디언트 아틀라스 등)과 알려진 제작자 성향에서 나온 **추정**이다. 사기 전에 사용자가 페이지의 그림을 직접 봐야 한다.
- 가격·라이선스는 2026-11-18 기준이다. 결제 직전에 다시 본다. 원화 환산은 1달러 약 1,450원으로 어림했다.
- OpenGameArt는 자동 조회를 막아(HTTP 403) 페이지를 하나도 직접 읽지 못했다. 그곳 후보는 모두 [검색]이다.

---

## 1. 지금 있는 적과 빈 곳

### 1.1 적 역할과 모델(코드·파일로 확인)

코어의 적 종류는 넷(`walker`, `ranged`, `charger`, `elite`)이고 화면 종류는 다섯이다. 모델 파일은 둘뿐이다. 근거: `chapter1/data/combat_tuning.json` 14~25행, `chapter1/view/actors/chapter_actors.gd`, `docs/specs/T2-perf-directives-20261118b.ko.md` 0.2절.

| 역할 | 화면 | 모델 | 변형 방법 | 수(풀) |
|---|---|---|---|---|
| `walker` 근접 | 해골 무법자 | `skeleton_outlaw_merged.glb` | 크기 .60~.645 네 단계, 머리 뼈 .72, 뼈색 조정. 색 변형 없음 | 144 |
| `ranged` 원거리 | 악마 몸을 가늘게(.44,.58,.44), 청회색 | `chained_demon_animated.glb` | 비균등 크기, 색, 코드로 만든 지팡이, 사슬 숨김 | 40 |
| `charger` 돌진 | 같은 몸을 납작하게(.72,.48,.72), 주황갈색 | 같은 파일 | 비균등 크기, 색 | 40 |
| `elite` 구역 0·1 수호자 | 같은 몸 .80, 어깨 장식(구·원뿔 도형) | 같은 파일 | 크기, 색, 코드 도형 | 판당 1씩 |
| `elite` 구역 2 최종 우두머리 | 사슬 포함 원본 1.15 | 같은 파일 | 부위별 색 | 1 |

캡처(`_local/shots/bb-on/09-playing-2400.png`)를 직접 봤다. 해골은 화면 높이의 약 5%(1080p에서 50~60px)로, 사실에 가까운 비례에 낮은 채도의 뼈색이고 도끼를 들었다. 원거리는 어두운 청회색의 가는 인간형, 돌진은 주황갈색의 네 발로 기는 듯한 낮은 몸이다. 이 크기에서는 얼굴이나 무늬가 아니라 **실루엣과 색 덩어리**만 읽힌다.

### 1.2 모델별 수치(GLB의 JSON 머리를 읽음, 2026-11-18)

| 항목 | 해골 무법자 v02 | 사슬 악마 v01 |
|---|---|---|
| 파일 | `chapter1/art/skeleton_outlaw/v02/skeleton_outlaw_merged.glb` (5.5MB) | `chapter1/art/chained_warden/v01/chained_demon_animated.glb` (1.3MB) |
| 메시 / 정점 / 삼각형 | 1 / 5,375 / 6,594 | 1 / 1,068 / 1,474 |
| 표면(재질) / 텍스처 | 2(몸, 도끼) / 2 | 3(피부, 가면, 사슬) / 1 |
| 뼈 | 57 | 73 |
| 정점당 가중치 | 8개까지 | 8개까지 |
| 클립 | 9개: `idle`, `idle_alert`, `walk`, `run`, `attack_slam`, `attack_cross`, `attack_fan`, `hit`, `death` (모두 길이 4.967초로 저장됨. 쓰는 구간은 코드 상수) | 8개: `idle` 1.225, `walk` 1.225, `windup_slam` .925, `windup_fan` .925, `slam` .625, `fan` .625, `hit` .325, `death` 1.125초 |
| 지금 쓰는 클립 | `idle`, `walk`, `attack_slam`, `hit`, `death`(T2 B-2). `run`, `idle_alert`, `attack_cross`, `attack_fan`은 들어 있으나 쓰는지 **미확인** | 전부 |
| 클립 출처 | 이 프로젝트가 만든 것("저작 9클립") | 이 프로젝트가 만든 FK 8클립 |

### 1.3 출처와 라이선스 기록

| 모델 | 원작 | 라이선스 | 기록 위치 | 비고 |
|---|---|---|---|---|
| 해골 무법자 | KevDev, Skeleton Outlaw(OpenGameArt) | CC0 | `chapter1/art/skeleton_outlaw/v02/ATTRIBUTION.ko.md` | **기록에 구멍이 있다.** 이 파일은 "원출처·라이선스·보존 원본은 `../v01/ATTRIBUTION.ko.md`와 `SOURCE.json` 참조"라고 적는데, `v01/` 폴더와 `SOURCE.json`, `DERIVATION.json`은 이 저장소에 없다(옛 저장소에 남은 것으로 보인다). 원 페이지 주소도 v02 파일에 없다. 검색으로는 OpenGameArt의 해당 글이 KevDev, CC0, FBX, 6,174폴리곤으로 나온다 [검색] |
| 사슬 악마 | Mophs, Chained Demon(OpenGameArt) | CC BY 3.0을 선택(원 글은 여러 라이선스 중 택일) | `chapter1/art/chained_warden/v01/ATTRIBUTION.ko.md` | **출시물에 출처 표시가 필요하다**(제작자, 제목, 라이선스, 변경 사실). 원본·파생 .blend는 저장소 밖 `C:/Project/game-research/art-sources/...`에 있다고 적혀 있다(있는지 **미확인**) |
| 주인공(참고) | thecubber, Rigged textured mage | CC BY-SA 3.0 | `chapter1/art/rigged_mage/v01/ATTRIBUTION.ko.md` | 적은 아니다 |

`chapter1/art/actors/{walker,ranged,charger,elite}.png`·`.json`은 생성한 2D 스프라이트다. 코드가 아직 읽어 들이지만(34행) 지금 화면의 적은 3D다.

### 1.4 세계관이 요구하는 적

근거: `docs/SEASON1_WORLD_STORY_MASTER.md` 2~4절, `docs/story/WORLD-BIBLE.ko.md` 11.3절(잠정), `docs/story/CHAPTER1-TEXT-PLAN.ko.md` 7.2절, `docs/ART-PLAN.ko.md` 3.2절, `docs/specs/D2-elite-carrier-spec.ko.md` 6.2절.

- **적은 "마수"다.** 중간계의 토착 생명체이고 악마신의 부하가 아니다(확정). 언데드나 악마가 아니다.
- 지금의 해골은 "균열의 침식이 유해에 들어앉은 하급 마수(껍질 마수)"로 읽는다(디렉터 잠정안). 우두머리는 "옛 사슬에 묶여 있던 영역 지배자"다.
- **악마는 적이 아니다.** 악마는 마녀에게 힘을 주는 쪽(어머니들)이다. 임프·악마 병사 같은 "악마" 잡몹은 설정과 부딪힌다. 쓰려면 악마가 아니라 마수로 읽히는 생김새여야 한다.
- 어린아이의 유해는 쓰지 않는다(11.3절). **머리가 크고 몸이 작은 2~3등신 해골은 아이로 읽힐 수 있어 이 규칙에 걸릴 위험이 있다.**
- 종교·신화 상징을 게임에서 쓰지 않는다(주인공 망토 문양을 지운 기록). 십자가나 성직 문양이 든 모델은 지우는 작업이 든다.
- 살아 있는 수도사·성직자·광신도는 설정에 없다. 수도원의 껍질은 "수사·순례자·문지기 같은 어른의 유해"다. 따라서 "타락한 성직자"는 사람 모델이 아니라 **두건·수도복 조각을 걸친 해골**이 맞다.

### 1.5 빈 곳

| 필요한 것(계획) | 수 | 지금 | 빈 정도 |
|---|---|---|---|
| 일반 3역할의 서로 다른 실루엣 | 3 | 원거리·돌진·수호자·우두머리가 한 악마 몸의 크기·색 변형 | 원거리와 돌진이 같은 몸이라 구분이 색과 납작함뿐이다. 악마 몸은 정점 1,068개로 가볍지만 "악마"로 읽힌다 |
| 구역 변종(색·장식) | 6~9 | 없음 | 변형으로 채울 계획 |
| 새 역할: 자폭·강화·소환(M5) | 3 | 없음 | 모델 없음. "공개 에셋 우선" |
| 보물 운반자 | 1 | 없음 | 해골 + 등짐 변형 계획 |
| 구역 우두머리 | 2 | 악마 몸 .80 + 도형 어깨 | 고유 실루엣 없음 |
| 던전 보스 | 1 | 사슬 악마 원본 | 있음(연구 모델, 외형 검수 중이라고 기록) |
| 마수다운 것(짐승형, 중간계 생물) | — | 없음 | 설정은 "소형·중대형 마수"를 말하는데 화면에는 해골과 악마 몸뿐이다 |

### 1.6 기술 제약

- 일반 적은 정점 움직임을 텍스처로 구워 MultiMesh로 그리는 방식으로 옮기는 중이다(`chapter1/view/actors/vat/`, 시험판은 `walker` 한 종, 스위치 `--chapter1-vat-walker`).
- 굽기는 Godot 안에서 `AnimationPlayer`를 샘플링하므로 **뼈대의 종류(인간형, 네 발, 거미)는 상관없다.** GLB에 스켈레톤과 클립이 들어 있으면 된다.
- 텍스처 가로 = 정점 수(최대 16,384), 세로 = 프레임 수. 해골(5,375 × 약 191줄)이 약 12MB다. 정점이 1,500~3,000이면 3~7MB로 준다. **정점 수가 적을수록 좋고, 재질(표면)이 하나면 묶음도 하나다.**
- 일반 적에 필요한 클립: 대기, 걷기, 공격, 피격, 죽음. 돌진형은 달리기, 원거리는 시전이 있으면 좋다.
- 정예·우두머리는 지금처럼 스켈레톤으로 그리므로 더 무거워도 된다.

---

## 2. 후보

### 2.1 무료(CC0·CC BY)

| 후보 | 제작자 | 가격 | 라이선스 | 형식 | 뼈·클립 | 정점/삼각형 | 화풍(추정)과 거리 | 쓸 수 있는 역할 |
|---|---|---|---|---|---|---|---|---|
| [KayKit Character Pack: Skeletons](https://kaylousberg.itch.io/kaykit-skeletons) | Kay Lousberg | 무료(전사·도적·마법사·졸개 4체). 7.95달러: 골렘·강령술사 추가. 11.95달러: .blend 원본, 클립 75개 | CC0, 표기 불필요. "수정 안 한 사본을 되팔지 말라"는 부탁이 붙어 있다 [페이지] | FBX, glTF | 리깅·기본 이동 클립 포함 [페이지]. 클립 이름 목록 미확인 | 미확인("low poly optimized") | 그라디언트 아틀라스 한 장(1024²), 머리 큰 양식화로 알려져 있다(그림은 못 봄). **지금 해골과 비례가 다를 가능성이 높고, 1.4절의 "아이로 읽힘" 위험이 있다** | 무기·방패·지팡이 등 부속 10종 이상을 지금 해골에 붙이는 **부품 공급원**으로 쓰는 편이 안전. 골렘(유료 단계)은 구역 우두머리 후보 |
| [KayKit Character Animations](https://kaylousberg.itch.io/kaykit-character-animations) | Kay Lousberg | 무료(원본 14.99달러) | CC0 [페이지] | FBX, glTF | 인간형 클립 161개(일반, 이동, 근접, 원거리, 특수 등). 중간·큰 뼈대 둘 | — | — | KayKit 뼈대용. 다른 인간형에는 엔진 리타기팅이 필요하고 결과는 다를 수 있다고 적혀 있다 |
| [Quaternius Bestiary – Dungeon Monsters Kit](https://quaternius.com/packs/bestiarydungeonmonsterskit.html) (2026-08) | Quaternius | 기본판 무료(묶음의 60~70%). 원본판 가격은 그림으로만 표시돼 미확인 | **QAL v1.0**(CC0가 아니다): 상업 사용·수정 가능, 표기 불필요, 에셋 자체의 재배포·재포장 금지, 엔진 제한 없음, AI 조항 없음 [페이지: [quaternius.com/license.html](https://quaternius.com/license.html)] | FBX, OBJ, glTF | 괴물 7종, 인간형 뼈대, 종마다 색 텍스처 3벌. **클립은 들어 있지 않은 것으로 보인다**(페이지의 "Animated" 표시가 X). Universal Animation Library와 호환 | 미확인 | 텍스처가 있는 새 계열. 괴물 이름과 생김새 미확인 | 인간형 괴물 7종 × 색 3벌. 클립을 Universal Animation Library에서 옮겨 와야 한다(작업 있음) |
| [Quaternius Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) | Quaternius | 기본판 무료 | CC0 [페이지] | FBX, glTF | 인간형 공통 뼈대, 120개 이상(8방향 이동, 죽음, 전투 등). 피격·좀비 걸음이 있는지 미확인 | — | — | 위 묶음과 다른 인간형 모델의 클립 원천 |
| [Quaternius Ultimate Monsters](https://quaternius.com/packs/ultimatemonsters.html) | Quaternius | 무료 | CC0 [페이지]. Sketchfab 쪽 표시는 CC BY 4.0로 어긋난다. 공식 사이트에서 받으면 CC0 | FBX, OBJ, Blend, glTF | 50종, 공격·죽음·달리기·걷기 등 [Sketchfab 설명] | 50종 합계 삼각형 212,200 / 정점 115,800 → **1종 평균 삼각형 약 4,200, 정점 약 2,300** [Sketchfab 수치에서 셈] | 단색 면의 카툰 로우폴리, 귀여운 쪽으로 알려져 있다(그림 못 봄). 지금 화면과 **멀 가능성이 높다** | 수치는 굽기에 알맞다. 색을 어둡게 눌러 "중간계 생물"로 쓸 수 있는 종이 몇이나 되는지는 사용자가 그림을 봐야 안다 |
| [Quaternius Ultimate Animated Animals](https://quaternius.com/packs/ultimateanimatedanimals.html) | Quaternius | 무료 | CC0 [페이지] | FBX, OBJ, Blend, glTF | 동물 12종, 종마다 클립 12개 이상(공격, 죽음, 걷기, 질주 등) | 미확인 | 위와 같은 계열. 늑대가 들어 있는지 미확인 | 짐승형 마수(돌진형)의 바탕 |
| [Quaternius Zombie Apocalypse Kit](https://quaternius.com/packs/zombieapocalypsekit.html) (2024-03) | Quaternius | 무료 | CC0 [페이지] | FBX, OBJ, Blend, glTF | 좀비 4종 + 개 2종. 적 클립 수 미확인 | 미확인 | 현대 복장의 좀비로 보인다(미확인). 맞지 않을 가능성 | 개 2종만 짐승형 후보 |
| Quaternius 옛 묶음: [Animated Monster](https://quaternius.com/packs/animatedmonster.html)(4종, 2018), [Easy Enemy](https://quaternius.com/packs/easyenemy.html)(5종, 2019), [LowPoly Animated Monsters](https://quaternius.itch.io/lowpoly-animated-monsters)(박쥐·해골·슬라임·용) | Quaternius | 무료 | CC0 [페이지] | FBX, OBJ, Blend | 종마다 자체 클립 | 미확인 | 단색 카툰 | 박쥐 정도 |
| [Dreamkit Character Pack: Monsters](https://dreamerh.itch.io/dreamkit-character-pack-monsters) | dreamerh | 무료 5종, 6달러 이상 28종 | CC0, "생성 AI 미사용" 표시 [페이지] | FBX, Blend | 뼈대 2종 이상이 대부분의 모델에 맞는다고만 적힘. **클립 설명 없음** | 미확인 | 그라디언트 아틀라스(KayKit풍) | 클립을 직접 붙여야 해서 우선순위 낮음 |
| OpenGameArt: Vampire Bat (Animated), Evil Giant Rat, Wolf Low Poly (Rigged), 3d wolf, Mutant Grunt, Goblin(CDmir) | 여러 사람 | 무료 | 모두 CC0로 나온다 [검색]. **페이지를 직접 못 읽었다** | 주로 .blend | 박쥐·쥐는 리깅·클립 있음, 늑대는 리깅만(클립 미확인) [검색] | 박쥐 약 7,700삼각형, 늑대 정점 318 [검색] | 건마다 다름. 미확인 | 자폭형(쥐·박쥐), 돌진형(늑대). 사용자가 페이지를 열어 라이선스와 그림을 확인해야 한다 |
| OpenGameArt: Mophs의 다른 모델("Creature" 등) | Mophs(지금 악마 몸의 제작자) | 무료 | CC BY 3.0 / GPL 3.0 / OGA-BY 3.0 택일 [검색] | 미확인 | 미확인 | 미확인 | **지금 우두머리와 같은 제작자라 화풍이 이어질 가능성**(추정, 그림 못 봄) | 구역 우두머리·정예 후보. 가장 먼저 열어 볼 만하다 |
| [Poly Pizza](https://poly.pizza/search/monster) | 모음 사이트 | 무료 | 모델마다 CC0 또는 CC BY. 검색 목록에는 라이선스가 안 보여 건마다 확인 필요 [페이지] | glTF/FBX | 대부분 Quaternius 모델의 낱개 판(Ghost, Demon, Zombie, Skeleton, Giant, Yeti 등) | 미확인 | Quaternius와 같다 | Quaternius 묶음을 낱개로 볼 때 편하다 |
| Kenney | Kenney | 무료 | CC0(저장소의 소리 라이선스 파일로 확인) | — | 적으로 쓸 리깅 괴물 묶음을 찾지 못했다 | — | 블록형 | 해당 없음 |

### 2.2 저가(팩당 몇 만 원 이하)

| 후보 | 제작자 | 가격 | 라이선스 요지 | 형식 | 뼈·클립 | 정점/삼각형 | 화풍(추정) | 쓸 수 있는 역할 |
|---|---|---|---|---|---|---|---|---|
| [Downrain DC 낱개 괴물](https://downraindc3d.itch.io/) (약 260종) | Downrain DC | 종당 6.99~11.99달러(약 1만~1만 7천 원) | "상업·개인 프로젝트에 사용 가능. 무단 공유·재판매 금지. 구매 뒤 수정해 게임에 쓸 수 있다." 표기 의무 문구 없음, 엔진 제한 문구 없음, AI 조항 없음. "생성 AI 미사용" 표시 [페이지: 5종에서 같은 문구] | **GLB(고도용이라고 명시)** + FBX | 종마다 리깅과 자체 클립 6~11개 | 아래 표 | 미확인(그림 못 봄). 1024² 텍스처 3장 구성 | 아래 표 |
| [Low Poly Spider Pack](https://returnerreign.itch.io/lowpoly-spider-pack) | returnerreign | 4.99달러 | 상업 사용·수정 가능, 표기 불필요, 재배포·재판매·다른 묶음에 포함 금지. "생성 AI 미사용" [페이지] | FBX, GLB | 거미 10종 변형, 클립 5개(대기, 걷기, 공격, 피격, 죽음) | 종당 삼각형 800~1,600 | 미확인 | 자폭형·소환물. 한 묶음으로 구역 변종까지 |
| [Animated Cartoon Fantasy Monster Pack](https://overactiongames.itch.io/animated-monster-pack) | Overaction Games | 13.63달러 | CC0 [페이지] | FBX, Blend | 슬라임, 해골, 기사 해골, 고블린, 오크, 멧돼지, 큰 쥐, 뱀 등 14~15종. 종마다 대기·공격·피격·죽음·걷기 | 미확인 | "카툰"이라고 스스로 적음. 멀 가능성 | 쥐·멧돼지·기사 해골. 유료인데 CC0라 변형·재사용이 자유롭다 |
| [Low Poly Dark Fantasy Pack](https://ake-studio.itch.io/low-poly-dark-fantasy-pack) | AKE Studio | 15달러 | 게임·앱·영상에 사용 가능, 원본 파일에 접근되는 재배포 금지, NFT 금지. 수정 허용 여부가 적혀 있지 않다 [페이지] | 미확인(.rar, Unity 렌더 파이프라인 언급 → Unity 패키지일 수 있다) | 리깅 있음. **클립 유무 미확인** | 미확인. 512² 텍스처 한 장 공유 | "low poly dark fantasy" | 흡혈귀, 해골, 미노타우로스, 돼지 인간, 보스 2종, 기사 석상. 형식과 클립을 판매자에게 물어야 한다 |
| [RPG Monster Wave Polyart](https://assetstore.unity.com/packages/slug/157652) | Dungeon Mason | 20달러 | Unity Asset Store 표준 EULA | Unity 패키지(안의 FBX 유무 미확인) | 미확인 | 미확인 | 폴리아트(밝은 카툰으로 알려짐) | 참고 |
| [Animated Undead Warriors Pack](https://assetstore-fallback.unity.com/packages/3d/characters/humanoids/fantasy/animated-undead-warriors-pack-78288) | 3dJeebs | 15달러 | Unity Asset Store 표준 EULA | Unity 패키지, 2017년 이후 갱신 없음 | 손그림 로우폴리 해골, 대기 2·걷기·달리기·공격 2·죽음 [검색] | 미확인 | "손그림 로우폴리"라 지금 해골과 가까울 수 있다(추정) | 해골 변종. 피격 클립이 없다 |

Downrain DC에서 페이지를 직접 읽은 다섯 종:

| 종 | 가격 | 정점 / 삼각형 | 클립 | 텍스처 | 쓸 자리 |
|---|---|---|---|---|---|
| [Ghoul](https://downraindc3d.itch.io/ghoul) | 7.99달러 | 1,413 / 2,652 | 11: 대기, 걷기, 달리기, 공격 3, 피격 2, 기절, 죽음, 일어남 | 2048² 6장 | 근접 변종, 돌진형. "일어남"은 등장 연출에 쓸 수 있다 |
| [Shadowwolf](https://downraindc3d.itch.io/shadowwolf) | 8.99달러 | 2,531 / 4,652 | 10: 대기, 걷기, 달리기, 공격 3, 시전, 어지러움, 피격, 죽음 | 1024² 3장 | 돌진형(네 발 짐승) |
| [TombSpider](https://downraindc3d.itch.io/tombspider) | 7.99달러 | 1,544 / 2,834 | 8: 대기, 걷기, 달리기, 공격 2, 뛰기, 피격, 죽음 | 1024² 3장 | 자폭형, 소환물 |
| [UndeadGuard](https://downraindc3d.itch.io/undeadguard) | 8.99달러 | 2,457 / 4,476 | 6: 대기, 이동, 공격 2, 피격, 죽음 | 1024² 3장 | 근접 변종, 정예 |
| [DarkWarrior](https://downraindc3d.itch.io/darkwarrior) | 7.99달러 | 2,289 / 4,080 | 10: 대기, 걷기, 달리기, 뛰기, 공격 2, 시전, 어지러움, 피격, 죽음 | 1024² 3장 | 갑옷 기사, 정예 |

같은 제작자의 목록에서 이름과 가격만 본 것(내용 미확인): CurseBat·EvilBat·TinyBat(6.99~7.99, 박쥐), ViciousRat·Rat(6.99, 쥐), FallenHound·MadHound·SkeletonHound(7.99~8.99, 개), Bonelurker(8.99), GraveWalker(7.99), SkullLegionary·SkullKnight·BladeSkeleton(8.99~9.99, 해골 변종), UndeadArcher(8.99, 원거리), Necrolyte·TombMage·SkeletonMage·WraithMage(8.99~9.99, 시전자), AshGargoyle·Gargoyle(7.99~8.99), Mossling·EvilStump·VenomBlossom(7.99~8.99, 식물형), AbyssSpider·AbyssWasp·Devilant·Mantis·Scorpion(6.99~8.99, 벌레형), UndeadTroll·GiantZombie·ChasmGolem·MountainTroll(8.99~9.99, 덩치), Undeadknight(11.99), DungeonWarden(9.99), SkeletonDragon·UndeadDragon(9.99), Mimic(11.99). 수치가 위 다섯 종과 비슷하다면 일반 적 굽기에 알맞은 범위다(확인 필요).

이 제작자를 저가 1순위로 꼽는 까닭은 확인한 사실 넷이다. GLB를 주고 고도 가져오기를 스스로 적는다. 종마다 걷기·공격·피격·죽음이 들어 있어 리깅과 클립 이식이 필요 없다. 정점이 1,400~2,500개로 해골(5,375)의 절반 이하다. 낱개로 사서 한 종으로 화풍을 시험할 수 있다. **모르는 것은 생김새다.**

### 2.3 참고(값이 높거나 조건이 맞지 않음)

| 후보 | 가격 | 메모 |
|---|---|---|
| [Downrain DC MS – UndeadSet](https://downraindc3d.itch.io/ms-undeadset) | 39.99달러(약 5만 8천 원) | 6종(UndeadGuard, UndeadWitch, UndeadArcher, Undeadknight, UndeadTroll, UndeadReaper), 무기 분리 가능, GLB. 낱개 합계(약 56달러)보다 싸다. 낱개 한 종으로 화풍을 본 뒤에만 |
| Downrain DC Monster Mega Pack 1~8 | 94.99~139.99달러 | 내용 미확인 |
| Synty POLYGON Dungeon Realms / Dungeons / Dark Fantasy | 99~200달러 [검색] | 라이선스는 엔진 제한이 없다고 명시("not limited by game engine") [페이지: [One Time Purchase Licence](https://syntystore.com/pages/one-time-purchase-licence)]. 그러나 **캐릭터에 클립이 들어 있지 않다**(Dungeon Realms의 Unity 글에 "no animations included") [검색]. 좌석 5개, 원본 파일 팀 밖 공유 금지, 생성 AI 입력·데이터셋 금지, NFT 금지. 화풍은 각진 단색 로우폴리로 알려져 있다 |
| Synty POLYGON Mini Fantasy Characters | 할인 20달러 [검색] | 던전 해골 변종 포함. 미니(짧은 비례)라 1.4절 위험 |
| [Undead Army](https://troglobytes.itch.io/undead-army) | 69.99달러 [검색] | 6종, Mixamo 뼈대 호환. 값이 범위 밖 |
| CGTrader의 구울·늑대 낱개 | 20~70달러 [검색] | 사실풍이 많고 건마다 라이선스가 다르다 |
| Sketchfab의 CC 모델 | 무료 | **이번에 쓸 만한 것을 찾지 못했다.** 검색 결과가 유료 장터 쪽으로 쏠렸고, Sketchfab 검색 페이지는 글로 읽히지 않는다. 사용자가 사이트에서 "Downloadable + Animated + CC0/CC BY" 필터로 직접 보는 편이 빠르다 |

### 2.4 장터·서비스의 라이선스 조건

| 곳 | 다른 엔진(Godot) 사용 | 재배포 | AI 조항 | 그 밖 | 출처 |
|---|---|---|---|---|---|
| Unity Asset Store(표준 EULA) | **된다.** Unity 지원 글이 "다른 엔진에서 쓸 수 있다"고 적는다. EULA의 허가 문구도 Unity 엔진을 지목하지 않는다. 단 "Restricted Assets"와 Unity가 직접 낸 에셋(별도 라이선스)은 제외 | 에셋 자체의 배포·판매 금지, 사용자가 원본 파일을 뽑아 갈 수 있게 하면 안 된다 | 제공자나 Unity의 동의 없이 AI·기계학습 학습·입력에 쓰지 못한다(2.2.1.1(g)) | 파일이 `.unitypackage`라 **Unity 편집기 없이는 FBX를 꺼내기 번거롭다.** 여럿이 돈을 모아 사는 것 금지 | [지원 글](https://support.unity.com/hc/en-us/articles/34387186019988-Can-I-use-assets-from-the-Asset-Store-with-other-engines), [EULA](https://unity.com/legal/as-terms) [페이지] |
| Fab(표준 라이선스) | **된다.** "usage is not limited to Unreal Engine" | 낱개 재판매·무료 재배포 금지 | 읽은 범위에 없다. 판매자가 붙이는 "NoAI" 표시가 있다 [검색] | 옛 UE Marketplace 라이선스가 남은 상품과 Epic 자체 콘텐츠는 따로 본다 | [fab.com/eula](https://www.fab.com/eula) [페이지, 요약본] |
| Synty Store | **된다**(엔진 제한 없음 명시). 공식 지원은 Unity·Unreal만 | 스톡 자산으로 배포 금지, 원본 파일 팀 밖 공유 금지 | 생성 AI의 데이터셋·입력·3D 생성 서비스 업로드 금지 | 좌석 5개 | 위 표 |
| itch.io | 판매자마다 다르다 | 판매자마다 다르다 | 판매자마다 다르다. "No generative AI" 표시는 제작 과정에 관한 표시다 | 후보마다 페이지 문구를 저장해 둔다 | 각 페이지 |
| Mixamo | 엔진 제한 없음 | **원본 캐릭터·동작 파일을 낱개로 배포하면 안 된다.** 게임에 넣어 배포하는 것은 된다. 표기 불필요 | 미확인 | 어도비 계정 필요. 공식 FAQ 페이지는 조회가 막혀(403) 커뮤니티에 옮겨진 문구로만 봤다 [검색]. **공개 저장소에 Mixamo 원본 FBX를 올리면 재배포가 될 수 있다** | [어도비 커뮤니티 글](https://community.adobe.com/t5/mixamo-discussions/mixamo-faq-licensing-royalties-ownership-eula-and-tos/td-p/13234775) |
| Quaternius | 제한 없음 | CC0 묶음은 자유. QAL 묶음(2026년의 새 묶음)은 에셋 자체의 재배포 금지 | 없음 | 묶음마다 CC0인지 QAL인지 다르다 | 위 표 |

공통 주의: "재배포 금지" 조건의 에셋을 Godot로 내보내면 `.pck` 안에 변환된 형태로 들어간다. 게임에 넣어 파는 것은 모든 후보가 허락한다. 다만 원본 GLB·FBX를 **공개 git 저장소에 올리면 재배포가 된다.** 이 저장소가 공개인지에 따라 유료 에셋의 원본을 두는 자리를 정해야 한다(4절).

---

## 3. 대안

### 3.1 지금 모델의 변형으로 늘리기

되는 것(추가 비용 0원)
- 색: 인스턴스 색 또는 재질 색. 새 방식에서는 굽기 추가가 없다.
- 크기: 균등·비균등. 지금 쓰는 방법이다.
- 쓰지 않는 클립 살리기: 해골에 `run`, `idle_alert`, `attack_cross`, `attack_fan`이 이미 있다. 같은 메시로 "달려드는 해골"(run + attack_cross)을 만들면 돌진형이 악마 몸에서 해골 계열로 넘어온다. 새 방식에서는 줄만 더 굽는다.
- 무기·장식 교체: 도끼가 따로 표면이라 지우거나 바꿀 수 있다. CC0 무기(KayKit 부속, Quaternius Modular Weapons)를 손 뼈에 붙인다. 두건·수도복 조각·등짐은 Blender에서 메시를 붙여 가중치를 준다.

한계
- 뼈대와 비례가 같아서 **실루엣이 같다.** 화면에서 50~60px이면 색과 무기 길이, 키 차이 정도만 읽힌다. 변형만으로 "다른 생물"은 안 된다.
- 비균등 크기는 얼굴·손이 찌그러진다. 지금 원거리·돌진이 그 상태다.
- 장식 메시가 붙은 변종은 새 방식에서 변종마다 한 번 더 굽는다(정점 구성이 달라지므로). T2 B-5가 이 비용을 적어 두었다.
- 악마 몸(정점 1,068)은 텍스처 해상도와 형태가 낮아 정예처럼 크게 그리면 거칠다(캡처에서 확인한 것은 일반 크기뿐이다).

현실적인 수: 해골에서 3~4종(도끼, 창·낫, 두건 쓴 시전자, 등짐 운반자), 악마 몸에서 지금의 4종. 여기에 구역별 색을 곱하면 계획의 "구역 변종 6~9"는 채워진다. 새 역할 3종의 실루엣은 부족하다.

### 3.2 Blender로 무료 조각 조합

- 해골 + CC0 부품(무기, 방패, 투구, 두건)은 Blender 5.3 명령줄 스크립트로 된다(가져오기, 뼈에 묶기, 내보내기). 천 조각의 가중치는 손이 든다.
- 클립 없는 인간형(Quaternius Bestiary 7종, Dreamkit) + CC0 클립(Universal Animation Library, KayKit Animations): 뼈 이름 대응표로 회전을 옮겨 굽는 스크립트가 필요하다. 비례가 다르면 발 미끄러짐과 손 뚫림이 남는다. 50~60px에서는 덜 보인다.
- 네 발·거미는 공통 클립 원천이 없다. 클립이 든 모델을 구하는 편이 싸다.

### 3.3 3D 생성 서비스(가격대만. 실행하지 않았다)

근거는 `docs/reviews/3D-GEN-TOOLS-20261117.ko.md`(어제 조사)와 오늘의 검색이다.
- Meshy: 무료 월 100크레딧(텍스처 포함 약 3회, 산출물 CC BY 4.0), Pro 월 약 2만 9천 원(1,000크레딧). 자동 리깅은 두 발 인간형. 네 발 리깅을 한다는 글이 있으나 공식 문서로 **미확인** [검색].
- Tripo: Pro 월 약 20달러 [검색]. 무료 산출물은 상업 사용 불가로 보인다.
- 생성 결과는 정점이 수만~수십만이라 일반 적에는 줄이기가 필수다. 클립은 내장 걷기·달리기뿐이라 공격·피격·죽음을 따로 붙여야 한다.
- 스팀 설문의 "미리 생성한 AI 콘텐츠"에 든다.
- `D2` 6.2절의 2026-11-15 사용자 결정은 "생성 도구는 쓰지 않는다(정예·운반자)", `ART-PLAN`은 "생성 도구는 보스처럼 꼭 필요한 곳에만"이다. 일반 적에는 2.2절의 낱개 구매(종당 약 1만 원, 클립 포함)가 생성보다 싸고 작업이 적다. **생성은 던전 보스 한 체에만 검토할 만하다.**

### 3.4 Mixamo 동작을 다른 모델에 입히기

- 인간형 전용이다. 네 발·거미·박쥐에는 못 쓴다.
- 길 1: 리깅 안 된 인간형 메시를 Mixamo에 올려 자동 리깅(사람이 웹에서 관절 표식을 찍는다. 어도비 계정 필요, 사용자가 직접) → 동작을 골라 FBX로 받기 → Blender에서 클립 이름·길이 맞춰 GLB.
- 길 2: 이미 리깅된 모델에 Mixamo 동작을 리타기팅. Blender 스크립트나 Godot의 인간형 뼈 대응(`SkeletonProfileHumanoid`)으로 한다.
- 좀비 걸음, 피격, 쓰러짐 계열 동작이 있다고 알려져 있다(목록은 이번에 **미확인**).
- 제약: 원본 FBX를 저장소에 올리지 않는다(2.4절). 서비스가 유지보수 상태라는 글이 있다.
- 판단: CC0인 Universal Animation Library나 KayKit Animations로 먼저 해 보고, 모자란 동작만 Mixamo에서 가져온다. 클립이 든 모델을 사면 이 길 전체가 필요 없다.

---

## 4. 권고안

### 안 A — 0원: 변형 + CC0

| 항목 | 내용 |
|---|---|
| 할 일 | ① 해골의 안 쓰는 클립(`run`, `attack_cross`)으로 돌진형을 해골 계열로 옮긴다. ② 해골에 CC0 무기·두건·등짐을 붙여 시전자·운반자 변종을 만든다(부품: KayKit Skeletons 무료 단계의 부속, Quaternius 무기). ③ 구역 변종은 색. ④ 짐승형은 OpenGameArt의 CC0 쥐·박쥐·늑대와 Quaternius Animals를 사용자가 그림을 보고 고른다. ⑤ Mophs의 다른 모델을 구역 우두머리 후보로 본다 |
| 늘어나는 종류 | 해골 변종 3~4, 짐승형 0~3(화풍이 맞는 것이 있을 때), 구역 색 변종 6~9 |
| 작업 | Blender 스크립트(부품 붙이기, 가중치), 변종마다 굽기 1회, 줄 번호 대응 코드. 짐승형은 가져오기·크기 맞추기·재질 정리·굽기 |
| 위험 | 실루엣이 여전히 해골 한 가지에 쏠린다. Quaternius·KayKit 계열은 단색 카툰이라 섞이면 튈 수 있다(그림을 못 봤다). OpenGameArt 후보는 라이선스 페이지를 직접 읽지 못했다. 새 역할 3종의 구분이 약하다 |

### 안 B — 약 1만~6만 원: 클립이 든 낱개 괴물을 골라 산다(권고)

| 항목 | 내용 |
|---|---|
| 1단계(약 1만 원) | 사용자가 Downrain DC 목록의 그림을 보고 **한 종만** 산다. 추천 시험 종은 Shadowwolf(8.99달러, 네 발 짐승이라 지금 없는 실루엣) 또는 Ghoul(7.99달러, 정점 1,413으로 가장 가볍다). 가져와 색을 지금 화면에 맞추고 굽기 시험판에 올려 캡처로 본다 |
| 2단계(통과하면 약 3만~5만 원 추가) | 역할마다 한 종: 자폭형 TombSpider(7.99) 또는 쥐·박쥐(6.99), 강화형·소환형 시전자 한 종(8.99~9.99, 내용 확인 뒤), 구역 우두머리용 덩치 한 종(8.99~9.99), 필요하면 Low Poly Spider Pack(4.99, 거미 10변형). 여섯 종이 다 필요하면 UndeadSet(39.99)과 낱개 합계를 견준다 |
| 늘어나는 종류 | 새 실루엣 4~6종 + 안 A의 변형 |
| 작업 | 종당: GLB 가져오기, 크기·방향·원점 맞추기, 재질을 하나로 합치기(텍스처 3장 구성 → 색 한 장 표준 재질), 색 누르기, 클립 구간 상수, 굽기, 줄 번호 대응. **리깅과 클립 이식은 없다** |
| 위험 | 화풍을 보지 못했다(1단계가 그 확인이다). 라이선스가 짧은 세 문장이라 "게임에 넣어 배포"는 분명하지만 저장소 공개 여부에 따라 원본 보관 자리를 정해야 한다. "악마"로 읽히는 종(Demon, Imp 계열)과 사람 모델(Monk, Priest, MadNun, Witch)은 설정상 피한다. 2048² 6장짜리 종(Ghoul)은 텍스처를 줄여야 한다 |
| 덤 | itch.io는 11월 말 할인 행사를 한다(KevDev 페이지가 오늘 "Black Friday 50%"를 표시했다). Downrain DC가 할인하는지는 **미확인** |

### 안 C — 안 B + 던전 보스 한 체만 따로

| 항목 | 내용 |
|---|---|
| 내용 | 일반·정예·구역 우두머리는 안 B로. 던전 보스만 고유 모델을 구한다: ① 공개·저가 먼저(Downrain DC의 Undeadknight 11.99, DungeonWarden 9.99, SkeletonDragon 9.99, KayKit 골렘 7.95 가운데 그림을 보고) ② 맞는 것이 없으면 생성 한 달(Meshy Pro 약 2만 9천 원, 승인 뒤) |
| 비용 | 안 B + 약 1만~3만 원 |
| 위험 | 생성 쪽은 줄이기·리깅·클립 제작이 들고 스팀 AI 공개 항목에 더해진다. 지금 사슬 악마 우두머리를 그대로 둘 수도 있다 |

권고: **안 A의 ①(해골의 남는 클립 활용)과 ③(색 변종)은 돈과 무관하게 먼저 하고, 새 실루엣은 안 B의 1단계로 한 종을 시험한다.** 무료 후보(Quaternius, KayKit)는 수치와 라이선스가 좋지만 화풍이 멀 가능성이 높고, 클립이 든 저가 낱개는 종당 약 1만 원으로 리깅·클립 작업을 통째로 없앤다. 어느 쪽이든 사용자가 그림을 보는 것이 첫 단계다.

---

## 5. 확인 못 한 것과 사용자가 정할 것

### 5.1 확인 못 한 것

- **모든 후보의 생김새.** 미리보기 그림을 보지 못했다.
- OpenGameArt의 모든 페이지(조회 차단). 지금 쓰는 두 모델의 원 페이지 문구도 오늘 다시 읽지 못했다.
- 해골 무법자의 원출처 기록(`v01/ATTRIBUTION.ko.md`, `SOURCE.json`)이 이 저장소에 없다. 옛 저장소나 `C:/Project/game-research/art-sources/`에 있는지 보지 않았다.
- Quaternius 묶음들의 종 이름, 클립 목록, 종별 정점 수. Bestiary Kit에 클립이 없는지(표시가 모호했다), 원본판 가격.
- KayKit Skeletons의 클립 목록과 정점 수, 실제 비례.
- Downrain DC: 직접 읽은 다섯 종 밖의 내용, 텍스처 3장의 구성(색·노멀·기타인지), GLB 안에 클립이 한 파일로 들어 있는지, 할인 여부.
- AKE Studio 묶음의 파일 형식과 클립 유무, Unity Asset Store 묶음 안에 FBX가 있는지.
- Mixamo 공식 FAQ 원문과 동작 목록, Meshy의 네 발 리깅.
- Sketchfab에서 쓸 만한 CC 모델이 있는지(찾지 못했다는 것이지 없다는 것이 아니다).
- 해골의 `run`·`idle_alert`·`attack_cross`·`attack_fan` 클립의 품질(재생해 보지 않았다).

### 5.2 사용자가 정할 것

| 번호 | 정할 것 | 선택지 | 권고 |
|---|---|---|---|
| E1 | 적의 생김새 범위 | (가) 해골(껍질 마수) 중심으로 변형만 (나) 짐승·벌레형 마수를 더한다 (다) 구울·덩치 같은 인간형 괴물도 더한다 | (나). 설정이 "마수"이고 지금 화면에 짐승형이 없다. narrative-lead 검수를 거친다 |
| E2 | 악마 몸을 일반 적(원거리·돌진)에 계속 쓰는가 | 그대로 / 새 모델로 바꾼다 | 새 실루엣이 들어오는 대로 바꾼다. 악마는 설정상 적이 아니다 |
| E3 | 돈을 쓰는가, 상한은 | 0원 / 1만 원 시험 / 6만 원까지 | 1만 원 시험 뒤 결과를 보고 |
| E4 | 누가 그림을 보고 고르는가 | 사용자가 직접 페이지를 본다 / 사용자가 허락하면 다음 조사에서 브라우저로 미리보기를 캡처해 비교표를 만든다 | 후자가 빠르다. 그래도 최종 선택은 사용자 |
| E5 | 구매와 내려받기 | 계정·결제·약관 동의는 사용자가 직접 한다 | — |
| E6 | 유료 에셋 원본을 어디에 두는가 | 저장소(비공개일 때만) / 저장소 밖에 두고 가져온 결과만 | 저장소 공개 여부에 달렸다. 공개면 원본을 올리지 않는다. Mixamo 원본도 같다 |
| E7 | 출처 표시 화면 | 지금도 사슬 악마(CC BY 3.0)와 주인공(CC BY-SA 3.0) 때문에 필요하다 | 크레딧 화면 항목을 출시 지시서(T4)에 넣는다. CC0·무표기 유료 에셋은 넣지 않아도 되지만 적어 두면 분쟁 때 근거가 된다 |
| E8 | 해골 출처 기록 복구 | 옛 저장소에서 `v01` 기록을 옮겨 온다 / 원 페이지를 다시 확인해 새로 적는다 | 둘 다. 페이지 저장본을 `_local/`에 남긴다 |
| E9 | 던전 보스 | 지금 사슬 악마 유지 / 저가 낱개 / 생성 | 일반 적을 먼저 하고 뒤에 정한다 |

### 5.3 다음 한 걸음(제안)

1. 사용자가 다음 세 곳의 그림을 본다: [Downrain DC 목록](https://downraindc3d.itch.io/), [Quaternius Ultimate Monsters](https://quaternius.com/packs/ultimatemonsters.html), [KayKit Skeletons](https://kaylousberg.itch.io/kaykit-skeletons). 지금 화면(`_local/shots/bb-on/09-playing-2400.png`)과 나란히 놓고 "섞어도 되는가"만 본다.
2. E1·E3을 정한다.
3. 정해지면 environment-artist가 시험 한 종을 가져와 굽기 시험판에서 캡처한다(굽기 시험판 `walker`의 판정이 먼저 나와야 한다).

## 6. 본 것

저장소: `CLAUDE.md`, `docs/SYSTEMS-DESIGN.ko.md`(적·드랍 줄), `docs/DIRECTOR-PLAN.ko.md`(F4 줄), `docs/SEASON1_WORLD_STORY_MASTER.md` 2~4절, `docs/story/WORLD-BIBLE.ko.md`(껍질 마수 줄), `docs/story/CHAPTER1-TEXT-PLAN.ko.md`(적 이름 줄), `docs/ART-PLAN.ko.md` 3.2절, `docs/specs/D2-elite-carrier-spec.ko.md` 6.2절, `docs/specs/T2-perf-directives-20261118b.ko.md` 0.2절·B절, `docs/reviews/3D-GEN-TOOLS-20261117.ko.md`, `chapter1/data/combat_tuning.json`, `chapter1/view/actors/chapter_actors.gd`(검색으로 해당 줄), `chapter1/art/` 아래 ATTRIBUTION 세 개와 `actors/*.json`, 두 GLB의 JSON 머리, 캡처 한 장.

실행하지 않은 것: 게임, Blender, 굽기 도구, 어떤 내려받기·구매·생성도.
