import { useEffect, useRef } from 'react';

/**
 * Adds `.is-in` to every `.reveal` descendant of the returned ref once it enters the viewport.
 * Pair with the global `.reveal` CSS in index.css. Respects prefers-reduced-motion (elements are
 * visible by default there).
 */
export function useReveal<T extends HTMLElement = HTMLElement>(threshold = 0.15) {
  const ref = useRef<T | null>(null);
  useEffect(() => {
    const root = ref.current;
    if (!root) return;
    const els = Array.from(root.querySelectorAll<HTMLElement>('.reveal'));
    if (root.classList.contains('reveal')) els.unshift(root);
    if (!('IntersectionObserver' in window)) { els.forEach((e) => e.classList.add('is-in')); return; }
    const io = new IntersectionObserver((entries) => {
      entries.forEach((en) => { if (en.isIntersecting) { en.target.classList.add('is-in'); io.unobserve(en.target); } });
    }, { threshold, rootMargin: '0px 0px -8% 0px' });
    els.forEach((e) => io.observe(e));
    return () => io.disconnect();
  }, [threshold]);
  return ref;
}
