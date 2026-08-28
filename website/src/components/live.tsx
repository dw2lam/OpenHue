/**
 * Live overlays for the screenshots — replicas of the app's controls drawn at the exact spot on top of
 * the real captures, driven by shared wall clocks so every dial, readout and toggle on the page agrees.
 * Used by Story and Showcase only. Positions come from `Shot.box` (source-canvas geometry, see shots.ts).
 */
import { useEffect, useRef, type CSSProperties, type ReactNode } from 'react';
import { gsap, reducedMotion } from '../lib/gsap';
import type { Shot } from '../shots';
import './live.css';

/* ── Geometry ────────────────────────────────────────────────── */
export type Rect = { x: number; y: number; w: number; h: number };
export const rect = (x: number, y: number, w: number, h: number): Rect => ({ x, y, w, h });
export const circ = (cx: number, cy: number, r: number): Rect => ({ x: cx - r, y: cy - r, w: 2 * r, h: 2 * r });

/** Absolute position of a source-canvas rect inside a Frame, in % of the image box. */
export function place(s: Shot, r: Rect): CSSProperties {
  const [x0, y0, x1, y1] = s.box;
  const W = x1 - x0, H = y1 - y0;
  return {
    left: `${((r.x - x0) / W) * 100}%`,
    top: `${((r.y - y0) / H) * 100}%`,
    width: `${(r.w / W) * 100}%`,
    height: `${(r.h / H) * 100}%`,
  };
}
/** `px` source pixels as container-query width units of the frame — scales with the capture. */
export const cq = (s: Shot, px: number) => `${(px / (s.box[2] - s.box[0])) * 100}cqw`;

/** Controls measured in the 2584×1784 window canvas. */
export const WIN = {
  dial: circ(1106, 753, 250),
  dialBadge: rect(1950, 421, 250, 36),
  ctTrack: rect(850, 690, 1360, 50),
  ctReadout: rect(1430, 752, 200, 40),
  headerSub: rect(924, 424, 230, 34),
  wheel: circ(1530, 958, 260),
  sidebarDots: [circ(544, 314, 13), circ(544, 378, 13)],
  rowDots: [circ(890, 1280, 17), circ(890, 1354, 17)],
  rowToggles: [rect(2134, 1260, 88, 40), rect(2134, 1334, 88, 40)],
  policeTile: rect(842, 1030, 216, 122),
  sceneCards: [
    ...[630, 996, 1361, 1727, 2092].map((x) => rect(x, 280, 338, 216)),
    ...[630, 996, 1361, 1727, 2092].map((x) => rect(x, 524, 338, 216)),
    rect(630, 768, 338, 216),
  ],
  chips: [[814, 993], [1017, 1219], [1243, 1462], [1486, 1664], [1688, 1859], [1883, 2133]].map(([a, b]) => rect(a, 1094, b - a, 56)),
  schedToggles: [568, 710, 948, 1090].map((y) => rect(620, y, 88, 40)),
  schedStatus: rect(730, 781, 520, 30),
  rssi: [rect(812, 545, 184, 34), rect(812, 1512, 184, 34)], // text starts at 836 → pad 24
  greenDots: [circ(654, 562, 9), circ(654, 1529, 9)],
  fadeBar: rect(888, 452, 1209, 16),
} as const;
/** Menu-bar popover canvas (772×674). */
export const MENU = {
  timerText: rect(508, 186, 58, 28),
  toggles: [rect(610, 120, 88, 40), rect(610, 262, 88, 40), rect(610, 314, 88, 40)],
  dots: [circ(126, 282, 17), circ(126, 334, 17)],
} as const;
/** Settings → Wake Mac canvas (1144×1440). */
export const WAKE = { toggle: rect(899, 364, 72, 34) } as const;

/* ── Shared clocks (ms since load) ───────────────────────────── */
const T0 = typeof performance !== 'undefined' ? performance.now() : 0;
export const now = () => performance.now() - T0;

