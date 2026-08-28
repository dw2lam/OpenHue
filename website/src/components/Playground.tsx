import { useEffect, useRef, useState, type PointerEvent as RPointerEvent } from 'react';
import { useReveal } from '../hooks/useReveal';
import { gsap, ScrollTrigger, reducedMotion } from '../lib/gsap';
import './playground.css';

/* ────────────────────────────────────────────────────────────────
   Colour math — ported from Sources/OpenHue/Models/ColorMath.swift
   ──────────────────────────────────────────────────────────────── */
interface XY { x: number; y: number }
interface RGB { r: number; g: number; b: number }

const GAMUT_C = { r: { x: 0.692, y: 0.308 }, g: { x: 0.170, y: 0.700 }, b: { x: 0.153, y: 0.048 } };
const MIN_MIREDS = 153; // ~6535 K
const MAX_MIREDS = 500; // 2000 K

const clamp01 = (v: number) => Math.max(0, Math.min(1, v));
const linearize = (c: number) => (c > 0.04045 ? Math.pow((c + 0.055) / 1.055, 2.4) : c / 12.92);
function gammaEncode(c: number) {
  const v = clamp01(c);
  return v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
}

function sign(p1: XY, p2: XY, p3: XY) {
  return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y);
}
function isInside(p: XY, a: XY, b: XY, c: XY) {
  const d1 = sign(p, a, b), d2 = sign(p, b, c), d3 = sign(p, c, a);
  const hasNeg = d1 < 0 || d2 < 0 || d3 < 0;
  const hasPos = d1 > 0 || d2 > 0 || d3 > 0;
  return !(hasNeg && hasPos);
}
function closestPoint(a: XY, b: XY, p: XY): XY {
  const abx = b.x - a.x, aby = b.y - a.y;
  const len2 = abx * abx + aby * aby;
  if (len2 <= 0) return a;
  const t = clamp01(((p.x - a.x) * abx + (p.y - a.y) * aby) / len2);
  return { x: a.x + t * abx, y: a.y + t * aby };
}
const dist2 = (a: XY, b: XY) => (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y);

function clampToGamutC(p: XY): XY {
  const { r, g, b } = GAMUT_C;
  if (isInside(p, r, g, b)) return p;
  const candidates = [closestPoint(r, g, p), closestPoint(g, b, p), closestPoint(b, r, p)];
  return candidates.reduce((best, c) => (dist2(c, p) < dist2(best, p) ? c : best));
}

/** sRGB → CIE xy (Philips wide-gamut D65 matrix), clamped into gamut C. */
function xyFromRGB(rgb: RGB): XY {
  const r = linearize(clamp01(rgb.r)), g = linearize(clamp01(rgb.g)), b = linearize(clamp01(rgb.b));
  const X = r * 0.664511 + g * 0.154324 + b * 0.162028;
  const Y = r * 0.283881 + g * 0.668433 + b * 0.047685;
  const Z = r * 0.000088 + g * 0.072310 + b * 0.986039;
  const sum = X + Y + Z;
  if (sum <= 0) return { x: 0.3127, y: 0.3290 };
  return clampToGamutC({ x: X / sum, y: Y / sum });
}

/** CIE xy → sRGB, normalised so the brightest channel is 1, then scaled by `brightness`. */
function rgbFromXY(xy: XY, brightness = 1): RGB {
  const y = Math.max(xy.y, 1e-6);
  const Y = 1.0;
  const X = (Y / y) * xy.x;
  const Z = (Y / y) * (1 - xy.x - xy.y);
  let r = X * 1.656492 - Y * 0.354851 - Z * 0.255038;
  let g = -X * 0.707196 + Y * 1.655397 + Z * 0.036152;
  let b = X * 0.051713 - Y * 0.121364 + Z * 1.011530;
  r = Math.max(0, r); g = Math.max(0, g); b = Math.max(0, b);
  const m = Math.max(r, g, b);
  if (m > 0) { r /= m; g /= m; b /= m; }
  const k = clamp01(brightness);
  return { r: gammaEncode(r * k), g: gammaEncode(g * k), b: gammaEncode(b * k) };
}

function rgbFromHSV(h: number, s: number, v: number): RGB {
  const hh = (h - Math.floor(h)) * 6;
  const i = Math.floor(hh);
  const f = hh - i;
  const p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
  switch (i % 6) {
    case 0: return { r: v, g: t, b: p };
    case 1: return { r: q, g: v, b: p };
    case 2: return { r: p, g: v, b: t };
    case 3: return { r: p, g: q, b: v };
    case 4: return { r: t, g: p, b: v };
    default: return { r: v, g: p, b: q };
  }
}

function hsvFromRGB(c: RGB) {
  const mx = Math.max(c.r, c.g, c.b), mn = Math.min(c.r, c.g, c.b);
  const d = mx - mn;
  let h = 0;
  if (d > 1e-9) {
    if (mx === c.r) h = ((c.g - c.b) / d) % 6;
    else if (mx === c.g) h = (c.b - c.r) / d + 2;
    else h = (c.r - c.g) / d + 4;
    h /= 6;
    if (h < 0) h += 1;
  }
  return { h, s: mx > 0 ? d / mx : 0, v: mx };
}

/** HSV(h, s, 1) → xy — what the colour wheel writes. */
const xyFromHue = (hue: number, saturation: number) => xyFromRGB(rgbFromHSV(hue, saturation, 1));
/** xy → (hue, saturation) for placing the wheel thumb. */
function hueSaturationFromXY(xy: XY) {
  const hsv = hsvFromRGB(rgbFromXY(xy));
  return { h: hsv.h, s: hsv.s };
}

