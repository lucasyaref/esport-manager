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
- ✅ **Three actions per character (designer decision, 2026-07-24)**: (1) **auto-attack**, (2) one **basic ability** — an active spell *or* a passive, unlocking early (laning phase), (3) one **ultimate**, unlocking at level 6. Each is one signature thing, distinct sim effect + distinct animation later; no mana, no combos. Both ability slots reuse the same data shape (`effect` + `params` + `cooldown` + unlock level) and the same combat firing rule, so a basic ability is not a new system — it's a second instance of the ultimate machine. Passives are the default (a persistent modifier, no activation AI, near-free in sim); active basic spells go only on the kits that want them, which keeps the count of AI-driven abilities low. This model exists so **CC can live on the basic ability** (early) for the few CC characters, letting laning plays actually connect — see §6.1.
- Each character: role, base stats (HP, damage, armor, speed, scaling curve), the three actions above, a simple tag set for comp logic (engage / poke / scaling / early-game / protect).
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
  - **Breaking off is hysteresis, not a ban.** A player who *was fighting* and pulled out stays
    out for `fight.disengage_lock_s` instead of bouncing back in every tick. It must never apply
    to a body that has not engaged yet: a third man walking into a 1v1 sees the enemies before
    his own ally enters his awareness radius, reads 1v2, declines — and used to be barred from
    the fight for twice as long as the average fight lasts (M5-G).
  - **Staying in a won fight** is available as `fight.hold_when_winning_edge` — a body below the
    disengage threshold holds anyway if it has that many more local bodies than the enemy,
    because a real player at 40% in a 4v1 does not walk home. **Shipped off (99).** Measured, it
    buys multi-kill moments and costs kill fidelity and macro win rate; it is a drama-versus-
    fidelity call for the designer, not a technical one (`REPORTS/M5.md` §3.4, §5 q2).
  - ⚠️ **Fights are short and small, and no number fixes it.** Real contact lasts one to three
    seconds; the reported 6 s fight duration is mostly the end-grace tail. 65% of all fights are
    two bodies, and that share held at 63–66% across sixteen measured arms — damage scale,
    disengage lock, respawn timers, the hold rule, all of it. Bodies arrive, exchange, break off,
    and the next exchange scores as a *new* fight. Making a real 5v5 happen is a change to **how
    long a committed body stays committed**, which is a change to this model rather than to a
    value in it. It is the largest remaining gap to a pro game and the prerequisite M6's close-up
    view is waiting on.
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
  and takes the first tower then swaps its bot duo onto a fresh lane to snowball that lead,
  while a low-macro side does the baseline and little more. One primitive, `TeamBrain.macro_gate`, expresses this everywhere — the probability an
  average roster (macro == pivot, 70) should hit, lifted by macro above that pivot and floored
  (never zero) below it — so macro reads consistently across ganks, roams, multi-man plays and
  lane swaps instead of a pile of ad-hoc dice. This is the macro **win-vector**: the designed
  path by which fielding a smarter roster visibly changes the game and converts map movement
  into advantage (and the lever intended to pull the macro-vs-mechanics balance back toward
  43/57).
- **The lane swap is objective-triggered, not an opening (M5-D, 2026-07-25).** The swap is a
  *consequence* of a lead, not a coin-flip at minute zero. A team focuses bot with its jungler,
  takes the enemy's bot outer tower (bot T1), and *only then* rotates its bot duo onto a lane
  that still has a tower to snowball — top if the enemy's top outer stands, else mid. The team
  that wins bot first dictates the swap; the other reads it and matches so it is not left 2v1.
  (The earlier opening-swap model sent both bot duos top before minions — the "botlane always
  goes top" the designer caught — and is retired.) A jungler's macro-gated ability to *set up*
  the bot lead and the roster's macro-gated ability to *execute* the rotation are both part of
  the win-vector.
- **Defensive macro: protect the base, punish the over-extension (M5-D, 2026-07-25).** A team
  reads its own map, not only the enemy's. When a *deep* tower of its own (inner/base or the
  nexus) is under real pressure, defending it outranks any siege or objective — you do not trade
  a baron for your own nexus. And an enemy caught over-extended and *alone* on your half of the
  map, where enough of yours can reach, is a pick to collapse on rather than let walk. Both read
  on screen as a team that plays the whole board; the fuller multi-man convergence on such picks
  is the M5-E/F layer.
