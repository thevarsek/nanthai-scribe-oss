import { timeline, clearEl } from "./timeline.js";
// One sentence, four tones; the app in the title bar changes with the tone (Style by app).
const tones = [
  ["natural", "Notes", "Can we move the launch to the 3rd? We need the extra week."],
  ["casual", "Messages", "Can we push the launch to the 3rd? Need an extra week."],
  ["formal", "Mail", "Could we move the launch to 3 November? We would need an additional week."],
  ["code", "Xcode", "launchDate = \"2026-11-03\" // needs the extra week"],
];
export default function tonesScene(root) {
    const text = root.querySelector(".tn-text"), app = root.querySelector(".tn-app"), chips = root.querySelectorAll(".tn-chips .sc-chip");
    const set = (i) => {
      const [tone, name, sentence] = tones[i];
      root.dataset.tone = tone; app.textContent = name; chips.forEach(c => c.classList.toggle("on", c.dataset.tone === tone));
      clearEl(text);
      sentence.split(" ").forEach((p, k) => { const s = document.createElement("span"); s.className = "w"; s.style.animationDelay = (k * 35) + "ms"; s.textContent = (k ? " " : "") + p; text.appendChild(s); });
    };
    const steps = tones.map((_, i) => [i * 2600, () => set(i)]);
    return { tl: timeline(steps, tones.length * 2600), final: () => set(2) };
  }