const kelvinFromMireds = (m: number) => 1_000_000 / Math.max(m, 1);
function miredsFromKelvin(k: number) {
  const m = Math.round(1_000_000 / Math.max(k, 1));
  return Math.min(MAX_MIREDS, Math.max(MIN_MIREDS, m));
}

/** Black-body sRGB (Tanner Helland's fit) — the app's CT slider gradient. */
function rgbFromKelvin(kelvin: number): RGB {
  const t = Math.max(1000, Math.min(40000, kelvin)) / 100;
  let r: number, g: number, b: number;
  if (t <= 66) {
    r = 255;
    g = 99.4708025861 * Math.log(t) - 161.1195681661;
    b = t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307;
  } else {
    r = 329.698727446 * Math.pow(t - 60, -0.1332047592);
    g = 288.1221695283 * Math.pow(t - 60, -0.0755148492);
    b = 255;
  }
  const c = (v: number) => Math.max(0, Math.min(255, v)) / 255;
  return { r: c(r), g: c(g), b: c(b) };
}

/** Correlated colour temperature of an xy point (McCamy), as clamped mireds. */
function approxMireds(xy: XY): number {
  const n = (xy.x - 0.3320) / (0.1858 - xy.y);
  const cct = 449 * n ** 3 + 3525 * n ** 2 + 6823.3 * n + 5520.33;
  if (!Number.isFinite(cct)) return 367;
  return miredsFromKelvin(cct);
}

/* ────────────────────────────────────────────────────────────────
   Light model + Hue's stock scenes (Sources/OpenHue/Models/Presets.swift)
   ──────────────────────────────────────────────────────────────── */
type ColorMode = { kind: 'ct'; mireds: number } | { kind: 'xy'; x: number; y: number };

type EffectId = 'none' | 'candle' | 'fireplace' | 'prism' | 'sparkle' | 'opal' | 'glisten' | 'underwater' | 'cosmos' | 'sunbeam' | 'enchant';

interface Light { on: boolean; bri: number; color: ColorMode; effect: EffectId }
type Lights = [Light, Light];

interface PaletteEntry { bri: number; color: ColorMode }
interface Scene { name: string; palette: PaletteEntry[] }

const white = (bri: number, mireds: number): PaletteEntry => ({ bri, color: { kind: 'ct', mireds } });
const color = (x: number, y: number, bri: number): PaletteEntry => ({ bri, color: { kind: 'xy', x, y } });

const SCENES: Scene[] = [
  { name: 'Bright', palette: [white(254, 367)] },
  { name: 'Dimmed', palette: [white(77, 367)] },
  { name: 'Nightlight', palette: [color(0.561, 0.404, 1)] },
  { name: 'Relax', palette: [white(144, 447)] },
  { name: 'Read', palette: [white(254, 346)] },
  { name: 'Concentrate', palette: [white(254, 233)] },
  { name: 'Energize', palette: [white(254, 156)] },
  { name: 'Savanna Sunset', palette: [color(0.644, 0.340, 200), color(0.570, 0.384, 200), color(0.492, 0.428, 200)] },
  { name: 'Tropical Twilight', palette: [color(0.312, 0.133, 180), color(0.405, 0.208, 180), color(0.602, 0.321, 180)] },
  { name: 'Arctic Aurora', palette: [color(0.164, 0.332, 200), color(0.221, 0.521, 200), color(0.150, 0.100, 200)] },
  { name: 'Spring Blossom', palette: [color(0.438, 0.270, 210), color(0.354, 0.247, 210), color(0.460, 0.380, 210)] },
];

/** Bulb firmware effects — TLV tag 06 values from HueProtocol.swift. */
const EFFECTS: { id: EffectId; tag: number; name: string }[] = [
  { id: 'none', tag: 0x00, name: 'None' },
  { id: 'candle', tag: 0x01, name: 'Candle' },
  { id: 'fireplace', tag: 0x02, name: 'Fireplace' },
  { id: 'prism', tag: 0x03, name: 'Prism' },
  { id: 'sparkle', tag: 0x0a, name: 'Sparkle' },
  { id: 'opal', tag: 0x0b, name: 'Opal' },
  { id: 'glisten', tag: 0x0c, name: 'Glisten' },
  { id: 'underwater', tag: 0x0e, name: 'Underwater' },
  { id: 'cosmos', tag: 0x0f, name: 'Cosmos' },
  { id: 'sunbeam', tag: 0x10, name: 'Sunbeam' },
  { id: 'enchant', tag: 0x11, name: 'Enchant' },
];
const effectName = (id: EffectId) => EFFECTS.find((e) => e.id === id)?.name ?? 'None';

/** Gamut-C corners the app uses for Police (AppEffectRunner.swift). */
const POLICE_RED = rgbFromXY(clampToGamutC(xyFromRGB({ r: 1, g: 0, b: 0 })));
const POLICE_BLUE = rgbFromXY(clampToGamutC(xyFromRGB({ r: 0, g: 0, b: 1 })));

/** Full-brightness representative colour (ColorMode.displayRGB). */
function displayRGB(c: ColorMode): RGB {
  return c.kind === 'ct' ? rgbFromKelvin(kelvinFromMireds(c.mireds)) : rgbFromXY({ x: c.x, y: c.y });
}
const rgbList = (c: RGB) => `${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)}`;
const css = (c: RGB) => `rgb(${rgbList(c)})`;

