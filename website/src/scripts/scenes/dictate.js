import { timeline, clearEl } from "./timeline.js";
export default function dictate(root) {
    const key = root.querySelector(".sc-key-opt"), cmd = root.querySelector(".sc-key-cmd"), hint = root.querySelector(".sc-key-hint");
    const hud = root.querySelector(".sc-hud"), live = root.querySelector(".sc-live"), wave = root.querySelector(".sc-wave"), typed = root.querySelector(".sc-typed");
    const raw = "um so can you, can you send me the report by friday, the uh the sales one";
    const clean = "Can you send me the sales report by Friday?";
    const reset = () => { key.classList.remove("down"); cmd.classList.remove("down"); hud.classList.remove("show", "chips"); wave.classList.remove("on"); live.className = "sc-live"; clearEl(live); clearEl(typed); hint.textContent = "Hold your shortcut and talk"; };
    const final = () => { reset(); typed.textContent = clean; hud.classList.add("show", "chips"); live.textContent = "Refine on · released"; hint.textContent = "Released: text typed into Mail"; };
    const steps = [
      [0, reset],
      [500, () => { key.classList.add("down"); hud.classList.add("show"); wave.classList.add("on"); live.textContent = "Listening…"; }],
      [1100, () => clearEl(live)],
    ];
    // live words into the HUD
    raw.split(" ").forEach((p, i) => steps.push([1100 + i * 190, () => { const s = document.createElement("span"); s.className = "w"; s.textContent = (i ? " " : "") + p; live.appendChild(s); }]));
    steps.push([2600, () => { cmd.classList.add("down"); hud.classList.add("chips"); hint.textContent = "Add ⌘ for Refine"; }]);
    steps.push([4600, () => { key.classList.remove("down"); cmd.classList.remove("down"); wave.classList.remove("on"); clearEl(live); live.innerHTML = '<span class="shimmer">Refining…</span>'; hint.textContent = "Let go"; }]);
    steps.push([5700, () => { hud.classList.remove("show"); }]);
    clean.split(" ").forEach((p, i) => steps.push([5800 + i * 60, () => { const s = document.createElement("span"); s.className = "w"; s.textContent = (i ? " " : "") + p; typed.appendChild(s); }]));
    steps.push([6100, () => { hint.textContent = "Typed into Mail. Clipboard restored."; }]);
    return { tl: timeline(steps, 13000), final };
  }

