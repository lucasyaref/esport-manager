class_name Combat
extends RefCounted
## Spatial combat engine (GDD §6.1).
##
## Combat is not an event that gets resolved — it is a continuous property of
## the world. Every tick each living player perceives nearby enemies, decides
## whether the fight is worth taking, picks a target, steers to the range its
## character wants to fight at, and swings when it can. Deaths happen because
## HP reached zero, never because a lottery said so.
##
## Positioning is emergent, not scripted: a long-range, low-HP carry drifts to
## the back because kiting keeps it alive; a short-range, high-HP engager has
## to close to do anything. `fight_role` in characters.json biases that, it does
## not dictate it.
##
## The tick contract, driven by SimMatch:
##   1. update_intent(t)    — before movement: perceive, commit, target, steer
##   2. (agents move)
##   3. resolve_attacks(t)  — after movement: ultimates, swings, deaths, events
##
## Determinism: agents are iterated in fixed array order, decisions are staged
## into parallel arrays and committed at once (so no agent's choice depends on
## where it sits in the array), and every draw goes through m.rng.

var m: SimMatch  # back-reference, set per-match; cleared by SimMatch at end of run()

# victim idx -> {attacker idx: tick of last hit}. Drives kill credit + assists.
var _damage_log: Dictionary = {}
# fight id -> {members: Array[int], started: int, last_seen: int, pos: Vector2,
#              context: String, deaths: {blue: int, red: int}}
var _fights: Dictionary = {}
var _next_fight_id := 1
# Per-tick threat cache, indexed by agent idx (see threat()).
var _threat_cache: Array[float] = []
var _threat_tick := -1


func _init(match_ref: SimMatch) -> void:
	m = match_ref


# --- tick phase 1: perceive and decide ---------------------------------------

## Sets in_combat / disengaging / target_idx / desired_pos on every agent.
## Decisions are staged and committed together so that an agent's choice never
## depends on whether its team-mates were processed before or after it.
func update_intent(t: int) -> void:
	var f: Dictionary = m.balance.fight
	var awareness := float(f.awareness_radius)
	var n := m.agents.size()
	var engaged: Array[bool] = []
	var backing_off: Array[bool] = []
	var targets: Array[int] = []
	var stands: Array[Vector2] = []
	var speeds: Array[float] = []
	engaged.resize(n)
	backing_off.resize(n)
	targets.resize(n)
	stands.resize(n)
	speeds.resize(n)

	for i in n:
		var agent: PlayerAgent = m.agents[i]
		engaged[i] = false
		backing_off[i] = false
		targets[i] = -1
		stands[i] = agent.pos
		speeds[i] = 1.0
		if not agent.alive or agent.state == PlayerAgent.State.RECALLING:
			continue
		var enemies := _near(agent, awareness, true)
		if enemies.is_empty():
			continue
		var allies := _near(agent, awareness, false)
		# Hysteresis: a player who has just broken off a fight stays broken off
		# for a few seconds. Without it, agents re-evaluate every tick, bounce
		# straight back into range, and one engagement reads as twenty.
		agent.decline_reason = ""
		var commit := _wants_to_fight(agent, allies, enemies, t)
		if commit and _chase_exhausted(agent, t, f):
			commit = false
			agent.decline_reason = "chase"
		var tgt: PlayerAgent = null
		var stand := agent.pos
		if commit and t >= agent.disengage_until:
			tgt = _select_target(agent, allies, enemies, t, f)
			stand = _stand_pos(agent, tgt, allies, enemies, f)
			# The third way a chase ends, and the one that reads best: the runner
			# makes it home and the pursuers peel off at the tower line.
			if m.objectives.under_enemy_tower(agent.team, stand) \
					and not _dive_worth_it(agent, tgt, allies, enemies, t, f):
				commit = false
				agent.decline_reason = "tower"
		if t < agent.disengage_until:
			commit = false
			agent.decline_reason = "locked"
		elif not commit and agent.in_combat and not agent.disengaging:
			# The lock is hysteresis for *breaking off*: someone who was fighting
			# and pulled out stays out for a few seconds instead of bouncing back
			# in every tick. It must not apply to a body that has not engaged yet.
			#
			# It used to fire on every decline, which locked out the arriving
			# reinforcement: a third man walking into a 1v1 sees the two enemies
			# before his own ally is inside his awareness radius, reads the local
			# numbers as 1v2, declines — and is then barred from the fight for
			# twelve seconds, which is twice as long as the average fight lasts.
			# That is most of why 1.4 bodies per fight stood in range of an enemy
			# without swinging (M5-G).
			agent.disengage_until = t + int(
				float(f.disengage_lock_s) * SimMatch.TICKS_PER_SECOND)
		if not commit:
			# Declining a fight only overrides what this agent was doing if the
			# threat is actually close. Otherwise the FSM keeps running, so a
			# laner facing an opponent across the wave still farms — and still
			# goes home on its own when it gets low.
			if agent.pos.distance_to(_closest(agent.pos, enemies).pos) <= float(f.danger_radius):
				engaged[i] = true
				backing_off[i] = true
				stands[i] = _retreat_pos(agent, enemies, f)
				# Backing off is not surrendering: anything already in reach
				# still gets shot at on the way out.
				var chased := _closest(agent.pos, enemies)
				if agent.pos.distance_to(chased.pos) <= float(agent.character.combat.attack_range):
					targets[i] = chased.idx
			continue
		# A fresh commitment anchors the leash and restarts the patience clock.
		if not agent.in_combat or agent.disengaging:
			agent.commit_pos = agent.pos
			agent.last_hit_at = t
		engaged[i] = true
		targets[i] = tgt.idx
		stands[i] = stand
		# Gap closers, abstracted: a frontline or flank character crossing open
		# ground to reach its target moves faster than it walks. Without it the
		# approach is free damage for whoever is already in range.
		var cmb: Dictionary = agent.character.combat
		if cmb.fight_role in ["frontline", "flank"] \
				and agent.pos.distance_to(tgt.pos) > float(cmb.attack_range):
			speeds[i] = 1.0 + float(f.engage_speed_bonus)

	for i in n:
		var agent: PlayerAgent = m.agents[i]
		agent.in_combat = engaged[i]
		agent.disengaging = backing_off[i]
		agent.target_idx = targets[i]
		agent.desired_pos = stands[i]
		agent.speed_mult = speeds[i]
	_update_fights(t)


