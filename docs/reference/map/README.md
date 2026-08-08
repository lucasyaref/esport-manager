# Map reference images

**Designer: drop the images here.** Any filename, PNG or JPG. That is the whole handover —
I read the folder, not the chat, so the reference survives the conversation it arrived in.

These are evidence for **gauntlet loop 1** (`docs/gauntlet-map.md`). They are no longer the
acceptance criteria on their own: **the criteria are GDD §6.3**, the eight rules the map obeys.
Where an image here and §6.3 disagree, §6.3 wins and the difference is logged `by-design`.
Read §6.3 before the loop's first iteration of a session.

Useful, if you have them, but never blocking — one image is enough to start:

- **the whole map**, top-down, the way it is normally seen. This is the one that matters most,
  because it is the view the game is in for most of a match.
- **a closer crop** of any part of it — jungle, a lane, a pit. Says what the texture and edge
  detail should be at zoom, which the whole-map shot cannot.
- **anything you like the look of but do not want copied.** Say so in a line of text next to
  it and I will record it as a deliberate difference rather than chase it.

If an image is meant to fix the *layout* (where the walls and corridors go) rather than the
*look* (colour, texture, edges), it is worth saying which — they pull on different halves of
the rubric, and I will otherwise assume an image is aiming at both.

---

## What is in here now

### `terrain_moba_2.png` — **palette and mood only** (designer, 2026-08-08)

> **Demoted the same day it arrived** (designer direction, 2026-08-08). It was briefly the whole
> look target; it is now one of two sources, and the smaller one. The direction is toward a
> sparser, darker, chunkier map than this — see GDD §6.3 rules 1–4 — with this image supplying
> the **warmth**: warm stone, the sand-coloured road, accent light at the bases and pits.
> Its density and its ornament are *not* the target. Findings that push the render toward
> "more painted, more decorated, more lit" are `by-design` refusals, not work.

Supersedes the earlier `Pixel_art_MOBA_arena_map_…jpeg`, which was the same artwork at a
tighter crop; this version shows the full rampart and the corners, so it says more about the
map's edge. The old crop was deleted rather than kept — two versions of one picture is two
answers to the same question.

**This image fixes the look. `data/terrain.txt` and `data/map.json` fix the layout.**

It is an illustration, not a playable map, and its geometry cannot be adopted: it is 4:3
against a square 100×100 world, its lanes are a perimeter ring with no readable mid, and it
has no tower positions. Judge palette, value structure, contrast relationships, surface
texture and edge treatment against it. Do **not** move a lane, a pit or a base to match it.

The one layout lesson already taken from it is the **arena margin** — its outer road sits well
inside a thick rampart with jungle between the two. That was decided as a gameplay call
(iteration 11), not read off the picture as art.

**Deliberate differences — present in the reference, not wanted in the map:**

| In the reference | Why we are not chasing it |
|---|---|
| Statues, torches, braziers, rune glyphs, per-object props | Authored art on a bitmap. The map is a tile renderer; these need a decal/sprite layer, which is not M6-T1. |
| Painted lighting — torch bloom, cast glow, soft gradients | Same reason. Value *hierarchy* is in scope; painted light is not. |
| Vignette and the dark framing border | It is a framed illustration; the map is a viewport that pans and zooms. If we want one it belongs in the viewer as a screen-space overlay, never baked into the terrain. |
| 4:3 aspect and the outer glow around the arena | Artefacts of the frame, not features of the map. |
| The two sparkles, lower right | Generator watermark. Not a map feature. |
| Ornament spread evenly over the whole map | GDD §6.3 rule 7 — the ornament budget goes to the bases, the two pits and the river, and the jungle is texture. |
| Fine-grained detail defining the shape of a rock mass | §6.3 rule 4 — masses are big and chunky, noise lives *inside* a mass. |
| Rich overall saturation | §6.3 rule 2 — water is the only strongly saturated thing on the map. |

A cold critic cannot know any of the above, so it will keep reporting them. That is the critic
working correctly — the orchestrator files them as `out-of-scope` (unreachable by any knob) or
`by-design` (reachable, and refused), and neither blocks the exit. See `docs/gauntlet-map.md`.

**Still missing, and worth having:** a close crop of one jungle quadrant. Without it the panel
judges texture by comparing a 1452 px painting against a 1024 px render, which inflates every
texture finding it makes.
