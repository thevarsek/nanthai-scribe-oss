// Reserve each scene's aspect ratio in HTML; scaling never changes page geometry.
const loaders = import.meta.glob('./scenes/*.js');
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const states = new Map();
const fit = (scene) => {
  const inner = scene.querySelector('.sc');
  const scale = scene.clientWidth / Number(scene.dataset.w);
  if (inner) { inner.style.left = '0'; inner.style.transform = `scale(${scale})`; }
};
const sizeObserver = new ResizeObserver(entries => entries.forEach(e => fit(e.target)));
async function update(state) {
  const shouldRun = state.visible && !reduced.matches && !document.hidden;
  if (!state.instance && state.visible && !reduced.matches) {
    if (state.loading) return;
    state.loading = true;
    const module = await loaders[`./scenes/${state.kind}.js`]();
    state.instance = module.default(state.root);
    state.loading = false;
    return update(state);
  }
  if (!state.instance) return;
  state.root.classList.toggle('scene-running', shouldRun);
  if (shouldRun) state.instance.tl.start();
  else { state.instance.tl.stop(); state.instance.final(); }
}
const observer = new IntersectionObserver(entries => entries.forEach(entry => {
  const state = states.get(entry.target);
  state.visible = entry.isIntersecting;
  update(state);
}), { threshold: .2 });
document.querySelectorAll('.scene').forEach(scene => {
  fit(scene); sizeObserver.observe(scene);
  const root = scene.querySelector('[data-anim]');
  if (!root) return;
  const state = { root, kind: root.dataset.anim, visible: false, instance: null, loading: false };
  states.set(scene, state); observer.observe(scene);
});
reduced.addEventListener('change', () => states.forEach(update));
document.addEventListener('visibilitychange', () => states.forEach(update));
// The test harness can inspect loaded scene types without forcing eager imports.
window.__scribeScenes = states;
