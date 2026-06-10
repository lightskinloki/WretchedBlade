extends RefCounted
class_name BossAbilities
# BossAbilities.gd — Axis 3 data: all boss ability definitions.
#
# Abilities are data, not scripts. BossEnemy executes them through a generic
# behavior-category executor. Each definition carries:
#   cat        — behavior category (drives the executor)
#   windup / active / recovery — timing in seconds
#   cd         — cooldown seconds
#   damage     — base damage (int); arrays for multi-hit
#   range_px   — activation range used by the pattern controller
#   phase      — minimum phase this ability can appear in (1-3)
#   counterable — "no" | "yes" | "partial"
#   counter_window — fraction of windup (from the end) that is counterable
#   params     — category-specific tuning
# See BOSS_DESIGN.md Axis 3 tables.

enum Cat {
	MELEE,            # arc/contact hit near the boss
	AOE_PULSE,        # radial or cone burst (point-blank or targeted)
	CHARGE,           # horizontal rush, stops at wall
	LEAP,             # jump to the player's position, damage on landing
	PROJECTILE,       # ranged shot — straight, lobbed, homing, spread, boomerang
	DELAYED_AOE,      # marker at player position → delay → blast (Artillery/Meteor)
	BEAM,             # charged line attack across the arena
	SUMMON,           # spawn minions or decoys
	BUFF,             # self status: enrage / shield / invisibility / parry stance
	TELEPORT_STRIKE,  # blink to the player and hit
	REPOSITION,       # blink/evade without damage
	ROOT,             # root, pull, stun, or control-invert on the player
	HAZARD_DROP,      # leave a ground hazard (poison pool, mine)
}

# Universal abilities — every boss
const U_DODGE_DASH := "u_dodge_dash"
const U_PHASE_SHIFT := "u_phase_shift"
const U_SUMMON_MINION := "u_summon_minion"

