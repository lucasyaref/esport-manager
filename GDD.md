# MOBA Manager — Game Design Document (PoC)

Design truth for the PoC. Claude Code updates this file when the designer changes direction. Frozen decisions are marked ✅.

## 1. Fantasy & pillars
- **Pillar 1 — "It's really pros playing"**: match outcomes and moment-to-moment behavior are visibly shaped by pre-game management decisions (player skill profiles, mood, draft comp, coach compliance).
- **Pillar 2 — Readable matches**: a viewer can follow the story of the game at a glance (lanes, ganks, objectives, teamfights, win condition).
- **Pillar 3 — Sim first**: everything meaningful happens in the deterministic sim; visuals are playback.

## 2. Roles ✅ (5, distinct playstyles)
Each role has a distinct sim behavior profile — this is core, not polish.

| Role | Behavioral profile |
|---|---|
| **Toplane** | Plays top lane, farms, favors split-pushing side lanes mid/late; often frontline/tank in fights; joins late to fights via teleport-like rotation. |
| **Jungle** | Never lanes. Paths jungle camps, gains XP/gold from camps, periodically ganks lanes (target choice weighted by lane state and player profile), initiates/secures objectives (Dragon/Baron equivalents). |
| **Midlane** | Farms mid, shortest lane → roams to side lanes and river skirmishes more than other laners; high burst damage profile. |
| **Carry (ADC)** | Bot lane with Support. Weak early, scales hardest with gold/items; positions at fight backline; the team's late-game damage engine. Protecting the fed carry is a valid win story. |
| **Support** | Bot lane with Carry, takes almost no farm; wards (vision events), peels/protects carry in fights, roams with or ahead of mid; engage or shield profile depending on character. |

## 3. Characters ✅ (15 for PoC, 3 per role)
- Each character: role, base stats (HP, damage, armor, speed, scaling curve), one **unique Ultimate** (distinct sim effect + distinct animation later), a simple tag set for comp logic (engage / poke / scaling / early-game / protect).
- Data-driven (file-defined). Names/kits are original (LoL-inspired archetypes, no copyrighted names).
- ✅ Each character is **explicitly modeled on a LoL champion** (designer decision, 2026-07-19), recorded as `model` in characters.json (e.g. Bastion→Malphite, Vexa→Jinx). The model anchors kit fantasy and sim behavior (how they lane/gank/fight). Names, art and lore stay original from day one — no re-skin debt, no trademark risk. LoL *numeric* balance is not imported: it doesn't survive the abstraction to our sim; balance comes from headless batch runs (M3).
- Comp logic v1: team comp tags produce modifiers (e.g., full-scaling comp weaker before 20:00, stronger after; engage comp gets better fight initiations).
- Counter/synergy matrix: v1 = small hand-authored matrix at role level; per-character later.

## 4. Pro players
- 10 players for PoC (two teams of 5), file-defined.
- Attributes v1: **Mechanics** (fight/skirmish performance), **Macro** (decision quality: rotations, objective timing), **Laning**, **Champion pool** (per-character proficiency 0–3), **Mood** (match modifier, set in match setup for PoC), **Coach compliance** interacts with draft (see §5).
- Attributes bias sim decisions and outcome rolls; a great player on a poor comp can still lose — decisions + variance both matter.

## 5. Draft ✅
- **Picks only, no bans.** Order: B1 / R1 R2 / B2 B3 / R3 R4 / B4 B5 / R5. No duplicate characters across teams.
- Coach recommendation shown at every user pick (based on comp needs, player pools, counters).
  - Follow reco → small team-cohesion bonus.
  - Ignore reco → no bonus; if the pick is outside the player's champion pool, performance penalty (players play what you lock).
- AI opponent drafts via role-priority list + pool proficiency + simple comp logic.

