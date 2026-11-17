extends SceneTree
## T3-L0a checks of view/loc.gd and the i18n files. Uses an isolated settings file under _local/.
const Loc = preload("res://chapter1/view/loc.gd")
const SETTINGS := "res://_local/test-loc/settings.cfg"
var checks := 0
var failures: Array[String] = []
var signals: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func eq(got: Variant, want: Variant, label: String) -> void:
	check(got == want, "%s (got %s, want %s)" % [label, str(got), str(want)])

func _on_locale(code: String) -> void:
	signals.append(code)

func _initialize() -> void:
	# ---- A1: the engine starts in another language (an English OS); Loc must still answer in its own
	TranslationServer.set_locale("en_US")
	eq(Loc.locale(), "ko", "first use: Loc.locale() is ko")
	eq(Loc.t("ui.example.plain"), "예시 글", "first use with engine in en_US: text follows Loc's ko")
	eq(TranslationServer.get_locale().substr(0, 2), "ko", "engine language was aligned to Loc")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_local/test-loc"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	Loc.configure(SETTINGS)
	Loc.bus().locale_changed.connect(_on_locale)

	# ---- locale switch and signal
	Loc.set_locale("ko")
	signals.clear()
	eq(Loc.set_locale("en"), "en", "set_locale en")
	eq(Loc.locale(), "en", "locale() after set")
	eq(signals, ["en"], "set_locale emits locale_changed once")
	Loc.set_locale("en")
	eq(signals.size(), 1, "same locale does not emit again")
	eq(Loc.set_locale("xx"), "en", "unsupported locale becomes en")
	eq(Loc.set_locale("ko-KR"), "ko", "ko-KR maps to ko")
	eq(signals, ["en", "ko"], "signal order en then ko")

	# ---- key translation
	Loc.set_locale("ko")
	eq(Loc.t("ui.example.plain"), "예시 글", "ko plain")
	Loc.set_locale("en")
	eq(Loc.t("ui.example.plain"), "Example text", "en plain")
	eq(Loc.t("ui.example.no_such_key"), "ui.example.no_such_key", "missing key comes back as the key")
	eq(Loc.t("ui.example.no_such_key", {"name": "x"}), "ui.example.no_such_key", "missing key is not formatted")

	# ---- fallback to en for a key only en has (added at runtime so the shipped .po stay in step)
	var only_en := Translation.new()
	only_en.locale = "en"
	only_en.add_message("ui.example.en_only", "English only")
	TranslationServer.add_translation(only_en)
	Loc.set_locale("ko")
	eq(Loc.t("ui.example.en_only"), "English only", "ko falls back to en")
	TranslationServer.remove_translation(only_en)

	# ---- placeholders
	Loc.set_locale("en")
	eq(Loc.t("ui.example.greeting", {"name": "Moira"}), "Welcome, Moira", "en {name}")
	eq(Loc.t("ui.example.start_with", {"name": "Arc", "rank": 2}), "Start with Arc (rank 2)", "en two placeholders")
	Loc.set_locale("ko")
	eq(Loc.t("ui.example.greeting", {"name": "모이라"}), "모이라, 어서 오세요", "ko {name}")

	# ---- plural
	Loc.set_locale("en")
	eq(Loc.tn("ui.example.kills", 1), "1 kill", "en tn 1")
	eq(Loc.tn("ui.example.kills", 2), "2 kills", "en tn 2")
	eq(Loc.tn("ui.example.kills", 0), "0 kills", "en tn 0")
	eq(Loc.tn("ui.example.kills", 1234), "1,234 kills", "en tn groups digits")
	Loc.set_locale("ko")
	eq(Loc.tn("ui.example.kills", 1), "1마리 처치", "ko tn 1")
	eq(Loc.tn("ui.example.kills", 5), "5마리 처치", "ko tn 5")
	eq(Loc.tn("ui.example.nope", 3), "ui.example.nope", "tn missing key")

	# ---- josa table: [text, particle, want]
	var table := [
		["성가대장", "을", "성가대장을"], ["서리창", "을", "서리창을"], ["모이라", "을", "모이라를"],
		["성가대장", "이", "성가대장이"], ["모이라", "가", "모이라가"],
		["성가대장", "은", "성가대장은"], ["모이라", "는", "모이라는"],
		["서리창", "와", "서리창과"], ["모이라", "와", "모이라와"],
		["서리창", "으로", "서리창으로"], ["모이라", "으로", "모이라로"],
		["연쇄 전류", "으로", "연쇄 전류로"],  # ㄹ final: rieul takes 로
		["회랑의 파수왕", "을", "회랑의 파수왕을"],
		["서리의 성가대장", "를", "서리의 성가대장을"],  # either member of the pair selects it
		["얼음", "로", "얼음으로"], ["불", "으로", "불로"],
		["랭크 2", "으로", "랭크 2로"], ["랭크 0", "을", "랭크 0을"], ["랭크 1", "이", "랭크 1이"],
		["랭크 3", "은", "랭크 3은"], ["랭크 4", "은", "랭크 4는"], ["랭크 5", "을", "랭크 5를"],
		["랭크 6", "을", "랭크 6을"], ["랭크 7", "으로", "랭크 7로"], ["랭크 8", "으로", "랭크 8로"],
		["랭크 9", "이", "랭크 9가"], ["랭크 6", "으로", "랭크 6으로"], ["랭크 0", "으로", "랭크 0으로"],
		["Arc", "을", "Arc를"], ["Wall", "을", "Wall을"], ["Gem", "이", "Gem이"], ["Moon", "은", "Moon은"],
		["Fire", "으로", "Fire로"], ["Star", "으로", "Star로"], ["Sun", "을", "Sun을"],
		["노드(A)", "을", "노드(A)를"],  # closing mark skipped
	]
	for row in table:
		eq(row[0] + Loc.josa(row[0], row[1]), row[2], "josa %s + %s" % [row[0], row[1]])
	Loc.set_locale("ko")
	eq(Loc.t("ui.example.defeat", {"name": "서리의 성가대장"}), "서리의 성가대장을 처치하세요", "ko marker with batchim")
	eq(Loc.t("ui.example.defeat", {"name": "모이라"}), "모이라를 처치하세요", "ko marker without batchim")
	eq(Loc.t("ui.example.start_with", {"name": "연쇄 전류", "rank": 1}), "연쇄 전류로 시작 (랭크 1)", "ko 으로/로 with rieul")
	eq(Loc.t("ui.example.start_with", {"name": "서리창", "rank": 2}), "서리창으로 시작 (랭크 2)", "ko 으로 with batchim")

	# ---- A2: one pass; braces inside values are not filled again; a missing argument keeps its placeholder
	Loc.set_locale("ko")
	eq(Loc.t("ui.example.start_with", {"name": "{rank}", "rank": 3}), "{rank}로 시작 (랭크 3)", "value with braces is not substituted twice")
	eq(Loc.t("ui.example.defeat", {}), "{name|을} 처치하세요", "missing argument leaves the josa placeholder")
	eq(Loc.t("ui.example.start_with", {"rank": 2}), "{name|으로} 시작 (랭크 2)", "one missing argument, the other still filled")
	Loc.set_locale("en")
	eq(Loc.t("ui.example.greeting", {"name": "{name}"}), "Welcome, {name}", "en value that looks like its own placeholder")
	eq(Loc.t("ui.example.greeting"), "Welcome, {name}", "en no args leaves the placeholder")

	# ---- A8: a negative count must not raise an engine error; the form follows |n|
	eq(Loc.tn("ui.example.kills", -1), "-1 kill", "en tn -1 uses the singular form")
	eq(Loc.tn("ui.example.kills", -5), "-5 kills", "en tn -5 uses the plural form")
	Loc.set_locale("ko")
	eq(Loc.tn("ui.example.kills", -3), "-3마리 처치", "ko tn -3")

	# ---- josa marker in another locale is rejected
	check(Loc.lint("{name|을} 처치", "en").has("josa marker outside ko"), "lint rejects josa marker in en")
	check(Loc.lint("{name|을} 처치", "ja").has("josa marker outside ko"), "lint rejects josa marker in ja")
	check(Loc.lint("{name|을} 처치", "ko").is_empty(), "lint accepts josa marker in ko")
	check(Loc.lint("Defeat {name}", "en").is_empty(), "lint accepts a plain template")
	check(not Loc.lint("Defeat %s", "en").is_empty(), "lint rejects %s")
	check(not Loc.lint("Defeat {name", "en").is_empty(), "lint rejects unbalanced braces")
	Loc.set_locale("en")
	eq(Loc.t("ui.example.defeat", {"name": "Ember Warden"}), "Defeat Ember Warden", "shipped en text has no marker")
	eq(Loc.placeholders("{name|을} {n} {name}"), ["n", "name"], "placeholders ignore josa suffix and duplicates")

	# ---- the shipped .po files agree on keys, placeholders and markers
	var ko_keys := po_entries("res://chapter1/i18n/ko.po")
	var en_keys := po_entries("res://chapter1/i18n/en.po")
	check(not ko_keys.is_empty(), "ko.po has entries")
	var ko_names: Array = ko_keys.keys()
	ko_names.sort()
	var en_names: Array = en_keys.keys()
	en_names.sort()
	eq(en_names, ko_names, "en.po has exactly the keys of ko.po")
	for key in ko_keys:
		if not en_keys.has(key):
			continue
		check(not en_keys[key].is_empty() and not ko_keys[key].is_empty(), "both languages have a form: " + key)
		for i in en_keys[key].size():
			# ko has one plural form, so every en form is compared with ko's form (the last one when ko has fewer)
			var ko_form: String = ko_keys[key][mini(i, ko_keys[key].size() - 1)]
			eq(Loc.placeholders(en_keys[key][i]), Loc.placeholders(ko_form), "placeholders match for %s form %d" % [key, i])
		for text in en_keys[key]:
			check(text != "", "en msgstr not empty: " + key)
			check(Loc.lint(text, "en").is_empty(), "en lint clean: " + key)
		for text in ko_keys[key]:
			check(Loc.lint(text, "ko").is_empty(), "ko lint clean: " + key)
	var locales := read_json("res://chapter1/i18n/locales.json")
	check(locales.get("shipping", []).has("ko") and locales.get("shipping", []).has("en"), "locales.json ships ko and en")

	# ---- number formats (locale argument stands in for a locale with no .po yet)
	eq(Loc.num(1234567, "ko"), "1,234,567", "ko grouping")
	eq(Loc.num(1234567, "en"), "1,234,567", "en grouping")
	eq(Loc.num(1234567, "de"), "1.234.567", "de grouping")
	eq(Loc.num(1234567, "fr"), "1 234 567", "fr grouping")
	eq(Loc.num(999, "de"), "999", "no separator under 1000")
	eq(Loc.num(1000, "de"), "1.000", "de 1000")
	eq(Loc.num(-12345, "en"), "-12,345", "negative")
	eq(Loc.num(0, "en"), "0", "zero")
	eq(Loc.dec(1234.5, 1, "en"), "1,234.5", "en decimal")
	eq(Loc.dec(1234.5, 1, "de"), "1.234,5", "de decimal")
	eq(Loc.dec(1.25, 2, "fr"), "1,25", "fr decimal")
	eq(Loc.dec(3.0, 0, "en"), "3", "dec 0 digits")
	eq(Loc.dec(-0.04, 1, "en"), "0.0", "tiny negative has no sign")
	eq(Loc.dec(-1.5, 1, "en"), "-1.5", "negative decimal")
	Loc.set_locale("en")
	eq(Loc.pct(12.5), "12.5%", "pct fraction")
	eq(Loc.pct(12.0), "12%", "pct whole")
	eq(Loc.num(4500), "4,500", "num uses the active locale")

	# ---- settings and first-run order
	Loc.configure(SETTINGS)
	eq(Loc.resolve_initial("koreana"), "ko", "steam language when nothing is saved")
	eq(Loc.resolve_initial("english"), "en", "steam english")
	Loc.choose_locale("en")
	eq(Loc.resolve_initial("koreana"), "en", "saved choice beats steam")
	var config := ConfigFile.new()
	eq(config.load(SETTINGS), OK, "settings file written in the isolated path")
	eq(str(config.get_value("loc", "locale", "")), "en", "settings file holds the choice")

	# ---- font roles
	check(Loc.font("body") is Font and Loc.font("heading") is Font, "font roles return fonts")
	check(Loc.font("body") != Loc.font("heading"), "body and heading differ")

	Loc.set_locale("ko")
	print("CHAPTER1_LOC_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if not failures.is_empty() else 0)

func read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed if parsed is Dictionary else {}

## Minimal .po reader: key -> array of msgstr values. Skips the header.
func po_entries(path: String) -> Dictionary:
	var out := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	var key := ""
	var current := ""
	var mode := ""
	for raw in file.get_as_text().split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("msgid_plural"):
			mode = "skip"
		elif line.begins_with("msgid"):
			key = unquote(line.substr(5))
			mode = "id"
		elif line.begins_with("msgstr"):
			if key != "":
				out[key] = out.get(key, [])
				out[key].append(unquote(line.substr(line.find(" ") + 1)))
			current = key
			mode = "str"
		elif line.begins_with("\"") and mode == "id":
			key += unquote(line)
		elif line.begins_with("\"") and mode == "str" and current != "":
			out[current][out[current].size() - 1] += unquote(line)
	return out

func unquote(text: String) -> String:
	var s := text.strip_edges()
	if s.length() >= 2 and s.begins_with("\"") and s.ends_with("\""):
		s = s.substr(1, s.length() - 2)
	return s.replace("\\n", "\n").replace("\\\"", "\"")
