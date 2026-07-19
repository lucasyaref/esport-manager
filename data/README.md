# Game data — designer's guide

Everything the sim knows about characters, players and teams lives in these JSON files. Edit values freely; then run `tools/check.sh` (or just tell Claude) to validate. No code changes are ever needed for a value tweak.

## characters.json — the 15 draftable characters (3 per role)
| Field | Meaning |
|---|---|
| `id` / `name` | Internal id (never change once referenced) / display name. |
| `role` | `top`, `jungle`, `mid`, `carry`, `support`. Exactly 3 characters per role. |
| `intent` | One-line design intent — documentation only, sim ignores it. |
| `sprite` | Sprite path. All share one placeholder for now; per-character art later = just change this path. |
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
`roster` maps each role to a player id. `color` tints the shared sprite in the viewer. `identity` is documentation.

## comp_rules.json — comp logic v1
- `phases`: sim-minute boundaries for laning → mid → late.
- `curves`: per-phase power multipliers behind each `curve` value.
- `synergies`: team-tag pairs granting a bonus (e.g. protect + scaling).
- `counters`: tag-vs-tag advantages applied team-vs-team (e.g. engage beats poke).

Bonuses are fractions (0.04 = +4% in the sim's combat weighting). Hand-tuned at tag level for the PoC; per-character matrices come later.
