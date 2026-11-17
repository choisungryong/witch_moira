# A4 — 화면 전면 재디자인 지시서

2026-11-17 밤, art-lead. 총괄 디렉터 배정. 문서만 썼다. 게임 코드·데이터를 고치지 않았고, Godot를 실행하지 않았고, 그림을 생성하지 않았다.

기획자 지시(원문): "게임 화면의 디자인 개선이 많이 필요해 보여. 메인 메뉴부터 캐릭터 선택 화면, 스킬 트리 화면, HUD 전반적으로 게임 디자인 전문 에이전트가 다시 디자인하고 반영해 주었으면 좋겠어."

이 문서는 A2(`docs/specs/A2-hud-visual-direction.ko.md`)를 손질한 것이 아니다. A2의 진단과 쓸 만한 결정을 이어받아 화면 전체를 다시 설계한다. A2에서 무엇을 잇고 무엇을 버리는지는 2절 표에 있다. A2의 방향은 결정 기록에서 "채택"(`DECISIONS-PENDING-20261117` 2절 A4)이므로, 이 문서의 권고안을 고르면 그 결정을 바꾸는 것이 된다(9절 U-A1).

## 디렉터용 요약

1. **진단 한 줄.** 원화는 화려한 반실사 회화인데 화면은 "평평한 어두운 상자 + 황동 1px 선 + Windows 글꼴"이다. 원화가 작은 액자 하나에 갇혀 있고(메뉴), 나머지 화면에는 사람이 없다. 화면이 원화의 화려함을 받지 못하는 이유는 장식이 모자라서가 아니라 **원화가 화면의 주인공이 아니고, 틀이 무엇으로 만든 물건인지 말하지 않기 때문**이다.
2. **세 안.** (가) **성유물함** — 검게 그을린 은과 바랜 금의 세공 틀, 연기 낀 유리, 원화는 틀 없이 크게. (나) **장정과 실** — A2의 그을린 가죽·황동 모서리·바느질을 다듬은 안. (다) **화보** — 거의 검은 바탕에 머리카락 굵기의 금선, 큰 여백과 큰 원화, 서브컬처 수집형 게임의 캐릭터 화면 관습.
3. **권고는 (가) 성유물함.** 디렉터 의견(원화를 주인공으로, 틀은 물건의 재질, 전투 중 표시는 얇고 조용하되 구슬과 스킬 칸만 "만든 물건")과 대부분 같다. 다르게 본 것 둘: 재질은 **금속과 유리 둘로 줄이고** 가죽은 판의 어두운 채움 색으로만 쓴다(재질이 셋이면 화면마다 섞여 한 벌로 읽히지 않는다). 전투 줄의 **판 자체는 거의 지운다**(어두운 그러데이션 + 가는 금속 레일). 물건으로 보일 것은 구슬 둘과 스킬 칸 여섯뿐이다(1·3절).
4. **목업 12장**(세 안 × 메뉴·캐릭터 선택·전투·스킬 트리), Codex CLI 그림 생성, 영문 프롬프트는 5절. 추가 비용은 없고(구독 안의 사용량) 한 장 1~3분이다. 사용자는 이 12장을 보고 방향을 고른다.
5. **새 화면**: 타이틀·메인 메뉴(이어 하기·새 게임·의상·설정·제작진·종료), **캐릭터 선택**(세 마녀를 원화로 크게, 영구 레벨·시작 기술·스킬 트리·장비·의상), 설정, 그리고 착용 창·저장 거부 안내의 틀(6절).
6. **구현은 열 단위**를 ui-hud가 차례로 한다(8절). 지금 바로 할 수 있는 것은 게임 코드를 건드리지 않는 재질 키트 제작(U0)과 목업뿐이다. 지금 도는 D4-U·D5-U와 곧 시작할 D6-A2에는 "새 재질을 나중에 입을 수 있게" 지킬 규칙 다섯을 붙인다(8.2절). 그 핵심은 **틀을 직접 만들지 말고 한 곳(`ui_style.gd`)에서 받기**다.
7. **성능.** 전투 중 표시는 프레임 시간이 크게 미달인 지금(p95 40~56ms) 비용을 늘리면 안 된다. 전투 줄은 노드를 늘리지 않고 `_draw()` 한 번에 그리며, 셰이더·화면 읽기·실행 중 흐림을 쓰지 않는다. 움직임은 판이 멈춘 화면(메뉴·창)에서만 돈다(7.4절).
8. **사용자 결정 9건**(9절). 가장 먼저: 방향 고르기(목업 뒤), 글꼴 내려받기 승인, 메인 메뉴 배경(기존 원화 셋 vs 세 사람이 함께 있는 새 그림), "새 게임"의 뜻.

---

## 0. 근거로 본 것과 단위

### 0.1 직접 열어 본 캡처와 그림

| 무엇 | 파일 |
|---|---|
| 메뉴 | `_local/shots/round2-20261117/frost-1080/01-menu.png`, `frost-720/01-menu.png`, `_local/shots/ui-g1p4/tree-1080-l8/02-menu-frost.png`(영구 성장 요약과 스킬 트리 단추가 있는 메뉴) |
| 보관함·장비창 | `round2-20261117/frost-1080/02-stash.png`, `06-inventory.png` |
| 전투 | `round2-20261117/frost-1080/03-playing-120.png`, `08-upgrade-prompt.png`, `11-playing-16000.png`, `frost-720/09-playing-2400.png` |
| 은총 | `round2-20261117/frost-1080/05-choice-2.png`(이번에는 카드가 그려져 있다. A2 때는 못 봤다) |
| 정지·결과 | `round2-20261117/frost-1080/07-paused.png`, `13-end-victory-result.png` |
| 스킬 트리 | `_local/shots/ui-g1p4/tree-1080-l8/04-tree-staged.png`, `tree-720-l8/03-tree-open.png` |
| 원화 | `chapter1/art/characters/frost_witch_v02.png`, `storm_witch_v02.png`(원본). 화염은 메뉴 캡처 안의 축소본만 봤다 |

**보지 않은 것**: `round2-20261117`의 화염·번개 벌 전부, 냉기의 04·09(1080)·10·12, 우두머리 체력바가 있는 장면, 생명 30% 아래 장면, `ui-a2d1` 스킬 트리, 착용 창(아직 없다), 저장 거부 안내(아직 없다), 설정 화면(없다). 움직임과 소리는 정지 화면으로 판단할 수 없어 보지 않았다.

### 0.2 문서

A2 전체, `QUALITY-TARGETS.ko.md` 2·3·5절, `T3-localization-directives-20261117.ko.md` 요약·1.5~1.6·2.6~2.8·3절 L2~L5·4절, `D6-loot-farming-spec.ko.md` 7절과 10절 A2 행, `D4-run-flow-spec.ko.md` D4-U, `D5-save-safety-spec.ko.md` D5-U, `A3-equipment-icon-direction.ko.md` 1.3절과 14절(의상), `docs/story/WORDING-RULES.ko.md` 1~6절, `DECISIONS-PENDING-20261117.ko.md` 2절과 L4·L5·R3·R4·G5·T3 행, `DIRECTOR-PLAN.ko.md` 2.8절의 11-17 기록, `T2-perf-directives-20261117.ko.md`(HUD 0.78ms 행), `AGENTS.md`, `.claude/agents/codex-operator.md`.

코드: `chapter1/view/hud/palette.gd`(전체), `combat_bar.gd` 1~60행(크기 상수), `chapter_hud.gd`의 함수 위치(Grep), `chapter1/view/loc.gd`의 함수 목록, `chapter1/i18n/README.ko.md`, `tools/art/make_equipment_icons.py`의 배경 떼기 방식.

### 0.3 단위

A2 0절과 같다. 크기·여백·글자는 **코드 단위**(기준 창 1600×900). 1080p에서 ×1.2, 720p에서 ×0.8. 코드 14가 720p에서 11.2px이고 이것이 하한이다. 캡처 위의 위치는 그 캡처의 픽셀 좌표 (x, y)이고 해상도를 적지 않으면 1920×1080이다.

- 전투 화면 가운데 60%: 코드 x 320~1280, y 180~720. 1080p (384~1536, 216~864), 720p (256~1024, 144~576).
- 이 가림 기준은 **판이 돌고 있는 전투 화면**에만 건다(QUALITY-TARGETS 3절). 판을 멈추는 창(은총, 정지, 착용 창, 결과)은 가운데를 써도 된다.
- 스팀 덱(1280×800): 지금 설정(`stretch/mode="canvas_items"`, 비율 유지)이면 1280×720으로 그려지고 위아래에 40px 띠가 생긴다. T4가 비율 넓히기(`aspect=expand`)를 검토 중이므로, 모든 화면은 **앵커로 붙이고 절대 좌표에 기대지 않는다**(7.3절).

---

## 1. 진단 — 지금 화면이 원화를 받지 못하는 이유

A2 1절의 공통 원인 다섯(C1 시스템 글꼴, C2 같은 평평한 사각형, C3 Godot 기본 위젯, C4 빈 판, C5 움직임 없음)은 지금도 그대로다. A2 지시서 1(색·글꼴 토큰, 읽기 하한, 알림 자리)은 반영됐다(`08-upgrade-prompt.png`의 장비 알림이 (1490~1890, 875~1055)로 가운데 60% 밖에 있다. 영혼 구슬 아래 레벨 명판이 있다). 그 위에 이번에 본 것:

| # | 화면 | 본 것(위치) | 무엇이 문제인가 |
|---|---|---|---|
| D1 | 메뉴 | 원화가 (182~518, 242~745)의 액자 안. 화면 넓이의 약 9%. 나머지 큰 상자는 기술 이름 단추 셋과 설정 줄 | 원화가 가장 강한 재료인데 화면의 장식 하나로 쓰인다. 사람을 고르는 화면이 아니라 기술을 고르는 양식(form)이다 |
| D2 | 메뉴 | `ui-g1p4/tree-1080-l8/02-menu-frost.png`: 왼쪽은 서리 마녀(초상·"서리의 마녀 Lv 8"), 초점 테두리는 잿불탄 줄 (574~1752, 337~441) | **고른 마녀와 키보드 초점이 다른 줄을 가리킨다.** 무엇이 선택됐는지 화면이 두 가지로 말한다. 새 캐릭터 선택에서는 "보이는 마녀 = 시작할 마녀" 하나만 있게 한다 |
| D3 | 메뉴 | 뒤의 월드 글자 "…하면 열립니다"(1780~1880, 900)와 관문 막대가 메뉴 바깥으로 보인다 | 게임 밖 화면에 판 안의 물건이 비친다. 메뉴 뒤는 그림으로 채운다 |
| D4 | 메뉴·정지 | 휴대폰식 토글 (1497~1533, 757), (1396~1432, 649) | A2 C3 그대로 |
| D5 | 전투 | 목표 띠 (480~1440, 96~148): 화면 폭 절반의 검은 막대 | 위쪽 가운데에 가장 무거운 검은 덩어리가 있다. 글은 필요하지만 상자는 필요 없다 |
| D6 | 전투 | 생명 구슬 (450~597, 912~1058)과 판 (668~1252, 925~1048) 사이 70px 빈틈, 구슬 테 바깥의 짧은 눈금 | A2 1.2절 그대로. 구슬·판·구슬이 세 개의 따로 놓인 부품이다 |
| D7 | 전투 | 필살기 칸 (960~1048, 942~1030)의 흐린 마름모 | 뜻 없는 자리 표시 |
| D8 | 전투 720p | `frost-720/09`: "Space", "Q"(705~760, 683~697)와 경로 판의 둘째 줄 (985~1140, 93) | 약 10px. 하한(11.2px) 아래로 보인다. 코드 값은 A2 지시서 1에서 14로 올렸다는데 화면에서는 작다. 글꼴 교체(7.2절) 뒤 다시 잰다 |
| D9 | 은총 | 세 카드 단추가 모두 "서약 선택", 화염 카드 (1242~1668, 812~868) 포함. 카드 아래 절반이 비어 있다 (746~1172, 650~800) | 다른 계열은 서약이 아니라 거래(U16, 결정 T3 "받아들이기 / 거래하기"). 카드 셋이 같은 상자라 어머니의 도움과 악마의 거래가 갈리지 않는다 |
| D10 | 장비창·보관함 | 상세 칸 아래 빈 판 (557~1751, 560~797), 회색 "장착 중", 기본 선택 상자 화살표 (133~767, 245~293) | 장비를 고르는 화면에 마녀가 없다. D6 7절의 착용 창으로 대체된다 |
| D11 | 정지 | 창 아래 40% 빈 판 (457~1463, 670~800) | A2 1.5절 그대로 |
| D12 | 결과 | 글자 영수증. 오른쪽 3분의 2 아래가 빈 판 (687~1680, 560~800). 제목 "회랑의 서약을 완수했습니다"(서약 낱말 오용, WORDING-RULES 3.1절) | 한 판이 어땠는지 그림이 없다 |
| D13 | 스킬 트리 | 초상 98×98 (48~145, 33~128). "+1" 칸이 노란 채움 (870~912, 207~232)으로 초점 테두리(밝은 황동) 바로 옆. 오른쪽 설명 칸 아래 빈 곳 (1390~1860, 500~760) | 구조와 상태 표시는 좋다(A2 1.7절). 금색이 두 뜻(선택, 영구 성장)으로 붙어 있어 초점이 어디인지 순간 헷갈린다 |
| D14 | 스킬 트리 720p | 아래 안내 줄 (362~920, 683~696), 칸 안 "투자 가능" | 약 10~11px. 하한에 붙어 있다 |

