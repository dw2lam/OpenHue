import { useLatestRelease, REPO_URL } from '../hooks/useLatestRelease';
import './footer.css';

const ext = { target: '_blank', rel: 'noopener' } as const;

export default function Footer() {
  const rel = useLatestRelease();
  const year = new Date().getFullYear();
  return (
    <footer className="foot">
      <div className="foot__inner">
        <div className="foot__grid">
          <div className="foot__brand">
            <a href="#top" className="foot__mark" aria-label="OpenHue — back to top">OPENHUE</a>
            <p className="foot__tag">Your Hue bulbs, straight from your Mac.</p>
          </div>

          <nav className="foot__cols" aria-label="Footer">
            <div className="foot__col">
              <p className="foot__h">Project</p>
              <ul>
                <li><a href={REPO_URL} {...ext}>GitHub</a></li>
                <li><a href={`${REPO_URL}/releases`} {...ext}>Releases</a></li>
                <li><a href={`${REPO_URL}/blob/main/ROADMAP.md`} {...ext}>Roadmap</a></li>
                <li><a href={`${REPO_URL}#readme`} {...ext}>README</a></li>
              </ul>
            </div>
            <div className="foot__col">
              <p className="foot__h">More apps</p>
              <ul>
                <li><a href="https://notchtune.davidlam.online" {...ext}>NotchTune</a></li>
                <li><a href="https://dotstudio.davidlam.online" {...ext}>DotStudio</a></li>
              </ul>
            </div>
            <div className="foot__col">
              <p className="foot__h">Made by</p>
              <ul>
                <li><a href="https://www.davidlam.online" {...ext}>David Lam</a></li>
                <li><a href="#pairing">Pairing help</a></li>
                <li><a href="#download">Download</a></li>
              </ul>
            </div>
          </nav>
        </div>

        <div className="foot__bottom">
          <p className="foot__legal">
            © {year} David Lam. OpenHue is free and open source. Not affiliated with Signify or Philips Hue.
          </p>
          <p className="foot__ver">v{rel.version} · macOS 14+ · Bluetooth LE · No Bridge</p>
        </div>
      </div>
    </footer>
  );
}