/* ────────────────────────────────────────────────────────────────
   Playground state
   ──────────────────────────────────────────────────────────────── */
type Tab = 'white' | 'color' | 'effects';
type Target = 'all' | 0 | 1;
type TimerMode = 'timer' | 'sleep';

interface Police { interval: number; snapshot: Lights }
interface TimerState { id: number; mode: TimerMode; startedAt: number; endsAt: number; duration: number }

interface PgState {
  lights: Lights;
  target: Target;
  tab: Tab;
  scene: string | null;
  police: Police | null;
  policeInterval: number;
  timer: TimerState | null;
  timerMode: TimerMode;
}

/** Arrival state: warm white on the left, a Candle already flickering on the right — alive before any click. */
const INITIAL: PgState = {
  lights: [
    { on: true, bri: 254, color: { kind: 'ct', mireds: 367 }, effect: 'none' },
    { on: true, bri: 230, color: { kind: 'ct', mireds: 400 }, effect: 'candle' },
  ],
  target: 'all',
  tab: 'white',
  scene: null,
  police: null,
  policeInterval: 0.35,
  timer: null,
  timerMode: 'timer',
};

const targetsOf = (t: Target): number[] => (t === 'all' ? [0, 1] : [t]);
function mapLights(lights: Lights, fn: (l: Light, i: number) => Light): Lights {
  return [fn(lights[0], 0), fn(lights[1], 1)];
}

/* ────────────────────────────────────────────────────────────────
   Per-frame simulation
   ──────────────────────────────────────────────────────────────── */
interface Frame { r: number; g: number; b: number; k: number }

function hash(n: number) { const x = Math.sin(n * 12.9898) * 43758.5453; return x - Math.floor(x); }
/** Smooth value noise in 0…1. */
function noise(x: number) {
  const i = Math.floor(x); const f = x - i; const u = f * f * (3 - 2 * f);
  return hash(i) * (1 - u) + hash(i + 1) * u;
}
const mix = (a: RGB, b: RGB, t: number): RGB => ({ r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t });
const WHITE: RGB = { r: 1, g: 1, b: 1 };
const hsv = (h: number, s: number) => rgbFromHSV(h, s, 1);
const briToK = (b: number) => 0.06 + 0.94 * Math.pow(b, 0.7);

function frameFor(s: PgState, i: number, t: number): Frame {
  if (s.police) {
    const phase = Math.floor(t / s.police.interval);
    const c = (phase + i) % 2 === 0 ? POLICE_RED : POLICE_BLUE;
    return { ...c, k: 1 };
  }
  const L = s.lights[i];
  if (!L.on) return { r: 0, g: 0, b: 0, k: 0 };
  const k0 = briToK(L.bri / 254);
  const o = i * 7.31;
  switch (L.effect) {
    case 'candle': {
      const c = mix(rgbFromKelvin(1800), rgbFromKelvin(2500), noise(t * 2.2 + o));
      const fl = 0.55 + 0.45 * (0.6 * noise(t * 7 + o) + 0.4 * noise(t * 13 + o * 3));
      return { ...c, k: k0 * fl };
    }
    case 'fireplace': {
      const c = hsv(0.02 + 0.045 * noise(t * 1.6 + o), 1);
      const fl = 0.38 + 0.62 * (0.5 * noise(t * 3.5 + o) + 0.5 * noise(t * 9 + o * 2));
      return { ...c, k: k0 * fl };
    }
    case 'prism': return { ...hsv((t / 14 + i * 0.5) % 1, 1), k: k0 };
    case 'sparkle': {
      const spark = Math.min(1, Math.pow(noise(t * 10 + o * 5), 8) * 1.6);
      const c = mix(rgbFromKelvin(4000), WHITE, spark);
      return { ...c, k: k0 * (0.55 + 0.45 * spark) };
    }
    case 'opal': return { ...hsv((t / 26 + i * 0.4) % 1, 0.45), k: k0 * (0.85 + 0.15 * noise(t * 0.8 + o)) };
    case 'glisten': {
      const c = mix(rgbFromKelvin(5500), hsv(0.55, 0.25), 0.5 + 0.5 * Math.sin(t * 0.7 + o));
      return { ...c, k: k0 * (0.7 + 0.3 * noise(t * 3 + o * 1.5)) };
    }
    case 'underwater': {
      const h = 0.5 + 0.12 * (0.5 + 0.5 * Math.sin(t * 0.5 + i * 2.1));
      return { ...hsv(h, 0.95), k: k0 * (0.65 + 0.35 * (0.5 + 0.5 * Math.sin(t * 1.1 + i * 0.8))) };
    }
    case 'cosmos': {
      const h = 0.70 + 0.10 * (0.5 + 0.5 * Math.sin(t * 0.35 + i * 2.5));
      const twinkle = Math.pow(noise(t * 5 + o * 2.3), 10);
      return { ...mix(hsv(h, 0.95), WHITE, twinkle * 0.6), k: Math.min(1, k0 * (0.5 + 0.35 * noise(t * 0.9 + o) + 0.6 * twinkle)) };
    }
    case 'sunbeam': return { ...hsv(0.09, 0.8), k: k0 * (0.55 + 0.45 * (0.5 + 0.5 * Math.sin(t * 0.45 + i * Math.PI))) };
    case 'enchant': {
      const h = 0.80 + 0.08 * Math.sin(t * 0.4 + i * 1.3);
      const spark = Math.pow(noise(t * 8 + o * 3.1), 7);
      return { ...mix(hsv(h, 0.85), WHITE, spark * 0.7), k: Math.min(1, k0 * (0.7 + 0.3 * noise(t * 1.5 + o) + 0.3 * spark)) };
    }
    default: return { ...displayRGB(L.color), k: k0 };
  }
}

