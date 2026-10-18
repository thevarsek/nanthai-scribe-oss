import { timeline } from "./timeline.js";
// A misheard name is corrected once; Scribe asks, you tap Add, the Dictionary learns it.
export default function learn(root) {
    const word = root.querySelector(".ln-word"), prompt = root.querySelector(".ln-prompt"), add = root.querySelector(".ln-btn.add"), row = root.querySelector(".ln-row"), tap = root.querySelector(".ph-tap");
    const tapAt = (el) => { const r = el.getBoundingClientRect(), p = root.getBoundingClientRect(); const s = r.width / el.offsetWidth; tap.style.left = ((r.left - p.left) / s + el.offsetWidth / 2) + "px"; tap.style.top = ((r.top - p.top) / s + el.offsetHeight / 2) + "px"; tap.classList.remove("go"); void tap.offsetWidth; tap.classList.add("go"); };
    const reset = () => { word.textContent = "Nantai"; word.className = "ln-word"; prompt.className = "ln-prompt"; row.classList.remove("show"); };
    const final = () => { reset(); word.textContent = "NanthAi"; row.classList.add("show"); };
    const fixed = "NanthAi";
    const steps = [[0, reset], [900, () => word.classList.add("sel")], [1500, () => { word.textContent = ""; word.classList.remove("sel"); word.classList.add("edit"); }]];
    [...fixed].forEach((ch, i) => steps.push([1600 + i * 110, () => { word.textContent += ch; }]));
    steps.push([2900, () => { word.classList.remove("edit"); prompt.classList.add("show"); }]);
    steps.push([4600, () => tapAt(add)]);
    steps.push([4850, () => prompt.classList.add("fly")]);
    steps.push([5200, () => row.classList.add("show")]);
    return { tl: timeline(steps, 9800), final };
  }
