import { useLatestRelease, REPO_URL } from '../hooks/useLatestRelease';
import './footer.css';

const ext = { target: '_blank', rel: 'noopener' } as const;

/** One row, like the DotStudio / NotchTune footers: icon + wordmark + tagline · GitHub · David Lam. */
export default function Footer() {
  const rel = useLatestRelease();
  const year = new Date().getFullYear();
  return (
    <footer className="foot">
      <div className="foot__inner">
        <div className="foot__row">
          <a href="#top" className="foot__brand" aria-label="OpenHue — back to top">
            <img className="foot__icon" src="/icon.png" width="28" height="28" alt="" loading="lazy" decoding="async" />
            <span className="foot__mark">OPENHUE</span>
            <span className="foot__tag">Your Hue bulbs, straight from your Mac.</span>
          </a>
          <nav className="foot__links" aria-label="Footer">
            <a href={REPO_URL} {...ext}>GitHub</a>
            <a href="https://www.davidlam.online" {...ext}>David Lam</a>
          </nav>
        </div>
        <p className="foot__legal">
          © {year} David Lam · v{rel.version} · Free and open source · Not affiliated with Signify or Philips Hue.
        </p>
      </div>
    </footer>
  );
}
