import { timeline } from './timeline.js';
export default function privacy(root) {
  const wave = root.querySelector('.sc-wave');
  function stage(name) { root.dataset.phase=name; }
  function final() { root.classList.remove('on'); wave.classList.remove('on'); stage('final'); }
  const steps = [
    [0, () => { final(); stage('audio'); }],
    [800, () => { root.classList.add('on'); wave.classList.add('on'); }],
    [3600, () => stage('text')],
    [6500, () => stage('private')],
    [8500, final],
  ];
  return { tl: timeline(steps, 15000), final };
}
