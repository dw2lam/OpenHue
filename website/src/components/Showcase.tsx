import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { gsap, ScrollTrigger, reducedMotion } from '../lib/gsap';
import { useReveal } from '../hooks/useReveal';
import { shots as S, type Shot } from '../shots';
import {
  Frame, LiveBadge, LiveCt, LiveDial, LiveDot, LiveFade, LiveHighlights, LivePolice, LiveText, LiveToggle, LiveWheel,
  MENU, PoliceGlow, SceneGlow, WAKE, WIN, armed, attachTilt, countdown, mmss, rightOn, rssi, sceneIdx,
} from './live';
import './showcase.css';

type Chapter = {
  rail: string;
  title: string;
  line: string;
  tags: readonly [string, string];
  /** CSS colour for the ambient glow, or a live glow kind */
  glow: string;
  card: Shot;
  cardLive: ReactNode;
  detail: Shot;
  detailLive: ReactNode;
};

const menuCountdown = (t: number) => mmss(countdown(t).rem);
const dBm = (i: number) => (t: number) => `· ${rssi(t, i)} dBm`;

const CHAPTERS: readonly Chapter[] = [
  {
    rail: 'Lights', title: 'Colour, warmth, brightness', line: 'Per bulb or all at once — instant over BLE.',
    tags: ['xy · 2000–6500 K', 'All Lights'], glow: 'var(--hue-warm)',
    card: S.allLightsColor,
    cardLive: <><LiveWheel s={S.allLightsColor} />{WIN.sidebarDots.map((r, i) => <LiveDot key={i} s={S.allLightsColor} r={r} mode="hue" />)}</>,
    detail: S.ctCard, detailLive: <LiveCt s={S.ctCard} />,
  },
  {
    rail: 'Scenes', title: 'Eleven Hue scenes', line: 'Bright to Spring Blossom, plus your own snapshots.',
    tags: ['stock scenes', 'save current as scene'], glow: 'scene',
    card: S.scenes, cardLive: <LiveHighlights s={S.scenes} rects={WIN.sceneCards} radius={16} active={sceneIdx} />,
    detail: S.sceneChips, detailLive: <LiveHighlights s={S.sceneChips} rects={WIN.chips} radius={28} active={(t) => { const i = sceneIdx(t); return i < 6 ? i : -1; }} />,
  },
  {
    rail: 'Effects', title: 'Candle, Fireplace, Police', line: 'Ten on-bulb effects — and a red/blue light bar run from the Mac.',
    tags: ['10 on the bulb', 'Police · from this Mac'], glow: 'police',
    card: S.allLightsEffects,
    cardLive: <><LivePolice s={S.allLightsEffects} /><LiveDot s={S.allLightsEffects} r={WIN.sidebarDots[0]} mode="police-a" /><LiveDot s={S.allLightsEffects} r={WIN.sidebarDots[1]} mode="police-b" /></>,
    detail: S.sidebar,
    detailLive: <><LiveDot s={S.sidebar} r={WIN.sidebarDots[0]} mode="police-a" /><LiveDot s={S.sidebar} r={WIN.sidebarDots[1]} mode="police-b" /></>,
  },
  {
    rail: 'Timer', title: 'A dial that counts down', line: 'One turn is an hour. Timer switches off; Sleep dims all the way down.',
    tags: ['5 min … 8 h', 'Timer / Sleep'], glow: '#5b66e0',
    card: S.timer, cardLive: <><LiveDial s={S.timer} /><LiveBadge s={S.timer} /></>,
    detail: S.timerCard, detailLive: <><LiveDial s={S.timerCard} /><LiveBadge s={S.timerCard} /></>,
  },
  {
    rail: 'Schedules', title: 'Schedules inside the bulb', line: 'Wake-ups fire on the bulb’s own clock — Mac asleep, phone away.',
    tags: ['on the bulb', 'on this Mac'], glow: 'var(--hue-candle)',
    card: S.schedules,
    cardLive: <>
      <LiveToggle s={S.schedules} r={WIN.schedToggles[1]} on={armed} />
      <LiveText s={S.schedules} r={WIN.schedStatus} bg="#1d1f21" color="#676a6b" size={22} text={(t) => (armed(t) ? 'Armed · fires Fri, Aug 28 at 08:25 · re-arms daily' : 'Disarmed · last set for Thu, Aug 27 at 08:25')} />
    </>,
    detail: S.wakeMac, detailLive: <LiveToggle s={S.wakeMac} r={WAKE.toggle} on={armed} />,
  },
  {
    rail: 'Menu bar', title: 'The whole room, one click', line: 'Toggles, brightness, scenes and Off in… without opening the window.',
    tags: ['Off in…', 'Disconnect All'], glow: 'var(--hue-warm)',
    card: S.allLightsWhite,
    cardLive: <><LiveCt s={S.allLightsWhite} header /><LiveToggle s={S.allLightsWhite} r={WIN.rowToggles[0]} on={rightOn} /></>,
    detail: S.menubar,
    detailLive: <>
      <LiveText s={S.menubar} r={MENU.timerText} bg="#0f0f0f" color="#9f9f9f" size={22} align="right" text={menuCountdown} />
      <LiveToggle s={S.menubar} r={MENU.toggles[1]} on={rightOn} />
    </>,
  },
  {
    rail: 'Diagnostics', title: 'Down to the bytes', line: 'RSSI, firmware, every characteristic raw — and a live log.',
    tags: ['0001 · 0007 · 1005', 'raw read / write'], glow: 'var(--hue-cyan)',
    card: S.diagnostics,
    cardLive: <>
      {WIN.rssi.map((r, i) => <LiveText key={i} s={S.diagnostics} r={r} bg="#262829" color="#9c9d9e" size={26} pad={24} text={dBm(i)} />)}
      {WIN.greenDots.map((r, i) => <LiveDot key={i} s={S.diagnostics} r={r} mode="pulse" color="#68cd66" />)}
    </>,
    detail: S.diagPanel,
    detailLive: <><LiveText s={S.diagPanel} r={WIN.rssi[0]} bg="#262829" color="#9c9d9e" size={26} pad={24} text={dBm(0)} /><LiveDot s={S.diagPanel} r={WIN.greenDots[0]} mode="pulse" color="#68cd66" /></>,
  },
];