const START = 246, TOTAL = 300, HOLD = 2; // the capture shows 4:06 left of a 5-minute Sleep timer
/** The site's one real countdown: starts where the capture left off, hits 0:00, re-arms at 5:00. */
export function countdown(t: number) {
  let e = t / 1000;
  if (e < START) return { rem: START - e, total: TOTAL };
  e = (e - START) % (TOTAL + HOLD);
  return { rem: e < HOLD ? 0 : TOTAL - (e - HOLD), total: TOTAL };
}
export const mmss = (sec: number) => `${Math.floor(sec / 60)}:${String(Math.floor(sec % 60)).padStart(2, '0')}`;
export function offAt(remSec: number) {
  const d = new Date(Date.now() + remSec * 1000);
  return `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')}`;
}
/** Colour temperature drifting between 2695 K (the capture) and ~3850 K. */
export const kelvin = (t: number) => 2695 + 1150 * (0.5 - 0.5 * Math.cos((2 * Math.PI * t) / 30000));
/** Colour-wheel marker: angle (deg, clockwise from east) and radius fraction; starts at the captured spot. */
export function hue(t: number) {
  const a = (38.2 + (360 * t) / 28000) % 360;
  const rf = 0.554 + 0.14 * Math.sin((2 * Math.PI * t) / 9000);
  return { a, rf, css: `hsl(${a.toFixed(1)} 100% ${(100 - 50 * rf).toFixed(1)}%)` };
}
export const rightOn = (t: number) => t % 9000 < 5800;
export const armed = (t: number) => t % 11000 >= 4500;
export const sceneIdx = (t: number) => Math.floor(t / 2600) % 11;
export function rssi(t: number, seed: number) {
  const q = Math.floor(t / 900);
  return -47 + Math.round(1.6 * Math.sin(q * 0.6 + seed) + 1.4 * Math.sin(q * 1.7 + seed * 2));
}
export const fadeFrac = (t: number) => 0.156 + (((t / 1000) % 90) / 90) * 0.844;

export const SCENES = [
  { n: 'Bright', glow: '#f2a65a' }, { n: 'Dimmed', glow: '#d8873f' }, { n: 'Nightlight', glow: '#ff9a3c' },
  { n: 'Relax', glow: '#f2a65a' }, { n: 'Read', glow: '#f3b172' }, { n: 'Concentrate', glow: '#ffe3c4' },
  { n: 'Energize', glow: '#dfe9ff' }, { n: 'Savanna Sunset', glow: '#ff5e62' }, { n: 'Tropical Twilight', glow: '#d84bff' },
  { n: 'Arctic Aurora', glow: '#35d0ff' }, { n: 'Spring Blossom', glow: '#ff7ab8' },
] as const;

/* ── One ticker for every overlay ────────────────────────────── */
type Fn = (t: number) => void;
const subs = new Set<Fn>();
let raf = 0;
function loop() {
  const t = now();
  subs.forEach((f) => f(t));
  raf = subs.size ? requestAnimationFrame(loop) : 0;
}
function subscribe(f: Fn) {
  subs.add(f);
  if (!raf) raf = requestAnimationFrame(loop);
  return () => {
    subs.delete(f);
    if (!subs.size && raf) { cancelAnimationFrame(raf); raf = 0; }
  };
}
/** Runs `fn` every frame while the element is near the viewport. Under reduced motion it runs once, at t = 0. */
function useLive<T extends HTMLElement>(fn: Fn) {
  const ref = useRef<T>(null);
  const fnRef = useRef(fn);
  fnRef.current = fn;
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    fnRef.current(0);
    if (reducedMotion()) return;
    const tick: Fn = (t) => fnRef.current(t);
    if (!('IntersectionObserver' in window)) return subscribe(tick);
    let off: (() => void) | null = null;
    const io = new IntersectionObserver(([en]) => {
      if (en.isIntersecting) { if (!off) off = subscribe(tick); }
      else if (off) { off(); off = null; }
    }, { rootMargin: '25% 0px' });
    io.observe(el);
    return () => { io.disconnect(); off?.(); };
  }, []);
  return ref;
}
/** Keeps CSS keyframe animations on late-mounted elements in phase with the rest of the page. */
function usePhase<T extends HTMLElement>(period: number) {
  const ref = useRef<T>(null);
  useEffect(() => {
    const el = ref.current;
    if (el) el.style.animationDelay = `${-(now() % period)}ms`;
  }, [period]);
  return ref;
}

/* ── Frame: the image box every overlay is positioned in ─────── */
export function Frame({ s, eager, className = '', style, children }: {
  s: Shot; eager?: boolean; className?: string; style?: CSSProperties; children?: ReactNode;
}) {
  return (
    <figure className={`lv-frame ${className}`} style={{ aspectRatio: `${s.width} / ${s.height}`, ...style }}>
      <img src={s.src} width={s.width} height={s.height} alt={s.alt} loading={eager ? 'eager' : 'lazy'} decoding="async" draggable={false} />
      {children}
    </figure>
  );
}