# --- tick phase 2: act --------------------------------------------------------

func resolve_attacks(t: int) -> void:
	for agent in m.agents:
		if agent.alive and t >= agent.stunned_until:
			# Two ability slots, one firing rule (§3): the basic first (the early
			# CC that catches), then the ultimate.
			_try_ability(agent, "basic_ability", t, m.balance.fight)
			_try_ability(agent, "ultimate", t, m.balance.fight)
	for agent in m.agents:
		if not agent.alive or agent.target_idx < 0 or t < agent.stunned_until:
			continue
		var tgt: PlayerAgent = m.agents[agent.target_idx]
		if not tgt.alive:
			continue
		if agent.pos.distance_to(tgt.pos) > float(agent.character.combat.attack_range):
			continue
		if t < agent.attack_ready_at:
			continue
		var period := float(SimMatch.TICKS_PER_SECOND) / float(agent.character.combat.attack_speed)
		agent.attack_ready_at = t + maxi(1, int(period))
		# Stamped for playback: the viewer turns each swing into a visible attack
		# beat (projectile / hit tick), which is what makes a fight read as an
		# exchange rather than two dots touching (M5.5-B). Sim-inert.
		agent.last_swing_at = t
		_deal_damage(t, agent, tgt, _attack_damage(agent, tgt, t))


## How dangerous a player is right now: stats at level x items x mechanics x
## phase curve x comp modifiers. Used for target priority and commit decisions
## (and, scaled, for ultimate impact) — the same shape the M3 resolver used.
##
## Cached per tick: target selection and commit checks ask for it O(n^2) times
## a tick, and recomputing it there dominated the batch-run cost. Levels and
## gold earned mid-tick land in the next tick's numbers, which is invisible at
## 10 ticks a second and keeps the cache deterministic.
func threat(agent: PlayerAgent, t: int) -> float:
	if t != _threat_tick:
		_threat_tick = t
		_threat_cache.resize(m.agents.size())
		for i in m.agents.size():
			_threat_cache[i] = _threat_uncached(m.agents[i], t)
	return _threat_cache[agent.idx]


func _threat_uncached(agent: PlayerAgent, t: int) -> float:
	var c: Dictionary = m.balance.combat
	var damage := DataLoader.stat_at_level(agent.character, "damage", agent.level)
	var hp := DataLoader.stat_at_level(agent.character, "hp", agent.level)
	var armor := DataLoader.stat_at_level(agent.character, "armor", agent.level)
	var ehp := hp * (1.0 + armor / 100.0)
	var item_factor: float = 1.0 + agent.item_power / float(c.power_item_divisor)
	var mech: float = float(c.mechanics_power_base) \
		+ float(agent.attrs.mechanics) / float(c.mechanics_power_divisor)
	# An offensive passive makes a player more threatening (more damage, valued
	# higher as a target); a defensive passive shows up in survival, not here.
	return damage * item_factor * mech * m.phase_curve_mult(agent.character.curve, t) \
		* m.mood_mult(agent.id) * sqrt(ehp / float(c.ehp_norm)) * float(agent.passive_power)


# --- perception ---------------------------------------------------------------

func _near(agent: PlayerAgent, radius: float, hostile: bool) -> Array:
	var out: Array = []
	for other in m.agents:
		if other.idx == agent.idx or not other.alive:
			continue
		if (other.team != agent.team) != hostile:
			continue
		if agent.pos.distance_to(other.pos) <= radius:
			out.append(other)
	return out


