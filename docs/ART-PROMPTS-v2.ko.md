# 원화 프롬프트 v2 — 전원 새로 그리기

2026-11-15. 여섯 명을 처음부터 다시 그리기 위한 프롬프트다. 각 블록은 그것만 붙여 넣으면 되도록 화풍 문장을 포함한다. 이전 판은 `ART-PROMPTS.ko.md`.

## 쓰는 법

- 한 명에 새 대화 하나. 블록 전체를 그대로 붙여 넣는다.
- 첫 장(서리 마녀)이 마음에 들면, 나머지를 그릴 때 그 그림을 첨부하고 맨 앞에 `Match the painting style, lighting and level of finish of the attached image. Do not copy the character.`를 한 줄 더한다.
- 거절되면: 새 대화에서 다시 시도하고, 노출 문장(`Outfit coverage:` 줄)만 한 단계 낮춘다. 비치는 옷이 나온 그림은 첨부하지 않는다.
- 노출 수준은 `Outfit coverage:` 줄 하나로 조절한다. 사용자가 정한 기준은 "15세 등급 게임 수준"이다(아래 표의 기본). 특정 게임의 캐릭터나 의상을 따라 그리게 하지 않고, 수준만 맞춘다.

| 수준 | `Outfit coverage:` 줄 |
|---|---|
| 낮음 | `Outfit coverage: elegant and fitted, shoulders and collarbone bare, a high leg slit, everything else covered in opaque fabric.` |
| 중간 | `Outfit coverage: bare shoulders, bare midriff and one bare thigh through a high slit; chest and hips fully covered in opaque fabric and armor pieces; tasteful, no nudity, nothing sheer.` |
| **확정(기본, 사용자 결정 2026-11-16: 서리 마녀 시안으로 확인)** | `Outfit coverage: a fantasy bikini-armor silhouette — an opaque structured bodice and opaque hip piece with long flowing fabric panels, bare arms, midriff and legs; tasteful, no nudity. Make only the cape and the trailing skirt panels semi-sheer gauze; keep the bodice and the hip piece fully opaque leather.` |
| 높음 | `Outfit coverage: a fantasy bikini-armor silhouette — an opaque structured bodice and opaque hip piece with long flowing fabric panels, bare arms, midriff and legs; tasteful, no nudity, nothing sheer.` |

## 화풍 바꾸기 (선택)

기본은 반실사 회화풍이다. 사용자가 2026-11-15에 보낸 참고 그림처럼 **모바일 게임 캐릭터 일러스트풍**으로 그리려면, 각 블록 첫 문단의 `Semi-realistic painterly dark-fantasy illustration, high finish, ... rim lighting, dark ... background of ..., single accent color: ...` 부분을 아래 문장으로 바꾼다(강조색만 캐릭터에 맞게 적는다).

```
Polished anime-style mobile game character illustration, clean confident line art, smooth cel shading with soft gradients and glossy highlights on hair and skin, tall elegant proportions with very long legs, standing full-body pose on a plain flat dark charcoal background with no scenery, single accent color: <강조색>.
```

배경이 단색이면 게임에서 잘라 쓰기 쉽다(초상, 선택 화면, 컷인).

## 확정된 기준 (2026-11-16)

- 서리 마녀 시안(불투명 상의·골반 가리개, 망토와 치맛자락만 반투명 거즈, 굽 높은 부츠)이 기준이다.
- 비치는 범위는 망토와 늘어지는 자락까지만이다. 상의와 골반 가리개는 불투명 가죽으로 둔다.
- 굽 높은 신발은 그대로 둔다.

## 설정 요약

- 마녀 셋은 **인간**이다. 뿔·꼬리·날개가 없다. 후원자에게 빌린 힘은 한쪽 팔과 눈, 몸의 문양으로만 드러난다.
- 후원자 셋은 **여악마**다. 뿔이 있고 사람보다 크고 위압적이다. 자기 마녀와 색과 문양을 공유한다.
- 전원 성인(20대 후반~30대). 자세는 여섯 장이 모두 다르다.

---

## 1. 서리 마녀 (주인공, 냉기)

