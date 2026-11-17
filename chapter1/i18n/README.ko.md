# 번역 틀과 규칙

기준 문서: `docs/specs/T3-localization-directives-20261117.ko.md`. 이 폴더는 화면 글의 번역 파일이다. 코어는 이 폴더를 쓰지 않는다(코어는 id·키·숫자만 낸다).

## 파일

| 파일 | 내용 |
|---|---|
| `ko.po` | 한국어 원문. `msgid`가 키, `msgstr`이 원문. 손으로 쓰는 원본 |
| `en.po` | 영어. 키 집합은 `ko.po`와 같아야 한다 |
| `locales.json` | `shipping`(출시 언어), `in_progress`(개발 빌드에서만 메뉴에 보임), `names`(언어 이름, 그 언어 자체로) |

`.po`는 UTF-8, 줄바꿈 LF. 새 언어를 더하면 `project.godot`의 `internationalization/locale/translations`에도 올린다. 빠진 키는 `en`으로, `en`에도 없으면 키가 그대로 보인다.

`ui.example.*` 키는 틀의 시험용이다(`chapter1/tests/test_loc.gd`가 쓴다). 실제 화면 키가 생겨도 지우지 않는다.

## 코드에서 쓰기

```gdscript
const Loc = preload("res://chapter1/view/loc.gd")
label.text = Loc.t("hud.objective.seal_kills", {"done": Loc.num(done), "total": Loc.num(total)})
label.text = Loc.tn("result.kills", kills)          # 복수형. {n}은 자동으로 들어간다
Loc.bus().locale_changed.connect(_rebuild)          # 언어가 바뀌면 화면을 다시 짓는다
```

- 화면 코드는 명시적으로 `Loc.t`·`Loc.tn`만 부른다. 컨트롤의 자동 번역에 기대지 않는다(HUD 뿌리에서 `auto_translate_mode`를 끈다).
- 언어는 메뉴에서만 바꾼다. `Loc.choose_locale(code)`가 저장(`user://settings.cfg`)하고, 첫 실행은 `Loc.init(steam_language)`가 저장값 → 스팀 언어 → OS 언어 → `en` 순으로 정한다. 검사는 먼저 `Loc.configure("res://_local/...")`로 격리 경로를 준다.
- 글꼴은 `Loc.font("body")`·`Loc.font("heading")`. 언어별 체인은 L3에서 이 함수 안에서 바뀐다.

## 키 규칙(2.2절)

- 소문자, 낱말은 `_`, 층은 `.`. 첫 마디는 영역: `ui`, `hud`, `menu`, `stash`, `tree`, `result`, `notify`, `profile`, `world`, `item`, `skill`, `grace`, `enemy`, `zone`, `ritual`, `stat`, `unit`, `story`, `input`.
- 화면 글은 `<영역>.<화면 또는 부품>.<뜻>`. 뜻으로 이름 짓고 글 모양으로 짓지 않는다(`hud.dash.ready`이지 `hud.space_evade_ready`가 아니다).
- 데이터 글은 id에서 만든다(`item.base.<id>.name`, `skill.<id>.name`, `tree.<tree_id>.node.<node_id>.name` 등. 표는 지시서 2.2절). id의 `.`은 그대로 둔다. 키를 쪼개 쓰는 코드는 만들지 않는다.
- 동음이의는 키를 나눈다. `msgctxt`는 쓰지 않는다. 복수형만 `msgid_plural`(같은 키)을 쓴다.

## 틀 규칙(2.5절)

