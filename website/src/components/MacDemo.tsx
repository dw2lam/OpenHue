import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type CSSProperties,
  type PointerEvent as ReactPointerEvent,
  type ReactElement,
  type Ref,
} from 'react';
import { gsap, ScrollTrigger, reducedMotion } from '../lib/gsap';
import { useReveal } from '../hooks/useReveal';
import './macdemo.css';

/* ───────────────────────── colour maths (ported from Models/ColorMath.swift) ───────────────────────── */
type RGB = { r: number; g: number; b: number };
type XY = { x: number; y: number };

const clamp01 = (v: number) => Math.max(0, Math.min(1, v));
const gammaEncode = (c: number) => {
  const v = clamp01(c);
  return v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
};
/** CIE xy → sRGB, normalised so the brightest channel is 1, then scaled by `brightness`. */
function rgbFromXY({ x, y }: XY, brightness = 1): RGB {
  const yy = Math.max(y, 1e-6);
  const Y = 1;
  const X = (Y / yy) * x;
  const Z = (Y / yy) * (1 - x - yy);
  let r = X * 1.656492 - Y * 0.354851 - Z * 0.255038;
  let g = -X * 0.707196 + Y * 1.655397 + Z * 0.036152;
  let b = X * 0.051713 - Y * 0.121364 + Z * 1.01153;
  r = Math.max(0, r); g = Math.max(0, g); b = Math.max(0, b);
  const m = Math.max(r, g, b);
  if (m > 0) { r /= m; g /= m; b /= m; }
  const k = clamp01(brightness);
  return { r: gammaEncode(r * k), g: gammaEncode(g * k), b: gammaEncode(b * k) };
}
/** Black-body sRGB (Tanner Helland's fit) — drives the CT gradient and warm-white swatches. */
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
const kelvinFromMireds = (m: number) => 1_000_000 / Math.max(m, 1);
const miredsFromKelvin = (k: number) => Math.min(500, Math.max(153, Math.round(1_000_000 / Math.max(k, 1))));
/** McCamy CCT of an xy point, as clamped mireds (what the app uses for colour scenes on white bulbs). */
function approxMiredsFromXY({ x, y }: XY) {
  const n = (x - 0.332) / (0.1858 - y);
  const cct = 449 * n ** 3 + 3525 * n ** 2 + 6823.3 * n + 5520.33;
  return Number.isFinite(cct) ? miredsFromKelvin(cct) : 367;
}
const scaleRGB = (c: RGB, k: number): RGB => ({ r: c.r * k, g: c.g * k, b: c.b * k });
const rgbCss = (c: RGB) => `rgb(${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)})`;

/* ───────────────────────── light model (mirrors LightState / Presets.swift) ───────────────────────── */
type LightColor = { kind: 'ct'; mireds: number } | { kind: 'xy'; x: number; y: number };
interface Light { on: boolean; bri: number; color: LightColor }

const briFraction = (bri: number) => Math.max(0, bri - 1) / 253;
const briPercent = (bri: number) => Math.max(1, Math.round(briFraction(bri) * 100));
const briFromPercent = (p: number) => Math.round(1 + (Math.max(0, Math.min(100, p)) / 100) * 253);
const baseRGB = (c: LightColor): RGB => (c.kind === 'ct' ? rgbFromKelvin(kelvinFromMireds(c.mireds)) : rgbFromXY(c));
/** Swatch colour: full-chroma colour dimmed toward 35 % at minimum brightness; dark when off. */
const swatchRGB = (l: Light): RGB => scaleRGB(baseRGB(l.color), l.on ? 0.35 + 0.65 * briFraction(l.bri) : 0.12);
const kelvinOf = (c: LightColor) =>
  Math.min(6500, Math.max(2000, Math.round(kelvinFromMireds(c.kind === 'ct' ? c.mireds : approxMiredsFromXY(c)))));
const describe = (l: Light) =>
  l.on ? `${l.color.kind === 'ct' ? `${kelvinOf(l.color)} K` : 'Color'} · ${briPercent(l.bri)}%` : 'Off';

const white = (bri: number, mireds: number): Light => ({ on: true, bri, color: { kind: 'ct', mireds } });
const xyLight = (x: number, y: number, bri: number): Light => ({ on: true, bri, color: { kind: 'xy', x, y } });

interface Scene { id: string; name: string; glyph: GlyphName; palette: Light[] }
const SCENES: Scene[] = [
  { id: 'bright', name: 'Bright', glyph: 'sun.max', palette: [white(254, 367)] },
  { id: 'dimmed', name: 'Dimmed', glyph: 'sun.min', palette: [white(77, 367)] },
  { id: 'nightlight', name: 'Nightlight', glyph: 'moon', palette: [xyLight(0.561, 0.404, 1)] },
  { id: 'relax', name: 'Relax', glyph: 'cup', palette: [white(144, 447)] },
  { id: 'read', name: 'Read', glyph: 'book', palette: [white(254, 346)] },
  { id: 'concentrate', name: 'Concentrate', glyph: 'brain', palette: [white(254, 233)] },
  { id: 'energize', name: 'Energize', glyph: 'bolt', palette: [white(254, 156)] },
  { id: 'savanna', name: 'Savanna Sunset', glyph: 'sunset', palette: [xyLight(0.644, 0.34, 200), xyLight(0.57, 0.384, 200), xyLight(0.492, 0.428, 200)] },
  { id: 'tropical', name: 'Tropical Twilight', glyph: 'leaf', palette: [xyLight(0.312, 0.133, 180), xyLight(0.405, 0.208, 180), xyLight(0.602, 0.321, 180)] },
  { id: 'arctic', name: 'Arctic Aurora', glyph: 'snowflake', palette: [xyLight(0.164, 0.332, 200), xyLight(0.221, 0.521, 200), xyLight(0.15, 0.1, 200)] },
  { id: 'spring', name: 'Spring Blossom', glyph: 'flower', palette: [xyLight(0.438, 0.27, 210), xyLight(0.354, 0.247, 210), xyLight(0.46, 0.38, 210)] },
];
const sceneById = (id: string) => SCENES.find((s) => s.id === id);

