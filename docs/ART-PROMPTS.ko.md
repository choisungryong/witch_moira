# 일러스트 프롬프트 — 여악마 3명과 마녀 3명

2026-11-14. ChatGPT의 이미지 생성에 그대로 붙여 넣어 쓰는 프롬프트다. 인물 설정은 `SYSTEMS-DESIGN.ko.md` 2장의 임시안이며 이름·배경이 바뀌면 함께 고친다. 아직 한 장도 생성해 보지 않았으므로 결과를 보고 다듬어야 한다.

## 쓰는 법

1. 프롬프트는 영어로 썼다(이미지 모델이 영어 묘사를 더 안정적으로 따른다). 각 프롬프트 앞에 **공통 스타일**을 붙여서 넣는다.
2. 한 인물의 첫 장이 마음에 들면 그 이미지를 첨부하고 "같은 인물로"라고 요청해 나머지 구도(컷인, 초상)를 만든다. 인물의 일관성은 이 방법이 가장 잘 지켜진다.
3. 크기: 은총 화면·선택 화면용 세로 그림은 1024×1536, 필살기 컷인용 가로 그림은 1536×1024.
4. 배경은 단순하게 요청했다. 게임 화면에서 인물만 잘라 쓰기 쉽게 하기 위해서다.
5. 받은 파일은 `chapter1/art/` 아래 인물별 폴더에 프롬프트·모델·날짜를 적은 출처 파일과 함께 둔다(기존 `portrait41`의 방식).

모든 인물은 성인 여성이다. 노출은 과하지 않은 수준으로 적었다. 수위 기준이 정해지면 의상 문장을 조정한다.

## 공통 스타일

```
Dark fantasy character illustration for a gothic action RPG. Painterly semi-realistic
rendering, dramatic rim lighting, rich material detail on metal, cloth and skin,
muted desaturated palette with one strong accent color. Adult woman, mature face,
confident and alluring presence, elegant pose. Original character design.
Simple dark background with soft vignette and faint atmospheric haze, no text,
no logo, no watermark, no frame.
```

## 여악마(후원자) — 은총 화면용 세로 그림

여악마는 매혹적이고 위압적이어야 한다. 인간이 아니라는 표식(뿔, 눈, 피부의 균열, 꼬리)을 하나 이상 분명히 둔다.

### 잿불의 여악마

```
Full-body portrait, vertical composition. A demoness of embers and ash, adult woman
with obsidian-black curved horns and long ash-grey hair with glowing ember tips.
Her skin is pale with thin glowing cracks like cooling lava along her shoulders and
forearms. She wears an asymmetrical gown of charred black silk and blackened bronze
filigree, one shoulder bare, a high slit skirt, layered ash-veil trailing behind.
She leans on a tall iron censer hanging from a chain, smoke and sparks drifting up.
Half-lidded amber eyes, a knowing faint smile, as if offering a bargain.
Accent color: ember orange (#ff943d). Warm light from below, cold darkness above.
```

### 서리의 여악마

```
Full-body portrait, vertical composition. A demoness of frost and silence, adult
woman with slender backswept horns of translucent blue ice and straight silver-white
hair to her waist. Her skin is porcelain with faint frost patterns at the collarbone
and fingertips, pale glowing cyan eyes. She wears a fitted gown of white and
midnight-blue velvet with silver chains and a tall fur-and-crystal collar, open at
the neckline, long gloves, a sheer frost-lace train. She stands very still with one
hand raised, a single shard of ice floating above her palm, breath misting.
Serene, distant, almost tender expression. Accent color: glacial cyan (#9ce7ef).
Cold top light, soft blue rim light.
```

### 뇌우의 여악마

```
Full-body portrait, vertical composition. A demoness of storm and lightning, adult
woman with short swept-back dark indigo hair lifted by static, two small sharp horns
of dark metal, and violet eyes with a bright electric ring. Thin branching lightning
scars glow faintly along her arms and thighs. She wears a battle dress of dark
leather and storm-grey plates with brass conductor rods on the pauldrons, bare
midriff, torn half-cape whipping in the wind. She crouches forward on a broken
stone pillar, one hand gripping a crackling spear of raw lightning, grinning with
fierce delight. Accent color: pale electric violet-blue (#b9caff).
Hard flickering key light from the spear, deep shadows.
```