- 자리 표시자는 이름 있는 것만: `{name}`, `{n}`, `{done}`. `%d`·`%s`를 번역 글에 쓰지 않는다. `{n}`은 `tn`이 넣는다.
- 숫자는 화면이 먼저 글로 만든 뒤 넣는다: `Loc.num(1234)`, `Loc.dec(1.5, 1)`, `Loc.pct(12.5)`. 단위는 틀 안에 쓴다(`"{n}초"`, `"{n} s"`).
- 한국어 조사: 1순위는 자리 표시자 뒤에 조사가 오지 않게 문장을 짓는다(`처치 대상: {name}`). 꼭 필요하면 `ko.po` 안에서만 `{name|을}`을 쓴다. 쌍은 을/를, 이/가, 은/는, 와/과, 으로/로이고 쌍의 어느 쪽을 적어도 된다. ㄹ 받침은 "로"를 고른다. 숫자와 라틴 문자로 끝나는 이름은 읽는 소리로 판단한다(`Loc.batchim`의 표). 다른 언어의 `.po`에 `|` 표기가 있으면 오류다(`Loc.lint`).
- 영어: 수량이 붙는 글은 `tn`. 자리 표시자 앞에 관사를 쓰지 않는다(`Defeat {name}`). 이름 자체에 관사가 필요하면 이름 쪽 글에 넣는다.
- 줄바꿈은 번역 글 안에 둔다. 화면이 문장을 이어 붙여 한 줄을 만들지 않는다.
- 단축키 표기는 글에 박지 않고 `{key_interact}` 같은 자리 표시자로 둔다.
- 표시 글을 `replace()`로 고치지 않는다. 조건에 따라 다른 키를 고른다.

## 새 화면 규칙

1. 화면에 보이는 모든 글은 키로 쓴다. 한국어 리터럴을 새로 만들지 않는다.
2. 글이 든 컨트롤에 고정 폭을 주지 않는다. 한 줄 글은 `OVERRUN_TRIM_ELLIPSIS` + 툴팁, 설명은 `AUTOWRAP_WORD_SMART`. 한국어 대비 가로 2배까지 견디게 짓는다.
3. 글자 수 상한이 필요한 키는 `.po`에 `#. max: 18` 주석으로 적는다.
4. 키를 더하면 `ko.po`와 `en.po`에 함께 더한다. `en.po`의 `msgstr`은 비어 있으면 안 된다(영어 초벌을 함께 넣는다. 검사가 잡는다). 각 항목 위에 `#.` 주석으로 자리 표시자의 뜻을 적는다.
5. 코어에서 받는 것은 id·키·숫자뿐이다. 사람이 읽는 글을 코어에 요구하지 않는다.
6. 저장 파일에 번역된 글을 넣지 않는다.

## 코어가 내는 것과 화면이 짓는 글

코어는 글을 만들지 않는다. 화면이 아래 키로 글을 만든다(T3-L1, 2026-11-17).

| 코어가 내는 것 | 화면이 쓰는 키 |
|---|---|
| 구역 번호 `zone` (이벤트 `gate_opened`, `zone_entered`, `objective().zone`) | `zone.<n>.name` |
| 수호자 `title_key`(= `enemy.champion.<zone>.name`), 이벤트 `chapter_champion.zone` | 그 키 그대로 |
| 의식 `id` (이벤트 `ritual_started/completed`, `RITUALS[].id`) | `ritual.<id>.name` |
| `objective()` = `{zone, kind, done, total, hp, hp_max, title_key, ...}` | `kind`가 `move`이면 `hud.objective.move`, `seal_kills`이면 `hud.objective.seal_kills`({done}, {total}), `champion`이면 `hp / hp_max`와 `title_key` |
| 은총 카드 `title_key`, `effective_skill().name_key` | `skill.<id>.name`, `skill.<id>.evolved_name`, `grace.passive.<id>.name` |
| `SkillTree.describe_keys()` = `[{key, args}]` | `Loc.t(key, args)`. `view/hud/tree_text.gd`가 줄을 만든다 |
| `stat_sheet()` 줄 `{id, unit_id, ...}`, 효과 `{source_uid, kind, id}` | `stat.<id>.label`, `unit.<unit_id>` |
| 저장 거부 `profile.error_code`와 `error_args` | `profile.error.<code>` (`error`는 개발용 문장으로 남는다) |

코어 쪽 파일이 `Loc`·`TranslationServer`·`tr(`·`res://chapter1/view`를 부르면 `tools/dev/i18n_scan.py`가 실패한다. 코어 출력에 한글이 새는지는 `chapter1/tests/test_core_text.gd`가 본다(장비 사전의 `name`·`description`만 T3-S까지 허용).

## 검사

`godot --headless --path . --script res://chapter1/tests/test_loc.gd` → 마커 `CHAPTER1_LOC_RESULT`. `ko.po`·`en.po`의 키 일치, 자리 표시자 일치, 조사 표기 규칙까지 본다.
