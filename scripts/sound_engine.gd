class_name SoundEngine
extends Node

class CueOverride extends Resource:
	@export var sound_name: StringName = &"jump"
	@export var custom_stream: AudioStream = null
	@export_range(-24.0, 12.0, 0.5) var volume_offset_db: float = 0.0
	@export_range(0.25, 2.5, 0.01) var pitch_multiplier: float = 1.0
	@export_range(0.0, 0.3, 0.01) var pitch_jitter: float = -1.0 ## -1 uses default engine jitter
	@export var cooldown_ms_override: int = -1 ## -1 uses default cooldown

const SAMPLE_RATE: int = 44100
const POOL_SIZE: int = 16

const ALL_SOUND_NAMES: Array[StringName] = [
	&"jump", &"land", &"eject", &"recall", &"win", &"bounce",
	&"roll_start", &"roll_tick", &"roll_hum",
	&"button_down", &"button_up", &"gate_move", &"explode",
	&"billiards_roll", &"billiards_hit", &"pocket_drop",
	&"scale_creak", &"scale_settle", &"tube_suck", &"tube_shoot",
	&"cannon_load", &"cannon_fire", &"block_crack", &"block_break",
	&"ui_hover", &"ui_click", &"ui_back", &"ui_slide",
]

@export_group("Master & Custom Audio")
@export_range(-40.0, 6.0, 0.5) var master_volume_db: float = 0.0
@export var custom_sfx_folder: String = "res://audio/sfx" ## Drop e.g. jump.wav / jump.ogg here to auto-override
@export var sound_overrides: Array[CueOverride] = []

var _streams: Dictionary = {} # StringName -> AudioStream
var _override_map: Dictionary = {} # StringName -> CueOverride
var _last_play_time_ms: Dictionary = {} # StringName -> float
var _is_muted: bool = false

var _players: Array[AudioStreamPlayer] = []
var _next_player_idx: int = 0

var _roll_hum_player: AudioStreamPlayer = null
var _roll_hum_tween: Tween = null
var _roll_hum_active: bool = false

const MIN_COOLDOWNS_MS: Dictionary = {
	&"bounce": 65.0,
	&"land": 80.0,
	&"eject": 60.0,
	&"roll_tick": 110.0,
	&"gate_move": 90.0,
	&"billiards_roll": 120.0,
	&"billiards_hit": 45.0,
	&"pocket_drop": 150.0,
	&"ui_hover": 38.0,
	&"ui_click": 45.0,
	&"ui_back": 45.0,
	&"ui_slide": 70.0,
	&"scale_creak": 135.0,
	&"scale_settle": 110.0,
	&"tube_suck": 160.0,
	&"tube_shoot": 140.0,
	&"cannon_load": 180.0,
	&"cannon_fire": 220.0,
	&"block_crack": 95.0,
	&"block_break": 120.0,
}

func _ready() -> void:
	_build_player_pool()
	_rebuild_override_map()
	_preload_buffers()

func _build_player_pool() -> void:
	for i in range(POOL_SIZE):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = "SFXPlayer_%d" % i
		add_child(p)
		_players.append(p)

	_roll_hum_player = AudioStreamPlayer.new()
	_roll_hum_player.name = "RollHumPlayer"
	add_child(_roll_hum_player)

func _rebuild_override_map() -> void:
	_override_map.clear()
	for cfg: CueOverride in sound_overrides:
		if cfg != null and cfg.sound_name != &"":
			_override_map[cfg.sound_name] = cfg

func reload_sounds() -> void:
	_rebuild_override_map()
	_preload_buffers()

func _get_override(sound_name: StringName) -> CueOverride:
	if _override_map.has(sound_name):
		return _override_map[sound_name] as CueOverride
	return null

func _try_load_custom_stream(sound_name: StringName) -> AudioStream:
	var cfg: CueOverride = _get_override(sound_name)
	if cfg != null and cfg.custom_stream != null:
		return cfg.custom_stream

	if not custom_sfx_folder.is_empty():
		var base: String = custom_sfx_folder.path_join(String(sound_name))
		for ext: String in [".wav", ".ogg", ".mp3"]:
			var path: String = base + ext
			if ResourceLoader.exists(path):
				var loaded: Resource = load(path)
				if loaded is AudioStream:
					return loaded as AudioStream
	return null