/* ── Text replica: a patch of the surface colour + live text ─── */
export function LiveText({ s, r, bg, color, size, weight = 400, align = 'left', pad = 0, text }: {
  s: Shot; r: Rect; bg: string; color: string; size: number; weight?: number; align?: 'left' | 'center' | 'right'; pad?: number; text: (t: number) => string;
}) {
  const last = useRef('');
  const ref = useLive<HTMLDivElement>((t) => {
    const v = text(t);
    if (v !== last.current && ref.current) { last.current = v; ref.current.textContent = v; }
  });
  return (
    <div
      ref={ref}
      className="lv lv-text"
      aria-hidden="true"
      style={{
        ...place(s, r), background: bg, color, fontSize: cq(s, size), fontWeight: weight,
        justifyContent: align === 'center' ? 'center' : align === 'right' ? 'flex-end' : 'flex-start',
        paddingLeft: cq(s, pad), paddingRight: cq(s, pad),
      }}
    />
  );
}

/* ── Timer dial (SVG replica; the ring drains for real) ──────── */
const C = 2 * Math.PI * 220;
const TICKS = Array.from({ length: 60 }, (_, i) => (
  <line key={i} x1="0" y1="-196" x2="0" y2={i % 5 === 0 ? '-178' : '-186'} strokeWidth={i % 5 === 0 ? 4 : 3} transform={`rotate(${i * 6})`} />
));
export function LiveDial({ s }: { s: Shot }) {
  const arc = useRef<SVGCircleElement>(null);
  const head = useRef<SVGTSpanElement>(null);
  const lastDigit = useRef<SVGTSpanElement>(null);
  const sub = useRef<SVGTextElement>(null);
  const lastSec = useRef(-1);
  const ref = useLive<HTMLDivElement>((t) => {
    const { rem, total } = countdown(t);
    if (arc.current) arc.current.style.strokeDashoffset = String(C * (1 - rem / total));
    const sec = Math.floor(rem);
    if (sec === lastSec.current) return;
    lastSec.current = sec;
    const str = mmss(sec);
    if (head.current) head.current.textContent = str.slice(0, -1);
    const d = lastDigit.current;
    if (d) {
      d.textContent = str.slice(-1);
      if (t > 0) { d.classList.remove('is-tick'); d.getBBox(); d.classList.add('is-tick'); }
    }
    if (sub.current) sub.current.textContent = rem > 0 ? `Dimming · off at ${offAt(rem)}` : 'Lights off';
  });
  return (
    <div className="lv lv-dial" ref={ref} style={place(s, WIN.dial)} aria-hidden="true">
      <svg viewBox="-250 -250 500 500">
        <circle r="250" fill="#262829" />
        <g stroke="#5e6062" strokeLinecap="round">{TICKS}</g>
        <circle r="220" fill="none" stroke="#353738" strokeWidth="40" />
        <circle ref={arc} className="lv-dial__arc" r="220" fill="none" stroke="#6b76e8" strokeWidth="40" strokeLinecap="round" strokeDasharray={C} strokeDashoffset={C * (1 - START / TOTAL)} transform="rotate(-90)" />
        <text y="23" textAnchor="middle" fontSize="116" fontWeight="500" fill="#9d9e9f" letterSpacing="-2">
          <tspan ref={head}>4:0</tspan><tspan ref={lastDigit} className="lv-dial__last">6</tspan>
        </text>
        <text ref={sub} y="82" textAnchor="middle" fontSize="32" fontWeight="500" fill="#9d9e9f">Dimming · off at 10:36</text>
      </svg>
    </div>
  );
}
/** The "Dimming · off at …" badge in the timer card header, kept in step with the dial. */
export function LiveBadge({ s }: { s: Shot }) {
  return <LiveText s={s} r={WIN.dialBadge} bg="#303446" color="#707cf7" size={22} weight={500} text={(t) => { const { rem } = countdown(t); return rem > 0 ? `Dimming · off at ${offAt(rem)}` : 'Lights off'; }} />;
}

