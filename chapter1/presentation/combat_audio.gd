extends RefCounted
## Licensed Kenney CC0 foley/spell layers; source/processing ledger is beside WAVs.
## AudioStreamPlayer API: https://docs.godotengine.org/en/4.5/classes/class_audiostreamplayer.html
## Twelve one-shot voices + one quiet loop. Worst aligned source peaks stay <1.
const MAX_VOICES := 13
const Routes := preload("res://chapter1/presentation/audio_routes.gd")
const MAP_PATH := "res://chapter1/data/audio_map.json"
const PATH := "res://chapter1/art/quality03_audio/"
## Sound name -> folder, for the names whose files are not in PATH (one table here, no path anywhere else; SD1's audio_map.json
## takes this over). Every name in DIRS has no file yet (AU-RS2/3): it is not in COUNTS, so no stream is loaded and the name is
## silent. When its files exist: put the name in COUNTS and keep the folder here. Names in DIRS take their pitch from PITCH_STEPS.
const RUN_SPELLS_PATH := "res://chapter1/art/audio/run_spells/"
const DIRS := {"ring_body":RUN_SPELLS_PATH,"ring_tail_ember":RUN_SPELLS_PATH,"ring_tail_frost":RUN_SPELLS_PATH,"ring_tail_arc":RUN_SPELLS_PATH,"ward_cut":RUN_SPELLS_PATH,
	"detonate_heat":RUN_SPELLS_PATH,"detonate_chill":RUN_SPELLS_PATH,"detonate_shock":RUN_SPELLS_PATH,
	"interlock_frozen":RUN_SPELLS_PATH,"interlock_stunned":RUN_SPELLS_PATH,"interlock_staggered":RUN_SPELLS_PATH}
## Pitch of the old sounds by variant number; of the new names (DIRS) by a table of their own, one step per play and apart from the variant.
const PITCHES := [.97,1.0,1.035]
const PITCH_STEPS := [.97,.985,1.0,1.015,1.03]
const COUNTS := {"fire":3,"cold":2,"lightning":1,"impact":3,"death":3,"explosion":1,"hurt":1,"drop":1,"pickup":1,"equip":1,"step":2,"jewel":1,"legend":1}
const COOLDOWNS := {"fire":10,"cold":14,"lightning":14,"impact":7,"death":10,"explosion":14,"hurt":18,"drop":18,"pickup":8,"equip":4,"step":18,"jewel":6,"legend":6,
	"ring_body":20,"ring_tail_ember":20,"ring_tail_frost":20,"ring_tail_arc":20,"ward_cut":12,"detonate_heat":15,"detonate_chill":15,"detonate_shock":15,
	"interlock_frozen":18,"interlock_stunned":18,"interlock_staggered":18}
## The gains of the new names are 1.0 until their files are measured (AU-RS2/3); they are silent until then.
const GAINS := {"fire":.8,"cold":.72,"lightning":.82,"impact":.9,"death":.65,"explosion":1.0,"hurt":1.0,"drop":.8,"pickup":.65,"equip":.75,"step":.38,"jewel":.95,"legend":1.0,
	"ring_body":1.0,"ring_tail_ember":1.0,"ring_tail_frost":1.0,"ring_tail_arc":1.0,"ward_cut":1.0,"detonate_heat":1.0,"detonate_chill":1.0,"detonate_shock":1.0,
	"interlock_frozen":1.0,"interlock_stunned":1.0,"interlock_staggered":1.0}