- **A few characters carry CC, and CC is how a play catches (M5).** Equal move speed means a
  healthy target just walks away from a gank or a roam — which is why proactive plays whiffed,
  and, measured, made the *macro* team lose by trading lane presence for nothing. Catching
  someone takes crowd control: a slow or stun. CC lives on the **basic ability** (see §3's
  three-action model) of a **few** characters (jungle and support archetypes — variety grows as
  characters are added), so *having* a CC ganker/roamer is a roster and draft decision, not a
  given. Because the basic ability unlocks **early** (laning phase), a CC ganker can catch a
  target *in lane*, not only after level 6 — that's the whole reason the three-action model was
  adopted. The **ultimate** (level 6) stays the bigger, rarer payoff on top. Plays without a CC
  carrier still need the target to be catchable on its own (low, or pinned under a tower). A
  landed play converts to **tempo** — a kill or a forced recall buys a tower or an objective —
  while the enemy, freed elsewhere, banks tempo of its own on the far side of the map. Reading
  that cross-map trade well is macro.
  - *Timing is the whole trick (learned in M5-C):* a slow only catches if it lands **as the
    target commits to fleeing**. Fired from max perception range it is spent before the chaser
    can close and the even-speed chase just resumes — so a CC carrier holds the slow until the
    target is at catch range. With that, ganks and skirmishes connect; the wider **multi-man
    pincer** (converging from two sides so the target cannot simply run home) is the M5-E layer
    on top, which is what lets a high-macro roster convert the catch into kills more often.
- **The sandwich is the gank the designer wants to see (designer, 2026-07-26).** Stated as a
  board position: *red mid is pushing blue's T2; the blue jungler is on blue buff or in the
  river; blue mid is defending behind T2.* That is a **perfect position** — and a team with
  macro must recognise it and call the jungler in. Three things make it the shape to build:
  - **The trigger is a position, not a timer.** An enemy laner deep in our half, our laner
    alive behind our own tower, a third body of ours within reach, and no enemy help nearer
    than ours. A gank is *called by the board state*, so the same board always produces the
    call and it reads as reading the map (macro), not as a dice roll on a cooldown.
  - **The jungler cuts the retreat, it does not chase the target.** It arrives *between the
    target and the target's home* — deeper into our half than the target is — so the target is
    caught between the laner and the jungler. This is what makes the play connect with equal
    move speeds: the escape route is the thing being taken away, not the gap being closed. CC
    still lands at catch range (above); the sandwich is what makes CC unnecessary for a
    catch when the geometry already has one.
  - **The laner is a participant, not a spectator.** The defending laner is told the play is
    coming — the call posts when the jungler commits, not when it arrives — and collapses on it.
    A gank the laner ignores is the 1.07-follower whiff M5-E exists to fix. *(The "holds the
    target, commits on arrival" half of this was built in M5-F2 and measured as a 7.5-point loss;
    see "What a laner does about an inbound gank" below. The laner engages immediately.)*
  - **Depth of the push is the cost.** The reward is scaled by how overextended the target is,
    and the price is the lane priority given up by whoever leaves. Both sides of that are
    `macro`-gated, so a sharp roster takes the sandwich that is there and a poor one takes a
    bad one or misses it — the same board, a different team.
- **The committed play: how a team collapses on a pick (M5-F2, designer item 3).** A team that
  spots an enemy caught over-extended and alone does not *all* turn around for it, and it does not
  ignore it either. It sends **a committed set**: a target, the two or three bodies that agreed to
  come, and a window. Everyone else keeps farming, sieging or holding their lane. Three properties
  make it work where the earlier team-wide version failed:
  - **Joining is rolled per player, against that player's own `macro`.** The sharp roster arrives
    three-handed and converts; the poor one sends nobody and the play is never called. This is the
    same `macro_gate` shape as every other call, applied to an individual rather than the team.
  - **A play with too few bodies is not called at all** (`play_min_men`). One player walking at an
    over-extended enemy is the 1v1 whiff that sank both earlier roam attempts (M5-C, M5-E2) — and it
    costs the farm either way. The commitment threshold is what makes leaving lane pay.
  - **The set is committed for the window.** The team's own intent does not get to walk those
    players somewhere else mid-collapse, and the play does not interrupt a recall, a camp clear or a
    gank already in flight. Two ends of one rule.
  This is also where **support mobility** (item 5) and **proactive roaming** (item 2) live: the
  support roams when it is part of a committed play, never on its own dice. Measured at **+4 points**
  of macro win rate — the largest single gain in M5, and notable for *raising* fight volume while
  still favouring the macro roster, because a coordinated collapse is a fight the numbers edge
  already won (`REPORTS/M5-F2.md`).