func _preload_buffers() -> void:
	_streams.clear()
	var procedural: Dictionary = {
		&"jump": _render_jump_buffer(),
		&"land": _render_land_buffer(),
		&"eject": _render_eject_buffer(),
		&"recall": _render_recall_buffer(),
		&"win": _render_win_buffer(),
		&"bounce": _render_bounce_buffer(),
		&"roll_start": _render_roll_start_buffer(),
		&"roll_tick": _render_roll_tick_buffer(),
		&"roll_hum": _render_roll_hum_buffer(),
		&"button_down": _render_button_down_buffer(),
		&"button_up": _render_button_up_buffer(),
		&"gate_move": _render_gate_move_buffer(),
		&"explode": _render_explode_buffer(),
		&"billiards_roll": _render_billiards_roll_buffer(),
		&"billiards_hit": _render_billiards_hit_buffer(),
		&"pocket_drop": _render_pocket_drop_buffer(),
		&"ui_hover": _render_ui_hover_buffer(),
		&"ui_click": _render_ui_click_buffer(),
		&"ui_back": _render_ui_back_buffer(),
		&"ui_slide": _render_ui_slide_buffer(),
		&"scale_creak": _render_scale_creak_buffer(),
		&"scale_settle": _render_scale_settle_buffer(),
		&"tube_suck": _render_tube_suck_buffer(),
		&"tube_shoot": _render_tube_shoot_buffer(),
		&"cannon_load": _render_cannon_load_buffer(),
		&"cannon_fire": _render_cannon_fire_buffer(),
		&"block_crack": _render_block_crack_buffer(),
		&"block_break": _render_block_break_buffer(),
	}

	for sfx_name: StringName in ALL_SOUND_NAMES:
		var custom: AudioStream = _try_load_custom_stream(sfx_name)
		_streams[sfx_name] = custom if custom != null else procedural.get(sfx_name)

func play(sound_name: StringName, volume_scale: float = 1.0, pitch_override: float = -1.0) -> void:
	if _is_muted:
		return

	var cfg: CueOverride = _get_override(sound_name)
	var default_cd: float = float(MIN_COOLDOWNS_MS.get(sound_name, 0.0))
	var min_cooldown: float = float(cfg.cooldown_ms_override) if (cfg != null and cfg.cooldown_ms_override >= 0) else default_cd
	var now_ms: float = float(Time.get_ticks_msec())
	var last_played: float = float(_last_play_time_ms.get(sound_name, -1e12))
	if now_ms - last_played < min_cooldown:
		return
	_last_play_time_ms[sound_name] = now_ms

	var stream: AudioStream = _streams.get(sound_name, null) as AudioStream
	if stream == null:
		return

	var base_pitch: float = 1.0
	var jitter: float = 0.06
	if sound_name == &"win":
		jitter = 0.0
	elif String(sound_name).begins_with("ui_"):
		jitter = 0.03
	if cfg != null and cfg.pitch_jitter >= 0.0:
		jitter = cfg.pitch_jitter

	if jitter > 0.0:
		base_pitch = randf_range(1.0 - jitter, 1.0 + jitter)

	var cfg_pitch: float = cfg.pitch_multiplier if cfg != null else 1.0
	var override_mult: float = pitch_override if pitch_override > 0.0 else 1.0
	var final_pitch: float = base_pitch * cfg_pitch * override_mult

	var gain_jitter: float = randf_range(0.92, 1.08)
	var linear_gain: float = clampf(volume_scale * gain_jitter, 0.0001, 0.95)
	var extra_db: float = cfg.volume_offset_db if cfg != null else 0.0

	var player: AudioStreamPlayer = _players[_next_player_idx]
	_next_player_idx = (_next_player_idx + 1) % POOL_SIZE
	player.stop()
	player.stream = stream
	player.pitch_scale = maxf(0.05, final_pitch)
	player.volume_db = master_volume_db + extra_db + linear_to_db(linear_gain)
	player.play()

func get_is_muted() -> bool:
	return _is_muted