```
Full-body character concept art of an adult woman in her late twenties, a human frost witch. Semi-realistic painterly dark-fantasy illustration, high finish, soft rim lighting, dark muted background of a ruined stone cloister with drifting snow, single accent color: icy cyan. Vertical 2:3.

She is fully human: no horns, no tail, no wings. Long silver-white hair in a loose side braid, pale skin, calm and slightly melancholic face, pale blue eyes; her left eye glows faintly cyan. Her left forearm and hand are coated in translucent blue frost-crystal, like a gauntlet of ice, with thin frost veins climbing to the shoulder — the mark of a borrowed power.

Outfit: dark navy and silver witch attire — a structured corset bodice with silver filigree, a long asymmetric skirt of layered dark fabric, a short fur-trimmed capelet, thigh-high stiletto-heeled boots, a silver chain belt with a small sealed ice lantern.
Outfit coverage: a fantasy bikini-armor silhouette — an opaque structured bodice and opaque hip piece with long flowing fabric panels, bare arms, midriff and legs; tasteful, no nudity. Make only the cape and the trailing skirt panels semi-sheer gauze; keep the bodice and the hip piece fully opaque leather.

Pose: relaxed contrapposto, weight on one hip, right hand resting on her hip, frozen left hand raised at shoulder height with a small rotating snowflake sigil above the palm, head tilted slightly, looking at the viewer with a quiet confident half-smile.
Clear readable silhouette, whole figure visible head to toe, no text, no watermark.
```

## 2. 잿불 마녀 (주인공, 화염)

```
Full-body character concept art of an adult woman in her late twenties, a human ember witch. Semi-realistic painterly dark-fantasy illustration, high finish, warm rim lighting, dark muted background of a burned chapel with floating embers, single accent color: molten orange. Vertical 2:3.

She is fully human: no horns, no tail, no wings. Shoulder-length dark auburn hair with a few glowing ember-tipped strands, warm tan skin with a light dusting of ash, bold amused expression, amber eyes; her right eye glows faintly orange. Her right arm from fingertips to elbow looks like cracked cooling charcoal with molten light in the cracks — the mark of a borrowed power.

Outfit: black and deep crimson witch attire with brass fittings — a fitted halter bodice of layered leather, a short asymmetric wrap skirt with a long trailing sash scorched at the edges, one brass pauldron, fingerless glove on the left hand, knee-high boots, a brass censer hanging from her belt on a chain.
Outfit coverage: a fantasy bikini-armor silhouette — an opaque structured bodice and opaque hip piece with long flowing fabric panels, bare arms, midriff and legs; tasteful, no nudity. Make only the cape and the trailing skirt panels semi-sheer gauze; keep the bodice and the hip piece fully opaque leather.

Pose: dynamic three-quarter view, mid-stride walking toward the viewer, charcoal right hand lowered at her side trailing a ribbon of fire, left hand flicking her hair back, chin up, a daring grin.
Clear readable silhouette, whole figure visible head to toe, no text, no watermark.
```

## 3. 뇌우 마녀 (주인공, 번개)

```
Full-body character concept art of an adult woman in her early twenties, a human storm witch. Semi-realistic painterly dark-fantasy illustration, high finish, cool rim lighting, dark muted background of a broken bell tower under storm clouds, single accent color: pale violet-blue lightning. Vertical 2:3.

She is fully human: no horns, no tail, no wings. Short platinum-blonde hair swept to one side and lifted as if by static, fair skin, sharp focused expression, grey eyes; both pupils flash faintly violet. Branching lightning-scar patterns (Lichtenberg figures) glow softly along both forearms and up one side of her neck — the mark of a borrowed power.

Outfit: slate grey and indigo witch attire with polished steel accents — a high-collared sleeveless fitted top, a long open-front coat-skirt split to the hip and blowing in the wind, steel bracers, a wide belt holding small bronze bells, fitted leggings on one leg, tall boots.
Outfit coverage: a fantasy bikini-armor silhouette — an opaque structured bodice and opaque hip piece with long flowing fabric panels, bare arms, midriff and legs; tasteful, no nudity. Make only the cape and the trailing skirt panels semi-sheer gauze; keep the bodice and the hip piece fully opaque leather.

Pose: seen slightly from below, standing on a broken ledge with feet apart, one arm stretched straight up drawing a thin bolt of lightning down to her fingertips, the other hand gathering her coat against the wind, looking down at the viewer over her shoulder with a cool challenging gaze.
Clear readable silhouette, whole figure visible head to toe, no text, no watermark.
```

## 4. 서리의 여악마 (후원자, 냉기)