- **What a laner does about an inbound gank: it engages, it does not wait (M5-F2).** The intuitive
  model — and the one written here after the 2026-07-26 direction — was that the laner *holds* the
  target while the play is inbound and commits when the ganker lands. Built and measured, it cost
  **7.5 points** of macro win rate and dropped the gank connect rate from 22% to 17%. The reason is
  physics, not tuning: in this sim engaging early is what **pins** the victim. A laner that merely
  holds leaves the victim free to disengage the moment a third body appears, so the gank arrives at
  a target already leaving. So a reactor all-ins as soon as it hears the call, and the "set-up" half
  of item 1 is **retired** — the telegraph itself (the call posts when the jungler commits, not when
  it arrives) is what the laner needs, and that already existed. Same lesson as the answer walking
  *at* its spot rather than cutting it off: being there, early, is the mechanic.
- **The answer: the other half of a jungler's job (designer, 2026-07-26).** *"The blue jungler
  passes behind the red mid while his own T1 is being attacked, and goes to a jungle camp
  instead of helping. Does not look like a human-pro decision."* Every play the sim made until
  now was one the jungler **chose** — a gank, a sandwich — rolled on a fifteen-second cadence.
  A pro jungler spends as much of the game on plays the **map forces on him**: a team-mate in a
  fight he is losing, an enemy standing on one of his own towers. So an *answer* is a separate
  trigger with a separate, fast clock (a fight is over in ten seconds; a fifteen-second cadence
  cannot see one), no phase restriction, and two shapes only — a team-mate fighting and not
  ahead on numbers, or an enemy on a tower of ours — both inside the distance a jungler would
  actually walk. It is `macro`-gated like every other call and posts to the blackboard, so the
  lane collapses with him. What it must **not** become is a magnet: a 2v1 already going our
  way needs no jungler, and the farm he gives up is the same cost that made blind roams lose
  (M5-C, M5-E2).
- **Defending is something bodies do (designer, 2026-07-26, remark 5).** *"Blue did not protect
  the nexus and left it undefended even if minions are pushing. Nexus should be priority — push
  the lane that is threatening, at least one player, not necessarily the whole team."* Three
  parts. First, **presence on a lane is positional**: whoever stands at the front kills what is in
  front of them, whether they are a laner farming, a defender who walked home or a squad grouped
  for a fight. Reading it off "is this player assigned to this lane and farming" meant a team
  standing on its own nexus contributed *nothing* to the wave grinding it down. Second, a wave
  **pinned on your own tower line with no counter-wave left** can be killed by the players
  standing on it — before, minions could only be killed by other minions' company, so a wave
  walking at an exposed nexus was invulnerable. Third, **the answer is sized to the threat**: a
  base or nexus in danger is worth the whole team; an outer tower is worth the nearest couple
  while the rest keep farming. Sending five bodies at every pinned wave is how a team ends with
  neither map nor farm.
  - *How hard defenders clear* was one number shared with ordinary laning, which made it look
    like a trade it is not. Raising it swung the macro/mechanics win split by 4–13 points
    **non-monotonically** (`REPORTS/M5-F1.md` §4) — but that cost came from the *contested* half:
    a lane in this sim is pinned on somebody's tower most of the game, so raising the shared
    number is really "everybody pushes harder". **Siege clearing is now its own weight**
    (`minions.defend_pressure_mult`, 1.0 = the M5-F1 behaviour), and measured on its own over 400
    sims it is well-behaved: ×6 costs ~3 points of macro win rate and leaves the snowball flat
    (66%, against 71–73% for the shared raise) while taking kills to pro's 28 and length to
    30.25 min. Which value ships is a designer call about fidelity, not a balance knob.
- **Towers hold in the early game (plating, 2026-07-26, remark 6).** The real game armours turrets
  with plates until 14:00, which is why a pro first tower falls around 10–12 minutes. Ours fell at
  **5.6**, which ended the laning phase before it produced anything worth watching. So a tower
  takes `towers.plating_reduction` less damage at minute zero, easing to none by
  `towers.plating_until_s`. It is the cheapest lever on three things at once — first-tower timing,
  match length, and total kills — and it is the only change in M5-F1 that *helped* the macro
  roster, because a team that wins through scaling wants the game to last.