## 마녀(주인공) — 선택 화면용 세로 그림

주인공은 인간이다. 여악마보다 지쳐 있고 결연하다. 서약의 표식(손목이나 목의 낙인, 한쪽 눈의 색)이 여악마의 색으로 한 군데 드러난다.

### 잿불의 마녀

```
Full-body portrait, vertical composition. A human witch who survived the pyre, adult
woman in her late twenties with long dark auburn hair partly singed, soot on her
cheek, steady brown eyes, one iris flecked with ember orange. An old burn-scar
pattern circles her left wrist like a brand and glows faintly. She wears a
travel-worn dark red and black coat over a fitted corset bodice, charred hem,
leather straps and pouches, tall boots. She holds a staff of scorched wood topped
with a caged smoldering coal. Tired but defiant posture, chin raised.
Accent color: ember orange (#ff943d).
```

### 서리의 마녀

```
Full-body portrait, vertical composition. A human witch, the last sister of a frozen
abbey, adult woman in her late twenties with pale blonde hair in a loose braid,
grey eyes, one iris turned pale cyan. A frost-white sigil marks the side of her
neck. She wears a modified nun's habit in deep navy and off-white, the veil pushed
back, fitted waist, a fur-lined mantle over one shoulder, silver prayer chains
wrapped around her forearm. She holds a slender crystal-tipped staff close to her
chest. Calm, guarded expression, snowflakes settling on her shoulders.
Accent color: glacial cyan (#9ce7ef).
```

### 뇌우의 마녀

```
Full-body portrait, vertical composition. A human knight who woke after being struck
by lightning, adult woman around thirty with short black hair with one white streak,
sharp features, dark eyes, one iris ringed with electric violet. A branching
lightning scar runs from her right shoulder down her arm. She wears dented
half-plate armor over a dark gambeson, one arm unarmored and wrapped in copper
wire and cloth, a tattered blue sash at the hip. She rests a longsword with a
conductor-rod pommel on her shoulder. Wry half-smile, storm wind in her hair.
Accent color: pale electric violet-blue (#b9caff).
```

## 추가 구도(첫 장을 첨부한 뒤 요청)

- **필살기 컷인(가로 1536×1024, 여악마)**: `Same character. Wide cinematic close-up from the waist up, three-quarter view, she reaches toward the viewer as her power erupts around her, hair and cloth in violent motion, strong diagonal composition, background dissolving into pure accent-colored energy.`
- **초상(정사각 1024×1024, 주인공)**: `Same character. Bust portrait, facing slightly left, neutral dark background, soft key light, calm expression, suitable as a small HUD portrait.`
- **제단의 여악마(세로, 마을용)**: `Same character. Seated on a ruined altar, relaxed and watchful, candles around her, as if waiting for the witch to return.`

## 생성 방법 두 가지

| 방법 | 장점 | 주의 |
|---|---|---|
| ChatGPT에서 직접 | 첨부 이미지로 같은 인물 유지가 쉽다. 추가 비용이 없다 | 수작업으로 내려받아 폴더에 넣어야 한다 |
| API 스크립트 | 여러 장을 한 번에 만들고 출처 기록까지 자동화할 수 있다 | API 사용 요금이 든다. 모델 이름과 지원 크기는 실행 전에 공식 문서로 확인해야 한다. 키는 환경 변수로만 읽는다 |

API 스크립트는 요청하면 만든다. 실행은 예상 비용을 제시하고 승인받은 뒤에 한다.

## 받은 그림을 볼 때 확인할 것

- 여섯 명이 실루엣만으로 구분되는가.
- 여악마와 그와 서약한 마녀가 색과 표식으로 짝지어 보이는가.
- 계열 색이 게임 안 이펙트 색과 같은가.
- 손가락, 뿔의 좌우, 장신구의 개수 같은 생성 오류가 없는가.
- 잘라 쓸 때 머리·무기 끝이 화면 밖으로 잘리지 않았는가.