## 6. Match simulation ✅ (architecture frozen)
- Deterministic, tick-based (10 ticks/sim-second), seeded. Headless-capable.
- Map: classic three lanes + jungle + river, two objective pits (Dragon-like: stacking team buff; Baron-like: pushing buff), towers per lane (outer/inner/base), nexus. Minion waves spawn periodically and push lanes.
- Phases: laning (0–14 sim-min) → mid game (rotations, objectives) → late game (grouped fights, Baron, closing). Average internal game length target: 25–35 sim-minutes.
- Combat: stat + item/gold + level + mechanics + comp-modifier weighted resolution with seeded variance; ultimates as high-impact cooldown events in fights.
- ✅ **Snowball philosophy (designer decision, 2026-07-19): comeback-friendly, but leads must matter.** Gold leads convert to win probability only through item/level power (roughly linear — no exponential runaway), like LoL's item gap. Comeback paths: shutdown bounties on kill-streak players, reduced worth on death streaks, and fight variance high enough that a behind-but-not-broken team can win a decisive objective fight. No artificial rubber-banding (no free gold for losing).
- Event stream includes: kills (killer/victim/assists), objective takes, tower falls, wards, ganks, recalls, item power-ups, ultimate casts — enough for a kill feed and post-game stats.

### 6.1 Combat model ✅ (designer decision, 2026-07-21 — after the M4 playtest)
The M4 playtest showed the failure mode of abstract combat: fights resolved as a single
comparison of team power scores, so "all points merge and suddenly we see death". Map
positions were decorative. The decision is **full spatial combat** — positions, health and
intent drive outcomes, and fights are something you watch happen rather than a result
that appears.

- **Health is a live resource.** Every player has current HP, regenerating slowly on the map
  and quickly in the fountain. HP drives the decisions the designer expects to see: back off,
  recall, dive, commit, or finish a low enemy. Death happens when HP reaches zero — it is
  never drawn from a lottery.
- **Reach and posture are per-character data.** `combat.attack_range`, `preferred_range`,
  `attack_speed` and `fight_role` (frontline / backline / flank / peel) live in
  `characters.json`. Ranges are in map units — 1 unit ≈ 125 LoL units, so melee ≈ 1.2 and
  artillery ≈ 5. Positioning is *emergent* from these: a long-range, low-HP carry naturally
  settles at the back; a short-range, high-HP engage character has to close.
- **Reach is paid for in damage.** Damage scales down with `attack_range`, so a melee
  character that must walk through a fight hits meaningfully harder than one that never
  leaves the back, and frontline/flank characters close the gap faster than they walk (gap
  closers, abstracted). Stated once as a balance rule rather than hand-tuned into fifteen
  characters. Discovered the hard way: without it an all-ranged draft beat a melee-heavy one
  82% of the time.
- **Fights are continuous, not instantaneous.** Each tick a player scans for threats, picks a
  target (weighted by low HP, threat and reachability — which is what produces focus-fire on
  carries), steers toward its preferred range, attacks when in range, and disengages when hurt.
  A fight detector groups these engagements so the kill feed and viewer still get
  `fight_start` / `fight_end` events. A team also **spreads its targets**: an enemy already
  being focused by allies is worth less to the next player, so five players never converge
  on one runner.
- **A chase has to end.** Players give up when the target has been out of reach too long,
  when the chase has dragged them too far from where they committed, or when continuing
  means diving a tower they cannot afford. Without a give-up rule and with equal move speed,
  every fight decays into an infinite chase off the edge of the map — the M4.5-B playtest
  showed exactly that.
- **The map has edges, and towers punish.** Positions are clamped to the playable area.
  Towers have range and dps and follow LoL aggro (minions first, then the nearest enemy
  player, switching to whoever attacks an ally in the zone), so a tower can kill: diving is a
  cost/benefit decision rather than a free chase. Kill credit for a tower kill goes to the
  diver who forced it, or to nobody.
- **Lanes are contested, not a ping-pong equation.** Laners pick a stance (push / trade /
  all-in / freeze / back), and trade HP through poke. Poke is only chip pressure — it is
  floored high enough that it can never, on its own, drop a laner far enough for an equal
  enemy to commit, so it pushes the loser toward home rather than deleting them at range. A
  **solo kill** needs a real edge (a level/item lead, or a third body from a gank) and is
  dealt by the combat engine, so it reads as a fight you watch. Stepping under the enemy
  tower for the kill (the all-in) is gated on the enemy being overextended and low — you die
  for greed, not for standing at 60% behind your own tower. Stance also drives how hard the
  wave pushes, so a shoving laner moves the front and exposes itself to a gank.