interface SleepTimer { end: number; start: number; sleep: boolean; bri0: number }
interface Demo { lights: Light[]; timer: SleepTimer | null; scene: string | null; connected: boolean }
const LIGHT_NAMES = ['Right', 'Left'];
const INITIAL: Demo = { lights: [white(241, 371), white(241, 371)], timer: null, scene: null, connected: true };

/** Menu("Off in…") entries. The real app offers 5/10/15/30/60/120; 20 is added so the demo lands on "19:59". */
const OFF_IN = [5, 10, 15, 20, 30, 60, 120];
const SLEEP_IN = [15, 30, 45, 60];

function countdownText(seconds: number) {
  const total = Math.max(0, Math.ceil(seconds));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const p = (n: number) => String(n).padStart(2, '0');
  return h > 0 ? `${h}:${p(m)}:${p(s)}` : `${m}:${p(s)}`;
}
const durationText = (min: number) =>
  min < 60 ? `${min} min` : min % 60 === 0 ? `${min / 60} h` : `${Math.floor(min / 60)} h ${min % 60} min`;

const DATE_FMT = new Intl.DateTimeFormat(undefined, { weekday: 'short', day: 'numeric', month: 'short' });
const TIME_FMT = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' });

/* ───────────────────────── SF-Symbol-style glyphs (inline SVG, 16 × 16 box) ───────────────────────── */
type GlyphName =
  | 'bulb.fill' | 'bulb' | 'bulb.2' | 'timer' | 'sun.min' | 'sun.max' | 'moon' | 'moon.zzz' | 'cup' | 'book'
  | 'brain' | 'bolt' | 'sunset' | 'leaf' | 'snowflake' | 'flower' | 'macwindow' | 'wifi' | 'battery' | 'updown';

const BULB = 'M8 1.4c-2.7 0-4.7 2.05-4.7 4.6 0 1.55.75 2.75 1.6 3.65.55.6.95 1.15 1.1 1.85h4c.15-.7.55-1.25 1.1-1.85.85-.9 1.6-2.1 1.6-3.65C12.7 3.45 10.7 1.4 8 1.4z';
const rays = (r0: number, r1: number, n = 8) =>
  Array.from({ length: n }, (_, i) => {
    const a = (i * Math.PI * 2) / n;
    return <line key={i} x1={8 + r0 * Math.cos(a)} y1={8 + r0 * Math.sin(a)} x2={8 + r1 * Math.cos(a)} y2={8 + r1 * Math.sin(a)} />;
  });
const GLYPHS: Record<GlyphName, ReactElement> = {
  'bulb.fill': <g fill="currentColor" stroke="none"><path d={BULB} /><path d="M6.1 12.5h3.8v1a1 1 0 0 1-1 1H7.1a1 1 0 0 1-1-1z" /></g>,
  bulb: <g><path d={BULB} /><path d="M6.2 12.9h3.6M6.6 14.5h2.8" /></g>,
  'bulb.2': <g><path d="M6.4 11.6c-.1-.6-.5-1.1-1-1.6C4.6 9.1 4 8.1 4 6.9 4 4.6 5.8 2.8 8.1 2.8" /><path d="M10.2 3c-2.2 0-3.9 1.7-3.9 3.8 0 1.3.6 2.3 1.3 3 .45.5.8.95.9 1.5h3.4c.1-.55.45-1 .9-1.5.7-.7 1.3-1.7 1.3-3C14.1 4.7 12.4 3 10.2 3z" /><path d="M8.7 12.9h3M9 14.3h2.4" /></g>,
  timer: <g><path d="M10.9 4.1A5.1 5.1 0 1 1 8 3.3" /><path d="M8 1.6v1.7M6.6 1.6h2.8" /><path d="M8 8.4 5.9 6.3" /></g>,
  'sun.min': <g strokeWidth="1.5"><circle cx="8" cy="8" r="2.3" fill="currentColor" stroke="none" />{rays(3.7, 5)}</g>,
  'sun.max': <g strokeWidth="1.5"><circle cx="8" cy="8" r="2.9" />{rays(4.7, 6.7)}</g>,
  moon: <path d="M13.3 10.3A5.7 5.7 0 0 1 5.7 2.7a5.7 5.7 0 1 0 7.6 7.6z" />,
  'moon.zzz': <g fill="currentColor" stroke="none"><path d="M9.6 13.8A5.4 5.4 0 0 1 3.9 6.4a5.4 5.4 0 1 0 5.7 7.4z" /><path d="M9.6 2.2h2.6l-1.8 2h1.8v.9H9.4l1.8-2H9.6zM12.6 5.8h2l-1.3 1.5h1.3v.8h-2.2l1.3-1.5h-1.1z" /></g>,
  cup: <g><path d="M3 5.2h8.2v3.3c0 2.1-1.7 3.8-3.8 3.8h-.6C4.7 12.3 3 10.6 3 8.5z" /><path d="M11.2 6.2h1a1.6 1.6 0 0 1 0 3.2h-1" /><path d="M2 14.3h11" /></g>,
  book: <g><path d="M2.3 3.3c1.9-.9 3.8-.9 5.7.5 1.9-1.4 3.8-1.4 5.7-.5v9.4c-1.9-.9-3.8-.9-5.7.5-1.9-1.4-3.8-1.4-5.7-.5z" /><path d="M8 3.8v9.4" /></g>,
  brain: <g><path d="M5.6 14.6v-2.3C4.2 11.3 3.3 9.7 3.3 7.9 3.3 5 5.6 2.6 8.5 2.6c2.9 0 5.2 2.2 5.2 5l1 1.9c.1.3 0 .5-.3.6l-.7.3v1.5c0 .7-.6 1.3-1.3 1.3h-1.2v1.4" /><path d="M6.6 6.8c.2-1.3 2-1.6 2.6-.5.9-.6 2.1.2 1.9 1.3.9.4.8 1.7-.1 2-.1 1-1.4 1.4-2.1.7-.8.6-2.1 0-2-1-.9-.4-.9-1.7-.3-2.5z" strokeWidth="1.1" /></g>,
  bolt: <path d="M9.2 1.6 3.8 9.1h3.7l-.9 5.3 5.6-7.6H8.5z" />,
  sunset: <g><path d="M2 12.2h12" /><path d="M4.6 12.2a3.4 3.4 0 0 1 6.8 0" /><path d="M8 6.3V4.6M4.3 8.3l-1-1M11.7 8.3l1-1" /><path d="M6.4 2.1 8 3.6l1.6-1.5" /></g>,
  leaf: <g><path d="M13.4 2.6C6.9 2.9 3.2 6.3 3.4 12.1c.1.7.2 1.2.5 1.6C9.7 13.9 13.8 9.5 13.4 2.6z" /><path d="M3.9 13.7c1.2-3.9 3.7-7 7.3-9.2" /></g>,
  snowflake: <g><path d="M8 1.8v12.4M2.6 4.9l10.8 6.2M2.6 11.1l10.8-6.2" /><path d="M6.2 3.4 8 4.6l1.8-1.2M6.2 12.6 8 11.4l1.8 1.2M3.1 7.4l1.9.7.5 1.9M12.9 7.4l-1.9.7-.5 1.9M3.1 8.6l1.9-.7.5-1.9M12.9 8.6l-1.9-.7-.5-1.9" strokeWidth="1.1" /></g>,
  flower: <g><circle cx="8" cy="8" r="1.5" />{Array.from({ length: 5 }, (_, i) => <ellipse key={i} cx="0" cy="-3.9" rx="1.7" ry="2.4" transform={`translate(8 8) rotate(${i * 72})`} />)}</g>,
  macwindow: <g><rect x="1.8" y="3" width="12.4" height="10" rx="2" /><path d="M1.8 6.3h12.4" /></g>,
  wifi: <g><path d="M1.8 6.2a9.2 9.2 0 0 1 12.4 0M4.2 8.8a5.8 5.8 0 0 1 7.6 0M6.5 11.3a2.3 2.3 0 0 1 3 0" /><circle cx="8" cy="13.6" r=".9" fill="currentColor" stroke="none" /></g>,
  battery: <g><rect x="1.2" y="4.4" width="11.6" height="7.2" rx="2" /><path d="M13.9 6.9v2.2" /><rect x="2.7" y="5.9" width="7.4" height="4.2" rx=".8" fill="currentColor" stroke="none" /></g>,
  updown: <path d="M5.3 6.2 8 3.5l2.7 2.7M5.3 9.8 8 12.5l2.7-2.7" strokeWidth="1.6" />,
};
function Glyph({ name, size = 16, className, style }: { name: GlyphName; size?: number; className?: string; style?: CSSProperties }) {
  return (
    <svg className={className} style={style} width={size} height={size} viewBox="0 0 16 16" fill="none" stroke="currentColor"
      strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
      {GLYPHS[name]}
    </svg>
  );
}

