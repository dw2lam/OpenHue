import { useCallback, useEffect, useRef, useState, type CSSProperties } from 'react';
import { REPO_URL, formatBytes, useLatestRelease } from '../hooks/useLatestRelease';
import './hero.css';

// Media: the CloudFront source re-cut as a centred bounce loop (forward + reverse, seam frames
// trimmed) so it loops without a jump. Rebuild: see website/HERO-SPEC.md → "Hero video".
const VIDEO_SRC = '/hero.mp4';
const POSTER_SRC = '/hero-poster.jpg';
const HUE_URL = 'https://www.philips-hue.com';
const ROADMAP_URL = `${REPO_URL}/blob/main/ROADMAP.md`;

interface NavLink {
  label: string;
  href: string;
  external?: boolean;
}

const NAV_LINKS: NavLink[] = [
  { label: 'Overview', href: '#story' },
  { label: 'Features', href: '#features' },
  { label: 'Try it', href: '#playground' },
  { label: 'Pairing', href: '#pairing' },
  { label: 'GitHub', href: REPO_URL, external: true },
];
const SPY_IDS = ['story', 'desktop', 'features', 'playground', 'pairing'];
const SPY_TO_HREF: Record<string, string> = {
  story: '#story', desktop: '#story', features: '#features', playground: '#playground', pairing: '#pairing',
};

const externalProps = (link: NavLink) =>
  link.external ? ({ target: '_blank', rel: 'noopener' } as const) : {};