- **Intent is communicated, not assumed.** Players post intent (a jungler committing to a gank)
  to a team blackboard; team-mates read it and react, and *who reacts is decided by their
  `macro` attribute* — a sharp laner collapses on the gank and adds the body that gets the
  kill, a poor one keeps farming and it goes 1v1. A shoved-in mid roams to the call. This is
  where a roster's macro quality becomes visible on screen (Pillar 1): the same gank reads as
  coordinated or uncoordinated depending on who you fielded. Objective decisions are gated on
  **vision** — a team that cannot see the pit (no ward, no ally nearby) judges the fight on
  worse information and plays it safer, so wards decide objectives and both teams make a real
  fight / trade / give-it-up call rather than blindly focusing the objective.
- **Macro is a blend of baseline and roster quality (M5).** Coordination is not all-or-nothing.
  Every team runs a deterministic *baseline* of team play — it groups, rotates and follows up
  on calls enough to always read as a team on screen — and each roster's `macro` attribute
  scales the *quality and frequency* on top: a high-macro side ganks with more followers,
  rotates to objectives sooner, spots and takes cross-map openings, dispatches multi-man plays,
  and swaps lanes to snowball a tower lead, while a low-macro side does the baseline and little
  more. One primitive, `TeamBrain.macro_gate`, expresses this everywhere — the probability an
  average roster (macro == pivot, 70) should hit, lifted by macro above that pivot and floored
  (never zero) below it — so macro reads consistently across ganks, roams, multi-man plays and
  lane swaps instead of a pile of ad-hoc dice. This is the macro **win-vector**: the designed
  path by which fielding a smarter roster visibly changes the game and converts map movement
  into advantage (and the lever intended to pull the macro-vs-mechanics balance back toward
  43/57).
- **A few characters carry CC, and CC is how a play catches (M5).** Equal move speed means a
  healthy target just walks away from a gank or a roam — which is why proactive plays whiffed,
  and, measured, made the *macro* team lose by trading lane presence for nothing. Catching
  someone takes crowd control: a slow or stun on the initiator's signature spell. CC lives on a
  **few** characters (jungle and support archetypes, one unique spell each — variety grows as
  characters are added), so *having* a CC ganker/roamer is a roster and draft decision, not a
  given. The signature spell unlocks at level 6, so hard CC lands in mid-game skirmishes and
  teamfights; early-laning plays are gated instead on the target being catchable (low, or pinned
  under a tower). A landed play converts to **tempo** — a kill or a forced recall buys a tower or
  an objective — while the enemy, freed elsewhere, banks tempo of its own on the far side of the
  map. Reading that cross-map trade well is macro.

**Scope guard**: this is a readable pro game, not a MOBA engine. No pathfinding search, no
collision resolution — steering toward a desired point along the precomputed lane paths only.
Minions are **squads, not entities**: a handful of moving points per lane, each carrying a
count, marching out of base along its lane, stopping on contact and grinding the enemy squad
down by attrition. They cannot leave their lane by construction. Aggregate counts still drive
CS, gold and the push front (the front is now *derived* from where the squads meet), so
headless batch runs stay cheap while the viewer draws real minion dots that walk.

## 7. Viewer ✅
- Top-down 2D map, sprite per character (shared placeholder sprite: team tint + role marker; per-character sprites later via data field).
- Animations per character: Move, Attack, Spell/Ultimate, Hurt, Die, Recall.
- On-screen: HP bar + level per character, game clock, gold difference graph or bar, kill feed, team scores.
- Playback: 1x (≈8 real minutes ✅) / 4x / 16x / skip-to-result.

## 8. Later phases (recorded, not in PoC)
- PoC+ : club creation, pro-league calendar (LCK/LEC-like round robin), match history/standings, other matches simulated headless.
- Then: budget, mercato, coaching staff recommendations as a system, marketing, per-character sprites and kits, playoffs/international events.