/** Timer: hold then fade out; Sleep: dim over the whole countdown. */
function timerFactor(tm: TimerState, now: number) {
  const remaining = tm.endsAt - now;
  if (remaining <= 0) return 0;
  if (tm.mode === 'sleep') return 1 - 0.95 * (1 - remaining / tm.duration);
  const fade = Math.min(2, tm.duration * 0.3);
  return remaining < fade ? remaining / fade : 1;
}

function describe(s: PgState, i: number) {
  const L = s.lights[i];
  const pct = `${Math.round((L.bri / 254) * 100)}%`;
  if (s.police) return 'Police · 100%';
  if (!L.on) return 'Off';
  if (L.effect !== 'none') return `${effectName(L.effect)} · ${pct}`;
  if (L.color.kind === 'ct') return `${Math.round(kelvinFromMireds(L.color.mireds) / 10) * 10} K · ${pct}`;
  return `xy ${L.color.x.toFixed(3)} ${L.color.y.toFixed(3)} · ${pct}`;
}

const hex = (n: number) => n.toString(16).padStart(2, '0').toUpperCase();
const u16le = (n: number) => `${hex(n & 0xff)} ${hex((n >> 8) & 0xff)}`;
/** The bytes OpenHue would write for the current control — see the protocol table below. */
function packetFor(tab: Tab, L: Light, police: Police | null): { char: string; bytes: string; note: string } {
  if (police) return { char: '0005', bytes: `${u16le(Math.round(GAMUT_C.r.x * 65535))} ${u16le(Math.round(GAMUT_C.r.y * 65535))}`, note: `xy red/blue · Mac · every ${police.interval.toFixed(2)} s` };
  if (tab === 'white') {
    const m = L.color.kind === 'ct' ? L.color.mireds : approxMireds(L.color);
    return { char: '0004', bytes: u16le(m), note: `uint16 LE · ${m} mireds` };
  }
  if (tab === 'color') {
    const xy = L.color.kind === 'xy' ? L.color : { x: 0.3127, y: 0.329 };
    return { char: '0005', bytes: `${u16le(Math.round(xy.x * 65535))} ${u16le(Math.round(xy.y * 65535))}`, note: 'round(x·65535), round(y·65535)' };
  }
  const tag = EFFECTS.find((e) => e.id === L.effect)?.tag ?? 0;
  return { char: '0007', bytes: `06 01 ${hex(tag)}`, note: 'TLV · tag 06 effect' };
}

const fmtClock = (secs: number) => {
  const s = Math.max(0, Math.ceil(secs));
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
};

/** Quick CT stops — same values the app's slider snaps to comfortably. */
const CT_PRESETS: [number, string][] = [[2000, 'Ember'], [2700, 'Warm'], [4000, 'Neutral'], [6500, 'Daylight']];
const CT_TRACK = `linear-gradient(90deg, ${[2000, 2400, 2700, 3200, 4000, 5000, 6500].map((k) => css(rgbFromKelvin(k))).join(', ')})`;
const BRI_TRACK = 'linear-gradient(90deg, rgba(255,255,255,0.06), rgba(255,255,255,0.92))';
const LAMP_POS = [{ x: 30, y: 40 }, { x: 70, y: 40 }];
const RING_R = 22;
const RING_C = 2 * Math.PI * RING_R;


interface LampEls { root: HTMLDivElement; lastC: string; lastK: number }

/** Copy budget: mono tags, not sentences. */
const HEAD_TAGS = ['2 virtual bulbs', 'White · Color · Effects', '11 Hue scenes', 'Police from the Mac', 'Timer'];
const footTags = (interval: number) => [
  '254 brightness steps', '153–500 mireds', 'xy · gamut C', 'Effects run on the bulb', `Police · Mac · every ${interval.toFixed(2)} s`,
];

/* ────────────────────────────────────────────────────────────────
   Component
   ──────────────────────────────────────────────────────────────── */