## Commit decision: worth fighting only if my side's live power stands up to
## theirs. Laning uses a stricter margin and a higher bail-out threshold, which
## is what turns a lane into trade-and-back-off instead of a duel to the death.
func _wants_to_fight(agent: PlayerAgent, allies: Array, enemies: Array, t: int) -> bool:
	var f: Dictionary = m.balance.fight
	# Laning restraint applies to the whole early game, not just once someone
	# has settled into FARMING — otherwise level-1 players brawl on the walk
	# out of base and first blood lands at a minute.
	var laning: bool = m.phase_of(t) == "early" and agent.state in [
		PlayerAgent.State.FARMING, PlayerAgent.State.TO_LANE]
	if agent.hp_fraction() <= float(f.lane_disengage_hp if laning else f.disengage_hp):
		agent.decline_reason = "low_hp"
		return false
	var mine := _live_power(agent, t)
	for ally: PlayerAgent in allies:
		mine += _live_power(ally, t)
	var theirs := 0.0
	for enemy: PlayerAgent in enemies:
		theirs += _live_power(enemy, t)
	if mine >= theirs * float(f.lane_commit_margin if laning else f.commit_margin):
		return true
	agent.decline_reason = "numbers"
	return false


## When to stop chasing. Everyone moves at the same speed, so a runner is never
## caught by walking after it: without this, a healthy team keeps passing
## _wants_to_fight against one fleeing enemy and follows it across the map
## forever (M4.5-B playtest). Two ways out — nothing landed for a while, or the
## chase has dragged us too far from where we chose to fight. The third, tower
## lines, is in update_intent where the destination is known.
func _chase_exhausted(agent: PlayerAgent, t: int, f: Dictionary) -> bool:
	if not agent.in_combat or agent.disengaging:
		return false  # not chasing anything yet
	if t - agent.last_hit_at > int(float(f.chase_patience_s) * SimMatch.TICKS_PER_SECOND):
		return true
	return agent.pos.distance_to(agent.commit_pos) > float(f.leash_radius)


## Standing under a live enemy tower has to be paid for, so it takes a reason:
## a target already nearly dead, or enough of a local advantage that the tower
## can hit somebody who can afford it. Never on low health. That is the
## difference between "they dove him" and "he wandered into the turret".
func _dive_worth_it(agent: PlayerAgent, tgt: PlayerAgent, allies: Array, enemies: Array,
		t: int, f: Dictionary) -> bool:
	if agent.hp_fraction() < float(f.dive_hp):
		return false
	if tgt.hp_fraction() <= float(f.dive_target_hp):
		return true
	# Numbers make a dive: a jungler arriving on a 2v1 goes in, a solo laner
	# who merely won the trade does not.
	var mine := _live_power(agent, t)
	for ally: PlayerAgent in allies:
		mine += _live_power(ally, t)
	var theirs := 0.0
	for enemy: PlayerAgent in enemies:
		theirs += _live_power(enemy, t)
	return mine >= theirs * float(f.dive_margin)


## How much punishment a player can absorb: stats at level, a defensive passive,
## and — the part that matters for who gets picked on — **gold**. A support earns
## a little over half what the carry does, so it is the squishiest body on the
## map by the mid game; `threat` counts that gold as damage only, which is why
## the support was simultaneously the least dangerous and (wrongly) no easier to
## kill than a fed carry. Target selection reads this; `threat` deliberately does
## not, because being hard to kill is not what makes someone dangerous.
func _ehp(agent: PlayerAgent) -> float:
	var hp := DataLoader.stat_at_level(agent.character, "hp", agent.level)
	var armor := DataLoader.stat_at_level(agent.character, "armor", agent.level)
	var items: float = 1.0 + agent.item_power / float(m.balance.combat.power_item_divisor)
	return hp * (1.0 + armor / 100.0) * items / maxf(float(agent.passive_guard), 0.01)


## Power discounted by how much health is left to spend on the fight.
func _live_power(agent: PlayerAgent, t: int) -> float:
	return threat(agent, t) * agent.hp_fraction()


func _select_target(agent: PlayerAgent, allies: Array, enemies: Array, t: int,
		f: Dictionary) -> PlayerAgent:
	var cmb: Dictionary = agent.character.combat
	var reach := float(cmb.attack_range)
	var ward: PlayerAgent = _protect_ally(agent, allies) if cmb.fight_role == "peel" else null
	var best: PlayerAgent = enemies[0]
	var best_score := -1.0
	for enemy: PlayerAgent in enemies:
		# Reachability dominates — you fight what you can actually hit. This is
		# what keeps a backline carry from suiciding into the enemy frontline.
		var gap: float = maxf(agent.pos.distance_to(enemy.pos) - reach, 0.0)
		var score: float = 1.0 / (1.0 + gap / float(f.reach_falloff))
		score *= 1.0 + (1.0 - enemy.hp_fraction()) * float(f.low_hp_focus)  # finish the wounded
		score *= threat(enemy, t) / float(f.threat_norm)                    # kill what kills you
		# Killability, not only value. Threat is built out of damage and gold, so
		# the enemy support — least damage, least gold — was nobody's target and
		# finished games having died once ("support healer never being dead",
		# 2026-07-26 remark 3). Pros kill what they can finish: a squishy in reach
		# is a kill, a tank in reach is a fight you spend and do not win.
		#
		# GATED OFF (squishy_bias = 0). Measured at 2.0 and at 4.0 over 200 sims
		# each: the support's share of all deaths moved 12.3% → 12.4% → 13.0%.
		# Target selection is not why supports survive — they are simply not in
		# the fights (43% of kills happen in mid lane, 12% in top). Left wired so
		# M5-G only has to turn the dial if the real cause is found; the diagnosis
		# is in REPORTS/M5-F1.md.
		score *= pow(float(f.squishy_ehp_ref) / maxf(_ehp(enemy), 1.0),
			float(f.squishy_bias))
		if cmb.fight_role == "flank" and enemy.character.combat.fight_role == "backline":
			score *= float(f.flank_backline_bias)
		if ward != null and enemy.target_idx == ward.idx:
			score *= float(f.peel_target_bias)  # get off my carry
		# Somebody else's problem: an enemy already being handled by team-mates
		# is worth less than the one nobody is on. Five players scoring targets
		# with the same formula all picked the same victim, which is why a fight
		# read as the whole team chasing one runner.
		var on_it := 0
		for ally: PlayerAgent in allies:
			if ally.target_idx == enemy.idx:
				on_it += 1
		score /= 1.0 + float(f.focus_penalty) * on_it
		if score > best_score:
			best_score = score
			best = enemy
	return best