/* ───────────────────────── macOS-style controls (real DOM, 1:1 with menubar.png) ───────────────────────── */
const SL_TRACK = 62; // pt, track length inside the 104-pt slider group
const SL_KNOB = 20;  // pt, pill knob width

function Slider({ value, onChange, knobRef, label, disabled }: {
  value: number; onChange: (v: number) => void; knobRef?: Ref<HTMLSpanElement>; label: string; disabled?: boolean;
}) {
  const trackRef = useRef<HTMLDivElement>(null);
  const [drag, setDrag] = useState(false);
  const f = clamp01(value / 100);
  const x = f * (SL_TRACK - SL_KNOB);
  const read = (e: ReactPointerEvent) => {
    const t = trackRef.current; if (!t) return;
    const r = t.getBoundingClientRect();
    const px = ((e.clientX - r.left) / r.width) * SL_TRACK;
    onChange(Math.round(clamp01((px - SL_KNOB / 2) / (SL_TRACK - SL_KNOB)) * 100));
  };
  return (
    <div className={`md-slider${drag ? ' is-drag' : ''}${disabled ? ' is-disabled' : ''}`} role="slider" aria-label={label}
      aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(value)} tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') { e.preventDefault(); onChange(Math.max(0, value - 5)); }
        if (e.key === 'ArrowRight' || e.key === 'ArrowUp') { e.preventDefault(); onChange(Math.min(100, value + 5)); }
      }}>
      <Glyph name="sun.min" size={12} className="md-slider__min" />
      <div className="md-slider__track" ref={trackRef}
        onPointerDown={(e) => { e.preventDefault(); e.currentTarget.setPointerCapture(e.pointerId); setDrag(true); read(e); }}
        onPointerMove={(e) => { if (drag) read(e); }}
        onPointerUp={() => setDrag(false)} onPointerCancel={() => setDrag(false)}>
        <span className="md-slider__fill" style={{ transform: `scaleX(${(x + SL_KNOB / 2) / SL_TRACK})` }} />
        <span className="md-slider__knob" ref={knobRef} style={{ transform: `translateX(${x}px)` }} />
      </div>
      <Glyph name="sun.max" size={14} className="md-slider__max" />
    </div>
  );
}

function Switch({ on, onChange, label, size }: { on: boolean; onChange: (v: boolean) => void; label: string; size?: 'regular' }) {
  return (
    <button type="button" role="switch" aria-checked={on} aria-label={label}
      className={`md-sw${on ? ' is-on' : ''}${size === 'regular' ? ' md-sw--regular' : ''}`} onClick={() => onChange(!on)}>
      <span className="md-sw__knob" />
    </button>
  );
}

/* ───────────────────────── stage geometry ───────────────────────── */
const STAGE = { w: 1280, h: 800 };
const COMPACT = { w: 420, h: 560 };
const POP_W = 340;
/** The window capture (2584 × 1784 with its shadow margin; opaque window rect 2360 × 1560 at 112, 76). */
const CAP = { w: 2584, h: 1784, winX: 112, winY: 76, winW: 2360 };
const WIN_W = 880;                                 // window rect width on the stage
const IMG_W = WIN_W / (CAP.winW / CAP.w);          // image box width
const IMG_H = IMG_W * (CAP.h / CAP.w);
const IMG_LEFT = 40 - (CAP.winX / CAP.w) * IMG_W;
const IMG_TOP = 58 - (CAP.winY / CAP.h) * IMG_H;
const fx = (px: number) => (px / CAP.w) * IMG_W;   // capture px → stage px
const fy = (px: number) => (px / CAP.h) * IMG_H;
const CARD = 'rgb(38,40,41)';

