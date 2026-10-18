import { timeline } from "./timeline.js";
export default function meeting(root) {
    const views = root.querySelectorAll(".mt-view"), time = root.querySelector(".mt-time"), btn = root.querySelector(".mt-btn"), waves = root.querySelectorAll(".mt-src .sc-wave"), stepsEl = root.querySelectorAll(".mt-step"), turns = root.querySelectorAll(".turn"), items = root.querySelectorAll(".mt-col li");
    const show = (i) => views.forEach((v, k) => v.classList.toggle("show", k === i));
    const reset = () => { show(0); time.textContent = "12:04"; btn.textContent = "Stop"; btn.classList.add("hot"); waves.forEach(w => w.classList.add("on")); stepsEl.forEach(s => s.className = "mt-step"); turns.forEach(t => t.classList.remove("in")); items.forEach(t => t.classList.remove("in")); };
    const final = () => { reset(); show(2); btn.textContent = "Copy"; btn.classList.remove("hot"); turns.forEach(t => t.classList.add("in")); items.forEach(t => t.classList.add("in")); };
    const steps = [[0, reset]];
    [1, 2, 3].forEach(i => steps.push([i * 1000, () => time.textContent = "12:0" + (4 + i)]));
    steps.push([3600, () => { waves.forEach(w => w.classList.remove("on")); btn.textContent = "Processing"; btn.classList.remove("hot"); }]);
    steps.push([4000, () => show(1)]);
    stepsEl.forEach((_, i) => { steps.push([4100 + i * 800, () => { stepsEl.forEach((x, k) => x.className = "mt-step" + (k < i ? " done" : k === i ? " active" : "")); }]); });
    steps.push([4100 + stepsEl.length * 800, () => stepsEl.forEach(x => x.className = "mt-step done")]);
    steps.push([4600 + stepsEl.length * 800, () => { show(2); btn.textContent = "Copy"; }]);
    const t0 = 4800 + stepsEl.length * 800;
    turns.forEach((t, i) => steps.push([t0 + i * 450, () => t.classList.add("in")]));
    items.forEach((t, i) => steps.push([t0 + turns.length * 450 + 200 + i * 300, () => t.classList.add("in")]));
    return { tl: timeline(steps, t0 + turns.length * 450 + items.length * 300 + 4200), final };
  }

