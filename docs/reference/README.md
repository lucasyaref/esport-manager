# Reference material

Visual and design targets we are aiming at. Nothing here ships in the game.

## `map/` — ours, committed

Images the designer made or commissioned for **this** map. These are the gauntlet loop's
palette and mood evidence (`docs/gauntlet-map.md`). See `map/README.md` for what each one is
for and, importantly, what it is *not* for.

## `inspirations/` — third-party, git-ignored, local only

Screenshots of other people's shipped games. **This folder is in `.gitignore` and must stay
there.** It is someone else's art; it is evidence for a conversation, not an asset of this
project, and it never goes to a public remote.

The rule that follows from that: **the durable record is the written observation, not the
image.** Anything worth keeping from a screenshot gets written up in `GDD.md` in our own
vocabulary, phrased as a rule for our map, so it survives the file being deleted and so this
repository does not read as a catalogue of another game.

What we have taken from this folder is in **GDD §7.3** (viewer structure — one renderer with a
continuous zoom, minimap, broadcast scoreboard, kill banner, transport) and **GDD §6.3** (the
map's look). §6.3 is the one to read before touching the renderer: it states the eight rules the
map obeys, including the two that come from no reference at all, and it outranks every image in
this tree when they disagree.