# --- steering -----------------------------------------------------------------

## Where this agent wants to stand this tick, given who it is fighting.
func _stand_pos(agent: PlayerAgent, tgt: PlayerAgent, allies: Array, enemies: Array,
		f: Dictionary) -> Vector2:
	var cmb: Dictionary = agent.character.combat
	var off_target := agent.pos - tgt.pos
	if off_target.length() < 0.001:
		off_target = agent.pos - m.map.bases[_enemy_of(agent.team)]
	if off_target.length() < 0.001:
		off_target = Vector2.RIGHT
	# Stand just inside our own reach, never exactly on it — a target that drifts
	# a hair further away should not silently stop the fight.
	var hold := minf(float(cmb.preferred_range), float(cmb.attack_range) - float(f.stand_inset))
	var stand := tgt.pos + off_target.normalized() * hold
	match String(cmb.fight_role):
		"frontline":
			# Close, and put yourself between the enemy and your own squishies.
			var screen := _backline_centroid(agent, allies)
			if screen != Vector2.ZERO:
				stand = stand.lerp(tgt.pos.lerp(screen, float(f.frontline_screen_lerp)),
					float(f.frontline_screen))
		"backline":
			# Hold range and drift off whoever is closest — this is the kiting
			# that makes a carry survive long enough to matter.
			var threat_src := _closest(agent.pos, enemies)
			var away := agent.pos - threat_src.pos
			if away.length() > 0.001:
				stand += away.normalized() * float(f.backline_kite)
		"peel":
			# Stand between the carry and whatever is closing on it.
			var ward := _protect_ally(agent, allies)
			if ward != null:
				var closing := _closest(ward.pos, enemies)
				var toward := closing.pos - ward.pos
				if toward.length() > 0.001:
					stand = ward.pos + toward.normalized() * float(f.peel_standoff)
		"flank":
			pass  # straight at the target, by design
	# Whatever the role bias asked for, the spot has to be one we can attack
	# from. Without this clamp a kiting carry walks out of its own range and
	# the fight never resolves.
	var offset := stand - tgt.pos
	if offset.length() > hold:
		stand = tgt.pos + offset.normalized() * hold
	return stand


func _retreat_pos(agent: PlayerAgent, enemies: Array, f: Dictionary) -> Vector2:
	var centroid := Vector2.ZERO
	for enemy: PlayerAgent in enemies:
		centroid += enemy.pos
	centroid /= float(enemies.size())
	var away := agent.pos - centroid
	if away.length() < 0.001:
		away = agent.pos - m.map.bases[_enemy_of(agent.team)]
	var home: Vector2 = m.map.bases[agent.team] - agent.pos
	var dir := away.normalized()
	if home.length() > 0.001:
		dir += home.normalized() * float(f.retreat_home_bias)
	if dir.length() < 0.001:
		dir = Vector2.RIGHT
	return agent.pos + dir.normalized() * float(f.retreat_step)


## The ally a peeler is looking after: the most dangerous backline team-mate.
func _protect_ally(_agent: PlayerAgent, allies: Array) -> PlayerAgent:
	var best: PlayerAgent = null
	var best_hp := -1.0
	for ally: PlayerAgent in allies:
		if ally.character.combat.fight_role != "backline":
			continue
		if ally.max_hp > best_hp:
			best_hp = ally.max_hp
			best = ally
	return best


func _backline_centroid(_agent: PlayerAgent, allies: Array) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for ally: PlayerAgent in allies:
		if ally.character.combat.fight_role in ["backline", "peel"]:
			sum += ally.pos
			count += 1
	return sum / float(count) if count > 0 else Vector2.ZERO


func _closest(from: Vector2, candidates: Array) -> PlayerAgent:
	var best: PlayerAgent = candidates[0]
	var best_d := INF
	for c: PlayerAgent in candidates:
		var d := from.distance_to(c.pos)
		if d < best_d:
			best_d = d
			best = c
	return best


# --- damage and death ---------------------------------------------------------

