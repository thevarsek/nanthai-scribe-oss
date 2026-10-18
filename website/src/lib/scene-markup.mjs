// Scene markup shared by all options. Each returns a <div class="scene"> that scenes.js scales and animates.

export const trioSymbol = `<svg width="0" height="0" style="position:absolute" aria-hidden="true" focusable="false">
  <defs>
    <linearGradient id="ribbon" x1="0" y1="1" x2="0" y2="0">
      <stop offset="0" stop-color="#1EC8FF"/><stop offset="0.45" stop-color="#5EE0F6"/><stop offset="0.6" stop-color="#FFD94A"/><stop offset="1" stop-color="#FFA51F"/>
    </linearGradient>
    <symbol id="trio" viewBox="0 0 18 18">
      <g stroke-width="0.7" stroke-linejoin="round" paint-order="stroke">
        <polygon class="t1" points="3,6.84 5.2,4.99 5.2,11.16 3,13.01" fill="#F2F4F7" stroke="#F2F4F7"/>
        <polygon class="t2" points="7.9,3.09 10.1,1.24 10.1,14.91 7.9,16.76" fill="url(#ribbon)" stroke="url(#ribbon)"/>
        <polygon class="t3" points="12.8,5.34 15,3.49 15,12.66 12.8,14.51" fill="#FF7A59" stroke="#FF7A59"/>
      </g>
    </symbol>
    <symbol id="refine" viewBox="0 0 18 18">
      <path d="M11.2 2.9l3.9 3.9-7.6 7.6-4.6.7.7-4.6z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>
      <path d="M2.5 16.5c1.6-1.4 3-1.4 4.4 0s2.8 1.4 4.4 0 2.8-1.4 4.2 0" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>
    </symbol>
  </defs>
</svg>`;

export const trio = (cls = "trio", live = false) => `<svg class="${cls}${live ? " trio-live" : ""}" aria-hidden="true"><use href="#trio"/></svg>`;
export const refineGlyph = `<svg aria-hidden="true"><use href="#refine"/></svg>`;
const wave = (n = 7) => `<div class="sc-wave" aria-hidden="true">${"<i></i>".repeat(n)}</div>`;

export function sceneDictate(max = 1) {
  return `<div class="scene" data-w="640" data-h="400" data-max="${max}" role="img" aria-label="Animation: holding the right Option key in Mail shows a floating bar with the live words; adding Command turns Refine on; releasing types the cleaned sentence into the message.">
  <div class="sc sc-dictate" data-anim="dictate" aria-hidden="true">
    <div class="sc-win">
      <div class="sc-win-bar"><i></i><i></i><i></i><span>New message</span></div>
      <div class="sc-win-meta"><span>To:</span> Anna Ferri</div>
      <div class="sc-win-meta"><span>Subject:</span> Sales report</div>
      <div class="sc-win-body"><span class="sc-typed"></span><span class="sc-caret"></span></div>
    </div>
    <div class="sc-keys"><kbd class="sc-key sc-key-opt">⌥<small>option</small></kbd><kbd class="sc-key sc-key-cmd">⌘<small>command</small></kbd><span class="sc-key-hint">Hold right ⌥ and talk</span></div>
    <div class="sc-hud"><div class="sc-chips"><span class="sc-chip on">${refineGlyph} Refine</span></div><div class="sc-hud-row">${wave()}<p class="sc-live">Listening…</p></div></div>
  </div>
</div>`;
}

export function scenePhone(max = 1) {
  const row = (keys) => `<div class="kl-row">${keys.map(k => `<span class="kl-key" data-k="${k}">${k}</span>`).join("")}</div>`;
  return `<div class="scene scene-center" data-w="300" data-h="600" data-max="${max}" role="img" aria-label="Animation: on the Scribe keyboard you type the start of a message on the letters, tap Talk, say the rest, tap Done, and the whole sentence is inserted into the message.">
  <div class="sc sc-phone" data-anim="phone" aria-hidden="true">
    <div class="ph">
      <div class="ph-top">Messages</div>
      <div class="ph-chat"><div class="bubble in">Running late?</div><div class="bubble out show">On my way, there in ten minutes</div></div>
      <div class="ph-field"><span class="sc-typed"></span><span class="sc-caret"></span></div>
      <div class="kb" data-layer="letters">
        <div class="kb-layer kb-letters">
          <div class="kl-strip"><span>I</span><span class="mid">On</span><span>The</span></div>
          ${row([..."qwertyuiop"])}
          ${row([..."asdfghjkl"])}
          <div class="kl-row"><span class="kl-key wide sys">⇧</span>${[..."zxcvbnm"].map(k => `<span class="kl-key" data-k="${k}">${k}</span>`).join("")}<span class="kl-key wide sys">⌫</span></div>
          <div class="kl-row"><span class="kl-key wide sys">123</span><span class="kl-key scribe sys" data-k="scribe">${trio()}</span><span class="kl-key space sys" data-k=" ">space</span><span class="kl-key wide sys">return</span></div>
        </div>
        <div class="kb-layer kb-talk-layer">
          <div class="kb-row kb-top"><span class="kb-pill">${refineGlyph} Refine</span><span class="kb-timer"><i></i>0:04</span><span class="kb-key kb-abc">ABC</span></div>
          <div class="kb-mid"><p class="kb-live">Tap Talk. Your words appear here as you speak.</p></div>
          <div class="kb-row kb-bottom"><span class="kb-key">space</span><span class="kb-talk">${trio("trio", true)}<span class="busy"></span><span class="kb-talk-label">Talk</span></span><span class="kb-key">return</span></div>
        </div>
      </div>
      <div class="ph-tap"></div>
    </div>
    <p class="sc-caption show">Type as usual. Talk when it's quicker.</p>
  </div>
</div>`;
}