## Cues that stay silent until their sound is replaced. User, 2026-11-18: the lightning cast grates (it plays 6 to 8 dB above
## the fire and cold casts, centred near 400 Hz); it is to become a running-current sound. Until then it makes no sound.
const SILENT: Array[String] = ["lightning"]
var voices: Array[AudioStreamPlayer]=[]
var streams: Dictionary={}
var ambience: AudioStreamWAV
var muted := false
var paused := true
var master_volume := .8
## One number for every one-shot (not the ambience loop): audio_map.json `mix_gain`, MIX_GAIN_DEFAULT when the file has none. A test gain
## (--chapter1-sfx-gain-db, set_sfx_test_gain_db) multiplies it; 0 dB changes nothing. Only the output of the voices changes, never the core.
const MIX_GAIN_DEFAULT := .11
const LIMITER_CEILING_DB := -1.0
var mix_gain := MIX_GAIN_DEFAULT
var map_mix_gain := MIX_GAIN_DEFAULT
var sfx_test_gain_db := 0.0
var played := 0
var dropped := 0
var last_cue_tick: Dictionary={}
var variants: Dictionary={}
var pitch_turn: Dictionary={}
var raw_fallbacks: Array[String]=[]
var voice_gains: Array[float]=[]
## T12 SL-A: sound slots (audio_map.json schema 2). A request that names a slot picks its file in this order: the audition fitted by
## a test window (audition_set), then the file adopted for the slot, then the sound of its cue as always. Cooldown, gain and pitch
## are the cue's. A slot with no parent cue (cue "") takes SLOT_DEFAULT. Nothing here runs unless a slot is adopted or fitted.
const SLOT_DEFAULT := {"cooldown":60,"gain":1.0}
const AUDITION_LOG_MAX := 200
var slot_table: Dictionary={}              # slot -> {"parent": cue, "per_targets": int}
var adopted: Dictionary={}                 # slot -> Array[AudioStream] (audio_map.json `adopted`)
var adopted_paths: Dictionary={}           # slot -> Array[String]
var audition: Dictionary={}                # slot -> Array[AudioStream] (audition_set)
var audition_paths: Dictionary={}          # slot -> Array[String]
var map_errors: Array[String]=[]
var audition_log: Array=[]                 # {tick, slot, cue, path}; only after audition_set was called once
var _audition_used := false
var _paths: Dictionary={}                  # cue -> Array[String], for the log of plays that use the cue's own files

func _read_map() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	return data if data is Dictionary else {}

func _load_chain_bank() -> void:
	var bank := Routes.chain_bank()
	if bank.is_empty(): return
	var data := _read_map()
	if not data.get("chain_lightning", {}).has(bank):
		push_error("Missing chain sound bank " + bank)
		return
	var table: Dictionary = data.chain_lightning[bank]
	for cue in table:
		var sample := _load_wav(String(table[cue]))
		if sample != null:
			streams[cue] = [sample]
			_paths[cue] = [String(table[cue])]

## Slots and adopted files of audio_map.json (schema 2; a schema 1 file has none and every request keeps its cue's sound).
## Called by setup() and again by a test window after an adoption. The audition is not touched.
func reload_map() -> void:
	slot_table.clear();adopted.clear();adopted_paths.clear();map_errors.clear()
	var data := _read_map()
	var mixed = data.get("mix_gain",MIX_GAIN_DEFAULT)
	map_mix_gain = clampf(float(mixed),.001,2.0) if (mixed is float or mixed is int) and is_finite(float(mixed)) else MIX_GAIN_DEFAULT
	_refresh_mix_gain()
	var slots = data.get("slots",{})
	if slots is Dictionary:
		for slot in slots:
			if slots[slot] is Dictionary: slot_table[String(slot)] = {"parent":String(slots[slot].get("parent","")),"per_targets":int(slots[slot].get("per_targets",0))}
	var taken = data.get("adopted",{})
	if not taken is Dictionary: return
	for slot in taken:
		var files = taken[slot].get("files",[]) if taken[slot] is Dictionary else []
		if not slot_table.has(String(slot)) or not files is Array or files.is_empty():
			map_errors.append("adopted slot without a slot entry or files: %s" % slot);continue
		var loaded: Array[AudioStream]=[]
		var names: Array[String]=[]
		for file in files:
			var sample := _load_wav(String(file))
			if sample == null: break
			loaded.append(sample);names.append(String(file))
		if loaded.size() != files.size():
			map_errors.append("adopted file missing for %s" % slot);continue
		adopted[String(slot)] = loaded;adopted_paths[String(slot)] = names