func set_muted(muted: bool) -> void:
	_is_muted = muted
	if _is_muted:
		stop_roll_hum(0.05)

func toggle_mute() -> bool:
	set_muted(not _is_muted)
	return _is_muted

# --- Continuous Roll Hum Control ---

func start_roll_hum(volume: float = 0.15) -> void:
	if _is_muted or _roll_hum_active:
		return
	var stream: AudioStream = _streams.get(&"roll_hum", null) as AudioStream
	if stream == null:
		return

	if _roll_hum_tween != null and _roll_hum_tween.is_valid():
		_roll_hum_tween.kill()

	var cfg: CueOverride = _get_override(&"roll_hum")
	var extra_db: float = cfg.volume_offset_db if cfg != null else 0.0

	_roll_hum_active = true
	_roll_hum_player.stream = stream
	_roll_hum_player.pitch_scale = cfg.pitch_multiplier if cfg != null else 1.0
	_roll_hum_player.volume_db = master_volume_db + extra_db + linear_to_db(clampf(volume, 0.001, 0.4))
	_roll_hum_player.play()

func stop_roll_hum(fade_time: float = 0.15) -> void:
	if not _roll_hum_active or _roll_hum_player == null:
		return
	_roll_hum_active = false
	if _roll_hum_tween != null and _roll_hum_tween.is_valid():
		_roll_hum_tween.kill()

	if fade_time <= 0.01 or not _roll_hum_player.playing:
		_roll_hum_player.stop()
		return

	_roll_hum_tween = create_tween()
	_roll_hum_tween.tween_property(_roll_hum_player, "volume_db", -60.0, fade_time)
	_roll_hum_tween.tween_callback(_roll_hum_player.stop)

func set_roll_hum_volume(volume: float, pitch: float = 1.0) -> void:
	if not _roll_hum_active or _roll_hum_player == null:
		return
	var cfg: CueOverride = _get_override(&"roll_hum")
	var extra_db: float = cfg.volume_offset_db if cfg != null else 0.0
	var pitch_mult: float = cfg.pitch_multiplier if cfg != null else 1.0
	var clamped: float = clampf(volume, 0.0005, 0.4)
	_roll_hum_player.volume_db = master_volume_db + extra_db + linear_to_db(clamped)
	_roll_hum_player.pitch_scale = maxf(0.25, pitch * pitch_mult)

# --- PCM 16-bit WAV Builder ---

func _samples_to_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var count: int = samples.size()
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * 2)
	for i in range(count):
		var s: float = clampf(samples[i], -1.0, 1.0)
		var pcm: int = int(roundf(s * 32767.0))
		bytes.encode_s16(i * 2, pcm)

	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = count
	return wav

# --- Tactile Balatro-Inspired UI Buffers ---

func _render_ui_hover_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.032)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var p1: float = 0.0
	var p2: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var freq: float = 1420.0 + 520.0 * pow(t, 0.6)
		p1 += (TAU * freq) / SAMPLE_RATE
		p2 += (TAU * (freq * 2.15)) / SAMPLE_RATE
		var attack: float = minf(1.0, t * 45.0)
		var env: float = attack * pow(1.0 - t, 3.2)
		data[i] = (sin(p1) * 0.16 + sin(p2) * 0.06) * env
	return _samples_to_wav(data)

func _render_ui_click_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.075)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var snap_phase: float = 0.0
	var body_phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var snap_freq: float = 1850.0 * pow(0.55, t * 4.0)
		snap_phase += (TAU * snap_freq) / SAMPLE_RATE
		var snap_env: float = sin((t / 0.28) * PI) * 0.24 if t < 0.28 else 0.0

		var body_freq: float = 523.25 if t < 0.42 else 783.99
		body_phase += (TAU * body_freq) / SAMPLE_RATE
		var attack: float = minf(1.0, t * 40.0)
		var body_env: float = attack * pow(1.0 - t, 2.1)
		data[i] = sin(snap_phase) * snap_env + sin(body_phase) * 0.24 * body_env
	return _samples_to_wav(data)