**Scope guard**: this is a readable pro game, not a MOBA engine. No collision resolution —
steering toward a desired point, now routed around terrain (§6.2) rather than free across an
empty plane. Minions are **squads, not entities**: a handful of moving points per lane, each
carrying a count, marching out of base along its lane, stopping on contact and grinding the
enemy squad down by attrition. They cannot leave their lane by construction. Aggregate counts
still drive CS, gold and the push front (the front is now *derived* from where the squads meet),
so headless batch runs stay cheap while the viewer draws real minion dots that walk.

### 6.2 The map: terrain, walls and brush (designer decision, 2026-08-02)
Until now `SimMap` is three lane polylines plus a handful of points on an otherwise empty
100×100 plane. There is no walkable space, so there are no corridors, no walls to hug, no
brush to sit in and no escape that costs anything. The designer's long-standing "need walls
around the jungle, complexify the map" is **taken up** (2026-08-02), driven by the close-up
view: at 4× zoom terrain is most of what you look at, and characters strolling through jungle
that does not exist reads as broken (§7.2, §7.3).

**The map is authored, not generated.** It is a real Summoner's-Rift-shaped layout — bases in
opposite corners, three lanes, a diagonal river, four jungle quadrants of blocks with corridors
between them, camps in their own pockets, the two pits on the river. It is authored as a
**human-readable ASCII grid** (`data/terrain.txt`), one character per cell, so the designer can
open it in any text editor, see the map, and move a wall by typing. The sim compiles that grid
once at load; the ASCII file is the source of truth and the only thing anyone edits.

**Cell kinds**, and what each one means to the sim:

- **Open** — walkable, visible.
- **Wall** — not walkable, blocks vision. Jungle rock, the base perimeter, the river banks.
- **Brush** — walkable; a body inside it is **invisible to enemies outside it** unless adjacent.
  This is the mechanic that makes a gank an ambush instead of a converging dot.
- **River** — walkable, cosmetic (and the place-name the reel already uses).
- **Pit** — walkable, the dragon/baron bowls, drawn as their own floor.

**What terrain changes in the sim, and what it deliberately does not.** Movement stops being
free 2D steering: a body routes around walls on a precomputed navigation grid, so a gank from
the enemy jungle takes the corridor and arrives late, and a fleeing carry can be cut off. That
is a *real* change to gank timing, escape rates and rotation cost, and it will move balance —
it is measured as a batch delta like every other lever, not assumed. What terrain does **not**
introduce: no per-body collision (bodies still overlap), no minions leaving their lane, no
per-agent search at runtime — routing is precomputed per destination and looked up.

**Vision through brush is a second, separable step.** Walls blocking sight and brush hiding
bodies is the part that changes how ganks *play*; walls merely blocking movement is the part
that changes how they *look*. They ship in that order, and the vision half is gated on its own
batch measurement (§ M6-T in `BACKLOG.md`).

## 7. Viewer ✅
- Top-down 2D map, sprite per character (shared placeholder sprite: team tint + role marker; per-character sprites later via data field).
- Animations per character: Move, Attack, Spell/Ultimate, Hurt, Die, Recall.
- On-screen: HP bar + level per character, game clock, gold difference graph or bar, kill feed, team scores.
- Playback: 1x (≈8 real minutes ✅) / 4x / 16x / skip-to-result. Note that **1x is already 4×
  sim-time** (40 sim-ticks per real second against the sim's 10 ticks per sim-second) — that is
  what buys the 8-minute match. True real speed is a *quarter* of 1x, and only the highlight view
  (§7.2) uses it.

### 7.1 Combat readability ✅ (designer playtest 2026-07-25 → M5.5)
The M4 viewer showed *movement*; the sim's combat depth (M4.5) and its CC (M5-C) were
invisible, so the designer could not judge — or gate — the sim underneath. Since the 1x
playtest is the real gate, the viewer has to show what the sim decided. Rules:

- **The sim is still the only source of truth.** Playback reads live combat state off the
  per-tick snapshot (who is engaged, backing off, stunned, slowed, recalling; who each
  player is attacking; the tick of its last swing) instead of inferring it from the event
  stream. Anything the viewer needs is *reported* by the sim, never re-decided in `game/`.
- **Every swing has a beat.** An auto-attack is drawn — a projectile crossing to the target
  for a ranged character, a slash for a melee one, a spark where it lands — so a fight reads
  as blows being traded rather than two dots resting against each other.
- **CC reads as a catch.** The victim carries a mark for exactly as long as the sim's lock
  lasts (icy ring for a slow, amber ring with orbiting stars for a hard lock) and a dashed
  tether ties it back to whoever cast it: "the jungler caught him", not "he stopped".
- **Ultimates land with weight, by family.** One shape per effect family — shockwave at the
  ability's real radius for AoE, a beam for single-target (piercing for a snipe, a cross for
  an execute), a bloom for heal/shield, an aura for a self-buff — bigger and louder than the
  same family fired from the basic-ability slot, so a level-6 ult never reads like a basic.
