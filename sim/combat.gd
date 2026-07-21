class_name Combat
extends RefCounted
## Fight resolution: skirmishes, ganks and teamfights. One resolver serves all
## sizes — inputs are the two participant lists plus context, output is a
## resolved fight (winner, deaths, gold/XP transfers, ultimate casts) emitted
## as events over a short fight window so the viewer can animate it.
##
## Design (GDD §6): power = stats(level) × phase curve × item factor ×
## mechanics × comp modifiers, with seeded variance. Comeback-friendly:
## linear item scaling, shutdown bounties, no rubber-banding.

var m: SimMatch  # back-reference, set per-match; not stored beyond match life


func _init(match_ref: SimMatch) -> void:
	m = match_ref


## One player's contribution to a fight at time t.
func fight_power(agent: PlayerAgent, t: int) -> float:
	var c: Dictionary = m.balance.combat
	var damage := DataLoader.stat_at_level(agent.character, "damage", agent.level)
	var hp := DataLoader.stat_at_level(agent.character, "hp", agent.level)
	var armor := DataLoader.stat_at_level(agent.character, "armor", agent.level)
	var ehp := hp * (1.0 + armor / 100.0)
	var item_factor: float = 1.0 + agent.item_power / float(c.power_item_divisor)
	var mech: float = float(c.mechanics_power_base) + float(agent.attrs.mechanics) / float(c.mechanics_power_divisor)
	var phase_mult := m.phase_curve_mult(agent.character.curve, t)
	var mood: float = m.mood_mult(agent.id)
	return damage * item_factor * mech * phase_mult * mood * sqrt(ehp / float(c.ehp_norm))


## Resolves a fight between two participant lists. location: Vector2 for
## events. context: "gank", "skirmish", "teamfight", "objective".
## Returns the winning side ("blue"/"red") — ties impossible (variance).
func resolve(t: int, blue: Array, red: Array, location: Vector2, context: String) -> String:
	var c: Dictionary = m.balance.combat
	m.emit_event(t, "fight_start", {
		"context": context, "pos": [location.x, location.y],
		"blue": _ids(blue), "red": _ids(red),
	})
	var sides := {"blue": blue, "red": red}
	var scores := {}
	for side: String in sides:
		var members: Array = sides[side]
		var score := 0.0
		for agent: PlayerAgent in members:
			score += fight_power(agent, t)
			if agent.ult_ready(t):
				score += fight_power(agent, t) * float(c.ult_impact[agent.character.ultimate.effect])
				agent.cast_ult(t, m)
		score *= m.team_comp_mult(side, t)
		score *= 1.0 + m.objectives.team_buff(side)
		# Set-piece fights (objective contests, organized tower defenses)
		# reward shot-calling: macro teams fight them on their terms.
		if context in ["objective", "siege_defense"]:
			score *= 1.0 + (m.brains[side].macro_avg() - float(c.macro_setpiece_pivot)) \
				/ float(c.macro_setpiece_divisor)
		var enemy_count: int = sides["red" if side == "blue" else "blue"].size()
		if members.size() > enemy_count:
			score *= 1.0 + float(c.numbers_advantage_per_member) * (members.size() - enemy_count)
		score *= 1.0 + m.rng.randf_range(-float(c.fight_variance), float(c.fight_variance))
		scores[side] = maxf(score, 0.01)

	var winner: String = "blue" if scores.blue > scores.red else "red"
	var loser: String = "red" if winner == "blue" else "blue"
	var ratio: float = scores[winner] / scores[loser]

	var loser_deaths := clampi(
		roundi(float(c.loser_deaths_base) + (ratio - 1.0) * float(c.deaths_ratio_scale)),
		1, mini(int(c.max_deaths_per_fight), sides[loser].size()))
	var winner_deaths := clampi(
		roundi(float(c.loser_deaths_base) - 0.75 - (ratio - 1.0) * float(c.deaths_ratio_scale) * 0.8),
		0, mini(int(c.max_deaths_per_fight), sides[winner].size() - 1))

	var end_tick := t + int(float(c.fight_duration_s) * SimMatch.TICKS_PER_SECOND)
	_apply_casualties(end_tick, sides[loser], sides[winner], loser_deaths)
	_apply_casualties(end_tick, sides[winner], sides[loser], winner_deaths)
	# Interim (Phase A): survivors walk away hurt, so health is already a real
	# resource before the spatial engine replaces this resolver in Phase B.
	var health: Dictionary = m.balance.health
	_apply_chip_damage(sides[loser], float(health.fight_damage_loser_pct))
	_apply_chip_damage(sides[winner], float(health.fight_damage_winner_pct))
	m.emit_event(end_tick, "fight_end", {
		"context": context, "winner": winner, "pos": [location.x, location.y],
	})
	return winner