const STRIP: readonly { s: Shot; cap: string; speed: number; live?: ReactNode }[] = [
  { s: S.addLightSheet, cap: '[ Add Light ]', speed: 0.75 },
  { s: S.fadeCard, cap: '[ Go-to-sleep fade ]', speed: 1.3, live: <LiveFade s={S.fadeCard} /> },
  { s: S.lightRows, cap: '[ Per light ]', speed: 0.9, live: <LiveToggle s={S.lightRows} r={WIN.rowToggles[0]} on={rightOn} /> },
  { s: S.pmset, cap: '[ pmset repeat wakeorpoweron ]', speed: 1.15 },
];

const N = CHAPTERS.length;
const HOLD = 0.4; // fraction of each chapter's scroll spent resting before the shuffle
const D = 1 - HOLD; // transition length
const pad2 = (n: number) => String(n + 1).padStart(2, '0');

/** Position `p` in the deck (0 = front). Cards recede up-right and fade. */
function cardState(p: number) {
  return {
    x: 58 * p,
    y: -40 * p,
    z: -180 * p,
    rotationY: -10,
    rotationX: 4,
    rotationZ: 0,
    opacity: p === 0 ? 1 : Math.max(0, 1 - 0.3 * p),
    xPercent: -50,
    yPercent: -50,
  };
}
const posOf = (k: number, active: number) => (k - active + N) % N;

function Glow({ c }: { c: Chapter }) {
  if (c.glow === 'scene') return <SceneGlow />;
  if (c.glow === 'police') return <PoliceGlow />;
  return <div className="glow" style={{ '--glow': c.glow } as CSSProperties} />;
}

function ChapterCopy({ c, i }: { c: Chapter; i: number }) {
  return (
    <>
      <p className="sc-chapter__n mono">{pad2(i)} / {pad2(N - 1)}</p>
      <h3 className="sc-chapter__t">{c.title}</h3>
      <p className="sc-chapter__p">{c.line}</p>
      <ul className="sc-tags">
        {c.tags.map((t) => <li className="sc-tag" key={t}>{t}</li>)}
      </ul>
    </>
  );
}

/** True when the pinned scrollytelling must be replaced by a static, stacked layout. */
function useStatic() {
  const query = '(max-width: 900px)';
  const [s, setS] = useState(() => window.matchMedia(query).matches || reducedMotion());
  useEffect(() => {
    const mqs = [window.matchMedia(query), window.matchMedia('(prefers-reduced-motion: reduce)')];
    const on = () => setS(mqs.some((m) => m.matches));
    mqs.forEach((m) => m.addEventListener('change', on));
    return () => mqs.forEach((m) => m.removeEventListener('change', on));
  }, []);
  return s;
}

