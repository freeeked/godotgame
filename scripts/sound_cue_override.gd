class_name SoundCueOverride
extends Resource

@export var sound_name: StringName = &"jump"
@export var custom_stream: AudioStream = null
@export_range(-24.0, 12.0, 0.5) var volume_offset_db: float = 0.0
@export_range(0.25, 2.5, 0.01) var pitch_multiplier: float = 1.0
@export_range(0.0, 0.3, 0.01) var pitch_jitter: float = -1.0 ## -1 uses default engine jitter
@export var cooldown_ms_override: int = -1 ## -1 uses default cooldown