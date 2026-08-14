# Game data — designer's guide

Everything the sim knows about characters, players and teams lives in these JSON files. Edit values freely; then run `tools/check.sh` (or just tell Claude) to validate. No code changes are ever needed for a value tweak.

## characters.json — the 15 draftable characters (3 per role)
| Field | Meaning |
|---|---|
| `id` / `name` | Internal id (never change once referenced) / display name. |
| `role` | `top`, `jungle`, `mid`, `carry`, `support`. Exactly 3 characters per role. |
| `model` | The LoL champion this character is modeled on — anchors kit fantasy and sim behavior. Documentation only; never shown in-game. |
| `intent` | One-line design intent — documentation only, sim ignores it. |
| `sprite` | Sprite path fallback, used only when `sprite_by_side` is absent. The hook a true future per-character replacement (one path, no team variants) drops into with no code change. |
| `sprite_by_side` | `{"blue": path, "red": path}` — which team-coloured sheet to draw, since M6-D2's art bakes team colour into the file rather than tinting it at draw time. All characters sharing a `role` currently point at the same pair of files (one look per role, not per character yet — see BACKLOG's character-art follow-up for the long-term per-character intent). Regenerate with `tools/fetch_lpc_sprites.mjs`. |
| `curve` | Power curve: `early` (strong before ~14:00, falls off), `balanced`, `late` (weak early, monster after ~22:00). Multipliers defined in comp_rules.json. |
| `base` | Level-1 stats: `hp`, `damage`, `armor`, `speed`. |
| `growth` | Stat gain per level (levels 1→18, linear): `hp`, `damage`, `armor`. Speed doesn't grow. |
| `ultimate` | `name`, `effect` (sim effect type), `params`, `cooldown` (seconds). Effects get real behavior in M3 (fights). |
| `tags` | Comp identity: `engage`, `poke`, `scaling`, `early`, `protect`. Drives synergy/counter bonuses and coach recommendations. |

Ultimate effect types: `aoe_cc` (stun/fear/knockup/slow an area), `single_cc` (stun/root one target), `aoe_damage`, `single_burst`, `snipe` (long-range pick), `team_shield`, `team_heal`, `self_steroid`, `global_teleport`, `zone_denial`, `execute`.

## players.json — the 10 pros
| Field | Meaning |
|---|---|
| `handle` | In-game name shown everywhere. |
| `role` | The one role this player plays. |
| `identity` | One-line personality — documentation only (for now). |
| `attributes` | All 0–100. `mechanics` = fight/skirmish execution. `macro` = decision quality (rotations, objectives). `laning` = lane phase strength. `coach_compliance` = how reliably they follow the game plan / draft reco. |
| `champion_pool` | Proficiency 0–3 per character of their role. 3 = signature pick, 0 = can't play it. Drafting outside the pool (0) means a performance penalty — you lock it, they play it badly. |

`mood` is **not** stored here: per GDD it's a per-match modifier chosen in match setup.

## teams.json — the 2 PoC teams
`roster` maps each role to a player id. `color` drives the viewer's team-colour UI (ring outline, HP bar, badges, minimap dots) and picks which side of a character's `sprite_by_side` to draw; it no longer tints the character body itself (M6-D2 — that art bakes team colour into the file). `identity` is documentation.

## map.json — the map
Logical 100×100 map, blue base bottom-left. `lanes` are waypoint paths (blue end → red end); `towers` sit at fractions along each lane (0 = blue nexus, 1 = red nexus); `camps` are the jungle camps with their gold/XP/clear-time values; `pits` are the Dragon/Baron locations (used from M3).

## balance.json — the economy dials
Everything that tunes match pacing, in designer language:
- `minions`: wave timing/size, gold per minion type, XP per minion, and the lane-physics rates (how fast armies grind each other, how hard towers shred waves, how much a player's presence pushes their lane).
- `economy`: passive gold trickle, support's bonus income, when players recall to buy.
- `xp`: level-up cost curve and how bot-lane duo XP is shared.
- `cs`: last-hit success formula (base + laning skill; support assist bonus).
- `jungle`: camp spawn/respawn timing.
- `combat`: fight resolution. Kill/assist gold, `shutdown_*` bounties on kill-streak players (the comeback lever), `fight_variance` (how swingy fights are — higher = more upsets), `power_item_divisor` (how much a gold lead converts to fight power — the "leads matter" dial), `mechanics_power_*` (how much the Mechanics attribute sways fights), `macro_setpiece_*` (how much Macro sways objective/organized-defense fights specifically), and the death-count / respawn model.
- `ganks`: laning-phase gank frequency and success (warded lanes and high-Mechanics victims are harder to gank).
- `wards`: support ward cadence and duration (wards reduce enemy gank success in that area).
- `towers`: tower/nexus HP, siege damage from minions and players, gold bounty per tower.
- `objectives`: Dragon/Baron spawn/respawn timing, gold/XP rewards, Dragon stacking buff, Baron's temporary team buff + siege multiplier, and how teams decide to contest them.

Change a value, run `tools/check.sh`, then `tools/economy_report.gd` regenerates the gold/CS/level tables and `tools/batch_run.gd` regenerates win-rate / length / kill / snowball numbers so you see exactly what your change did.

## comp_rules.json — comp logic v1
- `phases`: sim-minute boundaries for laning → mid → late.
- `curves`: per-phase power multipliers behind each `curve` value.
- `synergies`: team-tag pairs granting a bonus (e.g. protect + scaling).
- `counters`: tag-vs-tag advantages applied team-vs-team (e.g. engage beats poke).

Bonuses are fractions (0.04 = +4% in the sim's combat weighting). Hand-tuned at tag level for the PoC; per-character matrices come later.