## Test window: fit `paths` (res:// or an absolute path inside this project, no "..") to `slot`; the next requests of the slot play them.
## All or nothing: one bad path and the slot keeps what it had. Returns {"ok": bool, "loaded": [paths], "errors": [text]}.
func audition_set(slot: String, paths: Array) -> Dictionary:
	var result := {"ok":false,"loaded":[],"errors":[]}
	if not slot_table.has(slot): result.errors.append("unknown slot: %s" % slot)
	if paths.is_empty(): result.errors.append("no paths")
	var loaded: Array[AudioStream]=[]
	var names: Array[String]=[]
	for item in paths:
		var path := _project_path(String(item))
		if path.is_empty(): result.errors.append("path not allowed (res:// or inside the project, no ..): %s" % item);continue
		var sample := _load_audition(path)
		if sample == null: result.errors.append("cannot load: %s" % path);continue
		loaded.append(sample);names.append(path)
	if not result.errors.is_empty(): return result
	audition[slot] = loaded;audition_paths[slot] = names
	_audition_used = true
	result.ok = true;result.loaded = names
	return result

func audition_clear(slot: String="") -> void:
	if slot.is_empty():
		audition.clear();audition_paths.clear()
	else:
		audition.erase(slot);audition_paths.erase(slot)

## "res://..." or an absolute path inside the project -> "res://..."; "" when it is neither or has a ".." part.
func _project_path(path: String) -> String:
	path = path.replace("\\","/")
	if "/../" in path or path.ends_with("/..") or path.begins_with("../"): return ""
	if path.begins_with("res://"): return path
	var root := ProjectSettings.globalize_path("res://").replace("\\","/")
	if not root.ends_with("/"): root += "/"
	if path.length() > root.length() and path.substr(0,root.length()).to_lower() == root.to_lower(): return "res://" + path.substr(root.length())
	return ""

func _load_audition(path: String) -> AudioStreamWAV:
	if ResourceLoader.exists(path,"AudioStreamWAV"): return ResourceLoader.load(path,"AudioStreamWAV") as AudioStreamWAV
	if FileAccess.file_exists(path): return AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
	return null

func setup(view: Node3D) -> void:
	for cue in COUNTS:
		var options: Array[AudioStream]=[]
		for i in int(COUNTS[cue]):options.append(_load_wav(path_of(cue)+cue+"_%d.wav" % i))
		streams[cue]=options
		var names: Array[String]=[]
		for i in int(COUNTS[cue]):names.append(path_of(cue)+cue+"_%d.wav" % i)
		_paths[cue]=names
	_load_chain_bank()
	reload_map()
	for i in MAX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name="Chapter1CombatVoice%d" % i
		view.add_child(voice);voices.append(voice)
		voice_gains.append(1.0)
	ambience=_load_wav(PATH+"ambience.wav").duplicate()
	ambience.loop_mode=AudioStreamWAV.LOOP_FORWARD
	ambience.loop_begin=0;ambience.loop_end=ambience.data.size()/2
	voices[0].stream=ambience
	apply_volume()
	print("CHAPTER1_AUDIO ",JSON.stringify({"licensed_variants":19,"voices":MAX_VOICES,"raw_fallbacks":raw_fallbacks,"ledger":PATH+"AUDIO-LEDGER.json"}))

func path_of(cue: String) -> String:
	return String(DIRS.get(cue,PATH))

func _load_wav(path: String) -> AudioStreamWAV:
	if ResourceLoader.exists(path,"AudioStreamWAV"):return ResourceLoader.load(path,"AudioStreamWAV") as AudioStreamWAV
	# Source-tree preview only. Exports must use imported resources (fallbacks=[]).
	# https://docs.godotengine.org/en/4.5/classes/class_audiostreamwav.html#class-audiostreamwav-method-load-from-file
	if FileAccess.file_exists(path):
		raw_fallbacks.append(path)
		return AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
	push_error("Missing Chapter1 audio resource: "+path)
	return null

