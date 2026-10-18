import { timeline, clearEl } from "./timeline.js";
// Type the start of a message on the letters, then tap Talk for the rest.
export default function phone(root) {
    const kb = root.querySelector(".kb"), talk = root.querySelector(".kb-talk"), label = root.querySelector(".kb-talk-label"), live = root.querySelector(".kb-live");
    const tap = root.querySelector(".ph-tap"), typed = root.querySelector(".ph-field .sc-typed"), caption = root.querySelector(".sc-caption"), bubble = root.querySelector(".bubble.out"), strip = root.querySelector(".kl-strip .mid");
    const typedPart = "On my way,", spoken = "there in ten minutes", full = typedPart + " " + spoken;
    const tapAt = (el) => { const r = el.getBoundingClientRect(), p = root.getBoundingClientRect(); const s = r.width / el.offsetWidth; tap.style.left = ((r.left - p.left) / s + el.offsetWidth / 2) + "px"; tap.style.top = ((r.top - p.top) / s + el.offsetHeight / 2) + "px"; tap.classList.remove("go"); void tap.offsetWidth; tap.classList.add("go"); };
    const key = (ch) => kb.querySelector(`.kl-key[data-k="${ch.toLowerCase()}"]`);
    const idle = () => { live.className = "kb-live"; live.textContent = "Tap Talk. Your words appear here as you speak."; };
    const reset = () => { root.classList.remove("on"); kb.dataset.layer = "letters"; talk.classList.remove("busy-on", "ring"); label.textContent = "Talk"; idle(); clearEl(typed); caption.classList.remove("show"); bubble.classList.remove("show"); strip.textContent = "On"; kb.querySelectorAll(".lit").forEach(k => k.classList.remove("lit")); };
    const final = () => { reset(); bubble.textContent = full; bubble.classList.add("show"); caption.classList.add("show"); };
    const steps = [[0, reset]];
    // Letters first: each character is a tap on its key.
    [...typedPart].forEach((ch, i) => steps.push([500 + i * 170, () => {
      const k = key(ch === "," ? "m" : ch); if (k) { tapAt(k); k.classList.add("lit"); setTimeout(() => k.classList.remove("lit"), 140); }
      typed.textContent += ch; strip.textContent = ch === " " ? "my" : typedPart.slice(0, i + 1).split(" ").pop();
    }]));
    const t = 500 + typedPart.length * 170 + 500;
    steps.push([t, () => tapAt(key("scribe"))]);
    steps.push([t + 250, () => { kb.dataset.layer = "talk"; }]);
    steps.push([t + 900, () => tapAt(talk)]);
    steps.push([t + 1100, () => { talk.classList.add("ring"); root.classList.add("on"); label.textContent = "Done"; live.className = "kb-live words"; clearEl(live); }]);
    spoken.split(" ").forEach((p, i) => steps.push([t + 1400 + i * 260, () => { const s = document.createElement("span"); s.className = "w"; s.textContent = (i ? " " : "") + p; live.appendChild(s); }]));
    const d = t + 1400 + spoken.split(" ").length * 260 + 700;
    steps.push([d, () => tapAt(talk)]);
    steps.push([d + 200, () => { talk.classList.remove("ring"); talk.classList.add("busy-on"); root.classList.remove("on"); label.textContent = "Finishing…"; }]);
    steps.push([d + 900, () => { talk.classList.remove("busy-on"); label.textContent = "Talk"; idle(); typed.textContent = full; }]);
    steps.push([d + 1800, () => { bubble.textContent = full; bubble.classList.add("show"); clearEl(typed); kb.dataset.layer = "letters"; }]);
    steps.push([d + 2000, () => caption.classList.add("show")]);
    return { tl: timeline(steps, 14500), final };
  }
