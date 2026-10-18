import { timeline } from "./timeline.js";
// An audio file is dragged onto the Library and goes through the meeting pipeline.
export default function transcribe(root) {
    const file = root.querySelector(".tr-file"), lib = root.querySelector(".tr-lib"), stepsBox = root.querySelector(".tr-steps"), stepsEl = root.querySelectorAll(".mt-step"), row = root.querySelector(".tr-row.new");
    const reset = () => { file.className = "tr-file"; lib.className = "tr-lib"; stepsBox.classList.remove("show"); stepsEl.forEach(s => s.className = "mt-step"); row.classList.remove("show"); };
    const final = () => { reset(); file.classList.add("dropped"); row.classList.add("show"); };
    const steps = [[0, reset], [600, () => { file.classList.add("drag"); lib.classList.add("over"); }], [1700, () => { file.classList.add("dropped"); lib.classList.remove("over"); lib.classList.add("busy"); stepsBox.classList.add("show"); }]];
    stepsEl.forEach((_, i) => steps.push([1900 + i * 650, () => stepsEl.forEach((x, k) => x.className = "mt-step" + (k < i ? " done" : k === i ? " active" : ""))]));
    const t = 1900 + stepsEl.length * 650;
    steps.push([t, () => stepsEl.forEach(x => x.className = "mt-step done")]);
    steps.push([t + 500, () => { stepsBox.classList.remove("show"); lib.classList.remove("busy"); }]);
    steps.push([t + 800, () => row.classList.add("show")]);
    return { tl: timeline(steps, t + 5200), final };
  }