const DEFS := {
	# ── Universal ────────────────────────────────────────────────────────────
	"u_dodge_dash": {
		"name": "Dodge Dash", "cat": Cat.REPOSITION,
		"windup": 0.05, "active": 0.12, "recovery": 0.05, "cd": 2.5,
		"damage": 0, "range_px": 0, "phase": 1, "counterable": "no",
		"params": {"distance": 60.0, "iframes": true},
	},
	"u_phase_shift": {
		"name": "Phase Shift", "cat": Cat.AOE_PULSE,
		"windup": 0.5, "active": 0.8, "recovery": 0.3, "cd": 999.0,
		"damage": 8, "range_px": 60, "phase": 1, "counterable": "no",
		"params": {"radius": 60.0, "knockback": 220.0, "self_invuln": 1.0},
	},
	"u_summon_minion": {
		"name": "Summon Minion", "cat": Cat.SUMMON,
		"windup": 0.4, "active": 0.1, "recovery": 0.3, "cd": 8.0,
		"damage": 0, "range_px": 9999, "phase": 1, "counterable": "no",
		"params": {"count": 1, "count_hard": 2},
	},

	# ── Bruiser ──────────────────────────────────────────────────────────────
	"b_ground_slam": {
		"name": "Ground Slam", "cat": Cat.AOE_PULSE,
		"windup": 0.6, "active": 0.3, "recovery": 0.5, "cd": 4.0,
		"damage": 14, "range_px": 70, "phase": 1,
		"counterable": "yes", "counter_window": 0.33,
		"params": {"radius": 60.0, "ground_wave": true},
	},
	"b_heavy_swipe": {
		"name": "Heavy Swipe", "cat": Cat.MELEE,
		"windup": 0.4, "active": 0.25, "recovery": 0.4, "cd": 2.5,
		"damage": 10, "range_px": 55, "phase": 1,
		"counterable": "yes", "counter_window": 0.5,
		"params": {"arc_px": 50.0},
	},
	"b_charge": {
		"name": "Charge", "cat": Cat.CHARGE,
		"windup": 0.5, "active": 0.6, "recovery": 0.3, "cd": 5.0,
		"damage": 12, "range_px": 400, "phase": 1,
		"counterable": "yes", "counter_window": 0.6,
		"params": {"speed": 320.0},
	},
	"b_rubble_toss": {
		"name": "Rubble Toss", "cat": Cat.PROJECTILE,
		"windup": 0.3, "active": 0.0, "recovery": 0.4, "cd": 3.0,
		"damage": 8, "range_px": 350, "phase": 1, "counterable": "no",
		"params": {"style": "lob", "aoe_radius": 40.0, "speed": 180.0},
	},
	"b_stomp": {
		"name": "Stomp", "cat": Cat.AOE_PULSE,
		"windup": 0.15, "active": 0.1, "recovery": 0.2, "cd": 2.0,
		"damage": 6, "range_px": 40, "phase": 1, "counterable": "no",
		"params": {"radius": 36.0},
	},
	"b_body_slam": {
		"name": "Body Slam", "cat": Cat.LEAP,
		"windup": 0.5, "active": 0.4, "recovery": 0.5, "cd": 6.0,
		"damage": 16, "range_px": 400, "phase": 2,
		"counterable": "partial", "counter_window": 0.3,
		"params": {"land_radius": 50.0},
	},
	"b_enrage": {
		"name": "Enrage", "cat": Cat.BUFF,
		"windup": 0.3, "active": 6.0, "recovery": 0.0, "cd": 12.0,
		"damage": 0, "range_px": 9999, "phase": 2,
		"counterable": "yes", "counter_window": 1.0,
		"params": {"speed_mult": 1.3, "damage_mult": 1.25, "style": "enrage"},
	},

	# ── Skirmisher ───────────────────────────────────────────────────────────
	"s_combo_slash": {
		"name": "Combo Slash", "cat": Cat.MELEE,
		"windup": 0.15, "active": 0.12, "recovery": 0.1, "cd": 2.0,
		"damage": 6, "range_px": 50, "phase": 1,
		"counterable": "yes", "counter_window": 1.0,
		"params": {"arc_px": 45.0, "hits": 3, "hit_gap": 0.27, "counter_first_only": true},
	},
	"s_dash_strike": {
		"name": "Dash Strike", "cat": Cat.CHARGE,
		"windup": 0.2, "active": 0.25, "recovery": 0.2, "cd": 3.0,
		"damage": 10, "range_px": 220, "phase": 1,
		"counterable": "yes", "counter_window": 0.8,
		"params": {"speed": 400.0, "stop_at_player": true},
	},
	"s_whirlwind": {
		"name": "Whirlwind", "cat": Cat.AOE_PULSE,
		"windup": 0.3, "active": 0.4, "recovery": 0.3, "cd": 4.0,
		"damage": 8, "range_px": 55, "phase": 1,
		"counterable": "partial", "counter_window": 0.15,
		"params": {"radius": 50.0, "hits": 2, "hit_gap": 0.2},
	},
	"s_throw_weapon": {
		"name": "Throw Weapon", "cat": Cat.PROJECTILE,
		"windup": 0.2, "active": 0.3, "recovery": 0.2, "cd": 2.5,
		"damage": 7, "range_px": 300, "phase": 1, "counterable": "no",
		"params": {"style": "boomerang", "speed": 260.0},
	},
	"s_kick": {
		"name": "Kick", "cat": Cat.MELEE,
		"windup": 0.15, "active": 0.1, "recovery": 0.15, "cd": 1.8,
		"damage": 5, "range_px": 40, "phase": 1,
		"counterable": "yes", "counter_window": 0.6,
		"params": {"arc_px": 36.0, "knockback": 240.0},
	},
	"s_parry": {
		"name": "Parry", "cat": Cat.BUFF,
		"windup": 0.1, "active": 0.3, "recovery": 0.2, "cd": 4.0,
		"damage": 10, "range_px": 70, "phase": 2, "counterable": "no",
		"params": {"style": "parry", "riposte_damage": 10},
	},
	"s_uppercut": {
		"name": "Uppercut", "cat": Cat.MELEE,
		"windup": 0.2, "active": 0.15, "recovery": 0.25, "cd": 3.0,
		"damage": 9, "range_px": 45, "phase": 2,
		"counterable": "yes", "counter_window": 0.4,
		"params": {"arc_px": 40.0, "launch": 320.0},
	},

	# ── Skitterer ────────────────────────────────────────────────────────────
	"k_quick_swipe": {
		"name": "Quick Swipe", "cat": Cat.MELEE,
		"windup": 0.08, "active": 0.08, "recovery": 0.1, "cd": 1.2,
		"damage": 4, "range_px": 38, "phase": 1,
		"counterable": "yes", "counter_window": 0.6,
		"params": {"arc_px": 34.0},
	},
	"k_leap_attack": {
		"name": "Leap Attack", "cat": Cat.LEAP,
		"windup": 0.2, "active": 0.3, "recovery": 0.15, "cd": 3.0,
		"damage": 7, "range_px": 300, "phase": 1,
		"counterable": "partial", "counter_window": 0.2,
		"params": {"land_radius": 32.0},
	},
	"k_venom_spit": {
		"name": "Venom Spit", "cat": Cat.HAZARD_DROP,
		"windup": 0.15, "active": 0.0, "recovery": 0.15, "cd": 2.5,
		"damage": 3, "range_px": 280, "phase": 1, "counterable": "no",
		"params": {"style": "pool", "pool_dps": 1, "pool_duration": 2.0, "speed": 240.0},
	},
	"k_bind": {
		"name": "Bind", "cat": Cat.ROOT,
		"windup": 0.2, "active": 1.2, "recovery": 0.2, "cd": 5.0,
		"damage": 0, "range_px": 160, "phase": 2, "counterable": "no",
		"params": {"style": "root", "duration": 1.2},
	},
	"k_evade": {
		"name": "Evade", "cat": Cat.REPOSITION,
		"windup": 0.0, "active": 0.2, "recovery": 0.0, "cd": 2.0,
		"damage": 0, "range_px": 90, "phase": 1, "counterable": "no",
		"params": {"behind_player": true},
	},
	"k_flurry": {
		"name": "Flurry", "cat": Cat.MELEE,
		"windup": 0.1, "active": 0.4, "recovery": 0.2, "cd": 4.0,
		"damage": 3, "range_px": 42, "phase": 2, "counterable": "no",
		"params": {"arc_px": 38.0, "hits": 5, "hit_gap": 0.08, "locked_in_place": true},
	},
	"k_venom_burst": {
		"name": "Venom Burst", "cat": Cat.AOE_PULSE,
		"windup": 0.5, "active": 0.2, "recovery": 0.3, "cd": 6.0,
		"damage": 8, "range_px": 60, "phase": 2,
		"counterable": "yes", "counter_window": 0.6,
		"params": {"radius": 55.0},
	},

	# ── Sentinel ─────────────────────────────────────────────────────────────
	"n_volley": {
		"name": "Volley", "cat": Cat.PROJECTILE,
		"windup": 0.3, "active": 0.5, "recovery": 0.3, "cd": 3.0,
		"damage": 5, "range_px": 9999, "phase": 1, "counterable": "no",
		"params": {"style": "spread", "count": 3, "spread_deg": 24.0, "speed": 220.0},
	},
	"n_ground_pulse": {
		"name": "Ground Pulse", "cat": Cat.AOE_PULSE,
		"windup": 0.5, "active": 0.3, "recovery": 0.4, "cd": 4.0,
		"damage": 10, "range_px": 140, "phase": 1,
		"counterable": "yes", "counter_window": 0.5,
		"params": {"radius": 120.0, "expanding": true},
	},
	"n_beam": {
		"name": "Beam", "cat": Cat.BEAM,
		"windup": 0.6, "active": 0.5, "recovery": 0.4, "cd": 5.0,
		"damage": 14, "range_px": 9999, "phase": 2,
		"counterable": "partial", "counter_window": 0.4,
		"params": {"width_px": 10.0, "tracks_player": true},
	},
	"n_shield": {
		"name": "Shield", "cat": Cat.BUFF,
		"windup": 0.2, "active": 2.0, "recovery": 0.2, "cd": 6.0,
		"damage": 0, "range_px": 9999, "phase": 2, "counterable": "no",
		"params": {"style": "shield"},
	},
	"n_mine": {
		"name": "Mine", "cat": Cat.HAZARD_DROP,
		"windup": 0.2, "active": 0.0, "recovery": 0.2, "cd": 3.5,
		"damage": 10, "range_px": 200, "phase": 1, "counterable": "no",
		"params": {"style": "mine", "trigger_radius": 40.0},
	},
	"n_artillery": {
		"name": "Artillery", "cat": Cat.DELAYED_AOE,
		"windup": 0.4, "active": 0.8, "recovery": 0.3, "cd": 5.0,
		"damage": 12, "range_px": 9999, "phase": 2, "counterable": "no",
		"params": {"delay": 1.0, "radius": 60.0},
	},

	# ── Stalker ──────────────────────────────────────────────────────────────
	"l_shadow_strike": {
		"name": "Shadow Strike", "cat": Cat.TELEPORT_STRIKE,
		"windup": 0.1, "active": 0.15, "recovery": 0.2, "cd": 2.0,
		"damage": 8, "range_px": 9999, "phase": 1,
		"counterable": "partial", "counter_window": 1.0,
		"params": {"arc_px": 40.0},
	},
	"l_claw_swipe": {
		"name": "Claw Swipe", "cat": Cat.MELEE,
		"windup": 0.12, "active": 0.1, "recovery": 0.12, "cd": 1.5,
		"damage": 5, "range_px": 42, "phase": 1,
		"counterable": "yes", "counter_window": 0.6,
		"params": {"arc_px": 38.0},
	},
	"l_phase_walk": {
		"name": "Phase Walk", "cat": Cat.BUFF,
		"windup": 0.0, "active": 2.0, "recovery": 0.1, "cd": 5.0,
		"damage": 0, "range_px": 9999, "phase": 2, "counterable": "no",
		"params": {"style": "invis", "next_attack_mult": 2.0},
	},
	"l_shadow_bolt": {
		"name": "Shadow Bolt", "cat": Cat.PROJECTILE,
		"windup": 0.2, "active": 0.4, "recovery": 0.2, "cd": 2.5,
		"damage": 6, "range_px": 350, "phase": 1, "counterable": "no",
		"params": {"style": "homing", "speed": 150.0, "lifetime": 3.0},
	},
	"l_backstab": {
		"name": "Backstab", "cat": Cat.MELEE,
		"windup": 0.1, "active": 0.1, "recovery": 0.2, "cd": 3.0,
		"damage": 12, "range_px": 45, "phase": 2, "counterable": "no",
		"params": {"arc_px": 40.0, "requires_behind": true},
	},
	"l_clone": {
		"name": "Clone", "cat": Cat.SUMMON,
		"windup": 0.3, "active": 0.1, "recovery": 0.2, "cd": 8.0,
		"damage": 0, "range_px": 9999, "phase": 1, "counterable": "no",
		"params": {"style": "decoy"},
	},
	"l_tether": {
		"name": "Tether", "cat": Cat.ROOT,
		"windup": 0.3, "active": 0.5, "recovery": 0.2, "cd": 4.0,
		"damage": 0, "range_px": 180, "phase": 2,
		"counterable": "yes", "counter_window": 1.0,
		"params": {"style": "pull", "pull_time": 0.5},
	},

	# ── Colossus ─────────────────────────────────────────────────────────────
	"c_giant_fist": {
		"name": "Giant Fist", "cat": Cat.MELEE,
		"windup": 0.8, "active": 0.35, "recovery": 0.6, "cd": 5.0,
		"damage": 20, "range_px": 80, "phase": 1,
		"counterable": "yes", "counter_window": 0.3,
		"params": {"arc_px": 70.0, "screen_shake": true},
	},
	"c_stomp": {
		"name": "Stomp", "cat": Cat.AOE_PULSE,
		"windup": 0.3, "active": 0.2, "recovery": 0.3, "cd": 4.0,
		"damage": 8, "range_px": 9999, "phase": 1, "counterable": "no",
		"params": {"radius": 9999.0, "ground_only": true, "screen_shake": true},
	},
	"c_eye_beam": {
		"name": "Eye Beam", "cat": Cat.BEAM,
		"windup": 0.5, "active": 0.8, "recovery": 0.4, "cd": 6.0,
		"damage": 16, "range_px": 9999, "phase": 2,
		"counterable": "yes", "counter_window": 0.5,
		"params": {"width_px": 12.0, "sweep": true},
	},
	"c_meteor": {
		"name": "Meteor", "cat": Cat.DELAYED_AOE,
		"windup": 0.6, "active": 0.6, "recovery": 0.3, "cd": 7.0,
		"damage": 18, "range_px": 9999, "phase": 2, "counterable": "no",
		"params": {"delay": 0.6, "radius": 80.0},
	},
	"c_earthquake": {
		"name": "Earthquake", "cat": Cat.AOE_PULSE,
		"windup": 0.4, "active": 1.0, "recovery": 0.5, "cd": 8.0,
		"damage": 12, "range_px": 9999, "phase": 3,
		"counterable": "yes", "counter_window": 0.6,
		"params": {"radius": 9999.0, "ground_only": true, "screen_shake": true},
	},
	"c_summon_rubble": {
		"name": "Summon Rubble", "cat": Cat.SUMMON,
		"windup": 0.3, "active": 0.5, "recovery": 0.3, "cd": 6.0,
		"damage": 0, "range_px": 9999, "phase": 2, "counterable": "no",
		"params": {"style": "minion", "count": 2},
	},
	"c_roar": {
		"name": "Roar", "cat": Cat.ROOT,
		"windup": 0.6, "active": 0.3, "recovery": 0.3, "cd": 7.0,
		"damage": 0, "range_px": 9999, "phase": 3,
		"counterable": "yes", "counter_window": 0.7,
		"params": {"style": "stun", "duration": 1.0},
	},

	# ── Wraith ───────────────────────────────────────────────────────────────
	"w_ghost_touch": {
		"name": "Ghost Touch", "cat": Cat.MELEE,
		"windup": 0.1, "active": 0.08, "recovery": 0.1, "cd": 1.5,
		"damage": 5, "range_px": 38, "phase": 1, "counterable": "no",
		"params": {"arc_px": 34.0, "pierce_iframes": true},
	},
	"w_shadow_orb": {
		"name": "Shadow Orb", "cat": Cat.PROJECTILE,
		"windup": 0.3, "active": 0.6, "recovery": 0.2, "cd": 3.0,
		"damage": 7, "range_px": 350, "phase": 1, "counterable": "no",
		"params": {"style": "homing", "speed": 120.0, "lifetime": 3.0},
	},
	"w_phase_shift": {
		"name": "Phase Shift", "cat": Cat.BUFF,
		"windup": 0.1, "active": 1.5, "recovery": 0.1, "cd": 6.0,
		"damage": 0, "range_px": 9999, "phase": 1, "counterable": "no",
		"params": {"style": "intangible"},
	},
	"w_spectral_wail": {
		"name": "Spectral Wail", "cat": Cat.AOE_PULSE,
		"windup": 0.4, "active": 0.3, "recovery": 0.3, "cd": 5.0,
		"damage": 5, "range_px": 120, "phase": 2,
		"counterable": "yes", "counter_window": 0.6,
		"params": {"radius": 100.0, "slow_mult": 0.6, "slow_duration": 2.5},
	},
	"w_ethereal_bind": {
		"name": "Ethereal Bind", "cat": Cat.ROOT,
		"windup": 0.35, "active": 1.5, "recovery": 0.3, "cd": 6.0,
		"damage": 3, "range_px": 160, "phase": 2,
		"counterable": "yes", "counter_window": 0.6,
		"params": {"style": "root", "duration": 1.5, "dot_ticks": 3},
	},
	"w_possess": {
		"name": "Possess", "cat": Cat.ROOT,
		"windup": 0.3, "active": 1.2, "recovery": 0.2, "cd": 7.0,
		"damage": 0, "range_px": 160, "phase": 2, "counterable": "no",
		"params": {"style": "invert", "duration": 1.2},
	},
	"w_banshee_scream": {
		"name": "Banshee Scream", "cat": Cat.AOE_PULSE,
		"windup": 0.5, "active": 0.3, "recovery": 0.4, "cd": 6.0,
		"damage": 14, "range_px": 140, "phase": 3,
		"counterable": "yes", "counter_window": 0.5,
		"params": {"radius": 120.0, "cone": true},
	},
}

