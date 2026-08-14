// M6-D2: regenerates game/assets/characters/lpc_<role>_<blue|red>.png from the
// Universal LPC Spritesheet Character Generator
// (https://liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator/),
// headlessly — no manual browser step, no "Claude in Chrome"-style extension.
// Re-run this if a role's look changes (weapon/hair/hat below) or a new role
// is added; the output path is exactly what data/characters.json's
// `sprite_by_side` fields already point at. Also regenerates
// game/assets/characters/LPC_NOTICE.txt from the generator's own "Credits
// (TXT)" export for every selection used — this is not CC0 art, the site's
// own credits page asks reuse to attribute it, and the export is the
// authoritative per-asset author/license/link list, not something to
// hand-summarize.
//
// Requires: Node, `npm install playwright-core` (browsers not bundled — this
// reuses whatever Chromium Playwright already has cached locally; point
// CHROME_PATH at any Chromium/Chrome executable if none is cached).
//
// Usage: node tools/fetch_lpc_sprites.mjs
//
// -- Why this doesn't just screenshot the on-page preview -------------------
// The small "Animation Preview" panel (#previewAnimations) is *not* a strip
// of animation frames — reading the app's own source
// (sources/canvas/preview-animation.ts) shows it redraws, on every
// requestAnimationFrame tick, one fixed cycle-frame column across all 4
// *directions* stacked side by side. Screenshotting it mid-cycle gives four
// different facings at one arbitrary pose, not "this pose" advancing through
// its frames — completely wrong to use as our four-frame walk/attack strips.
// This script instead reads `window.canvasRenderer.getCanvas().value` (the
// full, real character sheet, exposed by the app itself for its own
// download button) and crops fixed (row, column) frames straight out of it,
// per the row offsets in sources/state/constants.ts' ANIMATION_CONFIGS
// (row = animation's block start + direction index; DIRECTIONS =
// ["up","left","down","right"], so "down" = +2 — the front-on, walking-
// toward-camera facing this top-down game already uses as its one drawn
// facing, horizontally flipped for the other side, same as the placeholder).
//
// -- Per-item animation gaps (verified against a live capture, not assumed) -
// Not every weapon/hat/hair supports every animation row — e.g. Arming
// Sword's only working swing is the oversized `slash_128` (double every
// other row's frame size, which this pipeline can't mix into one uniform
// sheet); a black hat on black hair was invisible at this frame size. Both
// were caught by rendering and looking, not by trusting the generator's
// "Current Selections" panel alone (that only confirms the pick parsed, not
// that it reads as intended). Re-verify visually after changing any pick
// below — see REPORTS/ for the review pass this shipped from.

import { chromium } from "playwright-core";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT_DIR = path.join(HERE, "..", "game", "assets", "characters");

const GENERATOR_URL =
  "https://liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator/";

const FRAME = 64;
const DOWN = 2; // direction index within a 4-row animation block: up=0,left=1,down=2,right=3

// Shared base look (everything except vest color, weapon, hair, hat).
const COMMON =
  "sex=male&body=Body_Color_light&head=Human_Male_light&expression=Neutral_light" +
  "&legs=Pants_black&shoes=Sandals_blue";

// Row offsets copied from the generator's own
// sources/state/constants.ts ANIMATION_CONFIGS (block-start row, before
// adding the direction offset). Keep in sync if the generator's layout
// changes — there is no API to read this back at runtime.
const BLOCK = { spellcast: 0, thrust: 4, walk: 8, slash: 12, shoot: 16, hurt: 20, idle: 22 };

// One look per role. `attack` names which animation block carries that
// role's basic-attack silhouette; `cast` is deliberately the same
// `spellcast` row for every role (a universal "used an ability" pose,
// independent of the weapon prop) rather than role-specific.
const ROLES = [
  { role: "top", weapon: "Spear_iron", hair: "Messy1_black", hat: null,
    attack: "thrust", attackCols: [0, 2, 4, 6] },
  { role: "jungle", weapon: "Dagger_dagger", hair: "Cowlick_black", hat: "Hood_black",
    attack: "slash", attackCols: [0, 1, 3, 5] },
  { role: "mid", weapon: "Simple_staff_simple", hair: "Wavy_black", hat: null,
    attack: "thrust", attackCols: [0, 2, 4, 6] },
  { role: "carry", weapon: "Normal_iron", hair: "Ponytail2_black", hat: null,
    attack: "shoot", attackCols: [0, 4, 8, 12] },
  { role: "support", weapon: "Simple_staff_simple", hair: "Plain_black", hat: "Formal_Bowler_Hat_tan",
    attack: "thrust", attackCols: [0, 2, 4, 6] },
];
const COLORS = ["blue", "red"];

// Output sheet layout — must match data/animation.json's "sheet" block
// (frame_px/cols/rows) exactly, or the two will disagree about where a pose
// lives. game/main.gd's --selftest hard-asserts every anim_state the game
// can ever assign (living or dying) has a real sheet row, so unlike an
// earlier version of this script, neither "die" nor "recall" gets to be a
// fallback — the generator has no dedicated pose for either, so both reuse
// frames from an animation it does have: "die" takes hurt's later,
// more-collapsed columns (a different selection than the "hurt" row itself
// uses, so the two don't look identical), "recall" reuses idle verbatim
// (the separate recall ring VFX in map_view.gd is what actually reads as
// "channeling" — the body pose underneath was already going to be idle-like).
const ROWS = ["idle", "run", "attack", "cast", "hurt", "die", "recall"];

