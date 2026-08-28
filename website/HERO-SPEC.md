# Hero spec (owner-supplied, follow precisely) — with OpenHue content substitutions

The owner pasted the spec below (originally written for a product called “ECHOID”). Recreate it
**exactly** in design terms — layout, tokens, fonts, sizes, scrim, nav, mobile menu, panel, footer,
motion, a11y — and substitute only the CONTENT as listed here. Media URLs stay verbatim.

## Content substitutions (OpenHue)
- Document title is already set in index.html — do not touch index.html.
- Nav logo text: `OPENHUE` (same Sora 200 treatment). href="#top" (give the hero id="top").
- Desktop nav links (in order): `Overview` → `#story`, `Features` → `#features`, `Pairing` → `#pairing`,
  `GitHub` → `https://github.com/dw2lam/OpenHue` (target=_blank rel=noopener). Same four in the mobile menu.
- Desktop CTA (was “Join up”): `Download` → `#download`. Mobile menu CTA: same.
- Chip (was “[ Voice entry ]”): `[ Bluetooth · No Bridge ]` (uppercase via CSS → “[ BLUETOOTH · NO BRIDGE ]”).
- H1: `OPENHUE`.
- Tagline (was “Your voice ID to the E network.”): `Your Hue bulbs, straight from your Mac.`
- Form → a download panel with the SAME visual rhythm and sizes:
  a) In place of the email input: a read-only readout row styled exactly like the input (transparent,
     bottom border 1px --line-strong, Sora 300, same padding) showing
     `OpenHue.dmg · v{version} · macOS 14 or later` — version from `useLatestRelease()` in
     `src/hooks/useLatestRelease.ts` (also gives dmgUrl / zipUrl / releaseUrl / dmgBytes; `formatBytes`).
     Use a `<div role="status">`, not an input. Keep the visually-hidden label pattern as a `<span class="sr-only">`.
  b) Ghost button (was “Proceed using email”): `View source on GitHub` → anchor to the repo (new tab).
  c) Solid button (was “Access”): `Download for macOS` → anchor to `dmgUrl` (download).
  Keep it a real `<form>`-free block, or a form with preventDefault — either is fine; sizes/gaps as spec.