- **Timing is real time, not sim ticks.** Playback at 1x runs four times sim-time, so every
  transient is sized in *real seconds at the speed being watched* (and stretches with the
  speed button, capped at 4x). A beat nobody can perceive is a beat that is not there.
- **Damage is visible on the body.** Playback diffs HP between snapshots into floating
  numbers and a hit-flash. Health bars alone move a couple of pixels a swing, which reads as
  nothing happening; every number shown is a real delta the sim produced.
- **"Fighting" means trading blows.** The sim's `in_combat` also covers standing off across a
  wave (measured: only ~30% of in-combat player-frames are exchanges), so the fight marker
  requires a swing given while still committed, and disengaging is drawn as a retreat instead.
- **Structures show health, and the endgame is narrated.** A turret drains as it is chipped
  (health on the glyph, not only in a bar), flashes when nearly dead, and leaves rubble;
  anything losing HP right now pulses. Turrets standing and both nexus healths are permanently
  on screen, and the feed calls every turret, an exposed nexus and each nexus threshold — a
  match must never end without the viewer knowing why. (The sim currently ends games by a slow
  minion grind; making that *decisive* is a balance job, making it *legible* is this one.)
- **Whatever kills a structure is shown killing it.** In this sim the *wave* takes turrets and
  then the nexus, so a besieging squad is drawn swinging at what it is chipping. And an open
  lane's wave now walks all the way to the nexus instead of stopping an eighth of the map short
  of it — a structure must never lose health with nothing visibly attacking it (designer,
  2026-07-25 and 2026-07-26: "no enemy hitting nexus, too far from it").
- **Bodies never stack.** Steering has no collision, and team-mates routinely aim at the
  same point (a rally spot, one lane stand position), so playback pushes overlapping bodies
  apart for drawing — a *layout* pass that preserves the group's centre, keeps the sim's
  numbers untouched, and leaves "the dot is where the fight is" true. Body separation *as a
  sim mechanic* was measured and deliberately not adopted here (see CHANGELOG M5.5): it
  moves win rates, so it is a balance decision, not a rendering one.
- **Characters, not dots.** One procedural silhouette per role (broad hexagon top,
  arrowhead jungler, star mid, pentagon carry, octagon-and-cross support), team-tinted,
  turned toward its target or its path. A character's `sprite` data field still overrides
  the placeholder with real art and no code change.
- **Headless verification.** The viewer can play a whole match back with no display
  (`--selftest`) and assert the frame stream is sane and that the visuals the sim's events
  imply were actually drawn, so playback regressions surface in `tools/check.sh` rather than
  in a designer playtest.

### 7.2 The highlight view (designer direction 2026-07-25 — scoped as M6, not yet built)
Two views of the same match, from the same tick stream.

- **Overview** — what exists today. The whole map, accelerated, silhouettes, the story at a
  glance. This is where a match is *followed*.
- **Highlight** — 5 to 10 times a match, playback drops into the action: camera zoomed on the
  fight, characters drawn as animated sprites with real spell effects, running at **real speed**
  for ~30 seconds at most. This is where a match is *watched*. Ganks that turn into kills,
  skirmishes at an objective, teamfights, the moment the game turned.

**Selection is scored, and it is part of the sim's output, not the viewer's taste.** Candidate
moments are clustered from the event stream (kills close in time and space, objective takes,
tower falls with champions present, a base defense), scored, and the best few selected:

- **Score** = stakes × execution. Deaths in the window, participants involved, gold swing, the
  objective or structure at stake, and whether the game's direction changed. Rarity bonuses for
  the things that make a story: first blood, a solo kill against a lead, a steal, a hold at the
  nexus, an outnumbered win.
