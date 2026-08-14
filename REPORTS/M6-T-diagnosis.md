# M6-T balance diagnosis — why does blue keep winning more?

**Status: cause found, fix not yet chosen — your call below.** Three terrain phases (T2 routing,
T3 brush, T4 camp separation) each pushed blue-side win rate further from the ~50% target
(49.7%→55.0%→57.7%→61.3%), and T4's report ruled out the working theory (camp/pit overlap). This
is the follow-up diagnosis pass you asked for instead of another blind terrain guess.

## 1. Method

Added a per-side breakdown to `tools/batch_run.gd` (kills, deaths by role, objectives, towers,
fight wins, gank/sandwich connect rate, gold differential over time — all split blue vs. red) and
ran it against the current tree (T1–T4, `brush_reveal_radius` at its shipped 3.5): 300 sims, seeds
5000–5299, same methodology as every phase report so far. `wins` are already isolated from which
named team is strongest — the batch alternates which team plays which side every match — so this
was never a team-balance question, only ever a side one.

## 2. What the breakdown actually shows

| Side breakdown | blue | red |
|---|---|---|
| Kills | 50% | 50% |
| First blood taken | 60% | 40% |
| Dragons taken | 49% | 51% |
| **Barons taken** | **61%** | **39%** |
| Towers lost | 49% | 51% |
| Fights won (decided only) | 50% | 50% |
| Gank/sandwich calls made | 50% | 50% |
| ...connect rate of those calls | 28% | 27% |

Gold differential (blue − red): +0 at 0 min, +239 at 15 min, **−369 at 30 min** (300/300/64
samples) — a swing that changes sign, not a steady lead. Deaths by role are within a body or two
of even on both sides.

**Every proximate combat number is a coin flip. Win rate is not (61.3% blue).** The one number
that isn't flat — barons taken, 61% blue — sits almost exactly on top of the win-rate split itself
(61% vs. 61.3%). That match is the finding: this isn't a kills-and-gold advantage compounding into
a win, it's one objective being decisive, and blue getting it more.

## 3. Why: baron is the stronger objective, and blue's base sits closer to it

