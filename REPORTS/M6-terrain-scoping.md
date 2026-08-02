# M6-T scoping — the real map: terrain, walls and brush

**Status: scoped, draft 1 of the map exists, no code written.** Your direction of 2026-08-02
("let's build it together based on a League map — I'm bad at art, do most of the work, but it has
to look at least as good as Teamfight Manager 2") turned into GDD §6.2, phase **M6-T** in
`BACKLOG.md`, and the draft map in `data/terrain.txt` that this report is mostly about.

## 1. How we build it together

The problem with "build a map jointly" is that the usual artefacts are bad for it: a polygon
list is unreadable, an image is uneditable by you, and a level editor is a week of work I'd
rather spend on the game. So the map is **a text file you can read as a picture**.

`data/terrain.txt` is a 50×50 character grid — one character per 2×2 world units, covering the
whole 100×100 map. Open it in any editor, and you are looking at the map from above. Move a
wall by typing a `#`. Widen a corridor by typing three dots. That is the entire tool.

```
;   #  wall     rock. not walkable, blocks sight.
;   .  open     walkable jungle floor.
;   ,  brush    walkable; hides a body from enemies outside it.
;   ~  river    walkable, cosmetic.
;   o  pit      walkable; the dragon / baron bowls.
;   =  lane     walkable; the lane road.
;   c  camp     walkable; a jungle camp pocket.
;   B / R       base floor.
```

The legend lives at the top of the file itself, so it never goes stale.

**The loop is: I draft → you read the picture and tell me (or type) what's wrong → I render it
and measure what it did to the sim.** You never have to open a graphics tool, and I never have to
guess at your taste from prose. The renderer turns those characters into the pixel-art look —
rock faces with lit tops, grass, water with a shimmer, pit bowls. That part is mine; the shape of
the map is the part where your read is better than mine, and it happens to be the part that a
text grid expresses perfectly.

**Guard rails the loader enforces**, so an edit can never quietly break the game: exactly 50×50,
every camp/pit/tower/base position in `map.json` on a walkable cell, every walkable cell
reachable from both bases, and **180° rotational symmetry** — blue-side win rate is a metric we
track, so an asymmetric map would poison every balance number we have. If you type something that
breaks one of those, `tools/check.sh` says which cell and why.

## 2. Draft 1

Generated from `data/map.json`'s real lane polylines, pits and camps, so it is consistent with the
sim as it exists today. Blue bottom-left, red top-right, mid on the diagonal, river on the other
diagonal, four jungle quadrants of corridors between camp pockets.

```
##################################################
########################################RRRRRRRRR#
################################========RRRRRRRRR#
################===================,,===RRRRRRRRR#
###===============================,,,,==RRRRRRRRR#
##================================,,,,==RRRRRRRRR#
##======================#####......######RRRRRRRR#
##======~~~#################......######=RRRRRRRR#
##====~~~~~~###############c.....######===RRRRRRR#
##====~~~~~~~############.ccc....#####=====#RRRRR#
##====#~~~~~~~##########..ccc.....###=====##====##
##====##~~~~~~~########.,,.c........=====###====##
##====###~~~~~~~#####..,,,,####....=====####====##
##====####~~~~~~~###...,,,######..=====#####,===##
##====#####~~~~~~~#cc...#########=====######,===##
##====######~~~~~~~cc..#########=====..####,====##
##====#######~~~~oooo.#########=====....##..====##
##====########~~oooooo########=====#....#...====##
##====########.~oooooo.######=====###.......===###
##====#######.ccoooooo~.####====,####.......===###
##====#######.ccoooooo~~.##=====######......===###
##====######.....oooo~~~~.=====#######.cc..#===###
##====#####,,......~~~~~~=====########cccc##===###
##====#####,,,.#....~~~~====,,#######..cc###===###
##====####,,,,###...,,~====,,,,######,,..###===###
##===####..,,######,,,,====~,,...###,,,,####===###
##===####cc..#######,,====~~~~....#.,,,####====###
##===###cccc########=====~~~~~~......,,####====###
##===##..cc.#######=====.~~~~oooo.....#####====###
##===#......######=====##.~~oooooo...######====###
##===#.......####,====####.~ooooooc..######====###
##===........###=====######.oooooo~.#######====###
##===....#....#=====########oooooo~~#######====###
##===...##....=====#########.oooo~~~~######====###
##===.,####..=====#########...c~~~~~~~#####===####
##===,######=====#########.....#~~~~~~~####===####
##===######=====..######,,,...###~~~~~~~###===####
##===#####=====....####,,,,..#####~~~~~~~##===####
##===####=====........c.,,.########~~~~~~~===####
##===###=====###.....ccc..##########~~~~~~~===####
#BBBBB#=====#####....ccc.############~~~~~~===####
#BBBBBBB===######.....c###############~~~~~===####
#BBBBBBBB=######......#################~~~====####
#BBBBBBBB######......###################~~====####
#BBBBBBBBB####,,...######=====================####
#BBBBBBBBB==,,,,==============================####
#BBBBBBBBB===,,===============================####
#BBBBBBBBB===================================#####
#BBBBBBBBB########################################
##################################################
```

56% of the map is walkable, which is about right for Summoner's Rift.

**What I already know is wrong with it, and would fix before you spend time reading it:**

1. **`b_camp_bot` (62,33) and `r_camp_bot` (67,38) are inside the dragon pit.** Not a terrain bug —
   the terrain draft *exposed* it. Those two camps have always been sitting on top of dragon; at
   overview scale nobody could see it. Same story mirrored at baron. This is exactly the class of
   thing the map file is good for, and it is why T4 (moving camps into real pockets) is a phase.
2. **The lanes in `map.json` are only approximately symmetric** (top starts at x=7, bot at y=7, but
   top bends at 88 and bot at 88 with different offsets). Small, invisible today, visible the
   moment a wall is drawn beside a lane. Worth straightening while we're here.
3. **The jungle is more corridor than clearing.** Real SR jungle is fairly open with wall *chunks*
   in it; draft 1 carves paths through solid rock, which is tighter. I went tight deliberately —
   chokepoints are the thing you actually want for a gank to read — but it may be too maze-like
   once bodies are moving through it. Easiest thing in the world to loosen once we watch it.
4. **Red's top-right corner is cramped** around rows 6–9, where the base, top lane and the jungle
   all meet. Needs a look.

## 3. What it costs, in phases

Each sub-phase ends runnable and measured, so we can stop or turn at any of them.

**T1 — the map exists and is drawn (cosmetic).** The loader, the checks, and the renderer. The sim
is untouched: bodies still walk through walls, but you can *see* the map and judge whether it
looks right. This is the phase where your read matters most and the risk is lowest, and it's where
the pixel-art look gets settled — rock, grass, water, brush, pit bowls, the lane roads. Nothing
about balance moves, so there is nothing to re-measure.

**T2 — movement respects walls.** The real change. A body routes around terrain instead of walking
through it, on a navigation grid precomputed at load (no per-agent search at runtime, and it stays
deterministic — that is non-negotiable, per CLAUDE.md). This *will* move balance: ganks from the
enemy jungle arrive later, a fleeing carry can be cut off at a chokepoint, and rotating across the
map costs real time it didn't before. I'll bring you the batch delta on gank connect rate, escape
rate, first-tower timing and the macro win vector before it's kept.

**T3 — brush hides you, walls block sight.** Separable from T2 on purpose. T2 changes how a gank
*looks*; T3 changes how a gank *plays* — sitting in a brush and being genuinely unseen is the
mechanic that makes an ambush an ambush. It is also the biggest balance change in the milestone,
so it gets its own measurement and its own go/no-go.

**T4 — camps and pits into their real pockets, sign-off.** Fix the two camps in the dragon pit,
straighten the lanes, re-run the full batch, `REPORTS/M6-T.md`.

My instinct on ordering: **T1 first and alone**, because you can judge it in five minutes and it
sets the art direction that M6-D's pixel characters then have to match.

## 4. What terrain is *not*

Recorded so it doesn't creep. No per-body collision — bodies still overlap, and the separate
"sim-side body volume" question stays open and separate. No minions leaving their lanes; they are
still squads on a polyline. No runtime pathfinding search per agent. No destructible terrain, no
wards, no fog of war beyond what T3's brush and wall-sight give us.

## 5. Questions for you

1. **Read the picture in §2 and tell me what's wrong with it.** Anything: "jungle's too tight",
   "river should be wider", "I want a wall there". That's the whole loop, and this first round is
   the one where changes are free.
2. **Do you want T3 (brush and vision) at all in the PoC?** It's the most fun mechanic in here and
   the most disruptive to a balance pass we just signed off. I'd build it, measure it, and let the
   numbers decide — but if you'd rather the PoC ship on the balance we have, T1/T2/T4 alone still
   give you a map that looks right and corridors that matter.
3. **Pixel art source.** Your answer (b) lifts the placeholder guardrail for a shared sprite set. I
   can either author the terrain tiles procedurally in the same pixel style (zero dependency, and I
   control it exactly) or pull a CC0 top-down tileset. For *terrain* I lean **authored** — a
   tileset that isn't shaped for our map fights us — and save the CC0 route for the **characters**
   in M6-D, where the animation work is what's expensive. Say if you'd rather I look for a pack.
