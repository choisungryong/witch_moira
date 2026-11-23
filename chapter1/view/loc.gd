extends RefCounted
## Translation front door for the view layer (T3-L0a). Use through preload:
##   const Loc = preload("res://chapter1/view/loc.gd")
##   label.text = Loc.t("hud.dash.ready")
## Static only, no autoload. The core never calls this. Keys and rules: chapter1/i18n/README.ko.md.
## Signal: a static class cannot own a signal, so Loc.bus().locale_changed is the emitter.

class Bus extends RefCounted:
	signal locale_changed(code: String)

const LOCALES_PATH := "res://chapter1/i18n/locales.json"
const DEFAULT_SETTINGS_PATH := "user://settings.cfg"
const FALLBACK := "en"
const SOURCE_LOCALE := "ko"

## Steam game-language names to our locale codes (2.8).
const STEAM_LANGUAGES := {
	"koreana": "ko", "english": "en", "schinese": "zh_CN", "tchinese": "zh_TW", "japanese": "ja",
	"german": "de", "french": "fr", "spanish": "es", "latam": "es", "russian": "ru", "brazilian": "pt_BR",
}
## Decimal and thousands separators. Locales not listed use "." and ",".
const COMMA_DECIMAL := ["de", "es", "fr", "pt", "pt_BR", "ru", "it"]
const THOUSANDS := {"de": ".", "es": ".", "it": ".", "pt": ".", "pt_BR": ".", "fr": " ", "ru": " "}
## Josa pairs: any member written in a marker selects the pair. [with batchim, without, without-after-rieul or "" ]
const JOSA_PAIRS := {
	"을": ["을", "를"], "를": ["을", "를"],
	"이": ["이", "가"], "가": ["이", "가"],
	"은": ["은", "는"], "는": ["은", "는"],
	"와": ["과", "와"], "과": ["과", "와"],
	"으로": ["으로", "로"], "로": ["으로", "로"],
}
## Batchim of Latin letters by how they are read (L = el, M = em, N = en, R = al). The value true marks a final rieul.
const LATIN_BATCHIM := {"L": true, "M": false, "N": false, "R": true}
## Digits read in Korean: 0 yeong, 1 il, 3 sam, 6 yuk, 7 chil, 8 pal have batchim; 1, 7, 8 end in rieul.
const DIGIT_BATCHIM := {"0": false, "1": true, "3": false, "6": false, "7": true, "8": true}

static var _bus: Bus = Bus.new()
static var _locale := SOURCE_LOCALE
## False until the engine's language has been set to _locale once. The engine starts in the OS language,
## so without this Loc.locale() could say "ko" while TranslationServer still answers in English.
static var _engine_synced := false
static var _settings_path := DEFAULT_SETTINGS_PATH
static var _locale_table: Dictionary = {}
static var _fonts: Dictionary = {}
static var _josa_re: RegEx = null
static var _placeholder_re: RegEx = null

static func bus() -> Bus:
	return _bus

# ---- locale ----