/* ── Pinned scrollytelling (desktop) ─────────────────────────── */
function Scrolly() {
  const pinRef = useRef<HTMLDivElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const deckRef = useRef<HTMLDivElement>(null);
  const railRef = useRef<HTMLDivElement>(null);
  const stRef = useRef<ScrollTrigger | null>(null);
  const tlRef = useRef<gsap.core.Timeline | null>(null);

  useEffect(() => {
    const pin = pinRef.current, stage = stageRef.current, deck = deckRef.current, rail = railRef.current;
    if (!pin || !stage || !deck || !rail) return;
    const cards = Array.from(deck.querySelectorAll<HTMLElement>('.sc-card'));
    const details = Array.from(deck.querySelectorAll<HTMLElement>('.sc-detail'));
    const glows = Array.from(stage.querySelectorAll<HTMLElement>('.sc-glow'));
    const texts = Array.from(pin.querySelectorAll<HTMLElement>('.sc-chapter'));
    const railBtns = Array.from(rail.querySelectorAll<HTMLElement>('.sc-rail__btn'));
    let last = -1;
    const setActive = (idx: number) => {
      if (idx === last) return;
      last = idx;
      railBtns.forEach((b, i) => {
        b.classList.toggle('is-active', i === idx);
        b.setAttribute('aria-current', i === idx ? 'step' : 'false');
      });
      texts.forEach((t, i) => t.setAttribute('aria-hidden', i === idx ? 'false' : 'true'));
    };

    const ctx = gsap.context(() => {
      // Resting states for chapter 0.
      cards.forEach((c, k) => gsap.set(c, cardState(k)));
      gsap.set(details, { opacity: 0, y: 48, z: -40, scale: 0.94 });
      gsap.set(details[0], { opacity: 1, y: 0, z: 220, scale: 1 });
      gsap.set(texts, { opacity: 0, y: 28 });
      gsap.set(texts[0], { opacity: 1, y: 0 });
      gsap.set(glows, { autoAlpha: 0 });
      gsap.set(glows[0], { autoAlpha: 1 });

      const tl = gsap.timeline({ paused: true, defaults: { ease: 'power2.inOut' } });
      for (let t = 0; t < N - 1; t++) {
        const T0 = t + HOLD;
        cards.forEach((c, k) => {
          if (k === t) {
            // The front card swipes out down-right, then re-enters at the back of the deck.
            tl.to(c, {
              keyframes: [
                { x: 200, y: 130, z: 170, rotationZ: 7, rotationY: -18, opacity: 0, duration: D * 0.55, ease: 'power2.in' },
                { ...cardState(N - 1), duration: D * 0.45, ease: 'none' },
              ],
            }, T0);
          } else {
            tl.to(c, { ...cardState(posOf(k, t + 1)), duration: D }, T0);
          }
        });
        tl.to(details[t], { opacity: 0, y: -70, z: 320, scale: 1.05, duration: D * 0.5, ease: 'power2.in' }, T0);
        tl.to(details[t + 1], { opacity: 1, y: 0, z: 220, scale: 1, duration: D * 0.6, ease: 'power3.out' }, T0 + D * 0.4);
        tl.to(texts[t], { opacity: 0, y: -24, duration: D * 0.45, ease: 'power2.in' }, T0);
        tl.to(texts[t + 1], { opacity: 1, y: 0, duration: D * 0.55, ease: 'power3.out' }, T0 + D * 0.45);
        tl.to(glows[t], { autoAlpha: 0, duration: D * 0.55, ease: 'power1.inOut' }, T0);
        tl.to(glows[t + 1], { autoAlpha: 1, duration: D * 0.6, ease: 'power1.inOut' }, T0 + D * 0.3);
      }
      tl.to({}, { duration: HOLD }, N - 1); // final rest
      tlRef.current = tl;

      stRef.current = ScrollTrigger.create({
        trigger: pin,
        pin: true,
        start: 'top top',
        end: () => '+=' + Math.round((N - 1 + HOLD) * 0.85 * window.innerHeight),
        scrub: 0.7,
        animation: tl,
        anticipatePin: 1,
        invalidateOnRefresh: true,
        onUpdate: (self) => {
          const time = self.progress * tl.duration();
          setActive(Math.min(N - 1, Math.round(Math.max(0, time - HOLD / 2))));
        },
      });
      setActive(0);

      // Pre-decode every deck image as the pin approaches, so the first shuffle never paints a blank frame.
      ScrollTrigger.create({
        trigger: pin,
        start: 'top bottom',
        once: true,
        onEnter: () => deck.querySelectorAll('img').forEach((img) => { img.decode().catch(() => {}); }),
      });
    }, pin);

    const offTilt = attachTilt(stage, deck, 5);
    return () => {
      offTilt();
      ctx.revert();
      stRef.current = null;
      tlRef.current = null;
      ScrollTrigger.refresh();
    };
  }, []);

  const jump = (i: number) => {
    const st = stRef.current, tl = tlRef.current;
    if (!st || !tl) return;
    const top = st.start + ((i + HOLD / 2) / tl.duration()) * (st.end - st.start);
    window.scrollTo({ top, behavior: 'smooth' });
  };

  return (
    <div className="sc-pin" ref={pinRef}>
      <div className="sc-pin__inner">
        <div className="sc-copy">
          <div className="sc-rail" ref={railRef} role="list" aria-label="Feature chapters">
            {CHAPTERS.map((c, i) => (
              <button type="button" className="sc-rail__btn" key={c.rail} onClick={() => jump(i)} role="listitem">
                <span className="sc-rail__n">{pad2(i)}</span>
                <span className="sc-rail__l">{c.rail}</span>
              </button>
            ))}
          </div>
          <div className="sc-chapters">
            {CHAPTERS.map((c, i) => (
              <article className="sc-chapter" key={c.title} aria-hidden={i === 0 ? undefined : true}>
                <ChapterCopy c={c} i={i} />
              </article>
            ))}
          </div>
        </div>

        <div className="sc-stage" ref={stageRef}>
          <div className="sc-glows" aria-hidden="true">
            {CHAPTERS.map((c, i) => <div className="sc-glow" key={i}><Glow c={c} /></div>)}
          </div>
          <div className="sc-deck" ref={deckRef}>
            {CHAPTERS.map((c, i) => (
              <Frame className="sc-card" s={c.card} eager={i === 0} key={`c${i}`}>{c.cardLive}</Frame>
            ))}
            {CHAPTERS.map((c, i) => (
              <Frame className={`sc-detail sc-detail--${i}`} s={c.detail} eager={i === 0} key={`d${i}`}>{c.detailLive}</Frame>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

/* ── Static chapters (mobile / reduced motion) ───────────────── */
function StaticList() {
  const root = useReveal<HTMLOListElement>(0.08);
  return (
    <ol className="sc-list" ref={root}>
      {CHAPTERS.map((c, i) => (
        <li className={`sc-item sc-item--${i}`} key={c.title}>
          <div className="sc-item__media reveal">
            <div className="sc-item__glow" aria-hidden="true"><Glow c={c} /></div>
            <Frame className="sc-item__card" s={c.card}>{c.cardLive}</Frame>
            <Frame className="sc-item__detail" s={c.detail}>{c.detailLive}</Frame>
          </div>
          <div className="sc-item__copy reveal" data-delay="1">
            <ChapterCopy c={c} i={i} />
          </div>
        </li>
      ))}
    </ol>
  );
}

/* ── Free-scrolling detail strip with per-item parallax ──────── */
function Strip() {
  const root = useReveal<HTMLDivElement>(0.05);
  useEffect(() => {
    const el = root.current;
    if (!el || reducedMotion()) return;
    const mobile = window.matchMedia('(max-width: 720px)').matches;
    const ctx = gsap.context(() => {
      el.querySelectorAll<HTMLElement>('.sc-strip__item').forEach((item) => {
        const speed = Number(item.dataset.speed || 1);
        const travel = (speed - 1) * (mobile ? 60 : 160);
        gsap.fromTo(item, { y: -travel }, {
          y: travel,
          ease: 'none',
          scrollTrigger: { trigger: el, start: 'top bottom', end: 'bottom top', scrub: 0.6 },
        });
      });
    }, el);
    return () => ctx.revert();
  }, [root]);

  return (
    <div className="sc-strip" ref={root}>
      {STRIP.map((it) => (
        <div className="sc-strip__item reveal" data-speed={it.speed} key={it.s.src}>
          <Frame s={it.s}>{it.live}</Frame>
          <p className="sc-cap">{it.cap}</p>
        </div>
      ))}
    </div>
  );
}

export default function Showcase() {
  const head = useReveal<HTMLElement>(0.15);
  const isStatic = useStatic();
  return (
    <section id="features" className="section sc" aria-labelledby="features-title">
      <header className="section__inner sc-head" ref={head}>
        <p className="eyebrow reveal">[ 03 — Features ]</p>
        <h2 id="features-title" className="display sc-title reveal" data-delay="1">
          Every control.<br />Every effect.
        </h2>
        <p className="sc-line mono reveal" data-delay="2">[ 7 views · 1 window · menu bar ]</p>
      </header>

      {isStatic ? <div className="section__inner"><StaticList /></div> : <Scrolly />}

      <div className="section__inner">
        <Strip />
      </div>
    </section>
  );
}
