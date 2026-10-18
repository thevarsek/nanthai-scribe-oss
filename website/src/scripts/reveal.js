// Reveal headings, text and visuals once as they scroll into view. CSS owns the motion
// (poster.css `[data-reveal]`); this only adds `.in`. Reduced motion shows everything at once.
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const targets = [...document.querySelectorAll('[data-reveal]')];
const showAll = () => targets.forEach(el => el.classList.add('in'));
if (reduced.matches || !('IntersectionObserver' in window)) showAll();
else {
  const io = new IntersectionObserver(entries => {
    for (const entry of entries) if (entry.isIntersecting) { entry.target.classList.add('in'); io.unobserve(entry.target); }
  }, { threshold: .12, rootMargin: '0px 0px -6% 0px' });
  targets.forEach(el => io.observe(el));
  reduced.addEventListener('change', () => { if (reduced.matches) { showAll(); io.disconnect(); } });
}
// The check script counts revealed elements after scrolling the page.
window.__scribeReveal = () => ({ total: targets.length, shown: targets.filter(el => el.classList.contains('in')).length });