func _attack_damage(agent: PlayerAgent, victim: PlayerAgent, t: int) -> float:
	var f: Dictionary = m.balance.fight
	var c: Dictionary = m.balance.combat
	var dmg := DataLoader.stat_at_level(agent.character, "damage", agent.level)
	dmg *= 1.0 + agent.item_power / float(c.power_item_divisor)
	dmg *= float(c.mechanics_power_base) \
		+ float(agent.attrs.mechanics) / float(c.mechanics_power_divisor)
	dmg *= m.phase_curve_mult(agent.character.curve, t)
	dmg *= m.mood_mult(agent.id)
	dmg *= m.team_comp_mult(agent.team, t)
	dmg *= 1.0 + m.objectives.team_buff(agent.team)
	dmg *= float(agent.passive_power)  # offensive passive (defensive applied on the victim)
	if t < agent.steroid_until:
		dmg *= float(f.steroid_damage_mult)
	# Reach is paid for in damage. A melee character has to walk through the
	# fight to do anything, so it hits harder than one that never leaves the
	# back — the standard MOBA trade, stated once here rather than hand-tuned
	# into fifteen characters. Without it an all-ranged draft is unbeatable.
	var reach := float(agent.character.combat.attack_range)
	dmg *= 1.0 + (float(f.max_reach) - reach) / float(f.max_reach) * float(f.melee_damage_bonus)
	dmg *= float(f.damage_scale)
	dmg *= 1.0 + m.rng.randf_range(-float(f.damage_variance), float(f.damage_variance))
	var armor := DataLoader.stat_at_level(victim.character, "armor", victim.level)
	return dmg * 100.0 / (100.0 + armor)


func _deal_damage(t: int, attacker: PlayerAgent, victim: PlayerAgent, amount: float) -> void:
	if not victim.alive or amount <= 0.0:
		return
	# Defensive passives reduce all incoming player damage in one place; offensive
	# passives are already baked into `amount` (auto damage / ability power).
	var dealt: float = amount * float(victim.passive_guard)
	victim.take_damage(dealt, t)
	if float(attacker.passive_sustain) > 0.0:
		attacker.hp = minf(attacker.hp + dealt * float(attacker.passive_sustain), attacker.max_hp)
	attacker.last_hit_at = t
	var hits: Dictionary = _damage_log.get(victim.idx, {})
	hits[attacker.idx] = t
	_damage_log[victim.idx] = hits
	if victim.hp <= 0.0:
		_kill(t, attacker, victim, "player")


## Damage from a structure. Called by Objectives — towers have no PlayerAgent
## behind them, which is why kill credit needs its own rule below.
func tower_damage(t: int, defender_team: String, tower_pos: Vector2, victim: PlayerAgent,
		amount: float) -> void:
	if not victim.alive or amount <= 0.0:
		return
	victim.take_damage(amount, t)
	if victim.hp > 0.0:
		return
	_kill(t, _tower_credit(t, defender_team, tower_pos, victim), victim, "tower")


## Who gets a tower kill: the defender who was last trading with the diver — the
## reason it was low enough to die — else the closest defender under the tower,
## else nobody. A dive that nobody was home to punish still reads as "the turret
## got him", which is a true and useful thing for the feed to say.
func _tower_credit(t: int, defender_team: String, tower_pos: Vector2,
		victim: PlayerAgent) -> PlayerAgent:
	var window := int(float(m.balance.fight.assist_window_s) * SimMatch.TICKS_PER_SECOND)
	var best: PlayerAgent = null
	var best_t := -1
	var hits: Dictionary = _damage_log.get(victim.idx, {})
	for attacker_idx: int in hits:
		var hit_t := int(hits[attacker_idx])
		var candidate: PlayerAgent = m.agents[attacker_idx]
		if candidate.team != defender_team or t - hit_t > window or hit_t <= best_t:
			continue
		best_t = hit_t
		best = candidate
	if best != null:
		return best
	var radius := float(m.balance.towers.credit_radius)
	var nearest_d := radius
	for agent in m.agents:
		if not agent.alive or agent.team != defender_team:
			continue
		var d := agent.pos.distance_to(tower_pos)
		if d < nearest_d:
			nearest_d = d
			best = agent
	return best


