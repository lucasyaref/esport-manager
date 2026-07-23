class_name Laning
extends RefCounted
## Lane agency (GDD §6.1): a lane is a contest, not a ping-pong equation.
##
## Two laners standing a wave apart used to just farm and occasionally back off
## — they perceived each other but never fought, so top and mid produced no
## kills and everything happened bot. This adds the missing middle: laners
## **trade HP** through poke, and a big enough advantage converts into a **solo
## kill**.
##
## The split is deliberate. Poke only trades — it is floored high enough that it
## can never, on its own, drop a laner far enough for an equal-strength enemy to
## commit (below ~61% HP an even lane tips into a fight through the combat
## engine's HP-discounted power). So poke is chip pressure that pushes the loser
## toward home; the *kill* needs a real edge — a level/item lead, or a third
## body from a gank — and is dealt by the combat engine, which already knows how
## to collapse on a low, isolated enemy. The result reads as a fight you watch,
## not damage at a distance. Stance sets how far up a laner stands and how hard
## it pokes, which also decides how hard its wave pushes — a pushed-up laner is
## the one the enemy jungler can gank.
##
## Determinism: laners are read in fixed agent order, poke variance goes through
## m.rng, and stance is a pure function of the state each laner can see.

## Stance names, for readability and the eventual viewer overlay.
const STANCES := ["push", "trade", "allin", "freeze", "back"]

var m: SimMatch  # back-reference; cleared by SimMatch at end of run()


func _init(match_ref: SimMatch) -> void:
	m = match_ref


## Called every tick. Decides each laner's stance and, on the poke cadence,
## trades HP between the laners actually standing in each lane.
func update(t: int) -> void:
	var lb: Dictionary = m.balance.laning
	var poke_now: bool = t % maxi(1, int(float(lb.poke_interval_s) * SimMatch.TICKS_PER_SECOND)) == 0
	for lane in SimMap.LANES:
		var present := {"blue": [], "red": []}
		for agent in m.agents:
			if agent.state == PlayerAgent.State.FARMING and agent.lane == lane and agent.alive:
				present[agent.team].append(agent)
		if present.blue.is_empty() and present.red.is_empty():
			continue
		_assign_stances(t, present, m.lanes[lane].front_t, lb)
		if poke_now and not present.blue.is_empty() and not present.red.is_empty():
			_poke(t, present, lb)


## Extra push pressure this laner puts on its wave, from its stance. Read by
## SimMatch._tick_lane so a shoving laner physically moves the front (and
## overextends into gank range) while one holding back does not.
func pressure_mult(agent: PlayerAgent) -> float:
	var lb: Dictionary = m.balance.laning
	match agent.lane_stance:
		"push", "allin", "trade":
			return float(lb.push_pressure_mult)
		"back", "freeze":
			return float(lb.back_pressure_mult)
	return 1.0


# --- internals ---------------------------------------------------------------

func _assign_stances(t: int, present: Dictionary, front: float, lb: Dictionary) -> void:
	var power := {
		"blue": _side_power(present.blue, t),
		"red": _side_power(present.red, t),
	}
	var low_hp := {
		"blue": _lowest_hp(present.blue),
		"red": _lowest_hp(present.red),
	}
	for team in SimMap.TEAMS:
		var enemy := "red" if team == "blue" else "blue"
		# The enemy is overextended when the wave has been shoved onto its half
		# of the lane, away from its own tower — for a blue agent that means the
		# red enemy is caught below the midline (front pushed toward blue).
		var enemy_overextended: bool = (front <= 0.5 - float(lb.allin_overext)) if team == "blue" \
			else (front >= 0.5 + float(lb.allin_overext))
		for agent: PlayerAgent in present[team]:
			agent.lane_stance = _stance_for(agent, power[team], power[enemy],
				low_hp[enemy], present[enemy].is_empty(), enemy_overextended, lb)


