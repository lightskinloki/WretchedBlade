extends Node2D
# Boss runtime smoke test. Run with:
#   godot --headless --path . res://tests/BossSmokeTest.tscn
# Spawns a boss of each body type with a stub player, steps several seconds of
# physics, deals damage to force phase transitions and death, then quits.

var _frame := 0
var _stage := 0
var _boss: BossEnemy
var _player: CharacterBody2D
var _failures := 0
var _events: Array = []

func _ready() -> void:
	add_to_group("world")
	_player = _make_stub_player()
	add_child(_player)
	_next_boss()

func _make_stub_player() -> CharacterBody2D:
	var p := CharacterBody2D.new()
	p.set_script(load("res://tests/StubPlayer.gd"))
	p.position = Vector2(100, 100)
	return p

func _next_boss() -> void:
	if _boss and is_instance_valid(_boss):
		_boss.queue_free()
	if _stage >= 7:
		_finish()
		return
	# Force each body type by re-rolling seeds until the wanted type appears
	var want := _stage
	var bp: BossBlueprint = null
	for s in range(5000):
		# Try multiple difficulty tiers — each body type only appears in
		# certain distribution tiers (Axis 4 step 1).
		for d in [0.8, 0.5, 0.15]:
			var candidate := BossBlueprint.generate(s, s % 6, d)
			if candidate.body_type == want:
				bp = candidate
				break
		if bp != null:
			break
	if bp == null:
		print("FAIL: could not roll body type %d" % want)
		_failures += 1
		_stage += 1
		_next_boss()
		return
	_boss = BossEnemy.spawn_for_dungeon(bp, Vector2(200, 100))
	add_child(_boss)
	var phases_seen: Array = []
	_boss.phase_changed.connect(func(p): phases_seen.append(p))
	_boss.boss_defeated.connect(func(): _events.append("defeated_%d" % want))
	print("TEST stage=%d %s" % [_stage, bp.describe()])
	_frame = 0

func _physics_process(_delta: float) -> void:
	_frame += 1
	if _boss == null or not is_instance_valid(_boss):
		_stage += 1
		_next_boss()
		return
	# Let the boss act for 1.5s, then chip it down to force phases + death
	if _frame > 90 and _frame % 10 == 0:
		_boss.take_damage(int(_boss.blueprint.max_hp * 0.08), Vector2(50, 0))
	if _boss.is_boss_defeated and _frame % 30 == 0:
		_stage += 1
		_next_boss()
	if _frame > 1800:
		print("FAIL: stage %d timed out (boss not defeated)" % _stage)
		_failures += 1
		_stage += 1
		_next_boss()

func _finish() -> void:
	var defeated := 0
	for e in _events:
		if String(e).begins_with("defeated"):
			defeated += 1
	print("DEFEATED: %d/7" % defeated)
	if _failures == 0 and defeated == 7:
		print("ALL BOSS SMOKE TESTS PASSED")
	else:
		print("%d FAILURES" % maxi(_failures, 7 - defeated))
	get_tree().quit(0 if (_failures == 0 and defeated == 7) else 1)