static func locale_table() -> Dictionary:
	if _locale_table.is_empty():
		var file := FileAccess.open(LOCALES_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		_locale_table = parsed if parsed is Dictionary else {"shipping": [FALLBACK], "in_progress": []}
	return _locale_table

## Locales a player may pick. in_progress ones only in debug builds (2.8).
static func available_locales() -> Array[String]:
	var out: Array[String] = []
	var table := locale_table()
	for code in table.get("shipping", []):
		out.append(str(code))
	if OS.is_debug_build():
		for code in table.get("in_progress", []):
			out.append(str(code))
	return out

static func normalize(code: String) -> String:
	var fixed := code.strip_edges().replace("-", "_")
	if fixed.length() >= 2:
		var parts := fixed.split("_")
		fixed = parts[0].to_lower() + ("_" + parts[1].to_upper() if parts.size() > 1 else "")
	return fixed

## Returns the code actually in force. An unsupported code becomes "en". Emits locale_changed only on a real change.
static func set_locale(code: String) -> String:
	var wanted := normalize(code)
	var available := available_locales()
	if not available.has(wanted):
		var base := wanted.split("_")[0]
		wanted = base if available.has(base) else FALLBACK
	var changed := wanted != _locale
	_locale = wanted
	TranslationServer.set_locale(wanted)
	_engine_synced = true
	if changed:
		_bus.locale_changed.emit(wanted)
	return wanted

static func _sync_engine() -> void:
	if not _engine_synced:
		_engine_synced = true
		TranslationServer.set_locale(_locale)

static func locale() -> String:
	_sync_engine()
	return _locale

## Use an isolated settings file (tests under _local/ must call this first).
static func configure(settings_path: String) -> void:
	_settings_path = settings_path

## First-run order (2.8): saved choice, then Steam language, then OS language, then en.
static func resolve_initial(steam_language: String = "") -> String:
	var config := ConfigFile.new()
	if config.load(_settings_path) == OK:
		var saved := normalize(str(config.get_value("loc", "locale", "")))
		if available_locales().has(saved):
			return saved
	var steam: String = STEAM_LANGUAGES.get(steam_language, "")
	if steam != "" and available_locales().has(steam):
		return steam
	var os_code := normalize(OS.get_locale_language())
	if available_locales().has(os_code):
		return os_code
	return FALLBACK

static func init(steam_language: String = "") -> String:
	return set_locale(resolve_initial(steam_language))

## A player's menu choice. Saved and ahead of Steam from now on.
static func choose_locale(code: String) -> String:
	var applied := set_locale(code)
	var config := ConfigFile.new()
	config.load(_settings_path)
	config.set_value("loc", "locale", applied)
	config.save(_settings_path)
	return applied

# ---- text ----

## Missing in the active locale and in the fallback returns the key unchanged (the checks find those).
static func t(key: String, args: Dictionary = {}) -> String:
	_sync_engine()
	var text := TranslationServer.translate(key)
	if text == key:
		return key
	return _fill(text, args)

## Plural by count. Entries need msgid_plural (same key) in the .po.
## The engine rejects negative counts, so the form is chosen by |n|; {n} keeps the sign.
static func tn(key: String, n: int, args: Dictionary = {}) -> String:
	_sync_engine()
	var text := TranslationServer.translate_plural(key, key, absi(n))
	if text == key:
		return key
	var filled := args
	if not filled.has("n"):
		filled = args.duplicate()
		filled["n"] = num(n)
	return _fill(text, filled)

## One pass over {name} and {name|josa}. Each value goes in exactly once, so braces inside a value are
## never filled again. An argument that is missing leaves its placeholder text as it is.
static func _fill(text: String, args: Dictionary) -> String:
	if not text.contains("{"):
		return text
	var out := ""
	var cursor := 0
	for m in _placeholder_regex().search_all(text):
		out += text.substr(cursor, m.get_start() - cursor)
		cursor = m.get_end()
		var arg_name := m.get_string(1)
		if not args.has(arg_name):
			out += m.get_string(0)
			if OS.is_debug_build():
				push_warning("Loc: missing argument '%s' in: %s" % [arg_name, text])
			continue
		var value := str(args[arg_name])
		out += value
		var particle := m.get_string(2)
		if particle != "" and _locale == SOURCE_LOCALE:
			out += josa(value, particle)
	return out + text.substr(cursor)

# ---- numbers ----

static func _group(digits: String, sep: String) -> String:
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = sep + out
		out = digits[i] + out
		count += 1
	return out

static func num(value: int, loc: String = "") -> String:
	var code := _locale if loc == "" else loc
	var sep: String = THOUSANDS.get(code, THOUSANDS.get(code.split("_")[0], ","))
	var text := str(absi(value))
	return ("-" if value < 0 else "") + _group(text, sep)

static func dec(value: float, digits: int = 1, loc: String = "") -> String:
	var code := _locale if loc == "" else loc
	var base := code.split("_")[0]
	var fixed: String = ("%." + str(maxi(digits, 0)) + "f") % absf(value)
	var parts := fixed.split(".")
	var int_part := num(int(parts[0]), code)
	var comma := COMMA_DECIMAL.has(code) or COMMA_DECIMAL.has(base)
	var out := int_part
	if parts.size() > 1:
		out += ("," if comma else ".") + parts[1]
	if value < 0 and fixed.replace(".", "").lstrip("0") != "":
		out = "-" + out
	return out

## Whole numbers print without decimals, others with one. The sign stays in the text.
static func pct(value: float, loc: String = "") -> String:
	var whole := is_equal_approx(value, roundf(value))
	return dec(value, 0 if whole else 1, loc) + "%"

# ---- Korean josa ----

## Does the last sound of text carry a batchim? Returns [has_batchim, ends_in_rieul].
static func batchim(text: String) -> Array:
	var i := text.length() - 1
	while i >= 0:
		var c := text.unicode_at(i)
		var ch := text[i]
		if c >= 0xAC00 and c <= 0xD7A3:
			var jong := (c - 0xAC00) % 28
			return [jong != 0, jong == 8]
		if ch >= "0" and ch <= "9":
			return [DIGIT_BATCHIM.has(ch), DIGIT_BATCHIM.get(ch, false)]
		var up := ch.to_upper()
		if up >= "A" and up <= "Z":
			return [LATIN_BATCHIM.has(up), LATIN_BATCHIM.get(up, false)]
		i -= 1  # skip closing marks, spaces, punctuation
	return [false, false]

static func josa(name_: String, particle: String) -> String:
	if not JOSA_PAIRS.has(particle):
		return particle
	var pair: Array = JOSA_PAIRS[particle]
	var b := batchim(name_)
	if pair[0] == "으로":
		return "로" if (not b[0] or b[1]) else "으로"
	return pair[0] if b[0] else pair[1]

static func _josa_regex() -> RegEx:
	if _josa_re == null:
		_josa_re = RegEx.new()
		_josa_re.compile("\\{(\\w+)\\|([^}]+)\\}")
	return _josa_re

## Matches {name} and {name|josa}; group 2 is the josa. Outside ko the josa is dropped (lint() reports it),
## so a stray marker never reaches the screen as raw braces.
static func _placeholder_regex() -> RegEx:
	if _placeholder_re == null:
		_placeholder_re = RegEx.new()
		_placeholder_re.compile("\\{(\\w+)(?:\\|([^}]+))?\\}")
	return _placeholder_re

# ---- lint (used by checks, never at play time) ----

static func placeholders(text: String) -> Array[String]:
	var found: Array[String] = []
	var re := RegEx.new()
	re.compile("\\{(\\w+)(?:\\|[^}]+)?\\}")
	for m in re.search_all(text):
		var name_ := m.get_string(1)
		if not found.has(name_):
			found.append(name_)
	found.sort()
	return found

## Problems of one translated text for one locale: josa marker outside ko, printf holes, unbalanced braces.
static func lint(text: String, locale_code: String) -> Array[String]:
	var problems: Array[String] = []
	var normal := normalize(locale_code)
	if normal != SOURCE_LOCALE and _josa_regex().search(text) != null:
		problems.append("josa marker outside ko")
	var marker := RegEx.new()
	marker.compile("%[-+ 0#]*\\d*(?:\\.\\d+)?[sdfxXc]")
	if marker.search(text) != null:
		problems.append("positional placeholder (%d/%s); use {name}")
	if text.count("{") != text.count("}"):
		problems.append("unbalanced braces")
	return problems

# ---- fonts ----

## Bundled fonts (T3-L3). Variable fonts: the weight is picked with a FontVariation, not a second file.
## No system font is ever used (allow_system_fallback off), so every machine draws the same glyphs.
const FONT_BODY := "res://chapter1/art/fonts/PretendardVariable.ttf"
const FONT_HEADING := "res://chapter1/art/fonts/NotoSerifKR-VF.ttf"
## Role -> [file, wght, tabular digits]. body = text, bold = labels, number = fixed-width digits, heading = serif titles.
const FONT_ROLES := {
	"body": [FONT_BODY, 400.0, false],
	"bold": [FONT_BODY, 700.0, false],
	"number": [FONT_BODY, 600.0, true],
	"heading": [FONT_HEADING, 700.0, false],
	## A11 12.2: the descent's skill name, the same variable file at its heaviest weight (no new file).
	"heading_black": [FONT_HEADING, 900.0, false],
}

static func _font_file(path: String) -> FontFile:
	var f: FontFile = load(path)
	f.allow_system_fallback = false
	return f

static func _weighted(path: String, weight: float) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = _font_file(path)
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return f

## Role "body", "bold", "number" or "heading". Chain: the role's font, then the other bundled family, never the system.
## The chain is the same for every shipped locale until the CJK and Cyrillic families are added (per-locale chains go here).
static func font(role: String = "body") -> Font:
	if _fonts.has(role):
		return _fonts[role]
	var spec: Array = FONT_ROLES.get(role, FONT_ROLES["body"])
	var f := _weighted(String(spec[0]), float(spec[1]))
	if bool(spec[2]):
		f.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	var other: String = FONT_HEADING if String(spec[0]) == FONT_BODY else FONT_BODY
	f.fallbacks = [_weighted(other, float(spec[1]))]
	_fonts[role] = f
	return f
