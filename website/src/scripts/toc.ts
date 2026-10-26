// Highlight the section being read in the on-page list.
const tocLinks = [...document.querySelectorAll<HTMLAnchorElement>('.docs-toc a')];
if (tocLinks.length && 'IntersectionObserver' in window) {
  const byId = new Map(tocLinks.map(a => [decodeURIComponent(a.hash.slice(1)), a]));
  const targets = [...byId.keys()].map(id => document.getElementById(id)).filter((el): el is HTMLElement => !!el);
  let currentId = '';
  const set = (id: string) => { if (id === currentId) return; currentId = id; tocLinks.forEach(a => a.classList.toggle('active', byId.get(id) === a)); };
  const observer = new IntersectionObserver(entries => {
    const visible = entries.filter(e => e.isIntersecting).sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
    if (visible[0]) set(visible[0].target.id);
  }, { rootMargin: '-80px 0px -60% 0px', threshold: 0 });
  targets.forEach(t => observer.observe(t));
  if (targets[0]) set(targets[0].id);
}