export function scenePrivacy(max = 1) {
  return `<div class="scene" data-w="640" data-h="360" data-max="${max}" role="img" aria-label="Diagram: the microphone audio turns into text inside the device; nothing travels to a server.">
  <div class="sc sc-privacy" data-anim="privacy" aria-hidden="true">
    <div class="pv-ring ring"></div>
    <div class="pv-device">
      <div class="pv-mic"></div>
      <div class="pv-wave">${wave(5)}</div>
      <div class="pv-path"></div><i class="pv-dot"></i><i class="pv-dot"></i><i class="pv-dot"></i>
      <div class="pv-text"><i></i><i></i><i></i><i></i></div>
      <span class="pv-io a">audio</span><span class="pv-io b">text</span>
      <p class="pv-label">Your Mac or iPhone</p>
    </div>
    <div class="pv-link"></div><div class="pv-x">×</div>
    <div class="pv-outside"><div class="pv-cloud"></div><p><strong>No server</strong>No account. No analytics.<br>Model downloads you start.<br>Mac update checks you choose.</p></div>
    <p class="pv-zero">Requests sent while dictating: 0</p>
  </div>
</div>`;
}

export function sceneMeeting(max = 1) {
  const src = (n) => `<div class="mt-src"><span>${n}</span>${wave(3)}</div>`;
  return `<div class="scene" data-w="640" data-h="420" data-max="${max}" role="img" aria-label="Animation: a meeting is recorded from the microphone and the call audio; after Stop, Scribe saves, transcribes, identifies speakers and summarises; the result is a transcript with You, Speaker 1 and Speaker 2, a summary and action items.">
  <div class="sc sc-meeting" data-anim="meeting" aria-hidden="true">
    <div class="mt-panel">
      <div class="mt-bar"><b>Meeting at 14:30</b><span>· today · Zoom</span><span class="mt-btn hot">Stop</span></div>
      <div class="mt-view mt-rec show">
        <div class="mt-time">12:04</div><div class="mt-state">● Recording</div>
        ${src("Microphone")}${src("Call audio")}
        <div class="mt-btns"><span>Pause</span><span class="primary">Stop</span></div>
      </div>
      <div class="mt-view mt-steps">
        <div class="mt-step"><i></i>Saving audio</div><div class="mt-step"><i></i>Transcribing</div><div class="mt-step"><i></i>Identifying speakers</div><div class="mt-step"><i></i>Summarising</div>
      </div>
      <div class="mt-view mt-result">
        <div class="mt-col">
          <h5>Summary</h5>
          <ul><li>Launch moves to 3 November.</li><li>Pricing stays as agreed in September.</li><li>Anna writes the press note.</li></ul>
          <h5>Action items</h5>
          <ul class="todo"><li>Anna: draft the press note by Friday</li><li>You: confirm the pricing page</li></ul>
        </div>
        <div class="mt-col">
          <h5>Transcript</h5>
          <div class="turn"><b class="you">You</b><time>00:12</time><p>Let's move the launch to the third, we need the extra week.</p></div>
          <div class="turn"><b class="s1">Speaker 1</b><time>00:21</time><p>Fine by me. Pricing doesn't change?</p></div>
          <div class="turn"><b class="you">You</b><time>00:26</time><p>No, same as September.</p></div>
          <div class="turn"><b class="s2">Speaker 2</b><time>00:30</time><p>I'll draft the press note by Friday.</p></div>
        </div>
      </div>
    </div>
  </div>
</div>`;
}