From `data/map.json` (unchanged by any T-phase — pits never moved, only T4's four camps did):

| | distance to baron | distance to dragon |
|---|---|---|
| blue base | **43.1** | 61.8 |
| red base | 61.8 | **43.1** |

The map is exactly 180°-symmetric (guard-railed) — blue is closer to baron by precisely the same
margin red is closer to dragon. That's fair *if the two pits are worth the same*. They aren't, per
`data/balance.json`:

| | dragon | baron |
|---|---|---|
| Gold per player | 100 | **300** |
| XP per player | 150 | **250** |
| Buff | +3% per stack (stacking) | +6% power, **3.0× siege damage**, 180 s |

Baron's siege multiplier is the whole story: it's the buff built to end a game (three times the
damage to towers and the nexus), worth 3× the gold, on top of an already-closer walk. Dragon is a
steady incremental buff with no siege component. **The map's spatial symmetry is real; the two
objectives sitting on it are not equivalent, so blue drew the stronger half of a fair-looking map.**

## 4. Why this only started showing up at T2, not before

This asymmetry was in the data before T1 existed — base and pit positions haven't changed all
milestone. T1's own baseline (49.7% blue-side, flat) shipped with it already there and it didn't
move the number. Best explanation: before T2, movement had no wall-respecting cost — every body
walked a straight line regardless of terrain, so "closer" was a fixed, small, one-time constant
that a whole game's worth of gold/kills could wash out. T2 made real path cost matter for the first
time; T3's brush and T4's camp move both then landed changes *in the same neighbourhood* (baron's
jungle, where two of T4's four moved camps sit) without ever touching the underlying proximity or
value gap. Three independent, individually-reasonable phases kept nudging a knob next to the actual
cause instead of the cause itself — which is why none of them fixed it, and why T4 made it worse
rather than better.

## 5. What isn't the cause, ruled out by this data

- **Team strength / roster balance** — kills, gold, deaths, fight wins are all ~50/50; this isn't
  the macro win-vector question, it's orthogonal to it.
- **Camp/pit overlap** (T2/T3's working theory) — already ruled out by T4's own batch delta
  (`REPORTS/M6-T4.md`), consistent with this: separating the camps didn't touch the actual lever
  (objective value + base distance), so of course it didn't move the number.
- **Terrain asymmetry** — `tools/check.sh`'s symmetry and anchor-symmetry checks pass; the grid
  itself is exactly fair. The unfairness is in what sits on top of the fair grid, not the grid.

## 6. Recommendation

**A data-only fix, not another terrain change.** The lever that's actually decisive is in
`data/balance.json`, not `data/terrain.txt` or `data/map.json` — bringing baron and dragon closer
to parity (or accepting the proximity gap but shrinking baron's edge enough that a 12-second
head start doesn't decide the game) is cheap to try and directly targets the mechanism this report
found, unlike the last three phases. I'd rather bring you a measured option than guess at numbers
myself given how wrong the last hypothesis was.

## 7. Questions for you

1. **Is baron *supposed* to be this much stronger than dragon**, or was `baron_siege_mult: 3.0`
   sized without weighing it against the fact that one side is always closer? If it's intentional
   design (baron as a late-game "win the game" objective, dragon as an early incremental one), the
   fix is a proximity one, not a value one — and proximity is much harder to fix cleanly (the pits
   can't both be equidistant from both bases without sitting on the river centreline, which T1
   deliberately moved them off of for an unrelated reason).
2. **If it's a value question**: want me to run a quick sweep on `baron_siege_mult` (e.g. 3.0 → 2.0
   → 1.5) and bring back the win-rate delta for each, the same way the brush-radius sweep worked?
3. **Scope check**: this sits outside T1–T4's original brief (terrain), even though terrain is what
   surfaced it. Fine to treat as its own small balance pass rather than folding it into the M6-T
   phase list?

## 8. Dragon Soul experiment (2026-08-12) — tried, doesn't work as tuned

Your proposal was to skip nerfing baron and instead give dragon a real LoL-style "Soul" payoff: a
discrete power spike at 4 stacks (`dragon_soul_stacks`), on top of the existing linear per-stack
buff, so a team that commits to dragon has its own game-winning lever to match baron's. Implemented
faithfully — `dragon_soul_power: 0.20` added to `team_buff()`, no siege-multiplier counterpart
(real Dragon Soul doesn't buff structures either, so this stays a champion-power buff only).

**Result: it changed nothing.** The 300-sim batch (same seeds as the diagnosis) came back
byte-identical to the pre-fix baseline — same 61.3% blue win rate, same 61%/39% baron split, same
gold curve, to the decimal. In a deterministic sim, identical output after a code change means the
new code never ran.

Added a small diagnostic (`tools/batch_run.gd`'s new "Dragon stacks" table) to confirm why, over
the same 300 games:

| | Value |
|---|---|
| Highest single-team dragon stack count seen, any match | 3 |
| Matches where a team reached 3+ stacks | 11% |
| Matches where a team reached 4+ stacks | **0%** |

Zero of 300 games ever had one team hold 4 dragons. The reason is upstream of the threshold choice:
this sim only sees **2.1 dragons taken in total, across both teams, per match** — for comparison, a
real LoL game at ~27 minutes (this sim's average length) typically sees 4–6 dragons taken combined.
At that uptake rate, a 4-stack threshold isn't a high bar the way it is in real LoL, it's an
unreachable one — even 3 stacks, which needs a team to win nearly every dragon fight of the game,
only happens one game in nine.

**This isn't a threshold-tuning problem** (lowering `dragon_soul_stacks` to 2 wouldn't obviously
fix it either — with total uptake at 2.1, a team getting 2 of its own still requires largely
sweeping the objective, which is exactly as rare). The real gap is *why so few dragons get taken at
all* relative to how often they're up — that's a separate, unmeasured question this session hasn't
looked at (jungle-control priority, contest logic, or just respawn timing vs. match length), and
fixing it would change more than this one balance question.

## 9. Recommendation (revised)

Given §8, dragon-buffing isn't the cheap fix it looked like on paper — not because the idea is
wrong (it's exactly how real LoL does it), but because it needs dragon to actually be contested at
something closer to real-game rates first, which is a bigger, separate lift. **§6's original
recommendation stands**: a direct pass at `baron_siege_mult` is still the cheapest lever that's
*provably* connected to the 61.3% number, because the mechanism (siege multiplier + base proximity)
is measured, not inferred. I'd suggest either:
   - **(a)** sweep `baron_siege_mult` (3.0 → 2.0 → 1.5) now and bring back the win-rate delta per
     step, same method as the brush-radius sweep, or
   - **(b)** keep Dragon Soul in the data as flavor (it's harmless — it just never fires under
     current dragon uptake) and separately scope a "why is dragon uptake so low" investigation,
     which could make dragon-buffing viable later without touching baron at all.

## 10. Questions for you (revised)

1. Given §9, want the `baron_siege_mult` sweep run now (path a)? That's the fastest way to close
   this out.
2. Or would you rather I first look at why dragon uptake is only 2.1/match before deciding between
   nerfing baron and fixing dragon's own economy (path b)? This is slower and doesn't guarantee a
   cleaner answer, but it's the more faithful version of your original instinct.
3. Either way: keep `dragon_soul_stacks`/`dragon_soul_power` in `data/balance.json` as shipped
   (inert but harmless), or revert them until dragon uptake is actually fixed? Leaning toward
   keeping — it's correct code sitting on top of an economy that isn't ready for it yet, not a bug.

## 11. The `baron_siege_mult` sweep (2026-08-12) — target hit at 1.5

Ran path (a): 300 sims each, seeds 5000-5299, same method as every sweep this milestone
(`brush_reveal_radius` included). Nothing else in the tree changed between runs — Dragon Soul stays
in the data as shipped (§10 Q3), confirmed inert at every step since barons/dragons taken don't
depend on `baron_siege_mult`.

| | 3.0 (shipped) | 2.0 | 1.5 |
|---|---|---|---|
| Blue-side win rate | 61.3% | 53.0% | **50.3%** |
| Barons taken (blue / red) | 61% / 39% | 58% / 42% | 62% / 38% |
| Fights won, decided (blue / red) | 50% / 50% | 52% / 48% | 52% / 48% |
| First blood (blue / red) | 60% / 40% | 60% / 40% | 60% / 40% |

**1.5 lands on the target almost exactly** (50.3% against the ~50% goal, down from 61.3%) — a
clean, near-linear response to the multiplier, no overshoot into red-favored. Worth noting: barons
taken *stays* blue-skewed at every step (58-62% blue throughout, no clear trend) — blue is still
structurally closer to baron and still takes it more, siege multiplier or not. What changes is how
much a baron kill is *worth*; at 1.5× a bonus baron doesn't convert to a nexus the way it does at
3.0×, so the proximity edge stops deciding games even though it's still there. This matches §6's
original framing: proximity isn't fixed (nor does it need to be), value parity is.

## 12. Recommendation

**Ship `baron_siege_mult: 1.5`.** It's the only tested value that closes the gap without touching
terrain, dragon, or anything else already in the tree, and three phases of terrain guesses (T2-T4)
already showed that chasing this any other way doesn't work. `data/balance.json` is currently back
at the original 3.0, uncommitted, pending your sign-off — flagged this explicitly since halving
baron's siege damage is a real feel change (a solo baron take, or a bad teamfight loss into an enemy
baron, now costs a tower or two rather than potentially the game), not just a balance-table number.

## 13. Questions for you

1. **Ship 1.5?** Or does baron feeling like less of a "the game is over" objective change how it
   should read narratively (the broadcast header in M6-G shows baron's remaining duration — a
   weaker baron might still deserve the same visual weight, or might not)?
2. Want a finer step between 1.5 and 2.0 (e.g. 1.75) to see if there's a value that keeps more of
   baron's swing without re-opening the gap, or is 50.3% close enough that finer tuning isn't worth
   the batch time?
3. §10's dragon-uptake investigation (why only ~2.1 dragons/match) is still open as a separate,
   unscoped follow-up — want that picked up now, or parked since baron alone closes the balance gap?
