# openhue.davidlam.online

Landing site for OpenHue — React 18 + Vite + TypeScript, plain CSS, GSAP for scroll motion.

## Deploy

Deploys are driven by **git**: the Vercel project `open-hue` is connected to `dw2lam/OpenHue`
with Root Directory `website`. Pushing to `main` builds and publishes production at
https://openhue.davidlam.online; other branches get preview URLs. Don't deploy with the CLI.

## Develop

```sh
npm install
npm run dev        # http://localhost:5173
npm run build      # tsc -b + vite build → dist/
```

`src/index.css` holds the design tokens; `--s` there scales every length site-wide (phones stay at 1).
`HERO-SPEC.md` is the hero brief (and the ffmpeg recipe for the bounce loop), `DESIGN.md` /
`ROUND2.md` are the section briefs. Raw window captures live in `shots-raw2/` (with the native macOS
shadow); processed assets in `public/shots/` with the manifest in `src/shots.ts`.