/** Live overlays on the real window capture — positions measured from all-lights-white.png. */
function WindowOverlay({ lights, all }: { lights: Light[]; all: Light }) {
  const ctK = kelvinOf(all.color);
  const ctF = clamp01((ctK - 2000) / 4500);
  const briF = briFraction(all.bri);
  const patch = (x0: number, y0: number, x1: number, y1: number, extra?: CSSProperties): CSSProperties => ({
    position: 'absolute', left: fx(x0), top: fy(y0), width: fx(x1 - x0), height: fy(y1 - y0), background: CARD, ...extra,
  });
  const dot = (cx: number, cy: number, d: number, l: Light) => (
    <span className="md-win__dot" style={{ left: fx(cx - d / 2), top: fy(cy - d / 2), width: fx(d), height: fx(d), background: rgbCss(swatchRGB(l)) }} />
  );
  const toggle = (x0: number, y0: number, w: number, h: number, on: boolean, key: string) => (
    <span key={key} className={`md-win__sw${on ? ' is-on' : ''}`} style={{ left: fx(x0), top: fy(y0), width: fx(w), height: fy(h) }}>
      <span className="md-win__swknob" style={{ width: fx(w * 0.59), height: fy(h - 8), margin: fy(4), transform: `translateX(${on ? fx(w - w * 0.59 - 8) : 0}px)` }} />
    </span>
  );
  /** Pill knob: `x0` is the travel origin (layout), `dx` the travel (transform) — both in capture px. */
  const pill = (x0: number, dx: number, cy: number) => (
    <span className="md-win__pill" style={{ left: fx(x0 - 19.5), top: fy(cy - 15.5), width: fx(39), height: fy(31), transform: `translateX(${fx(dx)}px)` }} />
  );
  return (
    <div className="md-win__ov" style={{ fontSize: fx(22) }}>
      {/* sidebar + Lights-list colour dots */}
      {dot(543.5, 313.5, 24, lights[0])}
      {dot(543.5, 377.5, 24, lights[1])}
      {dot(889.5, 1279.5, 32, lights[0])}
      {dot(889.5, 1353.5, 32, lights[1])}
      {/* power card readout */}
      <div style={patch(922, 388, 1300, 462)} />
      <div className="md-win__t md-win__t--title" style={{ left: fx(928), top: fy(392), fontSize: fx(26) }}>{all.on ? 'On' : 'Off'}</div>
      <div className="md-win__t md-win__t--dim" style={{ left: fx(928), top: fy(428) }}>{describe(all)}</div>
      {toggle(2090, 394, 127, 55, all.on, 'power')}
      {/* colour-temperature slider (patch first: the captured thumb ring is taller than the track) */}
      <div style={patch(836, 676, 2224, 752)} />
      <div className="md-win__ct" style={{ left: fx(850), top: fy(690), width: fx(1359), height: fy(51) }}>
        <span className="md-win__ctknob" style={{ width: fx(59), height: fx(59), marginTop: -fx(29.5), borderWidth: fx(6), transform: `translateX(${fx(0.5 + ctF * 1299)}px)` }} />
      </div>
      <div style={patch(1400, 758, 1660, 792)} />
      <div className="md-win__t md-win__t--bold" style={{ left: fx(1400), width: fx(260), top: fy(761), textAlign: 'center' }}>{ctK} K</div>
      {/* brightness slider */}
      <div style={patch(870, 928, 2115, 976)} />
      <div className="md-win__bri" style={{ left: fx(879), top: fy(945.5), width: fx(1194), height: fy(12) }}>
        <span className="md-win__brifill" style={{ transform: `scaleX(${(19.5 + briF * 1155) / 1194})` }} />
      </div>
      {pill(898.5, briF * 1155, 951.5)}
      <div style={patch(2130, 930, 2250, 974)} />
      <div className="md-win__t md-win__t--dim" style={{ left: fx(2130), width: fx(120), top: fy(941), textAlign: 'center' }}>{briPercent(all.bri)}%</div>
      {/* per-light rows */}
      {lights.map((l, i) => {
        const cy = i === 0 ? 1279.5 : 1353.5;
        const f = briFraction(l.bri);
        return (
          <div key={i}>
            <div style={patch(1822, cy - 22, 2100, cy + 22)} />
            <div className="md-win__bri" style={{ left: fx(1831), top: fy(cy - 6), width: fx(242), height: fy(12) }}>
              <span className="md-win__brifill" style={{ transform: `scaleX(${(19.5 + f * 203.4) / 242})` }} />
            </div>
            {pill(1850.5, f * 203.4, cy)}
            {toggle(2134, cy - 19.5, 87, 39, l.on, `row${i}`)}
          </div>
        );
      })}
    </div>
  );
}

/** Layout position of `el` inside `stage` (unaffected by the CSS transforms on the stage/frame). */
function stageRect(el: HTMLElement, stage: HTMLElement) {
  let x = 0, y = 0;
  let n: HTMLElement | null = el;
  while (n && n !== stage) { x += n.offsetLeft; y += n.offsetTop; n = n.offsetParent as HTMLElement | null; }
  let p = el.parentElement;
  while (p && p !== stage) { x -= p.scrollLeft; y -= p.scrollTop; p = p.parentElement; }
  return { x, y, w: el.offsetWidth, h: el.offsetHeight };
}
const wait = (s: number) => new Promise<void>((r) => window.setTimeout(r, s * 1000));
const nextPaint = () => new Promise<void>((r) => requestAnimationFrame(() => requestAnimationFrame(() => r())));
const press = (el?: HTMLElement | null) => {
  if (!el) return;
  el.classList.add('is-pressed');
  window.setTimeout(() => el.classList.remove('is-pressed'), 170);
};