export function sceneSwipe(max = 1) {
  const row = (keys, cls = "") => `<div class="sw-row">${keys.map(k => `<span class="sw-key${cls}" data-k="${k}">${k}</span>`).join("")}</div>`;
  return `<div class="scene scene-center" data-w="360" data-h="320" data-max="${max}" role="img" aria-label="Animation: a finger slides across the letters h, e, l, l, o without lifting; the word hello is inserted and two alternatives appear in the suggestion bar.">
  <div class="sc sc-swipe" data-anim="swipe" aria-hidden="true">
    <div class="sw-field"><span class="sc-typed">Say </span><span class="sc-caret"></span></div>
    <div class="sw-kb">
      <div class="sw-strip"><span></span><span class="mid"></span><span></span></div>
      ${row([..."qwertyuiop"])}
      ${row([..."asdfghjkl"])}
      <div class="sw-row"><span class="sw-key wide sys">⇧</span>${[..."zxcvbnm"].map(k => `<span class="sw-key" data-k="${k}">${k}</span>`).join("")}<span class="sw-key wide sys">⌫</span></div>
      <div class="sw-row"><span class="sw-key wide sys">123</span><span class="sw-key wide sys">${trio()}</span><span class="sw-key space sys">space</span><span class="sw-key wide sys">return</span></div>
      <svg class="sw-trail" aria-hidden="true"><path d=""/></svg>
      <div class="sw-finger"></div>
    </div>
  </div>
</div>`;
}

/* Feature callouts. Each drawing is rendered in its finished state; the timeline resets it. */
export function sceneTones(max = 1) {
  return `<div class="scene" data-w="560" data-h="300" data-max="${max}" role="img" aria-label="Animation: the same spoken sentence rewritten as the tone changes with the app: Natural in Notes, Casual in Messages, Formal in Mail, Code in Xcode.">
  <div class="sc sc-tones" data-anim="tones" data-tone="formal" aria-hidden="true">
    <div class="tn-win">
      <div class="tn-bar"><i></i><i></i><i></i><span class="tn-app">Mail</span></div>
      <p class="tn-said">“um can we move the launch to the third, we need the extra week”</p>
      <p class="tn-text">Could we move the launch to 3 November? We would need an additional week.</p>
    </div>
    <div class="tn-chips"><span class="sc-chip" data-tone="natural">Natural</span><span class="sc-chip" data-tone="casual">Casual</span><span class="sc-chip on" data-tone="formal">Formal</span><span class="sc-chip" data-tone="code">Code</span></div>
  </div>
</div>`;
}

export function sceneLearn(max = 1) {
  return `<div class="scene" data-w="560" data-h="300" data-max="${max}" role="img" aria-label="Animation: Scribe hears Nantai, you correct it to NanthAi, Scribe asks once whether to always spell it that way, and the word lands in your Dictionary marked Learned.">
  <div class="sc sc-learn" data-anim="learn" aria-hidden="true">
    <div class="ln-doc"><p>Meet the <span class="ln-word">NanthAi</span> team on Monday.</p></div>
    <div class="ln-prompt"><span>Always spell “Nantai” as “NanthAi”?</span><span class="ln-btn add">Add</span><span class="ln-btn">Not now</span></div>
    <div class="ln-dict"><div class="ln-dict-head">Dictionary</div><div class="ln-row show"><b>NanthAi</b><span>Heard as Nantai</span><em>Learned</em></div></div>
    <div class="ph-tap"></div>
  </div>
</div>`;
}

export function sceneTranscribe(max = 1) {
  const step = (t) => `<div class="mt-step"><i></i>${t}</div>`;
  return `<div class="scene" data-w="560" data-h="300" data-max="${max}" role="img" aria-label="Animation: an audio file is dropped onto the Library; Scribe saves, transcribes, identifies speakers and summarises it, and a new meeting appears in the list.">
  <div class="sc sc-transcribe" data-anim="transcribe" aria-hidden="true">
    <div class="tr-file dropped"><span class="tr-icon">${wave(4)}</span><b>interview.m4a</b><span>23:14</span></div>
    <div class="tr-lib">
      <div class="tr-head"><b>Library</b><span>Meetings</span></div>
      <div class="tr-steps">${step("Saving audio")}${step("Transcribing")}${step("Identifying speakers")}${step("Summarising")}</div>
      <div class="tr-rows">
        <div class="tr-row new show"><b>interview</b><span>23:14 · You, Speaker 1 · summary and 3 action items</span></div>
        <div class="tr-row"><b>Meeting at 14:30</b><span>41:02 · Zoom</span></div>
        <div class="tr-row"><b>Standup</b><span>12:40 · in person</span></div>
      </div>
    </div>
  </div>
</div>`;
}

export function sceneShortcut(max = 1) {
  return `<div class="scene" data-w="560" data-h="300" data-max="${max}" role="img" aria-label="Animation: three ways to start a dictation on the Mac, each pressed in turn: the right Option key, a key combination, and a foot pedal sending F13. Each one opens the listening bar.">
  <div class="sc sc-shortcut" data-anim="shortcut" aria-hidden="true">
    <div class="sh-keys"><kbd class="sc-key down" data-k="opt">⌥<small>right option</small></kbd><kbd class="sc-key sh-combo" data-k="combo">⌃⌥␣<small>combination</small></kbd><kbd class="sc-key" data-k="f13">F13<small>pedal</small></kbd></div>
    <div class="sh-cable"></div><div class="sh-pedal"></div>
    <div class="sh-hud show"><div class="sc-hud-row">${wave()}<p class="sc-live">Listening…</p></div></div>
  </div>
</div>`;
}