```
Full-body character concept art of an adult demoness, the frost patron of a witch. Semi-realistic painterly dark-fantasy illustration, high finish, cold rim lighting, dark background of a frozen throne hall with hanging icicles, single accent color: icy cyan. Vertical 2:3.

She is clearly not human: tall and statuesque, pale blue-grey skin, two long backward-curving horns of clear ice, long straight white hair reaching her knees, fully glowing cyan eyes without pupils, frost-crystal claws on both hands, a faint cold mist falling from her shoulders. Regal, serene, faintly cruel expression.

Outfit: a queenly gown of midnight blue and silver — a sculpted silver breastplate-bodice, a tall ice-crystal collar, a long heavy skirt open at the front, silver chains across the hips, an ice crown fused with her horns, bare feet standing on frost.
Outfit coverage: a fantasy bikini-armor silhouette — an opaque structured bodice and opaque hip piece with long flowing fabric panels, bare arms, midriff and legs; tasteful, no nudity. Make only the cape and the trailing skirt panels semi-sheer gauze; keep the bodice and the hip piece fully opaque leather.

Pose: seated sideways on a throne of ice, legs crossed, chin resting on the back of one clawed hand, the other hand idly holding a small frozen flame, looking down at the viewer as if weighing a bargain.
Clear readable silhouette, whole figure visible, no text, no watermark.
```

## 5. 잿불의 여악마 (후원자, 화염)

```
Full-body character concept art of an adult demoness, the ember patron of a witch. Semi-realistic painterly dark-fantasy illustration, high finish, hot rim lighting from below, dark background of a volcanic altar with drifting ash, single accent color: molten orange. Vertical 2:3.

She is clearly not human: tall and powerful, charcoal-dark skin with glowing molten cracks along her arms and legs, two large upward-sweeping horns like cooled lava with glowing tips, long hair that turns into slow-burning embers at the ends, fully glowing orange eyes, a long thin tail ending in a small flame. Proud, playful, dangerous smile.

Outfit: black iron and deep red silk — a forged iron bodice shaped like overlapping scales, a low iron hip belt with a long red silk loincloth-style panel front and back, a thin magma-lit veil hanging from her horns down her back, iron bangles, bare feet with ember-lit claws.
Outfit coverage: a fantasy bikini-armor silhouette — an opaque structured bodice and opaque hip piece with long flowing fabric panels, bare arms, midriff and legs; tasteful, no nudity. Make only the cape and the trailing skirt panels semi-sheer gauze; keep the bodice and the hip piece fully opaque leather.

Pose: leaning forward toward the viewer with one hand on her knee and the other extended palm-up offering a floating burning coal, tail curled behind her, head tilted with an inviting, mocking grin.
Clear readable silhouette, whole figure visible, no text, no watermark.
```

## 6. 뇌우의 여악마 (후원자, 번개)

```
Full-body character concept art of an adult demoness, the storm patron of a witch. Semi-realistic painterly dark-fantasy illustration, high finish, flickering cool rim lighting, dark background of storm clouds seen from above a ruined spire, single accent color: pale violet-blue lightning. Vertical 2:3.

She is clearly not human: lean and elegant, dusky slate-violet skin, two slender antler-like horns that branch like lightning and glow at the tips, wild long dark-indigo hair floating upward, fully glowing violet-white eyes, a pair of ragged cloud-like wings of dark mist, small sparks crawling over her skin. Wild, delighted, unpredictable expression.

Outfit: indigo and storm-grey with bright steel — a strapless fitted steel-plate bodice, long detached sleeves torn at the ends, a short layered skirt of feather-like dark fabric with long trailing ribbons, steel anklets with tiny bells, bare feet.
Outfit coverage: a fantasy bikini-armor silhouette — an opaque structured bodice and opaque hip piece with long flowing fabric panels, bare arms, midriff and legs; tasteful, no nudity. Make only the cape and the trailing skirt panels semi-sheer gauze; keep the bodice and the hip piece fully opaque leather.

Pose: hovering in mid-air, body arched in a relaxed weightless curve, one knee drawn up, both arms spread wide with thin lightning strung between her fingers like a cat's cradle, laughing as she looks down at the viewer.
Clear readable silhouette, whole figure visible, no text, no watermark.
```

---

## 그린 뒤

- 파일은 `chapter1/art/characters/`에 `frost_witch_v02.png`처럼 새 이름으로 넣는다. 기존 v01은 지우지 않는다.
- 여섯 장이 모이면 아트 관리자가 한 세트로 일관되는지(화풍, 마녀와 후원자의 짝, 실루엣) 검수한다.
