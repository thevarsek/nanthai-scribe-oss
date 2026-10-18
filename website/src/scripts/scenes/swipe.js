export default function swipe(root) {
    const kb = root.querySelector(".sw-kb"), finger = root.querySelector(".sw-finger"), path = root.querySelector(".sw-trail path"), strip = root.querySelectorAll(".sw-strip span"), typed = root.querySelector(".sw-field .sc-typed");
    const wordsList = [["hello", ["hell", "hello", "hallo"]], ["there", ["three", "there", "the"]]];
    let raf = 0, idx = 0, delay = 0, tail = 0;
    const keyPos = (ch) => { const k = kb.querySelector(`.sw-key[data-k="${ch}"]`); return [k.offsetLeft + k.offsetWidth / 2, k.offsetTop + k.offsetHeight / 2 + k.offsetParent.offsetTop - kb.offsetTop]; };
    const reset = () => { cancelAnimationFrame(raf); clearTimeout(delay); clearTimeout(tail); finger.classList.remove("show"); path.setAttribute("d", ""); strip.forEach(s => s.textContent = ""); typed.textContent = "Say "; kb.querySelectorAll(".lit").forEach(k => k.classList.remove("lit")); };
    function run(word, alts, done) {
      const pts = [...word].map(keyPos); const seg = 420; const total = seg * (pts.length - 1); const start = performance.now(); const hist = [];
      finger.classList.add("show");
      function frame(now) {
        const t = Math.min(total, now - start); const i = Math.min(pts.length - 2, Math.floor(t / seg)); const f = (t - i * seg) / seg; const e = f < .5 ? 2 * f * f : -1 + (4 - 2 * f) * f;
        const x = pts[i][0] + (pts[i + 1][0] - pts[i][0]) * e, y = pts[i][1] + (pts[i + 1][1] - pts[i][1]) * e;
        finger.style.left = x + "px"; finger.style.top = y + "px"; hist.push([now, x, y]);
        while (hist.length && now - hist[0][0] > 320) hist.shift();
        path.setAttribute("d", hist.map((p, k) => (k ? "L" : "M") + p[1].toFixed(1) + " " + p[2].toFixed(1)).join(" "));
        kb.querySelectorAll(".lit").forEach(k => k.classList.remove("lit")); kb.querySelector(`.sw-key[data-k="${word[Math.round(i + e)]}"]`)?.classList.add("lit");
        if (t < total) raf = requestAnimationFrame(frame); else { finger.classList.remove("show"); tail = setTimeout(() => path.setAttribute("d", ""), 250); kb.querySelectorAll(".lit").forEach(k => k.classList.remove("lit")); strip.forEach((s, k) => s.textContent = alts[k]); typed.textContent += word + " "; done && done(); }
      }
      raf = requestAnimationFrame(frame);
    }
    let on = false;
    function loop() { if (!on) return; reset(); const [w, a] = wordsList[idx % wordsList.length]; idx++; delay = setTimeout(() => on && run(w, a, () => { delay = setTimeout(loop, 4000); }), 900); }
    const final = () => { reset(); const pts = [..."hello"].map(keyPos); path.setAttribute("d", pts.map((p, k) => (k ? "L" : "M") + p[0] + " " + p[1]).join(" ")); strip.forEach((s, k) => s.textContent = ["hell", "hello", "hallo"][k]); typed.textContent = "Say hello "; };
    return { tl: { start() { if (on) return; on = true; loop(); }, stop() { on = false; cancelAnimationFrame(raf); clearTimeout(delay); clearTimeout(tail); } }, final };
  }