**원화를 다시 봤다.** 세 장 모두 세로 2:3, 전신, 고딕 폐허 배경, 계열 강조색 하나(화염 주황, 냉기 청록, 번개 보라)의 림 조명, 은·금 세공 장신구, 비치는 긴 자락. 번개는 낮은 카메라에 다리를 넓게 벌린 자세다. 이 원화에서 화면이 가져올 것은 셋이다: **은·금 세공의 질감**, **계열색 하나만 빛나는 조명 규칙**, **인물의 크기**. 화면 틀의 재질을 원화의 장신구와 같은 금속으로 하면 그림과 틀이 한 세계의 물건이 된다. 이것이 권고안 (가)의 근거다.

---

## 2. A2에서 잇는 것과 버리는 것

| A2 절 | 내용 | 판정 | 이유 |
|---|---|---|---|
| 0절 | 코드 단위, 가운데 60% 좌표, 720p 하한 14 | **잇는다** | 측정 규칙이다 |
| 1절 | 진단 C1~C5 | **잇는다** | 지금도 맞다(1절) |
| 2.1 판 | 그을린 가죽 9분할이 모든 창의 주재질 | **버린다** → 금속 테 + 어두운 채움 | 원화의 장신구가 은·금 세공이라 가죽은 그림과 한 벌로 읽히지 않는다. 가죽 색은 판의 채움 색으로만 남긴다 |
| 2.1 모서리 | ㄱ자 황동 모서리 쇠와 리벳 | **바꾼다** → 뚫새김 세공 모서리 | 리벳은 상자·궤짝의 말이다. 원화의 세공과 맞는 것은 고딕 창살 무늬를 뚫어 새긴 모서리다 |
| 2.1 단추·선택 | 단추는 모서리 쇠 없음, 선택은 `BRASS_HI`만 | **잇는다** | |
| 2.1 구분선 | 바느질 땀 | **조건부** → (가)에서는 가는 금속선 + 가운데 작은 장식, 바느질은 은총의 어머니 카드에만 | 재질을 한 벌로 줄이기 위해서 |
| 2.1 배경 막 | 따뜻한 검정 + 비네트 | **잇는다** | |
| 2.2 글꼴 위계 | H1~숫자 6층, 14 미만 금지 | **잇는다**, 크기를 조금 고침(7.2절) | |
| 2.3 색 토큰 | `palette.gd`(이미 반영) | **잇는다**. 새 토큰 둘(`METAL_SILVER`, `GLASS`)만 더함(7.1절) | 한 색에 한 뜻 |
| 2.4 모티프 | 이야기에서 온 것만, 화면마다 하나 | **잇는다**. 단 타이틀의 "셋으로 갈라지는 실"은 버린다 | `WORDING-RULES` 1.2절 4번이 "운명의 실"을 모이라이 신화를 바로 가리키는 상투로 막는다. 그림으로서의 실 한 가닥·매듭은 허용되지만 첫 화면에 크게 걸면 그 상투가 된다. 실은 은총(어머니와 이어짐)과 결과(한 판의 길이)에만 둔다 |
| 2.5 움직임 | 창 0.18초, 초점 0.10초, 구슬 출렁임 | **잇는다**, 범위를 판이 멈춘 화면으로 좁힘(7.4절) | 성능 |
| 3.1 타이틀 세 폭 | 세 폭 카드 + 허리 위 그림 + 실 | **버린다** → 메인 메뉴(4.1)와 캐릭터 선택(4.2)으로 나눔 | 사용자가 캐릭터 선택 화면을 따로 원했다. 세 폭 카드는 다시 원화를 액자에 가둔다 |
| 3.2 은총 | 어머니 카드(둥근·바느질·실) 대 거래 카드(각진·이중선·봉랍) | **잇는다**. 글은 결정 T3대로("후원자"·"본래의"를 쓰지 않음) | 이야기의 핵심 대비다 |
| 3.3 결과 | 한 판의 실, 매듭, 해진 끝 | **잇는다** | |
| 3.4 스킬 트리 | 구조·상태 규칙 유지, 바깥 틀·연결선만 바꿈 | **잇는다** + 초상과 금색 충돌 고침(4.3절) | |
| 3.5 전투 | A 배치와 크기, 레벨 명판, 우두머리 바, 알림 자리, 회피 숫자 | **잇는다** | A 배치는 확정이다 |
| 3.5 황동 팔 | 구슬과 판을 잇는 굵기 3의 팔 두 줄 | **바꾼다** → 판 뒤를 지나는 금속 레일 하나 | 판을 거의 지우기 때문(3절) |
| 4절 지시서 1 | 토큰·하한·가림 | **끝남**(반영) | |
| 4절 지시서 2-A | 재질 키트를 전부 코드(Pillow)로 절차 생성 | **바꾼다** → 장식 조각은 Codex 생성, 곧은 변·채움·초점 표시는 코드 | 뚫새김 세공은 절차 생성으로 원화 수준이 나오지 않는다. 반대로 9분할의 곧은 변은 생성 그림으로는 이음매가 맞지 않는다(7.5절) |
| 4절 지시서 2-B·3·4·5 | 적용, 타이틀, 은총, 결과 | **이 문서 8절의 U1~U9로 대체** | |
| 5절 | 본래 냉기 악마 시험 원화 평가 | 이 문서 범위 밖 | 이후 결정(A1)으로 지나갔다 |

---

## 3. 시각 방향 세 안

공통 전제: 고딕 다크 판타지, 원화는 반실사 회화풍의 화려한 성인 여성 마녀. 주문 효과가 화면에서 가장 밝아야 하므로 **표시는 빛나지 않는다**(A2 2.1). 색은 `palette.gd`의 한 색 한 뜻.

### (가) 성유물함 — 권고

**한 줄**: 화면 표시는 수도원 제단에 남은 **성유물함**이다. 검게 그을린 은과 바랜 금으로 짠 가는 틀, 그 안의 연기 낀 유리. 마녀는 틀 밖에 크게 선다.

| 성격 | 내용 |
|---|---|
| 재질 | **금속 둘**: 그을린 은(`METAL_SILVER` 새 토큰, 회청 `8e949a` 부근)과 바랜 금(`BRASS` `aa8d58`). **유리**: 구슬과 스킬 칸의 앞면, 연기 낀 검정(`GLASS`, `0e1316` 75%). 판의 채움은 거의 검은 따뜻한 회색(`SURFACE`)에 아주 고운 질감 |
| 틀 | 가는 테(코드 2, 안쪽 1px 그늘) + **모서리에만 몰린 뚫새김 장식**(고딕 창살 무늬, 코드 28~40). 변은 비어 있다. 큰 창만 장식 모서리, 단추·목록 칸은 테만 |
| 글꼴 | 제목은 획 대비가 큰 명조(새김 글자 느낌), 본문은 깨끗한 고딕 |
| 색 | 바탕 무채. 금은 틀, 밝은 금(`BRASS_HI`)은 선택만. 계열색은 보석 한 점(칸의 문장, 이름 글자, 봉랍) |
| 움직임 | 창이 열릴 때 테가 위에서 아래로 0.18초 그려지고 내용이 뒤따라 뜬다. 초점은 밝은 금 모서리 괄호가 0.10초 미끄러진다. 구슬 액체는 수면이 출렁인다(전투에서는 비용 기준 안에서만, 7.4절) |
| 장르 관습 | 아이소메트릭 액션 RPG의 "아래 양쪽 구슬 + 가운데 기술 줄", 고딕 액션 RPG의 금속 세공 틀. 이 장르 사용자가 바로 읽는 문법이다 |
| 이야기·원화와 맞는 이유 | 원화의 장신구(은 세공 뷔스티에, 사슬, 금 체인)와 같은 금속이라 그림과 틀이 한 세계의 물건이 된다. 무대가 수도원이고, 성유물함은 수도원에 실제로 있는 물건이다. 구슬을 "성유물을 담는 유리 용기"로 보는 A2의 생각을 그대로 잇는다. 원화는 틀 밖에서 크게 서므로 화려함이 줄지 않는다 |
| 위험 | ① 장식이 늘면 이 장르의 흔한 금박 화면이 된다 → 장식은 큰 창 모서리 넷과 구슬·스킬 칸에만, 변은 비운다. ② 이 장르의 대표작 구슬 장식(구슬을 받치는 조각상 등)을 닮을 수 있다 → 구슬 틀은 "창살 네 개로 감싼 유리 용기"로 정하고 인물·짐승 조각을 쓰지 않는다. ③ 금속 장식 조각을 생성하면 화풍이 원화보다 매끈한 CG로 갈 수 있다 → 원화를 참조로 붙이고 검수 시트를 원화 옆에 놓는다(7.5절) |

### (나) 장정과 실

**한 줄**: A2의 방향을 다듬은 안. 화면 표시는 수도원 서고에 남은 **기도서의 장정**이다. 그을린 검은 가죽, 눌러 찍은 테두리, 닳은 황동 모서리 쇠, 그리고 표백하지 않은 아마실 한 가닥.

| 성격 | 내용 |
|---|---|
| 재질 | 검은 가죽(밝기 차 2~3%의 질감), 황동 모서리 쇠, 아마실, 작은 이름표에만 양피지 |
| 틀 | 가장자리 6px 안쪽에 눌러 찍은 선, ㄱ자 모서리 쇠와 리벳(큰 창), 구분선은 바느질 땀 |
| 글꼴 | 책 본문 같은 부드러운 명조 + 고딕 |
| 색 | 따뜻한 갈색 쪽 무채. 실은 `LINEN` |
| 움직임 | 실이 그려지고 매듭이 묶인다(0.25~0.8초) |
| 장르 관습 | 어두운 판타지 전략·로그라이크의 "낡은 책·서류" 화면 |
| 이야기·원화와 맞는 이유 | 실과 매듭이 이름(모이라)의 뿌리와 서약·거래의 대비를 화면마다 말해 준다. 조용해서 효과를 가리지 않는다 |
| 위험 | ① **원화와 재질이 맞지 않는다.** 원화는 은·금 세공과 비치는 천의 화려한 그림인데 화면은 갈색 가죽이라, 그림만 혼자 빛나고 화면은 여전히 수수하다. 사용자가 지적한 "디자인 개선이 많이 필요"를 덜 푼다. ② 실을 화면마다 쓰면 `WORDING-RULES` 1.2절 4번의 상투(운명의 실)가 그림으로 반복된다. ③ 갈색 가죽 판은 어두운 판타지 전략 장르의 기존 화면들과 가장 많이 겹친다 |

### (다) 화보

**한 줄**: 화면은 마녀의 **화보집**이다. 거의 검은 윤기 있는 바탕, 머리카락 굵기의 샴페인 금선, 큰 여백, 비스듬히 자른 판, 크게 오려 낸 인물.

| 성격 | 내용 |
|---|---|
| 재질 | 재질이 거의 없다. 검은 유리 같은 면, 1px 금선, 아주 옅은 빛줄기 |
| 틀 | 틀 대신 여백과 비스듬한 선. 큰 제목 글자가 틀 노릇을 한다 |
| 글꼴 | 가늘고 큰 명조 제목, 자간을 넓힌 작은 대문자 이름표 |
| 색 | 검정과 샴페인 금. 계열색은 인물 조명에서만 |
| 움직임 | 인물이 옆에서 미끄러져 들어오고 빛줄기가 지나간다. 화면 전환이 크다 |
| 장르 관습 | 서브컬처 수집형 RPG의 캐릭터 선택·의상 화면 |
| 이야기·원화와 맞는 이유 | 원화와 의상 컬렉션(수영복 등, 사용자 결정)을 가장 돋보이게 한다. 인물이 곧 상품인 화면에 강하다 |
| 위험 | ① **고딕 다크 판타지와 어긋난다.** 수도원·서약·악마의 세계가 휴대폰 게임 상점처럼 읽힌다. ② 전투 화면에 옮기면 표시가 너무 가늘어 효과 속에서 사라진다(전투에는 맞지 않음). ③ 이야기 모티프(서약과 거래, 한 판의 실)를 담을 자리가 없다 |

**버린 후보**: 스테인드글라스와 납선(고딕 창의 색유리). 고딕 성당과 가장 가깝지만, 색유리가 계열색·등급색과 같은 자리를 다투어 한 색 한 뜻이 무너지고, 빛나는 유리는 주문 효과와 밝기를 다툰다.

### 권고: (가) 성유물함, 다른 두 안에서 빌릴 것

- (다)에서 **배치**를 빌린다: 메뉴·캐릭터 선택·의상에서 원화를 틀 없이 화면 끝까지 크게(4.1~4.2절). 비스듬한 판과 큰 화면 전환은 빌리지 않는다.
- (나)에서 **이야기 모티프**를 빌린다: 은총의 실과 봉랍, 결과의 한 판의 실(4.5·4.7절). 화면 전체의 재질로는 쓰지 않는다.
- 디렉터 의견과 다른 점 둘(요약 3번): 재질을 금속·유리 둘로, 전투 줄의 판을 거의 지움.

---

## 4. 화면별 배치 설계 — 권고안 (가) 기준