func _render_ui_back_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.075)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var freq: float = 560.0 * pow(0.48, t)
		phase += (TAU * freq) / SAMPLE_RATE
		var attack: float = minf(1.0, t * 40.0)
		var env: float = attack * pow(1.0 - t, 2.0)
		data[i] = sin(phase) * 0.25 * env
	return _samples_to_wav(data)

func _render_ui_slide_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.095)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var lp1: float = 0.0
	var lp2: float = 0.0
	var tone_phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var white: float = randf_range(-1.0, 1.0)
		lp1 = lp1 * 0.84 + white * 0.16
		lp2 = lp2 * 0.84 + lp1 * 0.16
		var freq: float = 340.0 + 360.0 * sin((t * PI) * 0.5)
		tone_phase += (TAU * freq) / SAMPLE_RATE
		var env: float = sin(PI * t)
		data[i] = (lp2 * 0.42 + sin(tone_phase) * 0.1) * env
	return _samples_to_wav(data)

# --- Gameplay Procedural Buffer Generators ---

func _render_jump_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.16)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var freq: float = 190.0 + 350.0 * pow(t, 0.7)
		phase += (TAU * freq) / SAMPLE_RATE
		var attack: float = minf(1.0, t * 25.0)
		var env: float = attack * (1.0 - t)
		data[i] = sin(phase) * env * 0.34
	return _samples_to_wav(data)

func _render_land_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.13)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var phase: float = 0.0
	var harmonic_phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var freq: float = 140.0 * pow(0.34, t)
		phase += (TAU * freq) / SAMPLE_RATE
		harmonic_phase += (TAU * freq * 1.5) / SAMPLE_RATE
		var attack: float = minf(1.0, t * 40.0)
		var env: float = attack * pow(1.0 - t, 2.2)
		var body: float = sin(phase) * 0.34 + sin(harmonic_phase) * 0.08 * pow(1.0 - t, 3.0)
		data[i] = body * env
	return _samples_to_wav(data)

func _render_bounce_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.12)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var phase: float = 0.0
	var overtone_phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var freq: float = (310.0 - 430.0 * t) if t < 0.22 else (215.0 + 290.0 * ((t - 0.22) / 0.78))
		phase += (TAU * freq) / SAMPLE_RATE
		overtone_phase += (TAU * freq * 2.0) / SAMPLE_RATE
		var attack: float = minf(1.0, t * 40.0)
		var env: float = attack * pow(1.0 - t, 1.9)
		var overtone: float = sin(overtone_phase) * 0.07 * pow(1.0 - t, 3.5)
		data[i] = (sin(phase) * 0.3 + overtone) * env
	return _samples_to_wav(data)

func _render_eject_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.18)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var phase: float = 0.0
	var pop_phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var freq: float = 250.0 + 440.0 * sin((t * PI) * 0.5)
		phase += (TAU * freq) / SAMPLE_RATE
		var pop_freq: float = 520.0 - 280.0 * minf(1.0, t * 8.0)
		pop_phase += (TAU * pop_freq) / SAMPLE_RATE
		var pop_env: float = sin((t / 0.14) * PI) * 0.14 if t < 0.14 else 0.0
		var attack: float = minf(1.0, t * 35.0)
		var env: float = attack * pow(1.0 - t, 1.6)
		data[i] = sin(phase) * 0.28 * env + sin(pop_phase) * pop_env
	return _samples_to_wav(data)

func _render_recall_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.18)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var freq: float = 620.0 - 320.0 * t + 400.0 * t * t
		phase += (TAU * freq) / SAMPLE_RATE
		var env: float = (1.0 - t) * minf(1.0, t * 14.0)
		data[i] = sin(phase) * env * 0.28
	return _samples_to_wav(data)

func _render_win_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.55)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var notes: Array[float] = [523.25, 659.25, 783.99, 1046.5]
	var phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var note_idx: int = mini(notes.size() - 1, int(floor(t * notes.size())))
		var note_t: float = fmod(t * notes.size(), 1.0)
		phase += (TAU * notes[note_idx]) / SAMPLE_RATE
		var attack: float = minf(1.0, note_t * 20.0)
		var env: float = attack * pow(1.0 - note_t, 1.2) * (1.0 - t * 0.35)
		data[i] = sin(phase) * env * 0.3
	return _samples_to_wav(data)