## `killer` may be null: a tower can finish someone with no player involved.
func _kill(t: int, killer: PlayerAgent, victim: PlayerAgent, source: String) -> void:
	var c: Dictionary = m.balance.combat
	var window := int(float(m.balance.fight.assist_window_s) * SimMatch.TICKS_PER_SECOND)
	var credit_team: String = killer.team if killer != null else _enemy_of(victim.team)
	var helpers: Array[PlayerAgent] = []
	var hits: Dictionary = _damage_log.get(victim.idx, {})
	for attacker_idx: int in hits:
		if (killer != null and attacker_idx == killer.idx) or t - int(hits[attacker_idx]) > window:
			continue
		var helper: PlayerAgent = m.agents[attacker_idx]
		if helper.team == credit_team:
			helpers.append(helper)

	var bounty: float = maxf(
		float(c.min_kill_worth),
		float(c.kill_gold) - victim.death_streak * 50.0
	) + minf(victim.kill_streak * float(c.shutdown_per_streak), float(c.shutdown_max))
	if killer != null:
		killer.earn(bounty)
		killer.kills += 1
		killer.kill_streak += 1
		killer.credit_kill_reset()  # a kill clears the killer's own feeding discount
	else:
		bounty = 0.0  # the tower does not spend gold

	var assist_ids: Array[String] = []
	var assist_each: float = float(c.assist_gold_total) / maxf(helpers.size(), 1)
	for helper in helpers:
		helper.earn(assist_each)
		helper.assists += 1
		assist_ids.append(helper.id)
	var kill_xp: float = float(c.kill_xp_base) + float(c.kill_xp_per_victim_level) * victim.level
	var share := float(helpers.size() + (1 if killer != null else 0))
	if share > 0.0:
		if killer != null:
			killer.add_xp(t, kill_xp / share, m)
		for helper in helpers:
			helper.add_xp(t, kill_xp / share, m)

	var where := victim.pos  # die() sends the victim home; keep where it happened
	_damage_log.erase(victim.idx)
	victim.die(t, m)
	_record_fight_death(victim, where)
	m.emit_event(t, "kill", {
		"killer": killer.id if killer != null else "", "victim": victim.id,
		"victim_team": victim.team,   # M6-A scores a moment by which side lost bodies
		"assists": assist_ids, "gold": roundi(bounty), "source": source,
		"pos": [where.x, where.y],
	})
	# The lane that just lost its laner is open for as long as the respawn takes.
	# Spending that window on the tower is what turns a pick into an advantage —
	# without it a gank is worth its gold and nothing else (M5-E, tempo trades).
	m.brains[credit_team].post_tempo(t, victim.lane, m)


# --- abilities: basic + ultimate (§3 three-action model) ----------------------

## Abilities fire on a condition, not on a timer: an AoE stun waits for bodies
## to hit, an execute waits for a target low enough to delete, a heal waits for
## an ally in trouble. That is what makes them read as a moment in the fight.
##
## One firing rule serves both slots (§3 three-action model): `slot_name` is
## "basic_ability" or "ultimate". A passive basic ability does not fire — it was
## resolved into persistent modifiers at spawn — so it returns here immediately.
func _try_ability(agent: PlayerAgent, slot_name: String, t: int, f: Dictionary) -> void:
	var slot: Dictionary = agent.character.get(slot_name, {})
	var effect: String = str(slot.get("effect", ""))
	if effect == "" or effect in DataLoader.PASSIVE_EFFECTS:
		return
	if not agent.ability_ready(slot_name, t) or not agent.in_combat or agent.disengaging:
		return
	if effect == "global_teleport":
		return  # a rotation tool, handled by the split-push logic, not here
	var radius: float = float(slot.params.get("radius", f.ult_default_radius))
	var enemies := _near(agent, radius, true)
	var allies := _near(agent, radius, false)
	var tgt: PlayerAgent = m.agents[agent.target_idx] if agent.target_idx >= 0 else null
	match effect:
		"aoe_cc", "aoe_damage", "zone_denial":
			if enemies.size() < int(f.ult_aoe_min_targets):
				return
		"single_cc", "single_burst", "snipe":
			if tgt == null:
				return
			# A slow only catches if it lands as the target tries to flee — fired at
			# max perception range it is spent before the chaser can close and the
			# even-speed chase resumes. Hold it until the target is at catch range.
			if String(slot.params.get("cc", "")) == "slow" \
					and agent.pos.distance_to(tgt.pos) > float(f.cc_catch_range):
				return
		"execute":
			if tgt == null or tgt.hp_fraction() > float(f.ult_execute_hp):
				return
		"team_heal", "team_shield":
			if not _any_hurt(allies + [agent], float(f.ult_heal_ally_hp)):
				return
		"self_steroid":
			if enemies.is_empty():
				return
	agent.cast_ability(slot_name, t, m, {
		"radius": radius, "targets": _ability_targets(agent, effect, tgt, enemies, allies),
	})
	_apply_ability(t, agent, slot_name, effect, slot.params, tgt, enemies, allies, f)


## Who an ability is about to touch, for the cast event. Mirrors the dispatch in
## _apply_ability — playback uses it to aim the impact (a beam at its target, a
## bloom on the healed, a shockwave over everyone caught in the circle).
func _ability_targets(agent: PlayerAgent, effect: String, tgt: PlayerAgent,
		enemies: Array, allies: Array) -> Array:
	match effect:
		"aoe_cc", "aoe_damage", "zone_denial":
			return _ids(enemies)
		"single_cc", "single_burst", "snipe", "execute":
			return [tgt.id] if tgt != null else []
		"team_heal", "team_shield":
			return _ids(allies) + [agent.id]
		"self_steroid":
			return [agent.id]
	return []