모든 크기는 코드 단위(1600×900). 화면마다 **영역 / 위계 / 초점 이동 / 720p / 번역 여유**를 적는다. 초점·패드 공통 규칙은 7.3절.

### 4.1 타이틀·메인 메뉴 (새로 만든다)

지금은 없다. 지금의 메뉴는 4.2의 캐릭터 선택으로 바뀐다.

```
x 0                    560                                               1600
┌───────────────────────┬──────────────────────────────────────────────────┐ y 0
│                       │  [화염]        [냉기]        [번개]              │
│  Witch Moira  (로고)   │  원화 세 장을 세로 띠로 나란히(머리~무릎).       │
│  제1장 · {장 이름}      │  띠 폭 각 347, 사이 0, 띠 경계와 왼쪽은           │
│                       │  어둠으로 사라짐. 틀 없음                         │
│  ▸ 이어 하기  ◆        │                                                  │
│    새 게임             │  (처음 실행이 아니면: 마지막으로 플레이한 마녀의  │
│    의상                │   띠를 밝기 1.0, 나머지 둘 0.55)                  │
│    설정                │                                                  │
│    제작진              │                                                  │
│    게임 종료           │                                                  │
│                       │                                                  │
│ v0.x · 저장 준비됨      │                        Enter 고르기 · Esc 종료   │
└───────────────────────┴──────────────────────────────────────────────────┘ y 900
```

| 영역 | 좌표(x, y, 폭×높이) | 내용 |
|---|---|---|
| 배경 | 0, 0, 1600×900 | 왼쪽 35%는 `SURFACE`에서 투명으로 가는 그러데이션, 오른쪽은 원화 띠 셋. 원화 띠는 원화를 0.62배(높이 952)로 놓고 각 띠 폭 347만 잘라 보인다. 얼굴이 y 90~200에 오게 위로 맞춘다. 비네트 |
| 로고 | 72, 110, 440×110 | "Witch Moira" 워드마크(그림 파일, 9절 U-A5). 그 아래 장 이름 한 줄(본문 18, `INK_DIM`) |
| 메뉴 목록 | 72, 330, 360×(52×6) | 한 줄 52. 글 H3 22. 왼쪽 정렬. 초점 줄은 밝은 금 모서리 괄호 + 왼쪽 작은 장식 + 글 `INK`, 나머지 `INK_DIM`. 판·상자 없음 |
| 아래 왼쪽 | 72, 846 | 판 번호, 저장 상태(보조 14) |
| 아래 오른쪽 | 오른쪽 끝 −48, 846 | 키 안내(보조 14, 입력 장치에 맞는 표기, 7.3절) |

- **위계**: 원화 셋 → 로고 → 초점 줄 → 나머지 줄 → 아래 줄.
- **항목**: 저장이 있으면 "이어 하기"가 맨 위이고 기본 초점이다. 저장이 없으면 "시작"(새 게임 줄 자리) 하나. "새 게임"의 뜻은 9절 U-A4(정해질 때까지 자리만 두고 숨긴다). "의상"은 캐릭터 선택을 의상 칸이 열린 상태로 연다. "제작진"은 글꼴·에셋 라이선스 고지(T3 2.6, T4)를 겸한다. "게임 종료"는 D4-U의 종료 흐름을 그대로 쓴다.
- **초점**: ↑/↓(패드 십자·왼쪽 막대)로 줄 이동, 끝에서 감기 없음. Enter/A 들어가기, Esc/B는 "게임 종료" 줄로 초점을 옮긴다(바로 끄지 않는다).
- **판 안 표시 숨김**: 메뉴·캐릭터 선택·설정에서 월드와 HUD를 그리지 않거나 원화 배경으로 완전히 덮는다(D3). 덮는 쪽이 싸다. 월드 3D를 메뉴 뒤에서 계속 그리면 프레임 비용이 남는다.
- **720p**: 메뉴 글 22 → 17.6px, 아래 줄 14 → 11.2px.
- **번역**: 목록 폭 360은 한국어 최장 "이어 하기"(5자)의 약 4배. 독일어 "Fortsetzen"·"Einstellungen" 길이를 넉넉히 받는다. 줄은 한 줄 고정, 넘치면 말줄임 + 툴팁(T3 2.7). 로고는 번역하지 않는다(그림). 장 이름은 키(`menu.chapter_line`, 자리 표시자 `{chapter}`)로 두어 장 이름이 바뀌어도 화면을 고치지 않는다.

### 4.2 캐릭터 선택 (새로 만든다)

세 마녀 가운데 한 사람을 크게 보고 고르는 화면. 지금 메뉴의 시작 기술 단추 셋이 맡던 일(어느 기술로 시작하는가)을 여기서 한다. **마녀 = 시작 기술**이다(화염 마녀 = 잿불탄, 냉기 = 서리창, 번개 = 연쇄 전류). 시작 콜백은 지금 것(기술 id 클로저)을 그대로 쓴다.

```
x 0                  520                                                 1600
┌──────────────────────┬────────────────────────────────────────────────────┐ y 0
│ ‹ 뒤로 Esc             │                                         설정 ⚙     │ 24
│ (◯화염)(◉냉기)(◯번개)   │                  ┌──────────────┐                  │ 72~184 메달 3개
│  LB/RB · Q/E 바꾸기     │      흐리게 늘린  │              │                  │
│                      │      원화 배경     │   원화        │                  │
│ 서리의 마녀  (H1 40)    │                  │  (머리~무릎)   │                  │ 206
│ Lv 8  ━━━━━━░░ 4,000/4,500                │   틀 없음     │                  │ 262
│ ◇ 남은 포인트 2         │                  │              │                  │
│ ───────── 장식선        │                  │              │                  │
│ [❄] 시작 기술  서리창    │                  │              │                  │ 330
│     관통 2 · 감속 20%   │                  │              │                  │
│ ─────────             │                  │              │                  │
│ ▸ 스킬 트리      ◆2     │                  │              │                  │ 450
│   장비                 │                  │              │  ┌─의상 칸(열면)─┐ │
│   의상           2/4    │                  │              │  │[■][■][▒][▒]  │ │ 690~870
│                      │                  └──────────────┘  └──────────────┘ │
│ [      시  작      ]   │                                                    │ 740~800
│ Enter 시작 · Esc 뒤로 · LB/RB 마녀                                          │ 850
└──────────────────────┴────────────────────────────────────────────────────┘ y 900
```

| 영역 | 좌표 | 내용 |
|---|---|---|
| 원화 | 원화를 0.75배(768×1152)로, 가운데 x 1060, 위 끝 y −24. 머리~무릎이 보인다 | 틀 없음. 왼쪽 가장자리는 x 560~720에서 왼쪽 판의 그러데이션으로 사라진다. 원화 바깥(오른쪽 끝, 아래)은 같은 원화를 크게 늘려 흐리게 한 **미리 만든 배경 그림**(실행 중 흐림 아님, 7.4절)과 비네트 |
| 마녀 메달 | 64, 72부터 96×96 셋, 간격 16 | `face_512`를 원으로 자른 것 + 금속 고리(K11). 고른 마녀는 밝은 금 괄호와 밝기 1.0, 나머지 0.55. 계열색은 고리 아래 작은 보석 한 점 |
| 이름·레벨 | 64, 206 | 이름 H1 40(계열 글자색). 레벨 숫자 24 + 경험치 바(폭 300, 높이 6, `GROWTH` 채움) + 수치 보조 14. 남은 포인트(◆ `GROWTH`) |
| 시작 기술 | 64, 330, 420×80 | 계열 문장(지금 `ElementSeal`) 48 + 기술 이름 H3 20 + 요약 한 줄 본문 16 `INK_DIM`. 요약은 숫자만(문장 전체를 계열색으로 칠하지 않는다, A2 1.1) |
| 행동 목록 | 64, 450, 420×(48×3) | 스킬 트리(◆ 남은 포인트), 장비(D6 착용 창, 판 밖), 의상(가진 수/전체). 4.1의 메뉴 줄과 같은 꼴 |
| 시작 | 64, 740, 420×60 | 주 단추(K4). H2 26. 기본 초점 |
| 의상 칸 | 680, 690, 872×180(열 때만) | 의상 카드 120×160, 간격 12, 가로 목록. 카드는 의상 초상의 얼굴~허리 자르기(A3 14.7 (C)). 입은 것은 작은 표시, 잠긴 것은 실루엣 + 얻는 법 한 줄(본문 16). 카드에 초점이 가면 큰 원화가 그 의상 초상으로 바로 바뀐다(0.15초 교차). Enter = 입기, Esc = 닫기(바꾼 것은 입은 채로 남는다) |
| 아래 줄 | 64, 850 | 키 안내 |

- **위계**: 원화 → 이름 → 시작 단추 → 시작 기술 → 레벨 → 행동 목록 → 메달 → 키 안내.
- **초점**: 기본 초점은 [시작]. ↑/↓로 행동 목록과 [시작] 사이를 오간다. 마녀 바꾸기는 **어느 초점에서나** LB/RB(키보드 Q/E, 마우스는 메달 클릭)이고 ←/→는 쓰지 않는다(의상 칸의 가로 이동과 부딪히지 않게). 의상 칸이 열리면 초점은 칸 안에 갇히고 ←/→로 움직인다. Esc/B는 의상 칸 → 화면 순으로 닫는다.
- **D2 해결**: 이 화면에서 "선택"은 하나다. 보이는 원화와 이름이 곧 시작할 마녀이고, 초점은 행동 목록 안에서만 움직인다.
- **원화 쓰기의 선**(A3 1.3.2): ① 원화를 0.75배보다 크게 키우지 않는다. ② 무릎 위에서 자르지 않는다(가슴·골반이 화면의 중심이 되는 자르기 금지). ③ 얼굴이 화면 위쪽 30% 안에 온다. ④ 번개 원화는 낮은 카메라에 다리를 넓게 벌린 자세라 골반이 그림 세로의 약 45%에 있다. 0.75배·위 맞춤이면 화면 y 약 490에 오고 가로로는 화면 가운데에서 260 오른쪽이다. 이 자리가 화면의 시선 중심이 되지 않는지 1080p 캡처로 art-lead가 본다. 걸리면 번개만 0.7배로 줄이고 아래로 더 자른다(무릎 아래).
- **의상과 저장**: 마녀별로 가진 의상 목록과 입은 의상은 스키마 4의 몫이다(`DECISIONS-PENDING` 2.12 이후 결정). 저장이 생기기 전에는 의상 칸에 기본 복장 카드 하나만 보이고 나머지는 잠긴 자리로 둔다. 화면은 먼저 지을 수 있다.
- **장비**: 마녀별 착용(L4)이 결정됐으므로 [장비]는 그 마녀의 착용 묶음을 연다.
- **720p**: 이름 40 → 32px, 요약 16 → 12.8px, 의상 카드 얻는 법 16 → 12.8px. 얼굴 높이: 원화 얼굴(이마~턱)이 원본 약 120px이므로 0.75배 × 0.8 = 약 72px(720p), 약 108px(1080p). A2가 정한 "720p 얼굴 90px"에는 못 미친다. 원화를 크게 하면 무릎 위로 잘려 위 ②에 걸린다. 그래서 얼굴은 메달(96 → 720p 77px)과 함께 읽힌다고 보고, 사용자 판단으로 넘긴다(9절 U-A6).
- **번역**: 왼쪽 판 폭 420. 이름("서리의 마녀" 6자, 영어 "Frost Witch")은 H1 40에서 한 줄, 넘치면 32로 줄이고 그래도 넘치면 두 줄. 시작 기술 요약은 자동 줄바꿈 두 줄까지. 행동 목록 줄은 4.1과 같다.

### 4.3 스킬 트리 (`view/hud/skill_tree_panel.gd`)

구조와 상태 규칙(점선 = 잠김, 실선 = 열림, 이중 = 최대, `+n` = 예정)은 그대로 둔다. 바꾸는 것은 재질, 사람, 금색 충돌이다.

```
┌ 창 틀(K1, 장식 모서리 넷) ─────────────────────────────────────────────────┐
│ (메달128) 서리의 마녀  Lv 8  ━━━━━━━░░ 4,000/4,500         남은 포인트 ◆ 2 │ y 20~150
│ ──── 장식선 ────────────────────────────────────────────────────────────── │
│      [관통 ▽] [얼음 지대 ▽] [파쇄 ▽] [서약 ▽]   ← 늘어뜨린 띠 머리           │ ┌ 설명 칸(K2) ┐
│ 단1  [칸][칸][칸][칸]                                                     │ │ 이름 / 랭크  │
│        │실  │실                                                          │ │ 지금 / 다음  │
│ 단2  [칸][칸][칸][칸][칸]                                                 │ │ 필요 조건    │
│ 단3  [칸][칸][칸]                                                        │ │ 한 줄       │
│ 단4                      [칸]                                            │ │ [투자][되돌]│
│                                                                          │ │ (아래: 원화  │
│                                                                          │ │  밝기 .35)  │
│ 재 0 · 초기화 비용 0                   [전체 초기화 R] [취소 Esc] [확정 F · 2] │ └────────────┘
│ 키 안내 한 줄                                                              │
└────────────────────────────────────────────────────────────────────────────┘
```