- **An absolute floor.** A moment under the threshold is not shown even if it is top-10 — a quiet
  game gets a short reel, not a padded one. ✅ (designer rule)
- **Spread and variety.** A minimum gap between highlights and a penalty for repeating the same
  kind in the same lane, so the reel isn't six identical bot ganks — and, since ~3/4 of the
  action lands after 14 minutes, at least a slot or two reserved for the laning phase.
- **Deterministic.** Same input + seed ⇒ same match ⇒ **same reel**. The rule from CLAUDE.md
  extends to highlight selection.

**The scorer is built and shipped ✅ (M6-A, 2026-08-01)** — `sim/highlights.gd`, tuned from
`data/highlights.json`, printed for one match by `tools/reel.gd` and measured in batch. Kills,
fights, objectives and structures all become *anchors* with a time span and a position; anchors
overlapping in both are one moment, which is why a gank, the tower it buys and the dragon that
follows read as one thing rather than three. Score is kills + multikills + ace + bodies at the
peak + gold swing + objective/structure value, all multiplied by game clock (`late_bonus`: a play
at minute 30 decides the game, one at minute 4 does not). Selection applies the absolute floor,
the spacing, a per-kind cap and a hard count; the nexus is exempt from all four, because a match
always ends on its nexus. The rarity bonuses and the reserved laning slot above are **not built** —
the measured reel spread is 2%/31%/67% early/mid/late, so reserving an early slot would be
reserving it for nothing until the early game has something in it.

**A highlight is a time window plus a camera focus** — nothing more. That single definition gives
both pacing modes for free: *full match* (watch it all, drop into each highlight as it comes,
~12 real minutes) and *highlights-only* (jump moment to moment, ~4–5 minutes) — the second is what
a manager watching a 38-game season actually wants, and it is the same code.

**Pacing: the watched match gets longer ✅ (designer, 2026-08-02).** Highlights are *added on top*
of the overview, not paid for by speeding it up — the overview keeps its 1x and a watched match
grows from ~8 to ~11–12 real minutes. Immersion wins over the time budget; the budget was never a
requirement, only an assumption. *Highlights-only* still ships as a mode (same machinery), and it
is what the season calendar will live in later.

**What the close-up demands that the overview never did.** Zoom is a magnifying glass on the sim:
things invisible at map scale become the whole picture. Bodies drawn away from their sim positions
for legibility (§7.1) stop being harmless; walking through jungle walls that do not exist reads as
broken; five keyframes a second reads as sliding. And the content has to be there — see
`REPORTS/M6-scoping.md`.

That last prerequisite is now measured rather than asserted. The scoping report's "no fight has
ever reached six participants" pre-dated M5-E/F and is **no longer true**: the average match's
biggest fight is 5.7 bodies and 3% of all fights reach six. What *is* true is that fights are
overwhelmingly small — **65% of them are two bodies** — and the reason is not macro. Teams do
converge: at the average fight 3.9 bodies are standing within reach of an enemy and only 2.6 are
swinging. **69% of that gap is the disengage lock** (§6.1), not a failure to rotate. The
prerequisite for the close-up view is therefore a *commitment* fix, not more plays.

### 7.3 Reference target ✅ — *Teamfight Manager 2* (designer, 2026-07-25)
The designer named a concrete long-term target for what a watched match should look and feel
like: **Teamfight Manager 2** (Team Nigo). Not to be copied — to be aimed at. Recorded here so
the bar does not drift; two screenshots were supplied (see `docs/reference/` — the observations
below are the durable part).

**What it does, and what we take from it:**

- **One renderer, a continuous zoom — not two views.** The same pixel-art map is watched close
  (a lane and its corridors filling the screen, sprites at readable size with name, level and HP
  bar) or pulled all the way out (the whole map, both bases, every turret). There are explicit
  zoom-in / zoom-out controls and an **"Auto Camera"** toggle. This corrects §7.2's framing:
  *overview* and *highlight* are **camera states of one view**, and the highlight director is an
  auto-camera decision plus a speed change, not a separate scene.
- **A minimap exists because the camera leaves home.** Once zoomed in you lose the map, so the
  pulled-out view carries a minimap with player dots, a viewport rectangle and objective timers.
  A minimap is therefore a *requirement* of zooming, not a decoration.