function findChromePath() {
  if (process.env.CHROME_PATH) return process.env.CHROME_PATH;
  const cacheRoot = path.join(
    process.env.HOME,
    "Library/Caches/ms-playwright",
  );
  if (!fs.existsSync(cacheRoot)) return null;
  const dir = fs.readdirSync(cacheRoot).find((d) => d.startsWith("chromium-") && !d.includes("headless"));
  if (!dir) return null;
  return path.join(
    cacheRoot,
    dir,
    "chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
  );
}

async function main() {
  const execPath = findChromePath();
  if (!execPath || !fs.existsSync(execPath)) {
    console.error(
      "ERROR: no Chromium found. Set CHROME_PATH, or `npx playwright install chromium`.",
    );
    process.exit(1);
  }
  fs.mkdirSync(OUT_DIR, { recursive: true });

  const browser = await chromium.launch({ executablePath: execPath, headless: true });
  const page = await browser.newPage({ viewport: { width: 1400, height: 1000 } });

  // Keyed by asset path (the credits export's own per-block identifier, e.g.
  // "weapon/sword/dagger/walk/dagger.png") so the several pieces shared by
  // every look (body/head/face/pants/sandals) collapse to one entry instead
  // of being repeated 10 times.
  const creditsByAsset = new Map();

  for (const color of COLORS) {
    for (const r of ROLES) {
      let hash = `${COMMON}&vest=Vest_open_${color}&weapon=${r.weapon}&hair=${r.hair}`;
      if (r.hat) hash += `&hat=${r.hat}`;
      await page.goto(`${GENERATOR_URL}#${hash}`, { waitUntil: "networkidle", timeout: 30000 });
      await page.waitForTimeout(900);

      // Sanity check: every requested item actually parsed and landed in
      // "Current Selections" (the exact per-item gotcha this whole approach
      // exists to catch before it ships silently broken).
      const selected = await page.evaluate(() =>
        Array.from(document.querySelectorAll(".tags .tag span:first-child")).map((e) => e.textContent),
      );
      console.log(`${color}/${r.role}:`, selected.join(" | "));

      const [download] = await Promise.all([
        page.waitForEvent("download"),
        page.click('button:has-text("Credits (TXT)")'),
      ]);
      const creditsText = fs.readFileSync(await download.path(), "utf8");
      for (const block of creditsText.split(/\n\n+/)) {
        if (!block.trim()) continue;
        const assetKey = block.split("\n")[0].trim();
        if (!creditsByAsset.has(assetKey)) creditsByAsset.set(assetKey, block.trim());
      }

      const rowSpec = {
        idle: { row: BLOCK.idle + DOWN, cols: [0, 1, 0, 1] },
        run: { row: BLOCK.walk + DOWN, cols: [1, 3, 5, 7] },
        attack: { row: BLOCK[r.attack] + DOWN, cols: r.attackCols },
        cast: { row: BLOCK.spellcast + DOWN, cols: [0, 2, 4, 6] },
        hurt: { row: BLOCK.hurt, cols: [0, 2, 4, 5] }, // hurt has no per-direction rows
        die: { row: BLOCK.hurt, cols: [3, 4, 5, 5] }, // later/more-collapsed hurt frames, held
        recall: { row: BLOCK.idle + DOWN, cols: [0, 1, 0, 1] }, // = idle, see ROWS comment above
      };

      const dataUrl = await page.evaluate(
        ({ rowSpec, ROWS, FRAME }) => {
          const src = window.canvasRenderer.getCanvas().value;
          const out = document.createElement("canvas");
          out.width = FRAME * 4;
          out.height = FRAME * ROWS.length;
          const ctx = out.getContext("2d");
          ROWS.forEach((name, rowIdx) => {
            const spec = rowSpec[name];
            spec.cols.forEach((col, colIdx) => {
              ctx.drawImage(
                src,
                col * FRAME, spec.row * FRAME, FRAME, FRAME,
                colIdx * FRAME, rowIdx * FRAME, FRAME, FRAME,
              );
            });
          });
          return out.toDataURL("image/png");
        },
        { rowSpec, ROWS, FRAME },
      );

      const outPath = path.join(OUT_DIR, `lpc_${r.role}_${color}.png`);
      fs.writeFileSync(outPath, Buffer.from(dataUrl.split(",")[1], "base64"));
      console.log("  wrote", outPath);
    }
  }

  await browser.close();

  const noticePath = path.join(OUT_DIR, "LPC_NOTICE.txt");
  const header = `LPC-generated character art — attribution
==========================================

game/assets/characters/lpc_<role>_<blue|red>.png were generated via the
Universal LPC Spritesheet Character Generator:
${GENERATOR_URL}

The site's own credit page (${GENERATOR_URL}#credits-section) asks that reuse
"credit the authors" per the "Detailed attribution instructions"
(https://github.com/liberatedpixelcup/Universal-LPC-Spritesheet-Character-Generator/blob/master/README.md).
This file is that credit: the exact per-asset "Credits (TXT)" export the
generator itself produces for these selections, merged below with
duplicates (assets shared across every role/color) collapsed to one entry.
Regenerated by this script — do not hand-edit; change the ROLES table above
and re-run instead.

Not CC0 as a whole — most pieces are CC-BY-SA-3.0 and/or GPL-3.0 and/or
OGA-BY-3.0 (attribution required); a few individual pieces are genuinely
CC0 (marked per-entry below). If any of this ships beyond the PoC
placeholder stage, carry this file forward alongside the assets.

------------------------------------------------------------------------

`;
  const sortedBlocks = [...creditsByAsset.keys()].sort().map((k) => creditsByAsset.get(k));
  fs.writeFileSync(noticePath, header + sortedBlocks.join("\n\n") + "\n");
  console.log("wrote", noticePath, `(${creditsByAsset.size} unique assets)`);

  console.log("done");
}

main();
