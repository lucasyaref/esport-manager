# M6-A — Highlight scoring (headless, no view)

**Status: shipped.** Pulled forward to run alongside M5-G, as the backlog planned: the selection
layer is cheap, pure and headless-testable, and it doubles as the balance instrument M5-G needed.

## 1. What it is

`sim/highlights.gd` reads a finished match's event stream and returns the handful of moments worth
watching. It is pure analysis — it never runs inside the sim and cannot influence it — so it was
safe to build now, years of viewer work before the camera that will consume it.

Kills, fights, objectives and structures all become **anchors**: a time span and a position.
Anchors that overlap in *both* are one moment. That single rule is why a gank, the tower it buys
and the dragon that follows come out as one moment rather than three — which is how a viewer would
see it, and it needed no special-casing.

**Score** = kills + multikills + ace + bodies at the peak + gold swing + objective/structure value,
the whole thing multiplied by game clock (`late_bonus`). A play at minute 30 decides the game; the
same play at minute 4 does not.

**Selection** applies the designer's rule from GDD §7.2 — an absolute floor, so a quiet game gets a
*short* reel and never a padded one — plus spacing (no five clips of one long brawl), a per-kind
cap for variety, and a hard count. The nexus is exempt from all four: a match always ends on its
nexus.

Deterministic by construction: one ordered pass over an ordered event list, every sort tie broken
by the event's own index. Same seed ⇒ same reel.

Tunables live in `data/highlights.json`, and nothing in that file can change how a match plays out.

## 2. What to look at

```
godot --headless --path . --script res://tools/reel.gd -- --seed=42
godot --headless --path . --script res://tools/reel.gd -- --seed=42 --all
```

`--all` prints every candidate with its score and marks the ones that made the reel, which is how
the floor gets tuned against real numbers instead of taste.

**This is the M6-A gate: read a reel and say whether those are the moments you would want to
watch.** Seed 42, as shipped:

```
seed=42  red wins  23.0 min  30 candidate moments, 3 in the reel

* 14:44 — dragon to red, 1 kill                     61.9
* 21:04 — baron to red, 1 kill                      62.0
* 22:57 — nexus falls, red wins                    320.0
```

## 3. Supporting changes to the event stream

So the scorer never has to re-derive the sim:

- `fight_end` now carries the participant lists, the gold swing, and **`peak`** — the largest
  either side ever got *at once*. The member list only says who touched the fight, which over a
  20-second scrap reaches five without four bodies ever standing together. The peak is the honest
  "did a big fight happen".
- `kill` carries `victim_team`; `objective_taken`, `tower_destroyed` and `nexus_destroyed` carry
  `pos`, so moments can merge spatially.
- `SimMap.region()` moved up out of `batch_run` so the reports and the reel name places the same
  way. Same constants, so no previously reported number changed.

## 4. What it measured, immediately

The reel is now a batch metric, which is the point: *"does this match contain 5–10 things worth
watching?"* is a balance question before it is a viewer question.

| Over 200 sims (seeds 5000–5199) | Value |
|---|---|
| Moments in the reel | 7.8 |
| Candidate moments | 47 |
| Moments where a side lost 2+ bodies | 2.2 |
| Reel spread early / mid / late | 2% / 31% / 67% |
| Biggest fight of the match (bodies) | 5.7 |
| Fights that reach 6 bodies | 3% |
| Fights that are 2 bodies | 65% |

Three readings:

1. **The reel length is right.** 7.8 moments sits inside the designer's 5–10 without any tuning of
   the floor, which is a better sign about the sim than about the scorer.
2. **The scoping report's headline finding has expired.** "No fight has ever reached six
   participants" was measured before M5-E/F; the average match's biggest fight is now 5.7 bodies.
   Big fights happen. They are just rare.
3. **The early game contains nothing worth watching** — 2% of reel moments in the first third.
   GDD §7.2 wanted a reserved laning slot; reserving one today would reserve it for nothing.

## 5. What it found, which M5-G then had to fix

Because the scorer forced `peak` and `present` onto `fight_end`, the obvious next question was
answerable for the first time: at the average fight, **3.9 bodies are standing within reach of an
enemy and only 2.6 are swinging**.

That single number reframed the problem. It is not a macro failure — the teams *do* converge. The
missing bodies are present and declining. The reason breakdown is in `REPORTS/M5.md`.

## 6. Open questions for the designer

1. **Read a reel or three** (`tools/reel.gd --seed=N`) and say whether those are the moments you
   would want to watch. If a kind of moment you care about is missing, it is a weight in
   `data/highlights.json`, not code.
2. **The floor is currently doing a lot of work.** 47 candidates become 7.8 moments. That is the
   intended shape, but it means the difference between a 6-moment reel and a 10-moment one is one
   number. Do you want the reel to be *consistent* (fixed count, quality varies) or *honest*
   (count varies, quality floor fixed)? It ships honest, per your GDD rule.
3. **Rarity bonuses are not built** — first blood, a solo kill against a lead, a steal, a hold at
   the nexus, an outnumbered win (GDD §7.2). They are all cheap to add once the stream carries the
   facts. They are worth doing when the reel starts feeling samey; it does not yet, because the
   sample is three dragons and a baron.