## gain_db: this call's own trim on top of GAINS (audio_routes.gd makes it; 0 for every old sound).
## slot, targets: the request's sound slot and chain contacts. Left empty they come from the handoff audio_routes.gd keeps for the
## requests it just made (chapter_one.gd does not pass them), so the game needs no change at its call.
func play(cue: String,tick: int=-1,gain_db: float=0.0,slot: String="",targets: int=0) -> void:
	_play_cue(cue,tick,false,gain_db,slot,targets)

func play_ui(cue: String,tick: int) -> void:
	_play_cue(cue,tick,true)

## The files of a slot, [streams, paths]: the audition first, then the adopted ones; [] when it has neither (the cue's own sound plays).
func _slot_files(slot: String) -> Array:
	if audition.has(slot): return [audition[slot],audition_paths[slot]]
	if adopted.has(slot): return [adopted[slot],adopted_paths[slot]]
	return []

func _play_cue(cue: String,tick: int,ui: bool,gain_db: float=0.0,slot: String="",targets: int=0) -> void:
	var handoff := Routes.take_handoff(cue)
	if slot.is_empty() and not handoff.is_empty(): slot = String(handoff.get("slot",""));targets = int(handoff.get("targets",0))
	var files: Array = _slot_files(slot) if not slot.is_empty() else []
	if not files.is_empty():
		_play_slot(cue,slot,files,tick,ui,gain_db,targets);return
	if muted or (paused and not ui) or not streams.has(cue) or cue in SILENT:return
	var chain := cue.begins_with("arc_path_")
	var group := "lightning" if chain else cue
	if tick>=0 and tick-int(last_cue_tick.get(group,-100000))<int(COOLDOWNS[group]):return
	# Two final voices remain available for player hurt and important loot/UI cues.
	var critical: bool=cue in ["hurt","drop","equip","pickup","jewel","legend"]
	var end := MAX_VOICES if critical else MAX_VOICES-2
	for index in range(1,end):
		var voice := voices[index]
		if voice.playing:continue
		var variant: int=int(variants.get(cue,0))%streams[cue].size()
		variants[cue]=variant+1
		voice.stream=streams[cue][variant]
		voice.pitch_scale=PITCHES[variant%PITCHES.size()]
		if _audition_used:_log_play(tick,slot,cue,_cue_path(cue,variant))
		if chain or DIRS.has(cue):
			var turn: int=int(pitch_turn.get(group,0));pitch_turn[group]=turn+1
			voice.pitch_scale=PITCH_STEPS[turn%PITCH_STEPS.size()]
		voice_gains[index]=float(GAINS[group])*(db_to_linear(gain_db) if gain_db!=0.0 else 1.0)
		voice.volume_db=linear_to_db(maxf(.0001,master_volume*mix_gain*voice_gains[index]))
		voice.stream_paused=false;voice.play()
		played+=1
		if tick>=0:last_cue_tick[group]=tick
		return
	dropped+=1