| 바꿀 것 | 지금 | 새 값 |
|---|---|---|
| 바깥 틀·설명 칸 | 평평한 판 | 창 틀 K1(장식 모서리 넷), 설명 칸 K2(장식 없음). 노드 칸은 재질을 넣지 않는다(상태 표시가 주인공) |
| 머리 초상 | 98×98 사각 | 메달 128(K11, 원형 + 금속 고리). 캐릭터 선택의 메달과 같은 물건 |
| 열 머리 | 사각 띠 | 아래 끝을 V자로 자른 짧은 띠(늘어뜨린 천). 서약 열 머리에만 작은 매듭 하나(A2 3.4) |
| 연결선 | 사각 연결 상자 "2" | 열린 연결은 `LINEN` 실선 + 아래 칸 위의 작은 매듭, 숫자 "2"는 매듭 옆 작은 글(14). 잠긴 연결은 점선 `BRASS_DIM` |
| `+1` 표시 | 노란 채움 사각 | **채움 없이** `GROWTH` 글자 + 1px `GROWTH` 테. 밝은 금 채움 덩어리는 화면에 "선택" 하나만 남긴다(D13) |
| 오른쪽 아래 빈 곳 | 빈 판 | 그 마녀 원화의 허리 위를 밝기 0.35로, 아래로 어둠에 사라지게. 설명 글 뒤에는 두지 않는다(설명 칸 안의 글이 끝난 아래 여백에만) |
| 비활성 단추 | 점선 테두리 | 점선은 "잠김"의 뜻이므로 단추에는 쓰지 않는다. 비활성 단추 상태(K3 disabled)로 |

- **초점**: 지금 규칙(방향키/WASD 칸 이동, Enter 투자, Backspace 되돌리기, F 확정, Esc 취소, R 전체 초기화)을 그대로 둔다. 패드: A 투자, X 되돌리기, Y 확정, B 취소, 왼쪽 막대·십자 이동. 버림 확인 창의 기본 초점은 [취소].
- **720p**: D14의 아래 안내 줄과 칸 안 둘째 줄은 글꼴 교체 뒤 다시 잰다. 11.2px 아래로 보이면 칸 안 둘째 줄을 15로 올리고, 안내 줄은 키 아이콘으로 줄여 글을 짧게 한다.
- **번역**: 칸 이름은 한 줄 + 말줄임 + 툴팁(지금 "서약의 가호"가 두 줄로 접히는 것을 허용할지: 칸 높이가 고정이라 두 줄까지만, 그 이상은 말줄임). 설명 칸은 자동 줄바꿈과 스크롤.
- 단 이름 "수녀의 기도"는 폐기된 설정(A2 1.7)이고 낱말 교체는 narrative-lead 몫이다. 화면은 단 이름 폭을 140으로 두고 두 줄까지 받는다.

### 4.4 전투 HUD 전체

A 배치(아래 가운데 한 줄, `combat_bar.gd`)와 크기는 확정이다. 전투 줄의 크기 `BAR_SIZE` 860×160, 화면 아래에서 10 띄움 → 코드 x 370~1230, y 730~890. 가운데 60%의 아래 경계(y 720) 밖이다.

```
 y 20  ┌장소·시간┐            목표 한 줄(상자 없음)                [⌂][Ⅱ][♪]
       │앞뜰 02:31│                                                ●──●──○ 경로
 y 92  └────────┘         ── 이름 ──                                현재 목표
 y146                     ▬▬▬▬▬▬▬▬▬▬ 우두머리 바
                     ┌──────── 가운데 60% (x 320~1280, y 180~720) — 표시 없음 ────────┐
                     └────────────────────────────────────────────────────────────────┘
 y 730       ╭───╮━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╭───╮   ┌알림┐
             │생명│  [불][얼음][번개]  ⟨필살⟩  [회피][물약]                      │영혼│   │    │
 y 890       ╰───╯━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╰─⑪╯   └────┘
              ↑구슬 틀(K5)  ↑칸 테(K6)    ↑필살 메달(K7)        ↑뒤로 가는 금속 레일   ↑레벨 명판(K12)
```

| 부품 | 좌표(코드) | 새 모습 | 근거·주의 |
|---|---|---|---|
| 전투 줄 판 | 370~1230 × 790~890 | **판을 거의 지운다**: 아래에서 위로 검정 0.55 → 0의 그러데이션(높이 100) 하나. 그 위 y 822 높이에 가는 금속 레일(K8, 두께 4, 양 끝이 구슬 틀 뒤로 들어감) | D6. 검은 띠가 사라지고 구슬과 칸만 물건으로 남는다. 판이 없어지므로 칸 사이로 바닥이 비친다 → 칸 안쪽은 불투명 유리라 아이콘 대비는 줄지 않는다 |
| 생명 구슬 | 가운데 (436, 820), 반지름 54 | 유리 용기를 창살 네 개와 위 덮개·아래 받침으로 감싼 금속 틀(K5). 액체는 지금 색(`LIFE`→`LIFE_DEEP`), 위에 1.5px 밝은 수면선. 눈금 8개를 없앤다. 숫자는 지금처럼 가운데, 뒤에 반투명 원판 | 생명 30% 아래: 지금의 테두리 맥박을 **금속 틀 전체가 `LIFE_LOW`로 물드는 맥박**으로 바꿔 색을 지워도 밝기 변화로 읽히게 |
| 영혼 구슬 | (1164, 820), 54 | 같은 틀(좌우 반전). 액체는 주력 계열색 | |
| 레벨 명판 | 영혼 구슬 아래 테 (1164, 872), 반지름 16 | 금속 원판(K12) + 숫자 20 | 지금 있다. 재질만 |
| 스킬 칸 셋 | 크기 60, y 중심 822 | 테(K6, 모서리 작은 돌기) 안에 연기 유리 + 지금 문장. 재사용은 유리가 어두워지는 부채꼴. 아래 랭크 점은 지금처럼 | 스킬 칸은 글자 없이 읽혀야 한다(QUALITY 3절) |
| 필살기 칸 | 74 | 둥근 메달(K7)에 **잠금 걸쇠**. 열리면 걸쇠가 풀리고 가운데에 그 마녀의 문장 | D7. 이야기로는 어머니가 빌려주는 필살기 → 계승 필살기의 자리. 걸쇠는 "아직 열리지 않음"만 말하고 정체를 말하지 않는다 |
| 회피·물약 | 60 | 테(K6) + 지금 아이콘. 키 이름은 칸 아래 14(720p 11.2px). 회피 숫자는 칸 아래쪽 3분의 1 | A2 3.5 그대로 |
| 위 왼쪽 장소 | 24, 20, 336×72 | 판을 얇게: K2(장식 없음) 75% 투명. 장소 이름 H3 18, 시간 고정폭 숫자, 둘째 줄 처치 수 + 가는 진행 바(높이 3) | 장소 이름은 데이터에서 온다. 장 이름에 기대지 않는다 |
| 목표 한 줄 | 가운데, y 76~110 | **상자 없음.** 글 18 `INK` + 외곽선 3 + 뒤에 폭이 글에 맞는 아주 옅은 그러데이션. 새 목표가 뜰 때 2초 밝게, 그 뒤 `INK_DIM` | D5 |
| 위 오른쪽 단추 | 1400~1576, 20~60 | 글 단추 셋 → **아이콘 단추 셋**(장비·정지·소리) 36×36, 아래에 키 표기 14 | 패드로 하면 단추를 누를 일이 없다. 마우스 사용자용으로 작게 |
| 경로 | 1216~1576, 70~130 | 가는 선 + 구슬 셋(지난 구역 = 채운 금속, 지금 = 밝은 금 테, 남은 = 빈 고리). 구역 이름은 지금 구역만 글로(본문 16), 나머지는 툴팁 | A2의 매듭 대신 금속 구슬. 같은 뜻 |
| 우두머리 바 | 520~1080, 이름 y 122~142, 바 y 146~160 | A2 3.5 값. 틀 K10(양 끝 마개), 채움 `THREAT_DEEP`, 위 1px `THREAT`. 이름 H3 18 명조 | y 180 위. 보지 못했다(0.1절) |
| 장비 알림 | 1240~1576, 728~880 | 지금 자리 그대로(검증됨). 틀 K2 + 위 3px 등급색 줄 | |
| 바닥 글자(월드) | — | 가림 기준 밖. 글꼴만 새 체인으로(T3 1.5) | |

- **움직임(전투 중)**: 생명 맥박(있음), 구슬 수면 출렁임(새것, 7.4절 비용 기준을 통과할 때만), 목표 줄 밝기 변화. 그 밖에는 없다.
- **720p**: 글은 모두 14 이상(키 이름, 경로 글, 처치 수). D8을 글꼴 교체 뒤 다시 잰다.
- **번역**: 목표 줄은 가운데 정렬 한 줄, 최대 폭 800(x 400~1200), 넘치면 두 줄(y 76~130까지, 우두머리 이름 위에서 멈춤). 장소 판은 폭이 글에 맞게 늘어나되 최대 420. 아이콘 단추는 글이 없어 번역 영향이 없다.

### 4.5 은총(성장) 선택

A2 3.2를 잇는다. 판이 멈춘 창이라 가운데를 써도 된다.

| 영역 | 좌표 | 내용 |
|---|---|---|
| 창 | 140~1460 × 170~730 (1320×560) | 창 틀 K1 |
| 어머니 자리 | 164, 230, 280×400 | 어머니 원화가 정해지기 전에는 어두운 천 결 그림(K15) + 그 마녀의 계열 문장 10%. 원화가 들어오면 밝기 0.7, 얼굴 위쪽 절반은 그늘(A2 3.2). **화면 글에 "후원자"를 쓰지 않는다**(결정 T3). 이름표가 필요하면 narrative-lead가 정한 말 |
| 카드 셋 | 남은 폭을 셋으로 | 주력 계열 = 어머니 카드(둥근 모서리, 안쪽 바느질 땀, 어머니 자리에서 실이 와서 카드 위 매듭에 묶임, 단추 "받아들이기"). 다른 계열 = 거래 카드(모서리를 깎은 팔각, 이중 쇠선, 위 가운데 봉랍, 머리 줄 "거래 · 화염의 악마", 단추 "거래하기") |
| 카드 안 | | 문장 48 → 이름 H3 20(계열 글자색) → 종류 한 줄(16 `INK_DIM`) → 수치 줄(16). 카드 아래 빈 곳(D9)은 카드 높이를 내용에 맞추고 단추를 바로 아래에 붙여 없앤다 |

- **초점**: ←/→ 카드 사이, Enter/A 고르기. 기본 초점은 왼쪽 첫 카드. 숫자 1·2·3 바로 고르기를 둔다(패드 없이 빠르게).
- **번역**: 카드 이름 한 줄 + 말줄임, 수치 줄은 자동 줄바꿈, 단추 글은 한 줄(최대 폭 = 카드 폭 − 40).
- 흑백으로 바꿔도 두 종류가 갈리는 것이 통과 기준이다(A2 지시서 4).

### 4.6 인벤토리·보관함 → 착용 창(D6-A2)

D6 7.1의 결정대로 새 착용 창이 판 중 장비 창(I)과 판 밖 보관함을 **대체한다**. 화면 설계는 D6 7.2를 따르고, 여기서는 틀과 사람만 정한다.

```
┌ 장비 ─ (메달48) 서리의 마녀 Lv12 ─ 재 340 ──────────────────────────── [Esc] ┐ y 40~96
│ ① 착용 (x 64~464)          │ ② 목록 (x 488~928)         │ ③ 비교 (x 952~1536)  │
│        [머리]   [목걸이]    │ [칸 ‹ ›][등급 ‹ ›][정렬 ‹ ›] │ 선택     ▏ 착용 중   │
│ [무기]  원화    [반지1]    │ 장비 줄 …                   │ …                   │
│         전신    [반지2]    │                            │ 바꾸면(최종 수치)     │
│ [장갑]  260×520            │                            │ ▲ ▼ 줄               │
│         [몸통] [신발]      │                            │                     │
│ 세트: …                    │ [착용 Enter] [해체 X] …     │ [반지1과 비교 Tab]   │
└────────────────────────────────────────────────────────────────────────────┘ y 860
```

- 창 40~1560 × 40~860. 세 열 최소 폭 D6 그대로(360·380·440), 여기서는 400·440·584.
- ① 가운데의 원화는 **전신 2D**(D6 7.2), 260×520, 밝기 0.85, 틀 없이 아래로 어둠에 사라진다. 의상을 입었으면 의상 초상(A3 14.6), 아니면 몸통 장비 단계 초상(A3 13.2), 둘 다 없으면 원화. 칸 8개는 원화 둘레에 놓이고(K9 장비 칸 테 + 등급색 위 줄), 원화 위에 겹치지 않는다.
- 선택 상자(OptionButton) 대신 **‹ 값 ›** 스테퍼(K13)로. 패드에서 ←/→로 바로 바뀐다(C3 해결).
- ▲▼와 부호를 색과 늘 같이(D6 7.6). 초록·빨강은 새 토큰 `GOOD`·`BAD`로 `palette.gd`에 두고 art-lead가 색각 점검을 한다(7.1절).
- **초점**: 열마다 따로 돌고 LB/RB(키보드 Tab은 반지 비교에 쓰므로 `[`·`]`)로 열을 옮긴다. ① 칸을 고르면 ② 목록이 그 칸으로 걸러지고 초점이 ②로 간다.

### 4.7 정지