func _apply_ability(t: int, agent: PlayerAgent, slot_name: String, effect: String,
		params: Dictionary, tgt: PlayerAgent, enemies: Array, allies: Array, f: Dictionary) -> void:
	var is_ult := slot_name == "ultimate"
	var impact: Dictionary = m.balance.combat.ult_impact if is_ult else m.balance.combat.basic_impact
	var scale: float = float(f.ult_damage_scale if is_ult else f.basic_damage_scale)
	var power := threat(agent, t) * float(impact.get(effect, 0.0)) * scale
	# Lock duration for the stun/knockup/root path (unchanged from the ult tuning):
	# single-target CC holds twice as long as the AoE version.
	var stun := int(float(f.stun_duration_s) * SimMatch.TICKS_PER_SECOND)
	match effect:
		"aoe_damage", "zone_denial":
			for enemy: PlayerAgent in enemies:
				_deal_damage(t, agent, enemy, power)
		"single_burst", "snipe":
			_deal_damage(t, agent, tgt, power * float(f.ult_single_mult))
		"execute":
			_deal_damage(t, agent, tgt, power * float(f.ult_execute_mult))
		"aoe_cc":
			for enemy: PlayerAgent in enemies:
				_apply_cc(t, agent, enemy, params, power, stun, f, is_ult)
		"single_cc":
			_apply_cc(t, agent, tgt, params, power, stun * 2, f, is_ult)
		"team_heal", "team_shield":
			for ally: PlayerAgent in allies + [agent]:
				ally.hp = minf(ally.hp + power * float(f.ult_heal_mult), ally.max_hp)
		"self_steroid":
			agent.steroid_until = t + int(float(f.steroid_duration_s) * SimMatch.TICKS_PER_SECOND)


## The CC that catches. A `slow` cuts the target's move speed for its data
## duration (an equal-speed pursuer can now close — the whole point of the
## three-action model), everything else (stun/knockup/root/fear) is a hard lock
## for `lock_ticks`. Both chip a little damage. This is shared by the basic
## ability (early, the catch) and CC ultimates (the bigger, later payoff).
func _apply_cc(t: int, agent: PlayerAgent, victim: PlayerAgent, params: Dictionary,
		power: float, lock_ticks: int, f: Dictionary, is_ult: bool) -> void:
	if victim == null:
		return
	var kind := String(params.get("cc", ""))
	var until := 0
	if kind == "slow":
		var dur := int(float(params.get("duration", f.stun_duration_s)) * SimMatch.TICKS_PER_SECOND)
		until = t + dur
		victim.apply_slow(t, until, float(params.get("slow_mult", 0.5)))
	else:
		until = maxi(victim.stunned_until, t + lock_ticks)
		victim.stunned_until = until
	# The catch, told to the viewer: who locked whom, with what, until when. The
	# designer could not see the control land (2026-07-25 playtest, remark 4) —
	# the CC state itself also rides the snapshot, but this carries the *source*,
	# which is what turns a lock into "the jungler caught him". Sim-inert.
	m.emit_event(t, "cc_applied", {
		"source": agent.id, "victim": victim.id, "cc": kind,
		"until": until, "slot": "ultimate" if is_ult else "basic",
	})
	_deal_damage(t, agent, victim, power * float(f.ult_cc_damage_mult))


func _any_hurt(group: Array, below: float) -> bool:
	for a: PlayerAgent in group:
		if a.hp_fraction() < below:
			return true
	return false


# --- fight detection ----------------------------------------------------------