export default function Playground() {
  const root = useReveal<HTMLElement>();
  const frameRef = useRef<HTMLDivElement>(null);
  const ambientRef = useRef<HTMLDivElement>(null);
  const [st, setSt] = useState<PgState>(INITIAL);
  const stRef = useRef(st);
  stRef.current = st;

  const [drag, setDrag] = useState<{ h: number; s: number } | null>(null);
  const wheelRef = useRef<HTMLDivElement>(null);
  const lampEls = useRef<(LampEls | null)[]>([null, null]);
  const countRef = useRef<HTMLSpanElement>(null);
  const ringRef = useRef<SVGCircleElement>(null);
  const timerDone = useRef(0);

  /* ── animation loop (rAF, DOM writes only) ───────────────────── */
  const sim = useRef({
    cur: [{ r: 1, g: 0.65, b: 0.34, k: 0 }, { r: 1, g: 0.65, b: 0.34, k: 0 }] as Frame[],
    last: 0, raf: 0, active: false, visible: true, rm: false,
    ambAt: 0, ambC: '', ambK: -1,
  });

  const tick = useRef((now: number) => {
    const S = sim.current;
    const s = stRef.current;
    const dt = S.last ? Math.min(0.1, (now - S.last) / 1000) : 0.016;
    S.last = now;
    const t = S.rm ? 0 : now / 1000;
    const animated = !S.rm && (!!s.police || s.lights.some((l) => l.on && l.effect !== 'none'));
    const tau = animated ? 0.045 : 0.22;
    const ease = 1 - Math.exp(-dt / tau);
    let busy = animated;

    const nowS = Date.now() / 1000;
    let tf = 1;
    if (s.timer) {
      busy = true;
      tf = timerFactor(s.timer, nowS);
      const remaining = s.timer.endsAt - nowS;
      if (countRef.current) countRef.current.textContent = fmtClock(remaining);
      if (ringRef.current) ringRef.current.style.strokeDashoffset = String(RING_C * (1 - Math.max(0, remaining) / s.timer.duration));
      if (remaining <= 0 && timerDone.current !== s.timer.id) {
        const id = s.timer.id;
        timerDone.current = id;
        setSt((p) => (p.timer?.id === id ? { ...p, lights: mapLights(p.lights, (l) => ({ ...l, on: false })), timer: null, police: null, scene: null } : p));
      }
    }

    for (let i = 0; i < 2; i++) {
      const target = frameFor(s, i, t);
      const c = S.cur[i];
      const kT = target.k * tf;
      if (kT > 0) { c.r += (target.r - c.r) * ease; c.g += (target.g - c.g) * ease; c.b += (target.b - c.b) * ease; }
      c.k += (kT - c.k) * ease;
      if (Math.abs(kT - c.k) > 0.002 || (kT > 0 && (Math.abs(target.r - c.r) + Math.abs(target.g - c.g) + Math.abs(target.b - c.b)) > 0.004)) busy = true;
      const el = lampEls.current[i];
      if (el) {
        const cs = `${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)}`;
        if (cs !== el.lastC) { el.root.style.setProperty('--c', cs); el.lastC = cs; }
        if (Math.abs(c.k - el.lastK) > 0.0025) { el.root.style.setProperty('--k', c.k.toFixed(3)); el.lastK = c.k; }
      }
    }

    /* Ambient glow behind the frame follows the light — at most ~8 writes/s (a blurred layer repaints on
       every colour change); the registered --pg-glow transition smooths between writes. Police strobes. */
    const amb = ambientRef.current;
    if (amb && (s.police || now - S.ambAt > 120)) {
      const a = S.cur[0], b = S.cur[1];
      let cs = S.ambC;
      if (s.police) cs = `${Math.round(a.r * 255)},${Math.round(a.g * 255)},${Math.round(a.b * 255)}`;
      else if (a.k + b.k > 0.01) {
        const w = a.k + b.k;
        cs = `${Math.round(((a.r * a.k + b.r * b.k) / w) * 255)},${Math.round(((a.g * a.k + b.g * b.k) / w) * 255)},${Math.round(((a.b * a.k + b.b * b.k) / w) * 255)}`;
      }
      const k = Math.max(a.k, b.k);
      if (cs !== S.ambC) { amb.style.setProperty('--pg-glow', `rgb(${cs})`); S.ambC = cs; S.ambAt = now; }
      if (Math.abs(k - S.ambK) > 0.02) { amb.style.setProperty('--pg-k', k.toFixed(2)); S.ambK = k; S.ambAt = now; }
    }

    if (busy && S.visible) S.raf = requestAnimationFrame(tick.current);
    else { S.active = false; S.last = 0; }
  });

  const start = () => {
    const S = sim.current;
    if (S.active || !S.visible) return;
    S.active = true;
    S.raf = requestAnimationFrame(tick.current);
  };

  useEffect(() => { start(); }, [st]);

  useEffect(() => {
    const S = sim.current;
    const mq = window.matchMedia('(prefers-reduced-motion: reduce)');
    S.rm = mq.matches;
    const onMq = () => { S.rm = mq.matches; start(); };
    mq.addEventListener('change', onMq);
    const io = new IntersectionObserver((entries) => {
      S.visible = entries[0]?.isIntersecting ?? true;
      if (S.visible) start();
    }, { rootMargin: '120px 0px' });
    if (frameRef.current) io.observe(frameRef.current);
    const onVis = () => { if (!document.hidden) start(); };
    document.addEventListener('visibilitychange', onVis);
    start();
    return () => {
      mq.removeEventListener('change', onMq);
      io.disconnect();
      document.removeEventListener('visibilitychange', onVis);
      cancelAnimationFrame(S.raf);
      S.active = false;
    };
  }, []);

  /* ── scroll entrance: frame tilts up out of the page ─────────── */
  useEffect(() => {
    const el = frameRef.current;
    if (!el || reducedMotion() || window.innerWidth <= 720) return;
    const tween = gsap.fromTo(el,
      { rotateX: 9, y: 70, opacity: 0.35, transformPerspective: 1400, transformOrigin: '50% 100%' },
      { rotateX: 0, y: 0, opacity: 1, ease: 'none', scrollTrigger: { trigger: el, start: 'top 95%', end: 'top 45%', scrub: 0.5 } });
    return () => { tween.scrollTrigger?.kill(); tween.kill(); ScrollTrigger.refresh(); };
  }, []);

  /* ── state helpers ────────────────────────────────────────────── */
  /** A manual change stops a Mac-driven effect without restoring (user wins), like the app. */
  const manual = (fn: (l: Light, i: number) => Light, extra: Partial<PgState> = {}) =>
    setSt((p) => {
      const ts = targetsOf(p.target);
      return { ...p, police: null, scene: null, lights: mapLights(p.lights, (l, i) => (ts.includes(i) ? fn(l, i) : l)), ...extra };
    });

  const setPower = (on: boolean) => manual((l) => ({ ...l, on }));
  const setBrightness = (pct: number) => manual((l) => ({ ...l, on: true, bri: Math.max(1, Math.round((pct / 100) * 254)) }));
  const setKelvin = (k: number) => manual((l) => ({ ...l, on: true, effect: 'none', color: { kind: 'ct', mireds: miredsFromKelvin(k) } }));
  const setXY = (xy: XY) => manual((l) => ({ ...l, on: true, effect: 'none', color: { kind: 'xy', ...xy } }));
  const setEffect = (effect: EffectId) => manual((l) => ({ ...l, on: true, effect }));

  const applyScene = (sc: Scene) =>
    setSt((p) => {
      const ts = targetsOf(p.target);
      const first = sc.palette[0];
      return {
        ...p, police: null, scene: sc.name,
        tab: p.tab === 'effects' ? (first.color.kind === 'ct' ? 'white' : 'color') : p.tab,
        lights: mapLights(p.lights, (l, i) => {
          if (!ts.includes(i)) return l;
          const e = sc.palette[i % sc.palette.length];
          return { on: true, bri: e.bri, color: e.color, effect: 'none' };
        }),
      };
    });

  const startPolice = () => setSt((p) => ({
    ...p, scene: null,
    police: { interval: p.policeInterval, snapshot: p.lights },
    lights: mapLights(p.lights, () => ({ on: true, bri: 254, color: { kind: 'xy', x: GAMUT_C.r.x, y: GAMUT_C.r.y }, effect: 'none' })),
  }));
  /** Stop restores each light to the state it had before the effect began. */
  const stopPolice = () => setSt((p) => (p.police ? { ...p, lights: p.police.snapshot, police: null } : p));

  const startTimer = (secs: number) => setSt((p) => {
    const now = Date.now() / 1000;
    return { ...p, timer: { id: now, mode: p.timerMode, startedAt: now, endsAt: now + secs, duration: secs } };
  });
  const extendTimer = (secs: number) => setSt((p) => (p.timer ? { ...p, timer: { ...p.timer, endsAt: p.timer.endsAt + secs, duration: p.timer.duration + secs } } : p));
  const cancelTimer = () => setSt((p) => ({ ...p, timer: null }));

  /* ── wheel ────────────────────────────────────────────────────── */
  const wheelAt = (e: RPointerEvent<HTMLDivElement>) => {
    const el = wheelRef.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    const R = r.width / 2;
    const dx = e.clientX - r.left - R, dy = e.clientY - r.top - R;
    let h = Math.atan2(dy, dx) / (2 * Math.PI);
    if (h < 0) h += 1;
    const s = Math.min(1, Math.hypot(dx, dy) / R);
    setDrag({ h, s });
    setXY(xyFromHue(h, s));
  };

  /* ── derived view values ──────────────────────────────────────── */
  const lead = st.lights[targetsOf(st.target)[0]];
  const pct = Math.round((lead.bri / 254) * 100);
  const kelvin = Math.round(kelvinFromMireds(lead.color.kind === 'ct' ? lead.color.mireds : approxMireds(lead.color)) / 10) * 10;
  const hs = drag ?? (lead.color.kind === 'xy' ? hueSaturationFromXY(lead.color) : { h: 0, s: 0 });
  const thumbRGB = drag ? rgbFromHSV(drag.h, drag.s, 1) : displayRGB(lead.color);
  const thumbLeft = `${50 + Math.cos(hs.h * 2 * Math.PI) * hs.s * 50}%`;
  const thumbTop = `${50 + Math.sin(hs.h * 2 * Math.PI) * hs.s * 50}%`;
  const anyOn = st.lights.some((l) => l.on);
  const pkt = packetFor(st.tab, lead, st.police);
  const offAt = st.timer ? new Date(st.timer.endsAt * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false }) : '';
  const modeName = st.police ? 'Police' : lead.effect !== 'none' ? effectName(lead.effect) : lead.color.kind === 'ct' ? 'White' : 'Color';

  return (
    <section id="playground" className="section pg" ref={root}>
      <div className="section__inner">
        <header className="pg__head">
          <div>
            <p className="eyebrow reveal">[ 04 — Try it ]</p>
            <h2 className="h2 pg__title reveal" data-delay="1">Same controls.<br />No bulbs required.</h2>
          </div>
          <ul className="pg-tags reveal" data-delay="2" aria-label="What is simulated">
            {HEAD_TAGS.map((t) => <li key={t}>{t}</li>)}
          </ul>
        </header>

        <div className="pg-stage">
          {/* Ambient light behind the frame — colour follows the bulbs, breathes slowly */}
          <div className="pg-ambient-wrap" aria-hidden="true">
            <div ref={ambientRef} className={`glow pg-ambient${st.police ? ' is-police' : ''}`} />
          </div>

          <div className="pg-frame" ref={frameRef}>
            {/* ── The room ─────────────────────────────────────────── */}
            <div className="pg-room" aria-hidden="true">
              <div className="pg-room__floor" />
              <div className="pg-room__horizon" />
              {LAMP_POS.map((p, i) => (
                <div
                  key={i}
                  className="pg-lamp"
                  style={{ ['--x' as string]: `${p.x}%`, ['--y' as string]: `${p.y}%` }}
                  ref={(el) => { lampEls.current[i] = el ? { root: el, lastC: '', lastK: -1 } : null; }}
                >
                  <div className="pg-pool" />
                  <div className="pg-glow pg-glow--far" />
                  <div className="pg-glow pg-glow--near" />
                  <div className="pg-cord" />
                  <div className="pg-socket" />
                  <div className="pg-bulb">
                    <div className="pg-bulb__glass" />
                    <div className="pg-bulb__lit" />
                  </div>
                </div>
              ))}
              <div className="pg-room__tags">
                <span className="pg-tag"><i className={`pg-tag__dot${anyOn ? ' is-on' : ''}`} />Sim room</span>
                <span className="pg-tag">2 / 2 connected</span>
              </div>
              <div className="pg-room__readouts">
                <span className="pg-ro"><b>Left</b><span>{describe(st, 0)}</span></span>
                <span className="pg-ro pg-ro--r"><b>Right</b><span>{describe(st, 1)}</span></span>
              </div>
            </div>

            {/* ── Controls ─────────────────────────────────────────── */}
            <div className="pg-panel">
              <div className="pg-block pg-block--top">
                <div className="pg-row">
                  <div className="pg-seg" role="tablist" aria-label="Target">
                    {([['all', 'All'], [0, 'Left'], [1, 'Right']] as [Target, string][]).map(([v, label]) => (
                      <button key={String(v)} type="button" role="tab" aria-selected={st.target === v} className={`pg-seg__btn${st.target === v ? ' is-on' : ''}`} onClick={() => setSt((p) => ({ ...p, target: v }))}>{label}</button>
                    ))}
                  </div>
                  <button type="button" className={`pg-switch${lead.on ? ' is-on' : ''}`} role="switch" aria-checked={lead.on} aria-label="Power" onClick={() => setPower(!lead.on)}>
                    <span className="pg-switch__knob" />
                  </button>
                </div>
                <div className="pg-row pg-row--status">
                  <span className="pg-label">{lead.on ? 'On' : 'Off'}<em>{lead.on ? ` · ${modeName}` : ''}</em></span>
                  <span className="pg-row__end">
                    {st.police && <button type="button" className="pg-mini pg-mini--live" onClick={stopPolice}>Stop</button>}
                    <span className="pg-value">{pct}%</span>
                  </span>
                </div>
                <input className="pg-range" type="range" min={1} max={100} value={pct} aria-label="Brightness"
                  style={{ ['--track' as string]: BRI_TRACK }} onChange={(e) => setBrightness(Number(e.target.value))} />
              </div>

              <div className="pg-block">
                <div className="pg-seg pg-seg--tabs" role="tablist" aria-label="Mode">
                  {([['white', 'White'], ['color', 'Color'], ['effects', 'Effects']] as [Tab, string][]).map(([v, label]) => (
                    <button key={v} type="button" role="tab" aria-selected={st.tab === v} className={`pg-seg__btn${st.tab === v ? ' is-on' : ''}`} onClick={() => setSt((p) => ({ ...p, tab: v }))}>{label}</button>
                  ))}
                </div>

                <div className="pg-pane">
                  {st.tab === 'white' && (
                    <div className="pg-ct">
                      <div className="pg-row"><span className="pg-label">CT</span><span className="pg-value">{kelvin} K <em>· {miredsFromKelvin(kelvin)} mireds</em></span></div>
                      <input className="pg-range" type="range" min={2000} max={6500} step={10} value={kelvin} aria-label="Colour temperature in kelvin"
                        style={{ ['--track' as string]: CT_TRACK }} onChange={(e) => setKelvin(Number(e.target.value))} />
                      <div className="pg-fx pg-fx--ct" role="group" aria-label="Colour temperature presets">
                        {CT_PRESETS.map(([k, name]) => {
                          const on = lead.color.kind === 'ct' && lead.effect === 'none' && Math.abs(kelvin - k) <= 20; // mireds are integers: 6500 K round-trips to 6490
                          return (
                          <button key={k} type="button" aria-pressed={on} className={`pg-fx__cell${on ? ' is-on' : ''}`} onClick={() => setKelvin(k)}>
                            <span className="pg-fx__tag">{name}</span>
                            <span className="pg-fx__name">{k} K</span>
                          </button>
                          );
                        })}
                      </div>
                    </div>
                  )}

                  {st.tab === 'color' && (
                    <div className="pg-colorpane">
                      <div
                        className="pg-wheel"
                        ref={wheelRef}
                        role="slider"
                        aria-label="Colour wheel"
                        aria-valuetext={`hue ${Math.round(hs.h * 360)}°, saturation ${Math.round(hs.s * 100)}%`}
                        tabIndex={0}
                        onPointerDown={(e) => { e.currentTarget.setPointerCapture(e.pointerId); wheelAt(e); }}
                        onPointerMove={(e) => { if (e.buttons & 1) wheelAt(e); }}
                        onPointerUp={() => setDrag(null)}
                        onPointerCancel={() => setDrag(null)}
                      >
                        <div className="pg-wheel__thumb" style={{ left: thumbLeft, top: thumbTop, background: css(thumbRGB) }} />
                      </div>
                      <div className="pg-row pg-row--xy">
                        <span className="pg-label">xy</span>
                        <span className="pg-value">{lead.color.kind === 'xy' ? `${lead.color.x.toFixed(4)}  ${lead.color.y.toFixed(4)}` : '— (CT mode)'}</span>
                      </div>
                    </div>
                  )}

                  {st.tab === 'effects' && (
                    <div className="pg-fxpane">
                      <div className="pg-fx" role="group" aria-label="Effects">
                        {EFFECTS.map((e) => {
                          const on = !st.police && lead.effect === e.id;
                          return (
                            <button key={e.id} type="button" aria-pressed={on} className={`pg-fx__cell${on ? ' is-on' : ''}`} onClick={() => setEffect(e.id)}>
                              <span className="pg-fx__tag">{e.tag.toString(16).padStart(2, '0').toUpperCase()}</span>
                              <span className="pg-fx__name">{e.name}</span>
                            </button>
                          );
                        })}
                        <button type="button" className={`pg-fx__cell pg-fx__cell--police${st.police ? ' is-on is-live' : ''}`} onClick={() => (st.police ? stopPolice() : startPolice())} aria-pressed={!!st.police}>
                          <span className="pg-fx__tag">{st.police ? 'Live' : 'Mac'}</span>
                          <span className="pg-fx__name">Police</span>
                        </button>
                      </div>
                      <div className="pg-mac">
                        <div className="pg-row"><span className="pg-label">Police interval <em className="pg-label__sub">· from this Mac</em></span><span className="pg-value">{st.policeInterval.toFixed(2)} s</span></div>
                        <input className="pg-range pg-range--thin" type="range" min={0.15} max={1} step={0.05} value={st.policeInterval} aria-label="Police interval in seconds"
                          style={{ ['--track' as string]: 'linear-gradient(90deg, rgba(255,255,255,0.35), rgba(255,255,255,0.08))' }}
                          onChange={(e) => { const v = Number(e.target.value); setSt((p) => ({ ...p, policeInterval: v, police: p.police ? { ...p.police, interval: v } : null })); }} />
                      </div>
                    </div>
                  )}
                  <p className="pg-packet" aria-live="off">
                    <span className="pg-packet__k">Write</span>
                    <span className="pg-packet__char">{pkt.char}</span>
                    <span className="pg-packet__arrow">←</span>
                    <span className="pg-packet__bytes">{pkt.bytes}</span>
                    <span className="pg-packet__note">{pkt.note}</span>
                  </p>
                </div>
              </div>

              <div className="pg-block">
                <p className="pg-label pg-label--gap">Scenes</p>
                <div className="pg-scenes">
                  {SCENES.map((sc) => {
                    const cols = sc.palette.map((e) => displayRGB(e.color));
                    const on = st.scene === sc.name;
                    return (
                      <button key={sc.name} type="button" className={`pg-chip${on ? ' is-on' : ''}`} style={{ ['--sw' as string]: rgbList(cols[0]) }} onClick={() => applyScene(sc)} aria-pressed={on}>
                        <span className="pg-chip__sw">{cols.map((c, j) => <i key={j} style={{ ['--sw' as string]: rgbList(c) }} />)}</span>
                        {sc.name}
                      </button>
                    );
                  })}
                </div>
              </div>

              <div className="pg-block pg-block--timer">
                <div className="pg-timer">
                  <div className="pg-timer__dial" aria-hidden="true">
                    <svg viewBox="0 0 52 52" width="52" height="52">
                      <circle cx="26" cy="26" r={RING_R} className="pg-timer__track" />
                      <circle ref={ringRef} cx="26" cy="26" r={RING_R} className="pg-timer__arc" style={{ strokeDasharray: RING_C, strokeDashoffset: st.timer ? undefined : RING_C }} />
                    </svg>
                    <span ref={countRef} className="pg-timer__count">{st.timer ? fmtClock(st.timer.endsAt - Date.now() / 1000) : '00:00'}</span>
                  </div>
                  <div className="pg-timer__body">
                    <p className="pg-label">Timer<em>{st.timer ? ` · off at ${offAt}` : st.timerMode === 'sleep' ? ' · dim → off' : ' · hold → fade → off'}</em></p>
                    <div className="pg-timer__actions">
                      <div className="pg-seg pg-seg--small" role="tablist" aria-label="Timer mode">
                        {([['timer', 'Timer'], ['sleep', 'Sleep']] as [TimerMode, string][]).map(([v, label]) => (
                          <button key={v} type="button" role="tab" aria-selected={st.timerMode === v} className={`pg-seg__btn${st.timerMode === v ? ' is-on' : ''}`} onClick={() => setSt((p) => ({ ...p, timerMode: v, timer: p.timer ? { ...p.timer, mode: v } : null }))}>{label}</button>
                        ))}
                      </div>
                      {st.timer ? (
                        <>
                          <button type="button" className="pg-mini" onClick={() => extendTimer(10)}>+10 s</button>
                          <button type="button" className="pg-mini" onClick={cancelTimer}>Cancel</button>
                        </>
                      ) : (
                        <>
                          <button type="button" className="pg-mini" onClick={() => startTimer(10)}>10 s</button>
                          <button type="button" className="pg-mini" onClick={() => startTimer(30)}>30 s</button>
                          <button type="button" className="pg-mini" onClick={() => startTimer(60)}>1 min</button>
                        </>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <ul className="pg-tags pg-tags--foot reveal" aria-label="In the app">
          {footTags(st.policeInterval).map((t) => <li key={t}>{t}</li>)}
        </ul>
      </div>
    </section>
  );
}