```
┌ 막(따뜻한 검정 .80 + 비네트) ───────────────────────────────────────────────┐
│   잠시 멈춤 (H2 28)                                                         │
│   ▸ 계속하기        │  이번 판                         │                       │
│     설정            │  앞뜰 · 02:31 · 처치 812 · Lv 6   │  원화 허리 위          │
│     조작 안내        │  기술: [❄3][🔥1][⚡0]             │  밝기 .35,            │
│     이번 판 포기     │  장비: 8칸 아이콘                  │  오른쪽 끝에서         │
│     메뉴로          │                                  │  어둠으로              │
│     게임 종료        │                                  │                       │
└──────────────────────────────────────────────────────────────────────────────┘
```

| 영역 | 좌표 | 내용 |
|---|---|---|
| 단추 목록 | 160, 220, 360×(52×6) | 4.1의 메뉴 줄과 같은 꼴. 판·상자 없음. "이번 판 포기", "메뉴로", "게임 종료"는 D4-U의 것 |
| 이번 판 요약 | 600, 220, 520×360 | 판 K2. 장소·시간·처치·레벨(본문 18), 기술 문장과 랭크, 장비 8칸 아이콘. **읽기만** |
| 원화 | 1120~1600 | 허리 위, 밝기 0.35. 글 뒤에 두지 않는다 |

- 조작 안내는 정지 창의 긴 문장(지금 (480~880, 430~520))에서 빼 "조작 안내" 화면(설정의 조작 칸과 같은 내용)으로 옮긴다.
- 화면 흔들림 토글은 설정으로 옮긴다. 설정이 생기기 전에는 정지 창 단추 목록 아래 한 줄(K14 토글).
- **초점**: 기본 [계속하기]. Esc/B = 계속하기. 포기·종료는 확인 창(D4-U, 기본 초점 [취소]).

### 4.8 결과

A2 3.3을 잇는다(한 판의 실, 구역 매듭, 희귀 이상 장비 구슬, 승리 = 묶인 끝, 패배 = 해진 끝). 이 문서에서 바꾸는 것:
- 창 틀 K1, 왼쪽 위 얼굴은 메달 160(K11), 패배 때 밝기 0.65.
- 장비 목록은 8칸 아이콘 격자(2×4), 이름은 초점 때만.
- 단추는 D4-U의 것(다시 도전, 메뉴로, 장비 정리, 스킬 트리). 기본 초점 [다시 도전].
- 제목 글은 narrative-lead의 교체안을 따른다(D12, "서약" 오용).

### 4.9 새 화면의 틀: 저장 거부 안내(D5-U), 설정

**저장 거부 안내** — 메뉴 위에 뜨는 확인 창. 창 K1(장식 모서리), 600×420 가운데. 제목 H2 26(`INK`), 설명 본문 16, 단추 넷 세로(D5 3.1). 기본 초점 [저장 없이 플레이]. 파일을 바꾸는 단추(새로 시작 등)는 일반 단추이되 아래에 `WARN` 글 한 줄로 결과를 적는다. **빨간 틀을 쓰지 않는다**(빨강은 적의 위협, `WARN`은 오류 글자만). 두 번 묻는 둘째 창도 같은 틀.

**설정** — 판 밖(메뉴)과 판 안(정지)에서 같은 화면. 범위는 결정 G5(해상도·전체 화면·음량 먼저) + T3-L5(언어) + 화면 흔들림.

```
┌ 설정 (창 K1, 1040×640, 가운데) ────────────────────────────────────────┐
│ ┌탭┐                                                                   │
│ │화면│  화면 모드        ‹  전체 화면  ›                                 │
│ │소리│  해상도           ‹  1920 × 1080  ›                               │
│ │언어│  수직 동기         [◉]                                             │
│ │조작│  화면 흔들림       [◉]                                             │
│ │    │  글자 크게         [○]   (9절 U-A8)                                │
│ └────┘                                                                   │
│                                        [되돌리기]  [적용]                │
└──────────────────────────────────────────────────────────────────────────┘
```

- 탭 목록 x 300~480(왼쪽), 내용 x 504~1300. 한 줄 = 이름(본문 18, 왼쪽) + 값(오른쪽 정렬, 폭 320). 값은 모두 **‹ 값 ›** 스테퍼(K13) 또는 토글(K14). 선택 상자와 휴대폰식 스위치를 쓰지 않는다.
- 해상도·화면 모드는 [적용] 뒤 10초 안에 [유지]를 누르지 않으면 되돌린다(게임 일반 관습).
- 언어 목록은 언어 이름을 그 언어 자체로(T3 2.8). 한국어 화면에서도 日本語·简体中文 글자가 보여야 하므로 **글꼴 체인에 CJK가 들어간 뒤에** 언어 칸을 연다(7.2절).
- **초점**: LB/RB 탭, ↑/↓ 줄, ←/→ 값. Esc/B 닫기(바꾼 값이 적용 전이면 묻기).
- **번역**: 이름 칸 폭 = 내용 폭 − 값 폭 − 24 = 452. 독일어 긴 이름도 한 줄, 넘치면 자동 줄바꿈 두 줄(줄 높이가 늘어난다).

---

## 5. 시안(목업) 생성 지시 — codex-operator용

### 5.1 목적과 범위

- **방향을 고르기 위한 그림**이다. 배치·재질·분위기를 보는 것이지, 글자·치수·720p 가독을 보는 것이 아니다. **글자는 뭉개져도 된다.** 목업이 통과해도 실제 화면의 통과 기준(8절)은 따로다.
- 세 안 × 네 화면 = **12장**. 장마다 1회, 배치가 크게 틀린 것(전투 HUD가 화면 가운데를 덮음, 인물이 원화와 다른 사람, 화면이 세로로 나옴)만 1회 다시. 최대 24회.
- 생성은 Codex CLI 내장 그림 생성만 쓴다(구독 안, 추가 과금 없음). Sunra·OpenAI API를 쓰지 않는다. 실행 배정은 디렉터가 한다.

### 5.2 실행

- 명령은 `codex-operator.md`의 형식 그대로: `codex exec -m gpt-5.6-sol -i <참조> -C <작업 폴더> --skip-git-repo-check -s workspace-write --color never -o <마지막 메시지 파일> -`, 프롬프트는 stdin.
- 작업 폴더: `_local/art/drafts/ui_mockups/work/<안>-<화면>-rN/`. 안 = `reliquary`(가), `codex`(나), `couture`(다). 화면 = `menu`, `select`, `hud`, `tree`.
- **참조 여러 장**: `-i`를 여러 번 주거나 쉼표로 이어 붙이는 방식이 되는지 첫 장에서 확인한다(확인하지 않았다). 안 되면 참조를 Pillow로 가로로 나란히 붙인 한 장(`refs-<화면>.png`)을 만들어 붙이고, 프롬프트의 참조 설명을 "왼쪽부터 …"로 바꾼다.
- **크기**: 내장 도구가 1920×1080을 직접 내지 못할 수 있다(지금까지 나온 것은 1024×1536 세로). 가로 최대(예: 1536×1024)로 뽑고, 프롬프트대로 가운데 16:9 띠 안에 내용을 두게 한 뒤, codex-operator가 가운데 16:9를 잘라 1920×1080으로 키운다(Lanczos). 원본도 남긴다.
- 대조 시트: 3행(안) × 4열(화면), 칸마다 640×360, `_local/art/drafts/ui_mockups/sheet-ui-mockups-r1.jpg`. 관리 툴 갤러리에 "화면 방향 시안" 묶음으로 등록(`organize.py`).
- **생성 도구가 거부하면**(특히 의상 카드가 있는 캐릭터 선택): 같은 문장으로 1회만 다시. 그래도 거부되면 문구를 바꿔 돌아가지 않고 멈춘 뒤 거부 메시지·프롬프트 전문·시각을 `run-log.txt`에 남겨 보고한다(A3 14.10과 같은 규칙).

### 5.3 프롬프트 조립

`prompt.txt` = [실행 문장] + 빈 줄 + `Image description:` + 빈 줄 + [공통 문장] + 빈 줄 + [안 문장] + 빈 줄 + [화면 문장]. 아래 영문을 고치지 않고 쓴다. `{REFS}`만 화면별로 채운다.

**실행 문장**

```
Use your built-in image generation tool to create exactly one image and save it in the current directory as mockup.png. The image is a user-interface design mockup: one full screenshot of a PC game screen in landscape orientation. Generate the widest landscape size the tool offers (for example 1536x1024) and keep every UI element and the important part of every character inside a centred 16:9 band that spans the full width; leave roughly the top 8% and bottom 8% as plain dark background, they will be cropped. The attached images are references only: {REFS}. Do not write any code. Create no file other than mockup.png. Do not read, modify or delete any other file in this directory or elsewhere. When done, reply with the saved file name, its pixel size, and whether the PNG has an alpha channel.
```

**공통 문장**

```
This is a design-direction mockup for an original dark gothic fantasy action game set in a ruined medieval monastery. Lettering is placeholder: menu labels may be short English words or illegible placeholder text; do not render long readable paragraphs and do not render Korean, Chinese or Japanese characters. The game's three heroines are adult women witches painted in a semi-realistic painterly style; when a heroine appears, keep her face, hair, body markings and outfit recognisable from the character reference and do not redesign her. Every character is an adult and clearly looks adult. All fabric covering the chest and hips is fully opaque, with no see-through fabric over the body and no nudity. Poses are neutral standing character-showcase poses; the framing never centres on the chest or hips and nothing is suggestive. The UI itself does not glow; spell effects are the brightest things on screen. Do not copy the layout, logo, icons or characters of any existing game. No watermark, no signature.
```

**안 문장 (가) 성유물함 — `reliquary`**

```
Visual direction "Reliquary": every UI frame is a piece of fine sacred metalwork from a monastery reliquary. Materials are only two metals and one glass: blackened silver (cool grey #8e949a) and worn antique gold (#aa8d58) for frames, and smoky dark glass (#0e1316, slightly translucent) for orb fronts and skill slot faces. Panel fills are near-black warm grey (#17191b) with an extremely subtle surface texture. Frames are thin (two-pixel metal rims with a one-pixel inner shadow); ornament is concentrated only at the corners of large windows as small pierced gothic tracery filigree, and the straight edges stay plain. Buttons and list rows have plain thin rims, no corner ornament. Selection is shown only by bright gold (#ffd27a) corner brackets. Element colours (orange fire, pale cyan frost, lavender lightning) appear only as tiny gem accents and spell icons, never on whole frames. Headings use an elegant high-contrast engraved serif; body text is a clean sans-serif. Characters are shown large and unframed, bleeding to the screen edge and fading into darkness, never boxed inside a picture frame.
```

**안 문장 (나) 장정과 실 — `codex`**

```
Visual direction "Bound Codex": every UI panel looks like the binding of an old monastery prayer book. Materials: smoked black leather with a fine grain (#17191b to #202628), a blind-tooled line pressed six pixels inside each edge, worn brass corner guards with two small rivets on large windows only, and a single strand of undyed linen thread (#cbbf9f) used as dividers (short slanted stitches) and to connect related items with small knots. Tiny parchment labels are allowed only for small tags. Buttons are slightly lighter leather pieces with a thin dim brass edge. Selection is shown only by a bright gold (#ffd27a) edge. Element colours (orange fire, pale cyan frost, lavender lightning) appear only on names, icons and a small wax seal. Headings use a soft bookish serif; body text is a clean sans-serif. Characters are shown inside leather-matted frames with brass corners.
```

**안 문장 (다) 화보 — `couture`**

```
Visual direction "Couture Gallery": the UI is a luxurious dark fashion-editorial layout. Surfaces are near-black glossy panels (#0c0d0f) with large areas of empty space; there are almost no frames, only ultra-thin one-pixel champagne-gold hairlines (#c9b48a) and a few diagonal cuts that separate areas. Typography carries the design: a very large thin high-contrast serif for titles and small widely letter-spaced capitals for labels. Selection is shown by a bright gold (#ffd27a) hairline underline and a slight brightening. Element colours appear only in the lighting of the characters and in small icons. Characters are shown very large, cut out against the dark background with dramatic rim light, like a magazine cover.
```

**화면 문장 — 메인 메뉴 `menu`** (참조: 화염·냉기·번개 원화 세 장. `{REFS}` = `the three character references, from left to right: the fire witch (red-brown hair, ember-orange markings), the frost witch (long silver braid, icy markings), the storm witch (short platinum hair, lavender lightning markings)`)

```
Screen: title and main menu. Left 35% of the screen: the game logo "Witch Moira" as a large wordmark in the direction's heading style, a short subtitle line under it, and below that a vertical list of six menu entries ("Continue", "New Game", "Costumes", "Settings", "Credits", "Quit") with the first entry focused using the direction's selection marker. A small version line at the bottom left and a small key-hint row at the bottom right. Right 65% of the screen: the three witches from the references shown as three tall side-by-side painted panels (fire witch, frost witch, storm witch, left to right), each cropped from head to knee with faces near the top, their own painted ruined-monastery backgrounds, panels fading into darkness at their shared edges and toward the left side. No in-game HUD, no world map, no other characters.
```

**화면 문장 — 캐릭터 선택 `select`** (참조: 냉기 원화. `{REFS}` = `the character reference of the frost witch (long silver braid, icy markings on one arm, dark bustier, thigh-high boots)`)

