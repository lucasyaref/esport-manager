---
name: next-milestone
description: Run the next actionable BACKLOG.md step end-to-end — implement via a Coder subagent, verify via a Tester subagent, update BACKLOG.md/CHANGELOG.md and write the REPORTS/ entry, then hand back a short report with decision points. Use when the designer says to do the next step, next phase, continue the backlog, or "go" — without wanting a play-by-play of how it happened.
---

# Next milestone — orchestrator loop

You are the **orchestrator**. The designer is the **executive**: they set direction, answer design
questions, and playtest. Per CLAUDE.md, they never read code or diffs — that's the whole point of this
loop. Your job is to run one BACKLOG.md step to completion and hand back a short report, not a
transcript of how you got there.

## Roles

| Role | Who | Does |
|---|---|---|
| Orchestrator | you | reads BACKLOG.md, scopes the next step, delegates, updates docs, reports |
| Designer | the user | direction, design-only decisions, playtest feedback — never asked technical questions |
| Coder | `coder` subagent | implements the step: sim/game code, data files |
| Tester | `tester` subagent | headless batch runs + stats, or launch + screenshot checks |

This split exists for the same reason it does in `gauntlet-map`: it keeps the designer's view down to
a short report instead of a transcript, and it keeps your own context clean enough to actually reason
about what's next instead of drowning in one task's tool calls. Unlike the map critics, Coder and
Tester are **not** meant to be cold — brief them with exactly what they need (see each agent's file).

## Before you start

1. Read BACKLOG.md's **Status** table and **Now** section. There is normally exactly one item flagged
   as next (e.g. "phase T next", "T3 next", "B next") — take that one. Don't infer a different one from
   the Parking Lot or a stale "Next" list entry.
2. **If the step is map/terrain look-and-feel** (layout, palette, how the map reads visually): stop and
   invoke the `gauntlet-map` skill instead. Don't reimplement that loop here.
3. **If the step is blocked on an open designer call** — BACKLOG.md accumulates these explicitly
   ("designer gate open", "three designer calls are open", etc.) — and the block is a genuine
   design/gameplay question, stop and ask the designer via `AskUserQuestion` before doing any work.
   Do not guess at gameplay intent. Technical implementation details are never a reason to stop.
4. Skim the most recent one or two files in `REPORTS/` for the current milestone, so your Coder/Tester
   briefs carry the right prior-art pointers instead of re-deriving them.

## The loop

1. **Scope the step.** Write down, for yourself: what BACKLOG.md item this is, what "done" looks like,
   and what — if anything — needs measuring (a batch stat target, a visual check, or neither).
2. **Trivial exception.** A one-line data tweak or an obvious typo-level fix doesn't need a subagent —
   just make it. Reserve delegation for steps with real implementation surface. When in doubt, delegate;
   the point is to keep your context and the designer's report clean, not to avoid all direct work.
3. **Delegate to `coder`.** Give it: the BACKLOG.md item, the concrete change, and relevant prior art
   (file paths, similar past phases, the data shape to follow). Run it in the foreground if you need its
   result before deciding what Tester should check; background if you have other scoping to do meanwhile.
4. **Delegate to `tester`** if the step has something to verify — a batch balance run, a headless
   self-test, or a visual check. Give it explicit pass criteria; don't make it invent a bar. Skip this
   step for changes with nothing measurable (e.g. pure refactors already covered by `tools/check.sh`
   inside the Coder's own run).
5. **Update the docs**, per CLAUDE.md's standing rule:
   - Write the `REPORTS/` entry — full detail, batch numbers, what to look at, open questions. This is
     the durable record; the chat report in step 6 is not a substitute for it.
   - Update BACKLOG.md's Status table and **Now** section to reflect what shipped and what's next.
   - If a whole milestone or phase closed out, move its detailed narrative into CHANGELOG.md, leaving
     one line behind in BACKLOG.md — CLAUDE.md requires this and it's easy to skip under time pressure.
6. **Report to the designer** — see format below.

## Report format (what the designer actually sees)

Short. A few bullets, not prose. Always include:

- **What shipped** — one or two lines, plain language, no jargon a non-coder wouldn't have.
- **Result**, if anything was measured — the numbers that matter, against the target if there is one.
- **What to look at** — a concrete action: "run the game and look at X", "read REPORTS/M6-T3.md for
  the full numbers", "here's the screenshot".
- **Open decision(s)**, if any — only genuine design/gameplay calls, framed as a choice with the
  tradeoff stated, the way BACKLOG.md's "designer decisions" log already does it. If there are none,
  say so plainly rather than manufacturing a question.
- **A prompt for direction** — what you'd do next by default, and an invitation to redirect.

Never ask the designer to resolve something you could decide yourself (tools, code structure, which
file something lives in). That's the one failure mode that turns this loop back into what it's meant
to replace.

## Cost discipline

Coder and Tester are fresh subagents — cheaper than a cold critic read since you brief them fully, but
still real overhead per spawn.

- Don't spawn a Tester to re-confirm something the Coder's own self-test already checked.
- Don't run this loop phase-by-phase in a tight loop without designer input in between — BACKLOG.md's
  existing checkpoints (playtest gates, "designer decisions" sections) exist on purpose. One step, one
  report, then wait, unless the designer has explicitly asked you to run several in a row.
