extends RefCounted
## Licensed Kenney CC0 foley/spell layers; source/processing ledger is beside WAVs.
## AudioStreamPlayer API: https://docs.godotengine.org/en/4.5/classes/class_audiostreamplayer.html
## Twelve one-shot voices + one quiet loop. Worst aligned source peaks stay <1.
const MAX_VOICES := 13
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
var played := 0
var dropped := 0
var last_cue_tick: Dictionary={}
var variants: Dictionary={}
var pitch_turn: Dictionary={}
var raw_fallbacks: Array[String]=[]
var voice_gains: Array[float]=[]

func setup(view: Node3D) -> void:
	for cue in COUNTS:
		var options: Array[AudioStream]=[]
		for i in int(COUNTS[cue]):options.append(_load_wav(path_of(cue)+cue+"_%d.wav" % i))
		streams[cue]=options
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
func play(cue: String,tick: int=-1,gain_db: float=0.0) -> void:
	_play_cue(cue,tick,false,gain_db)

func play_ui(cue: String,tick: int) -> void:
	_play_cue(cue,tick,true)

func _play_cue(cue: String,tick: int,ui: bool,gain_db: float=0.0) -> void:
	if muted or (paused and not ui) or not streams.has(cue) or cue in SILENT:return
	if tick>=0 and tick-int(last_cue_tick.get(cue,-100000))<int(COOLDOWNS[cue]):return
	# Two final voices remain available for player hurt and important loot/UI cues.
	var critical: bool=cue in ["hurt","drop","equip","pickup","jewel","legend"]
	var end := MAX_VOICES if critical else MAX_VOICES-2
	for index in range(1,end):
		var voice := voices[index]
		if voice.playing:continue
		var variant: int=int(variants.get(cue,0))%int(COUNTS[cue])
		variants[cue]=variant+1
		voice.stream=streams[cue][variant]
		voice.pitch_scale=PITCHES[variant%PITCHES.size()]
		if DIRS.has(cue):
			var turn: int=int(pitch_turn.get(cue,0));pitch_turn[cue]=turn+1
			voice.pitch_scale=PITCH_STEPS[turn%PITCH_STEPS.size()]
		voice_gains[index]=float(GAINS[cue])*(db_to_linear(gain_db) if gain_db!=0.0 else 1.0)
		voice.volume_db=linear_to_db(maxf(.0001,master_volume*.11*voice_gains[index]))
		voice.stream_paused=false;voice.play()
		played+=1
		if tick>=0:last_cue_tick[cue]=tick
		return
	dropped+=1

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

func apply_volume() -> void:
	for index in voices.size():
		# Individual peaks<=.68 *12voices*.11 =.8976 at master1.
		# Looppeak<=.22*.025 adds.0055, so even worst phase alignment stays bounded.
		var gain := .025 if index==0 else .11*voice_gains[index]
		voices[index].volume_db=linear_to_db(maxf(.0001,master_volume*gain)) if not muted else -80

func reset() -> void:
	for voice in voices:voice.stop();voice.stream_paused=false
	voice_gains.fill(1.0)
	last_cue_tick.clear();variants.clear();pitch_turn.clear();paused=true