/* ── Colour-temperature slider ───────────────────────────────── */
const CT_STOPS = [[240, 147, 61], [242, 164, 89], [243, 179, 117], [245, 192, 143], [246, 204, 163], [248, 214, 182], [250, 223, 197], [250, 231, 213], [253, 239, 226], [254, 245, 238], [255, 253, 249]];
function ctColor(f: number) {
  const p = Math.min(0.9999, Math.max(0, f)) * 10, i = Math.floor(p), k = p - i;
  const a = CT_STOPS[i], b = CT_STOPS[i + 1];
  return `rgb(${a.map((v, j) => Math.round(v + (b[j] - v) * k)).join(' ')})`;
}
export function LiveCt({ s, header }: { s: Shot; header?: boolean }) {
  const thumb = useRef<HTMLSpanElement>(null);
  const ref = useLive<HTMLDivElement>((t) => {
    const f = (kelvin(t) - 2000) / 4500;
    const th = thumb.current;
    if (!th) return;
    th.style.left = `${((25 + f * 1310) / 1360) * 100}%`;
    th.style.background = ctColor(f);
  });
  const k = (t: number) => `${Math.round(kelvin(t))} K`;
  // The patch is 66 px tall (the thumb + its shadow) so the captured thumb is fully covered; the bar inside is the 50 px track.
  const tr = WIN.ctTrack;
  return (
    <>
      <div ref={ref} className="lv lv-track" style={place(s, rect(tr.x, tr.y - 8, tr.w, tr.h + 16))} aria-hidden="true">
        <span className="lv-track__bar" />
        <span ref={thumb} className="lv-thumb" style={{ width: cq(s, 60), height: cq(s, 60), borderWidth: cq(s, 6) }} />
      </div>
      <LiveText s={s} r={WIN.ctReadout} bg="#262829" color="#dedede" size={26} weight={600} align="center" text={k} />
      {header && <LiveText s={s} r={WIN.headerSub} bg="#262829" color="#9d9e9f" size={22} text={(t) => `${k(t)} · 95%`} />}
    </>
  );
}

/* ── Colour wheel marker + bulb dots ─────────────────────────── */
export function LiveWheel({ s }: { s: Shot }) {
  const m = useRef<HTMLSpanElement>(null);
  const ref = useLive<HTMLDivElement>((t) => {
    const { a, rf, css } = hue(t);
    const el = m.current;
    if (!el) return;
    const rad = (a * Math.PI) / 180;
    el.style.left = `${50 + 50 * rf * Math.cos(rad)}%`;
    el.style.top = `${50 + 50 * rf * Math.sin(rad)}%`;
    el.style.background = css;
  });
  return (
    <div ref={ref} className="lv" style={place(s, WIN.wheel)} aria-hidden="true">
      <span ref={m} className="lv-marker" style={{ width: cq(s, 56), height: cq(s, 56), borderWidth: cq(s, 6) }} />
    </div>
  );
}
export function LiveDot({ s, r, mode, color }: { s: Shot; r: Rect; mode: 'hue' | 'police-a' | 'police-b' | 'pulse'; color?: string }) {
  const live = useLive<HTMLSpanElement>((t) => { if (mode === 'hue' && live.current) live.current.style.background = hue(t).css; });
  const phased = usePhase<HTMLSpanElement>(mode === 'pulse' ? 2200 : 2400);
  const cls = mode === 'police-a' ? 'lv-dot--pa' : mode === 'police-b' ? 'lv-dot--pb' : mode === 'pulse' ? 'lv-dot--pulse' : '';
  return <span ref={mode === 'hue' ? live : phased} className={`lv lv-dot ${cls}`} style={{ ...place(s, r), background: color }} aria-hidden="true" />;
}

/* ── macOS switch ────────────────────────────────────────────── */
export function LiveToggle({ s, r, on }: { s: Shot; r: Rect; on: (t: number) => boolean }) {
  const last = useRef<boolean | null>(null);
  const ref = useLive<HTMLDivElement>((t) => {
    const v = on(t);
    if (v !== last.current && ref.current) { last.current = v; ref.current.classList.toggle('is-on', v); }
  });
  const inset = 2, d = r.h - inset * 2;
  return (
    <div ref={ref} className="lv lv-toggle" style={{ ...place(s, r), ['--travel' as string]: `${((r.w - r.h) / d) * 100}%` } as CSSProperties} aria-hidden="true">
      <span className="lv-toggle__knob" style={{ top: `${(inset / r.h) * 100}%`, left: `${(inset / r.w) * 100}%`, width: `${(d / r.w) * 100}%`, height: `${(d / r.h) * 100}%` }} />
    </div>
  );
}

