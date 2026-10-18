export function timeline(steps, loop) {
    let timers = [], on = false;
    const clear = () => { timers.forEach(clearTimeout); timers = []; };
    const cycle = () => { steps.forEach(([t, fn]) => timers.push(setTimeout(fn, t))); timers.push(setTimeout(() => { clear(); if (on) cycle(); }, loop)); };
    return { start() { if (on) return; on = true; cycle(); }, stop() { on = false; clear(); } };
  }
export function clearEl(el) { el.textContent = ""; }