func _render_roll_start_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.18)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var freq: float = 130.0 + 180.0 * sin((t * PI) * 0.5)
		phase += (TAU * freq) / SAMPLE_RATE
		var env: float = sin(PI * t) * 0.28
		data[i] = sin(phase) * env
	return _samples_to_wav(data)

func _render_roll_tick_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.14)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var freq: float = 115.0 + 30.0 * sin(PI * t)
		phase += (TAU * freq) / SAMPLE_RATE
		var env: float = sin(PI * t) * 0.18
		data[i] = sin(phase) * env
	return _samples_to_wav(data)

func _render_roll_hum_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 2.0)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var lp1: float = 0.0
	var lp2: float = 0.0
	var lp3: float = 0.0
	var tone_phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var rumble_freq: float = 28.0 + 12.0 * sin(t * PI * 0.3)
		tone_phase += (TAU * rumble_freq) / SAMPLE_RATE
		var white: float = randf_range(-1.0, 1.0) * 0.08
		lp1 = lp1 * 0.94 + white * 0.06
		lp2 = lp2 * 0.94 + lp1 * 0.06
		lp3 = lp3 * 0.94 + lp2 * 0.06
		var loop_pos: float = fmod(t * 4.0, 1.0)
		var env: float = 0.15 + 0.05 * sin(loop_pos * TAU)
		data[i] = (sin(tone_phase) * 0.06 + lp3 * 0.28) * env
	return _samples_to_wav(data, true)

func _render_button_down_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.22)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var phase: float = 0.0
	var tick_phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		tick_phase += (TAU * 1150.0) / SAMPLE_RATE
		var click: float = sin((t / 0.03) * PI) * sin(tick_phase) * 0.2 if t < 0.03 else 0.0
		var freq: float = 392.0 if t < 0.35 else 587.33
		phase += (TAU * freq) / SAMPLE_RATE
		var attack: float = minf(1.0, t * 30.0)
		var env: float = attack * pow(1.0 - t, 1.4)
		data[i] = sin(phase) * 0.28 * env + click
	return _samples_to_wav(data)

func _render_button_up_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.16)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var phase: float = 0.0
	var tick_phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		tick_phase += (TAU * 820.0) / SAMPLE_RATE
		var clack: float = sin((t / 0.035) * PI) * sin(tick_phase) * 0.16 if t < 0.035 else 0.0
		var freq: float = 310.0 - 170.0 * t
		phase += (TAU * freq) / SAMPLE_RATE
		var attack: float = minf(1.0, t * 30.0)
		var env: float = attack * pow(1.0 - t, 1.8)
		data[i] = sin(phase) * 0.24 * env + clack
	return _samples_to_wav(data)

func _render_gate_move_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.16)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var phase1: float = 0.0
	var phase2: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var freq: float = 78.0 + 14.0 * sin(PI * t)
		phase1 += (TAU * freq) / SAMPLE_RATE
		phase2 += (TAU * freq * 2.0) / SAMPLE_RATE
		var env: float = sin(PI * t) * 0.22
		data[i] = (sin(phase1) * 0.7 + sin(phase2) * 0.3) * env
	return _samples_to_wav(data)

func _render_explode_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.44)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var phase: float = 0.0
	var sub_phase: float = 0.0
	var lp1: float = 0.0
	var lp2: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var freq: float = 155.0 * pow(0.22, pow(t, 0.72))
		phase += (TAU * freq) / SAMPLE_RATE
		sub_phase += (TAU * (freq * 0.5)) / SAMPLE_RATE
		var white: float = randf_range(-1.0, 1.0)
		lp1 = lp1 * 0.92 + white * 0.08
		lp2 = lp2 * 0.92 + lp1 * 0.08
		var attack: float = minf(1.0, t * 45.0)
		var sub_env: float = attack * pow(1.0 - t, 1.8)
		var rumble_env: float = attack * pow(1.0 - t, 2.3)
		data[i] = (sin(phase) * 0.42 + sin(sub_phase) * 0.25) * sub_env + lp2 * 1.1 * rumble_env
	return _samples_to_wav(data)

