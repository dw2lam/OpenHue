import { useEffect, useState } from 'react';

export const REPO = 'dw2lam/OpenHue';
export const REPO_URL = `https://github.com/${REPO}`;

export interface ReleaseInfo {
  version: string;
  dmgUrl: string;
  zipUrl: string;
  releaseUrl: string;
  dmgBytes?: number;
}

const FALLBACK: ReleaseInfo = {
  version: '0.1.0',
  dmgUrl: `${REPO_URL}/releases/latest/download/OpenHue.dmg`,
  zipUrl: `${REPO_URL}/releases/latest/download/OpenHue.zip`,
  releaseUrl: `${REPO_URL}/releases/latest`,
  dmgBytes: 4077361,
};

let cached: ReleaseInfo | null = null;
let inflight: Promise<ReleaseInfo> | null = null;

function fetchRelease(): Promise<ReleaseInfo> {
  if (cached) return Promise.resolve(cached);
  if (inflight) return inflight;
  inflight = fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
    headers: { Accept: 'application/vnd.github+json' },
  })
    .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
    .then((data: any) => {
      const v = String(data.tag_name || '').replace(/^v/i, '');
      const assets: any[] = data.assets || [];
      const dmg = assets.find((a) => /\.dmg$/i.test(a.name));
      const zip = assets.find((a) => /\.zip$/i.test(a.name));
      const info: ReleaseInfo = {
        version: v || FALLBACK.version,
        dmgUrl: dmg ? dmg.browser_download_url : FALLBACK.dmgUrl,
        zipUrl: zip ? zip.browser_download_url : FALLBACK.zipUrl,
        releaseUrl: data.html_url || FALLBACK.releaseUrl,
        dmgBytes: dmg ? dmg.size : FALLBACK.dmgBytes,
      };
      cached = info;
      return info;
    })
    .catch(() => FALLBACK)
    .finally(() => { inflight = null; });
  return inflight;
}

/** Latest GitHub release of OpenHue (dmg preferred). Falls back to static values offline. */
export function useLatestRelease(): ReleaseInfo {
  const [info, setInfo] = useState<ReleaseInfo>(cached ?? FALLBACK);
  useEffect(() => {
    let cancelled = false;
    fetchRelease().then((i) => { if (!cancelled) setInfo(i); });
    return () => { cancelled = true; };
  }, []);
  return info;
}

export function formatBytes(n?: number): string {
  if (!n) return '';
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}
