import { timeline } from "./timeline.js";
// Three ways to start: a lone modifier, a combination, a pedal on F13. Each opens the bar.
export default function shortcut(root) {
    const keys = root.querySelectorAll(".sh-keys .sc-key"), pedal = root.querySelector(".sh-pedal"), hud = root.querySelector(".sh-hud"), wave = root.querySelector(".sh-hud .sc-wave"), live = root.querySelector(".sc-live");
    const release = () => { keys.forEach(k => k.classList.remove("down")); pedal.classList.remove("down"); hud.classList.remove("show"); wave.classList.remove("on"); };
    const press = (i) => { keys[i].classList.add("down"); if (keys[i].dataset.k === "f13") pedal.classList.add("down"); hud.classList.add("show"); wave.classList.add("on"); live.textContent = "Listening…"; };
    const final = () => { release(); keys[0].classList.add("down"); hud.classList.add("show"); };
    const steps = [[0, release]];
    keys.forEach((_, i) => { steps.push([400 + i * 2700, () => press(i)]); steps.push([400 + i * 2700 + 1900, release]); });
    return { tl: timeline(steps, 400 + keys.length * 2700), final };
  }