# Body type → ability pool (BOSS_DESIGN.md Axis 3 / data table body_ability_pools)
const POOLS := {
	BossBodyTypes.BodyType.BRUISER: [
		"b_ground_slam", "b_heavy_swipe", "b_charge", "b_rubble_toss",
		"b_stomp", "b_body_slam", "b_enrage",
	],
	BossBodyTypes.BodyType.SKIRMISHER: [
		"s_combo_slash", "s_dash_strike", "s_whirlwind", "s_throw_weapon",
		"s_kick", "s_parry", "s_uppercut",
	],
	BossBodyTypes.BodyType.SKITTERER: [
		"k_quick_swipe", "k_leap_attack", "k_venom_spit", "k_bind",
		"k_evade", "k_flurry", "k_venom_burst",
	],
	BossBodyTypes.BodyType.SENTINEL: [
		"n_volley", "n_ground_pulse", "u_summon_minion", "n_beam",
		"n_shield", "n_mine", "n_artillery",
	],
	BossBodyTypes.BodyType.STALKER: [
		"l_shadow_strike", "l_claw_swipe", "l_phase_walk", "l_shadow_bolt",
		"l_backstab", "l_clone", "l_tether",
	],
	BossBodyTypes.BodyType.COLOSSUS: [
		"c_giant_fist", "c_stomp", "c_eye_beam", "c_meteor",
		"c_earthquake", "c_summon_rubble", "c_roar",
	],
	BossBodyTypes.BodyType.WRAITH: [
		"w_ghost_touch", "w_shadow_orb", "w_phase_shift", "w_spectral_wail",
		"w_ethereal_bind", "w_possess", "w_banshee_scream",
	],
}

static func get_def(ability_id: String) -> Dictionary:
	return DEFS.get(ability_id, {})

static func get_pool(body_type: int) -> Array:
	return POOLS.get(body_type, POOLS[BossBodyTypes.BodyType.SKIRMISHER])