- **The map is real terrain.** Rock walls, brush, water, jungle blocks with corridors between
  them, camps sitting in their own pockets. At close zoom this is most of what you look at, and
  it is what makes a gank read as an ambush. Our map is lane polylines and points — this is the
  clearest statement yet that terrain is a prerequisite for the close view (§7.2, M6-D).
- **Sprites are small and cheap.** Characters are tiny pixel sprites — recognisable, animated,
  not detailed. The bar to clear for the close-up view is *far* lower than "real character art".
  ✅ **Adopted (designer, 2026-08-02): pixel sprite sheets, not procedural bodies.** The close-up
  actor is a 16–32 px animated pixel character per role, drawn from a sprite sheet, with the
  animation states in §7.2/M6-D. This lifts CLAUDE.md's placeholder-only guardrail *narrowly*:
  a CC0/free top-down pixel set (or one authored here) is allowed as the shared placeholder. The
  per-character `sprite` data field still overrides it with real art and no code change, so the
  contract is unchanged — only the default behind it. The map art direction follows the same
  choice: pixel terrain (§6.2) and pixel characters are one look, not two.
- **Persistent per-team panels** — five portraits a side, level and HP bar, each bound to a
  camera hotkey (F1–F10) so you can jump the camera to a player.
- **A scoreboard that reads like a broadcast** — per player: items in slots, KDA, CS, gold, with
  the gold lead marked per role. Top bar: team names, dragon/baron/turret counts, team gold,
  the kill score, the clock. (Items in slots are a system we do not have — we abstract item
  power. Recorded, not adopted.)
- **Big moments are announced.** A kill draws a full-width banner with both portraits —
  "Pure has slain Twisten!" — over the map. Our kill feed is a side list; the banner is the
  cheap juice item that makes a kill feel like an event.
- **Full transport, not just play/pause.** Skip-to-start, rewind, pause, fast-forward,
  skip-to-end, plus speeds 0.5 / 1 / 1.5 / 2 / 3. The viewer is treated as a *replay* you can
  move around in. (Our numbers differ — our 1x is already 4× sim-time, see §7 — but the model
  of "scrub and re-watch" is the one to aim at, and it makes "replay that highlight" natural.)

**Where we deliberately differ:** their sim is theirs; ours is the pro-play sim described in §6.1
and everything visible must still come from it (Pillar 3). And their game has no draft-time
management depth of the kind in §5 — the club/roster fantasy is ours to push further.

### 7.4 The broadcast header (designer direction, 2026-08-02)
The designer's reference is the **top bar of a real LoL broadcast** (Worlds / LEC / LCK, and the
OTP-lol-style watch-along framing) — the strip that sits across the top of every pro game and lets
anyone read the state of the match in one glance, without knowing anything else. Our HUD today has
a clock, a kill score and a gold bar scattered around the screen; this makes it *one* header that
reads like a broadcast.

**What the header carries**, per team, symmetrically around the clock:

- **Team name and tag**, tinted its side colour, blue left / red right.
- **Kills** — the big number, the pair of them either side of the clock.
- **Dragons taken**, as one pip per dragon (so "3 dragons, soul point" is readable at a glance,
  not a digit) — and **baron**, shown only when a team has it, with its remaining duration since
  the sim already tracks `baron_duration_s`.
- **Turrets destroyed**, a count per team.
- **Team gold**, absolute, both sides — with the **delta marked on the leading team only**, in the
  broadcast's own form: `+1.7k`. One number, on one side, so the lead reads instantly and never
  needs a subtraction.
- **The game clock**, centre.

**Rules.** Everything in it is a *read* of the sim's own snapshot and event stream — the HUD never
counts anything the sim did not report (Pillar 3). It is permanently on screen at every zoom level,
because the whole point is that a zoomed-in camera has lost the map and still has to tell you who
is winning. The existing side kill-feed stays; the header is state, the feed is narration, and the
full-width kill banner (§7.3) is the event.

**Not adopted, recorded:** per-player item slots from the reference target — we abstract item
power, and changing that is a sim decision, not a viewer one.

*(The highlight **selection weights** in §7.2 were reviewed at the same time and left as shipped:
nothing added, nothing blacklisted. The rarity bonuses there remain unbuilt-by-choice.)*

## 8. Later phases (recorded, not in PoC)
- PoC+ : club creation, pro-league calendar (LCK/LEC-like round robin), match history/standings, other matches simulated headless.
- Then: budget, mercato, coaching staff recommendations as a system, marketing, per-character sprites and kits, playoffs/international events.