```
Screen: character select. The frost witch from the reference is shown very large on the right 60% of the screen, from head to knee, standing in the reference pose, unframed, her snowy ruined-cloister background extended and softly blurred to fill the screen, fading into darkness toward the left. Left 32% of the screen, on a dark gradient: three round portrait medallions in a row (fire witch, frost witch, storm witch) with the frost one selected; her name as a large heading ("Frost Witch"); a level number with a thin experience bar; a "starting spell" row with a small snowflake sigil icon and one short line; a vertical list of three entries ("Skill Tree" with a small badge "2", "Equipment", "Costumes 2/4"); a large primary "Start" button near the bottom; a thin key-hint row at the very bottom. Bottom right, over the lower part of the painting: an open horizontal strip of four small portrait cards of the same witch in different outfits (her battle outfit; an elegant opaque summer swimsuit with a long sarong and a wide-brimmed hat; two locked dark silhouette cards), the first card focused.
```

**화면 문장 — 전투 HUD `hud`** (참조: 전투 캡처 `_local/shots/round2-20261117/frost-1080/11-playing-16000.png` + 냉기 원화. `{REFS}` = `first, a gameplay screenshot that shows the camera height, scene and HUD placement to keep (replace its HUD with the new style, keep the scene composition); second, the frost witch character reference for the heroine's colours`)

```
Screen: in-game combat. High top-down three-quarter isometric view of a ruined gothic cloister courtyard at night, stone floor, broken pillars; a small heroine (about 10% of the screen height) in the centre fighting a large horde of skeletons with bright pale-cyan ice shard spells; one red danger telegraph shape on the ground. HUD in the new style, thin and quiet, the middle 60% of the screen completely free of UI: bottom centre a single compact row; at its left end a round glass life orb filled with dark red liquid with a bright liquid surface line, held in a crafted cage of four thin metal ribs with a top cap and a small foot; at its right end a matching orb with pale cyan liquid and a small round metal level plaque with the number 11 on its lower rim; between the orbs a thin metal rail with six square slots in small crafted bezels with smoky glass faces: three spell sigils (fire, frost, lightning), a slightly larger central round medallion closed with a small clasp, a dash slot with chevrons, a potion slot. No dark plate behind the row, only a soft dark gradient. Top left: a small thin semi-transparent plate with an area name and a timer and a thin progress line. Top centre: one line of objective text with no box, and under it a thin boss health bar with a name. Top right: three small icon buttons and a thin route line with three beads. Bottom right corner: a small item-upgrade notification card with a coloured top edge.
```

**화면 문장 — 스킬 트리 `tree`** (참조: `_local/shots/ui-g1p4/tree-1080-l8/04-tree-staged.png` + 냉기 원화. `{REFS}` = `first, a screenshot of the current skill tree whose structure must be kept (grid, states, panels), restyle it completely; second, the frost witch character reference`)

```
Screen: full-screen permanent skill tree of the frost witch, a game menu over a darkened background. Keep the structure of the first reference: a header row with a round portrait medallion of the frost witch, her name, a level number and a thin experience bar, and a points counter at the top right; four columns with short hanging banner headers (the last column's banner has a small knot); four tiers of rectangular node tiles in a grid, each tile with a small icon, a name, rank pips and a rank number; unlocked tiles have solid thin frames, locked tiles have dashed frames and a small lock, maxed tiles have double frames; short connector lines with small knots between tiers; one tile focused with bright gold corner brackets. Right side: a tall detail panel with the selected node's name, rank, current and next effect, requirements and two buttons; in the empty lower part of that panel, a faint large painted half-figure of the frost witch fading into darkness. A footer row with three buttons and a thin key-hint line.
```

### 5.4 검수(art-lead, 받은 뒤)

| 항목 | 기준 |
|---|---|
| 인물 | 원화와 같은 사람으로 읽힌다. 세 선(성인, 가슴·골반 천 불투명, 성행위 연상 자세·구도 없음). 가슴·골반은 원본을 2배로 잘라 본다(A3 1.3.2) |
| 배치 | 전투 HUD: 가운데 60%에 표시가 없다, 아래 한 줄. 스킬 트리: 4열 × 4단 구조가 남았다 |
| 방향 | 같은 안의 네 장이 한 벌로 읽힌다(틀·글꼴·색). 세 안이 서로 다르게 읽힌다 |
| 복제 | 알려진 게임의 로고·틀·아이콘과 닮은 것이 없다(눈으로) |

그 뒤 대조 시트를 디렉터 → 사용자에게 올린다(9절 U-A1).

---

## 6. 재질 키트 목록 — 권고안 (가)

**제작 방식**: 장식 조각(뚫새김 모서리, 구슬 틀, 칸 테, 메달 고리, 걸쇠)은 Codex 생성, 곧은 변·채움·질감·초점 괄호·실·봉랍은 코드(Pillow, 고정 씨앗)로 만든다. 9분할은 생성 그림의 모서리 칸에 코드로 만든 곧은 변을 이어 붙여 짓는다(생성 그림의 변은 이음매가 맞지 않는다).

- 생성 조각은 **자홍 `#FF00FF` 바탕** 위에 그린다. 지금 아이콘 파이프라인(`tools/art/make_equipment_icons.py`의 `remove_magenta`)과 같은 방식으로 배경을 뗀다. 금속에는 자홍이 없어 잘 떨어진다. 반투명 유리는 생성하지 않는다(배경 떼기가 반투명을 못 살린다). 유리·액체·반사는 코드로 그린다.
- 원본 크기 = 코드 크기 × 2(1080p는 ×1.2라 여유가 있다). 가져오기: 무손실, 장식 조각은 밉맵 켬 + 선형 밉맵 필터(720p에서 ×0.4로 줄어 고운 세공이 깨지지 않게), 9분할 판은 밉맵 끔.
- 하나의 텍스처 묶음(아틀라스)에 모아 전체 VRAM 6MB 이하.
- 스크립트: `tools/art/make_ui_kit.py`(asset-producer). 생성 조각은 `_local/art/drafts/ui_kit/`에서 고르고, art-lead 검수 통과 뒤 `chapter1/art/ui/kit_v01/`로. 원장에 "Codex 생성(구독), 자체 후처리".

**생성 조각의 공통 문장**(조각 문장 앞에 붙인다. 실행 문장은 5.3절과 같은 꼴로 파일 이름만 `sheet.png`)

```
Game UI ornament sprite sheet in the "Reliquary" style: fine sacred metalwork in blackened silver (#8e949a) with worn antique gold (#aa8d58) accents, matching the jewellery in the attached character reference (silver filigree, small chains). Orthographic straight-on front view, no perspective, soft even light from the top left, crisp clean edges, small engraved detail that still reads at small size. Each piece sits separately on a perfectly flat solid magenta (#FF00FF) background with wide magenta gaps between pieces and around the border; nothing touches the image edge; no shadow on the background, no magenta inside the pieces. No glass, no glow, no gems unless stated, no text, no faces, no skulls, no animals, no watermark.
```

참조는 냉기 원화 한 장(장신구의 세공 참조).

| # | 조각 | 코드 크기 | 용도 | 제작 | 프롬프트 재료(조각 문장) |
|---|---|---|---|---|---|
| K1 | 큰 창 틀 9분할 | 모서리 40×40, 여백 24, 원본 192×192 | 메뉴 위 창, 스킬 트리, 은총, 정지 요약, 결과, 착용 창, 설정, 확인 창 | 모서리 넷 = 생성 / 변·채움 = 코드 | `Sheet of four matching corner ornaments for a window frame (top-left, top-right, bottom-left, bottom-right, mirrored), each an L-shaped thin double metal rim with a small pierced gothic tracery filigree in the corner, about 80 pixels on a side in the final asset` |
| K2 | 판 9분할(장식 없음) | 여백 12, 원본 64×64 | 목록·설명 칸, 위 왼쪽 장소 판, 알림 | 코드 | 테 2(은 + 안쪽 1px 그늘), 채움 `SURFACE` + 밝기 ±2% 질감 |
| K3 | 단추 4상태 | 64×40, 여백 12 | 모든 일반 단추 | 코드 | 보통 `SURFACE_RAISED` + 테 `BRASS_DIM`, 올림 테 `BRASS`, 누름 채움 한 단계 어둡게, 비활성 채움 `SURFACE`·테 `3e4343`·글 `INK_FAINT`. 비활성은 회색 막대가 아니라 "꺼진 금속"으로 보이게 |
| K4 | 주 단추 | 420×60, 여백 20 | 시작, 확정, 다시 도전 | 양 끝 마개 = 생성 / 가운데 = 코드 | `Pair of end caps for a long horizontal button: small pointed gothic metal finials, mirrored left and right, about 40 by 60 pixels each` |
| K5 | 구슬 틀 | 지름 140(구슬 108 + 틀), 원본 280 | 생명·영혼 구슬 | 생성 | `One round cage for a glass orb: a thin circular metal ring with four thin vertical ribs curving around the sphere, a small domed top cap and a small footed base, the inside of the ring left fully magenta (the glass will be added later), about 280 pixels tall` |
| K6 | 칸 테 | 60 / 74, 원본 120 / 148 | 스킬 칸 셋, 회피, 물약 | 생성 | `Two square bezels for skill slots: thin metal square rims with a tiny rounded nub at each corner, plain straight edges, the inside fully magenta, one 120 and one 148 pixels wide` |
| K7 | 필살기 메달 | 지름 74, 원본 148 + 걸쇠 | 필살기 칸(잠김·열림) | 생성 | `A round medallion bezel about 148 pixels wide with a thin decorated metal rim and an empty magenta centre; separately, a small closed metal clasp that can lie across the medallion, and the same clasp open` |
| K8 | 레일과 구분선 | 레일 높이 4 가로 반복, 구분선 높이 12 + 가운데 장식 96×12 | 전투 줄 레일, 창 안 구분선, 제목 밑줄 | 레일·선 = 코드 / 가운데 장식 = 생성 | `A small horizontal centre ornament for a divider line: a tiny pierced quatrefoil flanked by two short tapered metal strokes, about 192 by 24 pixels` |
| K9 | 장비 칸 테 | 72, 원본 144 | 착용 창 8칸 | 코드 | K6의 테를 등급색 없이. 등급은 위 3px 줄로 따로(A2 2-B) |
| K10 | 우두머리 바 틀 | 560×22, 양 끝 마개 24×30 | 우두머리 체력 | 마개 = 생성 / 몸 = 코드 | `Pair of end caps for a thin horizontal health bar frame: small pointed metal clasps, mirrored, about 48 by 60 pixels each` |
| K11 | 메달 고리 | 96 / 128 / 160, 원본 320 하나를 줄여 씀 | 마녀 메달(선택, 트리 머리, 결과, 착용 창 머리) | 생성 | `One circular portrait frame ring, about 320 pixels wide: a thin metal ring with fine engraved filigree and one small empty round setting at the bottom for a gem, the inside fully magenta` |
| K12 | 레벨 명판 | 지름 36, 원본 72 | 영혼 구슬 아래 | 코드 | 금속 원판 + 테 1.5, 글 대비 4.5:1 |
| K13 | 스테퍼 화살 | 16×16, 원본 32 | ‹ 값 ›, 목록 넘기기 | 코드 | 작은 금속 갈매기 |
| K14 | 토글 | 28×28, 원본 56 | 켬/끔 | 코드 | 끔 = 빈 금속 고리, 켬 = 고리 안 채운 원(`BRASS`). 휴대폰식 스위치 대체 |
| K15 | 천 결 그림 | 280×400 | 은총의 어머니 자리(원화 전) | 코드 | A2 `veil_280x400`과 같은 내용. 파일 이름에 veil을 쓰지 않는다(`cloth_280x400`) |
| K16 | 초점 괄호 | 모서리 12×12 넷 | 모든 초점 | 코드 | `BRASS_HI` 2px ㄱ자 넷. 코드로 그려 색이 정확하게. 0.10초 미끄러짐 |
| K17 | 실·매듭·봉랍·해진 끝 | A2 2-A 값 | 은총 어머니 카드, 결과, 트리 연결 | 코드 | A2 2-A 표 그대로 |
| K18 | 카드 틀 | 어머니·거래 각 96×128, 의상 카드 120×160 | 은총, 의상 칸 | 코드 + K1 모서리 축소 | 어머니·거래는 A2 2-A. 의상 카드는 K2 + 아래 이름 띠 |
| K19 | 배경 그림 | 1600×900 × 세 마녀 + 메뉴 1 | 캐릭터 선택·메뉴의 원화 바깥 | 코드(원화를 크게 늘려 흐림 반지름 40, 밝기 0.45로 미리 구움) | 실행 중 흐림 금지(7.4) |
| K20 | 마우스 커서 | 32×32, 원본 64 | 메뉴·창(전투 중에는 지금 커서) | 생성 | `One small mouse pointer arrow made of blackened silver with a worn gold edge, pointing up-left, about 64 pixels tall, crisp silhouette` |
| K21 | 비네트 | 800×450 | 창 뒤 막 | 코드 | A2 `vignette.png` |

**검수(art-lead)**: 대조 시트 `_local/art/drafts/ui_kit/kit-contact.png`에 모든 조각을 1배·2배, 검은 바탕과 전투 캡처 위, 원화 장신구 확대 옆에 놓는다. 같은 금속으로 읽히는지, 720p 크기(×0.4)에서 세공이 깨지지 않는지, 배경 떼기 가장자리에 자홍 테두리가 남지 않는지 본다.