## Picks who dies on `victims_side`, credits kills to `killers_side`, pays
## gold/XP with shutdown bounties, starts respawn timers.
func _apply_casualties(t: int, victims_side: Array, killers_side: Array, count: int) -> void:
	var c: Dictionary = m.balance.combat
	var pool: Array = victims_side.filter(func(a: PlayerAgent) -> bool: return a.alive)
	var killers_alive: Array = killers_side.filter(func(a: PlayerAgent) -> bool: return a.alive)
	if killers_alive.is_empty():
		killers_alive = killers_side
	for _i in range(count):
		if pool.is_empty():
			return
		var weights: Array[float] = []
		for agent: PlayerAgent in pool:
			weights.append(_death_weight(agent, victims_side))
		var victim: PlayerAgent = pool.pop_at(m.rng.weighted_index(weights))

		var killer_weights: Array[float] = []
		for agent: PlayerAgent in killers_alive:
			# Supports peel and set up kills; the damage roles finish them.
			var kill_bias := 0.25 if agent.role == "support" else 1.0
			killer_weights.append(fight_power(agent, t) * kill_bias)
		var killer: PlayerAgent = killers_alive[m.rng.weighted_index(killer_weights)]

		var bounty: float = maxf(
			float(c.min_kill_worth),
			float(c.kill_gold) - victim.death_streak * 50.0
		) + minf(victim.kill_streak * float(c.shutdown_per_streak), float(c.shutdown_max))
		killer.earn(bounty)
		killer.kills += 1
		killer.kill_streak += 1
		killer.credit_kill_reset()  # a kill clears the killer's own feeding discount
		var assists: Array[String] = []
		var assist_each: float = float(c.assist_gold_total) / maxf(killers_alive.size() - 1, 1)
		for agent: PlayerAgent in killers_alive:
			if agent != killer:
				agent.earn(assist_each)
				agent.assists += 1
				assists.append(agent.id)
		var kill_xp: float = float(c.kill_xp_base) + float(c.kill_xp_per_victim_level) * victim.level
		for agent: PlayerAgent in killers_alive:
			agent.add_xp(t, kill_xp / killers_alive.size(), m)
		victim.die(t, m)
		m.emit_event(t, "kill", {
			"killer": killer.id, "victim": victim.id, "assists": assists,
			"gold": roundi(bounty),
		})


func _apply_chip_damage(side: Array, pct: float) -> void:
	for agent: PlayerAgent in side:
		if not agent.alive:
			continue
		agent.take_damage(agent.max_hp * pct * m.rng.randf_range(0.6, 1.4))


func _death_weight(agent: PlayerAgent, side: Array) -> float:
	var c: Dictionary = m.balance.combat
	var weight := 1.0
	var tags: Array = agent.character.tags
	if agent.role in ["top", "jungle"] or "engage" in tags or "protect" in tags:
		weight *= float(c.frontline_death_weight)
	if agent.role == "carry":
		for ally: PlayerAgent in side:
			if ally != agent and ally.alive and "protect" in ally.character.tags:
				weight *= float(c.protect_carry_death_factor)
				break
	weight *= 1.3 - float(agent.attrs.mechanics) / 250.0
	return maxf(weight, 0.1)


func _ids(agents: Array) -> Array:
	var out := []
	for agent: PlayerAgent in agents:
		out.append(agent.id)
	return out