- Referral link (was “I've got an invite key”): `Already paired with the Hue app?` → `#pairing`.
- Legal footer copy: `OpenHue is free and open source. It is not affiliated with Signify or Philips Hue.`
  with `open source` linking to the GitHub repo and `Philips Hue` linking to https://www.philips-hue.com
  (both white underlined links exactly as the spec's Privacy Notice / Service Contract links).
- Everything else (video, poster, fonts, tokens, scrim, hamburger, mobile menu, reduced motion,
  short-height compress, focus styles) exactly as written below.

Implementation: React function component `Hero` (default export, no props) in `src/components/Hero.tsx`
+ `src/components/hero.css` (import it). Global tokens already exist in `src/index.css` (--bg, --text,
--text-dim, --text-dimmer, --line, --line-strong, --fill-ghost, --fill-solid, --gutter, --ease-premium,
--font-display, --font-mono, .sr-only) — reuse them; define hero-only rules under `.hero` prefixes.
Fonts are loaded from index.html already (Sora 200/300/400 + JetBrains Mono 300/400/500).

────────────────────────────────────────────────────────────────────────────
ORIGINAL SPEC (verbatim)
────────────────────────────────────────────────────────────────────────────
Recreate this exact full-viewport dark hero landing page for “ECHOID” — a voice-identity product for the E network. Match every detail below precisely. Do not invent extra sections, cards, stats, or decorative overlays. Desktop composition: full-bleed cinematic background video on the left/center with a right-aligned signup panel; black negative space on the left; UI pinned top (nav), right (form), and bottom (legal).

PAGE META
- Document title: ECHOID — Your voice ID to the E network
- Lang: en
- Pure black page background (#000)
- Antialiased text
- Single full-viewport section only (no other page sections)

EXACT MEDIA URLS (CloudFront — use these verbatim)
Background video (MP4):
https://d8j0ntlcm91z4.cloudfront.net/user_38xzZboKViGWJOttwIXH07lWA1P/hf_20260806_133255_956f653f-5d80-4b06-abd5-0f46c98b60fa.mp4
Poster / fallback still (PNG):
https://d8j0ntlcm91z4.cloudfront.net/user_38xzZboKViGWJOttwIXH07lWA1P/hf_20260806_132328_5f9029c8-218f-4489-82b6-29ff2849920e.png
Video attributes: autoPlay, muted, loop, playsInline, preload="auto"
Video CSS: width/height 100%, object-fit: cover, object-position: center
Media layer: position absolute, inset 0, z-index -1, black background behind video
Preconnect to: https://d8j0ntlcm91z4.cloudfront.net
Video content (for reference): dark cinematic AI/surreal face sequence — abstract metallic/glass facial forms, cool dark palette, motion graphic identity vibe. Full-bleed edge-to-edge; never inset, never in a card.

FONTS (exact Google Fonts)
family=Sora:wght@200;300;400  family=JetBrains+Mono:wght@300;400;500  display=swap
CSS stacks:
--font-display: "Sora", "Helvetica Neue", Helvetica, Arial, sans-serif
--font-mono: "JetBrains Mono", ui-monospace, "SF Mono", "Cascadia Mono", Menlo, Consolas, monospace
Usage map:
- Sora 200: nav logo, hero H1
- Sora 300: email input, legal footer text
- JetBrains Mono 400: nav links, CTA, chip, buttons, referral link, mobile menu links/CTA
- JetBrains Mono 300: tagline

DESIGN TOKENS
--bg: #000000  --text: #ffffff  --text-dim: rgba(255,255,255,0.62)  --text-dimmer: rgba(255,255,255,0.42)
--line: rgba(255,255,255,0.14)  --line-strong: rgba(255,255,255,0.26)  --fill-ghost: rgba(255,255,255,0.05)
--fill-solid: rgba(255,255,255,0.10)  --gutter: clamp(20px, 5vw, 100px)  --ease-premium: cubic-bezier(0.16, 1, 0.3, 1)

LAYOUT SHELL
.hero: position relative, width 100%; height: 100vh AND 100svh; min-height: 640px (if max-height ≤640px, min-height becomes 100svh); overflow hidden; CSS grid: grid-template-rows: auto 1fr auto; isolation: isolate
Row 1 = navbar; Row 2 = right-aligned form body (flex end / center on mobile); Row 3 = legal footer

SCRIM (dual gradient overlay on video)
Desktop (≥721px) — two stacked linear-gradients:
1) to right: transparent 0% → transparent 45% → rgba(0,0,0,0.45) 72% → rgba(0,0,0,0.72) 100%
2) to bottom: rgba(0,0,0,0.55) 0% → transparent 22% → transparent 78% → rgba(0,0,0,0.65) 100%
Mobile (≤720px) — single bottom gradient: rgba(0,0,0,0.6) 0% → rgba(0,0,0,0.25) 30% → rgba(0,0,0,0.75) 100%

NAVBAR (top)
Flex space-between, align center, gap 32px. Padding: clamp(20px, 2.4vw, 34px) horizontal gutter; respect safe-area insets
LEFT — Logo link: Sora 200; font-size clamp(20px, 1.75vw, 30px); letter-spacing 0.16em; white, no underline, line-height 1
RIGHT — nav cluster (gap clamp(24px, 3.2vw, 62px)):
A) Desktop links (≥901px): JetBrains Mono 400; font-size clamp(11px, 0.78vw, 14px); letter-spacing 0.18em; uppercase; white; hover → --text-dim; transition color 0.25s ease; link gap clamp(20px, 2.8vw, 56px)
B) Desktop CTA: same mono type as links; padding clamp(12px,1vw,17px) clamp(20px,1.8vw,32px); border 1px solid --line-strong; hover: background --fill-ghost, border-color rgba(255,255,255,0.5); transition background+border 0.25s ease
C) Mobile hamburger (≤900px only; desktop links+CTA hidden): 44×44 hit target, 3 bars 22px wide × 1px tall, white; bars at top 16/22/28px, centered with translateX(-50%); Active (X morph): bar1 rotate(45deg) to top 22px; bar2 opacity 0 + scaleX(0); bar3 rotate(-45deg) to top 22px; transition: transform 0.45s --ease-premium, opacity 0.25s ease

MOBILE MENU OVERLAY
Fixed fullscreen, z-index 50 (nav is 60). Background rgba(4,4,6,0.94); backdrop-filter blur(28px) saturate(140%)
Closed: clip-path circle(3% at calc(100% - 42px) 42px), opacity 0, pointer-events none
Open: clip-path circle(150% at same origin), opacity 1, pointer-events auto
Transition: clip-path 0.7s --ease-premium, opacity 0.45s ease
Centered column of uppercase mono links then bordered CTA. Link size clamp(20px, 5.5vw, 28px), letter-spacing 0.14em. CTA: letter-spacing 0.22em, padding 16px 40px, border 1px --line-strong
Stagger entrance: each item starts opacity 0 + translateY(16px); when open → opacity 1 + translateY(0). Delay calc(180ms + var(--i) * 70ms), i = 0..3 for links, i=4 for CTA. Transition on items: opacity 0.4s ease, transform 0.5s --ease-premium
Escape closes; click backdrop closes; body.menu-open { overflow:hidden }; restore focus; auto-close at ≥901px

