extends SceneTree
## Check tool, not product code. Measures how loud the game's own player (chapter1/presentation/combat_audio.gd) is on the Master bus
## compared with the raw wav a page button plays. For each case it records the Master bus (AudioEffectCapture, 48 kHz stereo) while
##   raw   : the wav is played by a bare AudioStreamPlayer at 0 dB (what the browser does with the file), and
##   game  : combat_audio.play(cue) / a slot with an audition file (what the game and the skill-lab window do),
## and writes one stereo WAV per recording to --out. Loudness is then measured with ffmpeg ebur128 by tools/dev/audio_level_report.py.
## Reads nothing of the core; no save is touched. Works with --headless (dummy driver still mixes):
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/audio_level_probe.gd -- --out=_local/lab-loud/cap
## --gain-db=N tests the sfx test gain. --cases=name:cue|slot|path,... overrides the default list. A game case is "game:<cue>", "slot:<slot>=<res path>" or "raw:<res path>".
const CombatAudio := preload("res://chapter1/presentation/combat_audio.gd")
const SECONDS := 2.5
var out_dir := "_local/lab-loud/cap"
var cases: Array = []
var audio: RefCounted
var host: Node3D
var capture: AudioEffectCapture
var raw_player: AudioStreamPlayer
var index := -1
var frames_left := 0
var buffer := PackedVector2Array()
var report: Array = []
var waited := 0
var gain_db := 0.0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out_dir = arg.substr(6)
		elif arg.begins_with("--gain-db="): gain_db = float(arg.substr(10))
		elif arg.begins_with("--cases="):
			for item in arg.substr(8).split(","): cases.append(item)
	if cases.is_empty():
		for cue in ["fire","cold","impact","explosion"]:
			cases.append("raw:res://chapter1/art/quality03_audio/%s_0.wav" % cue)
			cases.append("game:" + cue)
		cases.append("raw:res://chapter1/art/quality03_audio/lightning_0.wav")
		cases.append("game:lightning")
		cases.append("slot:skill.arc.cast=res://chapter1/art/quality03_audio/lightning_0.wav")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(out_dir))
	host = Node3D.new()
	root.add_child(host)
	raw_player = AudioStreamPlayer.new()
	host.add_child(raw_player)
	audio = CombatAudio.new()
	audio.setup(host)
	audio.set_master_volume(.80)       # what chapter_one.gd sets
	if gain_db != 0.0: audio.set_sfx_test_gain_db(gain_db)   # --gain-db=N, as --chapter1-sfx-gain-db=N; adds the limiter above 0
	capture = AudioEffectCapture.new()           # after the limiter, so the capture hears what the speaker would
	capture.buffer_length = 4.0
	AudioServer.add_bus_effect(0, capture)
	audio.set_paused(false)

func _process(_delta: float) -> bool:
	if frames_left > 0:
		frames_left -= 1
		buffer.append_array(capture.get_buffer(capture.get_frames_available()))
		if frames_left == 0: _finish()
		return false
	waited += 1
	if waited < 5: return false
	index += 1
	if index >= cases.size():
		var f := FileAccess.open(ProjectSettings.globalize_path("res://").path_join(out_dir).path_join("probe.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "  ")); f.close()
		print("AUDIO_LEVEL_PROBE ", JSON.stringify(report))
		quit(0)
		return true
	_start(String(cases[index]))
	return false

func _start(spec: String) -> void:
	for v in audio.voices: v.stop()
	raw_player.stop()
	capture.clear_buffer()
	buffer = PackedVector2Array()
	var kind := spec.get_slice(":", 0)
	var rest := spec.substr(kind.length() + 1)
	if kind == "raw":
		raw_player.stream = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(rest)) if not ResourceLoader.exists(rest, "AudioStreamWAV") else ResourceLoader.load(rest)
		raw_player.volume_db = 0.0
		raw_player.play()
	elif kind == "game":
		audio.last_cue_tick.clear()
		audio.play(rest, 1000 * (index + 1))
	elif kind == "slot":
		var slot := rest.get_slice("=", 0)
		var path := rest.get_slice("=", 1)
		audio.audition_set(slot, [path])
		audio.last_cue_tick.clear()
		audio.play("lightning" if slot.ends_with("arc.cast") else "", 1000 * (index + 1), 0.0, slot, 1)
	frames_left = int(SECONDS * 60.0)
	report.append({"spec": spec, "file": ""})

func _finish() -> void:
	var spec := String(cases[index])
	var name := "%02d_%s" % [index, spec.replace(":", "_").replace("/", "_").replace("=", "_").replace(".", "_")]
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 48000
	var bytes := PackedByteArray()
	var peak := 0.0
	for s in buffer:
		peak = maxf(peak, maxf(absf(s.x), absf(s.y)))
		bytes.append_array(_pcm(s.x)); bytes.append_array(_pcm(s.y))
	wav.data = bytes
	var path := ProjectSettings.globalize_path("res://").path_join(out_dir).path_join(name + ".wav")
	wav.save_to_wav(path)
	report[index].file = name + ".wav"
	report[index].peak_linear = peak
	report[index].frames = buffer.size()
	audio.played = audio.played

func _pcm(v: float) -> PackedByteArray:
	var i := clampi(int(round(v * 32767.0)), -32768, 32767)
	var b := PackedByteArray()
	b.resize(2)
	b.encode_s16(0, i)
	return b