## A laner's stance is a pure read of what it can see: its own health, whether
## it is ahead in the lane, and whether the enemy is low AND overextended enough
## to actually catch. Requiring overextension is what stops the all-in from
## firing on every slightly-behind laner — you get solo-killed for greed, not
## for being at 60% HP behind your own tower.
func _stance_for(agent: PlayerAgent, mine: float, theirs: float, enemy_low_hp: float,
		enemy_absent: bool, enemy_overextended: bool, lb: Dictionary) -> String:
	var recall_hp := float(m.balance.health.recall_hp_threshold)
	if agent.hp_fraction() <= recall_hp + 0.08:
		return "back"          # hurt: give ground, farm safe, go home soon
	if enemy_absent:
		return "push"          # nobody home: shove the wave and threaten a roam
	var ahead: bool = mine >= theirs * float(lb.trade_lead)
	if ahead and enemy_overextended and agent.level >= int(lb.allin_min_level) \
			and agent.hp_fraction() >= float(lb.allin_self_hp) \
			and enemy_low_hp <= float(lb.allin_enemy_hp) \
			and mine >= theirs * float(lb.allin_lead):
		return "allin"         # ahead, past level 1-2, enemy low and caught out
	if ahead:
		return "trade"         # ahead: step up and poke
	return "freeze"            # behind: hold, deny, wait for help


## Each present laner pokes the nearest enemy laner. Poke only trades HP — it is
## clamped above the floor so it never kills; the kill, when it comes, is the
## combat engine collapsing on whoever this wore down.
func _poke(t: int, present: Dictionary, lb: Dictionary) -> void:
	for team in SimMap.TEAMS:
		var enemy := "red" if team == "blue" else "blue"
		for agent: PlayerAgent in present[team]:
			if agent.level < 2:
				continue  # level 1 has no poke tools; keeps first blood off 0:40
			var victim := _closest(agent, present[enemy])
			if victim == null:
				continue
			var amount := _poke_damage(agent, victim, t, lb)
			var floor_hp := float(lb.poke_floor_hp) * victim.max_hp
			amount = minf(amount, maxf(victim.hp - floor_hp, 0.0))
			if amount > 0.0:
				victim.take_damage(amount, t)


func _poke_damage(agent: PlayerAgent, victim: PlayerAgent, t: int, lb: Dictionary) -> float:
	var dmg := float(lb.poke_base)
	dmg *= DataLoader.stat_at_level(agent.character, "damage", agent.level) \
		/ float(lb.poke_damage_norm)
	dmg *= 1.0 + float(agent.attrs.laning) / float(lb.poke_laning_div)
	# Poke is weak at level 1 and ramps to full by 6 — otherwise laners chunk
	# each other to death in the first minute and first blood lands at 1:30.
	var ramp := float(lb.poke_level_ramp_start)
	dmg *= minf(1.0, ramp + (1.0 - ramp) * (agent.level - 1) / 5.0)
	match agent.lane_stance:
		"allin": dmg *= 1.4
		"trade": dmg *= 1.2
		"freeze": dmg *= 0.7
		"back": dmg *= 0.5
	dmg *= m.phase_curve_mult(agent.character.curve, t)
	dmg *= 1.0 + m.rng.randf_range(-float(lb.poke_variance), float(lb.poke_variance))
	var armor := DataLoader.stat_at_level(victim.character, "armor", victim.level)
	return dmg * 100.0 / (100.0 + armor)


func _side_power(laners: Array, t: int) -> float:
	var total := 0.0
	for agent: PlayerAgent in laners:
		total += m.combat.threat(agent, t) * agent.hp_fraction()
	return total


func _lowest_hp(laners: Array) -> float:
	var low := 1.0
	for agent: PlayerAgent in laners:
		low = minf(low, agent.hp_fraction())
	return low


func _closest(agent: PlayerAgent, candidates: Array) -> PlayerAgent:
	var best: PlayerAgent = null
	var best_d := INF
	for c: PlayerAgent in candidates:
		var d := agent.pos.distance_to(c.pos)
		if d < best_d:
			best_d = d
			best = c
	return best