## A request whose slot has an audition or an adopted file. The rules are those of the slot's parent cue: its cooldown group, its gain,
## its voices; the file by contacts (per_targets: min(targets, per_targets), pitch steps like the chain) or in turn by variant.
func _play_slot(cue: String,slot: String,files: Array,tick: int,ui: bool,gain_db: float,targets: int) -> void:
	if muted or (paused and not ui):return
	var entry: Dictionary = slot_table.get(slot,{})
	if cue.is_empty(): cue = String(entry.get("parent",""))
	var per_targets := int(entry.get("per_targets",0))
	var group := "lightning" if cue.begins_with("arc_path_") else (cue if not cue.is_empty() else slot)
	if tick>=0 and tick-int(last_cue_tick.get(group,-100000))<int(COOLDOWNS.get(group,SLOT_DEFAULT.cooldown)):return
	var critical: bool=cue in ["hurt","drop","equip","pickup","jewel","legend"]
	var end := MAX_VOICES if critical else MAX_VOICES-2
	var list: Array = files[0]
	for index in range(1,end):
		var voice := voices[index]
		if voice.playing:continue
		var variant: int
		if per_targets>0: variant = clampi(maxi(targets,1),1,mini(per_targets,list.size()))-1
		else:
			variant = int(variants.get(slot,0))%list.size();variants[slot]=variant+1
		voice.stream=list[variant]
		if per_targets>0 or DIRS.has(cue):
			var turn: int=int(pitch_turn.get(group,0));pitch_turn[group]=turn+1
			voice.pitch_scale=PITCH_STEPS[turn%PITCH_STEPS.size()]
		else: voice.pitch_scale=PITCHES[variant%PITCHES.size()]
		voice_gains[index]=float(GAINS.get(group,SLOT_DEFAULT.gain))*(db_to_linear(gain_db) if gain_db!=0.0 else 1.0)
		voice.volume_db=linear_to_db(maxf(.0001,master_volume*mix_gain*voice_gains[index]))
		voice.stream_paused=false;voice.play()
		played+=1
		if tick>=0:last_cue_tick[group]=tick
		if _audition_used:_log_play(tick,slot,cue,String(files[1][variant]))
		return
	dropped+=1

func _cue_path(cue: String,variant: int) -> String:
	var names: Array = _paths.get(cue,[])
	return String(names[variant]) if variant<names.size() else ""

func _log_play(tick: int,slot: String,cue: String,path: String) -> void:
	audition_log.append({"tick":tick,"slot":slot,"cue":cue,"path":path})
	if audition_log.size()>AUDITION_LOG_MAX:audition_log.pop_front()

func set_paused(value: bool) -> void:
	if paused==value:return
	paused=value
	if not value and not voices[0].playing:
		voices[0].stream=ambience;voices[0].play()
	for voice in voices:voice.stream_paused=value

func set_muted(value: bool) -> void:
	muted=value;apply_volume()

func set_master_volume(value: float) -> void:
	if not is_finite(value):return
	master_volume=clampf(value,0,1);apply_volume()

## Test only: raise or lower every one-shot by `db` (0 = as the data says). Above 0 dB a hard limiter is put on the Master bus
## (ceiling LIMITER_CEILING_DB) so a big gain cannot clip; at 0 or below no effect is added, the output is as before.
func set_sfx_test_gain_db(db: float) -> void:
	if not is_finite(db):return
	sfx_test_gain_db=clampf(db,-40.0,30.0)
	_refresh_mix_gain()
	if sfx_test_gain_db>0.0 and not _limiter_on():
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db=LIMITER_CEILING_DB
		AudioServer.add_bus_effect(0,limiter)
	apply_volume()

func _refresh_mix_gain() -> void:
	mix_gain=map_mix_gain*(db_to_linear(sfx_test_gain_db) if sfx_test_gain_db!=0.0 else 1.0)

func _limiter_on() -> bool:
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0,i) is AudioEffectHardLimiter:return true
	return false

func apply_volume() -> void:
	for index in voices.size():
		# Individual peaks<=.68 *12voices*.11 =.8976 at master1 (with the default mix_gain; see MIX_GAIN_DEFAULT).
		# Looppeak<=.22*.025 adds.0055, so even worst phase alignment stays bounded.
		var gain := .025 if index==0 else mix_gain*voice_gains[index]
		voices[index].volume_db=linear_to_db(maxf(.0001,master_volume*gain)) if not muted else -80

func reset() -> void:
	for voice in voices:voice.stop();voice.stream_paused=false
	voice_gains.fill(1.0)
	last_cue_tick.clear();variants.clear();pitch_turn.clear();paused=true
