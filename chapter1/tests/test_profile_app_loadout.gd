extends SceneTree
## T5 S1b: the app's side of the per-witch kit (T5 8.3). The app script is built without entering the tree (no _ready), so it
## never reads a real save; its profile is an isolated one under res://_local/ set up by hand.
##  - a run whose starting kit could not be imported does not change the witch's saved kit,
##  - a run that started with her kit saves what she wore at the end (win, loss or give-up alike, T5-U5),
##  - the stash window equips onto the witch the title menu shows,
##  - the profile line is worded by the app's own variable or by the profile's code, never by the profile's sentence.
## Marker: CHAPTER1_APP_LOADOUT_RESULT.
const App = preload("res://chapter1/app/chapter_one.gd")
const Profile = preload("res://chapter1/core/chapter_profile.gd")
const FROST := "chapter1.character.frost"
const ARC := "chapter1.character.arc"
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
func _initialize() -> void:
	call_deferred("execute")
func prepare(folder: String) -> Array:
	var profile = Profile.new()
	profile.configure(folder + "/profile.json", true)
	for index in 2:
		profile.record_run("lvl-%d" % index, [], [], false, 1, {"character_id": FROST, "xp_gained": 1000, "first_kills": [], "sources": {}})
	var tables = Profile.loot()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var weapon: Dictionary = tables.roll_item(rng, 4, "magic", "weapon")
	weapon.uid = 1
	var head: Dictionary = tables.roll_item(rng, 4, "magic", "head")
	head.uid = 2
	profile.record_run("kit", [weapon, head], [], false, 1, {}, {"character_id": FROST, "equipped": {"weapon": 1, "head": 2}, "kept_slots": []})
	return [profile, weapon, head]
func execute() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/_local/appdata/"):
		print("CHAPTER1_APP_LOADOUT_RESULT ", JSON.stringify({"checks": 0, "failures": ["user data dir is not isolated: refusing to run"]}))
		quit(1)
		return
	var root := "res://_local/app-loadout/%d" % Time.get_ticks_usec() # a new folder per run: an old file would answer by its receipts
	# A run that started with her kit.
	var made := prepare(root + "/a")
	var app = App.new()
	app.profile = made[0]
	var kit_before: Dictionary = app.profile.loadout(FROST)
	check(kit_before.size() == 2, "the witch has a kit of two pieces")
	app.run_character_id = FROST
	app.run.start(11, "chapter1.skill.frost")
	check(app._import_profile_kit() and app.run_character_id == FROST and app._run_carry_ok and app._run_kept_slots.is_empty() and app.run.equipped.size() == 2, "the run started wearing her kit and may carry the result back")
	app._receipt = "app-run-1"
	app.run.equipped.erase("head")
	app.run.abandon()
	check(app.run.mode == "defeat", "the run ended (a give-up)")
	app._save_terminal()
	var kit_after: Dictionary = app.profile.loadout(FROST)
	check(kit_after.size() == 1 and kit_after.has("weapon") and kit_after.weapon == kit_before.weapon, "a given-up run saves what she wore: the head piece is off, the weapon stays")
	# A run whose kit could not be imported.
	var broken_made := prepare(root + "/b")
	var other = App.new()
	other.profile = broken_made[0]
	var kit_text := JSON.stringify(other.profile.loadout(FROST))
	other.run_character_id = FROST
	other.run.start(11, "chapter1.skill.frost")
	other.run.tick = 1 # the core only takes a starting kit at tick 0: the import is refused
	check(not other._import_profile_kit() and not other._run_carry_ok and other.run.equipped.is_empty(), "a kit that could not be imported starts the run bare and switches the carry off")
	other._receipt = "app-run-2"
	other.run.abandon()
	var file_before := FileAccess.get_file_as_string(other.profile.path)
	other._save_terminal()
	check(JSON.stringify(other.profile.loadout(FROST)) == kit_text, "that run leaves her saved kit as it was")
	check(FileAccess.get_file_as_string(other.profile.path) != file_before, "the run itself is still saved (receipt, experience)")
	# The stash window equips onto the witch the menu shows.
	var menu = App.new()
	var menu_made := prepare(root + "/c")
	menu.profile = menu_made[0]
	for index in 2:
		menu.profile.record_run("arc-%d" % index, [], [], false, 1, {"character_id": ARC, "xp_gained": 1000, "first_kills": [], "sources": {}})
	var spare = menu.profile.state.items[0].storage_id
	menu.hud.menu_select_skill("chapter1.skill.arc")
	check(menu.menu_character_id() == ARC, "the menu witch is the host's answer (no screen is needed for it)")
	menu._equip_from_stash(int(spare))
	check(menu.profile.loadout(ARC).has("weapon") and int(menu.profile.loadout(ARC).weapon) == int(spare) and menu.profile.loadout(FROST).size() == 2, "equipping from the stash goes to the shown witch only")
	check(menu.hud.profile_state.equipped == menu.profile.loadout(ARC), "the screen's copy shows the shown witch's kit")
	# B2: a host without the public function (or another kind of node) means "no witch", never a script error.
	var bare_hud = App.new()
	var real_hud = bare_hud.hud
	bare_hud.hud = Node.new()
	check(bare_hud.menu_character_id() == "", "a host with no menu_character_id() gives no witch")
	bare_hud.hud.free()
	bare_hud.hud = real_hud
	bare_hud.free()
	# The profile line.
	var off = App.new()
	off._profile_off = true
	off._app_error = "app sentence"
	check(off._profile_error_text() == "app sentence", "profile off: the app's own sentence is shown")
	var coded = App.new()
	coded.profile.available = false
	coded.profile.reject_kind = "incompatible"
	coded.profile._err("file_rejected", "Save file failed validation; original kept")
	check(coded._profile_error_text() != "Save file failed validation; original kept" and not coded._profile_error_text().is_empty(), "a refusal is worded from its code, not from the profile's dev sentence")
	coded.play_without_save()
	check(coded._profile_error_text() == coded.SESSION_NO_SAVE_NOTE, "play without saving shows the app's own note")
	for node in [app, other, menu, off, coded]:
		node.free()
	print("CHAPTER1_APP_LOADOUT_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