const GitHubMark = ({ size = 14 }: { size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 16 16" aria-hidden="true" focusable="false">
    <path
      fill="currentColor"
      d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8z"
    />
  </svg>
);

export default function Hero() {
  const release = useLatestRelease();
  const [menuOpen, setMenuOpen] = useState(false);
  const toggleRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const wasOpen = useRef(false);
  const linksRef = useRef<HTMLElement>(null);
  const [active, setActive] = useState<string | null>(null);
  const [pill, setPill] = useState<{ x: number; w: number } | null>(null);
  const [scrolled, setScrolled] = useState(false);

  const closeMenu = useCallback(() => setMenuOpen(false), []);

  // React sets `muted` as a property, not an attribute — make sure the
  // autoplay policy sees a muted element and nudge playback to start.
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    v.muted = true;
    v.defaultMuted = true;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      v.pause();
      return;
    }
    const p = v.play();
    if (p) p.catch(() => {});
  }, []);

  // Menu side effects: body scroll lock, inert when closed, focus management.
  useEffect(() => {
    const menu = menuRef.current;
    document.body.classList.toggle('menu-open', menuOpen);
    if (menu) menu.inert = !menuOpen;

    if (menuOpen) {
      wasOpen.current = true;
      menu?.querySelector<HTMLElement>('a, button')?.focus({ preventScroll: true });
      return () => document.body.classList.remove('menu-open');
    }

    if (wasOpen.current) {
      wasOpen.current = false;
      toggleRef.current?.focus({ preventScroll: true });
    }
    return () => document.body.classList.remove('menu-open');
  }, [menuOpen]);

  // Scroll-spy for the island: which section is under the top third of the viewport.
  useEffect(() => {
    const els = SPY_IDS.map((id) => document.getElementById(id)).filter((e): e is HTMLElement => !!e);
    if (!els.length) return;
    const pick = () => {
      const line = window.innerHeight * 0.35;
      let current: string | null = null;
      for (const el of els) {
        const r = el.getBoundingClientRect();
        if (r.top <= line && r.bottom > line) { current = SPY_TO_HREF[el.id] ?? null; break; }
      }
      setActive(current);
      setScrolled(window.scrollY > 24);
    };
    pick();
    let raf = 0;
    const onScroll = () => { if (!raf) raf = requestAnimationFrame(() => { raf = 0; pick(); }); };
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll);
    return () => { window.removeEventListener('scroll', onScroll); window.removeEventListener('resize', onScroll); if (raf) cancelAnimationFrame(raf); };
  }, []);

  // Slide the highlight pill under the active link.
  useEffect(() => {
    const nav = linksRef.current;
    if (!nav) return;
    const measure = () => {
      const a = active ? nav.querySelector<HTMLAnchorElement>(`a[href="${active}"]`) : null;
      if (!a) { setPill(null); return; }
      setPill({ x: a.offsetLeft, w: a.offsetWidth });
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(nav);
    return () => ro.disconnect();
  }, [active]);

  // Escape closes.
  useEffect(() => {
    if (!menuOpen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setMenuOpen(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [menuOpen]);

  // Auto-close once the viewport grows into the desktop layout.
  useEffect(() => {
    const mq = window.matchMedia('(min-width: 901px)');
    const onChange = (e: MediaQueryListEvent) => {
      if (e.matches) setMenuOpen(false);
    };
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);

  return (
    <section id="top" className="hero">
      <div className="hero__media" aria-hidden="true">
        <video
          ref={videoRef}
          className="hero__video"
          autoPlay
          muted
          loop
          playsInline
          preload="auto"
          poster={POSTER_SRC}
        >
          <source src={VIDEO_SRC} type="video/mp4" />
        </video>
      </div>

      <header className={`hero__nav${scrolled ? ' is-scrolled' : ''}`}>
        <div className="hero__island">
          <nav className="hero__links" aria-label="Primary" ref={linksRef}>
            <span
              className={`hero__pill${pill ? ' is-on' : ''}`}
              aria-hidden="true"
              style={pill ? { transform: `translateX(${pill.x}px)`, width: pill.w } : undefined}
            />
            {NAV_LINKS.filter((l) => !l.external).map((link) => (
              <a
                key={link.label}
                href={link.href}
                className={active === link.href ? 'is-active' : undefined}
                aria-current={active === link.href ? 'true' : undefined}
              >
                {link.label}
              </a>
            ))}
          </nav>
          <a className="hero__gh" href={REPO_URL} target="_blank" rel="noopener" aria-label="OpenHue on GitHub (opens in a new tab)">
            <GitHubMark />
            <span>GitHub</span>
            <i aria-hidden="true">↗</i>
          </a>
          <button
            ref={toggleRef}
            type="button"
            className={`hero__toggle${menuOpen ? ' is-active' : ''}`}
            aria-expanded={menuOpen}
            aria-controls="mobileMenu"
            aria-label={menuOpen ? 'Close menu' : 'Open menu'}
            onClick={() => setMenuOpen((o) => !o)}
          >
            <span className="hero__bar" />
            <span className="hero__bar" />
            <span className="hero__bar" />
          </button>
        </div>
      </header>

      <div className="hero__body">
        <div className="hero__panel">
          <div className="hero__meet">
            <img className="hero__meet-icon" src="/icon.png" width="64" height="64" alt="OpenHue app icon" decoding="async" />
            <p className="hero__meet-line">Meet OpenHue</p>
          </div>
          <h1 className="hero__title">Control the bulbs you&nbsp;own.</h1>
          <p className="hero__lede">
            A native Swift app for Philips Hue Bluetooth bulbs that does everything the Hue app does — and more.
            No Bridge to buy, no account, no closed API between you and the hardware you already paid for.
          </p>

          <div className="hero__actions">
            <a className="hero__btn hero__btn--solid" href={release.dmgUrl} download>
              Download for macOS
            </a>
            <a
              className="hero__btn hero__btn--ghost"
              href={REPO_URL}
              target="_blank"
              rel="noopener"
            >
              View source
            </a>
          </div>

          <div className="hero__meta" role="status">
            <span className="sr-only">Latest release</span>
            v{release.version} · {formatBytes(release.dmgBytes) || '4.1 MB'} · macOS 14 or later
          </div>

        </div>

        <a className="hero__roadmap" href={ROADMAP_URL} target="_blank" rel="noopener">
          <span className="hero__roadmap-k">Next</span>
          <span>Homebridge</span><i>·</i><span>Home Assistant</span><i>·</i><span>HomeKit</span>
          <span className="hero__roadmap-k">on the roadmap ↗</span>
        </a>
      </div>

      <footer className="hero__legal">
        <p>
          OpenHue is free and{' '}
          <a href={REPO_URL} target="_blank" rel="noopener">
            open source
          </a>
          . It is not affiliated with Signify or{' '}
          <a href={HUE_URL} target="_blank" rel="noopener">
            Philips Hue
          </a>
          .
        </p>
      </footer>

      <div
        id="mobileMenu"
        ref={menuRef}
        className={`hero__menu${menuOpen ? ' is-open' : ''}`}
        role="dialog"
        aria-modal="true"
        aria-label="Site menu"
        aria-hidden={!menuOpen}
        onClick={(e) => {
          if (e.target === e.currentTarget) closeMenu();
        }}
      >
        <div className="hero__menu-inner">
          {NAV_LINKS.map((link, i) => (
            <a
              key={link.label}
              className={`hero__menu-item hero__menu-link${link.external ? ' hero__menu-link--ext' : ''}`}
              style={{ '--i': i } as CSSProperties}
              href={link.href}
              onClick={closeMenu}
              {...externalProps(link)}
            >
              {link.external && <GitHubMark size={18} />}
              {link.label}
              {link.external && <i aria-hidden="true">↗</i>}
            </a>
          ))}
          <a
            className="hero__menu-item hero__menu-cta"
            style={{ '--i': NAV_LINKS.length } as CSSProperties}
            href="#download"
            onClick={closeMenu}
          >
            Download
          </a>
        </div>
      </div>
    </section>
  );
}