/* ── Selection highlights (scene cards, chips) ───────────────── */
export function LiveHighlights({ s, rects, radius, active }: { s: Shot; rects: readonly Rect[]; radius: number; active: (t: number) => number }) {
  const last = useRef(-2);
  const ref = useLive<HTMLDivElement>((t) => {
    const i = active(t);
    if (i === last.current || !ref.current) return;
    last.current = i;
    Array.from(ref.current.children).forEach((c, k) => c.classList.toggle('is-on', k === i));
  });
  return (
    <div ref={ref} className="lv" style={{ inset: 0 }} aria-hidden="true">
      {rects.map((r, i) => <span key={i} className="lv lv-hl" style={{ ...place(s, r), borderRadius: cq(s, radius), borderWidth: cq(s, 2) }} />)}
    </div>
  );
}

/* ── Police tile: red ↔ blue ─────────────────────────────────── */
export function LivePolice({ s }: { s: Shot }) {
  const ref = usePhase<HTMLDivElement>(2400);
  return (
    <div ref={ref} className="lv lv-police" style={{ ...place(s, WIN.policeTile), borderRadius: cq(s, 16), borderWidth: cq(s, 2) }} aria-hidden="true">
      <span style={{ animationDelay: 'inherit' }} /><span style={{ animationDelay: 'inherit' }} />
    </div>
  );
}

/* ── Go-to-sleep fade progress ───────────────────────────────── */
export function LiveFade({ s }: { s: Shot }) {
  const bar = useRef<HTMLSpanElement>(null);
  const ref = useLive<HTMLDivElement>((t) => { if (bar.current) bar.current.style.width = `${fadeFrac(t) * 100}%`; });
  return (
    <div ref={ref} className="lv lv-bar" style={place(s, WIN.fadeBar)} aria-hidden="true"><span ref={bar} /></div>
  );
}

/* ── Ambient glows that follow the overlays ──────────────────── */
/** Two .glow layers crossfading through the active scene's colour. */
export function SceneGlow({ className = '' }: { className?: string }) {
  const a = useRef<HTMLDivElement>(null), b = useRef<HTMLDivElement>(null);
  const cur = useRef(-1), front = useRef(0);
  const ref = useLive<HTMLDivElement>((t) => {
    const i = sceneIdx(t);
    if (i === cur.current) return;
    cur.current = i;
    front.current ^= 1;
    const show = front.current ? b.current : a.current, hide = front.current ? a.current : b.current;
    show?.style.setProperty('--glow', SCENES[i].glow);
    show?.classList.remove('is-off');
    hide?.classList.add('is-off');
  });
  return (
    <div ref={ref} className={`lv-glow-pair ${className}`} aria-hidden="true">
      <div className="glow" ref={a} /><div className="glow is-off" ref={b} />
    </div>
  );
}
/** Red ↔ blue, in phase with every police dot and tile. */
export function PoliceGlow({ className = '' }: { className?: string }) {
  const ref = usePhase<HTMLDivElement>(2400);
  return (
    <div ref={ref} className={`lv-police-glow ${className}`} aria-hidden="true">
      <div className="glow" style={{ animationDelay: 'inherit' }} /><div className="glow" style={{ animationDelay: 'inherit' }} />
    </div>
  );
}

/* ── Cursor tilt (shared by the Story stack and the Showcase deck) ── */
export function attachTilt(area: HTMLElement, target: HTMLElement, max: number) {
  if (reducedMotion() || !window.matchMedia('(hover: hover) and (pointer: fine)').matches) return () => {};
  const rx = gsap.quickTo(target, 'rotationX', { duration: 1.1, ease: 'power3.out' });
  const ry = gsap.quickTo(target, 'rotationY', { duration: 1.1, ease: 'power3.out' });
  const move = (e: PointerEvent) => {
    const r = area.getBoundingClientRect();
    ry((((e.clientX - r.left) / r.width) * 2 - 1) * max);
    rx(-(((e.clientY - r.top) / r.height) * 2 - 1) * max * 0.7);
  };
  const leave = () => { rx(0); ry(0); };
  area.addEventListener('pointermove', move);
  area.addEventListener('pointerleave', leave);
  return () => {
    area.removeEventListener('pointermove', move);
    area.removeEventListener('pointerleave', leave);
  };
}