---

## 7. 공통 규칙

### 7.1 색

`palette.gd`의 토큰 그대로(A2 2.3, 이미 반영). 더할 것:

| 이름 | 값(안) | 뜻 | 쓰지 않는 곳 |
|---|---|---|---|
| `METAL_SILVER` | `8e949a` | 틀의 은(조각 그림의 바탕 색 참고값, 코드 선의 색) | 글자 |
| `GLASS` | `0e1316` 75% | 구슬·칸의 유리 앞면 | 판 |
| `GOOD` / `BAD` | 색각 점검 뒤 정함 | 착용 비교의 좋아짐·나빠짐(D6 7.6), 늘 ▲▼·부호와 함께 | 다른 곳 |

- `GROWTH`(영구 성장 금)와 `BRASS_HI`(선택 금)가 가까운 색이다(D13). `GROWTH`는 **채움 덩어리로 쓰지 않는다**(글자·가는 바·마름모 기호만). 바꾸지 않고 쓰는 법으로 가른다.

### 7.2 글꼴

시스템 글꼴(`SystemFont` "Malgun Gothic", "Batang") 의존을 끊는다. 다른 컴퓨터와 스팀 덱에는 이 글꼴이 없고, Microsoft 글꼴이라 게임에 넣어 배포할 수 없다(T3 1.5).

**위계**(A2 2.2를 고침)

| 층 | 용도 | 크기(코드) | 720p |
|---|---|---|---|
| H1 | 마녀 이름(선택), 결과 제목 | 40~48 | 32~38px |
| H2 | 창 제목 | 26~30 | 21~24px |
| H3 | 메뉴 줄, 카드·칸 이름 | 18~22 | 14~18px |
| 본문 | 설명, 수치 | 16~18 | 12.8~14px |
| 보조 | 키 안내, 출처 | 14(하한) | 11.2px |
| 숫자 | 생명, 레벨, 시간 | 17~24, 고정폭 숫자 | |

**후보**(라이선스는 내 기억이다. 원문을 열어 보지 않았다. **내려받기는 사용자 승인(A3 = T3 L-U2) 뒤**)

| 용도 | 1순위 | 다른 후보 | 덮는 글자 | 라이선스(기억) | 메모 |
|---|---|---|---|---|---|
| 제목(한) | **Noto Serif KR**(= 본명조 Source Han Serif K) | 마루 부리(MaruBuri), 함렛(Hahmlet), 고운바탕 | 한글·라틴 | SIL OFL 1.1 | 1순위를 고른 이유: 같은 설계의 일·간·번체판(Noto Serif JP/SC/TC)이 있어 **언어를 바꿔도 제목의 인상이 같다**. 굵기가 여럿이라 720p에서 SemiBold로 획을 지킬 수 있다 |
| 제목(일·간·번) | **Noto Serif JP / SC / TC** | — | 한자 지역 모양, 가나 | OFL 1.1 | T3 2.6 체인 그대로 |
| 제목(라틴·키릴) | **Noto Serif** | Cormorant Garamond, EB Garamond | 라틴 확장, 키릴 | OFL 1.1 | Cormorant는 획 대비가 커서 (가)와 맞지만 작은 크기에서 약하다. H1·H2에만. Cinzel은 이 장르에서 너무 흔해 권하지 않는다 |
| 본문(한) | **Pretendard** | Noto Sans KR, SUIT, IBM Plex Sans KR | 한글·라틴 | OFL 1.1 | 고정폭 숫자 기능(`tnum`)이 있다고 기억한다(확인 필요) |
| 본문(일·간·번) | **Noto Sans JP / SC / TC** | — | | OFL 1.1 | T3 2.6 |
| 본문(라틴·키릴) | **Noto Sans** | Inter | | OFL 1.1 | |
| 로고 | 글꼴로 만든 워드마크 그림 | 따로 그린 로고(나중) | 라틴 "Witch Moira" | — | 9절 U-A5 |

- 체인은 T3 2.6 그대로(언어마다 첫 글꼴을 바꿈, 시스템 대체 끔). `Loc.font(role)`(T3-L3)가 역할 `title`·`body`·`number`를 돌려준다. `draw_string`(전투 줄, 스킬 트리)과 `Label3D`도 이것을 쓴다.
- 확인할 것(T3 2.6 절차): 원문(`OFL.txt`)과 판 번호, 예약 글꼴 이름 조항과 부분 집합 때 이름 바꾸기, 게임 실행 파일에 넣어 배포 가능 문구, 쓰는 글자가 다 있는지 기계 검사, 720p 렌더링(힌팅·서브픽셀), 파일 크기. Pretendard·마루 부리의 라이선스가 OFL인지는 특히 확인한다.

### 7.3 초점과 패드(스팀 덱 대응은 출시 조건, 결정 R4)

| 규칙 | 내용 |
|---|---|
| 하나의 초점 표시 | 밝은 금 모서리 괄호(K16)만. 마우스 올림은 테 밝기만 바뀐다(초점과 다른 모양) |
| 이동은 `ui_*` 동작으로 | 초점 이동·확인·취소는 Godot의 `ui_up/down/left/right`, `ui_accept`, `ui_cancel`, `ui_focus_next/prev`로 읽는다. Godot 4는 이 동작에 패드 십자·막대·A·B를 기본으로 묶어 두므로 패드가 따로 일 없이 따라온다. **새 화면에서 키코드를 직접 읽지 않는다.** 화면 고유 키(F 확정, R 초기화, Q/E 마녀 바꾸기)는 새 입력 동작 이름으로 만들고 패드 단추는 T4-I가 묶는다 |
| 기본 초점 | 화면마다 정한다(4절). 창을 닫으면 연 단추로 돌아간다 |
| 갇힘 | 창이 열리면 초점은 창 안에만. 끝에서 감지 않는다 |
| 탭·열 | LB/RB(키보드 `[`·`]` 또는 화면이 정한 키) |
| 키 표기 | 글 안에 박지 않고 `{key_*}` 자리 표시자(T3 2.7). 패드 아이콘은 T4 |
| 마우스 | 모든 단추를 마우스로도 누를 수 있다. 마우스와 키보드를 섞어 써도 초점이 하나 |
| 화면 비율 | 앵커로 붙인다. 1280×800(16:10)에서 `aspect=expand`가 되어도 위아래 표시가 화면 끝에 붙어 있게(절대 y를 쓰지 않는다) |

### 7.4 움직임과 성능

**전투 중(판이 돌 때) — 비용을 늘리지 않는다.** 지금 판 전체 p95 40~56ms, HUD 동기화 후반 평균 0.78ms(T2 25행).
- 전투 줄은 지금처럼 컨트롤 하나의 `_draw()`. 새 노드를 만들지 않는다. 텍스처는 `draw_texture_rect`(같은 아틀라스라 한 번에 그려진다).
- 셰이더, 화면 읽기(`BackBufferCopy`, 화면 텍스처를 읽는 셰이더), 실행 중 흐림, 파티클을 HUD에 쓰지 않는다.
- `_draw()`는 값이 바뀔 때만 다시 부른다(구슬 값·재사용·물약 수가 바뀔 때, 맥박·출렁임은 30Hz로 묶어서). 지금 매 프레임 부르는지는 확인하지 않았다(8절 U3의 첫 단계).
- 구슬 출렁임은 측정으로 통과할 때만 켠다. 통과 기준: 같은 시드·시점에서 HUD 동기화 시간이 지금 +0.1ms 이내, 판 전체 p95가 나빠지지 않음(T2-0b의 계측으로 qa-perf가 잰다).
- 글자는 매 프레임 새로 짓지 않는다(값이 바뀔 때만 `text`를 바꾼다).

**판이 멈춘 화면(메뉴, 캐릭터 선택, 창)** — 움직임을 쓴다. 창 열기 0.18초(투명 0→1, 크기 0.97→1), 닫기 0.12초, 초점 괄호 0.10초, 원화 교차 0.15초, 실 0.25~0.8초(아무 키나 건너뛰기). 메뉴 배경의 원화는 아주 느린 확대(20초에 1.00→1.03)를 쓸 수 있다. 길이 상수는 한 파일(`ui_motion.gd`)에 모아 "움직임 줄이기" 설정이 0으로 만들 수 있게.

### 7.5 글 길이(번역 여유)

- 기준: 가짜 언어 **1.4배**(`hud_dump.gd --pseudo --pseudo-expand=1.4`, T3-L4)에서 잘림·화면 밖·겹침 0. 구조 규칙은 T3 2.7의 "한국어 대비 가로 2배"를 따른다: 한 줄 글은 말줄임 + 툴팁, 설명은 자동 줄바꿈, 단추를 가로로 늘어놓는 곳(창 아래 단추 줄)은 2배에서 두 줄로 접히거나 세로로 바뀌게.
- 글이 든 컨트롤에 고정 폭을 주지 않는다. 화면 설계의 폭(4절)은 **최대 폭**이다.
- 새 화면 글은 모두 `Loc.t(key)`, 원문은 `chapter1/i18n/ko.po`. 자리 표시자 `{이름}`, 자리 표시자 뒤 조사 금지. 장 이름·구역 이름·마녀 이름은 자리 표시자로 받는다(이름이 바뀌어도 화면을 고치지 않는다).
- 화면 글은 `WORDING-RULES`를 따른다. 이 문서의 보기 글("이어 하기", "받아들이기" 등)은 자리 표시용이고, 최종 글은 원문 주인(ui-hud가 쓰고 narrative-lead가 서사 글을 검수)이 정한다.

---

## 8. 구현 지시서로 쪼개기

### 8.1 단위와 순서

모든 단위의 공통 규칙:
- 게임 코드는 `chapter1/view/hud/`와 새 화면 파일만. 코어·데이터·옛 층(`cloister_*.gd`, `chapter_world_quality*.gd`)은 고치지 않는다. 평탄화된 `__q` 메서드는 최종 진입점에서만 덮어쓴다.
- `chapter_hud.gd`를 건드리는 단위는 **동시에 하지 않는다**(ui-hud가 차례로). 코드를 고치는 에이전트는 별도 작업 폴더에서 일한다(DIRECTOR-PLAN 11-17 기록).
- 새 화면은 **새 파일**로 짓고 `chapter_hud.gd`에는 여는 줄과 신호 연결만 둔다(파일이 1,730줄이다. 더 키우지 않는다).
- 시작 조건에 디렉터의 "T2-V 통과 뒤" 규칙(DIRECTOR-PLAN 2.8, 11-17 낮)이 걸리는지는 디렉터가 정한다. 게임 코드를 건드리지 않는 U0는 걸리지 않는다.

| 순서 | 단위 | 담당 | 고칠·만들 파일 | 먼저 있어야 할 것 |
|---|---|---|---|---|
| 0a | **목업 12장** | codex-operator | `_local/`만 | 디렉터 배정 |
| 0b | **U0 재질 키트** | codex-operator(생성) → asset-producer(`make_ui_kit.py`) → art-lead 검수 | `tools/art/make_ui_kit.py`, `_local/art/drafts/ui_kit/`, 통과 뒤 `chapter1/art/ui/kit_v01/` | 방향 결정(U-A1). 방향이 (가)가 아니면 6절 표를 그 안으로 다시 쓴다 |
| 0c | **U0b 원화 파생본** | character-artist | `tools/art/derive_witch_crops.py`, `chapter1/art/characters/derived/`(얼굴 512 원형용, 허리 위, 캐릭터 선택용 배경 K19) | 없음. A2 3-A와 같다 |
| 1 | **US 틀 한 곳** | ui-hud | 새 `view/hud/ui_style.gd`(역할별 스타일을 돌려주는 함수: `window`, `inset`, `button`, `button_primary`, `focus`, `divider`, `toggle`, `stepper`, `card_mother`, `card_pact`). 지금은 `_style()`과 같은 평평한 스타일을 돌려준다. `chapter_hud.gd`의 `_style()`·`_button()`이 이것을 부르게 하는 줄만 | D5-U 끝(같은 파일). 작고 빠르다. **D6-A2보다 먼저** |
| 2 | **L3 글꼴** | ui-hud(T3-L3) | T3-L3 그대로 | 사용자 승인 U-A2 |
| 3 | **U1 테마 입히기** | ui-hud | `ui_style.gd`가 K1~K3·K13·K14·K16을 쓰게, 새 `ui_theme.gd`(Theme: Button·OptionButton·CheckButton·PanelContainer·ScrollBar·Separator), 창 뒤 막과 비네트, `ui_motion.gd` | U0, US, (가능하면 L3) |
| 4 | **U2 전투 HUD** | ui-hud | `combat_bar.gd`(4.4 표), `chapter_hud.gd`의 위 왼쪽·목표·위 오른쪽·경로·우두머리·알림 | U1 |
| 5 | **U3 타이틀·메인 메뉴** | ui-hud | 새 `view/hud/title_screen.gd`, `chapter_hud.gd`(연결), `hud_dump.gd`(시점 추가) | U1, D4-U(종료 흐름), 결정 U-A3·U-A4·U-A5 |
| 6 | **U4 캐릭터 선택** | ui-hud | 새 `view/hud/character_select.gd`, `chapter_hud.gd`(지금 메뉴의 시작 단추 자리를 이 화면으로) | U3, U0b. 의상 칸은 저장(스키마 4) 전에는 기본 복장 하나 |
| 7 | **D6-A2 착용 창** | ui-hud | D6 10절대로 `equipment_window.gd` | D6 A1, D4-U·D5-U, **US**. U1이 먼저 끝났으면 처음부터 새 재질 |
| 8 | **U5 스킬 트리** | ui-hud | `skill_tree_panel.gd`(4.3 표) | U1. `chapter_hud.gd`를 건드리지 않으면 U4·D6-A2와 다른 작업 폴더에서 나란히 할 수 있다(디렉터 판단) |
| 9 | **U6 은총** | ui-hud | `chapter_hud.gd`의 `_growth_cards38()` 최종 진입점, 미리보기 검사 파일 하나 | U1, 어머니 자리 글(narrative-lead) |
| 10 | **U7 정지·결과** | ui-hud | `_build_modal()`·`_build_result40()` 최종 진입점 | U1, D4-U |
| 11 | **U8 설정** | ui-hud(화면) + gameplay-systems(`settings.cfg` 적용) | 새 `view/hud/settings_panel.gd`, T3-L5 | G5 범위 결정, design-lead 설정 명세, L3(언어 이름 글자) |
| 12 | **T3-L2** 기존 화면 글을 키로 | ui-hud | T3-L2 | 위 화면 묶음 전부 |

