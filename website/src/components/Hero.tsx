import { useCallback, useEffect, useRef, useState, type CSSProperties } from 'react';
import { REPO_URL, useLatestRelease } from '../hooks/useLatestRelease';
import './hero.css';

// Media (CloudFront — verbatim per spec). Preconnect lives in index.html.
const VIDEO_SRC =
  'https://d8j0ntlcm91z4.cloudfront.net/user_38xzZboKViGWJOttwIXH07lWA1P/hf_20260806_133255_956f653f-5d80-4b06-abd5-0f46c98b60fa.mp4';
const POSTER_SRC =
  'https://d8j0ntlcm91z4.cloudfront.net/user_38xzZboKViGWJOttwIXH07lWA1P/hf_20260806_132328_5f9029c8-218f-4489-82b6-29ff2849920e.png';
const HUE_URL = 'https://www.philips-hue.com';

interface NavLink {
  label: string;
  href: string;
  external?: boolean;
}

const NAV_LINKS: NavLink[] = [
  { label: 'Overview', href: '#story' },
  { label: 'Features', href: '#features' },
  { label: 'Pairing', href: '#pairing' },
  { label: 'GitHub', href: REPO_URL, external: true },
];

const externalProps = (link: NavLink) =>
  link.external ? ({ target: '_blank', rel: 'noopener' } as const) : {};

export default function Hero() {
  const release = useLatestRelease();
  const [menuOpen, setMenuOpen] = useState(false);
  const toggleRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const wasOpen = useRef(false);

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

      <header className="hero__nav">
        <a className="hero__logo" href="#top" aria-label="OpenHue — top of page">
          OPENHUE
        </a>
        <div className="hero__cluster">
          <nav className="hero__links" aria-label="Primary">
            {NAV_LINKS.map((link) => (
              <a key={link.label} href={link.href} {...externalProps(link)}>
                {link.label}
              </a>
            ))}
          </nav>
          <a className="hero__cta" href="#download">
            Download
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
          <span className="hero__chip">[ Bluetooth · No Bridge ]</span>
          <h1 className="hero__title">OPENHUE</h1>
          <p className="hero__tagline">Your Hue bulbs, straight from your Mac.</p>

          <div className="hero__form">
            <div className="hero__readout" role="status">
              <span className="sr-only">Latest release</span>
              OpenHue.dmg · v{release.version} · macOS 14 or later
            </div>
            <a
              className="hero__btn hero__btn--ghost"
              href={REPO_URL}
              target="_blank"
              rel="noopener"
            >
              View source on GitHub
            </a>
            <a className="hero__btn hero__btn--solid" href={release.dmgUrl} download>
              Download for macOS
            </a>
          </div>

          <a className="hero__referral" href="#pairing">
            Already paired with the Hue app?
          </a>
        </div>
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
              className="hero__menu-item hero__menu-link"
              style={{ '--i': i } as CSSProperties}
              href={link.href}
              onClick={closeMenu}
              {...externalProps(link)}
            >
              {link.label}
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
