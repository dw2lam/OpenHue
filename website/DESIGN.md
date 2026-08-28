# OpenHue site — design brief (shared by all section agents)

Site for **OpenHue**: a native macOS app (Swift / SwiftUI / CoreBluetooth, macOS 14+) that controls
Philips Hue **Bluetooth** bulbs directly over BLE — **no Hue Bridge, no cloud, no phone**. Repo:
https://github.com/dw2lam/OpenHue (latest release v0.1.0: OpenHue.dmg 4.1 MB, OpenHue.zip).
Sibling sites for tone: notchtune.davidlam.online, dotstudio.davidlam.online. This one is
**openhue.davidlam.online**. Read `../README.md` for every product fact (features, limits, pairing, protocol).

## The look (extends the hero — read HERO-SPEC.md first)
Black / white / translucent-white glass. Terminal-mono UI labels over cinematic content. **Sharp
rectangles only** (no border-radius on our own chrome; screenshots keep their native macOS corners).
The *only* colour on the page is the light itself: Hue glows, the colour wheel, the CT gradient,
scene swatches inside screenshots, the interactive bulbs. Everything we draw is monochrome.

Tokens live in `src/index.css` (do NOT edit that file — it is owned by the orchestrator):
`--bg --text --text-dim --text-dimmer --line --line-strong --fill-ghost --fill-solid --gutter
--ease-premium --font-display (Sora 200/300/400) --font-mono (JetBrains Mono 300/400/500)
--section-pad --content-max --fs-* --shadow-deep`, plus classes `.section .section__inner .eyebrow
.display .h2 .h3 .body .mono .btn .btn--ghost .btn--solid .btn--outline .glass .rule .reveal .sr-only`.

Type usage: Sora 200 for display headings (huge, letter-spacing 0.01em, line-height 1.0); Sora 300
for body; JetBrains Mono 400 uppercase 0.18–0.22em tracking for labels/eyebrows/buttons/captions;
Mono 300 for taglines. Eyebrows read like `[ 01 — OVERVIEW ]`. Copy is short, confident, specific.

## Make it 3D, stacked, fluid, alive (the owner's explicit ask)
Take the hero's cinematic feel through the whole page. Expected devices:
- Screenshots floating in **perspective** (rotateX/rotateY/translateZ), **stacked decks** of windows
  that fan/shuffle as you scroll, sticky scrollytelling (pinned text on one side, stage on the other),
  parallax layers at different speeds, cursor-tilt on hover, hairline grids/rules that draw in.
- Use **GSAP + ScrollTrigger** (`import { gsap, ScrollTrigger, reducedMotion } from '../lib/gsap'`),
  scrubbed to scroll (`scrub: true` / small numbers) so motion is fluid, never jumpy. Or CSS
  transitions with `--ease-premium`. Kill your ScrollTriggers on unmount.
- Depth: `var(--shadow-deep)` + 1px `var(--line)` outline around screenshot frames; a soft Hue-coloured
  ambient glow behind a screenshot is allowed when it reads as light from the app (keep it subtle).
- Everything must degrade under `prefers-reduced-motion` (static, visible, no pins) and on mobile
  (≤720px: single column, no pinned sections taller than the viewport, transforms toned down).
- 60fps: animate only transform/opacity, `will-change` sparingly, lazy-load images (`loading="lazy"`,
  `decoding="async"`), no layout thrash in scroll handlers.

## Screenshots
Raw window captures (2360×1560 @2x, transparent rounded corners, no shadow) are in `shots-raw/`:
all-lights-white / all-lights-color / all-lights-effects (+ *-scrolled variants showing Scenes chips
and per-light rows), light-right / light-right-white / light-right-effects, scenes, timer, schedules,
diagnostics, settings-general / settings-schedules / settings-wake-mac / settings-data (920×1236),
menubar (popover 680×574), add-light-region (sheet over the window, opaque). Note: the bulbs were
red at 1% when captured — crop out the brightness slider when it would read badly, and lean on the
colour wheel / CT gradient / dial / effects grid / scene cards / menu bar, which all look great.
Only the **Showcase agent** writes to `public/shots/` and `src/shots.ts` (manifest of processed
assets: path, width, height, alt). Convert with `cwebp -q 84` (keep alpha), max 2000px wide, plus
tight detail crops (PIL is available in python3). Other agents may reference files listed in
`src/shots.ts` once they exist; never write there yourselves.

## File ownership (parallel agents — never edit another agent's files)
- Orchestrator: index.html, src/index.css, src/main.tsx, src/App.tsx, src/hooks/*, src/lib/*, vercel.json
- Hero agent: src/components/Hero.tsx, src/components/hero.css
- Showcase agent: src/components/Story.tsx + story.css, Showcase.tsx + showcase.css, public/shots/*, src/shots.ts
- Playground agent: src/components/Playground.tsx + playground.css, Pairing.tsx + pairing.css,
  Download.tsx + download.css, Footer.tsx + footer.css
Each component is default-exported and takes no props. Section ids (nav targets): `#story`,
`#features` (Showcase), `#playground`, `#pairing`, `#download`. Keep your CSS scoped with a unique
class prefix (`.hero-`, `.story-`, `.sc-`, `.pg-`, `.pair-`, `.dl-`, `.foot-`) to avoid collisions.

## Verify your own work
A Vite dev server is running at **http://localhost:5180** (do not start another). Load the Chrome
tools in ONE ToolSearch call, create your OWN tab (`tabs_create_mcp`), work only in it, close it at
the end. Look at your section at desktop (~1440 wide) and mobile (~390 wide) widths (use
`resize_window`), scroll through it, check the console for errors, and iterate until it is genuinely
good before reporting. `npx tsc -b` must pass (strict, noUnusedLocals). Screenshots you take of the
page are for you; report a concise summary of what you built and any caveats.