RIGHT PANEL
hero__body: flex align center, justify flex-end (center on ≤720px), horizontal gutter, min-height 0, overflow-y auto
.panel desktop: width min(34vw, 620px), min-width 380px, column flex-start. ≤1100px: width min(70vw, 520px), min-width 0. ≤720px: width 100%, stretch; chip stays flex-start
1) CHIP: JetBrains Mono 400; font-size clamp(11px, 0.72vw, 14px); letter-spacing 0.2em; background rgba(255,255,255,0.09); padding clamp(9px,0.8vw,14px) clamp(14px,1.1vw,20px); line-height 1; NO rounded pill — sharp rectangle
2) H1: Sora 200; font-size clamp(54px, 6.2vw, 118px) [≤380px: clamp(44px,15vw,64px)]; letter-spacing 0.03em; line-height 0.95; margin-top clamp(28px, 3vw, 52px). Brand-first: dominant hero word; nothing larger
3) TAGLINE: JetBrains Mono 300, uppercase via CSS; font-size clamp(11px, 0.94vw, 17px); letter-spacing 0.14em; color --text-dim; margin-top clamp(14px, 1.4vw, 24px); line-height 1.4
4) FORM: margin-top clamp(38px, 4.6vw, 82px); column gap clamp(14px, 1.3vw, 22px); width 100%
   a) Email field: visually-hidden label; transparent input, no side borders, bottom border only 1px --line-strong; border-radius 0; padding 0 2px clamp(12px,1.1vw,18px); Sora 300, clamp(16px,0.95vw,18px), white text; placeholder color --text-dim; focus: bottom border rgba(255,255,255,0.85); placeholder → --text-dimmer; transition border-color 0.25s ease
   b) Button .btn--ghost: full width, border-radius 0, no border; padding clamp(17px,1.6vw,27px) 20px; JetBrains Mono 400, uppercase, letter-spacing 0.22em; font-size clamp(11px,0.78vw,14px); background --fill-ghost, color --text-dimmer; hover: bg rgba(255,255,255,0.09), color white
   c) Button .btn--solid: same type/padding; background --fill-solid, color white; hover: bg rgba(255,255,255,0.17)
5) Referral link (centered under form): JetBrains Mono 400, uppercase via CSS; font-size clamp(11px, 0.74vw, 14px); letter-spacing 0.18em; margin-top clamp(26px, 2.6vw, 46px); align-self center; hover: --text-dim + underline, underline-offset 4px

LEGAL FOOTER
border-top 1px solid --line; padding clamp(18px,1.7vw,30px) gutter; safe-area bottom; text-align center
Sora 300, clamp(12px,0.82vw,16px), color --text-dim, line-height 1.5; the two links are white underlined (underline-offset 3px, thickness 1px); link hover → --text-dim

FOCUS / A11Y
Focus-visible outline: 1px solid rgba(255,255,255,0.7), offset 3px on buttons, CTA, toggle, referral, input, mobile links
Mobile menu: role=dialog, aria-modal, aria-label="Site menu", aria-hidden when closed, inert when closed
Toggle: aria-expanded, aria-controls="mobileMenu", aria-label Open/Close menu

REDUCED MOTION
prefers-reduced-motion: reduce → hide video; show poster as cover background-image on .hero__media; crush all animation/transition durations to 0.01ms

SHORT-HEIGHT COMPRESS (max-height: 640px)
Tighter nav padding; smaller H1 (clamp(36px,7vw,64px)); smaller form margins/gaps; thinner buttons; smaller legal (11px); tighter mobile menu

MOTION SUMMARY
1. Background video continuous loop (primary presence)
2. Hover color/background transitions at 0.25s ease on links, CTAs, buttons, input border
3. Hamburger ↔ X morph 0.45s premium ease
4. Mobile menu circular clip-path expand 0.7s premium ease + opacity 0.45s
5. Mobile menu items staggered fade/slide-up with 70ms index delay
NO entrance animation on desktop panel. NO floating badges over video. NO cards, pills, glow, purple, or multi-shadow chrome. Sharp rects only. Aesthetic: black / white / translucent white glass, terminal-mono UI over cinematic face video.

STACK: React + plain CSS. Custom properties as above. Page hero only (the rest of this site continues below it — that is fine; the hero itself stays a single full-viewport section).

────────────────────────────────────────────────────────────────────────────
Hero video (added 2026-08-28)
────────────────────────────────────────────────────────────────────────────
The CloudFront MP4's ring sits ~31 % from the left and its first/last frames don't match, so the
site serves `public/hero.mp4`: the source shifted 360 px right (ring centred), its left 200–660 px faded to black with geq so the pad has no seam, and rendered as a bounce
(forward + reverse, duplicate seam frames trimmed) → 20 s seamless loop, 1.8 MB. Poster = first frame.
Rebuild:
  ffmpeg -i hero-src.mp4 -filter_complex "[0:v]pad=w=iw+360:h=ih:x=360:y=0:color=black,crop=1920:1080:0:0,geq=lum='(lum(X,Y)-16)*clip((X-200)/460,0,1)+16':cb='(cb(X,Y)-128)*clip((X*2-200)/460,0,1)+128':cr='(cr(X,Y)-128)*clip((X*2-200)/460,0,1)+128',split[a][b];[b]reverse,trim=start_frame=1:end_frame=240,setpts=PTS-STARTPTS[r];[a][r]concat=n=2:v=1,format=yuv420p[v]" -map "[v]" -an -c:v libx264 -preset slow -crf 25 -g 48 -movflags +faststart -r 24 public/hero.mp4
  ffmpeg -i public/hero.mp4 -frames:v 1 -q:v 3 public/hero-poster.jpg