func _render_billiards_roll_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.16)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var sub_phase: float = 0.0
	var body_phase: float = 0.0
	var lp1: float = 0.0
	var lp2: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var freq: float = 65.0 + 30.0 * sin(PI * t)
		sub_phase += (TAU * freq) / SAMPLE_RATE
		body_phase += (TAU * (freq * 1.85)) / SAMPLE_RATE
		var white: float = randf_range(-1.0, 1.0)
		lp1 = lp1 * 0.89 + white * 0.11
		lp2 = lp2 * 0.89 + lp1 * 0.11
		var env: float = sin(PI * t)
		var slate_rumble: float = (sin(sub_phase) * 0.16 + sin(body_phase) * 0.05) * env
		var felt_brush: float = lp2 * 0.52 * env
		data[i] = slate_rumble + felt_brush
	return _samples_to_wav(data)

func _render_billiards_hit_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.13)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var clack_phase1: float = 0.0
	var clack_phase2: float = 0.0
	var slate_phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var clack_freq: float = 1200.0 * pow(0.84, t * 6.0)
		clack_phase1 += (TAU * clack_freq) / SAMPLE_RATE
		clack_phase2 += (TAU * (clack_freq * 2.21)) / SAMPLE_RATE
		var slate_freq: float = 340.0 * pow(0.57, t)
		slate_phase += (TAU * slate_freq) / SAMPLE_RATE
		var attack: float = minf(1.0, t * 90.0)
		var clack_env: float = attack * pow(1.0 - t, 7.5)
		var body_env: float = attack * pow(1.0 - t, 2.4)
		var resin_clack: float = (sin(clack_phase1) * 0.34 + sin(clack_phase2) * 0.14) * clack_env
		var slate_body: float = sin(slate_phase) * 0.16 * body_env
		data[i] = resin_clack + slate_body
	return _samples_to_wav(data)

func _render_pocket_drop_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.34)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var thud_phase: float = 0.0
	var rattle_phase: float = 0.0
	var lp1: float = 0.0
	var lp2: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var thud_freq: float = 180.0 * pow(0.36, pow(t, 0.65))
		thud_phase += (TAU * thud_freq) / SAMPLE_RATE
		var rattle_freq: float = 240.0 - 95.0 * t
		rattle_phase += (TAU * rattle_freq) / SAMPLE_RATE
		var white: float = randf_range(-1.0, 1.0)
		lp1 = lp1 * 0.85 + white * 0.15
		lp2 = lp2 * 0.85 + lp1 * 0.15
		var attack: float = minf(1.0, t * 50.0)
		var thud_env: float = attack * pow(1.0 - t, 2.1)
		var bounce_t: float = maxf(0.0, (t - 0.24) / 0.36)
		var secondary_knock: float = sin(PI * bounce_t) * sin(rattle_phase) * 0.13 if (t >= 0.24 and t <= 0.6) else 0.0
		var net_env: float = sin(PI * minf(1.0, (t - 0.08) / 0.85)) if t > 0.08 else 0.0
		var net_rustle: float = lp2 * 0.65 * net_env
		data[i] = sin(thud_phase) * 0.38 * thud_env + secondary_knock + net_rustle
	return _samples_to_wav(data)

# --- Sandbox Contraption Procedural Buffers ---

func _render_scale_creak_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.14)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var p1: float = 0.0
	var p2: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var freq: float = 145.0 + 35.0 * sin(t * PI * 3.0)
		p1 += (TAU * freq) / SAMPLE_RATE
		p2 += (TAU * (freq * 2.45)) / SAMPLE_RATE
		var env: float = sin(PI * t) * 0.2
		data[i] = (sin(p1) * 0.65 + sin(p2) * 0.35) * env
	return _samples_to_wav(data)

func _render_scale_settle_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.11)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var freq: float = 240.0 * pow(0.45, t)
		phase += (TAU * freq) / SAMPLE_RATE
		var attack: float = minf(1.0, t * 55.0)
		var env: float = attack * pow(1.0 - t, 2.4)
		data[i] = sin(phase) * 0.28 * env
	return _samples_to_wav(data)

