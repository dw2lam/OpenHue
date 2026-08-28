# Round 2 — owner feedback and assignments (read DESIGN.md + HERO-SPEC.md first)

The v1 page is live at https://open-hue.vercel.app. The owner's verdict: "The website's good", but:

1. **More relevant screenshots and examples.** He wants a **demo macOS environment** — not a real one,
   one that *looks* like one — showing the app and **how it works in the menu bar**, visually.
2. **Screenshots should look cleaner: rounded, with the soft shadow you get from ⌘⇧4-Space** window
   captures. → DONE at the capture level: `shots-raw2/` now holds every view captured WITH the native
   macOS shadow (transparent margins, rounded corners), bulbs at warm white 2695 K · 95% instead of red 1%.
   Use these; `shots-raw/` (no shadow, red 1%) is obsolete.
3. **Too many words, too little colour.** Cut copy hard — headline + one line, mono tags instead of
   paragraphs. Bring in colour as *light*: Hue-coloured ambient glows behind compositions (tokens
   `--hue-warm --hue-candle --hue-sunset --hue-magenta --hue-blue --hue-cyan --hue-mint --hue-red
   --hue-police-blue` + the `.glow` utility in index.css, set `--glow` per composition), coloured scene
   swatches, tinted wallpaper, the light itself. Chrome stays monochrome/sharp; light is colourful.
4. **Missing the basic descriptor** of what it is. Lead with it, plainly: *the Hue Bluetooth app, rebuilt
   for your Mac — same bulbs, same scenes and effects, now local and open source.* (Bridge-free, no
   cloud, no phone are supporting points, not the headline.)
5. **Motion inside the screenshots.** "The timer is going off, then the real timer on the website should
   go down" — captures must feel alive: live countdowns, thumbs that move, markers that orbit, toggles
   that flip, dots that recolour, a Police effect that actually strobes. Overlay live HTML/SVG replicas
   on top of the real captures at the exact spot (position in % of the image box; the shadowed PNGs
   have transparent margins — measure the window rect inside each PNG), or rebuild the control as a
   faithful macOS-styled replica.

## Files in shots-raw2 (all @2x with shadow)
all-lights-white (2584×1784: white tab, CT slider 2695 K, scenes row, per-light rows), all-lights-color
(colour wheel), all-lights-effects (effects grid + From this Mac → Police), light-right / light-right-color /
light-right-effects, scenes, timer, schedules, diagnostics, settings-general/-schedules/-wake-mac/-data,
menubar (772×674 popover), menubar-context (region of the real menu bar with the bulb item),
add-light-sheet (sheet only), add-light-region (opaque region, sheet over window).
Conversion: `cwebp -q 84 -alpha_q 100 -resize 2000 0` keeping alpha; trim transparent margins only if
you must (the shadow IS the point — keep at least the full shadow extent).

## Assignments (disjoint files — never touch another agent's files)
- **MacDemo agent** — NEW `src/components/MacDemo.tsx` + `macdemo.css` (section `id="desktop"`,
  already wired into App.tsx between Story and Showcase). Owns nothing else.
- **Showcase agent** — `Story.tsx/story.css`, `Showcase.tsx/showcase.css`, `public/shots/*`, `src/shots.ts`, `public/og.png`.
  NOTE `src/shots.ts` is imported by Playground/Pairing/Download? — check with grep before changing keys;
  keep existing keys working (dimensions may change) or add new keys.
- **Copy agent** — `Playground.tsx/playground.css`, `Pairing.tsx/pairing.css`, `Download.tsx/download.css`, `Footer.tsx/footer.css`.
- Orchestrator — index.css tokens (`--hue-*`, `.glow`), App.tsx, hooks, deploy.

Verification as in DESIGN.md (own Chrome tab on http://localhost:5180, desktop + phone, console clean,
`npx tsc -b`). Headless fallback if the MCP window misbehaves: `node scratchpad/qa.mjs` pattern —
puppeteer-core is installed, Chrome for Testing at ~/.cache/puppeteer/chrome/mac_arm-134.0.6998.35.