/* ───────────────────────── the section ───────────────────────── */
export default function MacDemo() {
  const root = useReveal<HTMLElement>(0.1);
  const sceneRef = useRef<HTMLDivElement>(null);
  const driftRef = useRef<HTMLDivElement>(null);
  const tiltRef = useRef<HTMLDivElement>(null);
  const frameRef = useRef<HTMLDivElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const wallRef = useRef<HTMLDivElement>(null);
  const glowRef = useRef<HTMLDivElement>(null);
  const bulbRef = useRef<HTMLButtonElement>(null);
  const popRef = useRef<HTMLDivElement>(null);
  const chipsRef = useRef<HTMLDivElement>(null);
  const chipRefs = useRef<Record<string, HTMLButtonElement | null>>({});
  const menuRefs = useRef<Record<number, HTMLButtonElement | null>>({});
  const offInRef = useRef<HTMLButtonElement>(null);
  const allKnobRef = useRef<HTMLSpanElement>(null);
  const cursorRef = useRef<SVGSVGElement>(null);

  const [demo, setDemo] = useState<Demo>(INITIAL);
  const demoRef = useRef(demo); demoRef.current = demo;
  const [open, setOpen] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [auto, setAuto] = useState(false);
  const [drag, setDrag] = useState(false);
  const [compact, setCompact] = useState(false);
  const [scale, setScale] = useState(1);
  const [popLeft, setPopLeft] = useState(869);
  const [now, setNow] = useState(() => Date.now());
  const runId = useRef(0);
  const played = useRef(false);
  const wallTween = useRef({ a: 0, b: 0, c: 0, d: 0, e: 0, f: 0, amb: 0, init: false });

  const SW = compact ? COMPACT.w : STAGE.w;
  const SH = compact ? COMPACT.h : STAGE.h;

  /* ── state actions (stable) ── */
  const setAllBrightness = useCallback((pct: number) => {
    const bri = briFromPercent(pct);
    setDemo((d) => ({ ...d, scene: null, lights: d.lights.map((l) => ({ ...l, bri })) }));
  }, []);
  const setAllPower = useCallback((on: boolean) => setDemo((d) => ({ ...d, lights: d.lights.map((l) => ({ ...l, on })) })), []);
  const setLightBrightness = useCallback((i: number, pct: number) => {
    const bri = briFromPercent(pct);
    setDemo((d) => ({ ...d, scene: null, lights: d.lights.map((l, j) => (j === i ? { ...l, bri } : l)) }));
  }, []);
  const setLightPower = useCallback((i: number, on: boolean) =>
    setDemo((d) => ({ ...d, lights: d.lights.map((l, j) => (j === i ? { ...l, on } : l)) })), []);
  const applyScene = useCallback((id: string) => {
    const s = sceneById(id); if (!s) return;
    setDemo((d) => ({ ...d, scene: id, lights: d.lights.map((_, i) => ({ ...s.palette[i % s.palette.length] })) }));
  }, []);
  const startTimer = useCallback((minutes: number, sleep: boolean) => {
    const start = Date.now();
    setDemo((d) => {
      const on = d.lights.filter((l) => l.on);
      const bri0 = on.length ? Math.round(on.reduce((a, l) => a + l.bri, 0) / on.length) : 254;
      return { ...d, timer: { start, end: start + minutes * 60_000, sleep, bri0 } };
    });
  }, []);
  const cancelTimer = useCallback(() => setDemo((d) => ({ ...d, timer: null })), []);
  const toggleConnection = useCallback(() => setDemo((d) => ({ ...d, connected: !d.connected })), []);

  /* ── derived ── */
  const { lights, timer } = demo;
  const onLights = lights.filter((l) => l.on);
  const anyOn = onLights.length > 0;
  const allBri = onLights.length ? Math.round(onLights.reduce((a, l) => a + l.bri, 0) / onLights.length) : lights[0].bri;
  const all: Light = { on: anyOn, bri: allBri, color: lights[0].color };
  const allPct = briPercent(allBri);
  // `now` is refreshed at 1 Hz, so clamp to the timer's length or a fresh 1 h timer would read 1:00:01
  const remaining = timer ? Math.min((timer.end - now) / 1000, (timer.end - timer.start) / 1000) : 0;

  /* ── one rAF: clock + countdown (1 Hz re-render), sleep-mode dimming, timer firing ── */
  useEffect(() => {
    let raf = 0, last = -1;
    const loop = () => {
      const t = Date.now();
      const sec = Math.floor(t / 1000);
      if (sec !== last) {
        last = sec;
        setNow(t);
        const d = demoRef.current;
        if (d.timer) {
          if (t >= d.timer.end) {
            setDemo((x) => ({ ...x, timer: null, lights: x.lights.map((l) => ({ ...l, on: false })) }));
          } else if (d.timer.sleep) {
            const k = (d.timer.end - t) / (d.timer.end - d.timer.start);
            const bri = Math.max(1, Math.round(d.timer.bri0 * k));
            setDemo((x) => ({ ...x, lights: x.lights.map((l) => (l.on ? { ...l, bri } : l)) }));
          }
        }
      }
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, []);

  /* ── layout: compact media query, stage scale, popover anchor under the bulb item ── */
  useLayoutEffect(() => {
    const mq = window.matchMedia('(max-width: 720px)');
    const apply = () => setCompact(mq.matches);
    apply();
    mq.addEventListener('change', apply);
    return () => mq.removeEventListener('change', apply);
  }, []);
  useLayoutEffect(() => {
    const frame = frameRef.current; if (!frame) return;
    const ro = new ResizeObserver(([e]) => setScale(e.contentRect.width / SW));
    ro.observe(frame);
    return () => ro.disconnect();
  }, [SW]);
  useLayoutEffect(() => {
    const place = () => {
      const stage = stageRef.current, bulb = bulbRef.current; if (!stage || !bulb) return;
      const r = stageRect(bulb, stage);
      setPopLeft(Math.round(Math.min(Math.max(r.x + r.w / 2 - POP_W / 2, 8), SW - POP_W - 8)));
    };
    place();
    let alive = true;
    document.fonts?.ready.then(() => { if (alive) place(); });
    return () => { alive = false; };
  }, [SW]);

  /* ── wallpaper + ambient glow follow the light state (tweened, transform/opacity/vars only) ── */
  const c0 = rgbCss(baseRGB(lights[0].color)), c1 = rgbCss(baseRGB(lights[1].color));
  const amb = anyOn ? 0.22 + 0.78 * briFraction(allBri) : 0;
  useEffect(() => {
    const wall = wallRef.current, glow = glowRef.current; if (!wall || !glow) return;
    const cur = wallTween.current;
    const parse = (s: string) => s.match(/\d+/g)!.map(Number);
    const [a, b, c] = parse(c0), [d, e, f] = parse(c1);
    const write = () => {
      wall.style.setProperty('--md-c1', `rgb(${cur.a | 0},${cur.b | 0},${cur.c | 0})`);
      wall.style.setProperty('--md-c2', `rgb(${cur.d | 0},${cur.e | 0},${cur.f | 0})`);
      wall.style.setProperty('--md-amb', cur.amb.toFixed(3));
      glow.style.setProperty('--glow', `rgb(${cur.a | 0},${cur.b | 0},${cur.c | 0})`);
      glow.style.opacity = (0.62 * cur.amb).toFixed(3);
    };
    gsap.killTweensOf(cur);
    gsap.to(cur, { a, b, c, d, e, f, amb, duration: !cur.init || reducedMotion() ? 0 : 1.3, ease: 'power2.out', onUpdate: write, onComplete: write });
    cur.init = true;
  }, [c0, c1, amb]);

  /* ── scroll drift (scrubbed) + cursor tilt ── */
  useEffect(() => {
    if (reducedMotion()) return;
    const scene = sceneRef.current, drift = driftRef.current, tilt = tiltRef.current;
    if (!scene || !drift || !tilt) return;
    const tw = gsap.fromTo(drift, { rotationX: 7, y: 36 }, {
      rotationX: -3, y: -24, ease: 'none',
      scrollTrigger: { trigger: scene, start: 'top bottom', end: 'bottom top', scrub: 0.8 },
    });
    let dispose = () => {};
    if (window.matchMedia('(hover: hover) and (pointer: fine)').matches) {
      const rx = gsap.quickTo(tilt, 'rotationX', { duration: 1.2, ease: 'power3.out' });
      const ry = gsap.quickTo(tilt, 'rotationY', { duration: 1.2, ease: 'power3.out' });
      const move = (e: PointerEvent) => {
        const r = scene.getBoundingClientRect();
        ry((((e.clientX - r.left) / r.width) * 2 - 1) * 2.2);
        rx(-(((e.clientY - r.top) / r.height) * 2 - 1) * 1.6);
      };
      const leave = () => { rx(0); ry(0); };
      scene.addEventListener('pointermove', move);
      scene.addEventListener('pointerleave', leave);
      dispose = () => { scene.removeEventListener('pointermove', move); scene.removeEventListener('pointerleave', leave); };
    }
    return () => { tw.scrollTrigger?.kill(); tw.kill(); dispose(); };
  }, []);

  /* ── click outside (inside the desktop) closes the popover / the Off in… menu; Escape too ── */
  useEffect(() => {
    if (!open || auto) return;
    const stage = stageRef.current; if (!stage) return;
    const down = (e: PointerEvent) => {
      const t = e.target as Node;
      if (bulbRef.current?.contains(t)) return;
      if (popRef.current?.contains(t)) { if (!(t as HTMLElement).closest?.('.md-menu-wrap')) setMenuOpen(false); return; }
      setOpen(false); setMenuOpen(false);
    };
    const key = (e: KeyboardEvent) => { if (e.key === 'Escape') { if (menuOpen) setMenuOpen(false); else setOpen(false); } };
    stage.addEventListener('pointerdown', down);
    window.addEventListener('keydown', key);
    return () => { stage.removeEventListener('pointerdown', down); window.removeEventListener('keydown', key); };
  }, [open, auto, menuOpen]);

  /* ── the scripted autoplay ── */
  const play = useCallback(async () => {
    const id = ++runId.current;
    const alive = () => runId.current === id && !!stageRef.current;
    const stage = stageRef.current, cur = cursorRef.current;
    if (!stage || !cur) return;
    gsap.killTweensOf(cur);
    if (chipsRef.current) gsap.killTweensOf(chipsRef.current);
    setDemo(INITIAL); setOpen(false); setMenuOpen(false); setDrag(false);
    if (reducedMotion()) {
      // No choreography: land on the final state with the popover open and the countdown ticking.
      applyScene('relax'); startTimer(20, false); setOpen(true); setAuto(false);
      return;
    }
    setAuto(true);
    await nextPaint(); if (!alive()) return;
    const at = (el: HTMLElement | null | undefined, fxr = 0.5, fyr = 0.5) => {
      if (!el) return null;
      const r = stageRect(el, stage);
      return { x: r.x + r.w * fxr, y: r.y + r.h * fyr };
    };
    const moveTo = async (p: { x: number; y: number } | null, d: number) => {
      if (!p) return;
      await gsap.to(cur, { x: p.x, y: p.y, duration: d, ease: 'power2.inOut' });
    };
    const tap = async () => { await gsap.to(cur, { scale: 0.84, duration: 0.07, yoyo: true, repeat: 1, ease: 'power1.inOut' }); };
    const revealChip = (chip: HTMLElement) => {
      const row = chipsRef.current; if (!row) return Promise.resolve();
      const target = Math.max(0, Math.min(row.scrollWidth - row.clientWidth, chip.offsetLeft + chip.offsetWidth / 2 - row.clientWidth / 2));
      return gsap.to(row, { scrollLeft: target, duration: 0.85, ease: 'power2.inOut' }).then(() => undefined);
    };

    gsap.set(cur, { x: compact ? 90 : 470, y: compact ? 400 : 470, opacity: 0, scale: 1 });
    await gsap.to(cur, { opacity: 1, duration: 0.45, ease: 'power1.out' });
    await wait(0.15); if (!alive()) return;

    // 1 · the menu-bar bulb
    await moveTo(at(bulbRef.current, 0.5, 0.56), 1.15); if (!alive()) return;
    await tap(); setOpen(true);
    await wait(0.95); if (!alive()) return;

    // 2 · Savanna Sunset (the row scrolls under the pointer, then the chip is clicked)
    const savanna = chipRefs.current.savanna;
    if (savanna) {
      await Promise.all([revealChip(savanna), moveTo(at(chipsRef.current, 0.55, 0.5), 0.85)]);
      if (!alive()) return;
      await moveTo(at(savanna), 0.55); if (!alive()) return;
      await tap(); press(savanna); applyScene('savanna');
    }
    await wait(1.15); if (!alive()) return;

    // 3 · drag All Lights brightness 95 % → 60 %
    const knob = allKnobRef.current;
    if (knob) {
      // the knob is positioned by a transform, which layout offsets don't see — add its travel by hand
      const p0 = briPercent(demoRef.current.lights[0].bri);
      const kp = at(knob);
      await moveTo(kp && { x: kp.x + (p0 / 100) * (SL_TRACK - SL_KNOB), y: kp.y }, 0.8); if (!alive()) return;
      await gsap.to(cur, { scale: 0.86, duration: 0.08 });
      setDrag(true);
      const v = { p: p0 };
      const x0 = gsap.getProperty(cur, 'x') as number;
      const dx = ((60 - p0) / 100) * (SL_TRACK - SL_KNOB);
      await Promise.all([
        gsap.to(cur, { x: x0 + dx, duration: 0.95, ease: 'power2.inOut' }),
        gsap.to(v, { p: 60, duration: 0.95, ease: 'power2.inOut', onUpdate: () => setAllBrightness(Math.round(v.p)) }),
      ]);
      setDrag(false);
      await gsap.to(cur, { scale: 1, duration: 0.1 });
    }
    await wait(0.55); if (!alive()) return;

    // 4 · Off in… → 20 min
    await moveTo(at(offInRef.current, 0.45, 0.5), 0.75); if (!alive()) return;
    await tap(); press(offInRef.current); setMenuOpen(true);
    await nextPaint(); await wait(0.35); if (!alive()) return;
    await moveTo(at(menuRefs.current[20], 0.3, 0.5), 0.6); if (!alive()) return;
    await tap(); press(menuRefs.current[20]);
    startTimer(20, false); setMenuOpen(false);
    await wait(1.4); if (!alive()) return;

    // 5 · Relax
    const relax = chipRefs.current.relax;
    if (relax) {
      await Promise.all([revealChip(relax), moveTo(at(chipsRef.current, 0.4, 0.5), 0.75)]);
      if (!alive()) return;
      await moveTo(at(relax), 0.5); if (!alive()) return;
      await tap(); press(relax); applyScene('relax');
    }
    await wait(0.9); if (!alive()) return;

    // 6 · ease away; the visitor's own pointer takes over
    await moveTo(compact ? { x: 60, y: 500 } : { x: 1030, y: 700 }, 1.1);
    await gsap.to(cur, { opacity: 0, duration: 0.45 });
    if (alive()) setAuto(false);
  }, [applyScene, startTimer, setAllBrightness, compact]);

  useEffect(() => {
    const scene = sceneRef.current; if (!scene || played.current) return;
    const go = () => { played.current = true; void play(); };
    if (reducedMotion()) { go(); return; }
    const st = ScrollTrigger.create({ trigger: scene, start: 'top 62%', once: true, onEnter: go });
    return () => st.kill();
  }, [play]);
  useEffect(() => () => {
    runId.current++;
    if (cursorRef.current) gsap.killTweensOf(cursorRef.current);
    if (chipsRef.current) gsap.killTweensOf(chipsRef.current);
    gsap.killTweensOf(wallTween.current);
  }, []);

  /* ── render ── */
  const clock = `${DATE_FMT.format(now).replace(",", "")}  ${TIME_FMT.format(now)}`;
  const status = demo.connected ? `${lights.length}/${lights.length} connected` : `0/${lights.length} connected`;
  const stageStyle: CSSProperties = { width: SW, height: SH, transform: `scale(${scale})` };

  return (
    <section id="desktop" className="section md" ref={root}>
      <div className="section__inner">
        <header className="md-head">
          <p className="eyebrow reveal">[ 02 — IN THE MENU BAR ]</p>
          <h2 className="display md-title reveal" data-delay="1">Lives in your menu bar.</h2>
          <p className="md-tag reveal" data-delay="2">One click · brightness · scenes · off in 20 min</p>
        </header>

        <div className="md-scene reveal" data-delay="2" ref={sceneRef}>
          <div className="glow md-glow" ref={glowRef} aria-hidden="true" />
          <div className="md-drift" ref={driftRef}>
            <div className="md-tilt" ref={tiltRef}>
              <div className={`md-frame${auto ? ' is-auto' : ''}${compact ? ' md-frame--compact' : ''}`} ref={frameRef} style={{ aspectRatio: `${SW} / ${SH}` }}>
                <div className={`md-stage${compact ? ' md-stage--compact' : ''}${auto ? ' md-stage--auto' : ''}${drag ? ' is-dragging' : ''}`}
                  ref={stageRef} style={stageStyle}>
                  {/* wallpaper */}
                  <div className="md-wall" ref={wallRef} aria-hidden="true">
                    <span className="md-wall__blob md-wall__blob--a" />
                    <span className="md-wall__blob md-wall__blob--b" />
                    <span className="md-wall__blob md-wall__blob--c" />
                    <span className="md-wall__blob md-wall__blob--d" />
                    <span className="md-wall__vignette" />
                  </div>

                  {/* the real OpenHue window with live overlays */}
                  {!compact && (
                    <div className="md-win" style={{ left: IMG_LEFT, top: IMG_TOP, width: IMG_W, height: IMG_H }}>
                      <img src="/macdemo/window.webp" width={1800} height={1243} alt="OpenHue main window — All Lights view"
                        loading="lazy" decoding="async" draggable={false} />
                      <WindowOverlay lights={lights} all={all} />
                    </div>
                  )}

                  {/* dock */}
                  {!compact && (
                    <div className="md-dock" aria-hidden="true">
                      <span className="md-dock__tile md-dock__tile--1" />
                      <span className="md-dock__tile md-dock__tile--2" />
                      <span className="md-dock__tile md-dock__tile--3" />
                      <span className="md-dock__tile md-dock__tile--4" />
                      <span className="md-dock__tile md-dock__tile--5" />
                      <span className="md-dock__sep" />
                      <span className="md-dock__tile md-dock__tile--hue"><Glyph name="bulb.fill" size={22} /></span>
                    </div>
                  )}

                  {/* menu bar */}
                  <div className="md-bar">
                    <div className="md-bar__l">
                      <span className="md-bar__app">OpenHue</span>
                      <span>File</span><span>Edit</span><span>View</span><span>Window</span><span>Help</span>
                    </div>
                    <div className="md-bar__r">
                      <button type="button" ref={bulbRef} className={`md-bar__item md-bar__bulb${open ? ' is-on' : ''}`}
                        aria-label="OpenHue menu bar extra" aria-expanded={open} aria-controls="md-popover"
                        onClick={() => { setOpen((o) => !o); setMenuOpen(false); }}>
                        <Glyph name="bulb" size={17} />
                      </button>
                      <span className="md-bar__item"><Glyph name="wifi" size={16} /></span>
                      <span className="md-bar__item md-bar__battery"><Glyph name="battery" size={17} /></span>
                      <span className="md-bar__item md-bar__clock">{clock}</span>
                    </div>
                  </div>

                  {/* the menu-bar extra, 1:1 with menubar.png */}
                  <div id="md-popover" className={`md-pop${open ? ' is-open' : ''}`} ref={popRef} style={{ left: popLeft }}
                    role="dialog" aria-label="OpenHue menu bar extra" aria-hidden={!open}>
                    <div className="md-pop__head">
                      <Glyph name="bulb.fill" size={16} className="md-pop__bulb" />
                      <span className="md-pop__title">OpenHue</span>
                      <span className="md-pop__status">{status}</span>
                    </div>

                    <div className={`md-row${demo.connected ? '' : ' is-dim'}`}>
                      <Glyph name="bulb.2" size={16} className="md-row__glyph" />
                      <span className="md-row__label md-row__label--med">All Lights</span>
                      <span className="md-spacer" />
                      <Slider value={allPct} onChange={setAllBrightness} knobRef={allKnobRef} label="All Lights brightness" disabled={!demo.connected} />
                      <Switch on={anyOn} onChange={setAllPower} label="All Lights" />
                    </div>

                    <div className="md-row">
                      <Glyph name="timer" size={16} className="md-row__glyph" />
                      <span className="md-row__label md-row__label--med">Timer</span>
                      <span className="md-spacer" />
                      {timer ? (
                        <>
                          {timer.sleep && <Glyph name="moon.zzz" size={12} className="md-row__moon" />}
                          <span className="md-count" aria-live="off">{countdownText(remaining)}</span>
                          <button type="button" className="md-btn" onClick={cancelTimer}>Cancel</button>
                        </>
                      ) : (
                        <div className="md-menu-wrap">
                          <button type="button" ref={offInRef} className="md-offin" aria-haspopup="menu" aria-expanded={menuOpen}
                            onClick={() => setMenuOpen((m) => !m)}>
                            Off in… <Glyph name="updown" size={9} className="md-offin__chev" />
                          </button>
                          <div className={`md-menu${menuOpen ? ' is-open' : ''}`} role="menu" aria-hidden={!menuOpen}>
                            {OFF_IN.map((m) => (
                              <button type="button" key={m} role="menuitem" className="md-menu__item"
                                ref={(el) => { menuRefs.current[m] = el; }}
                                onClick={() => { startTimer(m, false); setMenuOpen(false); }}>{durationText(m)}</button>
                            ))}
                            <span className="md-menu__sep" />
                            <span className="md-menu__title">Sleep in…</span>
                            {SLEEP_IN.map((m) => (
                              <button type="button" key={`s${m}`} role="menuitem" className="md-menu__item"
                                onClick={() => { startTimer(m, true); setMenuOpen(false); }}>{durationText(m)}</button>
                            ))}
                          </div>
                        </div>
                      )}
                    </div>

                    <span className="md-div" />

                    <div className="md-lights">
                      {lights.map((l, i) => (
                        <div className={`md-row md-row--light${demo.connected ? '' : ' is-dim'}`} key={i}>
                          <span className={`md-dot md-dot--conn${demo.connected ? ' is-on' : ''}`} />
                          <span className="md-dot md-dot--light" style={{ background: rgbCss(swatchRGB(l)) }} />
                          <span className="md-row__label">{LIGHT_NAMES[i]}</span>
                          <span className="md-spacer" />
                          <Slider value={briPercent(l.bri)} onChange={(v) => setLightBrightness(i, v)} label={`${LIGHT_NAMES[i]} brightness`} disabled={!demo.connected} />
                          <Switch on={l.on} onChange={(v) => setLightPower(i, v)} label={LIGHT_NAMES[i]} />
                        </div>
                      ))}
                    </div>

                    <span className="md-div" />

                    <div className="md-chips" ref={chipsRef}>
                      {SCENES.map((s) => (
                        <button type="button" key={s.id} className={`md-chip${demo.scene === s.id ? ' is-active' : ''}`}
                          ref={(el) => { chipRefs.current[s.id] = el; }} onClick={() => applyScene(s.id)}>
                          <span className="md-chip__dot" style={{ background: rgbCss(swatchRGB(s.palette[0])) }} />
                          <Glyph name={s.glyph} size={12} className="md-chip__glyph" />
                          <span className="md-chip__name">{s.name}</span>
                        </button>
                      ))}
                    </div>

                    <span className="md-div" />

                    <div className="md-foot">
                      <button type="button" className="md-open"><Glyph name="macwindow" size={16} />Open OpenHue</button>
                      <div className="md-foot__row">
                        <button type="button" className="md-btn" onClick={toggleConnection}>{demo.connected ? 'Disconnect All' : 'Reconnect All'}</button>
                        <span className="md-spacer" />
                        <button type="button" className="md-btn">Settings…</button>
                        <button type="button" className="md-btn">Quit</button>
                      </div>
                    </div>
                  </div>

                  {/* the drawn pointer used by the autoplay */}
                  <svg className="md-cursor" ref={cursorRef} width="22" height="30" viewBox="0 0 22 30" aria-hidden="true">
                    <path d="M2 2v21.2l5.6-5.2 3.6 8.4 3.8-1.7-3.6-8.1h7.6z" fill="#000" stroke="#fff" strokeWidth="1.7" strokeLinejoin="round" />
                  </svg>
                </div>
              </div>
            </div>
          </div>

          <div className="md-toolbar">
            <span className="md-live"><span className="md-live__dot" />Live — real clock, real countdown</span>
            <button type="button" className="md-replay" onClick={() => { void play(); }}>↻ Replay</button>
          </div>
        </div>
      </div>
    </section>
  );
}