## Fights are no longer objects the sim creates — they are a shape it observes.
## Each tick we cluster the players who are actually engaged with each other and
## report clusters that contain both teams, so the kill feed, the viewer and the
## reports still get fight_start / fight_end.
func _update_fights(t: int) -> void:
	var f: Dictionary = m.balance.fight
	var engaged: Array = []
	for agent in m.agents:
		if agent.alive and agent.in_combat and not agent.disengaging and agent.target_idx >= 0:
			engaged.append(agent)

	for cluster in _clusters(engaged, float(f.fight_group_radius)):
		var sides := {"blue": [], "red": []}
		var centre := Vector2.ZERO
		for agent: PlayerAgent in cluster:
			sides[agent.team].append(agent)
			centre += agent.pos
		if sides.blue.is_empty() or sides.red.is_empty():
			continue
		centre /= float(cluster.size())
		var fight_id := _fight_for(cluster)
		if fight_id < 0:
			fight_id = _next_fight_id
			_next_fight_id += 1
			var context := _context_at(centre, cluster.size())
			_fights[fight_id] = {
				"members": [], "started": t, "pos": centre, "context": context,
				"deaths": {"blue": 0, "red": 0},
				# `peak` is the largest the fight ever got *at once* per side; the
				# member list only says who touched it, which over a 20 s scrap can
				# add up to five without four bodies ever standing together. The
				# honest "did a big fight happen" number is the peak (M6-A).
				"peak": {"blue": sides.blue.size(), "red": sides.red.size()},
				"present": {"blue": 0, "red": 0},
				"declines": {}, "decline_samples": 0,
				"gold0": _team_gold(),
			}
			m.emit_event(t, "fight_start", {
				"context": context, "pos": [centre.x, centre.y],
				"blue": _ids(sides.blue), "red": _ids(sides.red),
			})
		var rec: Dictionary = _fights[fight_id]
		rec.last_seen = t
		rec.pos = centre
		# `peak` counts bodies actually swinging; `present` counts every living
		# body standing there. The gap between them separates two very different
		# problems — "the team never came" from "the team came and didn't fight"
		# — which is the question M5-G has to answer about fight size.
		# "Present" is deliberately strict: at the fight AND with an enemy inside
		# its own awareness radius, i.e. a body that could be swinging and is not.
		# Merely standing 12 units away with nothing in sight is not a choice.
		var here := {"blue": 0, "red": 0}
		for agent in m.agents:
			if not agent.alive or agent.pos.distance_to(centre) > float(f.fight_group_radius):
				continue
			for other in m.agents:
				if other.alive and other.team != agent.team \
						and other.pos.distance_to(agent.pos) <= float(f.awareness_radius):
					here[agent.team] += 1
					if not agent.in_combat or agent.disengaging:
						var why: String = agent.decline_reason if agent.decline_reason != "" \
							else "other"
						rec.declines[why] = int(rec.declines.get(why, 0)) + 1
						rec.decline_samples += 1
					break
		for side: String in rec.peak:
			rec.peak[side] = maxi(int(rec.peak[side]), sides[side].size())
			rec.present[side] = maxi(int(rec.present[side]), here[side])
		for agent: PlayerAgent in cluster:
			if not agent.idx in rec.members:
				rec.members.append(agent.idx)

	var grace := int(float(f.fight_end_grace_s) * SimMatch.TICKS_PER_SECOND)
	for fight_id: int in _fights.keys():
		var rec: Dictionary = _fights[fight_id]
		if t - int(rec.last_seen) < grace:
			continue
		var deaths: Dictionary = rec.deaths
		var winner := ""
		if deaths.blue != deaths.red:
			winner = "blue" if deaths.blue < deaths.red else "red"
		var members := {"blue": [], "red": []}
		for idx: int in rec.members:
			members[m.agents[idx].team].append(m.agents[idx].id)
		var gold_now := _team_gold()
		m.emit_event(t, "fight_end", {
			"context": rec.context, "winner": winner,
			"pos": [rec.pos.x, rec.pos.y],
			"duration_s": roundi((t - int(rec.started)) / float(SimMatch.TICKS_PER_SECOND)),
			"kills": deaths,
			# M6-A scores fights without re-deriving them from the raw stream:
			# who was in it, how big it ever got at once, and what it was worth.
			"blue": members.blue, "red": members.red,
			"peak": rec.peak, "present": rec.present, "declines": rec.declines,
			"gold": {
				"blue": roundi(gold_now.blue - float(rec.gold0.blue)),
				"red": roundi(gold_now.red - float(rec.gold0.red)),
			},
		})
		_fights.erase(fight_id)


## Single-linkage clustering by proximity, via union-find. At most ten agents,
## so the quadratic pass is free and stays exactly reproducible.
func _clusters(agents: Array, radius: float) -> Array:
	var n := agents.size()
	if n == 0:
		return []
	var parent: Array[int] = []
	for i in n:
		parent.append(i)
	for i in n:
		for j in range(i + 1, n):
			if agents[i].pos.distance_to(agents[j].pos) <= radius:
				var ri := _find(parent, i)
				var rj := _find(parent, j)
				if ri != rj:
					parent[maxi(ri, rj)] = mini(ri, rj)
	var by_root := {}
	for i in n:
		var root := _find(parent, i)
		if not by_root.has(root):
			by_root[root] = []
		by_root[root].append(agents[i])
	var out: Array = []
	for root: int in by_root:
		out.append(by_root[root])
	return out


func _find(parent: Array[int], i: int) -> int:
	var root := i
	while parent[root] != root:
		root = parent[root]
	return root


## Gold earned so far by each side, for the fight's gold swing. Team-wide rather
## than participants-only on purpose: a fight the rest of the map pays for (the
## split-pusher taking a tower while four die) is a fight worth watching.
func _team_gold() -> Dictionary:
	var out := {"blue": 0.0, "red": 0.0}
	for agent: PlayerAgent in m.agents:
		out[agent.team] += agent.gold_total
	return out


## An existing fight this cluster continues, or -1 if it is a new one.
func _fight_for(cluster: Array) -> int:
	for fight_id: int in _fights:
		var members: Array = _fights[fight_id].members
		for agent: PlayerAgent in cluster:
			if agent.idx in members:
				return fight_id
	return -1


func _record_fight_death(victim: PlayerAgent, where: Vector2) -> void:
	for fight_id: int in _fights:
		var rec: Dictionary = _fights[fight_id]
		if victim.idx in rec.members or where.distance_to(rec.pos) < 14.0:
			rec.deaths[victim.team] += 1
			return


## Names the fight from where and how big it is, so the feed can narrate it.
func _context_at(pos: Vector2, size: int) -> String:
	var pit_radius := float(m.balance.fight.pit_context_radius)
	if pos.distance_to(m.map.pits.baron) < pit_radius:
		return "baron"
	if pos.distance_to(m.map.pits.dragon) < pit_radius:
		return "dragon"
	if size >= 7:
		return "teamfight"
	if size >= 4:
		return "fight"
	return "skirmish"


# --- helpers ------------------------------------------------------------------

func _enemy_of(team: String) -> String:
	return "red" if team == "blue" else "blue"


func _ids(agents: Array) -> Array:
	var out := []
	for agent: PlayerAgent in agents:
		out.append(agent.id)
	return out
