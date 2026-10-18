import { timeline } from './timeline.js';
export default function story(root) {
  const state = root.querySelector('.story-state');
  const words = root.querySelector('.story-words');
  const hint = root.querySelector('.story-hint');
  const beats = root.querySelectorAll('.story-beat');
  const raw = 'um so can you, can you send me the report by friday, the uh the sales one';
  function phase(name, label, caption, beat) {
    root.dataset.phase = name; state.textContent = label; hint.textContent = caption;
    beats.forEach(el => el.classList.toggle('active', el.dataset.beat === beat));
  }
  function reset() { words.replaceChildren(); phase('listen', 'Listening', 'Just speak. Even if it comes out roughly.', 'say'); }
  const steps = [[0, reset]];
  raw.split(' ').forEach((word, i) => steps.push([1200 + i * 285, () => {
    const token = document.createElement('span');
    token.className = 'w' + ([0,1,2,3,12,13,14,16].includes(i) ? ' filler' : '');
    token.textContent = (i ? ' ' : '') + word;
    words.append(token);
  }]));
  steps.push([8100, () => phase('refine', 'Refining', 'A little less ramble. Still your words.', 'scribe')]);
  steps.push([11100, () => phase('clean', 'Refined', 'Can you send me the sales report by Friday?', 'scribe')]);
  steps.push([13900, () => phase('compose', 'Ready to send', 'Clean text, right where you need it.', 'send')]);
  steps.push([16400, () => phase('sent', 'Sent', 'Your words. Ready to go.', 'send')]);
  return { tl: timeline(steps, 22000), final() { phase('sent', 'Sent', 'Your words. Ready to go.', 'send'); } };
}