func _render_tube_suck_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.28)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var lp1: float = 0.0
	var lp2: float = 0.0
	var tone_phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var white: float = randf_range(-1.0, 1.0)
		lp1 = lp1 * 0.82 + white * 0.18
		lp2 = lp2 * 0.82 + lp1 * 0.18
		var freq: float = 220.0 + 620.0 * pow(t, 1.4)
		tone_phase += (TAU * freq) / SAMPLE_RATE
		var env: float = sin(PI * pow(t, 0.7))
		data[i] = (lp2 * 0.65 + sin(tone_phase) * 0.18) * env
	return _samples_to_wav(data)

func _render_tube_shoot_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.22)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var pop_phase: float = 0.0
	var lp: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var pop_freq: float = 320.0 + 540.0 * pow(1.0 - t, 2.2)
		pop_phase += (TAU * pop_freq) / SAMPLE_RATE
		var white: float = randf_range(-1.0, 1.0)
		lp = lp * 0.78 + white * 0.22
		var attack: float = minf(1.0, t * 65.0)
		var env: float = attack * pow(1.0 - t, 1.7)
		data[i] = (sin(pop_phase) * 0.34 + lp * 0.32) * env
	return _samples_to_wav(data)

func _render_cannon_load_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.24)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var thump_phase: float = 0.0
	var latch_phase: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var thump_freq: float = 135.0 * pow(0.4, t)
		thump_phase += (TAU * thump_freq) / SAMPLE_RATE
		latch_phase += (TAU * 980.0) / SAMPLE_RATE
		var latch_env: float = sin(((t - 0.45) / 0.17) * PI) if (t > 0.45 and t < 0.62) else 0.0
		var env: float = minf(1.0, t * 40.0) * pow(1.0 - t, 1.9)
		data[i] = sin(thump_phase) * 0.35 * env + sin(latch_phase) * 0.2 * latch_env
	return _samples_to_wav(data)

func _render_cannon_fire_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.52)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var sub_phase: float = 0.0
	var punch_phase: float = 0.0
	var lp1: float = 0.0
	var lp2: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var punch_freq: float = 190.0 * pow(0.18, pow(t, 0.6))
		punch_phase += (TAU * punch_freq) / SAMPLE_RATE
		sub_phase += (TAU * (punch_freq * 0.48)) / SAMPLE_RATE
		var white: float = randf_range(-1.0, 1.0)
		lp1 = lp1 * 0.9 + white * 0.1
		lp2 = lp2 * 0.9 + lp1 * 0.1
		var attack: float = minf(1.0, t * 70.0)
		var sub_env: float = attack * pow(1.0 - t, 1.5)
		var blast_env: float = attack * pow(1.0 - t, 2.0)
		data[i] = (sin(punch_phase) * 0.48 + sin(sub_phase) * 0.34) * sub_env + lp2 * 1.25 * blast_env
	return _samples_to_wav(data)

func _render_block_crack_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.14)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var p1: float = 0.0
	var lp: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var freq: float = 520.0 * pow(0.35, t)
		p1 += (TAU * freq) / SAMPLE_RATE
		var white: float = randf_range(-1.0, 1.0)
		lp = lp * 0.72 + white * 0.28
		var env: float = minf(1.0, t * 80.0) * pow(1.0 - t, 2.6)
		data[i] = (sin(p1) * 0.26 + lp * 0.45) * env
	return _samples_to_wav(data)

func _render_block_break_buffer() -> AudioStreamWAV:
	var length: int = int(SAMPLE_RATE * 0.36)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(length)
	var low_phase: float = 0.0
	var grit_phase: float = 0.0
	var lp: float = 0.0
	for i in range(length):
		var t: float = float(i) / float(length)
		var low_freq: float = 165.0 * pow(0.28, t)
		low_phase += (TAU * low_freq) / SAMPLE_RATE
		grit_phase += (TAU * (410.0 - 260.0 * t)) / SAMPLE_RATE
		var white: float = randf_range(-1.0, 1.0)
		lp = lp * 0.8 + white * 0.2
		var attack: float = minf(1.0, t * 75.0)
		var env: float = attack * pow(1.0 - t, 1.85)
		data[i] = (sin(low_phase) * 0.36 + sin(grit_phase) * 0.18 + lp * 0.85) * env
	return _samples_to_wav(data)