순서의 이유: 틀을 한 곳으로 모으는 US를 가장 먼저 두면, 그 뒤의 모든 화면(D6-A2 포함)이 재질을 "나중에 한 번에" 입는다. 글꼴(L3)을 테마보다 먼저 두면 캡처 판정을 최종 글꼴로 한 번만 한다. 전투 HUD를 메뉴보다 먼저 두는 것은 사람이 가장 오래 보는 화면이기 때문이다.

### 8.2 지금 도는 작업과 곧 시작할 작업에 붙일 규칙

D4-U(판 흐름 화면), D5-U(저장 거부 안내)는 돌고 있고 D6-A2(착용 창)는 곧 시작한다. 이 셋이 새 재질 키트를 나중에 입을 수 있게 **다섯 가지만** 지킨다. 디렉터가 각 지시서에 그대로 붙인다.

1. **틀을 직접 만들지 않는다.** `StyleBoxFlat.new()`, 테두리 두께·모서리 값을 새 화면 코드에 쓰지 않는다. D4-U·D5-U는 지금의 `_style()`·`_button()`만 쓴다. D6-A2는 US의 `ui_style.gd` 역할 함수만 쓴다(US가 먼저 끝난다).
2. **색은 `palette.gd` 토큰만.** 16진수 색 글자 금지(지금 규칙).
3. **글은 `Loc.t(key)`, 폭 고정 금지**(T3 2.7). 한 줄 글은 말줄임 + 툴팁.
4. **초점은 `ui_*` 동작으로, 모든 새 단추가 초점 목록에 든다.** 확인 창의 기본 초점은 [취소](D4-U), 저장 거부의 기본 초점은 [저장 없이 플레이](D5-U).
5. **휴대폰식 토글·선택 상자를 새로 쓰지 않는다.** 꼭 필요하면 버튼 둘이나 ‹ 값 › 단추로 둔다(나중에 K13·K14로 바뀐다).

### 8.3 단위마다 통과 기준

**모든 단위 공통**
- 캡처: 저장소 루트에서 `hud_dump.gd --shots`로 1920×1080과 1280×720. 같은 시드(11)·시점의 전후를 나란히. 전 캡처는 그 단위를 시작하기 직전에 새로 찍는다. 경로 `_local/shots/a4-<단위>/<before|after>/<계열>-<1080|720>/`.
- 키보드만으로 그 화면의 모든 단추에 닿고 되돌아올 수 있다(덤프의 초점 순서 목록을 보고서에 붙임). 마우스 없이 한 바퀴.
- 글자: 코드 14 미만 0건(검색 결과 첨부). 720p 캡처에서 가장 작은 글을 3배 확대해 붙인다.
- 가림(전투 화면 단위만): 판이 도는 캡처에서 가운데 60%에 표시 판 0. 판의 네 귀 좌표를 적는다.
- 번역: 가짜 언어 1.4배 캡처와 `check_overflow.py` 실패 0(T3-L4 도구가 있으면. 없으면 일부러 긴 글을 넣은 캡처 한 벌).
- 회귀: `python tools/dev/run_all.py --quick` 통과, 실행 로그 스크립트 오류 0, 골든 불변(표현만 바꿈).
- 색·틀: `chapter1/view/hud/` 안에서 16진수 색 글자가 `palette.gd` 밖에 0건, `StyleBoxFlat.new()`가 `ui_style.gd` 밖에 0건(US 이후).

**단위별 더할 것**

| 단위 | 통과 기준 |
|---|---|
| U0 | 대조 시트를 art-lead가 열어 봄: 한 금속 벌로 읽힘, 720p 크기에서 세공이 깨지지 않음, 자홍 테두리 0, 원장 기록, VRAM 합 6MB 이하 |
| US | 화면이 바뀌지 않는다: 전후 캡처가 픽셀 단위로 같거나 차이가 0.5% 이하(디렉터가 보는 비교 이미지 첨부). `ui_style.gd` 역할 목록 |
| U1 | 기본 Godot 위젯 모양(휴대폰식 토글, 선택 상자 화살표, 기본 구분선, 기본 스크롤 막대)이 모든 캡처에서 0개. 큰 창 모두 같은 K1, 단추·목록에는 장식 모서리 없음(모서리 200×200 잘라 모은 한 장). 720p에서 9분할 이음매 틈 0(3배 확대) |
| U2 | 세 계열 × 1080p, 냉기 × 720p, 화염 우두머리(`--until=21300`). 가운데 60% 침범 0. 레벨 명판 대비 4.5:1(픽셀 표본). 생명 30% 아래 캡처 한 장에서 흑백으로 바꿔도 구슬 틀의 밝기가 다르다. **성능**: qa-perf가 같은 시드·시점에서 HUD 동기화 시간 전후(T2-0b 계측), +0.1ms 이내. 판 전체 p95가 나빠지지 않음 |
| U3 | 메뉴 캡처에 판 안 표시(월드 글자, 위 왼쪽 판, 경로) 0. 저장 있음·없음 두 벌(격리 프로필). 메뉴 각 줄로 들어가고 돌아오기(덤프). 게임 종료 흐름이 D4의 것 그대로 |
| U4 | 세 마녀 × 두 해상도(`--select-witch=0|1|2`를 `hud_dump.gd`에 더함). 각 마녀로 시작한 덤프의 `primary`가 맞음(시작 콜백·순서 불변). 고른 마녀와 초점이 다른 것을 가리키는 화면 0(D2). 4.2절 원화 쓰기의 선 ①~④를 art-lead가 1080p에서 봄. 의상 칸 열고 닫기 캡처 |
| D6-A2 | D6 10절 기준 + 8.2절 다섯 규칙 |
| U5 | G1 미리보기 9장면 × 두 해상도(지금 도구). 상태 형태 규칙(점선·실선·이중·`+n`)이 흑백에서 그대로 읽힘. 화면에 채움 금색 덩어리가 초점 하나뿐(D13) |
| U6 | A2 지시서 4 통과 기준 + 화면 글에 "후원자"·"본래의" 0(결정 T3) |
| U7 | A2 지시서 5 통과 기준 + D4-U의 단추 콜백 그대로. 정지 창에 빈 판 영역이 창 넓이의 25% 이하 |
| U8 | T3-L5 기준 + 해상도 바꾸기 → 10초 되돌림 캡처 두 장. 설정 파일은 격리 경로(`Loc.configure`)만 |

---

## 9. 사용자 결정이 필요한 것

| # | 결정 | 선택지 | 권고 | 언제 |
|---|---|---|---|---|
| U-A1 | 화면 방향 | (가) 성유물함 / (나) 장정과 실 / (다) 화보 | **(가)**. 목업 12장을 본 뒤 정한다. A2 방향(결정 A4 "채택")을 바꾸는 결정이다 | 목업 뒤 |
| U-A2 | 글꼴 내려받기 승인과 제목 글꼴 | 승인 범위: 한국어만 / 한·중·일·라틴·키릴 전부. 제목: Noto Serif CJK 계열 / 마루 부리 / 함렛 | 전부(T3 L-U2와 같음), 제목은 **Noto Serif CJK 계열**(언어를 바꿔도 같은 인상) | 지금. U1 전 |
| U-A3 | 메인 메뉴 배경 | (ㄱ) 지금 원화 셋을 세로 띠로 / (ㄴ) 세 마녀가 함께 선 새 그림 한 장(Codex 생성, 추가 비용 없음, 같은 사람으로 보이게 맞추는 품이 큼) | **(ㄱ)로 먼저 짓고**, (ㄴ)은 출시 전 상점 그림과 함께 따로 정한다 | U3 전 |
| U-A4 | "새 게임"의 뜻 | (ㄱ) 1장에서는 숨기고 "이어 하기 / 시작"만 / (ㄴ) 저장 칸 셋(저장 구조가 바뀜, 스키마 4) / (ㄷ) 지금 저장을 보관하고 새로 시작(두 번 묻기) | **(ㄱ)**. 자리만 둔다. 저장 구조를 바꾸는 일은 화면 일이 아니다 | U3 전 |
| U-A5 | 로고 | (ㄱ) 고른 제목 글꼴로 만든 워드마크 그림 + 작은 장식 / (ㄴ) 따로 그린 로고(나중) | **(ㄱ)로 먼저**. "Witch Moira"를 라틴 글자로 둘지, 한글 표기를 함께 둘지(A2 결정 5)도 함께 | U3 전 |
| U-A6 | 캐릭터 선택의 원화 크기 | (ㄱ) 0.75배, 머리~무릎(720p 얼굴 약 72px) / (ㄴ) 0.62배 전신(얼굴 약 60px) / (ㄷ) 더 키워 허리 위(얼굴 90px 이상, 의상의 아래가 안 보임) | **(ㄱ)**. 의상 컬렉션을 보여 주는 화면이라 아래가 너무 잘리면 안 된다. 얼굴은 메달이 돕는다 | U4 캡처를 보고 |
| U-A7 | 전투 줄 판 | (ㄱ) 판을 거의 지우고 레일만(권고안) / (ㄴ) 얇은 판을 남김(A2) | **(ㄱ)**. 다만 바닥이 밝은 구역에서 칸이 떠 보이면 (ㄴ)로 돌아갈 수 있게 U2에서 두 벌을 찍는다 | U2 캡처를 보고 |
| U-A8 | 스팀 덱용 글자 | (ㄱ) 하한 14 그대로 / (ㄴ) 설정에 "글자 크게"(1.15배) / (ㄷ) 본문 하한을 16으로 올림 | **(ㄴ)**. 7인치 화면에서 11.2px는 작다. 다만 밸브의 덱 검증 기준의 글자 크기 수치는 확인하지 않았다(T4-D가 확인) | U8 전 |
| U-A9 | 의상의 위치 | (ㄱ) 캐릭터 선택 안의 칸(권고안) / (ㄴ) 따로 큰 "의상실" 화면 | **(ㄱ)**. 의상이 늘어 한 마녀에 8벌을 넘으면 (ㄴ)을 다시 본다 | U4 전 |

디렉터가 정할 것(사용자에게 올리지 않아도 되는 것): 목업 실행 배정, U0의 시작 시점(지금 가능), US를 D5-U 직후에 끼울지, U5를 다른 작업 폴더에서 나란히 할지, 각 단위에 T2-V 시작 조건을 걸지.

---

## 10. 확인하지 못한 것과 사람만 판단할 것

**확인하지 못한 것**
- 0.1절의 보지 않은 화면 전부. 특히 화염·번개의 이번 캡처, 우두머리 체력바, 생명 30% 아래, 장비가 많은 목록.
- Codex 내장 그림 생성의 가로 크기와 참조 여러 장 붙이기(5.2절). 지금까지 본 결과물은 세로 1024×1536뿐이다.
- 글꼴 라이선스(기억에 의존). Pretendard·마루 부리가 OFL인지, Noto 계열의 예약 글꼴 이름 조항.
- 지금 전투 줄이 매 프레임 `_draw()`를 다시 부르는지, 9분할 텍스처와 구슬 출렁임의 실제 비용.
- 720p의 작은 글(D8, D14)이 코드 14인데 화면에서 작게 보이는 이유(글꼴 탓인지, 크기 값이 다른지). 캡처를 눈으로만 봤고 코드 값을 대조하지 않았다.
- 4.2절의 얼굴 크기는 원화 얼굴이 원본 약 120px이라는 눈대중에서 계산했다. 재지 않았다.
- 스팀 덱 실기, 패드 입력, `aspect=expand`에서의 배치.
- 움직임과 소리 전부.

**사람만 판단할 것**(사용자 플레이와 감상으로만 채운다. 미평가)
- 세 목업 가운데 어느 쪽이 이 게임이라고 느껴지는가. (가)가 금박 화면처럼 과하게 보이지 않는가.
- 캐릭터 선택에서 원화가 "고르고 싶은 사람"으로 보이는가. 의상 칸이 그 매력을 더하는가.
- 전투 줄의 판을 지운 것이 "깔끔함"으로 읽히는가, "덜 만든 것"으로 읽히는가.
- QUALITY-TARGETS 5절 "화면 표시의 완성도"(참고 대상과의 비교).
