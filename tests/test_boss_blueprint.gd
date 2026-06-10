extends SceneTree
# Headless sanity test: generate boss blueprints across the difficulty range
# and assert structural invariants. Run with:
#   godot --headless --path . --script res://tests/test_boss_blueprint.gd

func _init() -> void:
	var failures := 0
	for i in range(60):
		var difficulty := float(i % 11) / 10.0
		var theme := i % 6
		var bp := BossBlueprint.generate(1000 + i, theme, difficulty)

		if bp.max_hp <= 0:
			print("FAIL: non-positive hp — ", bp.describe())
			failures += 1
		var total_abilities: int = bp.phase_abilities[1].size() + bp.phase_abilities[2].size() + bp.phase_abilities[3].size()
		if total_abilities == 0:
			print("FAIL: no abilities — ", bp.describe())
			failures += 1
		if bp.phase_abilities[1].is_empty():
			print("FAIL: no phase-1 ability — ", bp.describe())
			failures += 1
		if total_abilities > bp.slot_count:
			print("FAIL: abilities exceed slots — ", bp.describe())
			failures += 1
		for p in [1, 2, 3]:
			for id in bp.phase_abilities[p]:
				if BossAbilities.get_def(id).is_empty():
					print("FAIL: unknown ability id '%s'" % id)
					failures += 1
		if bp.phase_count == 2 and not bp.phase_abilities[3].is_empty():
			print("FAIL: 2-phase boss has phase-3 ability — ", bp.describe())
			failures += 1
		# Determinism
		var bp2 := BossBlueprint.generate(1000 + i, theme, difficulty)
		if bp2.describe() != bp.describe():
			print("FAIL: non-deterministic for seed %d" % (1000 + i))
			failures += 1

	# Show a sample across difficulties
	for d in [0.1, 0.5, 0.9]:
		print("SAMPLE d=%.1f: " % d, BossBlueprint.generate(42, 0, d).describe())

	if failures == 0:
		print("ALL BLUEPRINT TESTS PASSED (60 generations)")
	else:
		print("%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)
